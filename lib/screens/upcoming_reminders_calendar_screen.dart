import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../reusable_widgets/bottom_nav_bar_widget.dart';
import '../services/local_notifications_service.dart';

class UpcomingRemindersCalendarScreen extends StatefulWidget {
  const UpcomingRemindersCalendarScreen({super.key});

  @override
  State<UpcomingRemindersCalendarScreen> createState() =>
      _UpcomingRemindersCalendarScreenState();
}

class _UpcomingRemindersCalendarScreenState
    extends State<UpcomingRemindersCalendarScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  DateTime _selectedMonth = DateTime.now();
  DateTime? _selectedDate;
  Map<DateTime, List<Map<String, dynamic>>> _itemsByDate = {};
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _loadBorrowedItems();
  }

  Future<void> _loadBorrowedItems() async {
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

      // Load borrowed items (items user borrowed)
      final borrowedItems = await _firestoreService.getBorrowedItemsByBorrower(
        userId,
      );

      // Load rental items where user is the owner (renting out)
      final ownerRentalRequests = await _firestoreService.getRentalRequestsByUser(
        userId,
        asOwner: true,
      );

      // Load rental items where user is the renter (renting from others)
      final renterRentalRequests = await _firestoreService.getRentalRequestsByUser(
        userId,
        asOwner: false,
      );

      // Combine both owner and renter rentals
      final allRentalRequests = [
        ...ownerRentalRequests,
        ...renterRentalRequests,
      ];

      // Filter for active rentals
      final activeRentals = allRentalRequests.where((req) {
        final status = (req['status'] ?? 'requested').toString().toLowerCase();
        return status == 'ownerapproved' ||
            status == 'active' ||
            status == 'returninitiated';
      }).toList();

      // Enrich rental data with item title
      final enrichedRentals = <Map<String, dynamic>>[];
      for (final rental in activeRentals) {
        final enrichedRental = Map<String, dynamic>.from(rental);

        // Get item title from listing
        final listingId = rental['listingId'] as String?;
        if (listingId != null) {
          try {
            final listing = await _firestoreService.getRentalListing(listingId);
            if (listing != null) {
              enrichedRental['title'] = listing['title'] as String?;
              // Fallback to item title if listing title not available
              if (enrichedRental['title'] == null ||
                  (enrichedRental['title'] as String).isEmpty) {
                final itemId = rental['itemId'] as String?;
                if (itemId != null) {
                  final item = await _firestoreService.getItem(itemId);
                  enrichedRental['title'] = item?['title'] as String?;
                }
              }
            }
          } catch (_) {
            // Continue if listing fetch fails
          }
        }
        enrichedRental['title'] ??= 'Rental Item';
        enrichedRental['type'] = 'rental'; // Mark as rental item
        enrichedRentals.add(enrichedRental);
      }

      // Mark borrowed items
      for (final item in borrowedItems) {
        item['type'] = 'borrow';
      }

      // Group items by their return date (date only, no time)
      final itemsByDate = <DateTime, List<Map<String, dynamic>>>{};

      // Process borrowed items
      for (final item in borrowedItems) {
        final returnDate = _parseDate(item['returnDate']);
        if (returnDate != null) {
          // Convert to local time and normalize to start of day
          final returnDateLocal = returnDate.toLocal();
          final dateOnly = DateTime(
            returnDateLocal.year,
            returnDateLocal.month,
            returnDateLocal.day,
          );
          itemsByDate.putIfAbsent(dateOnly, () => []).add(item);
        }
      }

      // Process rental items
      for (final rental in enrichedRentals) {
        final returnDate = _parseDate(rental['returnDueDate']);
        if (returnDate != null) {
          // Convert to local time and normalize to start of day
          final returnDateLocal = returnDate.toLocal();
          final dateOnly = DateTime(
            returnDateLocal.year,
            returnDateLocal.month,
            returnDateLocal.day,
          );
          // Use returnDueDate for the calendar display, but store it as returnDate for consistency
          final rentalForCalendar = Map<String, dynamic>.from(rental);
          rentalForCalendar['returnDate'] = returnDate;
          itemsByDate.putIfAbsent(dateOnly, () => []).add(rentalForCalendar);
        }
      }

      setState(() {
        _itemsByDate = itemsByDate;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading items: ${e.toString()}';
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

  void _previousMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
    });
  }

  void _goToToday() {
    setState(() {
      _selectedMonth = DateTime.now();
      _selectedDate = DateTime.now();
    });
  }

  Color _getDateColor(DateTime date) {
    // Normalize to start of day for accurate day comparison
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final dateStart = DateTime(date.year, date.month, date.day);
    final difference = dateStart.difference(todayStart).inDays;

    if (difference < 0) {
      return Colors.red; // Overdue
    } else if (difference == 0) {
      return Colors.orange; // Due today
    } else if (difference <= 3) {
      return Colors.orange.shade700; // Due soon
    } else {
      return const Color(0xFF00897B); // Future date
    }
  }

  List<Map<String, dynamic>> _getItemsForDate(DateTime date) {
    final dateOnly = DateTime(date.year, date.month, date.day);
    return _itemsByDate[dateOnly] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF00897B),
        elevation: 0,
        title: const Text(
          'Upcoming Reminders',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.today, color: Colors.white),
            onPressed: _goToToday,
            tooltip: 'Go to today',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadBorrowedItems,
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
                    onPressed: _loadBorrowedItems,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Calendar Header
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: _previousMonth,
                      ),
                      Text(
                        '${_getMonthName(_selectedMonth.month)} ${_selectedMonth.year}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: _nextMonth,
                      ),
                    ],
                  ),
                ),
                // Calendar Grid
                Expanded(child: _buildCalendar()),
                // Selected Date Items
                if (_selectedDate != null)
                  Container(
                    height: 200,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: _buildSelectedDateItems(),
                  ),
              ],
            ),
      bottomNavigationBar: BottomNavBarWidget(
        selectedIndex: 0,
        onTap: (_) {},
        navigationContext: context,
      ),
    );
  }

  Widget _buildCalendar() {
    final firstDayOfMonth = DateTime(
      _selectedMonth.year,
      _selectedMonth.month,
      1,
    );
    final lastDayOfMonth = DateTime(
      _selectedMonth.year,
      _selectedMonth.month + 1,
      0,
    );
    final firstWeekday = firstDayOfMonth.weekday;
    final daysInMonth = lastDayOfMonth.day;
    // Normalize to start of day for accurate day comparison
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Calculate total cells needed (including empty cells at start)
    final totalCells = firstWeekday - 1 + daysInMonth;
    final weeks = (totalCells / 7).ceil();

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // Weekday headers
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Row(
              children: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
                  .map(
                    (day) => Expanded(
                      child: Center(
                        child: Text(
                          day,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          // Calendar grid
          Expanded(
            child: ListView.builder(
              itemCount: weeks,
              itemBuilder: (context, weekIndex) {
                return Row(
                  children: List.generate(7, (dayIndex) {
                    final cellIndex = weekIndex * 7 + dayIndex;
                    final dayNumber = cellIndex - (firstWeekday - 1) + 1;

                    if (dayNumber < 1 || dayNumber > daysInMonth) {
                      return Expanded(child: Container());
                    }

                    final date = DateTime(
                      _selectedMonth.year,
                      _selectedMonth.month,
                      dayNumber,
                    );
                    final dateOnly = DateTime(date.year, date.month, date.day);
                    final isToday = dateOnly == today;
                    final isSelected =
                        _selectedDate != null &&
                        DateTime(
                              _selectedDate!.year,
                              _selectedDate!.month,
                              _selectedDate!.day,
                            ) ==
                            dateOnly;
                    final itemsForDate = _getItemsForDate(date);
                    final hasItems = itemsForDate.isNotEmpty;
                    final dateColor = hasItems ? _getDateColor(date) : null;

                    return Expanded(
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selectedDate = date;
                          });
                        },
                        child: Container(
                          margin: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? dateColor?.withValues(alpha: 0.2) ??
                                      const Color(
                                        0xFF00897B,
                                      ).withValues(alpha: 0.1)
                                : Colors.transparent,
                            border: isToday
                                ? Border.all(
                                    color: const Color(0xFF00897B),
                                    width: 2,
                                  )
                                : isSelected
                                ? Border.all(
                                    color: dateColor ?? const Color(0xFF00897B),
                                    width: 2,
                                  )
                                : null,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                dayNumber.toString(),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isToday || isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isSelected && dateColor != null
                                      ? dateColor
                                      : isToday
                                      ? const Color(0xFF00897B)
                                      : Colors.black87,
                                ),
                              ),
                              if (hasItems)
                                Container(
                                  margin: const EdgeInsets.only(top: 2),
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: dateColor ?? const Color(0xFF00897B),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedDateItems() {
    if (_selectedDate == null) return const SizedBox.shrink();

    final items = _getItemsForDate(_selectedDate!);
    // Normalize to start of day for accurate day comparison
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final selectedDateStart = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
    );
    final difference = selectedDateStart.difference(todayStart).inDays;

    String dateLabel;
    if (difference < 0) {
      dateLabel =
          'Overdue by ${difference.abs()} ${difference.abs() == 1 ? 'day' : 'days'}';
    } else if (difference == 0) {
      dateLabel = 'Due Today';
    } else if (difference == 1) {
      dateLabel = 'Due Tomorrow';
    } else {
      dateLabel = 'Due on ${_formatDate(_selectedDate!)}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
          ),
          child: Row(
            children: [
              Icon(Icons.calendar_today, size: 20, color: Colors.grey[700]),
              const SizedBox(width: 8),
              Text(
                dateLabel,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (items.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getDateColor(_selectedDate!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${items.length} ${items.length == 1 ? 'item' : 'items'}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 48,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No items due on this date',
                        style: TextStyle(color: Colors.grey[600], fontSize: 14),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final title = (item['title'] ?? 'Untitled Item').toString();
                    final returnDate = _parseDate(item['returnDate']);
                    final itemType = (item['type'] ?? 'borrow').toString();
                    final isRental = itemType == 'rental';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _getDateColor(
                              _selectedDate!,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            isRental
                                ? Icons.home_outlined
                                : Icons.inventory_2_outlined,
                            color: _getDateColor(_selectedDate!),
                            size: 20,
                          ),
                        ),
                        title: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (isRental)
                              Container(
                                margin: const EdgeInsets.only(bottom: 4),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Rental',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue[700],
                                  ),
                                ),
                              )
                            else
                              Container(
                                margin: const EdgeInsets.only(bottom: 4),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Borrow',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.green[700],
                                  ),
                                ),
                              ),
                            if (returnDate != null)
                              Text(
                                'Due at ${returnDate.hour.toString().padLeft(2, '0')}:${returnDate.minute.toString().padLeft(2, '0')}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.notifications_outlined),
                          onPressed: () async {
                            final itemId = (item['id'] ?? '').toString();
                            try {
                              await LocalNotificationsService().scheduleNudge(
                                itemId: itemId,
                                itemTitle: title,
                              );
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Reminder scheduled'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error: ${e.toString()}'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                          tooltip: 'Set reminder',
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _getMonthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month - 1];
  }

  String _formatDate(DateTime date) {
    return '${_getMonthName(date.month)} ${date.day}, ${date.year}';
  }
}
