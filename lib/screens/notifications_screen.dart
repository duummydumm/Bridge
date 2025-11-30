import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'All'),
              Tab(text: 'Borrow Request'),
              Tab(text: 'Trading'),
              Tab(text: 'Rent'),
              Tab(text: 'Donate'),
            ],
          ),
        ),
        body: uid == null
            ? const Center(child: Text('Sign in to view notifications'))
            : _NotificationsTabView(userId: uid),
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

        return TabBarView(
          children: [
            _buildList(context, docs),
            _buildList(
              context,
              docs.where((d) {
                final t = (d.data()['type'] as String?) ?? '';
                return t.startsWith('borrow_') || t == 'item_overdue';
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
                return t.startsWith('donate') ||
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
    if (docs.isEmpty) {
      return const Center(child: Text('No notifications'));
    }
    return ListView.separated(
      itemCount: docs.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final data = docs[index].data();
        final type = data['type'] as String? ?? '';
        final fromName = data['fromUserName'] as String? ?? 'Someone';
        final itemTitle = data['itemTitle'] as String? ?? 'an item';
        final isUnread = data['status'] == 'unread';
        final createdAt = _asDateTime(data['createdAt']);
        final timeText = createdAt == null ? '' : _relativeTime(createdAt);
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
        } else if (type == 'trade_offer') {
          title = '$fromName made a trade offer on "$itemTitle"';
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
          title =
              data['message'] as String? ?? 'Payment received for "$itemTitle"';
        } else if (type == 'rent_payment_reminder') {
          title =
              data['message'] as String? ?? 'Payment reminder for "$itemTitle"';
        } else if (type == 'rent_active') {
          title =
              data['message'] as String? ??
              'Rental is now active for "$itemTitle"';
        } else if (type == 'rent_return_initiated') {
          final renterName = data['renterName'] as String?;
          title = renterName != null
              ? '$renterName initiated return for "$itemTitle"'
              : data['message'] as String? ??
                    'Return initiated for "$itemTitle". Please verify the item.';
        } else if (type == 'rent_return_verified') {
          final ownerName = data['ownerName'] as String?;
          title = ownerName != null
              ? '$ownerName verified return for "$itemTitle". Rental completed!'
              : data['message'] as String? ??
                    'Return verified for "$itemTitle". Rental completed!';
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
            title =
                '⚠️ "$itemTitle" borrowed by $borrowerName is 1 day overdue';
          } else {
            title =
                '⚠️ "$itemTitle" borrowed by $borrowerName is $daysOverdue days overdue';
          }
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
          final eventTitle =
              data['eventTitle'] as String? ?? 'New Calamity Event';
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

        final bgColor = isUnread
            ? Theme.of(context).colorScheme.surfaceTint.withOpacity(0.08)
            : Colors.transparent;
        return Dismissible(
          key: ValueKey(docs[index].id),
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
              try {
                await FirestoreService().markNotificationRead(docs[index].id);
              } catch (_) {}
              return false; // keep in list; stream will update
            } else {
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
                    .doc(docs[index].id)
                    .delete();
              } catch (_) {}
            }
          },
          child: Container(
            color: bgColor,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: Icon(
                _iconForType(type),
                color: isUnread ? const Color(0xFF00897B) : Colors.grey,
              ),
              title: Text(
                title,
                style: TextStyle(
                  fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 15,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  if (type == 'item_overdue' || type == 'item_overdue_lender')
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
                  if (timeText.isNotEmpty)
                    Text(
                      timeText,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                ],
              ),
              trailing: isUnread
                  ? Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Color(0xFF00897B),
                        shape: BoxShape.circle,
                      ),
                    )
                  : null,
              onTap: () async {
                try {
                  await FirestoreService().markNotificationRead(docs[index].id);
                } catch (_) {}

                if (type == 'borrow_request') {
                  final itemId = data['itemId'] as String? ?? '';
                  String? requestId = data['requestId'] as String?;
                  final borrowerId = data['fromUserId'] as String? ?? '';
                  if (requestId == null || requestId.isEmpty) {
                    try {
                      requestId = await FirestoreService()
                          .findPendingBorrowRequestId(
                            itemId: itemId,
                            borrowerId: borrowerId,
                          );
                    } catch (_) {}
                  }
                  if (context.mounted &&
                      requestId != null &&
                      requestId.isNotEmpty) {
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
                  // Navigate to returned items screen (for borrowers)
                  if (context.mounted) {
                    Navigator.of(context).pushNamed('/borrow/returned-items');
                  }
                } else if (type == 'borrow_return_disputed') {
                  // Navigate to disputed returns screen (for borrowers)
                  if (context.mounted) {
                    Navigator.of(context).pushNamed('/borrow/disputed-returns');
                  }
                } else if (type == 'trade_offer') {
                  // Navigate to Trade tab and show My Trades (where offers appear)
                  if (context.mounted) {
                    Navigator.of(context).pushNamedAndRemoveUntil(
                      '/trade',
                      (route) =>
                          route.settings.name == '/home' || route.isFirst,
                    );
                  }
                } else if (type == 'trade_match') {
                  // Navigate to Trade screen and show Matches tab
                  if (context.mounted) {
                    Navigator.of(context).pushNamedAndRemoveUntil(
                      '/trade',
                      (route) =>
                          route.settings.name == '/home' || route.isFirst,
                    );
                    // Note: The Matches tab will show all matches including the new one
                  }
                } else if (type == 'rent_request') {
                  // Navigate to rental request detail screen
                  final requestId = data['requestId'] as String?;
                  if (context.mounted &&
                      requestId != null &&
                      requestId.isNotEmpty) {
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
                    type == 'rent_return_verified') {
                  // Navigate to rental request detail screen or active rental detail
                  final requestId = data['requestId'] as String?;
                  if (context.mounted &&
                      requestId != null &&
                      requestId.isNotEmpty) {
                    // For return notifications, navigate to active rental detail screen
                    if (type == 'rent_return_initiated' ||
                        type == 'rent_return_verified') {
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
                } else if (type == 'donation_request') {
                  // Navigate to Giveaway detail screen
                  final itemId = data['itemId'] as String?;
                  if (context.mounted && itemId != null && itemId.isNotEmpty) {
                    Navigator.of(context).pushNamed(
                      '/giveaway/detail',
                      arguments: {'giveawayId': itemId},
                    );
                  } else if (context.mounted) {
                    // Fallback to giveaways list if itemId not available
                    Navigator.of(context).pushNamedAndRemoveUntil(
                      '/giveaway',
                      (route) =>
                          route.settings.name == '/home' || route.isFirst,
                    );
                  }
                } else if (type == 'calamity_donation') {
                  // Navigate to Calamity Event Detail Admin screen
                  final eventId = data['eventId'] as String?;
                  if (context.mounted &&
                      eventId != null &&
                      eventId.isNotEmpty) {
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
                  if (context.mounted &&
                      eventId != null &&
                      eventId.isNotEmpty) {
                    Navigator.of(context).pushNamed(
                      '/calamity/detail',
                      arguments: {'eventId': eventId},
                    );
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
                            Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.orange,
                            ),
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
                }
              },
            ),
          ),
        );
      },
    );
  }
}

IconData _iconForType(String type) {
  if (type == 'borrow_request') return Icons.handshake_outlined;
  if (type == 'borrow_request_decision') return Icons.rule_folder_outlined;
  if (type == 'borrow_return_initiated') return Icons.assignment_return;
  if (type == 'borrow_return_confirmed') return Icons.verified;
  if (type == 'borrow_return_disputed') return Icons.gavel_outlined;
  if (type == 'trade_offer') return Icons.swap_horiz;
  if (type == 'trade_offer_decision') return Icons.rule_folder_outlined;
  if (type == 'rent_request') return Icons.home_repair_service_outlined;
  if (type == 'rent_request_decision') return Icons.rule_folder_outlined;
  if (type == 'rent_payment_received') return Icons.payment;
  if (type == 'rent_payment_reminder') return Icons.notifications_active;
  if (type == 'rent_active') return Icons.check_circle;
  if (type == 'rent_return_initiated') return Icons.assignment_return;
  if (type == 'rent_return_verified') return Icons.verified;
  if (type == 'donation_request') return Icons.volunteer_activism_outlined;
  if (type == 'donation_request_decision') return Icons.rule_folder_outlined;
  if (type == 'calamity_donation') return Icons.emergency_outlined;
  if (type == 'calamity_event_created') return Icons.crisis_alert;
  if (type == 'verification_rejected') return Icons.warning_amber_rounded;
  if (type == 'violation_issued') return Icons.warning_amber_rounded;
  if (type == 'report_resolved') return Icons.verified_user;
  if (type == 'account_suspended') return Icons.block;
  if (type == 'item_overdue' || type == 'item_overdue_lender')
    return Icons.warning_amber_rounded;
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
