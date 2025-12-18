import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/firestore_service.dart';
import '../../reusable_widgets/bottom_nav_bar_widget.dart';
import '../chat_detail_screen.dart';
import 'active_rental_detail_screen.dart';

class DisputedRentalsScreen extends StatefulWidget {
  const DisputedRentalsScreen({super.key});

  @override
  State<DisputedRentalsScreen> createState() => _DisputedRentalsScreenState();
}

class _DisputedRentalsScreenState extends State<DisputedRentalsScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  bool _isLoading = true;
  List<Map<String, dynamic>> _disputedRentals = [];

  @override
  void initState() {
    super.initState();
    _loadDisputedRentals();
  }

  Future<void> _loadDisputedRentals() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.user?.uid;

      if (userId == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Get disputed rentals for both renter and owner
      final renterDisputes = await _firestoreService
          .getDisputedRentalsForRenter(userId);
      final ownerDisputes = await _firestoreService.getDisputedRentalsForOwner(
        userId,
      );

      // Combine and deduplicate
      final allDisputes = <String, Map<String, dynamic>>{};
      for (final dispute in renterDisputes) {
        allDisputes[dispute['id'] as String] = dispute;
      }
      for (final dispute in ownerDisputes) {
        allDisputes[dispute['id'] as String] = dispute;
      }

      setState(() {
        _disputedRentals = allDisputes.values.toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading disputed rentals: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  DateTime? _parseDate(dynamic dateValue) {
    if (dateValue == null) return null;
    if (dateValue is DateTime) return dateValue;
    if (dateValue is Timestamp) return dateValue.toDate();
    if (dateValue is int) {
      return DateTime.fromMillisecondsSinceEpoch(dateValue);
    }
    return null;
  }

  Future<void> _messageOwner(Map<String, dynamic> rental) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);

      if (!authProvider.isAuthenticated || authProvider.user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please login to message owner'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final currentUser = userProvider.currentUser;
      if (currentUser == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('User data not available'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final ownerId = rental['ownerId'] as String? ?? '';
      final ownerName = rental['ownerName'] as String? ?? 'Owner';
      final itemId = rental['itemId'] as String? ?? '';
      final itemTitle =
          rental['title'] as String? ??
          rental['itemTitle'] as String? ??
          'Rental Item';

      // Show loading
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (dialogContext) =>
            const Center(child: CircularProgressIndicator()),
      );

      // Create or get conversation
      final conversationId = await chatProvider.createOrGetConversation(
        userId1: authProvider.user!.uid,
        userId1Name: currentUser.fullName,
        userId2: ownerId,
        userId2Name: ownerName,
        itemId: itemId,
        itemTitle: itemTitle,
      );

      // Close loading dialog
      if (mounted) {
        final rootNav = Navigator.of(context, rootNavigator: true);
        if (rootNav.canPop()) rootNav.pop();
      }

      if (conversationId != null && mounted) {
        // Navigate to chat detail screen
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatDetailScreen(
              conversationId: conversationId,
              otherParticipantName: ownerName,
              userId: authProvider.user!.uid,
            ),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to create conversation'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final rootNav = Navigator.of(context, rootNavigator: true);
        if (rootNav.canPop()) rootNav.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _messageRenter(Map<String, dynamic> rental) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);

      if (!authProvider.isAuthenticated || authProvider.user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please login to message renter'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final currentUser = userProvider.currentUser;
      if (currentUser == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('User data not available'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final renterId = rental['renterId'] as String? ?? '';
      final renterName = rental['renterName'] as String? ?? 'Renter';
      final itemId = rental['itemId'] as String? ?? '';
      final itemTitle =
          rental['title'] as String? ??
          rental['itemTitle'] as String? ??
          'Rental Item';

      // Show loading
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (dialogContext) =>
            const Center(child: CircularProgressIndicator()),
      );

      // Create or get conversation
      final conversationId = await chatProvider.createOrGetConversation(
        userId1: authProvider.user!.uid,
        userId1Name: currentUser.fullName,
        userId2: renterId,
        userId2Name: renterName,
        itemId: itemId,
        itemTitle: itemTitle,
      );

      // Close loading dialog
      if (mounted) {
        final rootNav = Navigator.of(context, rootNavigator: true);
        if (rootNav.canPop()) rootNav.pop();
      }

      if (conversationId != null && mounted) {
        // Navigate to chat detail screen
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatDetailScreen(
              conversationId: conversationId,
              otherParticipantName: renterName,
              userId: authProvider.user!.uid,
            ),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to create conversation'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final rootNav = Navigator.of(context, rootNavigator: true);
        if (rootNav.canPop()) rootNav.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _viewDetails(Map<String, dynamic> rental) async {
    final requestId = rental['id'] as String?;
    if (requestId == null) return;

    // Navigate to active rental detail screen (user-facing detail view)
    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ActiveRentalDetailScreen(requestId: requestId),
        ),
      );
    }
  }

  Future<void> _proposeCompensation(Map<String, dynamic> rental) async {
    final requestId = rental['id'] as String?;
    if (requestId == null) return;

    final damageReport = rental['damageReport'] as Map<String, dynamic>?;
    final estimatedCost = damageReport?['estimatedCost'] as num?;

    final amountController = TextEditingController(
      text: estimatedCost != null ? estimatedCost.toStringAsFixed(2) : '',
    );
    final notesController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Propose Compensation'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter the compensation amount you are proposing:',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amountController,
                decoration: const InputDecoration(
                  labelText: 'Compensation Amount *',
                  hintText: '0.00',
                  prefixText: '₱ ',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes (Optional)',
                  hintText: 'Additional information about the compensation...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final amount = double.tryParse(amountController.text.trim());
              if (amount == null || amount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a valid amount'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              Navigator.pop(context, true);
            },
            child: const Text('Propose'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final ownerId = authProvider.user?.uid;

      if (ownerId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You must be logged in'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final amount = double.parse(amountController.text.trim());
      final notes = notesController.text.trim().isNotEmpty
          ? notesController.text.trim()
          : null;

      await _firestoreService.proposeRentalDisputeCompensation(
        requestId: requestId,
        ownerId: ownerId,
        compensationAmount: amount,
        proposalNotes: notes,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Compensation proposal sent successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _loadDisputedRentals();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _acceptCompensation(Map<String, dynamic> rental) async {
    final requestId = rental['id'] as String?;
    if (requestId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Accept Compensation?'),
        content: const Text(
          'Are you sure you want to accept this compensation proposal? You will need to record payment after accepting.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00897B),
            ),
            child: const Text('Accept'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final renterId = authProvider.user?.uid;

      if (renterId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You must be logged in'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      await _firestoreService.acceptRentalDisputeCompensation(
        requestId: requestId,
        renterId: renterId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Compensation accepted. Please record payment.'),
            backgroundColor: Colors.green,
          ),
        );
        _loadDisputedRentals();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _rejectCompensation(Map<String, dynamic> rental) async {
    final requestId = rental['id'] as String?;
    if (requestId == null) return;

    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Compensation?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Are you sure you want to reject this compensation proposal?',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'Reason (Optional)',
                  hintText: 'Why are you rejecting this proposal?',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final renterId = authProvider.user?.uid;

      if (renterId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You must be logged in'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final reason = reasonController.text.trim().isNotEmpty
          ? reasonController.text.trim()
          : null;

      await _firestoreService.rejectRentalDisputeCompensation(
        requestId: requestId,
        renterId: renterId,
        rejectionReason: reason,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Compensation proposal rejected'),
            backgroundColor: Colors.orange,
          ),
        );
        _loadDisputedRentals();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _recordPayment(Map<String, dynamic> rental) async {
    final requestId = rental['id'] as String?;
    if (requestId == null) return;

    final disputeResolution =
        rental['disputeResolution'] as Map<String, dynamic>?;
    final proposedAmount = disputeResolution?['proposedAmount'] as num?;

    final amountController = TextEditingController(
      text: proposedAmount != null ? proposedAmount.toStringAsFixed(2) : '',
    );
    final methodController = TextEditingController(text: 'Cash');
    final notesController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Record Payment'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Record the compensation payment you made:',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amountController,
                decoration: const InputDecoration(
                  labelText: 'Payment Amount *',
                  hintText: '0.00',
                  prefixText: '₱ ',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: methodController,
                decoration: const InputDecoration(
                  labelText: 'Payment Method',
                  hintText: 'Cash, Bank Transfer, etc.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes (Optional)',
                  hintText: 'Payment reference, transaction ID, etc.',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final amount = double.tryParse(amountController.text.trim());
              if (amount == null || amount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a valid amount'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Record Payment'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final renterId = authProvider.user?.uid;

      if (renterId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You must be logged in'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final amount = double.parse(amountController.text.trim());
      final method = methodController.text.trim().isNotEmpty
          ? methodController.text.trim()
          : null;
      final notes = notesController.text.trim().isNotEmpty
          ? notesController.text.trim()
          : null;

      await _firestoreService.recordRentalDisputeCompensationPayment(
        requestId: requestId,
        renterId: renterId,
        amount: amount,
        paymentMethod: method,
        paymentNotes: notes,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment recorded. Dispute resolved!'),
            backgroundColor: Colors.green,
          ),
        );
        _loadDisputedRentals();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF00897B),
        elevation: 0,
        title: const Text(
          'Disputed Rentals',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadDisputedRentals,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _disputedRentals.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.gavel_outlined, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No disputed rentals',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Rentals with damage reports will appear here',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadDisputedRentals,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _disputedRentals.length,
                itemBuilder: (context, index) {
                  final rental = _disputedRentals[index];
                  return _buildDisputeCard(rental);
                },
              ),
            ),
      bottomNavigationBar: BottomNavBarWidget(
        onTap: (_) {},
        navigationContext: context,
      ),
    );
  }

  Widget _buildDisputeCard(Map<String, dynamic> rental) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userId = authProvider.user?.uid;

    final title =
        rental['title'] as String? ??
        rental['itemTitle'] as String? ??
        'Unknown Item';
    final ownerName = rental['ownerName'] as String? ?? 'Unknown';
    final renterName = rental['renterName'] as String? ?? 'Unknown';
    final returnVerifiedAt = _parseDate(rental['returnVerifiedAt']);
    final images = (rental['images'] as List<dynamic>?)?.cast<String>() ?? [];
    final hasImages = images.isNotEmpty;
    final damageReport = rental['damageReport'] as Map<String, dynamic>?;
    final disputeResolution =
        rental['disputeResolution'] as Map<String, dynamic>?;
    final resolutionStatus = disputeResolution?['status'] as String?;
    final proposedAmount = disputeResolution?['proposedAmount'] as num?;
    final isOwner = rental['ownerId'] == userId;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => _viewDetails(rental),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Item image
                  if (hasImages)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: images.first,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          width: 60,
                          height: 60,
                          color: Colors.grey[300],
                          child: const Icon(Icons.image),
                        ),
                        errorWidget: (context, url, error) => Container(
                          width: 60,
                          height: 60,
                          color: Colors.grey[300],
                          child: const Icon(Icons.broken_image),
                        ),
                      ),
                    )
                  else
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.inventory_2, size: 30),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isOwner
                              ? 'Rented by: $renterName'
                              : 'Owner: $ownerName',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                        if (returnVerifiedAt != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Disputed: ${_formatDate(returnVerifiedAt)}',
                            style: TextStyle(
                              color: Colors.orange[700],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red[100],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Disputed',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              if (damageReport != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.warning, color: Colors.red[700], size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'Damage Reported',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      if (damageReport['description'] != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          damageReport['description'] as String,
                          style: TextStyle(fontSize: 13),
                        ),
                      ],
                      if (damageReport['estimatedCost'] != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Estimated Cost: ₱${(damageReport['estimatedCost'] as num).toStringAsFixed(2)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.red[700],
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              // Compensation Proposal Section
              if (disputeResolution != null && proposedAmount != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: resolutionStatus == 'proposal_pending'
                        ? Colors.blue.withOpacity(0.1)
                        : resolutionStatus == 'accepted'
                        ? Colors.green.withOpacity(0.1)
                        : resolutionStatus == 'resolved'
                        ? Colors.green.withOpacity(0.1)
                        : Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: resolutionStatus == 'proposal_pending'
                          ? Colors.blue.withOpacity(0.3)
                          : resolutionStatus == 'accepted'
                          ? Colors.green.withOpacity(0.3)
                          : resolutionStatus == 'resolved'
                          ? Colors.green.withOpacity(0.3)
                          : Colors.orange.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            resolutionStatus == 'proposal_pending'
                                ? Icons.pending_outlined
                                : resolutionStatus == 'accepted'
                                ? Icons.check_circle
                                : resolutionStatus == 'resolved'
                                ? Icons.check_circle_outline
                                : Icons.cancel,
                            color: resolutionStatus == 'proposal_pending'
                                ? Colors.blue[700]
                                : resolutionStatus == 'accepted'
                                ? Colors.green[700]
                                : resolutionStatus == 'resolved'
                                ? Colors.green[700]
                                : Colors.orange[700],
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            resolutionStatus == 'proposal_pending'
                                ? 'Compensation Proposal'
                                : resolutionStatus == 'accepted'
                                ? 'Compensation Accepted'
                                : resolutionStatus == 'resolved'
                                ? 'Dispute Resolved'
                                : 'Compensation Rejected',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: resolutionStatus == 'proposal_pending'
                                  ? Colors.blue[700]
                                  : resolutionStatus == 'accepted'
                                  ? Colors.green[700]
                                  : resolutionStatus == 'resolved'
                                  ? Colors.green[700]
                                  : Colors.orange[700],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Proposed Amount: ₱${proposedAmount.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                      ),
                      if (disputeResolution['proposalNotes'] != null &&
                          (disputeResolution['proposalNotes'] as String)
                              .isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          disputeResolution['proposalNotes'] as String,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (resolutionStatus == 'resolved' &&
                          disputeResolution['paymentAmount'] != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Payment Recorded: ₱${(disputeResolution['paymentAmount'] as num).toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.green[700],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ] else if (isOwner &&
                  (disputeResolution == null ||
                      resolutionStatus == null ||
                      resolutionStatus == 'rejected')) ...[
                // Owner can propose compensation (first time or after rejection)
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () => _proposeCompensation(rental),
                  icon: const Icon(Icons.attach_money, size: 18),
                  label: Text(
                    resolutionStatus == 'rejected'
                        ? 'Propose New Compensation'
                        : 'Propose Compensation',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 40),
                  ),
                ),
                const SizedBox(height: 12),
              ] else if (!isOwner &&
                  (disputeResolution == null || resolutionStatus == null)) ...[
                // Renter waiting for proposal
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.hourglass_empty, color: Colors.orange[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Waiting for owner to propose compensation amount.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              // Action Buttons based on resolution status
              if (resolutionStatus == 'proposal_pending' && !isOwner) ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _rejectCompensation(rental),
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Reject'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _acceptCompensation(rental),
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Accept'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00897B),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ] else if (resolutionStatus == 'accepted' && !isOwner) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Compensation accepted. Please record payment.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () => _recordPayment(rental),
                  icon: const Icon(Icons.payment, size: 18),
                  label: const Text('Record Payment'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 40),
                  ),
                ),
                const SizedBox(height: 8),
              ] else if (resolutionStatus == 'resolved') ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        color: Colors.green[700],
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Dispute resolved. Payment has been recorded.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => isOwner
                        ? _messageRenter(rental)
                        : _messageOwner(rental),
                    icon: const Icon(Icons.message, size: 18),
                    label: const Text('Message'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF00897B),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _viewDetails(rental),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00897B),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('View Details'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
}
