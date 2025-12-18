import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/firestore_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/rental_request_provider.dart';
import 'package:provider/provider.dart';
import 'active_rental_detail_screen.dart';

class BoardingHouseRentersScreen extends StatefulWidget {
  final String listingId;
  final String itemTitle;

  const BoardingHouseRentersScreen({
    super.key,
    required this.listingId,
    required this.itemTitle,
  });

  @override
  State<BoardingHouseRentersScreen> createState() =>
      _BoardingHouseRentersScreenState();
}

class _BoardingHouseRentersScreenState
    extends State<BoardingHouseRentersScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  List<Map<String, dynamic>> _renters = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRenters();
  }

  Future<void> _loadRenters() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.user?.uid;

      if (userId == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      // Get all active rentals for this boarding house listing
      // Query directly by listingId to get all renters for this boarding house
      final db = FirebaseFirestore.instance;
      final rentalsSnapshot = await db
          .collection('rental_requests')
          .where('listingId', isEqualTo: widget.listingId)
          .where('ownerId', isEqualTo: userId)
          .where(
            'status',
            whereIn: ['ownerapproved', 'active', 'returninitiated'],
          )
          .get();

      final boardingHouseRentals = rentalsSnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      // Enrich with renter information
      final enrichedRenters = <Map<String, dynamic>>[];
      for (final rental in boardingHouseRentals) {
        final enrichedRental = Map<String, dynamic>.from(rental);
        final renterId = rental['renterId'] as String?;

        if (renterId != null) {
          try {
            final renter = await _firestoreService.getUser(renterId);
            if (renter != null) {
              final firstName = renter['firstName'] ?? '';
              final lastName = renter['lastName'] ?? '';
              enrichedRental['renterName'] = '$firstName $lastName'.trim();
              enrichedRental['renterEmail'] = renter['email'] ?? '';
            }
          } catch (_) {
            // Continue if user fetch fails
          }
        }
        enrichedRental['renterName'] ??= 'Renter';

        // Get rent type from listing for proper dialog messages
        final listingId = rental['listingId'] as String?;
        if (listingId != null) {
          try {
            final listing = await _firestoreService.getRentalListing(listingId);
            if (listing != null) {
              enrichedRental['rentType'] =
                  listing['rentType'] as String? ?? 'item';
            }
          } catch (_) {
            // Continue if listing fetch fails
          }
        }
        enrichedRental['rentType'] ??= 'item';

        enrichedRenters.add(enrichedRental);
      }

      // Sort by start date (most recent first)
      enrichedRenters.sort((a, b) {
        final aDate =
            (a['startDate'] as Timestamp?)?.toDate() ?? DateTime(1970);
        final bDate =
            (b['startDate'] as Timestamp?)?.toDate() ?? DateTime(1970);
        return bDate.compareTo(aDate);
      });

      if (mounted) {
        setState(() {
          _renters = enrichedRenters;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading renters: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day.toString().padLeft(2, '0')}, ${date.year}';
  }

  String _getStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'ownerapproved':
        return 'Approved';
      case 'active':
        return 'Active';
      case 'returninitiated':
        return 'Return Initiated';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'ownerapproved':
        return Colors.blue;
      case 'active':
        return Colors.green;
      case 'returninitiated':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.itemTitle),
        backgroundColor: const Color(0xFF00897B),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _renters.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              onRefresh: _loadRenters,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _renters.length,
                itemBuilder: (context, index) {
                  return _buildRenterCard(_renters[index]);
                },
              ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text(
            'No Active Renters',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No active renters for this boarding house',
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildRenterCard(Map<String, dynamic> rental) {
    final renterName = (rental['renterName'] ?? 'Renter').toString();
    final status = (rental['status'] ?? 'active').toString().toLowerCase();
    final startDate =
        (rental['startDate'] as Timestamp?)?.toDate() ?? DateTime.now();
    final requestId = rental['id'] as String? ?? '';
    final monthlyAmount = (rental['monthlyPaymentAmount'] as num?)?.toDouble();
    final isLongTerm = rental['isLongTerm'] as bool? ?? false;
    final nextPaymentDue = (rental['nextPaymentDueDate'] as Timestamp?)
        ?.toDate();

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () {
          if (requestId.isNotEmpty) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    ActiveRentalDetailScreen(requestId: requestId),
              ),
            ).then((_) {
              // Reload when returning from detail screen
              _loadRenters();
            });
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00897B).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.person,
                      color: Color(0xFF00897B),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          renterName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _getStatusColor(
                              status,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _getStatusLabel(status),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _getStatusColor(status),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Started: ${_formatDate(startDate)}',
                      style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                    ),
                  ),
                ],
              ),
              if (isLongTerm && monthlyAmount != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.attach_money,
                        size: 18,
                        color: Colors.blue[700],
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Monthly Payment',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                            Text(
                              '₱${monthlyAmount.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[900],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (nextPaymentDue != null) ...[
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Next Due',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                            Text(
                              _formatDate(nextPaymentDue),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: nextPaymentDue.isBefore(DateTime.now())
                                    ? Colors.red[700]
                                    : Colors.blue[900],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              // Force-terminate button for owners on active/approved rentals
              if (status.toLowerCase() == 'active' ||
                  status.toLowerCase() == 'ownerapproved') ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _ownerTerminateRental(requestId, rental),
                    icon: const Icon(Icons.warning_amber_rounded, size: 18),
                    label: const Text('Force End Rental'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _getOwnerTerminateDialogTitle(Map<String, dynamic> rental) {
    final rentType = (rental['rentType'] as String? ?? 'item').toLowerCase();
    switch (rentType) {
      case 'apartment':
        return 'Force End Rental?';
      case 'boardinghouse':
      case 'boarding_house':
        return 'Force Move Out?';
      case 'commercial':
        return 'Force End Lease?';
      default:
        return 'End Rental?';
    }
  }

  String _getOwnerTerminateDialogMessage(Map<String, dynamic> rental) {
    final rentType = (rental['rentType'] as String? ?? 'item').toLowerCase();
    switch (rentType) {
      case 'apartment':
        return 'Are you sure you want to forcibly end this apartment rental? '
            'This should only be used for serious issues like non-payment or violations.';
      case 'boardinghouse':
      case 'boarding_house':
        return 'Are you sure you want to forcibly move this renter out? '
            'This should only be used for serious issues like non-payment or violations.';
      case 'commercial':
        return 'Are you sure you want to forcibly end this lease? '
            'This should only be used for serious issues like non-payment or violations.';
      default:
        return 'Are you sure you want to end this rental? '
            'This should only be used for serious issues like non-payment or violations.';
    }
  }

  String _getOwnerTerminateSuccessMessage(Map<String, dynamic> rental) {
    final rentType = (rental['rentType'] as String? ?? 'item').toLowerCase();
    switch (rentType) {
      case 'apartment':
        return 'Apartment rental has been terminated.';
      case 'boardinghouse':
      case 'boarding_house':
        return 'Boarding house rental has been terminated.';
      case 'commercial':
        return 'Commercial lease has been terminated.';
      default:
        return 'Rental has been terminated.';
    }
  }

  Future<void> _ownerTerminateRental(
    String requestId,
    Map<String, dynamic> rental,
  ) async {
    final TextEditingController reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_getOwnerTerminateDialogTitle(rental)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_getOwnerTerminateDialogMessage(rental)),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'e.g., Non-payment, repeated violations',
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Force End Rental'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      if (!mounted) return;
      final reqProvider = Provider.of<RentalRequestProvider>(
        context,
        listen: false,
      );
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.user;

      if (currentUser == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You must be logged in'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final success = await reqProvider.ownerTerminateRental(
        requestId,
        currentUser.uid,
        reason: reasonController.text.trim().isEmpty
            ? null
            : reasonController.text.trim(),
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_getOwnerTerminateSuccessMessage(rental)),
              backgroundColor: Colors.redAccent,
            ),
          );
          _loadRenters();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                reqProvider.errorMessage ?? 'Failed to terminate rental',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
