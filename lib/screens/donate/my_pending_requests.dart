import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/giveaway_claim_request_model.dart';
import '../../models/giveaway_listing_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../reusable_widgets/bottom_nav_bar_widget.dart';

class MyPendingRequestsScreen extends StatefulWidget {
  const MyPendingRequestsScreen({super.key});

  @override
  State<MyPendingRequestsScreen> createState() =>
      _MyPendingRequestsScreenState();
}

class _MyPendingRequestsScreenState extends State<MyPendingRequestsScreen> {
  final FirestoreService _firestore = FirestoreService();

  static const Color _primaryColor = Color(0xFF2A7A9E);

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final currentUserId = authProvider.user?.uid;

    if (currentUserId == null || currentUserId.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          title: const Text(
            'My Pending Requests',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        body: const Center(
          child: Text('Please sign in to view your pending requests'),
        ),
      );
    }

    // Query for pending claim requests made by the current user
    final pendingRequestsQuery = FirebaseFirestore.instance
        .collection('giveaway_claims')
        .where('claimantId', isEqualTo: currentUserId)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'My Pending Requests',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: pendingRequestsQuery.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            final error = snapshot.error;
            final isIndexError =
                error.toString().contains('index') ||
                error.toString().contains('requires an index');
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.orange[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isIndexError
                          ? 'Firestore Index Required'
                          : 'Error loading requests',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[800],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange[200]!),
                      ),
                      child: Text(
                        isIndexError
                            ? 'Please deploy the indexes from firestore.indexes.json to Firebase Console.'
                            : 'An error occurred while loading requests.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.orange[900],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async {
                // StreamBuilder will automatically refresh
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.7,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.pending_actions_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No pending requests',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Your giveaway claim requests will appear here',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          final docs = snapshot.data!.docs;
          return RefreshIndicator(
            onRefresh: () async {
              // StreamBuilder will automatically refresh
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final claimData = docs[index].data();
                final claimId = docs[index].id;
                final claim = GiveawayClaimRequestModel.fromMap(
                  claimData,
                  claimId,
                );
                return _buildRequestCard(claim);
              },
            ),
          );
        },
      ),
      bottomNavigationBar: BottomNavBarWidget(
        selectedIndex: 1, // Exchange tab (Give is part of Exchange)
        onTap: (_) {},
        navigationContext: context,
      ),
    );
  }

  Widget _buildRequestCard(GiveawayClaimRequestModel claim) {
    return FutureBuilder<GiveawayListingModel?>(
      future: _loadGiveaway(claim.giveawayId),
      builder: (context, snapshot) {
        final giveaway = snapshot.data;

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image Section
              if (giveaway != null && giveaway.hasImages)
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                  child: Image.network(
                    giveaway.images.first,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        height: 180,
                        color: Colors.grey[200],
                        child: const Icon(Icons.image_not_supported, size: 48),
                      );
                    },
                  ),
                ),
              // Content Section
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Row(
                      children: [
                        Icon(
                          Icons.card_giftcard,
                          color: _primaryColor,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            giveaway?.title ?? 'Giveaway Item',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Pending',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Donor Info
                    Row(
                      children: [
                        Icon(
                          Icons.person_outline,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Donor: ${giveaway?.donorName ?? 'Unknown'}',
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Location
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 16,
                          color: _primaryColor,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            giveaway?.location ?? 'Location not available',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (claim.message != null && claim.message!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Your Message:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[700],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              claim.message!,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[800],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    // Request Date
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: 14,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Requested: ${_formatDate(claim.createdAt)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pushNamed(
                                context,
                                '/giveaway/detail',
                                arguments: {'giveawayId': claim.giveawayId},
                              );
                            },
                            icon: const Icon(Icons.visibility, size: 18),
                            label: const Text('View Giveaway'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _primaryColor,
                              side: BorderSide(color: _primaryColor),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _cancelRequest(claim),
                            icon: const Icon(Icons.cancel_outlined, size: 18),
                            label: const Text('Cancel'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<GiveawayListingModel?> _loadGiveaway(String giveawayId) async {
    try {
      final data = await _firestore.getGiveaway(giveawayId);
      if (data == null) return null;
      return GiveawayListingModel.fromMap(data, giveawayId);
    } catch (e) {
      debugPrint('Error loading giveaway: $e');
      return null;
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

  Future<void> _cancelRequest(GiveawayClaimRequestModel claim) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Request'),
        content: const Text(
          'Are you sure you want to cancel this claim request?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _firestore.updateClaimRequest(claim.id, {
        'status': 'cancelled',
        'updatedAt': DateTime.now(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request cancelled successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cancelling request: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
