import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/firestore_service.dart';
import '../../services/local_notifications_service.dart';
import '../../models/borrow_request_model.dart';
import '../chat_detail_screen.dart';

class BorrowRequestDetailScreen extends StatefulWidget {
  final String requestId;

  const BorrowRequestDetailScreen({super.key, required this.requestId});

  @override
  State<BorrowRequestDetailScreen> createState() =>
      _BorrowRequestDetailScreenState();
}

class _BorrowRequestDetailScreenState extends State<BorrowRequestDetailScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  BorrowRequestModel? _requestData;
  Map<String, dynamic>?
  _itemEnrichment; // For item details (title, category, image)
  bool _isLoading = true;
  bool _isProcessing = false;
  DateTime? _selectedReturnDate;

  @override
  void initState() {
    super.initState();
    _loadRequest();
  }

  Future<void> _loadRequest() async {
    try {
      final data = await _firestoreService.getBorrowRequestById(
        widget.requestId,
      );
      if (data == null) {
        if (mounted) {
          setState(() {
            _requestData = null;
            _isLoading = false;
          });
        }
        return;
      }

      // Enrich with item details (title, category, image)
      final itemId = data.itemId;
      Map<String, dynamic>? itemEnrichment;
      if (itemId.isNotEmpty) {
        try {
          final item = await _firestoreService.getItem(itemId);
          if (item != null) {
            itemEnrichment = {
              'itemTitle': item['title'] as String? ?? data.itemTitle,
              'itemCategory': item['category'] as String? ?? 'General',
              'itemImageUrl': (item['images'] as List<dynamic>?)
                  ?.whereType<String>()
                  .where((img) => img.isNotEmpty)
                  .firstOrNull,
            };
          }
        } catch (_) {
          // Best-effort enrichment; ignore errors
        }
      }
      itemEnrichment ??= {
        'itemTitle': data.itemTitle.isNotEmpty ? data.itemTitle : 'Item',
        'itemCategory': 'General',
      };

      if (mounted) {
        setState(() {
          _requestData = data;
          _itemEnrichment = itemEnrichment;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading request: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _acceptRequest() async {
    if (_requestData == null) return;

    // Show date picker for return date
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 7)),
      firstDate: now.add(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Select Return Date',
    );

    if (pickedDate == null) return;

    setState(() {
      _selectedReturnDate = pickedDate;
    });

    // Confirm acceptance
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Accept Borrow Request?'),
        content: Text(
          'Are you sure you want to accept the borrow request from '
          '${_requestData!.borrowerName}? Return date: ${pickedDate.toString().split(' ')[0]}',
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
              foregroundColor: Colors.white,
            ),
            child: const Text('Accept'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      setState(() {
        _selectedReturnDate = null;
      });
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final requestId = widget.requestId;
      final itemId = _requestData!.itemId;
      final borrowerId = _requestData!.borrowerId;
      final itemTitle =
          _itemEnrichment?['itemTitle'] as String? ?? _requestData!.itemTitle;
      final lenderName = _requestData!.lenderName;

      await _firestoreService.acceptBorrowRequest(
        requestId: requestId,
        itemId: itemId,
        borrowerId: borrowerId,
        returnDate: pickedDate,
      );

      // Send notification to borrower
      await _firestoreService.sendDecisionNotification(
        toUserId: borrowerId,
        itemTitle: itemTitle,
        decision: 'accepted',
        requestId: requestId,
        lenderName: lenderName,
      );

      // Schedule local notifications for return reminders (for borrower)
      try {
        final borrowerName = _requestData!.borrowerName;
        await LocalNotificationsService().scheduleReturnReminders(
          itemId: itemId,
          itemTitle: itemTitle,
          returnDateLocal: pickedDate,
          borrowerName: borrowerName,
          borrowerId:
              borrowerId, // Pass borrower ID so reminders go to borrower
        );
      } catch (e) {
        // Best-effort: don't fail acceptance if notification scheduling fails
        debugPrint('Failed to schedule return reminders: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Borrow request accepted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _selectedReturnDate = null; // Reset date picker
        });

        // Extract error message for better user experience
        String errorMessage = 'Error accepting request: $e';
        if (e.toString().contains('maximum limit')) {
          errorMessage = e.toString().replaceFirst('Exception: ', '');
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _declineRequest() async {
    if (_requestData == null) return;

    // Confirm decline
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Decline Borrow Request?'),
        content: Text(
          'Are you sure you want to decline the borrow request from '
          '${_requestData!.borrowerName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Decline'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final requestId = widget.requestId;
      final borrowerId = _requestData!.borrowerId;
      final itemTitle =
          _itemEnrichment?['itemTitle'] as String? ?? _requestData!.itemTitle;
      final lenderName = _requestData!.lenderName;

      await _firestoreService.declineBorrowRequest(requestId: requestId);

      // Send notification to borrower
      await _firestoreService.sendDecisionNotification(
        toUserId: borrowerId,
        itemTitle: itemTitle,
        decision: 'declined',
        requestId: requestId,
        lenderName: lenderName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Borrow request declined'),
            backgroundColor: Colors.orange,
          ),
        );
        Navigator.of(context).pop(true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error declining request: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildOverdueActionsCard(BorrowRequestModel request) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = authProvider.user?.uid;
    final lenderId = request.lenderId;

    // Only show for lenders
    if (currentUserId != lenderId) {
      return const SizedBox.shrink();
    }

    // Check if item is overdue
    final agreedReturnDate = request.agreedReturnDate;
    if (agreedReturnDate == null) {
      return const SizedBox.shrink();
    }

    final isOverdue = agreedReturnDate.isBefore(DateTime.now());

    // Check if already reported
    final missingItemReported = request.missingItemReported ?? false;

    if (!isOverdue) {
      return const SizedBox.shrink();
    }

    final daysOverdue = DateTime.now().difference(agreedReturnDate).inDays;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red[200]!, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning, color: Colors.red[700], size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Item is $daysOverdue ${daysOverdue == 1 ? 'day' : 'days'} overdue',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.red[700],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!missingItemReported) ...[
            ElevatedButton.icon(
              onPressed: _reportMissingItem,
              icon: const Icon(Icons.report_problem, size: 20),
              label: const Text(
                'Report Not Returned',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Not returned report has been submitted. Admins have been notified.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange[900],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _reportMissingItem() async {
    if (_requestData == null) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = authProvider.user?.uid;

    if (currentUserId == null) return;

    final lenderId = _requestData!.lenderId;
    if (lenderId != currentUserId) {
      // Only lender can report missing items
      return;
    }

    final itemTitle =
        _itemEnrichment?['itemTitle'] as String? ?? _requestData!.itemTitle;
    final agreedReturnDate = _requestData!.agreedReturnDate;
    final daysOverdue = agreedReturnDate != null
        ? DateTime.now().difference(agreedReturnDate).inDays
        : 0;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Text('Report Not Returned'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to report "$itemTitle" as missing?',
              style: const TextStyle(fontSize: 16),
            ),
            if (daysOverdue > 0) ...[
              const SizedBox(height: 12),
              Text(
                'This item is $daysOverdue ${daysOverdue == 1 ? 'day' : 'days'} overdue.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.red[700],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'This will:\n'
              '• Notify admins immediately\n'
              '• Notify the borrower\n'
              '• Create a high-priority report',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Report Not Returned'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Show loading
    if (mounted) {
      setState(() {
        _isProcessing = true;
      });
    }

    try {
      await _firestoreService.reportMissingBorrowItem(
        requestId: widget.requestId,
        lenderId: currentUserId,
        description:
            'Item "$itemTitle" has not been returned. '
            'Days overdue: $daysOverdue',
      );

      if (mounted) {
        // Reload request to update missingItemReported status
        await _loadRequest();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Not returned report submitted successfully. Admins have been notified.',
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error reporting item not returned: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _messageBorrower() async {
    if (_requestData == null) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    if (!authProvider.isAuthenticated || authProvider.user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please login to message'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final currentUser = userProvider.currentUser;
    if (currentUser == null) return;

    final borrowerId = _requestData!.borrowerId;
    final borrowerName = _requestData!.borrowerName;
    final itemId = _requestData!.itemId;
    final itemTitle =
        _itemEnrichment?['itemTitle'] as String? ?? _requestData!.itemTitle;

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
      userId2: borrowerId,
      userId2Name: borrowerName,
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
            otherParticipantName: borrowerName,
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Borrow Request'),
        backgroundColor: const Color(0xFF00897B),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF5F5F5),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _requestData == null
          ? const Center(child: Text('Request not found'))
          : _buildRequestDetails(),
    );
  }

  Widget _buildRequestDetails() {
    final request = _requestData!;
    final borrowerName = request.borrowerName;
    final itemTitle =
        _itemEnrichment?['itemTitle'] as String? ?? request.itemTitle;
    final itemCategory =
        _itemEnrichment?['itemCategory'] as String? ?? 'General';
    final itemImageUrl = _itemEnrichment?['itemImageUrl'] as String?;
    final message = request.message ?? '';
    final createdAt = request.createdAt;

    final isPending = request.isPending;

    return Container(
      color: const Color(0xFFF5F5F5),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header card: status + borrower + item
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
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isPending
                                ? Colors.orange
                                : request.isAccepted
                                ? Colors.green
                                : Colors.red,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            request.statusDisplay.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            const Icon(
                              Icons.access_time,
                              size: 16,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              createdAt.toString().split(' ').first,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: itemImageUrl != null && itemImageUrl.isNotEmpty
                              ? Image.network(
                                  itemImageUrl,
                                  width: 64,
                                  height: 64,
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  width: 64,
                                  height: 64,
                                  color: const Color(
                                    0xFF00897B,
                                  ).withValues(alpha: 0.08),
                                  child: const Icon(
                                    Icons.inventory_2_outlined,
                                    color: Color(0xFF00897B),
                                    size: 32,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                itemTitle,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF00897B,
                                  ).withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.category,
                                      size: 14,
                                      color: Color(0xFF00897B),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      itemCategory,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF00897B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.person,
                                    size: 16,
                                    color: Color(0xFF00897B),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      borrowerName,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
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
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Message card
            if (message.isNotEmpty) ...[
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Icon(
                            Icons.chat_bubble_outline,
                            color: Color(0xFF00897B),
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Borrower Message',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        message,
                        style: const TextStyle(fontSize: 14, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Dates card (requested + selected return date)
            if (_selectedReturnDate != null) ...[
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Icon(
                            Icons.calendar_today,
                            color: Color(0xFF00897B),
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Request Details',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Requested on',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            createdAt.toString().split(' ').first,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      if (_selectedReturnDate != null)
                        const SizedBox(height: 8),
                      if (_selectedReturnDate != null)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Selected return date',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              _selectedReturnDate!.toString().split(' ').first,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF00897B),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Action buttons & status info
            if (isPending && !_isProcessing) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _messageBorrower,
                      icon: const Icon(Icons.message),
                      label: const Text('Message'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF00897B),
                        side: const BorderSide(
                          color: Color(0xFF00897B),
                          width: 2,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _declineRequest,
                      icon: const Icon(Icons.close),
                      label: const Text('Decline'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _acceptRequest,
                      icon: const Icon(Icons.check),
                      label: const Text('Accept'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00897B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ] else if (_isProcessing) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
            ] else ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: request.isAccepted ? Colors.green[50] : Colors.red[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      request.isAccepted ? Icons.check_circle : Icons.cancel,
                      color: request.isAccepted ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        request.isAccepted
                            ? 'This request has been accepted.'
                            : 'This request has been declined.',
                        style: TextStyle(
                          color: request.isAccepted
                              ? Colors.green[900]
                              : Colors.red[900],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Show "Report Not Returned" button for lenders when item is overdue
              if (request.isAccepted) ...[
                const SizedBox(height: 16),
                _buildOverdueActionsCard(request),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
