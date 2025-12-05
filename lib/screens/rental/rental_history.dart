import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/firestore_service.dart';
import '../../services/rating_service.dart';
import '../../providers/auth_provider.dart';
import '../../models/rating_model.dart';
import '../../models/rental_request_model.dart';
import 'package:provider/provider.dart';
import 'active_rental_detail_screen.dart';
import '../../reusable_widgets/bottom_nav_bar_widget.dart';
import '../submit_rating_screen.dart';

class RentalHistoryScreen extends StatefulWidget {
  final bool?
  asOwner; // null = auto-detect, true = owner view, false = renter view

  const RentalHistoryScreen({super.key, this.asOwner});

  @override
  State<RentalHistoryScreen> createState() => _RentalHistoryScreenState();
}

class _RentalHistoryScreenState extends State<RentalHistoryScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final RatingService _ratingService = RatingService();
  List<Map<String, dynamic>> _historyRentals = [];
  bool _isLoading = true;
  bool _viewingAsOwner = false; // Track which view we're showing
  String _selectedFilter = 'all'; // 'all', 'returned', 'cancelled', 'disputed'

  @override
  void initState() {
    super.initState();
    // Initialize _viewingAsOwner based on widget.asOwner if explicitly set
    if (widget.asOwner != null) {
      _viewingAsOwner = widget.asOwner!;
    }
    _loadRentalHistory();
  }

  Future<void> _loadRentalHistory() async {
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
      bool showAsOwner;

      if (widget.asOwner == null) {
        // Auto-detect mode: use current _viewingAsOwner state (can be toggled)
        // On first load (when _viewingAsOwner is still false), determine which has more history rentals
        if (!_viewingAsOwner && _historyRentals.isEmpty) {
          final ownerRentals = await _firestoreService.getRentalRequestsByUser(
            userId,
            asOwner: true,
          );
          final renterRentals = await _firestoreService.getRentalRequestsByUser(
            userId,
            asOwner: false,
          );

          final historyOwnerRentals = ownerRentals.where((req) {
            final status = (req['status'] ?? 'requested')
                .toString()
                .toLowerCase();
            return status == 'returned' ||
                status == 'cancelled' ||
                status == 'disputed';
          }).length;

          final historyRenterRentals = renterRentals.where((req) {
            final status = (req['status'] ?? 'requested')
                .toString()
                .toLowerCase();
            return status == 'returned' ||
                status == 'cancelled' ||
                status == 'disputed';
          }).length;

          // Show owner view if they have more history rentals as owner
          showAsOwner = historyOwnerRentals > historyRenterRentals;
        } else {
          // Use current toggle state
          showAsOwner = _viewingAsOwner;
        }
      } else {
        // Explicit mode: use current toggle state (which was initialized from widget.asOwner)
        showAsOwner = _viewingAsOwner;
      }

      final rentRequests = await _firestoreService.getRentalRequestsByUser(
        userId,
        asOwner: showAsOwner,
      );

      // Filter for history rentals (returned, cancelled, disputed)
      var historyRentals = rentRequests.where((req) {
        final status = (req['status'] ?? 'requested').toString().toLowerCase();
        return status == 'returned' ||
            status == 'cancelled' ||
            status == 'disputed';
      }).toList();

      // Apply status filter
      if (_selectedFilter != 'all') {
        historyRentals = historyRentals.where((req) {
          final status = (req['status'] ?? 'requested')
              .toString()
              .toLowerCase();
          return status == _selectedFilter;
        }).toList();
      }

      // Enrich rental data with item title and names
      final enrichedRentals = <Map<String, dynamic>>[];
      for (final rental in historyRentals) {
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

        // Check if user has already rated this rental (only for returned status)
        final rentalStatus = (rental['status'] ?? 'returned')
            .toString()
            .toLowerCase();
        if (rentalStatus == 'returned') {
          final requestId = rental['id'] as String? ?? '';
          if (requestId.isNotEmpty) {
            try {
              final isOwner = showAsOwner;
              final otherUserId = isOwner
                  ? (rental['renterId'] as String? ?? '')
                  : (rental['ownerId'] as String? ?? '');

              if (otherUserId.isNotEmpty) {
                final hasRated = await _firestoreService.hasExistingRating(
                  raterUserId: userId,
                  ratedUserId: otherUserId,
                  transactionId: requestId,
                );
                enrichedRental['hasRated'] = hasRated;
                enrichedRental['otherUserId'] = otherUserId;
              }
            } catch (_) {
              // Continue if rating check fails
              enrichedRental['hasRated'] = false;
            }
          }
        } else {
          enrichedRental['hasRated'] = false;
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
          _historyRentals = enrichedRentals;
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
            content: Text('Error loading rental history: $e'),
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
      case 'returned':
        return 'Returned';
      case 'cancelled':
        return 'Cancelled';
      case 'disputed':
        return 'Disputed';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'returned':
        return Colors.green;
      case 'cancelled':
        return Colors.orange;
      case 'disputed':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'returned':
        return Icons.check_circle_outline;
      case 'cancelled':
        return Icons.cancel_outlined;
      case 'disputed':
        return Icons.warning_outlined;
      default:
        return Icons.info_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          _viewingAsOwner ? 'Rental History (Owner)' : 'Rental History',
        ),
        backgroundColor: const Color(0xFF00897B),
        foregroundColor: Colors.white,
        actions: [
          // Toggle view button
          IconButton(
            icon: Icon(
              _viewingAsOwner ? Icons.person_outline : Icons.store_outlined,
            ),
            tooltip: _viewingAsOwner ? 'View as Renter' : 'View as Owner',
            onPressed: () {
              setState(() {
                _viewingAsOwner = !_viewingAsOwner;
              });
              _loadRentalHistory();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter chips
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('All', 'all', Icons.history),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    'Returned',
                    'returned',
                    Icons.check_circle_outline,
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    'Cancelled',
                    'cancelled',
                    Icons.cancel_outlined,
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    'Disputed',
                    'disputed',
                    Icons.warning_outlined,
                  ),
                ],
              ),
            ),
          ),
          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _historyRentals.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
                    onRefresh: _loadRentalHistory,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _historyRentals.length,
                      itemBuilder: (context, index) {
                        return _buildHistoryCard(_historyRentals[index]);
                      },
                    ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavBarWidget(
        selectedIndex: 1, // Exchange tab (Rent is part of Exchange)
        onTap: (_) {},
        navigationContext: context,
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, IconData icon) {
    final isSelected = _selectedFilter == value;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedFilter = value;
        });
        _loadRentalHistory();
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00897B) : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF00897B) : Colors.grey[300]!,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : Colors.grey[700],
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey[700],
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No Rental History',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _viewingAsOwner
                ? 'Completed rentals you\'ve rented out will appear here'
                : 'Your completed rentals will appear here',
            style: TextStyle(color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> rental) {
    final itemTitle = (rental['itemTitle'] ?? 'Rental Item').toString();
    final ownerName = (rental['ownerName'] ?? 'Owner').toString();
    final renterName = (rental['renterName'] ?? 'Renter').toString();
    final status = (rental['status'] ?? 'returned').toString().toLowerCase();
    final startDate =
        (rental['startDate'] as Timestamp?)?.toDate() ?? DateTime.now();
    final endDate = (rental['endDate'] as Timestamp?)?.toDate();
    final actualReturnDate = (rental['actualReturnDate'] as Timestamp?)
        ?.toDate();
    final totalDue = (rental['totalDue'] as num?)?.toDouble() ?? 0.0;
    final requestId = rental['id'] as String? ?? '';
    final createdAt =
        (rental['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();

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
              _loadRentalHistory();
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
                      color: _getStatusColor(status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _getStatusIcon(status),
                      color: _getStatusColor(status),
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
              // Person info
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
              // Dates
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
                        'Ended: ${_formatDate(endDate)}',
                        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                      ),
                    ),
                  ],
                ),
              ],
              if (actualReturnDate != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.assignment_return,
                      size: 16,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Returned: ${_formatDate(actualReturnDate)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              // Payment info
              if (status == 'returned' && totalDue > 0) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.attach_money,
                        size: 18,
                        color: Colors.green[700],
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total Paid',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                            Text(
                              _formatCurrency(totalDue),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.green[900],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // Rating button for returned rentals
              if (status == 'returned') ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: (rental['hasRated'] as bool? ?? false)
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE0F2F1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.star,
                                    size: 16,
                                    color: Colors.amber[700],
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Rated',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : OutlinedButton.icon(
                              onPressed: () => _rateRental(rental),
                              icon: const Icon(Icons.star_outline, size: 18),
                              label: const Text('Rate'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF00897B),
                                side: const BorderSide(
                                  color: Color(0xFF00897B),
                                  width: 1.5,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ],
              // Created date
              const SizedBox(height: 8),
              Text(
                'Rental created: ${_formatDate(createdAt)}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[500],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _rateRental(Map<String, dynamic> rental) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.user;

      if (currentUser == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You must be logged in to rate'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final requestId = rental['id'] as String? ?? '';
      if (requestId.isEmpty) return;

      // Get rental request details
      final requestData = await _firestoreService.getRentalRequest(requestId);
      if (requestData == null) return;

      final request = RentalRequestModel.fromMap(requestData, requestId);

      // Determine who to rate based on current user
      final isOwner = currentUser.uid == request.ownerId;
      final ratedUserId = isOwner ? request.renterId : request.ownerId;
      final ratedUserName = isOwner ? 'Renter' : 'Owner';

      // Check if already rated (double-check)
      final hasRated = await _ratingService.hasRated(
        raterUserId: currentUser.uid,
        ratedUserId: ratedUserId,
        transactionId: requestId,
      );

      if (hasRated) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You have already rated this rental'),
            backgroundColor: Colors.orange,
          ),
        );
        // Reload to update UI
        _loadRentalHistory();
        return;
      }

      // Get rated user's name if available
      String? ratedUserNameFull;
      try {
        final ratedUserData = await _firestoreService.getUser(ratedUserId);
        if (ratedUserData != null) {
          ratedUserNameFull =
              '${ratedUserData['firstName']} ${ratedUserData['lastName']}';
        }
      } catch (e) {
        // Silent fail, use default
      }

      // Navigate to rating screen
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SubmitRatingScreen(
            ratedUserId: ratedUserId,
            ratedUserName: ratedUserNameFull ?? ratedUserName,
            context: RatingContext.rental,
            transactionId: requestId,
            role: isOwner ? 'owner' : 'renter',
          ),
        ),
      );

      // Reload history after rating
      if (mounted) {
        _loadRentalHistory();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error launching rating: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
