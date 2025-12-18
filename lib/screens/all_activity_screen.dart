import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import 'rental/active_rental_detail_screen.dart';

class AllActivityScreen extends StatefulWidget {
  const AllActivityScreen({super.key});

  @override
  State<AllActivityScreen> createState() => _AllActivityScreenState();
}

class _AllActivityScreenState extends State<AllActivityScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _activities = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final userId = auth.user?.uid;
      if (userId == null) {
        setState(() {
          _isLoading = false;
          _activities = [];
        });
      } else {
        _loadActivities(userId);
      }
    });
  }

  Future<void> _loadActivities(String userId) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final service = FirestoreService();
      final allActivities = <Map<String, dynamic>>[];

      // 1. Borrow activities
      final pendingBorrow = await service.getPendingBorrowRequestsForBorrower(
        userId,
      );
      for (final req in pendingBorrow) {
        allActivities.add({
          'type': 'borrow',
          'subtype': 'pending',
          'title': req.itemTitle.isNotEmpty ? req.itemTitle : 'Item',
          'subtitle': 'Borrow request pending',
          'icon': Icons.shopping_cart_outlined,
          'iconColor': Colors.orange,
          'status': 'pending',
          'createdAt': req.createdAt,
          'itemId': req.itemId,
          'requestId': req.id,
        });
      }

      final borrowed = await service.getBorrowedItemsByBorrower(userId);
      for (final item in borrowed) {
        allActivities.add({
          'type': 'borrow',
          'subtype': 'active',
          'title': (item['title'] ?? 'Item').toString(),
          'subtitle': 'Currently borrowed',
          'icon': Icons.check_circle_outline,
          'iconColor': Colors.green,
          'status': 'approved',
          'createdAt': item['borrowedAt'] ?? item['createdAt'],
          'itemId': item['id'],
        });
      }

      // 2. Rent activities
      final pendingRent = await service.getPendingRentalRequestsForRenter(
        userId,
      );
      for (final req in pendingRent) {
        allActivities.add({
          'type': 'rent',
          'subtype': 'pending',
          'title': (req['itemTitle'] ?? 'Rental Item').toString(),
          'subtitle': 'Rental request pending',
          'icon': Icons.attach_money,
          'iconColor': Colors.blue,
          'status': 'pending',
          'createdAt': req['createdAt'],
          'requestId': req['id'],
          'listingId': req['listingId'],
        });
      }

      final rentRequests = await service.getRentalRequestsByUser(
        userId,
        asOwner: false,
      );
      for (final req in rentRequests) {
        final status = (req['status'] ?? 'requested').toString().toLowerCase();
        // Active rentals include: ownerapproved, active, returninitiated
        if (status == 'ownerapproved' ||
            status == 'active' ||
            status == 'returninitiated') {
          allActivities.add({
            'type': 'rent',
            'subtype': 'active',
            'title': (req['itemTitle'] ?? 'Rental Item').toString(),
            'subtitle': 'Rental active',
            'icon': Icons.check_circle_outline,
            'iconColor': Colors.green,
            'status': status,
            'createdAt': req['createdAt'],
            'requestId': req['id'],
            'listingId': req['listingId'],
          });
        }
      }

      // 3. Trade activities
      final tradeOffers = await service.getPendingTradeOffersForUser(userId);
      for (final offer in tradeOffers) {
        allActivities.add({
          'type': 'trade',
          'subtype': 'pending',
          'title': (offer['originalOfferedItemName'] ?? 'Trade Item')
              .toString(),
          'subtitle': 'Trade offer pending',
          'icon': Icons.swap_horiz,
          'iconColor': Colors.purple,
          'status': 'pending',
          'createdAt': offer['createdAt'],
          'offerId': offer['id'],
          'tradeItemId': offer['tradeItemId'],
        });
      }

      final allTradeOffers = await service.getTradeOffersByUser(userId);
      for (final offer in allTradeOffers) {
        final status = (offer['status'] ?? 'pending').toString();
        if (status == 'approved' || status == 'completed') {
          allActivities.add({
            'type': 'trade',
            'subtype': 'completed',
            'title': (offer['originalOfferedItemName'] ?? 'Trade Item')
                .toString(),
            'subtitle': 'Trade completed',
            'icon': Icons.check_circle_outline,
            'iconColor': Colors.green,
            'status': status,
            'createdAt': offer['createdAt'],
            'offerId': offer['id'],
            'tradeItemId': offer['tradeItemId'],
          });
        }
      }

      // 4. Donate/Giveaway activities
      final claimRequests = await service.getClaimRequestsByClaimant(userId);
      for (final claim in claimRequests) {
        final status = (claim['status'] ?? 'pending').toString();
        // Fetch giveaway title if available
        String giveawayTitle = 'Giveaway Item';
        final giveawayId = (claim['giveawayId'] ?? '').toString();
        if (giveawayId.isNotEmpty) {
          try {
            final giveaway = await service.getGiveaway(giveawayId);
            if (giveaway != null) {
              giveawayTitle = (giveaway['title'] ?? 'Giveaway Item').toString();
            }
          } catch (_) {
            // Use default if fetch fails
          }
        }
        allActivities.add({
          'type': 'donate',
          'subtype': status == 'approved' ? 'claimed' : 'pending',
          'title': giveawayTitle,
          'subtitle': status == 'approved'
              ? 'Giveaway claimed'
              : 'Claim request pending',
          'icon': status == 'approved' ? Icons.card_giftcard : Icons.pending,
          'iconColor': status == 'approved' ? Colors.green : Colors.orange,
          'status': status,
          'createdAt': claim['createdAt'],
          'claimId': claim['id'],
          'giveawayId': giveawayId,
        });
      }

      // Sort by date (most recent first)
      allActivities.sort((a, b) {
        final aDate = _parseActivityDate(a['createdAt']);
        final bDate = _parseActivityDate(b['createdAt']);
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate); // Descending order
      });

      if (mounted) {
        setState(() {
          _activities = allActivities;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _activities = [];
        });
      }
    }
  }

  DateTime? _parseActivityDate(dynamic dateValue) {
    if (dateValue == null) return null;
    if (dateValue is DateTime) return dateValue;
    if (dateValue is Timestamp) return dateValue.toDate();
    if (dateValue is int) {
      return DateTime.fromMillisecondsSinceEpoch(dateValue);
    }
    return null;
  }

  void _handleActivityTap(Map<String, dynamic> activity) {
    final type = activity['type'] as String;
    HapticFeedback.selectionClick();

    if (type == 'borrow') {
      if (activity['subtype'] == 'pending') {
        Navigator.pushNamed(context, '/pending-requests');
      } else {
        Navigator.pushNamed(context, '/borrowed-items-detail');
      }
    } else if (type == 'rent') {
      if (activity['subtype'] == 'pending') {
        Navigator.pushNamed(context, '/pending-requests');
      } else {
        // Active rental - navigate to active rental detail
        final requestId = activity['requestId'] as String?;
        if (requestId != null && requestId.isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  ActiveRentalDetailScreen(requestId: requestId),
            ),
          );
        } else {
          Navigator.pushNamed(context, '/pending-requests');
        }
      }
    } else if (type == 'trade') {
      Navigator.pushNamed(context, '/trade');
    } else if (type == 'donate') {
      Navigator.pushNamed(context, '/giveaway');
    }
  }

  Widget _buildActivityItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String status,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap:
            onTap ??
            () {
              HapticFeedback.selectionClick();
            },
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: iconColor.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 3),
                spreadRadius: 0,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      iconColor.withValues(alpha: 0.2),
                      iconColor.withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: iconColor.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Icon(icon, color: iconColor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        letterSpacing: -0.2,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                        height: 1.2,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [iconColor, iconColor.withValues(alpha: 0.8)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: iconColor.withValues(alpha: 0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  status,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('All Activity')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _activities.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.inbox_outlined,
                      size: 48,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No recent activity',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your borrow, rent, trade, and donate activities will appear here',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            : ListView.builder(
                itemCount: _activities.length,
                itemBuilder: (context, index) {
                  final activity = _activities[index];
                  return _buildActivityItem(
                    icon: activity['icon'] as IconData,
                    iconColor: activity['iconColor'] as Color,
                    title: activity['title'] as String,
                    subtitle: activity['subtitle'] as String,
                    status: activity['status'] as String,
                    onTap: () => _handleActivityTap(activity),
                  );
                },
              ),
      ),
    );
  }
}
