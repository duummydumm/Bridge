import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../services/firestore_service.dart';
import '../../services/export_service.dart';
import '../../reusable_widgets/export_format_dialog.dart';

/// Enhanced Admin view of notifications.
///
/// Features:
/// - Mark as read/unread
/// - Mark all as read
/// - Filter by type
/// - Search notifications
/// - Delete notifications
/// - Navigate to related items
/// - Export notifications
/// - Unread count badge
class AdminNotificationsScreen extends StatefulWidget {
  const AdminNotificationsScreen({super.key});

  @override
  State<AdminNotificationsScreen> createState() =>
      _AdminNotificationsScreenState();
}

class _AdminNotificationsScreenState extends State<AdminNotificationsScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final ExportService _exportService = ExportService();
  final TextEditingController _searchController = TextEditingController();
  String? _selectedTypeFilter;
  bool _showUnreadOnly = false;

  // Available notification types for filtering
  final List<String> _notificationTypes = [
    'All',
    'new_user_registration',
    'calamity_donation',
    'calamity_event_created',
    'verification_approved',
    'verification_rejected',
    'violation_issued',
    'account_suspended',
    'account_restored',
    'donate_request',
    'donate_approved',
    'donate_rejected',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _markAsRead(String notificationId) async {
    try {
      await _firestoreService.markNotificationRead(notificationId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notification marked as read'),
            duration: Duration(seconds: 2),
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
  }

  Future<void> _markAsUnread(String notificationId) async {
    try {
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(notificationId)
          .update({'status': 'unread'});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notification marked as unread'),
            duration: Duration(seconds: 2),
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
  }

  Future<void> _markAllAsRead(String userId) async {
    try {
      final db = FirebaseFirestore.instance;
      final snap = await db
          .collection('notifications')
          .where('toUserId', isEqualTo: userId)
          .where('status', isEqualTo: 'unread')
          .limit(500)
          .get();
      final batch = db.batch();
      for (final d in snap.docs) {
        batch.update(d.reference, {'status': 'read'});
      }
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Marked ${snap.docs.length} notifications as read'),
            duration: const Duration(seconds: 2),
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
  }

  Future<void> _deleteNotification(String notificationId) async {
    try {
      await FirebaseFirestore.instance
          .collection('notifications')
          .doc(notificationId)
          .delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notification deleted'),
            duration: Duration(seconds: 2),
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
  }

  Future<void> _clearReadNotifications(String userId) async {
    try {
      final db = FirebaseFirestore.instance;
      final snap = await db
          .collection('notifications')
          .where('toUserId', isEqualTo: userId)
          .where('status', isEqualTo: 'read')
          .limit(200)
          .get();
      final batch = db.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cleared ${snap.docs.length} read notifications'),
            duration: const Duration(seconds: 2),
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
  }

  void _handleNotificationTap(
    BuildContext context,
    Map<String, dynamic> data,
    String type,
  ) {
    // Mark as read on tap
    final notificationId = data['notificationId'] as String?;
    if (notificationId != null && data['status'] == 'unread') {
      _markAsRead(notificationId);
    }

    // Navigate based on type
    if (type == 'calamity_donation') {
      final eventId = data['eventId'] as String?;
      if (eventId != null && eventId.isNotEmpty) {
        Navigator.of(context).pushNamed(
          '/admin/calamity/event-detail',
          arguments: {'eventId': eventId},
        );
      }
    } else if (type == 'calamity_event_created') {
      final eventId = data['eventId'] as String?;
      if (eventId != null && eventId.isNotEmpty) {
        Navigator.of(context).pushNamed(
          '/admin/calamity/event-detail',
          arguments: {'eventId': eventId},
        );
      }
    } else if (type == 'new_user_registration') {
      // Navigate to user verification board
      Navigator.of(context).pushNamed('/admin', arguments: {'tab': 0});
    } else if (type == 'verification_approved' ||
        type == 'verification_rejected') {
      // Navigate to user verification board
      final userId = data['userId'] as String?;
      if (userId != null) {
        // Could navigate to user detail in account management
        Navigator.of(context).pushNamed('/admin', arguments: {'tab': 'users'});
      }
    } else if (type == 'violation_issued' ||
        type == 'account_suspended' ||
        type == 'account_restored') {
      final userId = data['userId'] as String?;
      if (userId != null) {
        // Navigate to account management
        Navigator.of(context).pushNamed('/admin', arguments: {'tab': 'users'});
      }
    }
  }

  Future<void> _exportNotifications(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> notifications,
  ) async {
    final format = await ExportFormatDialog.show(
      context,
      title: 'Export Notifications',
      subtitle:
          'Select export format for ${notifications.length} notifications',
    );
    if (format == null) return;

    try {
      String result = '';
      if (format == ExportFormat.csv || format == ExportFormat.json) {
        result = await _exportService.exportNotifications(
          format: format,
          notifications: notifications,
        );
        // Copy to clipboard
        await Clipboard.setData(ClipboardData(text: result));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Exported ${notifications.length} notifications to ${format.name.toUpperCase()} and copied to clipboard!',
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        // Excel or PDF - file download
        await _exportService.exportNotifications(
          format: format,
          notifications: notifications,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Exported ${notifications.length} notifications to ${format.name.toUpperCase()}! ${kIsWeb ? 'File downloaded to your downloads folder.' : 'Use the share dialog to save the file.'}',
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = fb_auth.FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Sign in as an admin to view notifications')),
      );
    }

    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('notifications')
        .where('toUserId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(500);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with unread count
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('notifications')
                  .where('toUserId', isEqualTo: uid)
                  .where('status', isEqualTo: 'unread')
                  .snapshots(),
              builder: (context, unreadSnapshot) {
                final unreadCount = unreadSnapshot.data?.docs.length ?? 0;
                return Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF00897B),
                        const Color(0xFF00695C),
                      ],
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
                        child: Stack(
                          children: [
                            const Icon(
                              Icons.notifications,
                              color: Colors.white,
                              size: 28,
                            ),
                            if (unreadCount > 0)
                              Positioned(
                                right: 0,
                                top: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  constraints: const BoxConstraints(
                                    minWidth: 16,
                                    minHeight: 16,
                                  ),
                                  child: Text(
                                    unreadCount > 99 ? '99+' : '$unreadCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Admin Notifications',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              unreadCount > 0
                                  ? '$unreadCount unread notification${unreadCount == 1 ? '' : 's'}'
                                  : 'All caught up!',
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            // Search and filter bar
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search notifications...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                // Filter dropdown
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.grey[100],
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedTypeFilter,
                      hint: const Text('Type'),
                      items: _notificationTypes.map((type) {
                        return DropdownMenuItem(
                          value: type == 'All' ? null : type,
                          child: Text(
                            type == 'All' ? 'All Types' : _formatTypeName(type),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedTypeFilter = value;
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Unread only toggle
                IconButton(
                  icon: Icon(
                    _showUnreadOnly
                        ? Icons.filter_alt
                        : Icons.filter_alt_outlined,
                    color: _showUnreadOnly
                        ? const Color(0xFF00897B)
                        : Colors.grey,
                  ),
                  tooltip: 'Show unread only',
                  onPressed: () {
                    setState(() {
                      _showUnreadOnly = !_showUnreadOnly;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.done_all),
                    label: const Text('Mark All Read'),
                    onPressed: () => _markAllAsRead(uid),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Clear Read'),
                    onPressed: () => _clearReadNotifications(uid),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.download),
                  tooltip: 'Export notifications',
                  onPressed: () async {
                    // Get current notifications for export
                    final snapshot = await query.get();
                    _exportNotifications(snapshot.docs);
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Notifications list
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: query.snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('Error: ${snapshot.error}'),
                      ),
                    );
                  }

                  final docs = snapshot.data?.docs ?? [];

                  // Apply filters
                  var filtered = docs.where((d) {
                    final data = d.data();
                    final type = data['type'] as String? ?? '';

                    // Type filter
                    if (_selectedTypeFilter != null &&
                        type != _selectedTypeFilter) {
                      return false;
                    }

                    // Unread only filter
                    if (_showUnreadOnly && data['status'] != 'unread') {
                      return false;
                    }

                    // Search filter
                    final searchText = _searchController.text.toLowerCase();
                    if (searchText.isNotEmpty) {
                      final title =
                          data['title']?.toString().toLowerCase() ?? '';
                      final message =
                          data['message']?.toString().toLowerCase() ?? '';
                      final eventTitle =
                          data['eventTitle']?.toString().toLowerCase() ?? '';
                      if (!title.contains(searchText) &&
                          !message.contains(searchText) &&
                          !eventTitle.contains(searchText)) {
                        return false;
                      }
                    }

                    // Admin-relevant types filter (keep all types now)
                    return true;
                  }).toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.notifications_none,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No notifications found',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final doc = filtered[index];
                      final data = doc.data();
                      final type = data['type'] as String? ?? '';
                      final isUnread = data['status'] == 'unread';
                      final createdAt = _asDateTime(data['createdAt']);
                      final timeText = createdAt == null
                          ? ''
                          : _relativeTime(createdAt);

                      final String title;
                      final String? message;
                      if (type == 'calamity_donation') {
                        final eventTitle =
                            data['eventTitle'] as String? ?? 'Calamity Event';
                        final itemType = data['itemType'] as String? ?? 'item';
                        final quantity = data['quantity'] as int? ?? 0;
                        final donorName = data['donorName'] as String?;
                        final donorEmail =
                            data['donorEmail'] as String? ?? 'a donor';
                        final donorLabel =
                            (donorName != null && donorName.isNotEmpty)
                            ? donorName
                            : donorEmail;
                        title =
                            'New donation: $quantity $itemType for "$eventTitle"';
                        message = 'From: $donorLabel';
                      } else if (type == 'calamity_event_created') {
                        final eventTitle =
                            data['eventTitle'] as String? ??
                            'New Calamity Event';
                        final calamityType = data['calamityType'] as String?;
                        if (calamityType != null && calamityType.isNotEmpty) {
                          title =
                              '🚨 New $calamityType Relief Event: "$eventTitle"';
                        } else {
                          title = '🚨 New Calamity Relief Event: "$eventTitle"';
                        }
                        message = data['message'] as String?;
                      } else if (type == 'verification_approved') {
                        title =
                            data['title'] as String? ??
                            'Account Verification Approved';
                        message = data['message'] as String?;
                      } else if (type == 'verification_rejected') {
                        title =
                            data['title'] as String? ??
                            'Account Verification Rejected';
                        message =
                            data['message'] as String? ??
                            data['rejectionReason'] as String?;
                      } else if (type == 'violation_issued') {
                        title = data['title'] as String? ?? 'Violation Issued';
                        message = data['message'] as String?;
                      } else if (type == 'account_suspended') {
                        title = data['title'] as String? ?? 'Account Suspended';
                        message = data['message'] as String?;
                      } else if (type == 'account_restored') {
                        title = data['title'] as String? ?? 'Account Restored';
                        message = data['message'] as String?;
                      } else if (type == 'new_user_registration') {
                        // Use userName from notification data, fallback to message, then email
                        final userName = data['userName'] as String?;
                        final userEmail = data['userEmail'] as String?;
                        final notificationMessage = data['message'] as String?;

                        // Determine the display name
                        String displayName;
                        if (userName != null &&
                            userName.isNotEmpty &&
                            userName != 'Unknown') {
                          displayName = userName;
                        } else if (userEmail != null &&
                            userEmail.isNotEmpty &&
                            userEmail != 'Unknown') {
                          displayName = userEmail;
                        } else if (notificationMessage != null &&
                            notificationMessage.isNotEmpty) {
                          // Extract name from message if available
                          displayName = notificationMessage;
                        } else {
                          displayName = 'A new user';
                        }

                        title =
                            data['title'] as String? ?? 'New User Registration';
                        message =
                            '$displayName has registered and is pending verification';
                      } else {
                        title = data['title'] as String? ?? 'Notification';
                        message = data['message'] as String?;
                      }

                      final bgColor = isUnread
                          ? Theme.of(
                              context,
                            ).colorScheme.surfaceTint.withOpacity(0.08)
                          : Colors.transparent;

                      return Dismissible(
                        key: Key(doc.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          color: Colors.red,
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (_) => _deleteNotification(doc.id),
                        child: Container(
                          color: bgColor,
                          child: ListTile(
                            leading: Icon(
                              _iconForType(type),
                              color: isUnread
                                  ? const Color(0xFF00897B)
                                  : Colors.grey,
                            ),
                            title: Text(
                              title,
                              style: TextStyle(
                                fontWeight: isUnread
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                fontSize: 15,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (message != null && message.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      message,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                if (timeText.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      timeText,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            trailing: PopupMenuButton(
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  child: Row(
                                    children: [
                                      Icon(
                                        isUnread
                                            ? Icons.mark_email_read
                                            : Icons.mark_email_unread,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        isUnread
                                            ? 'Mark as read'
                                            : 'Mark as unread',
                                      ),
                                    ],
                                  ),
                                  onTap: () {
                                    Future.delayed(
                                      const Duration(milliseconds: 100),
                                      () {
                                        if (isUnread) {
                                          _markAsRead(doc.id);
                                        } else {
                                          _markAsUnread(doc.id);
                                        }
                                      },
                                    );
                                  },
                                ),
                                PopupMenuItem(
                                  child: const Row(
                                    children: [
                                      Icon(Icons.delete, size: 20),
                                      SizedBox(width: 8),
                                      Text('Delete'),
                                    ],
                                  ),
                                  onTap: () {
                                    Future.delayed(
                                      const Duration(milliseconds: 100),
                                      () => _deleteNotification(doc.id),
                                    );
                                  },
                                ),
                              ],
                            ),
                            onTap: () {
                              data['notificationId'] = doc.id;
                              _handleNotificationTap(context, data, type);
                            },
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _iconForType(String type) {
  if (type == 'new_user_registration') return Icons.person_add_outlined;
  if (type == 'calamity_donation') return Icons.emergency_outlined;
  if (type == 'calamity_event_created') return Icons.crisis_alert;
  if (type == 'verification_approved') return Icons.verified;
  if (type == 'verification_rejected') return Icons.warning_amber_rounded;
  if (type == 'violation_issued') return Icons.gavel;
  if (type == 'account_suspended') return Icons.block;
  if (type == 'account_restored') return Icons.check_circle;
  if (type.startsWith('donate')) return Icons.volunteer_activism_outlined;
  return Icons.notifications;
}

String _formatTypeName(String type) {
  return type
      .split('_')
      .map((word) => word[0].toUpperCase() + word.substring(1))
      .join(' ');
}

DateTime? _asDateTime(dynamic ts) {
  try {
    if (ts == null) return null;
    if (ts is DateTime) return ts;
    if (ts is Timestamp) return ts.toDate();
    if (ts is int) return DateTime.fromMillisecondsSinceEpoch(ts);
  } catch (_) {}
  return null;
}

String _relativeTime(DateTime time) {
  final now = DateTime.now();
  final diff = now.difference(time);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  final weeks = (diff.inDays / 7).floor();
  if (weeks < 5) return '${weeks}w ago';
  return '${time.year}/${time.month.toString().padLeft(2, '0')}/${time.day.toString().padLeft(2, '0')}';
}
