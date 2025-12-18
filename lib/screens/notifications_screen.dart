import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import 'borrow/borrow_request_detail_screen.dart';
import 'rental/rental_request_detail_screen.dart';
import 'rental/active_rental_detail_screen.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final String? uid = auth.user?.uid;
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Notifications'),
          actions: [
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'mark_all_read') {
                  await _markAllAsRead(uid!);
                } else if (value == 'clear_read') {
                  await _clearRead(uid!);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'mark_all_read',
                  child: Text('Mark all as read'),
                ),
                const PopupMenuItem(
                  value: 'clear_read',
                  child: Text('Clear read notifications'),
                ),
              ],
            ),
          ],
          bottom: _NotificationsTabBar(userId: uid ?? ''),
        ),
        body: uid == null
            ? const Center(child: Text('Sign in to view notifications'))
            : _NotificationsTabView(userId: uid),
      ),
    );
  }
}

class _NotificationsTabBar extends StatelessWidget
    implements PreferredSizeWidget {
  final String userId;
  const _NotificationsTabBar({required this.userId});

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('notifications')
        .where('toUserId', isEqualTo: userId)
        .limit(100);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];

        // Count unread notifications by category
        final allUnread = docs.where((d) {
          final t = (d.data()['type'] as String?) ?? '';
          return d.data()['status'] == 'unread' &&
              t != 'chat_message' &&
              t != 'message';
        }).length;

        final borrowUnread = docs.where((d) {
          final t = (d.data()['type'] as String?) ?? '';
          return d.data()['status'] == 'unread' &&
              (t.startsWith('borrow_') ||
                  t == 'item_overdue' ||
                  t.startsWith('return_reminder_')) &&
              t != 'chat_message' &&
              t != 'message';
        }).length;

        final tradeUnread = docs.where((d) {
          final t = (d.data()['type'] as String?) ?? '';
          return d.data()['status'] == 'unread' &&
              t.startsWith('trade') &&
              t != 'chat_message' &&
              t != 'message';
        }).length;

        final rentUnread = docs.where((d) {
          final t = (d.data()['type'] as String?) ?? '';
          return d.data()['status'] == 'unread' &&
              t.startsWith('rent') &&
              t != 'chat_message' &&
              t != 'message';
        }).length;

        final donateUnread = docs.where((d) {
          final t = (d.data()['type'] as String?) ?? '';
          return d.data()['status'] == 'unread' &&
              (t.startsWith('donation') ||
                  t == 'calamity_donation' ||
                  t == 'calamity_event_created') &&
              t != 'chat_message' &&
              t != 'message';
        }).length;

        return TabBar(
          isScrollable: true,
          tabs: [
            _TabWithBadge(text: 'All', count: allUnread),
            _TabWithBadge(text: 'Borrow', count: borrowUnread),
            _TabWithBadge(text: 'Trading', count: tradeUnread),
            _TabWithBadge(text: 'Rent', count: rentUnread),
            _TabWithBadge(text: 'Donate', count: donateUnread),
          ],
        );
      },
    );
  }
}

class _TabWithBadge extends StatelessWidget {
  final String text;
  final int count;

  const _TabWithBadge({required this.text, required this.count});

  @override
  Widget build(BuildContext context) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count > 99 ? '99+' : count.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NotificationsTabView extends StatelessWidget {
  final String userId;
  const _NotificationsTabView({required this.userId});

  @override
  Widget build(BuildContext context) {
    debugPrint(
      'NotificationsScreen: Querying notifications for userId: $userId',
    );
    final query = FirebaseFirestore.instance
        .collection('notifications')
        .where('toUserId', isEqualTo: userId)
        .limit(100);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          debugPrint(
            'NotificationsScreen: Found ${snapshot.data!.docs.length} notifications for userId: $userId',
          );
          // Debug: Print toUserId of each notification
          for (final doc in snapshot.data!.docs) {
            final data = doc.data();
            final notifToUserId = data['toUserId'] as String?;
            final notifType = data['type'] as String?;
            debugPrint(
              'Notification ${doc.id}: type=$notifType, toUserId=$notifToUserId, expectedUserId=$userId',
            );
          }
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildSkeletonLoader(context);
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

        return TabBarView(
          children: [
            _buildList(context, docs),
            _buildList(
              context,
              docs.where((d) {
                final t = (d.data()['type'] as String?) ?? '';
                return t.startsWith('borrow_') ||
                    t == 'item_overdue' ||
                    t.startsWith('return_reminder_');
              }).toList(),
            ),
            _buildList(
              context,
              docs.where((d) {
                final t = (d.data()['type'] as String?) ?? '';
                return t.startsWith('trade');
              }).toList(),
            ),
            _buildList(
              context,
              docs.where((d) {
                final t = (d.data()['type'] as String?) ?? '';
                return t.startsWith('rent');
              }).toList(),
            ),
            _buildList(
              context,
              docs.where((d) {
                final t = (d.data()['type'] as String?) ?? '';
                return t.startsWith('donation') ||
                    t == 'calamity_donation' ||
                    t == 'calamity_event_created';
              }).toList(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildList(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    // Exclude chat/message notifications from this screen; they are handled
    // separately by the chat UI and FCM handlers.
    final filteredDocs = docs.where((d) {
      final t = (d.data()['type'] as String?) ?? '';
      return t != 'chat_message' && t != 'message';
    }).toList();

    if (filteredDocs.isEmpty) {
      return _buildEmptyState(context);
    }

    // Group notifications by date
    final grouped = _groupByDate(filteredDocs);

    return RefreshIndicator(
      onRefresh: () async {
        // Trigger a refresh by re-fetching
        await Future.delayed(const Duration(milliseconds: 500));
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: grouped.length,
        itemBuilder: (context, index) {
          final group = grouped[index];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  group['dateLabel'] as String,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.6),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              // Notifications in this group
              ...(group['notifications']
                      as List<QueryDocumentSnapshot<Map<String, dynamic>>>)
                  .map((doc) => _buildNotificationCard(context, doc)),
            ],
          );
        },
      ),
    );
  }

  List<Map<String, dynamic>> _groupByDate(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final thisWeek = today.subtract(const Duration(days: 7));

    final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
    groups = {};

    for (final doc in docs) {
      final createdAt = _asDateTime(doc.data()['createdAt']);
      if (createdAt == null) {
        groups.putIfAbsent('Older', () => []).add(doc);
        continue;
      }

      final date = DateTime(createdAt.year, createdAt.month, createdAt.day);
      String label;
      if (date == today) {
        label = 'Today';
      } else if (date == yesterday) {
        label = 'Yesterday';
      } else if (createdAt.isAfter(thisWeek)) {
        label = 'This Week';
      } else {
        label = 'Older';
      }

      groups.putIfAbsent(label, () => []).add(doc);
    }

    // Sort groups in order: Today, Yesterday, This Week, Older
    final order = ['Today', 'Yesterday', 'This Week', 'Older'];
    return order
        .where((label) => groups.containsKey(label))
        .map((label) => {'dateLabel': label, 'notifications': groups[label]!})
        .toList();
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 80,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No notifications',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You\'re all caught up!',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonLoader(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: 5,
      itemBuilder: (context, index) {
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 16,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 12,
                        width: 100,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNotificationCard(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final type = data['type'] as String? ?? '';
    final fromName = data['fromUserName'] as String? ?? 'Someone';
    final itemTitle = data['itemTitle'] as String? ?? 'an item';
    final isUnread = data['status'] == 'unread';
    final createdAt = _asDateTime(data['createdAt']);
    final timeText = createdAt == null ? '' : _relativeTime(createdAt);
    final itemImageUrl = data['itemImageUrl'] as String?;

    final String title;
    if (type == 'borrow_request') {
      title = '$fromName requested to borrow "$itemTitle"';
    } else if (type == 'borrow_request_decision') {
      final decision = data['decision'] as String? ?? '';
      final lenderName = data['lenderName'] as String?;
      if (decision == 'accepted') {
        title = lenderName != null
            ? '$lenderName accepted your request to borrow "$itemTitle"!'
            : 'Your request to borrow "$itemTitle" was accepted!';
      } else if (decision == 'declined') {
        title = lenderName != null
            ? '$lenderName declined your request to borrow "$itemTitle"'
            : 'Your request to borrow "$itemTitle" was declined';
      } else {
        title = 'Update on "$itemTitle"';
      }
    } else if (type == 'borrow_return_initiated') {
      title = '$fromName wants to return "$itemTitle"';
    } else if (type == 'borrow_return_confirmed') {
      title = '$fromName confirmed return for "$itemTitle". Item returned!';
    } else if (type == 'borrow_return_disputed') {
      title =
          '$fromName disputed return for "$itemTitle". Please review the damage report.';
    } else if (type == 'dispute_compensation_proposed') {
      final amount = data['amount'] as num?;
      final amountText = amount != null ? '₱${amount.toStringAsFixed(2)}' : '';
      title = amountText.isNotEmpty
          ? '$fromName proposed compensation of $amountText for "$itemTitle". Please review and respond.'
          : '$fromName proposed compensation for "$itemTitle". Please review and respond.';
    } else if (type == 'dispute_compensation_accepted') {
      final amount = data['amount'] as num?;
      final amountText = amount != null ? '₱${amount.toStringAsFixed(2)}' : '';
      title = amountText.isNotEmpty
          ? '$fromName accepted your compensation proposal of $amountText for "$itemTitle"'
          : '$fromName accepted your compensation proposal for "$itemTitle"';
    } else if (type == 'dispute_compensation_rejected') {
      title =
          '$fromName rejected your compensation proposal for "$itemTitle". You can propose a new amount.';
    } else if (type == 'rental_dispute_compensation_proposed') {
      final amount = data['amount'] as num?;
      final amountText = amount != null ? '₱${amount.toStringAsFixed(2)}' : '';
      title = amountText.isNotEmpty
          ? '$fromName proposed compensation of $amountText for "$itemTitle". Please review and respond.'
          : '$fromName proposed compensation for "$itemTitle". Please review and respond.';
    } else if (type == 'rental_dispute_compensation_accepted') {
      final amount = data['amount'] as num?;
      final amountText = amount != null ? '₱${amount.toStringAsFixed(2)}' : '';
      title = amountText.isNotEmpty
          ? '$fromName accepted your compensation proposal of $amountText for "$itemTitle"'
          : '$fromName accepted your compensation proposal for "$itemTitle"';
    } else if (type == 'rental_dispute_compensation_rejected') {
      title =
          '$fromName rejected your compensation proposal for "$itemTitle". You can propose a new amount.';
    } else if (type == 'rental_dispute_payment_recorded') {
      final amount = data['amount'] as num?;
      final amountText = amount != null ? '₱${amount.toStringAsFixed(2)}' : '';
      title = amountText.isNotEmpty
          ? '$fromName recorded payment of $amountText for "$itemTitle". Dispute resolved!'
          : '$fromName recorded payment for "$itemTitle". Dispute resolved!';
    } else if (type == 'trade_offer') {
      title = '$fromName made a trade offer on "$itemTitle"';
    } else if (type == 'trade_counter_offer') {
      title = '$fromName sent you a counter-offer for "$itemTitle"';
    } else if (type == 'trade_match') {
      final matchReason =
          data['matchReason'] as String? ?? 'A new trade match was found!';
      title = matchReason;
    } else if (type == 'trade_offer_decision') {
      final decision = data['decision'] as String? ?? '';
      final ownerName = data['ownerName'] as String?;
      if (decision == 'accepted') {
        title = ownerName != null
            ? '$ownerName accepted your trade offer on "$itemTitle"!'
            : 'Your trade offer on "$itemTitle" was accepted!';
      } else if (decision == 'declined') {
        title = ownerName != null
            ? '$ownerName declined your trade offer on "$itemTitle"'
            : 'Your trade offer on "$itemTitle" was declined';
      } else {
        title = 'Update on "$itemTitle"';
      }
    } else if (type == 'rent_request') {
      title = '$fromName requested to rent "$itemTitle"';
    } else if (type == 'rent_request_decision') {
      final decision = data['decision'] as String? ?? '';
      final ownerName = data['ownerName'] as String?;
      if (decision == 'accepted') {
        title = ownerName != null
            ? '$ownerName accepted your rental request for "$itemTitle"!'
            : 'Your rental request for "$itemTitle" was accepted!';
      } else if (decision == 'declined') {
        title = ownerName != null
            ? '$ownerName declined your rental request for "$itemTitle"'
            : 'Your rental request for "$itemTitle" was declined';
      } else {
        title = 'Update on "$itemTitle"';
      }
    } else if (type == 'rent_payment_received') {
      title = data['message'] as String? ?? 'Payment received for "$itemTitle"';
    } else if (type == 'rent_payment_reminder') {
      title = data['message'] as String? ?? 'Payment reminder for "$itemTitle"';
    } else if (type == 'rental_monthly_payment_due') {
      final monthlyAmount = data['monthlyAmount'] as num?;
      final amountText = monthlyAmount != null
          ? '₱${monthlyAmount.toStringAsFixed(2)}'
          : '';
      title = amountText.isNotEmpty
          ? '💰 Monthly payment due: $itemTitle ($amountText)'
          : '💰 Monthly payment due: $itemTitle';
    } else if (type == 'rental_monthly_payment_overdue') {
      final monthlyAmount = data['monthlyAmount'] as num?;
      final amountText = monthlyAmount != null
          ? '₱${monthlyAmount.toStringAsFixed(2)}'
          : '';
      title = amountText.isNotEmpty
          ? '⚠️ Monthly payment overdue: $itemTitle ($amountText)'
          : '⚠️ Monthly payment overdue: $itemTitle';
    } else if (type == 'rent_active') {
      title =
          data['message'] as String? ?? 'Rental is now active for "$itemTitle"';
    } else if (type == 'rent_return_initiated') {
      final renterName = data['renterName'] as String?;
      final rentType = (data['rentType'] as String? ?? 'item')
          .toString()
          .toLowerCase();

      // Generate rent type-specific notification title
      String notificationTitle;
      if (renterName != null) {
        switch (rentType) {
          case 'apartment':
            notificationTitle = '$renterName ended rental for "$itemTitle"';
            break;
          case 'boardinghouse':
          case 'boarding_house':
            notificationTitle = '$renterName moved out from "$itemTitle"';
            break;
          case 'commercial':
          case 'commercialspace':
          case 'commercial_space':
            notificationTitle = '$renterName ended lease for "$itemTitle"';
            break;
          default:
            notificationTitle = '$renterName initiated return for "$itemTitle"';
        }
      } else {
        // Fallback to message or default based on rent type
        switch (rentType) {
          case 'apartment':
            notificationTitle =
                data['message'] as String? ??
                'Rental ended for "$itemTitle". Please verify the apartment.';
            break;
          case 'boardinghouse':
          case 'boarding_house':
            notificationTitle =
                data['message'] as String? ??
                'Move out for "$itemTitle". Please verify the room/space.';
            break;
          case 'commercial':
          case 'commercialspace':
          case 'commercial_space':
            notificationTitle =
                data['message'] as String? ??
                'Lease ended for "$itemTitle". Please verify the commercial space.';
            break;
          default:
            notificationTitle =
                data['message'] as String? ??
                'Return initiated for "$itemTitle". Please verify the item.';
        }
      }
      title = notificationTitle;
    } else if (type == 'rent_return_verified') {
      final ownerName = data['ownerName'] as String?;
      title = ownerName != null
          ? '$ownerName verified return for "$itemTitle". Rental completed!'
          : data['message'] as String? ??
                'Return verified for "$itemTitle". Rental completed!';
    } else if (type == 'rent_return_disputed') {
      final ownerName = data['fromUserName'] as String? ?? 'Owner';
      title =
          '$ownerName disputed return for "$itemTitle". Please review the damage report.';
    } else if (type == 'rent_terminated_by_owner') {
      final ownerName = data['fromUserName'] as String? ?? 'Owner';
      final terminationReason = data['terminationReason'] as String?;
      final rentType = (data['rentType'] as String? ?? 'item')
          .toString()
          .toLowerCase();

      // Generate rent type-specific notification title
      String notificationTitle;
      switch (rentType) {
        case 'apartment':
          notificationTitle =
              '$ownerName forcibly ended your rental for "$itemTitle"';
          break;
        case 'boardinghouse':
        case 'boarding_house':
          notificationTitle =
              '$ownerName forcibly moved you out from "$itemTitle"';
          break;
        case 'commercial':
        case 'commercialspace':
        case 'commercial_space':
          notificationTitle =
              '$ownerName forcibly ended your lease for "$itemTitle"';
          break;
        default:
          notificationTitle =
              '$ownerName forcibly ended your rental for "$itemTitle"';
      }

      // Add reason if provided
      if (terminationReason != null && terminationReason.isNotEmpty) {
        notificationTitle += '\nReason: $terminationReason';
      }

      title = notificationTitle;
    } else if (type == 'donation_request') {
      title = '$fromName requested to claim "$itemTitle"';
    } else if (type == 'donation_request_decision') {
      final decision = data['decision'] as String? ?? '';
      final donorName = data['donorName'] as String?;
      if (decision == 'accepted') {
        title = donorName != null
            ? '$donorName approved your claim request for "$itemTitle"!'
            : 'Your claim request for "$itemTitle" was approved!';
      } else if (decision == 'declined') {
        title = donorName != null
            ? '$donorName declined your claim request for "$itemTitle"'
            : 'Your claim request for "$itemTitle" was declined';
      } else {
        title = 'Update on "$itemTitle"';
      }
    } else if (type == 'verification_rejected') {
      title = data['title'] as String? ?? 'Account Verification Rejected';
    } else if (type == 'verification_approved') {
      title = data['title'] as String? ?? 'Account Verified Successfully';
    } else if (type == 'rental_overdue') {
      final daysOverdue = data['daysOverdue'] as int? ?? 0;
      if (daysOverdue == 0) {
        title = '⚠️ "$itemTitle" rental is due today';
      } else if (daysOverdue == 1) {
        title = '⚠️ "$itemTitle" rental is 1 day overdue';
      } else {
        title = '⚠️ "$itemTitle" rental is $daysOverdue days overdue';
      }
    } else if (type == 'rental_overdue_owner') {
      final daysOverdue = data['daysOverdue'] as int? ?? 0;
      final renterName = data['renterName'] as String? ?? 'Renter';
      if (daysOverdue == 0) {
        title = '⚠️ "$itemTitle" rented by $renterName is due today';
      } else if (daysOverdue == 1) {
        title = '⚠️ "$itemTitle" rented by $renterName is 1 day overdue';
      } else {
        title =
            '⚠️ "$itemTitle" rented by $renterName is $daysOverdue days overdue';
      }
    } else if (type == 'item_overdue') {
      final daysOverdue = data['daysOverdue'] as int? ?? 0;
      if (daysOverdue == 0) {
        title = '⚠️ "$itemTitle" is due today';
      } else if (daysOverdue == 1) {
        title = '⚠️ "$itemTitle" is 1 day overdue';
      } else {
        title = '⚠️ "$itemTitle" is $daysOverdue days overdue';
      }
    } else if (type == 'item_overdue_lender') {
      final daysOverdue = data['daysOverdue'] as int? ?? 0;
      final borrowerName = data['borrowerName'] as String? ?? 'Borrower';
      if (daysOverdue == 0) {
        title = '⚠️ "$itemTitle" borrowed by $borrowerName is due today';
      } else if (daysOverdue == 1) {
        title = '⚠️ "$itemTitle" borrowed by $borrowerName is 1 day overdue';
      } else {
        title =
            '⚠️ "$itemTitle" borrowed by $borrowerName is $daysOverdue days overdue';
      }
    } else if (type == 'return_reminder_24h') {
      title = data['title'] as String? ?? '⏰ Return reminder (24h): $itemTitle';
    } else if (type == 'return_reminder_1h') {
      title = data['title'] as String? ?? '⏰ Return reminder (1h): $itemTitle';
    } else if (type == 'return_reminder_due') {
      title = data['title'] as String? ?? '⏰ Due now: $itemTitle';
    } else if (type == 'calamity_donation') {
      final eventTitle = data['eventTitle'] as String? ?? 'Calamity Event';
      final itemType = data['itemType'] as String? ?? 'item';
      final quantity = data['quantity'] as int? ?? 0;
      final donorName = data['donorName'] as String?;
      final donorEmail = data['donorEmail'] as String? ?? 'a donor';
      final donorLabel = (donorName != null && donorName.isNotEmpty)
          ? donorName
          : donorEmail;
      title =
          'New donation: $quantity $itemType for "$eventTitle" from $donorLabel';
    } else if (type == 'calamity_event_created') {
      final eventTitle = data['eventTitle'] as String? ?? 'New Calamity Event';
      final calamityType = data['calamityType'] as String?;
      if (calamityType != null && calamityType.isNotEmpty) {
        title = '🚨 New $calamityType Relief Event: "$eventTitle"';
      } else {
        title = '🚨 New Calamity Relief Event: "$eventTitle"';
      }
    } else if (type == 'violation_issued') {
      // Use the title from the notification data, or fallback to a default message
      final notificationTitle = data['title'] as String?;
      if (notificationTitle != null && notificationTitle.isNotEmpty) {
        title = notificationTitle;
      } else {
        final violationCount = data['violationCount'] as int? ?? 0;
        title = 'Violation Issued (Count: $violationCount)';
      }
    } else if (type == 'report_resolved') {
      // Use the title from the notification data, or fallback to a default message
      final notificationTitle = data['title'] as String?;
      if (notificationTitle != null && notificationTitle.isNotEmpty) {
        title = notificationTitle;
      } else {
        title = 'Report Resolved';
      }
    } else if (type == 'account_suspended') {
      // Use the title from the notification data, or fallback to a default message
      final notificationTitle = data['title'] as String?;
      if (notificationTitle != null && notificationTitle.isNotEmpty) {
        title = notificationTitle;
      } else {
        title = 'Account Suspended';
      }
    } else {
      // For any other notification type, try to use the title field if available
      final notificationTitle = data['title'] as String?;
      if (notificationTitle != null && notificationTitle.isNotEmpty) {
        title = notificationTitle;
      } else {
        title = 'Notification';
      }
    }

    return Dismissible(
      key: ValueKey(doc.id),
      background: Container(
        color: const Color(0xFF00897B),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.centerLeft,
        child: const Row(
          children: [
            Icon(Icons.mark_email_read, color: Colors.white),
            SizedBox(width: 8),
            Text('Mark read', style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
      secondaryBackground: Container(
        color: Colors.red,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.centerRight,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('Delete', style: TextStyle(color: Colors.white)),
            SizedBox(width: 8),
            Icon(Icons.delete, color: Colors.white),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          HapticFeedback.lightImpact();
          try {
            await FirestoreService().markNotificationRead(doc.id);
          } catch (_) {}
          return false; // keep in list; stream will update
        } else {
          HapticFeedback.mediumImpact();
          return await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete notification?'),
                  content: const Text('This cannot be undone.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              ) ??
              false;
        }
      },
      onDismissed: (direction) async {
        if (direction == DismissDirection.endToStart) {
          try {
            await FirebaseFirestore.instance
                .collection('notifications')
                .doc(doc.id)
                .delete();
          } catch (_) {}
        }
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        elevation: isUnread ? 2 : 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: isUnread
              ? BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.3),
                  width: 1,
                )
              : BorderSide.none,
        ),
        color: isUnread
            ? Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.3)
            : Theme.of(context).cardColor,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            HapticFeedback.selectionClick();
            try {
              await FirestoreService().markNotificationRead(doc.id);
            } catch (_) {}

            _handleNotificationTap(context, type, data);
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon with unread indicator
                Stack(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: isUnread
                            ? Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.1)
                            : Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _iconForType(type),
                        color: isUnread
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.6),
                        size: 24,
                      ),
                    ),
                    if (isUnread)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: isUnread
                              ? FontWeight.w600
                              : FontWeight.w500,
                          fontSize: 15,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      // Subtitle content
                      if (type == 'verification_rejected')
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            data['message'] as String? ??
                                data['rejectionReason'] as String? ??
                                'Your account verification was rejected.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.orange[700],
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (type == 'verification_approved')
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            data['message'] as String? ??
                                'Congratulations! Your account has been verified.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.green[700],
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (type == 'rental_overdue')
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            'Please return this rental item as soon as possible.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.red[700],
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (type == 'rental_overdue_owner')
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            'Contact the renter to arrange return.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.red[700],
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (type == 'item_overdue' ||
                          type == 'item_overdue_lender')
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            type == 'item_overdue'
                                ? 'Please return this item as soon as possible.'
                                : 'Contact the borrower to arrange return.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.red[700],
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (type == 'return_reminder_24h' ||
                          type == 'return_reminder_1h' ||
                          type == 'return_reminder_due')
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            data['message'] as String? ??
                                'Please prepare to return this item.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.blue[700],
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (type == 'violation_issued' ||
                          type == 'report_resolved' ||
                          type == 'account_suspended')
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            data['message'] as String? ?? '',
                            style: TextStyle(
                              fontSize: 13,
                              color:
                                  type == 'violation_issued' ||
                                      type == 'account_suspended'
                                  ? Colors.orange[700]
                                  : Colors.blue[700],
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      // Time and item image row
                      Row(
                        children: [
                          if (timeText.isNotEmpty)
                            Text(
                              timeText,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                          if (itemImageUrl != null &&
                              itemImageUrl.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                image: DecorationImage(
                                  image: NetworkImage(itemImageUrl),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleNotificationTap(
    BuildContext context,
    String type,
    Map<String, dynamic> data,
  ) async {
    if (type == 'borrow_request') {
      final itemId = data['itemId'] as String? ?? '';
      String? requestId = data['requestId'] as String?;
      final borrowerId = data['fromUserId'] as String? ?? '';
      if (requestId == null || requestId.isEmpty) {
        try {
          requestId = await FirestoreService().findPendingBorrowRequestId(
            itemId: itemId,
            borrowerId: borrowerId,
          );
        } catch (_) {}
      }
      if (context.mounted && requestId != null && requestId.isNotEmpty) {
        // Navigate to borrow request detail screen
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) =>
                BorrowRequestDetailScreen(requestId: requestId!),
          ),
        );
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not find borrow request details'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } else if (type == 'borrow_return_initiated') {
      // Navigate to pending returns screen (for lenders)
      if (context.mounted) {
        Navigator.of(context).pushNamed('/borrow/pending-returns');
      }
    } else if (type == 'borrow_return_confirmed') {
      // Navigate to borrow history screen (for borrowers) since Returned Items was removed
      if (context.mounted) {
        Navigator.of(context).pushNamed('/borrow/history');
      }
    } else if (type == 'borrow_return_disputed') {
      // Navigate to disputed returns screen (for borrowers)
      if (context.mounted) {
        Navigator.of(context).pushNamed('/borrow/disputed-returns');
      }
    } else if (type == 'dispute_compensation_proposed') {
      // Navigate to disputed returns screen (for borrowers to see the proposal)
      if (context.mounted) {
        Navigator.of(context).pushNamed('/borrow/disputed-returns');
      }
    } else if (type == 'dispute_compensation_accepted' ||
        type == 'dispute_compensation_rejected') {
      // Navigate to lender disputes screen (for lenders to see the response)
      if (context.mounted) {
        Navigator.of(context).pushNamed('/borrow/lender-disputes');
      }
    } else if (type == 'rental_dispute_compensation_proposed') {
      // Navigate to disputed rentals screen (for renters to see the proposal)
      final requestId = data['requestId'] as String?;
      if (context.mounted && requestId != null && requestId.isNotEmpty) {
        Navigator.of(context).pushNamed('/rental/disputed-rentals');
      } else if (context.mounted) {
        Navigator.of(context).pushNamed('/rental/disputed-rentals');
      }
    } else if (type == 'rental_dispute_compensation_accepted' ||
        type == 'rental_dispute_compensation_rejected' ||
        type == 'rental_dispute_payment_recorded') {
      // Navigate to disputed rentals screen (for owners to see the response)
      final requestId = data['requestId'] as String?;
      if (context.mounted && requestId != null && requestId.isNotEmpty) {
        Navigator.of(context).pushNamed('/rental/disputed-rentals');
      } else if (context.mounted) {
        Navigator.of(context).pushNamed('/rental/disputed-rentals');
      }
    } else if (type == 'trade_offer' || type == 'trade_counter_offer') {
      // Navigate to Trade tab and show My Trades (where offers appear)
      if (context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/trade',
          (route) => route.settings.name == '/home' || route.isFirst,
        );
      }
    } else if (type == 'trade_match') {
      // Navigate to Trade screen and show Matches tab
      if (context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/trade',
          (route) => route.settings.name == '/home' || route.isFirst,
        );
        // Note: The Matches tab will show all matches including the new one
      }
    } else if (type == 'rent_request') {
      // Navigate to rental request detail screen
      final requestId = data['requestId'] as String?;
      if (context.mounted && requestId != null && requestId.isNotEmpty) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) =>
                RentalRequestDetailScreen(requestId: requestId),
          ),
        );
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not find rental request details'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } else if (type == 'rent_request_decision' ||
        type == 'rent_payment_received' ||
        type == 'rent_payment_reminder' ||
        type == 'rent_active' ||
        type == 'rent_return_initiated' ||
        type == 'rent_return_verified' ||
        type == 'rent_return_disputed' ||
        type == 'rental_overdue' ||
        type == 'rental_overdue_owner' ||
        type == 'rental_monthly_payment_due' ||
        type == 'rental_monthly_payment_overdue') {
      // Navigate to rental request detail screen or active rental detail
      final requestId = data['requestId'] as String?;
      if (context.mounted && requestId != null && requestId.isNotEmpty) {
        // For return notifications and overdue, navigate to active rental detail screen
        if (type == 'rent_return_initiated' ||
            type == 'rent_return_verified' ||
            type == 'rent_return_disputed' ||
            type == 'rent_terminated_by_owner' ||
            type == 'rental_overdue' ||
            type == 'rental_overdue_owner') {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) =>
                  ActiveRentalDetailScreen(requestId: requestId),
            ),
          );
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) =>
                  RentalRequestDetailScreen(requestId: requestId),
            ),
          );
        }
      } else if (context.mounted) {
        // Fallback to pending requests screen
        Navigator.of(context).pushNamed('/pending-requests');
      }
    } else if (type == 'return_reminder_24h' ||
        type == 'return_reminder_1h' ||
        type == 'return_reminder_due') {
      // Navigate to currently borrowed screen
      if (context.mounted) {
        Navigator.of(context).pushNamed('/borrow/currently-borrowed');
      }
    } else if (type == 'donation_request') {
      // Navigate to Giveaway detail screen
      final itemId = data['itemId'] as String?;
      if (context.mounted && itemId != null && itemId.isNotEmpty) {
        Navigator.of(
          context,
        ).pushNamed('/giveaway/detail', arguments: {'giveawayId': itemId});
      } else if (context.mounted) {
        // Fallback to giveaways list if itemId not available
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/giveaway',
          (route) => route.settings.name == '/home' || route.isFirst,
        );
      }
    } else if (type == 'calamity_donation') {
      // Navigate to Calamity Event Detail Admin screen
      final eventId = data['eventId'] as String?;
      if (context.mounted && eventId != null && eventId.isNotEmpty) {
        Navigator.of(context).pushNamed(
          '/admin/calamity/event-detail',
          arguments: {'eventId': eventId},
        );
      } else if (context.mounted) {
        // Fallback to calamity events admin screen
        Navigator.of(context).pushNamed('/admin/calamity');
      }
    } else if (type == 'calamity_event_created') {
      // Navigate to Calamity Event Detail screen (user view)
      final eventId = data['eventId'] as String?;
      if (context.mounted && eventId != null && eventId.isNotEmpty) {
        Navigator.of(
          context,
        ).pushNamed('/calamity/detail', arguments: {'eventId': eventId});
      } else if (context.mounted) {
        // Fallback to calamity events screen
        Navigator.of(context).pushNamed('/calamity');
      }
    } else if (type == 'verification_rejected') {
      // Show rejection reason dialog
      if (context.mounted) {
        final rejectionReason =
            data['rejectionReason'] as String? ??
            data['message'] as String? ??
            'Your account verification was rejected. Please review your submitted information and try again.';
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange),
                SizedBox(width: 8),
                Text('Verification Rejected'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your account verification was rejected. Please review the reason below:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Text(
                    rejectionReason,
                    style: TextStyle(color: Colors.orange[900]),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'You can update your information and resubmit for verification.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } else if (type == 'verification_approved') {
      // Show verification success dialog
      if (context.mounted) {
        final message =
            data['message'] as String? ??
            'Congratulations! Your account has been verified. You can now post items, borrow, rent, and use all features of the app.';
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.verified, color: Colors.green),
                SizedBox(width: 8),
                Text('Account Verified'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green[200]!),
                  ),
                  child: Text(
                    message,
                    style: TextStyle(color: Colors.green[900]),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'You can now access all features of the app!',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Got it!'),
              ),
            ],
          ),
        );
      }
    }
  }
}

IconData _iconForType(String type) {
  if (type == 'borrow_request') return Icons.handshake_outlined;
  if (type == 'borrow_request_decision') return Icons.rule_folder_outlined;
  if (type == 'borrow_return_initiated') return Icons.assignment_return;
  if (type == 'borrow_return_confirmed') return Icons.verified;
  if (type == 'borrow_return_disputed') return Icons.gavel_outlined;
  if (type == 'dispute_compensation_proposed') return Icons.attach_money;
  if (type == 'dispute_compensation_accepted') return Icons.check_circle;
  if (type == 'dispute_compensation_rejected') return Icons.cancel;
  if (type == 'rental_dispute_compensation_proposed') return Icons.attach_money;
  if (type == 'rental_dispute_compensation_accepted') return Icons.check_circle;
  if (type == 'rental_dispute_compensation_rejected') return Icons.cancel;
  if (type == 'rental_dispute_payment_recorded') return Icons.payment;
  if (type == 'trade_offer') return Icons.swap_horiz;
  if (type == 'trade_counter_offer') return Icons.swap_horiz_outlined;
  if (type == 'trade_offer_decision') return Icons.rule_folder_outlined;
  if (type == 'rent_request') return Icons.home_repair_service_outlined;
  if (type == 'rent_request_decision') return Icons.rule_folder_outlined;
  if (type == 'rent_payment_received') return Icons.payment;
  if (type == 'rent_payment_reminder') return Icons.notifications_active;
  if (type == 'rental_monthly_payment_due') return Icons.payment;
  if (type == 'rental_monthly_payment_overdue') {
    return Icons.warning_amber_rounded;
  }
  if (type == 'rent_active') return Icons.check_circle;
  if (type == 'rent_return_initiated') return Icons.assignment_return;
  if (type == 'rent_return_verified') return Icons.verified;
  if (type == 'rent_return_disputed') return Icons.gavel_outlined;
  if (type == 'rent_terminated_by_owner') return Icons.warning_amber_rounded;
  if (type == 'donation_request') return Icons.volunteer_activism_outlined;
  if (type == 'donation_request_decision') return Icons.rule_folder_outlined;
  if (type == 'calamity_donation') return Icons.emergency_outlined;
  if (type == 'calamity_event_created') return Icons.crisis_alert;
  if (type == 'verification_rejected') return Icons.warning_amber_rounded;
  if (type == 'verification_approved') return Icons.verified;
  if (type == 'violation_issued') return Icons.warning_amber_rounded;
  if (type == 'report_resolved') return Icons.verified_user;
  if (type == 'account_suspended') return Icons.block;
  if (type == 'rental_overdue' || type == 'rental_overdue_owner') {
    return Icons.warning_amber_rounded;
  }
  if (type == 'item_overdue' || type == 'item_overdue_lender') {
    return Icons.warning_amber_rounded;
  }
  if (type == 'return_reminder_24h' ||
      type == 'return_reminder_1h' ||
      type == 'return_reminder_due') {
    return Icons.notifications_active;
  }
  if (type.startsWith('trade')) return Icons.swap_horiz;
  if (type.startsWith('rent')) return Icons.home_repair_service_outlined;
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
  } catch (_) {}
}

Future<void> _clearRead(String userId) async {
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
  } catch (_) {}
}
