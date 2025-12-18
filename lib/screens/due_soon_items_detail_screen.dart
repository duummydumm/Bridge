import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../reusable_widgets/bottom_nav_bar_widget.dart';
import '../services/local_notifications_service.dart';
import 'rental/active_rental_detail_screen.dart';

class DueSoonItemsDetailScreen extends StatefulWidget {
  const DueSoonItemsDetailScreen({super.key});

  @override
  State<DueSoonItemsDetailScreen> createState() =>
      _DueSoonItemsDetailScreenState();
}

class _DueSoonItemsDetailScreenState extends State<DueSoonItemsDetailScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  List<Map<String, dynamic>> _dueSoonItems = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDueSoonItems();
  }

  Future<void> _loadDueSoonItems() async {
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

      final allBorrowed = await _firestoreService.getBorrowedItemsByBorrower(
        userId,
      );
      final now = DateTime.now();
      final dueSoonBorrowed = allBorrowed.where((item) {
        final returnDate = _parseDate(item['returnDate']);
        if (returnDate == null) return false;
        return returnDate.isBefore(now.add(const Duration(days: 3)));
      }).toList();

      // Mark borrowed items with type
      for (final item in dueSoonBorrowed) {
        item['type'] = 'borrow';
      }

      // Load rental items where user is the renter
      final renterRentalRequests = await _firestoreService
          .getRentalRequestsByUser(userId, asOwner: false);

      // Filter for active rentals
      final activeRentals = renterRentalRequests.where((req) {
        final status = (req['status'] ?? 'requested').toString().toLowerCase();
        return status == 'ownerapproved' ||
            status == 'active' ||
            status == 'returninitiated';
      }).toList();

      // Filter rentals that are due soon
      final dueSoonRentals = <Map<String, dynamic>>[];
      for (final rental in activeRentals) {
        final returnDate = _parseDate(rental['returnDueDate']);
        if (returnDate != null &&
            returnDate.isBefore(now.add(const Duration(days: 3)))) {
          final enrichedRental = Map<String, dynamic>.from(rental);

          // Get item title from listing
          final listingId = rental['listingId'] as String?;
          if (listingId != null) {
            try {
              final listing = await _firestoreService.getRentalListing(
                listingId,
              );
              if (listing != null) {
                enrichedRental['title'] = listing['title'] as String?;
              }
            } catch (_) {
              // Continue if listing fetch fails
            }
          }
          enrichedRental['title'] ??= 'Rental Item';
          enrichedRental['type'] = 'rental';
          enrichedRental['returnDate'] =
              returnDate; // Use returnDate for consistency
          enrichedRental['id'] = rental['id'] ?? rental['requestId'] ?? '';
          dueSoonRentals.add(enrichedRental);
        }
      }

      // Combine borrowed and rental items
      final allDueSoon = [...dueSoonBorrowed, ...dueSoonRentals];

      // Sort by due date (earliest first)
      allDueSoon.sort((a, b) {
        final dateA = _parseDate(a['returnDate']);
        final dateB = _parseDate(b['returnDate']);
        if (dateA == null && dateB == null) return 0;
        if (dateA == null) return 1;
        if (dateB == null) return -1;
        return dateA.compareTo(dateB);
      });

      setState(() {
        _dueSoonItems = allDueSoon;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading due soon items: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  DateTime? _parseDate(dynamic dateValue) {
    if (dateValue == null) return null;
    if (dateValue is DateTime) return dateValue;
    if (dateValue is Timestamp) return dateValue.toDate();
    if (dateValue is int) {
      return DateTime.fromMillisecondsSinceEpoch(dateValue);
    }
    return null;
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'No date set';
    final now = DateTime.now();
    final difference = date.difference(now);

    if (difference.inDays < 0) {
      return 'Overdue by ${difference.inDays.abs()} ${difference.inDays.abs() == 1 ? 'day' : 'days'}';
    } else if (difference.inDays == 0) {
      final hours = difference.inHours;
      if (hours < 0) {
        return 'Overdue by ${hours.abs()} ${hours.abs() == 1 ? 'hour' : 'hours'}';
      }
      return 'Due today at ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Due tomorrow at ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else {
      return 'Due on ${date.day}/${date.month}/${date.year}';
    }
  }

  Color _getStatusColor(DateTime? returnDate) {
    if (returnDate == null) return Colors.grey;
    final now = DateTime.now();
    final difference = returnDate.difference(now);

    if (difference.inDays < 0) {
      return Colors.red;
    } else if (difference.inDays == 0) {
      return Colors.orange;
    } else if (difference.inDays <= 3) {
      return Colors.orange.shade700;
    } else {
      return Colors.green;
    }
  }

  Future<void> _scheduleReminder(String itemId, String itemTitle) async {
    try {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF00897B),
        elevation: 0,
        title: const Text(
          'Due Soon Items',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today, color: Colors.white),
            onPressed: () {
              Navigator.pushNamed(context, '/upcoming-reminders');
            },
            tooltip: 'View Calendar',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadDueSoonItems,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadDueSoonItems,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      style: TextStyle(color: Colors.grey[700], fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loadDueSoonItems,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            : _dueSoonItems.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 64,
                      color: Colors.green[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'All caught up!',
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No items due soon',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _dueSoonItems.length,
                itemBuilder: (context, index) {
                  final item = _dueSoonItems[index];
                  final itemId = (item['id'] ?? '').toString();
                  final title = (item['title'] ?? 'Untitled Item').toString();
                  final returnDate = _parseDate(item['returnDate']);
                  final statusColor = _getStatusColor(returnDate);
                  final isOverdue =
                      returnDate != null && returnDate.isBefore(DateTime.now());
                  final itemType = (item['type'] ?? 'borrow').toString();
                  final isRental = itemType == 'rental';
                  final requestId = item['id'] ?? item['requestId'] ?? '';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: isOverdue
                          ? BorderSide(color: Colors.red, width: 2)
                          : BorderSide.none,
                    ),
                    child: InkWell(
                      onTap: () {
                        if (isRental && requestId.isNotEmpty) {
                          // Navigate to rental detail screen
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ActiveRentalDetailScreen(
                                requestId: requestId,
                              ),
                            ),
                          );
                        } else {
                          // Navigate to currently borrowed screen to view item details
                          Navigator.pushNamed(
                            context,
                            '/borrow/currently-borrowed',
                          );
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    isOverdue
                                        ? Icons.warning
                                        : isRental
                                        ? Icons.home_outlined
                                        : Icons.access_time,
                                    color: statusColor,
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              title,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF1A1A1A),
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (isRental)
                                            Container(
                                              margin: const EdgeInsets.only(
                                                left: 8,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.blue.withValues(
                                                  alpha: 0.1,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                'Rental',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.blue[700],
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.calendar_today,
                                            size: 16,
                                            color: statusColor,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            _formatDate(returnDate),
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: statusColor,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right,
                                  color: Colors.grey[400],
                                ),
                              ],
                            ),
                            if (!isOverdue) ...[
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      _scheduleReminder(itemId, title),
                                  icon: const Icon(Icons.notifications),
                                  label: const Text('Remind Me Later'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: statusColor,
                                    side: BorderSide(color: statusColor),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
      bottomNavigationBar: BottomNavBarWidget(
        selectedIndex: 0,
        onTap: (_) {},
        navigationContext: context,
      ),
    );
  }
}
