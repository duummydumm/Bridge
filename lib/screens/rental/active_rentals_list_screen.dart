import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/firestore_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/rental_request_provider.dart';
import 'package:provider/provider.dart';
import 'active_rental_detail_screen.dart';

class ActiveRentalsListScreen extends StatefulWidget {
  final bool?
  asOwner; // null = auto-detect, true = owner view, false = renter view

  const ActiveRentalsListScreen({super.key, this.asOwner});

  @override
  State<ActiveRentalsListScreen> createState() =>
      _ActiveRentalsListScreenState();
}

class _ActiveRentalsListScreenState extends State<ActiveRentalsListScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  List<Map<String, dynamic>> _activeRentals = [];
  bool _isLoading = true;
  bool _viewingAsOwner = false; // Track which view we're showing

  @override
  void initState() {
    super.initState();
    _loadActiveRentals();
  }

  Future<void> _loadActiveRentals() async {
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

      // Determine which view to show
      bool showAsOwner = widget.asOwner ?? false; // Default to renter view

      // If auto-detect (null), check which has more active rentals
      if (widget.asOwner == null) {
        final ownerRentals = await _firestoreService.getRentalRequestsByUser(
          userId,
          asOwner: true,
        );
        final renterRentals = await _firestoreService.getRentalRequestsByUser(
          userId,
          asOwner: false,
        );

        final activeOwnerRentals = ownerRentals.where((req) {
          final status = (req['status'] ?? 'requested')
              .toString()
              .toLowerCase();
          return status == 'ownerapproved' ||
              status == 'active' ||
              status == 'returninitiated';
        }).length;

        final activeRenterRentals = renterRentals.where((req) {
          final status = (req['status'] ?? 'requested')
              .toString()
              .toLowerCase();
          return status == 'ownerapproved' ||
              status == 'active' ||
              status == 'returninitiated';
        }).length;

        // Show owner view if they have more active rentals as owner
        showAsOwner = activeOwnerRentals > activeRenterRentals;
      }

      final rentRequests = await _firestoreService.getRentalRequestsByUser(
        userId,
        asOwner: showAsOwner,
      );

      // Filter for active rentals
      final activeRentals = rentRequests.where((req) {
        final status = (req['status'] ?? 'requested').toString().toLowerCase();
        return status == 'ownerapproved' ||
            status == 'active' ||
            status == 'returninitiated';
      }).toList();

      // Enrich rental data with item title and names
      final enrichedRentals = <Map<String, dynamic>>[];
      for (final rental in activeRentals) {
        final enrichedRental = Map<String, dynamic>.from(rental);

        // Get item title from listing
        final listingId = rental['listingId'] as String?;
        if (listingId != null) {
          try {
            final listing = await _firestoreService.getRentalListing(listingId);
            if (listing != null) {
              enrichedRental['itemTitle'] = listing['title'] as String?;
              // Fallback to item title if listing title not available
              if (enrichedRental['itemTitle'] == null ||
                  (enrichedRental['itemTitle'] as String).isEmpty) {
                final itemId = rental['itemId'] as String?;
                if (itemId != null) {
                  final item = await _firestoreService.getItem(itemId);
                  enrichedRental['itemTitle'] = item?['title'] as String?;
                }
              }
            }
          } catch (_) {
            // Continue if listing fetch fails
          }
        }
        enrichedRental['itemTitle'] ??= 'Rental Item';

        // Get names based on view
        if (showAsOwner) {
          // When viewing as owner, show renter name
          final renterId = rental['renterId'] as String?;
          if (renterId != null) {
            try {
              final renter = await _firestoreService.getUser(renterId);
              if (renter != null) {
                final firstName = renter['firstName'] ?? '';
                final lastName = renter['lastName'] ?? '';
                enrichedRental['renterName'] = '$firstName $lastName'.trim();
              }
            } catch (_) {
              // Continue if user fetch fails
            }
          }
          enrichedRental['renterName'] ??= 'Renter';
        } else {
          // When viewing as renter, show owner name
          final ownerId = rental['ownerId'] as String?;
          if (ownerId != null) {
            try {
              final owner = await _firestoreService.getUser(ownerId);
              if (owner != null) {
                final firstName = owner['firstName'] ?? '';
                final lastName = owner['lastName'] ?? '';
                enrichedRental['ownerName'] = '$firstName $lastName'.trim();
              }
            } catch (_) {
              // Continue if user fetch fails
            }
          }
          enrichedRental['ownerName'] ??= 'Owner';
        }

        enrichedRentals.add(enrichedRental);
      }

      // Sort by createdAt descending (most recent first)
      enrichedRentals.sort((a, b) {
        final aDate =
            (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime(1970);
        final bDate =
            (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime(1970);
        return bDate.compareTo(aDate);
      });

      if (mounted) {
        setState(() {
          _activeRentals = enrichedRentals;
          _viewingAsOwner = showAsOwner;
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
            content: Text('Error loading active rentals: $e'),
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

  String _formatCurrency(double? amount) {
    if (amount == null) return '₱0.00';
    return '₱${amount.toStringAsFixed(2)}';
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

  Future<void> _initiateReturn(String requestId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Initiate Return?'),
        content: const Text(
          'Are you sure you want to initiate the return? '
          'The owner will be notified to verify the return.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Initiate Return'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
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

      final success = await reqProvider.initiateReturn(
        requestId,
        currentUser.uid,
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Return initiated successfully! Owner will verify.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
          // Reload list to show updated status
          _loadActiveRentals();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                reqProvider.errorMessage ?? 'Failed to initiate return',
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

  Future<void> _verifyReturn(String requestId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as Returned?'),
        content: const Text(
          'Have you received the item in good condition? '
          'This will complete the rental.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: const Text('Mark as Returned'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
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

      final success = await reqProvider.verifyReturn(
        requestId,
        currentUser.uid,
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Return verified! Rental completed.'),
              backgroundColor: Colors.green,
            ),
          );
          // Reload list to show updated status
          _loadActiveRentals();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                reqProvider.errorMessage ?? 'Failed to verify return',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_viewingAsOwner ? 'My Rentals' : 'Active Rentals'),
        backgroundColor: const Color(0xFF00897B),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _activeRentals.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              onRefresh: _loadActiveRentals,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _activeRentals.length,
                itemBuilder: (context, index) {
                  return _buildRentalCard(_activeRentals[index]);
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
          Icon(Icons.home_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            _viewingAsOwner ? 'No Active Rentals' : 'No Active Rentals',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _viewingAsOwner
                ? 'Items you\'ve rented out will appear here'
                : 'Your active rentals will appear here',
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildRentalCard(Map<String, dynamic> rental) {
    final itemTitle = (rental['itemTitle'] ?? 'Rental Item').toString();
    final ownerName = (rental['ownerName'] ?? 'Owner').toString();
    final renterName = (rental['renterName'] ?? 'Renter').toString();
    final status = (rental['status'] ?? 'active').toString().toLowerCase();
    final startDate =
        (rental['startDate'] as Timestamp?)?.toDate() ?? DateTime.now();
    final endDate = (rental['endDate'] as Timestamp?)?.toDate();
    final monthlyAmount = (rental['monthlyPaymentAmount'] as num?)?.toDouble();
    final isLongTerm = rental['isLongTerm'] as bool? ?? false;
    final nextPaymentDue = (rental['nextPaymentDueDate'] as Timestamp?)
        ?.toDate();
    final requestId = rental['id'] as String? ?? '';

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
              _loadActiveRentals();
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
                      color: const Color(0xFF00897B).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.home_outlined,
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
                          itemTitle,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _getStatusColor(status).withOpacity(0.1),
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
              // Person info (Owner when viewing as renter, Renter when viewing as owner)
              Row(
                children: [
                  Icon(Icons.person, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _viewingAsOwner
                          ? 'Rented by: $renterName'
                          : 'Owner: $ownerName',
                      style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
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
              if (endDate != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.event, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ends: ${_formatDate(endDate)}',
                        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                      ),
                    ),
                  ],
                ),
              ] else if (isLongTerm) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.event, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Month-to-month (Ongoing)',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[700],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
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
                              _formatCurrency(monthlyAmount),
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
              // Return button only for renters (not owners)
              // Owners verify returns, renters initiate them
              if (!_viewingAsOwner &&
                  (status.toLowerCase() == 'active' ||
                      status.toLowerCase() == 'ownerapproved')) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _initiateReturn(requestId),
                    icon: const Icon(Icons.assignment_return, size: 18),
                    label: const Text('Initiate Return'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
              // Mark as Returned button for owners when return is initiated
              if (_viewingAsOwner &&
                  status.toLowerCase() == 'returninitiated') ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _verifyReturn(requestId),
                    icon: const Icon(Icons.check_circle, size: 18),
                    label: const Text('Mark as Returned'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
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
}
