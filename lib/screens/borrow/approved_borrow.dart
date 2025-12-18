import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/firestore_service.dart';
import '../../reusable_widgets/bottom_nav_bar_widget.dart';
import '../../models/borrow_request_model.dart';
import '../chat_detail_screen.dart';

class ApprovedBorrowScreen extends StatefulWidget {
  const ApprovedBorrowScreen({super.key});

  @override
  State<ApprovedBorrowScreen> createState() => _ApprovedBorrowScreenState();
}

class _ApprovedBorrowScreenState extends State<ApprovedBorrowScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  bool _isLoading = true;
  List<BorrowRequestModel> _requests = [];

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
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

      final requests = await _firestoreService
          .getAcceptedBorrowRequestsForBorrower(userId);
      setState(() {
        _requests = requests;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading requests: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _messageLender(BorrowRequestModel request) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);

      if (!authProvider.isAuthenticated || authProvider.user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please login to message lender'),
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
              content: Text('User data not found'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final lenderId = request.lenderId;
      final lenderName = request.lenderName;
      final itemId = request.itemId;
      final itemTitle = request.itemTitle;

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
        userId2: lenderId,
        userId2Name: lenderName,
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
              otherParticipantName: lenderName,
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

  void _viewDetails(BorrowRequestModel request) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildRequestDetailsModal(request),
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

  String _formatDateTime(DateTime date) {
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
    final hour = date.hour > 12 ? date.hour - 12 : date.hour;
    final amPm = date.hour >= 12 ? 'PM' : 'AM';
    return '${months[date.month - 1]} ${date.day.toString().padLeft(2, '0')}, ${date.year} at ${hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} $amPm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF00897B),
        elevation: 0,
        title: const Text(
          'Approved Borrow Requests',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _requests.isEmpty
          ? Center(
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
                    'No approved borrow requests',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your approved borrow requests will appear here',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadRequests,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _requests.length,
                itemBuilder: (context, index) {
                  final request = _requests[index];
                  return _buildBorrowRequestCard(request);
                },
              ),
            ),
      bottomNavigationBar: BottomNavBarWidget(
        selectedIndex: null,
        onTap: (_) {},
        navigationContext: context,
      ),
    );
  }

  Widget _buildBorrowRequestCard(BorrowRequestModel request) {
    final createdAt = request.createdAt;
    final updatedAt = request.updatedAt ?? createdAt;
    final agreedReturnDate = request.agreedReturnDate;
    final isOverdue =
        agreedReturnDate != null && agreedReturnDate.isBefore(DateTime.now());

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => _viewDetails(request),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          request.itemTitle.isNotEmpty
                              ? request.itemTitle
                              : 'Unknown Item',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Lender: ${request.lenderName.isNotEmpty ? request.lenderName : 'Unknown'}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
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
                      color: isOverdue ? Colors.red : Colors.green,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isOverdue ? 'Overdue' : 'Approved',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (request.message != null && request.message!.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    request.message!,
                    style: TextStyle(fontSize: 14, color: Colors.grey[800]),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (agreedReturnDate != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isOverdue
                        ? Colors.red.withValues(alpha: 0.1)
                        : const Color(0xFF00897B).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isOverdue
                          ? Colors.red.withValues(alpha: 0.3)
                          : const Color(0xFF00897B).withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 18,
                        color: isOverdue ? Colors.red : const Color(0xFF00897B),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Return Date',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatDate(agreedReturnDate),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: isOverdue
                                    ? Colors.red
                                    : const Color(0xFF00897B),
                              ),
                            ),
                            if (isOverdue) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Please return this item as soon as possible',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.red[700],
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    'Approved: ${_formatDate(updatedAt)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: () => _messageLender(request),
                    icon: const Icon(Icons.message, size: 18),
                    label: const Text('Message'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF00897B),
                      side: const BorderSide(color: Color(0xFF00897B)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRequestDetailsModal(BorrowRequestModel request) {
    final createdAt = request.createdAt;
    final updatedAt = request.updatedAt ?? createdAt;
    final agreedReturnDate = request.agreedReturnDate;
    final isOverdue =
        agreedReturnDate != null && agreedReturnDate.isBefore(DateTime.now());

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Content
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Status badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isOverdue ? Colors.red : Colors.green,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isOverdue ? 'OVERDUE' : 'APPROVED',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Item Title
                      Text(
                        request.itemTitle.isNotEmpty
                            ? request.itemTitle
                            : 'Unknown Item',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Lender Info
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const CircleAvatar(
                              backgroundColor: Color(0xFF00897B),
                              child: Icon(Icons.person, color: Colors.white),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Lender',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  Text(
                                    request.lenderName.isNotEmpty
                                        ? request.lenderName
                                        : 'Unknown',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Return Date
                      if (agreedReturnDate != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isOverdue
                                ? Colors.red.withValues(alpha: 0.1)
                                : const Color(
                                    0xFF00897B,
                                  ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isOverdue
                                  ? Colors.red.withValues(alpha: 0.3)
                                  : const Color(
                                      0xFF00897B,
                                    ).withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.calendar_today,
                                color: isOverdue
                                    ? Colors.red
                                    : const Color(0xFF00897B),
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Return Date',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _formatDate(agreedReturnDate),
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: isOverdue
                                            ? Colors.red
                                            : const Color(0xFF00897B),
                                      ),
                                    ),
                                    if (isOverdue) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'This item is overdue. Please return it as soon as possible.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.red[700],
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      // Message
                      if (request.message != null &&
                          request.message!.isNotEmpty) ...[
                        const Text(
                          'Your Message',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            request.message!,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[800],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      // Dates
                      const Text(
                        'Request Timeline',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildTimelineItem(
                        'Requested',
                        _formatDateTime(createdAt),
                        Icons.send,
                      ),
                      const SizedBox(height: 8),
                      _buildTimelineItem(
                        'Approved',
                        _formatDateTime(updatedAt),
                        Icons.check_circle,
                        isApproved: true,
                      ),
                      const SizedBox(height: 24),
                      // Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                _messageLender(request);
                              },
                              icon: const Icon(Icons.message),
                              label: const Text('Message Lender'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF00897B),
                                side: const BorderSide(
                                  color: Color(0xFF00897B),
                                  width: 2,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTimelineItem(
    String label,
    String date,
    IconData icon, {
    bool isApproved = false,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: isApproved ? Colors.green : Colors.grey[600],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isApproved ? Colors.green : Colors.grey[800],
                ),
              ),
              Text(
                date,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
