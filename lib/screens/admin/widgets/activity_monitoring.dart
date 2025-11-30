import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../providers/admin_provider.dart';

class ActivityMonitoringTab extends StatefulWidget {
  const ActivityMonitoringTab({super.key});

  @override
  State<ActivityMonitoringTab> createState() => _ActivityMonitoringTabState();
}

class _ActivityMonitoringTabState extends State<ActivityMonitoringTab> {
  int _selectedCategory = 0; // 0 Borrow, 1 Rent, 2 Trade, 3 Give
  String? _filterUserId;
  String? _filterStatus;
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  final TextEditingController _userSearchController = TextEditingController();
  List<Map<String, dynamic>> _suspiciousActivities = [];

  @override
  void initState() {
    super.initState();
    _checkSuspiciousActivities();
  }

  @override
  void dispose() {
    _userSearchController.dispose();
    super.dispose();
  }

  Future<void> _checkSuspiciousActivities() async {
    // Check for suspicious patterns across all activity types
    final admin = Provider.of<AdminProvider>(context, listen: false);
    try {
      final suspicious = <Map<String, dynamic>>[];

      // Check all activity types
      final streams = [
        (admin.borrowRequestsStream, 'Borrow', 'borrowerId'),
        (admin.rentalRequestsStream, 'Rent', 'renterId'),
        (admin.tradeOffersStream, 'Trade', 'fromUserId'),
        (admin.giveawayClaimsStream, 'Give', 'claimantId'),
      ];

      for (final streamInfo in streams) {
        final stream = streamInfo.$1;
        final activityType = streamInfo.$2;
        final userIdField = streamInfo.$3;

        try {
          final snap = await stream.first;
          final Map<String, int> userActivityCount = {}; // Only non-declined
          final Map<String, int> userTotalCount = {}; // All activities
          final Map<String, Map<String, int>> userStatusCounts =
              {}; // Status breakdown
          final Map<String, List<DateTime>> userActivityTimes = {};

          // Group by user and track activity times and status
          for (final doc in snap.docs) {
            final data = doc.data();
            final userId = data[userIdField] as String?;
            if (userId != null && userId.isNotEmpty) {
              final status = (data['status'] as String? ?? 'pending')
                  .toLowerCase();

              // Count all activities
              userTotalCount[userId] = (userTotalCount[userId] ?? 0) + 1;

              // Initialize status tracking
              if (userStatusCounts[userId] == null) {
                userStatusCounts[userId] = {
                  'accepted': 0,
                  'declined': 0,
                  'rejected': 0,
                  'cancelled': 0,
                  'pending': 0,
                  'other': 0,
                };
              }

              // Track status counts
              if (userStatusCounts[userId]!.containsKey(status)) {
                userStatusCounts[userId]![status] =
                    (userStatusCounts[userId]![status] ?? 0) + 1;
              } else {
                userStatusCounts[userId]!['other'] =
                    (userStatusCounts[userId]!['other'] ?? 0) + 1;
              }

              // Only count non-declined activities for threshold
              if (status != 'declined' &&
                  status != 'rejected' &&
                  status != 'cancelled') {
                userActivityCount[userId] =
                    (userActivityCount[userId] ?? 0) + 1;

                // Track when non-declined activities occurred
                final createdAt = data['createdAt'];
                if (createdAt is Timestamp) {
                  if (userActivityTimes[userId] == null) {
                    userActivityTimes[userId] = [];
                  }
                  userActivityTimes[userId]!.add(createdAt.toDate());
                }
              }
            }
          }

          // Check for high frequency (more than 10 non-declined activities)
          for (final entry in userActivityCount.entries) {
            final userId = entry.key;
            final count = entry.value; // Non-declined count
            final totalCount = userTotalCount[userId] ?? 0;
            final statusCounts = userStatusCounts[userId] ?? {};

            if (count > 10) {
              // Check if activities happened in a short time window (last hour)
              final now = DateTime.now();
              final oneHourAgo = now.subtract(const Duration(hours: 1));
              final recentActivities =
                  userActivityTimes[userId]
                      ?.where((time) => time.isAfter(oneHourAgo))
                      .length ??
                  0;

              // Calculate decline rate
              final declinedCount =
                  (statusCounts['declined'] ?? 0) +
                  (statusCounts['rejected'] ?? 0) +
                  (statusCounts['cancelled'] ?? 0);
              final acceptedCount = statusCounts['accepted'] ?? 0;
              final pendingCount = statusCounts['pending'] ?? 0;
              final declineRate = totalCount > 0
                  ? (declinedCount / totalCount * 100).round()
                  : 0;

              String message;
              if (recentActivities > 5) {
                message =
                    'User has $count active $activityType activities ($recentActivities in last hour) - possible spam';
              } else if (declineRate > 70) {
                message =
                    'User has $count active $activityType activities (${declineRate}% declined) - high rejection rate';
              } else {
                message =
                    'User has $count active $activityType activities - unusually high frequency';
              }

              // Try to get user name
              String userName = 'User ID: ${userId.substring(0, 8)}...';
              try {
                final userDoc = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(userId)
                    .get();
                if (userDoc.exists) {
                  final userData = userDoc.data();
                  final firstName = userData?['firstName'] ?? '';
                  final lastName = userData?['lastName'] ?? '';
                  final email = userData?['email'] ?? '';
                  if (firstName.isNotEmpty || lastName.isNotEmpty) {
                    userName = '$firstName $lastName'.trim();
                  } else if (email.isNotEmpty) {
                    userName = email;
                  }
                }
              } catch (_) {
                // Keep default userName if fetch fails
              }

              suspicious.add({
                'type': 'high_frequency',
                'activityType': activityType,
                'userId': userId,
                'userName': userName,
                'count': count, // Non-declined count
                'totalCount': totalCount, // All activities
                'acceptedCount': acceptedCount,
                'declinedCount': declinedCount,
                'pendingCount': pendingCount,
                'declineRate': declineRate,
                'recentCount': recentActivities,
                'message': message,
              });
            }
          }
        } catch (e) {
          // Continue checking other activity types if one fails
        }
      }

      if (mounted) {
        setState(() => _suspiciousActivities = suspicious);
      }
    } catch (e) {
      // Error checking - ignore
    }
  }

  Future<void> _exportActivities() async {
    try {
      final admin = Provider.of<AdminProvider>(context, listen: false);

      // Get current activities based on category
      QuerySnapshot<Map<String, dynamic>>? snapshot;
      switch (_selectedCategory) {
        case 0:
          snapshot = await admin.borrowRequestsStream.first;
          break;
        case 1:
          snapshot = await admin.rentalRequestsStream.first;
          break;
        case 2:
          snapshot = await admin.tradeOffersStream.first;
          break;
        case 3:
          snapshot = await admin.giveawayClaimsStream.first;
          break;
      }

      if (snapshot == null) return;

      final csv = StringBuffer();
      csv.writeln('Type,User,Item,Status,Date');

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final type = ['Borrow', 'Rent', 'Trade', 'Give'][_selectedCategory];
        final user =
            data['borrowerName'] ??
            data['renterName'] ??
            data['fromUserName'] ??
            data['claimantName'] ??
            'Unknown';
        final item = data['itemTitle'] ?? 'Item';
        final status = data['status'] ?? 'pending';
        final date = data['createdAt'] is Timestamp
            ? DateFormat(
                'yyyy-MM-dd HH:mm',
              ).format((data['createdAt'] as Timestamp).toDate())
            : '';

        csv.writeln('$type,$user,$item,$status,$date');
      }

      await Clipboard.setData(ClipboardData(text: csv.toString()));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Activities exported to CSV and copied to clipboard!',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error exporting: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [const Color(0xFF00897B), const Color(0xFF00695C)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00897B).withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.monitor_heart,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Activity Monitoring',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Track all transactions across the platform',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.download, color: Colors.white),
                  onPressed: _exportActivities,
                  tooltip: 'Export activities',
                ),
                IconButton(
                  icon: const Icon(Icons.filter_list, color: Colors.white),
                  onPressed: () => _showFiltersDialog(context),
                  tooltip: 'Filter activities',
                ),
              ],
            ),
          ),
          if (_suspiciousActivities.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red[300]!),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_suspiciousActivities.length} suspicious activity pattern(s) detected',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _showSuspiciousActivities(context),
                    child: const Text('View Details'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          _ActivityCategoryBar(
            onCategoryChanged: (index) {
              setState(() => _selectedCategory = index);
            },
          ),
          if (_filterUserId != null ||
              _filterStatus != null ||
              _filterStartDate != null)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                children: [
                  const Icon(Icons.filter_alt, color: Colors.blue, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Filters active: ${_getActiveFiltersText()}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _filterUserId = null;
                        _filterStatus = null;
                        _filterStartDate = null;
                        _filterEndDate = null;
                      });
                    },
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Expanded(
            child: _getActivitySection(
              context,
              filterStatus: _filterStatus,
              filterStartDate: _filterStartDate,
              filterEndDate: _filterEndDate,
            ),
          ),
        ],
      ),
    );
  }

  Widget _getActivitySection(
    BuildContext context, {
    String? filterStatus,
    DateTime? filterStartDate,
    DateTime? filterEndDate,
  }) {
    switch (_selectedCategory) {
      case 0:
        return _BorrowActivitiesSection(
          filterStatus: filterStatus,
          filterStartDate: filterStartDate,
          filterEndDate: filterEndDate,
        );
      case 1:
        return _RentalActivitiesSection(
          filterStatus: filterStatus,
          filterStartDate: filterStartDate,
          filterEndDate: filterEndDate,
        );
      case 2:
        return _TradeActivitiesSection(
          filterStatus: filterStatus,
          filterStartDate: filterStartDate,
          filterEndDate: filterEndDate,
        );
      case 3:
        return _GiveawayActivitiesSection(
          filterStatus: filterStatus,
          filterStartDate: filterStartDate,
          filterEndDate: filterEndDate,
        );
      default:
        return _BorrowActivitiesSection(
          filterStatus: filterStatus,
          filterStartDate: filterStartDate,
          filterEndDate: filterEndDate,
        );
    }
  }

  String _getActiveFiltersText() {
    final filters = <String>[];
    if (_filterUserId != null) filters.add('User');
    if (_filterStatus != null) filters.add('Status: $_filterStatus');
    if (_filterStartDate != null) filters.add('Date range');
    return filters.isEmpty ? 'None' : filters.join(', ');
  }

  Future<void> _showFiltersDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Filter Activities'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _userSearchController,
                  decoration: const InputDecoration(
                    labelText: 'User ID or Email',
                    hintText: 'Enter user identifier',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _filterStatus,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'pending', child: Text('Pending')),
                    DropdownMenuItem(
                      value: 'accepted',
                      child: Text('Accepted'),
                    ),
                    DropdownMenuItem(
                      value: 'declined',
                      child: Text('Declined'),
                    ),
                  ],
                  onChanged: (value) {
                    setDialogState(() => _filterStatus = value);
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _filterStartDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (date != null) {
                            setDialogState(() => _filterStartDate = date);
                          }
                        },
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(
                          _filterStartDate != null
                              ? DateFormat(
                                  'MMM dd, yyyy',
                                ).format(_filterStartDate!)
                              : 'Start Date',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _filterEndDate ?? DateTime.now(),
                            firstDate: _filterStartDate ?? DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (date != null) {
                            setDialogState(() => _filterEndDate = date);
                          }
                        },
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(
                          _filterEndDate != null
                              ? DateFormat(
                                  'MMM dd, yyyy',
                                ).format(_filterEndDate!)
                              : 'End Date',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                setState(() {
                  _filterUserId = _userSearchController.text.trim().isEmpty
                      ? null
                      : _userSearchController.text.trim();
                });
                Navigator.pop(context);
              },
              child: const Text('Apply Filters'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSuspiciousActivities(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('Suspicious Activities'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: _suspiciousActivities.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('No suspicious activities detected.'),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _suspiciousActivities.length,
                  itemBuilder: (context, index) {
                    final activity = _suspiciousActivities[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.flag,
                                  color: Colors.red,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    activity['userName'] ?? 'Unknown User',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.orange),
                                  ),
                                  child: Text(
                                    activity['activityType'] ?? 'Activity',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.orange[700],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              activity['message'] ?? 'Suspicious activity',
                              style: const TextStyle(fontSize: 13),
                            ),
                            const SizedBox(height: 8),
                            // Status breakdown
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                _InfoChip(
                                  icon: Icons.check_circle,
                                  label: 'Active: ${activity['count'] ?? 0}',
                                  color: Colors.green,
                                ),
                                if (activity['totalCount'] != null &&
                                    (activity['totalCount'] as int) >
                                        (activity['count'] as int))
                                  _InfoChip(
                                    icon: Icons.cancel,
                                    label:
                                        'Total: ${activity['totalCount'] ?? 0}',
                                    color: Colors.blue,
                                  ),
                                if (activity['acceptedCount'] != null &&
                                    (activity['acceptedCount'] as int) > 0)
                                  _InfoChip(
                                    icon: Icons.thumb_up,
                                    label:
                                        'Accepted: ${activity['acceptedCount']}',
                                    color: Colors.green,
                                  ),
                                if (activity['declinedCount'] != null &&
                                    (activity['declinedCount'] as int) > 0)
                                  _InfoChip(
                                    icon: Icons.thumb_down,
                                    label:
                                        'Declined: ${activity['declinedCount']}',
                                    color: Colors.red,
                                  ),
                                if (activity['pendingCount'] != null &&
                                    (activity['pendingCount'] as int) > 0)
                                  _InfoChip(
                                    icon: Icons.hourglass_empty,
                                    label:
                                        'Pending: ${activity['pendingCount']}',
                                    color: Colors.orange,
                                  ),
                                if (activity['recentCount'] != null &&
                                    (activity['recentCount'] as int) > 0)
                                  _InfoChip(
                                    icon: Icons.access_time,
                                    label: 'Recent: ${activity['recentCount']}',
                                    color: Colors.purple,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _InfoChip({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? Colors.blue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: chipColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: chipColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: chipColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityCategoryBar extends StatefulWidget {
  final ValueChanged<int> onCategoryChanged;

  const _ActivityCategoryBar({required this.onCategoryChanged});

  @override
  State<_ActivityCategoryBar> createState() => _ActivityCategoryBarState();
}

class _ActivityCategoryBarState extends State<_ActivityCategoryBar> {
  int _index = 0; // 0 Borrow, 1 Rent, 2 Trade, 3 Give

  @override
  Widget build(BuildContext context) {
    final entries = const [
      (Icons.handshake_outlined, 'Borrow'),
      (Icons.attach_money_outlined, 'Rent'),
      (Icons.compare_arrows_outlined, 'Trade'),
      (Icons.card_giftcard_outlined, 'Give'),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: List.generate(entries.length, (i) {
        final selected = _index == i;
        final e = entries[i];
        return Container(
          decoration: selected
              ? BoxDecoration(
                  gradient: LinearGradient(
                    colors: [const Color(0xFF00897B), const Color(0xFF00695C)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00897B).withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                )
              : BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey[300]!, width: 1),
                ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() => _index = i);
                widget.onCategoryChanged(i);
              },
              borderRadius: BorderRadius.circular(20),
              splashColor: selected
                  ? Colors.white.withOpacity(0.2)
                  : const Color(0xFF00897B).withOpacity(0.1),
              highlightColor: selected
                  ? Colors.white.withOpacity(0.1)
                  : const Color(0xFF00897B).withOpacity(0.05),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      e.$1,
                      size: 18,
                      color: selected ? Colors.white : Colors.black87,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      e.$2,
                      style: TextStyle(
                        color: selected ? Colors.white : Colors.black87,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _BorrowActivitiesSection extends StatelessWidget {
  final String? filterStatus;
  final DateTime? filterStartDate;
  final DateTime? filterEndDate;
  const _BorrowActivitiesSection({
    this.filterStatus,
    this.filterStartDate,
    this.filterEndDate,
  });
  @override
  Widget build(BuildContext context) {
    final admin = Provider.of<AdminProvider>(context, listen: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.handshake_outlined),
            SizedBox(width: 8),
            Text(
              'Borrow Activities',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: admin.borrowRequestsStream,
            builder: (context, snapshot) {
              var docs = snapshot.data?.docs ?? [];

              // Apply filters
              if (filterStatus != null) {
                docs = docs.where((doc) {
                  return (doc.data()['status'] ?? '') == filterStatus;
                }).toList();
              }
              if (filterStartDate != null || filterEndDate != null) {
                docs = docs.where((doc) {
                  final createdAt = doc.data()['createdAt'];
                  if (createdAt is! Timestamp) return false;
                  final date = createdAt.toDate();
                  if (filterStartDate != null &&
                      date.isBefore(filterStartDate!)) {
                    return false;
                  }
                  if (filterEndDate != null && date.isAfter(filterEndDate!)) {
                    return false;
                  }
                  return true;
                }).toList();
              }

              if (docs.isEmpty) {
                return Center(
                  child: Text(
                    'No borrow activities yet',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                );
              }
              return ListView.separated(
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final d = docs[index].data();
                  final title = (d['itemTitle'] ?? 'Item') as String;
                  final borrower = (d['borrowerName'] ?? '') as String;
                  final lender = (d['lenderName'] ?? '') as String;
                  final status = (d['status'] ?? 'pending') as String;
                  DateTime? ts;
                  final createdAt = d['createdAt'];
                  if (createdAt is Timestamp) ts = createdAt.toDate();

                  return _ActivityCard(
                    title: borrower.isNotEmpty
                        ? '$borrower → $lender'
                        : 'Borrow Request',
                    subtitle: title,
                    status: status,
                    timestamp: ts,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RentalActivitiesSection extends StatelessWidget {
  final String? filterStatus;
  final DateTime? filterStartDate;
  final DateTime? filterEndDate;
  const _RentalActivitiesSection({
    this.filterStatus,
    this.filterStartDate,
    this.filterEndDate,
  });
  @override
  Widget build(BuildContext context) {
    final admin = Provider.of<AdminProvider>(context, listen: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.attach_money_outlined),
            SizedBox(width: 8),
            Text(
              'Rental Activities',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: admin.rentalRequestsStream,
            builder: (context, snapshot) {
              var docs = snapshot.data?.docs ?? [];

              // Apply filters
              if (filterStatus != null) {
                docs = docs.where((doc) {
                  return (doc.data()['status'] ?? '') == filterStatus;
                }).toList();
              }
              if (filterStartDate != null || filterEndDate != null) {
                docs = docs.where((doc) {
                  final createdAt = doc.data()['createdAt'];
                  if (createdAt is! Timestamp) return false;
                  final date = createdAt.toDate();
                  if (filterStartDate != null &&
                      date.isBefore(filterStartDate!)) {
                    return false;
                  }
                  if (filterEndDate != null && date.isAfter(filterEndDate!)) {
                    return false;
                  }
                  return true;
                }).toList();
              }

              if (docs.isEmpty) {
                return Center(
                  child: Text(
                    'No rental activities yet',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                );
              }
              return ListView.separated(
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final d = docs[index].data();
                  final itemTitle = (d['itemTitle'] ?? 'Item') as String;
                  final renterId = (d['renterId'] ?? '') as String;
                  final ownerId = (d['ownerId'] ?? '') as String;
                  final status = (d['status'] ?? 'pending') as String;
                  DateTime? ts;
                  final createdAt = d['createdAt'];
                  if (createdAt is Timestamp) ts = createdAt.toDate();

                  return _RentalActivityCard(
                    itemTitle: itemTitle,
                    renterId: renterId,
                    ownerId: ownerId,
                    status: status,
                    timestamp: ts,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// New widget to fetch and display user names
class _RentalActivityCard extends StatelessWidget {
  final String itemTitle;
  final String renterId;
  final String ownerId;
  final String status;
  final DateTime? timestamp;

  const _RentalActivityCard({
    required this.itemTitle,
    required this.renterId,
    required this.ownerId,
    required this.status,
    required this.timestamp,
  });

  Future<Map<String, String>> _fetchUserNames() async {
    final db = FirebaseFirestore.instance;
    String renterName = 'Renter';
    String ownerName = 'Owner';

    try {
      // Fetch renter name
      if (renterId.isNotEmpty) {
        final renterDoc = await db.collection('users').doc(renterId).get();
        if (renterDoc.exists) {
          final renterData = renterDoc.data();
          final firstName = renterData?['firstName'] ?? '';
          final lastName = renterData?['lastName'] ?? '';
          final fullName = '$firstName $lastName'.trim();
          if (fullName.isNotEmpty) {
            renterName = fullName;
          }
        }
      }

      // Fetch owner name
      if (ownerId.isNotEmpty) {
        final ownerDoc = await db.collection('users').doc(ownerId).get();
        if (ownerDoc.exists) {
          final ownerData = ownerDoc.data();
          final firstName = ownerData?['firstName'] ?? '';
          final lastName = ownerData?['lastName'] ?? '';
          final fullName = '$firstName $lastName'.trim();
          if (fullName.isNotEmpty) {
            ownerName = fullName;
          }
        }
      }
    } catch (e) {
      // If fetching fails, use default names
    }

    return {'renterName': renterName, 'ownerName': ownerName};
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, String>>(
      future: _fetchUserNames(),
      builder: (context, snapshot) {
        final names =
            snapshot.data ?? {'renterName': 'Renter', 'ownerName': 'Owner'};
        final renterName = names['renterName']!;
        final ownerName = names['ownerName']!;

        return _ActivityCard(
          title: '$renterName → $ownerName',
          subtitle: itemTitle,
          status: status,
          timestamp: timestamp,
        );
      },
    );
  }
}

class _TradeActivitiesSection extends StatelessWidget {
  final String? filterStatus;
  final DateTime? filterStartDate;
  final DateTime? filterEndDate;
  const _TradeActivitiesSection({
    this.filterStatus,
    this.filterStartDate,
    this.filterEndDate,
  });
  @override
  Widget build(BuildContext context) {
    final admin = Provider.of<AdminProvider>(context, listen: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.compare_arrows_outlined),
            SizedBox(width: 8),
            Text(
              'Trade Activities',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: admin.tradeOffersStream,
            builder: (context, snapshot) {
              var docs = snapshot.data?.docs ?? [];

              // Apply filters
              if (filterStatus != null) {
                docs = docs.where((doc) {
                  return (doc.data()['status'] ?? '') == filterStatus;
                }).toList();
              }
              if (filterStartDate != null || filterEndDate != null) {
                docs = docs.where((doc) {
                  final createdAt = doc.data()['createdAt'];
                  if (createdAt is! Timestamp) return false;
                  final date = createdAt.toDate();
                  if (filterStartDate != null &&
                      date.isBefore(filterStartDate!)) {
                    return false;
                  }
                  if (filterEndDate != null && date.isAfter(filterEndDate!)) {
                    return false;
                  }
                  return true;
                }).toList();
              }

              if (docs.isEmpty) {
                return Center(
                  child: Text(
                    'No trade activities yet',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                );
              }
              return ListView.separated(
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final d = docs[index].data();
                  final fromUserName = (d['fromUserName'] ?? 'User') as String;
                  final toUserName = (d['toUserName'] ?? 'User') as String;
                  final status = (d['status'] ?? 'pending') as String;
                  final offeredItemName =
                      (d['offeredItemName'] ?? 'Item') as String;
                  DateTime? ts;
                  final createdAt = d['createdAt'];
                  if (createdAt is Timestamp) ts = createdAt.toDate();

                  return _ActivityCard(
                    title: '$fromUserName ↔ $toUserName',
                    subtitle: offeredItemName,
                    status: status,
                    timestamp: ts,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _GiveawayActivitiesSection extends StatelessWidget {
  final String? filterStatus;
  final DateTime? filterStartDate;
  final DateTime? filterEndDate;
  const _GiveawayActivitiesSection({
    this.filterStatus,
    this.filterStartDate,
    this.filterEndDate,
  });
  @override
  Widget build(BuildContext context) {
    final admin = Provider.of<AdminProvider>(context, listen: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.card_giftcard_outlined),
            SizedBox(width: 8),
            Text(
              'Giveaway Activities',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: admin.giveawayClaimsStream,
            builder: (context, snapshot) {
              var docs = snapshot.data?.docs ?? [];

              // Apply filters
              if (filterStatus != null) {
                docs = docs.where((doc) {
                  return (doc.data()['status'] ?? '') == filterStatus;
                }).toList();
              }
              if (filterStartDate != null || filterEndDate != null) {
                docs = docs.where((doc) {
                  final createdAt = doc.data()['createdAt'];
                  if (createdAt is! Timestamp) return false;
                  final date = createdAt.toDate();
                  if (filterStartDate != null &&
                      date.isBefore(filterStartDate!)) {
                    return false;
                  }
                  if (filterEndDate != null && date.isAfter(filterEndDate!)) {
                    return false;
                  }
                  return true;
                }).toList();
              }

              if (docs.isEmpty) {
                return Center(
                  child: Text(
                    'No giveaway activities yet',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                );
              }
              return ListView.separated(
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final d = docs[index].data();
                  final claimantName = (d['claimantName'] ?? 'User') as String;
                  final donorName = (d['donorName'] ?? 'Donor') as String;
                  final status = (d['status'] ?? 'pending') as String;
                  final itemTitle =
                      (d['itemTitle'] ?? (d['giveawayTitle'] ?? 'Item'))
                          as String;
                  DateTime? ts;
                  final createdAt = d['createdAt'];
                  if (createdAt is Timestamp) ts = createdAt.toDate();

                  return _ActivityCard(
                    title: '$claimantName → $donorName',
                    subtitle: itemTitle,
                    status: status,
                    timestamp: ts,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ActivityCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String status; // pending | accepted | declined
  final DateTime? timestamp;
  const _ActivityCard({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.timestamp,
  });

  @override
  Widget build(BuildContext context) {
    final Color badgeColor;
    final String badgeText;
    switch (status.toLowerCase()) {
      case 'accepted':
      case 'approved':
      case 'active':
      case 'completed':
        badgeColor = const Color(0xFF1E88E5);
        badgeText = 'active';
        break;
      case 'declined':
      case 'rejected':
      case 'cancelled':
        badgeColor = const Color(0xFFE53935);
        badgeText = 'declined';
        break;
      default:
        badgeColor = const Color(0xFFFB8C00);
        badgeText = 'pending';
    }

    final timeText = timestamp != null
        ? '${timestamp!.year.toString().padLeft(4, '0')}-${timestamp!.month.toString().padLeft(2, '0')}-${timestamp!.day.toString().padLeft(2, '0')} ${timestamp!.hour.toString().padLeft(2, '0')}:${timestamp!.minute.toString().padLeft(2, '0')}'
        : '';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, const Color(0xFFF5F7FA)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          const Icon(Icons.swap_horiz, color: Colors.black54),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: badgeColor.withOpacity(0.3)),
                ),
                child: Text(
                  badgeText.toUpperCase(),
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                timeText,
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
