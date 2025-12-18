import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/giveaway_claim_request_model.dart';
import '../../models/giveaway_listing_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/giveaway_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/user_provider.dart';
import '../../reusable_widgets/bottom_nav_bar_widget.dart';
import '../chat_detail_screen.dart';

class ApprovedClaimsScreen extends StatefulWidget {
  const ApprovedClaimsScreen({super.key});

  @override
  State<ApprovedClaimsScreen> createState() => _ApprovedClaimsScreenState();
}

class _ApprovedClaimsScreenState extends State<ApprovedClaimsScreen> {
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
            'Approved Claims',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        body: const Center(
          child: Text('Please sign in to view approved claims'),
        ),
      );
    }

    // Query for approved claims on user's giveaways
    // Note: Using orderBy on 'approvedAt' requires a composite index.
    // If index is missing, Firestore will throw an error with a link to create it.
    // Fallback: If approvedAt field is missing on documents, they won't appear in results.
    final approvedClaimsQuery = FirebaseFirestore.instance
        .collection('giveaway_claims')
        .where('donorId', isEqualTo: currentUserId)
        .where('status', isEqualTo: 'approved')
        .orderBy('approvedAt', descending: true);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Approved Claims',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: approvedClaimsQuery.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading claims',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    snapshot.error.toString(),
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                    textAlign: TextAlign.center,
                  ),
                ],
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
                          Icons.check_circle_outline,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No approved claims',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Approved claims on your giveaways will appear here',
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
                return _buildClaimCard(claim);
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

  Widget _buildClaimCard(GiveawayClaimRequestModel claim) {
    // Use StreamBuilder to listen to real-time updates
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('giveaways')
          .doc(claim.giveawayId)
          .snapshots(),
      builder: (context, snapshot) {
        GiveawayListingModel? giveaway;
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data()!;
          data['id'] = snapshot.data!.id;
          giveaway = GiveawayListingModel.fromMap(data, snapshot.data!.id);
        } else if (snapshot.connectionState == ConnectionState.waiting) {
          // Show loading state
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 12),
                Text('Loading giveaway details...'),
              ],
            ),
          );
        }

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
              // Giveaway Info Section
              if (giveaway != null)
                InkWell(
                  onTap: () {
                    Navigator.pushNamed(
                      context,
                      '/giveaway/detail',
                      arguments: {'giveawayId': claim.giveawayId},
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: Row(
                      children: [
                        // Giveaway Image
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.grey[200],
                            image:
                                giveaway.hasImages && giveaway.images.isNotEmpty
                                ? DecorationImage(
                                    image: NetworkImage(giveaway.images.first),
                                    fit: BoxFit.cover,
                                    onError: (_, __) {},
                                  )
                                : null,
                          ),
                          child: !giveaway.hasImages
                              ? const Icon(
                                  Icons.image_not_supported_outlined,
                                  color: Colors.grey,
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        // Giveaway Title
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                giveaway.title,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.category_outlined,
                                    size: 14,
                                    color: Colors.grey[600],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    giveaway.category,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: Colors.grey[400]),
                      ],
                    ),
                  ),
                )
              else if (giveaway == null)
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.grey[50],
                  child: const Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.grey),
                      SizedBox(width: 12),
                      Text('Giveaway not found'),
                    ],
                  ),
                ),

              // Claimant Info Section
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Claimant Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.person_outline,
                            color: Colors.green,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Claimed By',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                claim.claimantName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.check_circle,
                                size: 14,
                                color: Colors.green,
                              ),
                              const SizedBox(width: 4),
                              const Text(
                                'APPROVED',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // Message (if provided)
                    if (claim.message != null && claim.message!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.blue.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.message_outlined,
                              size: 16,
                              color: Colors.blue[700],
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                claim.message!,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[800],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Dates Section
                    const SizedBox(height: 12),
                    Column(
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 14,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Requested: ${_formatDate(claim.createdAt)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (claim.approvedAt != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                size: 14,
                                color: Colors.green[700],
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Approved: ${_formatDate(claim.approvedAt!)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.green[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),

                    // Status Badge
                    if (giveaway != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: giveaway.status == GiveawayStatus.completed
                              ? Colors.green.withValues(alpha: 0.1)
                              : Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: giveaway.status == GiveawayStatus.completed
                                ? Colors.green
                                : Colors.orange,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              giveaway.status == GiveawayStatus.completed
                                  ? Icons.check_circle
                                  : Icons.pending,
                              size: 16,
                              color: giveaway.status == GiveawayStatus.completed
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              giveaway.statusDisplay,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color:
                                    giveaway.status == GiveawayStatus.completed
                                    ? Colors.green
                                    : Colors.orange,
                              ),
                            ),
                            if (giveaway.completedAt != null) ...[
                              const SizedBox(width: 6),
                              Text(
                                'on ${_formatDate(giveaway.completedAt!)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],

                    // Action Buttons
                    const SizedBox(height: 16),
                    if (giveaway != null &&
                        giveaway.status == GiveawayStatus.claimed) ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _markAsCompleted(claim, giveaway!),
                          icon: const Icon(Icons.check_circle),
                          label: const Text('Mark as Completed'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: giveaway != null
                            ? () => _messageClaimant(claim, giveaway)
                            : null,
                        icon: const Icon(Icons.message),
                        label: const Text('Message Claimant'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pushNamed(
                            context,
                            '/giveaway/detail',
                            arguments: {'giveawayId': claim.giveawayId},
                          );
                        },
                        icon: const Icon(Icons.visibility),
                        label: const Text('View Giveaway Details'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _primaryColor,
                          side: BorderSide(color: _primaryColor),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
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

  Future<void> _messageClaimant(
    GiveawayClaimRequestModel claim,
    GiveawayListingModel? giveaway,
  ) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    final currentUserId = authProvider.user?.uid;
    final currentUser = userProvider.currentUser;

    if (currentUserId == null || currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to send a message'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final conversationId = await chatProvider.createOrGetConversation(
        userId1: currentUserId,
        userId1Name: currentUser.fullName,
        userId2: claim.claimantId,
        userId2Name: claim.claimantName,
        itemId: claim.giveawayId,
        itemTitle: giveaway?.title ?? 'Giveaway Item',
      );

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      if (conversationId != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatDetailScreen(
              conversationId: conversationId,
              otherParticipantName: claim.claimantName,
              userId: currentUserId,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to start conversation'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _markAsCompleted(
    GiveawayClaimRequestModel claim,
    GiveawayListingModel giveaway,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Mark as Completed?',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        content: Text(
          'Have you completed the pickup/delivery of "${giveaway.title}" with ${claim.claimantName}? This will mark the donation as completed.',
          style: const TextStyle(fontSize: 14),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Mark as Completed',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Show loading
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final giveawayProvider = Provider.of<GiveawayProvider>(
      context,
      listen: false,
    );

    final success = await giveawayProvider.markGiveawayAsCompleted(
      giveawayId: giveaway.id,
    );

    if (!mounted) return;
    Navigator.pop(context); // Close loading dialog

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Donation marked as completed successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            giveawayProvider.errorMessage ?? 'Failed to mark as completed',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'just now';
        }
        return '${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'} ago';
      }
      return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
    } else if (difference.inDays == 1) {
      return 'yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
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
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    }
  }
}
