import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../../providers/admin_provider.dart';

class ActivityMonitoringTab extends StatefulWidget {
  const ActivityMonitoringTab({super.key});

  @override
  State<ActivityMonitoringTab> createState() => _ActivityMonitoringTabState();
}

class _ActivityMonitoringTabState extends State<ActivityMonitoringTab> {
  int _selectedCategory = 0; // 0 Borrow, 1 Rent, 2 Trade, 3 Give

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
              ],
            ),
          ),
          const SizedBox(height: 16),
          _ActivityCategoryBar(
            onCategoryChanged: (index) {
              setState(() => _selectedCategory = index);
            },
          ),
          const SizedBox(height: 16),
          Expanded(child: _getActivitySection(context)),
        ],
      ),
    );
  }

  Widget _getActivitySection(BuildContext context) {
    switch (_selectedCategory) {
      case 0:
        return const _BorrowActivitiesSection();
      case 1:
        return const _RentalActivitiesSection();
      case 2:
        return const _TradeActivitiesSection();
      case 3:
        return const _GiveawayActivitiesSection();
      default:
        return const _BorrowActivitiesSection();
    }
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
          child: ChoiceChip(
            selected: selected,
            label: Row(
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
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
            selectedColor: Colors.transparent,
            backgroundColor: Colors.transparent,
            onSelected: (_) {
              setState(() => _index = i);
              widget.onCategoryChanged(i);
            },
          ),
        );
      }),
    );
  }
}

class _BorrowActivitiesSection extends StatelessWidget {
  const _BorrowActivitiesSection();
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
              final docs = snapshot.data?.docs ?? [];
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
  const _RentalActivitiesSection();
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
              final docs = snapshot.data?.docs ?? [];
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
                  final renterName = (d['renterName'] ?? 'Renter') as String;
                  final ownerName = (d['ownerName'] ?? 'Owner') as String;
                  final status = (d['status'] ?? 'pending') as String;
                  DateTime? ts;
                  final createdAt = d['createdAt'];
                  if (createdAt is Timestamp) ts = createdAt.toDate();

                  return _ActivityCard(
                    title: '$renterName → $ownerName',
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

class _TradeActivitiesSection extends StatelessWidget {
  const _TradeActivitiesSection();
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
              final docs = snapshot.data?.docs ?? [];
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
  const _GiveawayActivitiesSection();
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
              final docs = snapshot.data?.docs ?? [];
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
