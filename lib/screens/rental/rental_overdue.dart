import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/firestore_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/chat_provider.dart';
import 'package:provider/provider.dart';
import 'active_rental_detail_screen.dart';
import '../chat_detail_screen.dart';

class RentalOverdueScreen extends StatefulWidget {
  const RentalOverdueScreen({super.key});

  @override
  State<RentalOverdueScreen> createState() => _RentalOverdueScreenState();
}

class _RentalOverdueScreenState extends State<RentalOverdueScreen>
    with SingleTickerProviderStateMixin {
  final FirestoreService _firestoreService = FirestoreService();
  late TabController _tabController;

  List<Map<String, dynamic>> _overdueAsRenter = [];
  List<Map<String, dynamic>> _overdueAsOwner = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadOverdueRentals();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadOverdueRentals() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.user?.uid;

      if (userId == null) {
        setState(() {
          _errorMessage = 'User not authenticated';
          _isLoading = false;
        });
        return;
      }

      final now = DateTime.now();

      // Load rentals as renter
      final renterRentals = await _firestoreService.getRentalRequestsByUser(
        userId,
        asOwner: false,
      );

      // Load rentals as owner
      final ownerRentals = await _firestoreService.getRentalRequestsByUser(
        userId,
        asOwner: true,
      );

      // Filter overdue rentals as renter (exclude monthly rentals)
      final overdueAsRenter = <Map<String, dynamic>>[];
      for (final rental in renterRentals) {
        final isLongTerm = rental['isLongTerm'] as bool? ?? false;
        if (isLongTerm) continue; // Skip monthly rentals

        final status = (rental['status'] ?? 'requested')
            .toString()
            .toLowerCase();
        if (status != 'active' &&
            status != 'ownerapproved' &&
            status != 'returninitiated')
          continue;

        final returnDueDate = (rental['returnDueDate'] as Timestamp?)?.toDate();
        final endDate = (rental['endDate'] as Timestamp?)?.toDate();
        final dueDate = returnDueDate ?? endDate;

        if (dueDate != null && dueDate.isBefore(now)) {
          // Enrich with item and owner info
          final enrichedRental = Map<String, dynamic>.from(rental);
          enrichedRental['dueDate'] = dueDate;
          enrichedRental['daysOverdue'] = now.difference(dueDate).inDays;

          // Get item title from listing
          final listingId = rental['listingId'] as String?;
          if (listingId != null) {
            try {
              final listing = await _firestoreService.getRentalListing(
                listingId,
              );
              if (listing != null) {
                enrichedRental['itemTitle'] = listing['title'] as String?;
                enrichedRental['imageUrl'] = listing['imageUrl'] as String?;
                enrichedRental['images'] = listing['images'] as List?;
              }
            } catch (_) {}
          }
          enrichedRental['itemTitle'] ??= 'Rental Item';

          // Get owner name
          final ownerId = rental['ownerId'] as String?;
          if (ownerId != null) {
            try {
              final owner = await _firestoreService.getUser(ownerId);
              if (owner != null) {
                final firstName = owner['firstName'] ?? '';
                final lastName = owner['lastName'] ?? '';
                enrichedRental['ownerName'] = '$firstName $lastName'.trim();
              }
            } catch (_) {}
          }
          enrichedRental['ownerName'] ??= 'Owner';

          overdueAsRenter.add(enrichedRental);
        }
      }

      // Filter overdue rentals as owner (exclude monthly rentals)
      final overdueAsOwner = <Map<String, dynamic>>[];
      for (final rental in ownerRentals) {
        final isLongTerm = rental['isLongTerm'] as bool? ?? false;
        if (isLongTerm) continue; // Skip monthly rentals

        final status = (rental['status'] ?? 'requested')
            .toString()
            .toLowerCase();
        if (status != 'active' &&
            status != 'ownerapproved' &&
            status != 'returninitiated')
          continue;

        final returnDueDate = (rental['returnDueDate'] as Timestamp?)?.toDate();
        final endDate = (rental['endDate'] as Timestamp?)?.toDate();
        final dueDate = returnDueDate ?? endDate;

        if (dueDate != null && dueDate.isBefore(now)) {
          // Enrich with item and renter info
          final enrichedRental = Map<String, dynamic>.from(rental);
          enrichedRental['dueDate'] = dueDate;
          enrichedRental['daysOverdue'] = now.difference(dueDate).inDays;

          // Get item title from listing
          final listingId = rental['listingId'] as String?;
          if (listingId != null) {
            try {
              final listing = await _firestoreService.getRentalListing(
                listingId,
              );
              if (listing != null) {
                enrichedRental['itemTitle'] = listing['title'] as String?;
                enrichedRental['imageUrl'] = listing['imageUrl'] as String?;
                enrichedRental['images'] = listing['images'] as List?;
              }
            } catch (_) {}
          }
          enrichedRental['itemTitle'] ??= 'Rental Item';

          // Get renter name
          final renterId = rental['renterId'] as String?;
          if (renterId != null) {
            try {
              final renter = await _firestoreService.getUser(renterId);
              if (renter != null) {
                final firstName = renter['firstName'] ?? '';
                final lastName = renter['lastName'] ?? '';
                enrichedRental['renterName'] = '$firstName $lastName'.trim();
              }
            } catch (_) {}
          }
          enrichedRental['renterName'] ??= 'Renter';

          overdueAsOwner.add(enrichedRental);
        }
      }

      // Sort by days overdue (most overdue first)
      overdueAsRenter.sort((a, b) {
        final daysA = a['daysOverdue'] as int? ?? 0;
        final daysB = b['daysOverdue'] as int? ?? 0;
        return daysB.compareTo(daysA);
      });

      overdueAsOwner.sort((a, b) {
        final daysA = a['daysOverdue'] as int? ?? 0;
        final daysB = b['daysOverdue'] as int? ?? 0;
        return daysB.compareTo(daysA);
      });

      if (mounted) {
        setState(() {
          _overdueAsRenter = overdueAsRenter;
          _overdueAsOwner = overdueAsOwner;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error loading overdue rentals: ${e.toString()}';
          _isLoading = false;
        });
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

  Future<void> _messageRenter(Map<String, dynamic> rental) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    if (!authProvider.isAuthenticated || authProvider.user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please login to message'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final currentUser = userProvider.currentUser;
    if (currentUser == null) return;

    final renterId = rental['renterId'] as String?;
    final renterName = (rental['renterName'] ?? 'Renter').toString();
    final itemId = rental['itemId'] as String? ?? '';
    final itemTitle = (rental['itemTitle'] ?? 'Rental Item').toString();

    if (renterId == null || renterId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Renter information not available'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Show loading
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogContext) =>
          const Center(child: CircularProgressIndicator()),
    );

    // Create or get conversation
    final conversationId = await chatProvider.createOrGetConversation(
      userId1: authProvider.user!.uid,
      userId1Name: currentUser.fullName,
      userId2: renterId,
      userId2Name: renterName,
      itemId: itemId,
      itemTitle: itemTitle,
    );

    // Close loading dialog
    if (mounted) {
      final rootNav = Navigator.of(context, rootNavigator: true);
      if (rootNav.canPop()) rootNav.pop();
    }

    if (conversationId != null && mounted) {
      // Navigate to chat detail screen
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatDetailScreen(
            conversationId: conversationId,
            otherParticipantName: renterName,
            userId: authProvider.user!.uid,
          ),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to create conversation'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildOverdueCard(Map<String, dynamic> rental, bool isOwnerView) {
    final itemTitle = (rental['itemTitle'] ?? 'Rental Item').toString();
    final ownerName = (rental['ownerName'] ?? 'Owner').toString();
    final renterName = (rental['renterName'] ?? 'Renter').toString();
    final daysOverdue = rental['daysOverdue'] as int? ?? 0;
    final dueDate = rental['dueDate'] as DateTime?;
    final requestId = rental['id'] as String? ?? '';
    final imageUrl = rental['imageUrl'] as String?;
    final images = rental['images'] as List?;
    final priceQuote = (rental['priceQuote'] as num?)?.toDouble() ?? 0.0;
    final totalDue = (rental['totalDue'] as num?)?.toDouble() ?? 0.0;
    final status = (rental['status'] ?? 'requested').toString().toLowerCase();
    final isReturnInitiated = status == 'returninitiated';

    // Get first available image
    String? displayImageUrl;
    if (images != null && images.isNotEmpty) {
      displayImageUrl = images.first as String?;
    } else if (imageUrl != null && imageUrl.isNotEmpty) {
      displayImageUrl = imageUrl;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.red[300]!, width: 2),
      ),
      child: InkWell(
        onTap: () {
          if (requestId.isNotEmpty) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    ActiveRentalDetailScreen(requestId: requestId),
              ),
            ).then((_) => _loadOverdueRentals());
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image and overdue badge
            Stack(
              children: [
                if (displayImageUrl != null && displayImageUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    child: CachedNetworkImage(
                      imageUrl: displayImageUrl,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        height: 180,
                        color: Colors.grey[200],
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                      errorWidget: (context, url, error) => Container(
                        height: 180,
                        color: Colors.grey[200],
                        child: const Icon(
                          Icons.image_not_supported,
                          size: 48,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  )
                else
                  Container(
                    height: 180,
                    color: Colors.grey[200],
                    child: const Icon(
                      Icons.inventory_2_outlined,
                      size: 48,
                      color: Colors.grey,
                    ),
                  ),
                // Overdue badge
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.warning,
                          color: Colors.white,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$daysOverdue day${daysOverdue != 1 ? 's' : ''} OVERDUE',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Item title
                  Text(
                    itemTitle,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  // Person info
                  Row(
                    children: [
                      Icon(Icons.person, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isOwnerView
                              ? 'Rented by: $renterName'
                              : 'Owner: $ownerName',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Due date
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          dueDate != null
                              ? 'Was due: ${_formatDate(dueDate)}'
                              : 'Due date not set',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Amount
                  Row(
                    children: [
                      Icon(
                        Icons.attach_money,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Amount: ${_formatCurrency(totalDue > 0 ? totalDue : priceQuote)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            if (requestId.isNotEmpty) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      ActiveRentalDetailScreen(
                                        requestId: requestId,
                                      ),
                                ),
                              ).then((_) => _loadOverdueRentals());
                            }
                          },
                          icon: const Icon(Icons.info_outline, size: 18),
                          label: const Text('View Details'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF00897B),
                            side: const BorderSide(color: Color(0xFF00897B)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (!isOwnerView)
                        Expanded(
                          child: isReturnInitiated
                              ? ElevatedButton.icon(
                                  onPressed: null, // Disabled
                                  icon: const Icon(
                                    Icons.hourglass_empty,
                                    size: 18,
                                  ),
                                  label: const Text('Return Pending'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.grey,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                )
                              : ElevatedButton.icon(
                                  onPressed: () {
                                    // Navigate to initiate return
                                    if (requestId.isNotEmpty) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              ActiveRentalDetailScreen(
                                                requestId: requestId,
                                              ),
                                        ),
                                      ).then((_) => _loadOverdueRentals());
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.assignment_return,
                                    size: 18,
                                  ),
                                  label: const Text('Return'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                        ),
                      if (isOwnerView)
                        Expanded(
                          child: isReturnInitiated
                              ? ElevatedButton.icon(
                                  onPressed: () {
                                    // Navigate to verify return
                                    if (requestId.isNotEmpty) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              ActiveRentalDetailScreen(
                                                requestId: requestId,
                                              ),
                                        ),
                                      ).then((_) => _loadOverdueRentals());
                                    }
                                  },
                                  icon: const Icon(Icons.verified, size: 18),
                                  label: const Text('Verify Return'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                )
                              : ElevatedButton.icon(
                                  onPressed: () => _messageRenter(rental),
                                  icon: const Icon(Icons.message, size: 18),
                                  label: const Text('Send Reminder'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isOwnerView) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline, size: 64, color: Colors.green[400]),
          const SizedBox(height: 16),
          Text(
            'No Overdue Rentals',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isOwnerView
                ? 'All items rented out are up to date'
                : 'All your rentals are up to date',
            style: TextStyle(color: Colors.grey[500]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Overdue Rentals',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.red[700],
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.shopping_bag_outlined), text: 'As Renter'),
            Tab(icon: Icon(Icons.store_outlined), text: 'As Owner'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadOverdueRentals,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    style: TextStyle(color: Colors.grey[700], fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadOverdueRentals,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                // As Renter Tab
                RefreshIndicator(
                  onRefresh: _loadOverdueRentals,
                  child: _overdueAsRenter.isEmpty
                      ? _buildEmptyState(false)
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _overdueAsRenter.length,
                          itemBuilder: (context, index) {
                            return _buildOverdueCard(
                              _overdueAsRenter[index],
                              false,
                            );
                          },
                        ),
                ),
                // As Owner Tab
                RefreshIndicator(
                  onRefresh: _loadOverdueRentals,
                  child: _overdueAsOwner.isEmpty
                      ? _buildEmptyState(true)
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _overdueAsOwner.length,
                          itemBuilder: (context, index) {
                            return _buildOverdueCard(
                              _overdueAsOwner[index],
                              true,
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
