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
import '../../services/local_notifications_service.dart';

class RentalDueSoonScreen extends StatefulWidget {
  const RentalDueSoonScreen({super.key});

  @override
  State<RentalDueSoonScreen> createState() => _RentalDueSoonScreenState();
}

class _RentalDueSoonScreenState extends State<RentalDueSoonScreen>
    with SingleTickerProviderStateMixin {
  final FirestoreService _firestoreService = FirestoreService();
  late TabController _tabController;

  List<Map<String, dynamic>> _dueSoonAsRenter = [];
  List<Map<String, dynamic>> _dueSoonAsOwner = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadDueSoonRentals();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDueSoonRentals() async {
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
      // Normalize to start of day for accurate day comparison
      final nowStartOfDay = DateTime(now.year, now.month, now.day);
      final threeDaysFromNow = nowStartOfDay.add(const Duration(days: 3));

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

      // Filter due soon rentals as renter (exclude monthly rentals)
      final dueSoonAsRenter = <Map<String, dynamic>>[];
      for (final rental in renterRentals) {
        final isLongTerm = rental['isLongTerm'] as bool? ?? false;
        if (isLongTerm) continue; // Skip monthly rentals

        final status = (rental['status'] ?? 'requested')
            .toString()
            .toLowerCase();
        if (status != 'active' && status != 'ownerapproved') continue;

        final returnDueDate = (rental['returnDueDate'] as Timestamp?)?.toDate();
        final endDate = (rental['endDate'] as Timestamp?)?.toDate();
        // Use endDate as primary source (matches detail screen), fallback to returnDueDate
        final dueDate = endDate ?? returnDueDate;

        if (dueDate != null) {
          // Normalize due date to start of day for accurate comparison
          final dueDateStartOfDay = DateTime(
            dueDate.year,
            dueDate.month,
            dueDate.day,
          );

          // Check if due date is today or within next 3 days (but not overdue)
          // Due soon = today OR (after today AND within 3 days)
          // Exclude overdue items (they should be in overdue screen, not due soon)
          final isDueToday = dueDateStartOfDay.isAtSameMomentAs(nowStartOfDay);
          final isDueInFuture =
              dueDateStartOfDay.isAfter(nowStartOfDay) &&
              (dueDateStartOfDay.isBefore(threeDaysFromNow) ||
                  dueDateStartOfDay.isAtSameMomentAs(threeDaysFromNow));

          if (isDueToday || isDueInFuture) {
            // Enrich with item and owner info
            final enrichedRental = Map<String, dynamic>.from(rental);
            enrichedRental['dueDate'] = dueDate;
            // Calculate days until (using normalized dates)
            final daysUntil = dueDateStartOfDay
                .difference(nowStartOfDay)
                .inDays;
            enrichedRental['daysUntil'] = daysUntil;

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

            dueSoonAsRenter.add(enrichedRental);
          }
        }
      }

      // Filter due soon rentals as owner (exclude monthly rentals)
      final dueSoonAsOwner = <Map<String, dynamic>>[];
      for (final rental in ownerRentals) {
        final isLongTerm = rental['isLongTerm'] as bool? ?? false;
        if (isLongTerm) continue; // Skip monthly rentals

        final status = (rental['status'] ?? 'requested')
            .toString()
            .toLowerCase();
        if (status != 'active' && status != 'ownerapproved') continue;

        final returnDueDate = (rental['returnDueDate'] as Timestamp?)?.toDate();
        final endDate = (rental['endDate'] as Timestamp?)?.toDate();
        // Use endDate as primary source (matches detail screen), fallback to returnDueDate
        final dueDate = endDate ?? returnDueDate;

        if (dueDate != null) {
          // Normalize due date to start of day for accurate comparison
          final dueDateStartOfDay = DateTime(
            dueDate.year,
            dueDate.month,
            dueDate.day,
          );

          // Check if due date is today or within next 3 days (but not overdue)
          // Due soon = today OR (after today AND within 3 days)
          // Exclude overdue items (they should be in overdue screen, not due soon)
          final isDueToday = dueDateStartOfDay.isAtSameMomentAs(nowStartOfDay);
          final isDueInFuture =
              dueDateStartOfDay.isAfter(nowStartOfDay) &&
              (dueDateStartOfDay.isBefore(threeDaysFromNow) ||
                  dueDateStartOfDay.isAtSameMomentAs(threeDaysFromNow));

          if (isDueToday || isDueInFuture) {
            // Enrich with item and renter info
            final enrichedRental = Map<String, dynamic>.from(rental);
            enrichedRental['dueDate'] = dueDate;
            // Calculate days until (using normalized dates)
            final daysUntil = dueDateStartOfDay
                .difference(nowStartOfDay)
                .inDays;
            enrichedRental['daysUntil'] = daysUntil;

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

            dueSoonAsOwner.add(enrichedRental);
          }
        }
      }

      // Sort by due date (earliest first)
      dueSoonAsRenter.sort((a, b) {
        final dateA = a['dueDate'] as DateTime?;
        final dateB = b['dueDate'] as DateTime?;
        if (dateA == null && dateB == null) return 0;
        if (dateA == null) return 1;
        if (dateB == null) return -1;
        return dateA.compareTo(dateB);
      });

      dueSoonAsOwner.sort((a, b) {
        final dateA = a['dueDate'] as DateTime?;
        final dateB = b['dueDate'] as DateTime?;
        if (dateA == null && dateB == null) return 0;
        if (dateA == null) return 1;
        if (dateB == null) return -1;
        return dateA.compareTo(dateB);
      });

      if (mounted) {
        setState(() {
          _dueSoonAsRenter = dueSoonAsRenter;
          _dueSoonAsOwner = dueSoonAsOwner;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error loading due soon rentals: ${e.toString()}';
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

  String _formatDueDate(DateTime? dueDate) {
    if (dueDate == null) return 'No date set';
    final now = DateTime.now();
    // Normalize to start of day for accurate day comparison
    final nowStartOfDay = DateTime(now.year, now.month, now.day);
    final dueDateStartOfDay = DateTime(
      dueDate.year,
      dueDate.month,
      dueDate.day,
    );
    final difference = dueDateStartOfDay.difference(nowStartOfDay);

    if (difference.inDays == 0) {
      // Same day - show time if available
      if (dueDate.hour != 0 || dueDate.minute != 0) {
        return 'Due today at ${dueDate.hour.toString().padLeft(2, '0')}:${dueDate.minute.toString().padLeft(2, '0')}';
      }
      return 'Due today';
    } else if (difference.inDays == 1) {
      // Tomorrow - show time if available
      if (dueDate.hour != 0 || dueDate.minute != 0) {
        return 'Due tomorrow at ${dueDate.hour.toString().padLeft(2, '0')}:${dueDate.minute.toString().padLeft(2, '0')}';
      }
      return 'Due tomorrow';
    } else if (difference.inDays > 1 && difference.inDays <= 3) {
      return 'Due in ${difference.inDays} days (${_formatDate(dueDate)})';
    } else {
      return 'Due on ${_formatDate(dueDate)}';
    }
  }

  String _formatCurrency(double? amount) {
    if (amount == null) return '₱0.00';
    return '₱${amount.toStringAsFixed(2)}';
  }

  Color _getStatusColor(int? daysUntil) {
    if (daysUntil == null) return Colors.grey;
    if (daysUntil == 0) return Colors.orange;
    if (daysUntil == 1) return Colors.orange.shade700;
    return Colors.orange.shade600;
  }

  String _getStatusLabel(int? daysUntil) {
    if (daysUntil == null) return 'Due Soon';
    if (daysUntil == 0) return 'Due Today';
    if (daysUntil == 1) return 'Due Tomorrow';
    return 'Due in $daysUntil days';
  }

  Future<void> _messageOwner(Map<String, dynamic> rental) async {
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

    final ownerId = rental['ownerId'] as String?;
    final ownerName = (rental['ownerName'] ?? 'Owner').toString();
    final itemId = rental['itemId'] as String? ?? '';
    final itemTitle = (rental['itemTitle'] ?? 'Rental Item').toString();

    if (ownerId == null || ownerId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Owner information not available'),
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
      userId2: ownerId,
      userId2Name: ownerName,
      itemId: itemId,
      itemTitle: itemTitle,
    );

    // Close loading dialog
    if (mounted) {
      final rootNav = Navigator.of(context, rootNavigator: true);
      if (rootNav.canPop()) rootNav.pop();
    }

    if (conversationId != null && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatDetailScreen(
            conversationId: conversationId,
            otherParticipantName: ownerName,
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

  Future<void> _scheduleReminder(Map<String, dynamic> rental) async {
    try {
      final itemId = rental['itemId'] as String? ?? '';
      final itemTitle = (rental['itemTitle'] ?? 'Rental Item').toString();
      final dueDate = rental['dueDate'] as DateTime?;

      if (itemId.isEmpty || dueDate == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to schedule reminder'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      await LocalNotificationsService().scheduleNudge(
        itemId: itemId,
        itemTitle: itemTitle,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reminder scheduled successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error scheduling reminder: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildDueSoonCard(Map<String, dynamic> rental, bool isOwnerView) {
    final itemTitle = (rental['itemTitle'] ?? 'Rental Item').toString();
    final ownerName = (rental['ownerName'] ?? 'Owner').toString();
    final renterName = (rental['renterName'] ?? 'Renter').toString();
    final daysUntil = rental['daysUntil'] as int? ?? 0;
    final dueDate = rental['dueDate'] as DateTime?;
    final requestId = rental['id'] as String? ?? '';
    final imageUrl = rental['imageUrl'] as String?;
    final images = rental['images'] as List?;
    final priceQuote = (rental['priceQuote'] as num?)?.toDouble() ?? 0.0;
    final totalDue = (rental['totalDue'] as num?)?.toDouble() ?? 0.0;
    final statusColor = _getStatusColor(daysUntil);

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
        side: BorderSide(color: statusColor.withValues(alpha: 0.5), width: 2),
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
            ).then((_) => _loadDueSoonRentals());
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image and due soon badge
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
                // Due soon badge
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.access_time,
                          color: Colors.white,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _getStatusLabel(daysUntil),
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
                      Icon(Icons.calendar_today, size: 16, color: statusColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _formatDueDate(dueDate),
                          style: TextStyle(
                            fontSize: 13,
                            color: statusColor,
                            fontWeight: FontWeight.w600,
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
                  if (!isOwnerView) ...[
                    // Renter view buttons
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
                                ).then((_) => _loadDueSoonRentals());
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
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _messageOwner(rental),
                            icon: const Icon(Icons.message, size: 18),
                            label: const Text('Contact'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.blue,
                              side: const BorderSide(color: Colors.blue),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              // Navigate to initiate return if due today/tomorrow
                              if (requestId.isNotEmpty) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        ActiveRentalDetailScreen(
                                          requestId: requestId,
                                        ),
                                  ),
                                ).then((_) => _loadDueSoonRentals());
                              }
                            },
                            icon: const Icon(Icons.assignment_return, size: 18),
                            label: const Text('Initiate Return'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _scheduleReminder(rental),
                            icon: const Icon(Icons.notifications, size: 18),
                            label: const Text('Remind Me'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: statusColor,
                              side: BorderSide(color: statusColor),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    // Owner view buttons
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
                                ).then((_) => _loadDueSoonRentals());
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
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _messageRenter(rental),
                            icon: const Icon(Icons.message, size: 18),
                            label: const Text('Send Reminder'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
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
            'All caught up!',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isOwnerView ? 'No items due soon' : 'No rentals due soon',
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
          'Due Soon Rentals',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.orange[700],
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
            onPressed: _loadDueSoonRentals,
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
                    onPressed: _loadDueSoonRentals,
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
                  onRefresh: _loadDueSoonRentals,
                  child: _dueSoonAsRenter.isEmpty
                      ? _buildEmptyState(false)
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _dueSoonAsRenter.length,
                          itemBuilder: (context, index) {
                            return _buildDueSoonCard(
                              _dueSoonAsRenter[index],
                              false,
                            );
                          },
                        ),
                ),
                // As Owner Tab
                RefreshIndicator(
                  onRefresh: _loadDueSoonRentals,
                  child: _dueSoonAsOwner.isEmpty
                      ? _buildEmptyState(true)
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _dueSoonAsOwner.length,
                          itemBuilder: (context, index) {
                            return _buildDueSoonCard(
                              _dueSoonAsOwner[index],
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
