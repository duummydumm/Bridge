import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/firestore_service.dart';
import '../../services/report_block_service.dart';
import '../../models/trade_offer_model.dart';
import '../../reusable_widgets/bottom_nav_bar_widget.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';

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
  bool _isLoading = true;
  Map<String, dynamic>? _offer;
  String? _error;

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
      setState(() {
        _offer = offer;
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
          const SizedBox(height: 16),
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

    String selectedReason = 'spam';
    final TextEditingController descriptionController = TextEditingController();
    final offer = TradeOfferModel.fromMap(_offer!, widget.offerId);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Report Trade Offer'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Please select a reason for reporting:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                RadioListTile<String>(
                  title: const Text('Spam'),
                  value: 'spam',
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setDialogState(() {
                      selectedReason = value!;
                    });
                  },
                ),
                RadioListTile<String>(
                  title: const Text('Inappropriate Content'),
                  value: 'inappropriate_content',
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setDialogState(() {
                      selectedReason = value!;
                    });
                  },
                ),
                RadioListTile<String>(
                  title: const Text('Fraud'),
                  value: 'fraud',
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setDialogState(() {
                      selectedReason = value!;
                    });
                  },
                ),
                RadioListTile<String>(
                  title: const Text('Other'),
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
                    labelText: 'Additional details (optional)',
                    hintText: 'Please provide more information...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                // Store parent context before closing dialog
                final parentContext = context;
                Navigator.pop(parentContext);

                final authProvider = Provider.of<AuthProvider>(
                  parentContext,
                  listen: false,
                );
                final userProvider = Provider.of<UserProvider>(
                  parentContext,
                  listen: false,
                );

                if (authProvider.user == null) return;

                final reporterName =
                    userProvider.currentUser?.fullName ??
                    authProvider.user!.email ??
                    'Unknown';

                try {
                  await _reportBlockService.reportContent(
                    reporterId: authProvider.user!.uid,
                    reporterName: reporterName,
                    contentType: 'trade',
                    contentId: widget.offerId,
                    contentTitle: 'Trade Offer: ${offer.offeredItemName}',
                    ownerId: offer.fromUserId,
                    ownerName: offer.fromUserName,
                    reason: selectedReason,
                    description: descriptionController.text.trim().isNotEmpty
                        ? descriptionController.text.trim()
                        : null,
                  );

                  if (mounted) {
                    ScaffoldMessenger.of(parentContext).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Trade offer has been reported successfully. Thank you for keeping the community safe.',
                        ),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 3),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(parentContext).showSnackBar(
                      SnackBar(
                        content: Text('Error reporting trade offer: $e'),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }
                }
              },
              child: const Text(
                'Report',
                style: TextStyle(color: Colors.orange),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _reportUser() {
    if (_offer == null) return;

    String selectedReason = 'spam';
    final TextEditingController descriptionController = TextEditingController();
    final offer = TradeOfferModel.fromMap(_offer!, widget.offerId);

    // Determine which user to report (the other party)
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = authProvider.user?.uid;

    if (currentUserId == null) return;

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

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Report User'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Please select a reason for reporting:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                RadioListTile<String>(
                  title: const Text('Spam'),
                  value: 'spam',
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setDialogState(() {
                      selectedReason = value!;
                    });
                  },
                ),
                RadioListTile<String>(
                  title: const Text('Harassment'),
                  value: 'harassment',
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setDialogState(() {
                      selectedReason = value!;
                    });
                  },
                ),
                RadioListTile<String>(
                  title: const Text('Inappropriate Content'),
                  value: 'inappropriate_content',
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setDialogState(() {
                      selectedReason = value!;
                    });
                  },
                ),
                RadioListTile<String>(
                  title: const Text('Fraud'),
                  value: 'fraud',
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setDialogState(() {
                      selectedReason = value!;
                    });
                  },
                ),
                RadioListTile<String>(
                  title: const Text('Other'),
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
                    labelText: 'Additional details (optional)',
                    hintText: 'Please provide more information...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                // Store parent context before closing dialog
                final parentContext = context;
                Navigator.pop(parentContext);

                final userProvider = Provider.of<UserProvider>(
                  parentContext,
                  listen: false,
                );

                if (authProvider.user == null) return;

                final reporterName =
                    userProvider.currentUser?.fullName ??
                    authProvider.user!.email ??
                    'Unknown';

                try {
                  await _reportBlockService.reportUser(
                    reporterId: authProvider.user!.uid,
                    reporterName: reporterName,
                    reportedUserId: reportedUserId,
                    reportedUserName: reportedUserName,
                    reason: selectedReason,
                    description: descriptionController.text.trim().isNotEmpty
                        ? descriptionController.text.trim()
                        : null,
                    contextType: 'trade',
                    contextId: widget.offerId,
                  );

                  if (mounted) {
                    ScaffoldMessenger.of(parentContext).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'User has been reported successfully. Thank you for keeping the community safe.',
                        ),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 3),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(parentContext).showSnackBar(
                      SnackBar(
                        content: Text('Error reporting user: $e'),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }
                }
              },
              child: const Text(
                'Report',
                style: TextStyle(color: Colors.orange),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
