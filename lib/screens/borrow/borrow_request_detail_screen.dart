import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/firestore_service.dart';
import '../../services/local_notifications_service.dart';
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
  Map<String, dynamic>? _requestData;
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
      final enrichedData = Map<String, dynamic>.from(data);
      final itemId = data['itemId'] as String?;
      if (itemId != null) {
        try {
          final item = await _firestoreService.getItem(itemId);
          if (item != null) {
            enrichedData['itemTitle'] ??= item['title'] as String?;
            enrichedData['itemCategory'] ??= item['category'] as String?;
            final itemImages = item['images'] as List<dynamic>?;
            if (itemImages != null && itemImages.isNotEmpty) {
              final first = itemImages.first;
              if (first is String && first.isNotEmpty) {
                enrichedData['itemImageUrl'] = first;
              }
            }
          }
        } catch (_) {
          // Best-effort enrichment; ignore errors
        }
      }
      enrichedData['itemTitle'] ??= 'Item';
      enrichedData['itemCategory'] ??= 'General';

      if (mounted) {
        setState(() {
          _requestData = enrichedData;
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
          '${_requestData!['borrowerName']}? Return date: ${pickedDate.toString().split(' ')[0]}',
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
      final itemId = _requestData!['itemId'] as String;
      final borrowerId = _requestData!['borrowerId'] as String;
      final itemTitle = _requestData!['itemTitle'] as String? ?? 'Item';
      final lenderName = _requestData!['lenderName'] as String?;

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

      // Schedule local notifications for return reminders (for lender)
      try {
        final borrowerName =
            _requestData!['borrowerName'] as String? ?? 'Borrower';
        await LocalNotificationsService().scheduleReturnReminders(
          itemId: itemId,
          itemTitle: itemTitle,
          returnDateLocal: pickedDate,
          borrowerName: borrowerName,
        );
      } catch (e) {
        // Best-effort: don't fail acceptance if notification scheduling fails
        print('Failed to schedule return reminders: $e');
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
          '${_requestData!['borrowerName']}?',
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
      final borrowerId = _requestData!['borrowerId'] as String;
      final itemTitle = _requestData!['itemTitle'] as String? ?? 'Item';
      final lenderName = _requestData!['lenderName'] as String?;

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

    final borrowerId = _requestData!['borrowerId'] as String;
    final borrowerName = _requestData!['borrowerName'] as String? ?? 'User';
    final itemId = _requestData!['itemId'] as String;
    final itemTitle = _requestData!['itemTitle'] as String? ?? 'Item';

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
    final status = _requestData!['status'] as String? ?? 'pending';
    final borrowerName =
        _requestData!['borrowerName'] as String? ?? 'Unknown borrower';
    final itemTitle = _requestData!['itemTitle'] as String? ?? 'Item';
    final itemCategory = _requestData!['itemCategory'] as String? ?? 'General';
    final itemImageUrl = _requestData!['itemImageUrl'] as String?;
    final message = _requestData!['message'] as String? ?? '';
    final createdAt = _requestData!['createdAt'] as Timestamp?;

    final isPending = status == 'pending';

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
                            color: status == 'pending'
                                ? Colors.orange
                                : status == 'accepted'
                                ? Colors.green
                                : Colors.red,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            status.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (createdAt != null)
                          Row(
                            children: [
                              const Icon(
                                Icons.access_time,
                                size: 16,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                createdAt.toDate().toString().split(' ').first,
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
                                  ).withOpacity(0.08),
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
                                  ).withOpacity(0.06),
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
            if (createdAt != null || _selectedReturnDate != null) ...[
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
                      if (createdAt != null)
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
                              createdAt.toDate().toString().split(' ').first,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      if (createdAt != null && _selectedReturnDate != null)
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
                  color: status == 'accepted'
                      ? Colors.green[50]
                      : Colors.red[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      status == 'accepted' ? Icons.check_circle : Icons.cancel,
                      color: status == 'accepted' ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        status == 'accepted'
                            ? 'This request has been accepted.'
                            : 'This request has been declined.',
                        style: TextStyle(
                          color: status == 'accepted'
                              ? Colors.green[900]
                              : Colors.red[900],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
