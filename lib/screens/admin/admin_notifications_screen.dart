import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/material.dart';

/// Admin view of notifications.
///
/// Shows notifications for the currently logged-in admin user
/// (documents in the `notifications` collection where `toUserId`
/// equals the admin's Firebase Auth UID).
///
/// This reuses the same Firestore structure as the user-facing
/// `NotificationsScreen`, but with a simpler single-list layout
/// that is focused on admin-relevant types such as
/// `calamity_donation` and `calamity_event_created`.
class AdminNotificationsScreen extends StatelessWidget {
  const AdminNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = fb_auth.FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Sign in as an admin to view notifications')),
      );
    }

    final query = FirebaseFirestore.instance
        .collection('notifications')
        .where('toUserId', isEqualTo: uid)
        .limit(100);

    return Scaffold(
      body: Padding(
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
                      Icons.notifications,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Admin Notifications',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'View all platform notifications',
                          style: TextStyle(fontSize: 14, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
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

                  final docs = (snapshot.data?.docs ?? []).toList()
                    ..sort((a, b) {
                      final aTime =
                          (a.data()['createdAt'] as Timestamp?)?.toDate() ??
                          DateTime(1970);
                      final bTime =
                          (b.data()['createdAt'] as Timestamp?)?.toDate() ??
                          DateTime(1970);
                      return bTime.compareTo(aTime);
                    });

                  // Filter to admin-relevant types; keep calamity-related
                  // and any explicitly-addressed messages.
                  final filtered = docs.where((d) {
                    final t = (d.data()['type'] as String?) ?? '';
                    return t == 'calamity_donation' ||
                        t == 'calamity_event_created' ||
                        t == 'verification_rejected' ||
                        t.startsWith('donate_');
                  }).toList();

                  if (filtered.isEmpty) {
                    return const Center(child: Text('No notifications'));
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
                            'New donation: $quantity $itemType for "$eventTitle" from $donorLabel';
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
                      } else if (type == 'verification_rejected') {
                        title =
                            data['title'] as String? ??
                            'Account Verification Rejected';
                      } else {
                        title = data['title'] as String? ?? 'Notification';
                      }

                      final bgColor = isUnread
                          ? Theme.of(
                              context,
                            ).colorScheme.surfaceTint.withOpacity(0.08)
                          : Colors.transparent;

                      return Container(
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
                          subtitle: timeText.isNotEmpty
                              ? Text(
                                  timeText,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                )
                              : null,
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
  if (type == 'calamity_donation') return Icons.emergency_outlined;
  if (type == 'calamity_event_created') return Icons.crisis_alert;
  if (type == 'verification_rejected') {
    return Icons.warning_amber_rounded;
  }
  if (type.startsWith('donate')) return Icons.volunteer_activism_outlined;
  return Icons.notifications;
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
