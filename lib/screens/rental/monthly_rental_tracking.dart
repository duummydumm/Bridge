import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/firestore_service.dart';
import '../../providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'active_rental_detail_screen.dart';
import '../../reusable_widgets/bottom_nav_bar_widget.dart';

class MonthlyRentalTrackingScreen extends StatefulWidget {
  const MonthlyRentalTrackingScreen({super.key});

  @override
  State<MonthlyRentalTrackingScreen> createState() =>
      _MonthlyRentalTrackingScreenState();
}

class _MonthlyRentalTrackingScreenState
    extends State<MonthlyRentalTrackingScreen>
    with SingleTickerProviderStateMixin {
  final FirestoreService _firestoreService = FirestoreService();
  late TabController _tabController;

  List<Map<String, dynamic>> _monthlyRentals = [];
  List<Map<String, dynamic>> _allPayments = [];
  bool _isLoading = true;
  bool _viewingAsOwner = false;

  // Statistics
  int _totalActiveRentals = 0;
  double _totalMonthlyIncome = 0.0;
  double _totalMonthlyExpenses = 0.0;
  int _upcomingPaymentsCount = 0;
  int _overduePaymentsCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
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

      // Load rentals as both owner and renter
      final ownerRentals = await _firestoreService.getRentalRequestsByUser(
        userId,
        asOwner: true,
      );
      final renterRentals = await _firestoreService.getRentalRequestsByUser(
        userId,
        asOwner: false,
      );

      // Filter for monthly rentals (isLongTerm = true) and active/returned status
      final monthlyOwnerRentals = ownerRentals.where((req) {
        final isLongTerm = req['isLongTerm'] as bool? ?? false;
        final status = (req['status'] ?? 'requested').toString().toLowerCase();
        return isLongTerm && (status == 'active' || status == 'returned');
      }).toList();

      final monthlyRenterRentals = renterRentals.where((req) {
        final isLongTerm = req['isLongTerm'] as bool? ?? false;
        final status = (req['status'] ?? 'requested').toString().toLowerCase();
        return isLongTerm && (status == 'active' || status == 'returned');
      }).toList();

      // Auto-detect view based on which has more rentals
      final showAsOwner =
          monthlyOwnerRentals.length >= monthlyRenterRentals.length;
      final selectedRentals = showAsOwner
          ? monthlyOwnerRentals
          : monthlyRenterRentals;

      // Enrich rental data
      final enrichedRentals = <Map<String, dynamic>>[];
      final allPaymentsList = <Map<String, dynamic>>[];

      for (final rental in selectedRentals) {
        final enrichedRental = Map<String, dynamic>.from(rental);

        // Get item title from listing
        final listingId = rental['listingId'] as String?;
        if (listingId != null) {
          try {
            final listing = await _firestoreService.getRentalListing(listingId);
            if (listing != null) {
              enrichedRental['itemTitle'] = listing['title'] as String?;
            }
          } catch (_) {}
        }
        enrichedRental['itemTitle'] ??= 'Rental Item';

        // Get names
        if (showAsOwner) {
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
        } else {
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
        }

        // Load payments for this rental
        final requestId = rental['id'] as String? ?? '';
        if (requestId.isNotEmpty) {
          try {
            final payments = await _firestoreService.getPaymentsForRequest(
              requestId,
            );
            for (final payment in payments) {
              payment['rentalRequestId'] = requestId;
              payment['itemTitle'] = enrichedRental['itemTitle'];
              allPaymentsList.add(payment);
            }
          } catch (_) {}
        }

        enrichedRentals.add(enrichedRental);
      }

      // Calculate statistics
      _calculateStatistics(enrichedRentals, allPaymentsList, showAsOwner);

      if (mounted) {
        setState(() {
          _monthlyRentals = enrichedRentals;
          _allPayments = allPaymentsList;
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
            content: Text('Error loading data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _calculateStatistics(
    List<Map<String, dynamic>> rentals,
    List<Map<String, dynamic>> payments,
    bool asOwner,
  ) {
    _totalActiveRentals = rentals.length;
    _totalMonthlyIncome = 0.0;
    _totalMonthlyExpenses = 0.0;
    _upcomingPaymentsCount = 0;
    _overduePaymentsCount = 0;

    final now = DateTime.now();
    final nextWeek = now.add(const Duration(days: 7));

    for (final rental in rentals) {
      final monthlyAmount =
          (rental['monthlyPaymentAmount'] as num?)?.toDouble() ?? 0.0;
      final nextPaymentDue = (rental['nextPaymentDueDate'] as Timestamp?)
          ?.toDate();
      final status = (rental['status'] ?? 'active').toString().toLowerCase();

      if (status == 'active') {
        if (asOwner) {
          _totalMonthlyIncome += monthlyAmount;
        } else {
          _totalMonthlyExpenses += monthlyAmount;
        }

        if (nextPaymentDue != null) {
          if (nextPaymentDue.isBefore(now)) {
            _overduePaymentsCount++;
          } else if (nextPaymentDue.isBefore(nextWeek)) {
            _upcomingPaymentsCount++;
          }
        }
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

  int _daysUntil(DateTime date) {
    return date.difference(DateTime.now()).inDays;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Monthly Rental Tracking'),
        backgroundColor: const Color(0xFF00897B),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard), text: 'Overview'),
            Tab(icon: Icon(Icons.calendar_today), text: 'Schedule'),
            Tab(icon: Icon(Icons.history), text: 'History'),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _viewingAsOwner ? Icons.person_outline : Icons.store_outlined,
            ),
            tooltip: _viewingAsOwner ? 'View as Renter' : 'View as Owner',
            onPressed: () {
              setState(() {
                _viewingAsOwner = !_viewingAsOwner;
              });
              _loadData();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildOverviewTab(),
                  _buildPaymentScheduleTab(),
                  _buildPaymentHistoryTab(),
                ],
              ),
            ),
      bottomNavigationBar: BottomNavBarWidget(
        selectedIndex: 1,
        onTap: (_) {},
        navigationContext: context,
      ),
    );
  }

  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary Cards
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  'Active Rentals',
                  '$_totalActiveRentals',
                  Icons.home_outlined,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  _viewingAsOwner ? 'Monthly Income' : 'Monthly Expenses',
                  _formatCurrency(
                    _viewingAsOwner
                        ? _totalMonthlyIncome
                        : _totalMonthlyExpenses,
                  ),
                  Icons.attach_money,
                  Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  'Upcoming (7 days)',
                  '$_upcomingPaymentsCount',
                  Icons.schedule,
                  Colors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  'Overdue',
                  '$_overduePaymentsCount',
                  Icons.warning,
                  Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Upcoming Payments Section
          if (_upcomingPaymentsCount > 0 || _overduePaymentsCount > 0) ...[
            Text(
              'Payment Alerts',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 12),
            ..._getUpcomingAndOverduePayments().map(
              (payment) => _buildPaymentAlertCard(payment),
            ),
          ],
          const SizedBox(height: 24),
          // Recent Payments
          Text(
            'Recent Payments',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 12),
          _allPayments.isEmpty
              ? _buildEmptyState('No payment history yet')
              : Column(
                  children: _allPayments
                      .take(5)
                      .map((payment) => _buildPaymentHistoryItem(payment))
                      .toList(),
                ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _getUpcomingAndOverduePayments() {
    final now = DateTime.now();
    final nextMonth = now.add(const Duration(days: 30));
    final payments = <Map<String, dynamic>>[];

    for (final rental in _monthlyRentals) {
      final status = (rental['status'] ?? 'active').toString().toLowerCase();
      if (status != 'active') continue;

      final nextPaymentDue = (rental['nextPaymentDueDate'] as Timestamp?)
          ?.toDate();
      if (nextPaymentDue == null) continue;

      if (nextPaymentDue.isBefore(nextMonth)) {
        payments.add({
          'rental': rental,
          'dueDate': nextPaymentDue,
          'amount': rental['monthlyPaymentAmount'],
          'isOverdue': nextPaymentDue.isBefore(now),
        });
      }
    }

    payments.sort((a, b) {
      final aDate = a['dueDate'] as DateTime;
      final bDate = b['dueDate'] as DateTime;
      return aDate.compareTo(bDate);
    });

    return payments;
  }

  Widget _buildPaymentAlertCard(Map<String, dynamic> payment) {
    final rental = payment['rental'] as Map<String, dynamic>;
    final dueDate = payment['dueDate'] as DateTime;
    final amount = (payment['amount'] as num?)?.toDouble() ?? 0.0;
    final isOverdue = payment['isOverdue'] as bool;
    final days = _daysUntil(dueDate);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isOverdue ? Colors.red[50] : Colors.orange[50],
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (isOverdue ? Colors.red : Colors.orange).withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isOverdue ? Icons.warning : Icons.schedule,
            color: isOverdue ? Colors.red : Colors.orange,
          ),
        ),
        title: Text(
          rental['itemTitle'] ?? 'Rental Item',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          isOverdue
              ? 'Overdue by ${-days} day${-days != 1 ? 's' : ''}'
              : 'Due in $days day${days != 1 ? 's' : ''}',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _formatCurrency(amount),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isOverdue ? Colors.red[700] : Colors.orange[700],
              ),
            ),
            Text(
              _formatDate(dueDate),
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ),
        onTap: () {
          final requestId = rental['id'] as String?;
          if (requestId != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    ActiveRentalDetailScreen(requestId: requestId),
              ),
            ).then((_) => _loadData());
          }
        },
      ),
    );
  }

  Widget _buildPaymentScheduleTab() {
    final upcomingPayments = _getUpcomingAndOverduePayments();
    final now = DateTime.now();
    final next3Months = <DateTime>[];

    for (int i = 0; i < 3; i++) {
      next3Months.add(DateTime(now.year, now.month + i, 1));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Calendar view for next 3 months
          ...next3Months.map((monthStart) {
            final monthEnd = DateTime(monthStart.year, monthStart.month + 1, 0);
            final monthPayments = upcomingPayments.where((p) {
              final dueDate = p['dueDate'] as DateTime;
              return dueDate.isAfter(
                    monthStart.subtract(const Duration(days: 1)),
                  ) &&
                  dueDate.isBefore(monthEnd.add(const Duration(days: 1)));
            }).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_getMonthName(monthStart.month)} ${monthStart.year}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00897B),
                  ),
                ),
                const SizedBox(height: 12),
                monthPayments.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: Text(
                          'No payments scheduled',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 14,
                          ),
                        ),
                      )
                    : Column(
                        children: monthPayments.map((payment) {
                          return _buildSchedulePaymentItem(payment);
                        }).toList(),
                      ),
                const SizedBox(height: 24),
              ],
            );
          }),
        ],
      ),
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

  Widget _buildSchedulePaymentItem(Map<String, dynamic> payment) {
    final rental = payment['rental'] as Map<String, dynamic>;
    final dueDate = payment['dueDate'] as DateTime;
    final amount = (payment['amount'] as num?)?.toDouble() ?? 0.0;
    final isOverdue = payment['isOverdue'] as bool;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isOverdue ? Colors.red[50] : Colors.white,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: (isOverdue ? Colors.red : Colors.blue).withOpacity(
            0.1,
          ),
          child: Text(
            dueDate.day.toString(),
            style: TextStyle(
              color: isOverdue ? Colors.red[700] : Colors.blue[700],
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          rental['itemTitle'] ?? 'Rental Item',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          _formatDate(dueDate),
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _formatCurrency(amount),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isOverdue ? Colors.red[700] : Colors.blue[700],
              ),
            ),
            if (isOverdue)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'OVERDUE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        onTap: () {
          final requestId = rental['id'] as String?;
          if (requestId != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    ActiveRentalDetailScreen(requestId: requestId),
              ),
            ).then((_) => _loadData());
          }
        },
      ),
    );
  }

  Widget _buildPaymentHistoryTab() {
    if (_allPayments.isEmpty) {
      return _buildEmptyState('No payment history');
    }

    // Sort payments by date (newest first)
    final sortedPayments = List<Map<String, dynamic>>.from(_allPayments)
      ..sort((a, b) {
        final aDate =
            (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime(1970);
        final bDate =
            (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime(1970);
        return bDate.compareTo(aDate);
      });

    // Group by month
    final groupedPayments = <String, List<Map<String, dynamic>>>{};
    for (final payment in sortedPayments) {
      final date =
          (payment['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
      final monthKey = '${date.year}-${date.month.toString().padLeft(2, '0')}';
      groupedPayments.putIfAbsent(monthKey, () => []).add(payment);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: groupedPayments.length,
      itemBuilder: (context, index) {
        final monthKey = groupedPayments.keys.elementAt(index);
        final payments = groupedPayments[monthKey]!;
        final firstDate =
            (payments.first['createdAt'] as Timestamp?)?.toDate() ??
            DateTime.now();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '${_getMonthName(firstDate.month)} ${firstDate.year}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00897B),
                ),
              ),
            ),
            ...payments.map((payment) => _buildPaymentHistoryItem(payment)),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Widget _buildPaymentHistoryItem(Map<String, dynamic> payment) {
    final amount = (payment['amount'] as num?)?.toDouble() ?? 0.0;
    final date =
        (payment['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    final status = (payment['status'] ?? 'succeeded').toString().toLowerCase();
    final itemTitle = payment['itemTitle'] ?? 'Rental Item';
    final isSuccess = status == 'succeeded';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (isSuccess ? Colors.green : Colors.orange).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isSuccess ? Icons.check_circle : Icons.pending,
            color: isSuccess ? Colors.green : Colors.orange,
          ),
        ),
        title: Text(
          itemTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          _formatDate(date),
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _formatCurrency(amount),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isSuccess ? Colors.green[700] : Colors.orange[700],
              ),
            ),
            Text(
              status.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                color: isSuccess ? Colors.green[700] : Colors.orange[700],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}
