import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/firestore_service.dart';
import '../../services/report_block_service.dart';
import '../../services/rating_service.dart';
import '../../reusable_widgets/report_dialog.dart';
import '../../models/trade_offer_model.dart';
import '../../models/rating_model.dart';
import '../../reusable_widgets/bottom_nav_bar_widget.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/chat_provider.dart';
import '../chat_detail_screen.dart';
import '../submit_rating_screen.dart';

class TradeOfferDetailScreen extends StatefulWidget {
  final String offerId;
  final bool canAcceptDecline; // Whether user can accept/decline

  const TradeOfferDetailScreen({
    super.key,
    required this.offerId,
    this.canAcceptDecline = false,
  });

  @override
  State<TradeOfferDetailScreen> createState() => _TradeOfferDetailScreenState();
}

class _TradeOfferDetailScreenState extends State<TradeOfferDetailScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final ReportBlockService _reportBlockService = ReportBlockService();
  final RatingService _ratingService = RatingService();
  bool _isLoading = true;
  Map<String, dynamic>? _offer;
  String? _error;
  bool _hasSubmittedRating = false;

  // BRIDGE Trade theme color
  static const Color _primaryColor = Color(0xFF2A7A9E);

  @override
  void initState() {
    super.initState();
    _loadOffer();
  }

  Future<void> _loadOffer() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final offer = await _firestoreService.getTradeOffer(widget.offerId);
      if (offer == null) {
        setState(() {
          _error = 'Trade offer not found';
          _isLoading = false;
        });
        return;
      }

      bool hasRating = false;
      try {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final currentUserId = authProvider.user?.uid;
        if (currentUserId != null) {
          final offerModel = TradeOfferModel.fromMap(offer, widget.offerId);
          // Determine other user for rating purposes
          final otherUserId = currentUserId == offerModel.fromUserId
              ? offerModel.toUserId
              : offerModel.fromUserId;
          hasRating = await _ratingService.hasRated(
            raterUserId: currentUserId,
            ratedUserId: otherUserId,
            transactionId: widget.offerId,
          );
        }
      } catch (_) {
        hasRating = false;
      }

      setState(() {
        _offer = offer;
        _hasSubmittedRating = hasRating;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _acceptOffer() async {
    if (_offer == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Accept Trade Offer'),
        content: const Text(
          'Are you sure you want to accept this trade offer? This will decline all other pending offers for this item.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.green),
            child: const Text('Accept'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await _firestoreService.acceptTradeOffer(
        offerId: widget.offerId,
        tradeItemId: _offer!['tradeItemId'] as String,
      );
      if (mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Trade offer accepted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context); // Return to previous screen
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error accepting offer: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _declineOffer() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Decline Trade Offer'),
        content: const Text(
          'Are you sure you want to decline this trade offer?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Decline'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await _firestoreService.declineTradeOffer(offerId: widget.offerId);
      if (mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Trade offer declined'),
            backgroundColor: Colors.orange,
          ),
        );
        Navigator.pop(context); // Return to previous screen
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error declining offer: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _completeTrade() async {
    if (_offer == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark Trade as Completed'),
        content: const Text(
          'Have you completed the physical exchange of items? This will mark the trade as completed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.blue),
            child: const Text('Mark Completed'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await _firestoreService.completeTradeOffer(offerId: widget.offerId);
      if (mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Trade marked as completed!'),
            backgroundColor: Colors.green,
          ),
        );
        _loadOffer(); // Reload to show updated status
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error completing trade: $e'),
            backgroundColor: Colors.red,
          ),
        );
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

  String _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'orange';
      case 'approved':
        return 'green';
      case 'declined':
        return 'red';
      case 'completed':
        return 'blue';
      case 'cancelled':
        return 'grey';
      default:
        return 'grey';
    }
  }

  /// Start or open a chat with the other party in this trade offer
  Future<void> _startChatWithOtherUser(TradeOfferModel offer) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    if (authProvider.user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to message the other user'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final currentUserId = authProvider.user!.uid;
    final currentUserName =
        userProvider.currentUser?.fullName.isNotEmpty == true
        ? userProvider.currentUser!.fullName
        : (authProvider.user!.email ?? 'You');

    // Determine other participant based on who is viewing
    late final String otherUserId;
    late final String otherUserName;
    if (currentUserId == offer.fromUserId) {
      otherUserId = offer.toUserId;
      otherUserName = offer.toUserName;
    } else {
      otherUserId = offer.fromUserId;
      otherUserName = offer.fromUserName;
    }

    if (otherUserId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not determine the other user for this trade'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Show a small loading dialog while creating / fetching the conversation
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final conversationId = await chatProvider.createOrGetConversation(
        userId1: currentUserId,
        userId1Name: currentUserName,
        userId2: otherUserId,
        userId2Name: otherUserName,
        itemId: offer.tradeItemId,
        itemTitle: offer.originalOfferedItemName,
      );

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // close loading

      if (conversationId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to start conversation'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatDetailScreen(
            conversationId: conversationId,
            otherParticipantName: otherUserName,
            userId: currentUserId,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error starting chat: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Navigate to the counter-offer flow as the listing owner
  Future<void> _startCounterOffer(TradeOfferModel offer) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (authProvider.user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to make a counter-offer'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Only the listing owner (offer.toUserId) should be able to counter
    if (authProvider.user!.uid != offer.toUserId) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only the listing owner can make a counter-offer'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    Navigator.pushNamed(
      context,
      '/trade/make-offer',
      arguments: {
        'tradeItemId': offer.tradeItemId,
        'isCounter': 'true',
        'counterToUserId': offer.fromUserId,
        'counterToUserName': offer.fromUserName,
        'parentOfferId': offer.id,
      },
    );
  }

  /// Start the post-trade rating flow for the other user
  Future<void> _startRating(TradeOfferModel offer) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (authProvider.user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to leave a rating'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final currentUserId = authProvider.user!.uid;
    // Determine who we are rating
    late final String otherUserId;
    late final String otherUserName;
    late final String role;

    if (currentUserId == offer.fromUserId) {
      otherUserId = offer.toUserId;
      otherUserName = offer.toUserName;
      role = 'trade_offer_initiator';
    } else if (currentUserId == offer.toUserId) {
      otherUserId = offer.fromUserId;
      otherUserName = offer.fromUserName;
      role = 'trade_listing_owner';
    } else {
      // Not a party in this trade
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only participants in this trade can leave a rating'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!mounted) return;
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SubmitRatingScreen(
          ratedUserId: otherUserId,
          ratedUserName: otherUserName,
          context: RatingContext.trade,
          transactionId: offer.id,
          role: role,
        ),
      ),
    );

    if (result == true && mounted) {
      setState(() {
        _hasSubmittedRating = true;
      });
    }
  }

  /// Open a dispute about a completed trade
  Future<void> _startDispute(TradeOfferModel offer) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (authProvider.user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to report a trade issue'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final currentUserId = authProvider.user!.uid;
    final currentUserName = authProvider.user!.email ?? 'You';

    // Only parties in the trade can open a dispute
    late final String otherUserId;
    late final String otherUserName;
    late final String role;

    if (currentUserId == offer.fromUserId) {
      otherUserId = offer.toUserId;
      otherUserName = offer.toUserName;
      role = 'trade_offer_initiator';
    } else if (currentUserId == offer.toUserId) {
      otherUserId = offer.fromUserId;
      otherUserName = offer.fromUserName;
      role = 'trade_listing_owner';
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only participants in this trade can open a dispute'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    String selectedReason = 'item_not_as_described';
    final TextEditingController descriptionController = TextEditingController();

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Report Trade Issue'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'What went wrong with this trade?',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                RadioListTile<String>(
                  title: const Text('Item not received'),
                  value: 'item_not_received',
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setDialogState(() {
                      selectedReason = value!;
                    });
                  },
                ),
                RadioListTile<String>(
                  title: const Text('Item significantly different / damaged'),
                  value: 'item_not_as_described',
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setDialogState(() {
                      selectedReason = value!;
                    });
                  },
                ),
                RadioListTile<String>(
                  title: const Text('Suspected fraud or unsafe behavior'),
                  value: 'fraud_or_safety',
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setDialogState(() {
                      selectedReason = value!;
                    });
                  },
                ),
                RadioListTile<String>(
                  title: const Text('Other issue'),
                  value: 'other',
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setDialogState(() {
                      selectedReason = value!;
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Describe the issue (required)',
                    hintText: 'Provide details to help admins review this case',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 4,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (descriptionController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Please provide a short description of the issue',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                Navigator.pop(context, true);
              },
              child: const Text('Submit', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _firestoreService.createTradeDispute({
        'offerId': offer.id,
        'tradeItemId': offer.tradeItemId,
        'itemTitle': offer.originalOfferedItemName,
        'openedByUserId': currentUserId,
        'openedByUserName': currentUserName,
        'otherUserId': otherUserId,
        'otherUserName': otherUserName,
        'reason': selectedReason,
        'description': descriptionController.text.trim(),
        'status': 'open',
        'role': role,
        'createdAt': DateTime.now(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Your trade issue has been recorded. Our team may review this case.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error creating dispute: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: _primaryColor,
        elevation: 0,
        title: const Text(
          'Trade Offer Details',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.flag_outlined, color: Colors.white),
            onPressed: _offer != null ? () => _showReportOptions() : null,
            tooltip: 'Report',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Go Back'),
                    ),
                  ],
                ),
              ),
            )
          : _offer == null
          ? const Center(child: Text('Trade offer not found'))
          : _buildOfferDetails(),
      bottomNavigationBar: BottomNavBarWidget(
        selectedIndex: null,
        onTap: (_) {},
        navigationContext: context,
      ),
    );
  }

  Widget _buildOfferDetails() {
    final offer = TradeOfferModel.fromMap(_offer!, widget.offerId);
    final createdAt = offer.createdAt;
    final status = offer.statusDisplay;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status Badge
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: _getStatusColor(status) == 'orange'
                    ? Colors.orange
                    : _getStatusColor(status) == 'green'
                    ? Colors.green
                    : _getStatusColor(status) == 'red'
                    ? Colors.red
                    : Colors.grey,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                status,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Trade Visualization
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // They Offer Section
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.inventory_2, color: _primaryColor),
                          const SizedBox(width: 8),
                          Text(
                            'They Offer',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (offer.offeredItemImageUrl != null)
                        Container(
                          height: 200,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.grey[200],
                            image: DecorationImage(
                              image: NetworkImage(offer.offeredItemImageUrl!),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Text(
                        offer.offeredItemName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (offer.offeredItemDescription != null &&
                          offer.offeredItemDescription!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          offer.offeredItemDescription!,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Swap Icon
                  const Icon(Icons.swap_vert, size: 48, color: _primaryColor),
                  const SizedBox(height: 24),
                  // You Offer Section
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.search, color: _primaryColor),
                          const SizedBox(width: 8),
                          Text(
                            'You Offer',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (offer.originalOfferedItemImageUrl != null)
                        Container(
                          height: 200,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.grey[200],
                            image: DecorationImage(
                              image: NetworkImage(
                                offer.originalOfferedItemImageUrl!,
                              ),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Text(
                        offer.originalOfferedItemName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Message Section
          if (offer.message != null && offer.message!.isNotEmpty)
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.message, color: _primaryColor),
                        const SizedBox(width: 8),
                        const Text(
                          'Message',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      offer.message!,
                      style: TextStyle(fontSize: 14, color: Colors.grey[800]),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),

          // Details Section
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: _primaryColor),
                      const SizedBox(width: 8),
                      const Text(
                        'Offer Details',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildDetailRow('From', offer.fromUserName),
                  _buildDetailRow('To', offer.toUserName),
                  _buildDetailRow('Date', _formatDate(createdAt)),
                  _buildDetailRow('Status', status),
                ],
              ),
            ),
          ),

          // Action Buttons
          if (widget.canAcceptDecline && offer.isPending) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _declineOffer,
                    icon: const Icon(Icons.close),
                    label: const Text('Decline'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _acceptOffer,
                    icon: const Icon(Icons.check),
                    label: const Text('Accept'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _startCounterOffer(offer),
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Make Counter Offer'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _primaryColor,
                  side: const BorderSide(color: _primaryColor),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
          // Mark as Completed button for approved trades
          if (offer.isApproved && !widget.canAcceptDecline) ...[
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _completeTrade,
                icon: const Icon(Icons.check_circle),
                label: const Text('Mark Trade as Completed'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
          // Dispute button for completed trades
          if (offer.isCompleted) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _startDispute(offer),
                icon: const Icon(Icons.gavel),
                label: const Text('Report Trade Issue'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
          // Rating button for completed trades (one per user)
          if (offer.isCompleted && !_hasSubmittedRating) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _startRating(offer),
                icon: const Icon(Icons.star_rate),
                label: const Text('Rate Your Trading Partner'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _primaryColor,
                  side: const BorderSide(color: _primaryColor),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          // Message button (for any status)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _startChatWithOtherUser(offer),
              icon: const Icon(Icons.message),
              label: const Text('Message User'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _primaryColor,
                side: const BorderSide(color: _primaryColor),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  void _showReportOptions() {
    if (_offer == null) return;

    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: Colors.orange),
              title: const Text('Report Trade Offer'),
              onTap: () {
                Navigator.pop(context);
                _reportTradeOffer();
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_off, color: Colors.red),
              title: const Text('Report User'),
              onTap: () {
                Navigator.pop(context);
                _reportUser();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _reportTradeOffer() {
    if (_offer == null) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userProvider = Provider.of<UserProvider>(context, listen: false);

    if (authProvider.user == null) return;

    final offer = TradeOfferModel.fromMap(_offer!, widget.offerId);

    ReportDialog.showReportContentDialog(
      context: context,
      contentType: 'trade',
      onSubmit:
          ({
            required String reason,
            String? description,
            List<String>? evidenceImageUrls,
          }) async {
            final reporterName =
                userProvider.currentUser?.fullName ??
                authProvider.user!.email ??
                'Unknown';

            await _reportBlockService.reportContent(
              reporterId: authProvider.user!.uid,
              reporterName: reporterName,
              contentType: 'trade',
              contentId: widget.offerId,
              contentTitle: 'Trade Offer: ${offer.offeredItemName}',
              ownerId: offer.fromUserId,
              ownerName: offer.fromUserName,
              reason: reason,
              description: description,
              evidenceImageUrls: evidenceImageUrls,
            );
          },
      successMessage:
          'Trade offer has been reported successfully. Thank you for keeping the community safe.',
      errorMessage: 'Error reporting trade offer',
    );
  }

  void _reportUser() {
    if (_offer == null) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final currentUserId = authProvider.user?.uid;

    if (currentUserId == null) return;

    final offer = TradeOfferModel.fromMap(_offer!, widget.offerId);

    // Determine which user to report (the other party)
    String reportedUserId;
    String reportedUserName;

    if (currentUserId == offer.fromUserId) {
      // Current user is the offer creator, report the recipient
      reportedUserId = offer.toUserId;
      reportedUserName = offer.toUserName;
    } else {
      // Current user is the recipient, report the offer creator
      reportedUserId = offer.fromUserId;
      reportedUserName = offer.fromUserName;
    }

    ReportDialog.showReportUserDialog(
      context: context,
      reportedUserId: reportedUserId,
      reportedUserName: reportedUserName,
      contextType: 'trade',
      contextId: widget.offerId,
      onSubmit:
          ({
            required String reason,
            String? description,
            List<String>? evidenceImageUrls,
          }) async {
            final reporterName =
                userProvider.currentUser?.fullName ??
                authProvider.user!.email ??
                'Unknown';

            await _reportBlockService.reportUser(
              reporterId: authProvider.user!.uid,
              reporterName: reporterName,
              reportedUserId: reportedUserId,
              reportedUserName: reportedUserName,
              reason: reason,
              description: description,
              contextType: 'trade',
              contextId: widget.offerId,
              evidenceImageUrls: evidenceImageUrls,
            );
          },
      successMessage:
          'User has been reported successfully. Thank you for keeping the community safe.',
      errorMessage: 'Error reporting user',
    );
  }
}
