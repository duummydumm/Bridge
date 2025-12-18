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
import '../submit_rating_screen.dart';
import '../../models/rating_model.dart';

class BorrowHistoryScreen extends StatefulWidget {
  const BorrowHistoryScreen({super.key});

  @override
  State<BorrowHistoryScreen> createState() => _BorrowHistoryScreenState();
}

class _BorrowHistoryScreenState extends State<BorrowHistoryScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  bool _isLoading = true;
  List<Map<String, dynamic>> _allTransactions = [];
  final Set<String> _ratedRequestIds = <String>{};
  String _selectedFilter =
      'all'; // 'all', 'pending', 'accepted', 'returned', 'declined', 'cancelled'
  String _selectedRoleFilter = 'all'; // 'all', 'borrower', 'lender'

  @override
  void initState() {
    super.initState();
    _loadBorrowHistory();
  }

  Future<void> _loadBorrowHistory() async {
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

      final transactions = await _firestoreService
          .getAllBorrowTransactionsForUser(userId);

      // Check rating status for returned transactions
      final ratedIds = <String>{};
      for (final transaction in transactions) {
        final requestId = transaction['requestId'] as String?;
        final status = transaction['requestStatus'] as String?;
        final userRole = transaction['userRole'] as String?;

        // Only check rating for returned transactions
        if (requestId != null && status == 'returned') {
          final lenderId = transaction['lenderId'] as String?;
          final borrowerId = transaction['borrowerId'] as String?;

          // Determine who to rate based on user's role
          final ratedUserId = userRole == 'borrower' ? lenderId : borrowerId;

          if (ratedUserId != null && ratedUserId.isNotEmpty) {
            final hasRated = await _firestoreService.hasExistingRating(
              raterUserId: userId,
              ratedUserId: ratedUserId,
              transactionId: requestId,
            );
            if (hasRated) {
              ratedIds.add(requestId);
            }
          }
        }
      }

      setState(() {
        _allTransactions = transactions;
        _ratedRequestIds
          ..clear()
          ..addAll(ratedIds);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading transaction history: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredTransactions {
    var filtered = _allTransactions;

    // Filter by role
    if (_selectedRoleFilter != 'all') {
      filtered = filtered.where((transaction) {
        final role = transaction['userRole'] as String? ?? '';
        return role == _selectedRoleFilter;
      }).toList();
    }

    // Filter by status
    if (_selectedFilter != 'all') {
      filtered = filtered.where((transaction) {
        final status = transaction['requestStatus'] as String? ?? '';
        // Also check the 'status' field in case it's stored there
        final itemStatus = transaction['status'] as String? ?? '';
        // Match either requestStatus or status field
        return status == _selectedFilter || itemStatus == _selectedFilter;
      }).toList();
    }

    return filtered;
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

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'accepted':
        return Colors.green;
      case 'returned':
        return Colors.grey;
      case 'declined':
        return Colors.red;
      case 'cancelled':
        return Colors.grey[600]!;
      case 'return_initiated':
        return Colors.blue;
      case 'return_disputed':
        return Colors.deepOrange;
      default:
        return Colors.grey;
    }
  }

  String _getStatusLabel(String? status) {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'accepted':
        return 'Accepted';
      case 'returned':
        return 'Returned';
      case 'declined':
        return 'Declined';
      case 'cancelled':
        return 'Cancelled';
      case 'return_initiated':
        return 'Return Initiated';
      case 'return_disputed':
        return 'Disputed';
      default:
        return status ?? 'Unknown';
    }
  }

  Future<void> _rateOtherParty(Map<String, dynamic> transaction) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.user;
      if (currentUser == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please login to rate'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final userRole = transaction['userRole'] as String? ?? 'borrower';
      final lenderId = transaction['lenderId'] as String? ?? '';
      final lenderName = transaction['lenderName'] as String? ?? 'Lender';
      final borrowerId = transaction['borrowerId'] as String? ?? '';
      final borrowerName = transaction['borrowerName'] as String? ?? 'Borrower';
      final requestId = transaction['requestId'] as String? ?? '';

      // Determine who to rate based on user's role
      final ratedUserId = userRole == 'borrower' ? lenderId : borrowerId;
      final ratedUserName = userRole == 'borrower' ? lenderName : borrowerName;

      if (ratedUserId.isEmpty || requestId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Rating unavailable for this transaction'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final alreadyRated = await _firestoreService.hasExistingRating(
        raterUserId: currentUser.uid,
        ratedUserId: ratedUserId,
        transactionId: requestId,
      );
      if (alreadyRated) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'You already rated $ratedUserName for this transaction.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
        setState(() {
          _ratedRequestIds.add(requestId);
        });
        return;
      }

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SubmitRatingScreen(
            ratedUserId: ratedUserId,
            ratedUserName: ratedUserName,
            context: RatingContext.borrow,
            transactionId: requestId,
            role: userRole,
          ),
        ),
      );

      setState(() {
        _ratedRequestIds.add(requestId);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Thanks for rating $ratedUserName!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error launching rating: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _messageOtherParty(Map<String, dynamic> transaction) async {
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

      final userRole = transaction['userRole'] as String? ?? 'borrower';
      final lenderId = transaction['lenderId'] as String? ?? '';
      final lenderName = transaction['lenderName'] as String? ?? 'Lender';
      final borrowerId = transaction['borrowerId'] as String? ?? '';
      final borrowerName = transaction['borrowerName'] as String? ?? 'Borrower';

      // Determine the other party based on user's role
      final otherPartyId = userRole == 'borrower' ? lenderId : borrowerId;
      final otherPartyName = userRole == 'borrower' ? lenderName : borrowerName;

      final itemId =
          transaction['id'] as String? ??
          transaction['itemId'] as String? ??
          '';
      final itemTitle = transaction['title'] as String? ?? 'Item';

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
        userId2: otherPartyId,
        userId2Name: otherPartyName,
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
              otherParticipantName: otherPartyName,
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

  void _viewDetails(Map<String, dynamic> transaction) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildTransactionDetailsModal(transaction),
    );
  }

  String _normalizeStorageUrl(String url) {
    return url;
  }

  Widget _buildPlaceholderImage() {
    return Container(
      color: Colors.grey[100],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_outlined, size: 50, color: Colors.grey[400]),
            const SizedBox(height: 8),
            Text(
              'no image available',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[400],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF00897B),
        elevation: 0,
        title: const Text(
          'Transaction History',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadBorrowHistory,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Role filter chips
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            color: Colors.white,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildRoleFilterChip('all', 'All Roles'),
                  const SizedBox(width: 8),
                  _buildRoleFilterChip('borrower', 'As Borrower'),
                  const SizedBox(width: 8),
                  _buildRoleFilterChip('lender', 'As Lender'),
                ],
              ),
            ),
          ),
          // Status filter chips
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            color: Colors.white,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('all', 'All Status'),
                  const SizedBox(width: 8),
                  _buildFilterChip('pending', 'Pending'),
                  const SizedBox(width: 8),
                  _buildFilterChip('accepted', 'Accepted'),
                  const SizedBox(width: 8),
                  _buildFilterChip('returned', 'Returned'),
                  const SizedBox(width: 8),
                  _buildFilterChip('return_disputed', 'Disputed'),
                  const SizedBox(width: 8),
                  _buildFilterChip('declined', 'Declined'),
                  const SizedBox(width: 8),
                  _buildFilterChip('cancelled', 'Cancelled'),
                ],
              ),
            ),
          ),
          // Transactions list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredTransactions.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.history_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No transactions',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Your transaction history will appear here',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadBorrowHistory,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _filteredTransactions.length,
                      itemBuilder: (context, index) {
                        final transaction = _filteredTransactions[index];
                        return _buildTransactionCard(transaction);
                      },
                    ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavBarWidget(
        selectedIndex: null,
        onTap: (_) {},
        navigationContext: context,
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final isSelected = _selectedFilter == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedFilter = value;
        });
      },
      selectedColor: const Color(0xFF00897B).withValues(alpha: 0.2),
      checkmarkColor: const Color(0xFF00897B),
      labelStyle: TextStyle(
        color: isSelected ? const Color(0xFF00897B) : Colors.grey[700],
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildRoleFilterChip(String value, String label) {
    final isSelected = _selectedRoleFilter == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedRoleFilter = value;
        });
      },
      selectedColor: Colors.blue.withValues(alpha: 0.2),
      checkmarkColor: Colors.blue,
      labelStyle: TextStyle(
        color: isSelected ? Colors.blue : Colors.grey[700],
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> transaction) {
    final title = transaction['title'] as String? ?? 'Unknown Item';
    final lenderName = transaction['lenderName'] as String? ?? 'Unknown';
    final borrowerName = transaction['borrowerName'] as String? ?? 'Unknown';
    final userRole = transaction['userRole'] as String? ?? 'borrower';
    final status = transaction['requestStatus'] as String? ?? 'unknown';
    final statusColor = _getStatusColor(status);
    final statusLabel = _getStatusLabel(status);
    final createdAt = _parseDate(transaction['requestCreatedAt']);
    final agreedReturnDate = _parseDate(transaction['agreedReturnDate']);
    final borrowedDate = _parseDate(transaction['borrowedDate']);
    final images =
        (transaction['images'] as List<dynamic>?)?.cast<String>() ?? [];
    final hasImages = images.isNotEmpty;
    final requestId = transaction['requestId'] as String?;
    final isRated = requestId != null && _ratedRequestIds.contains(requestId);

    // Determine the other party's name based on user's role
    final otherPartyName = userRole == 'borrower' ? lenderName : borrowerName;
    final otherPartyLabel = userRole == 'borrower' ? 'Lender' : 'Borrower';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => _viewDetails(transaction),
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            if (hasImages)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                child: Container(
                  height: 200,
                  width: double.infinity,
                  color: Colors.grey[200],
                  child: CachedNetworkImage(
                    imageUrl: _normalizeStorageUrl(images.first),
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: Colors.grey[200],
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                    errorWidget: (context, url, error) {
                      return _buildPlaceholderImage();
                    },
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title and Status
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          statusLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Role Badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: userRole == 'borrower'
                          ? Colors.blue.withValues(alpha: 0.1)
                          : Colors.purple.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: userRole == 'borrower'
                            ? Colors.blue.withValues(alpha: 0.3)
                            : Colors.purple.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          userRole == 'borrower'
                              ? Icons.shopping_cart
                              : Icons.inventory_2,
                          size: 14,
                          color: userRole == 'borrower'
                              ? Colors.blue
                              : Colors.purple,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          userRole == 'borrower'
                              ? 'You: Borrower'
                              : 'You: Lender',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: userRole == 'borrower'
                                ? Colors.blue
                                : Colors.purple,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Other Party Info
                  Row(
                    children: [
                      Icon(
                        Icons.person_outline,
                        size: 16,
                        color: Colors.grey[700],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$otherPartyLabel: $otherPartyName',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Dates
                  if (createdAt != null) ...[
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 14,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Requested: ${_formatDate(createdAt)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (borrowedDate != null) ...[
                    Row(
                      children: [
                        Icon(
                          Icons.shopping_cart,
                          size: 14,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Borrowed: ${_formatDate(borrowedDate)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (agreedReturnDate != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00897B).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF00897B).withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 18,
                            color: const Color(0xFF00897B),
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
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF00897B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // Action Buttons
                  if (status != 'declined' && status != 'cancelled') ...[
                    OutlinedButton.icon(
                      onPressed: () => _messageOtherParty(transaction),
                      icon: const Icon(Icons.message, size: 18),
                      label: Text(
                        userRole == 'borrower'
                            ? 'Message Lender'
                            : 'Message Borrower',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF00897B),
                        side: const BorderSide(color: Color(0xFF00897B)),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        minimumSize: const Size(double.infinity, 40),
                      ),
                    ),
                    // Rating button for returned transactions
                    if (status == 'returned') ...[
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: isRated
                            ? null
                            : () => _rateOtherParty(transaction),
                        icon: const Icon(Icons.star_rate_rounded, size: 18),
                        label: Text(
                          isRated
                              ? (userRole == 'borrower'
                                    ? 'Lender Rated'
                                    : 'Borrower Rated')
                              : (userRole == 'borrower'
                                    ? 'Rate Lender'
                                    : 'Rate Borrower'),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00897B),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          minimumSize: const Size(double.infinity, 40),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionDetailsModal(Map<String, dynamic> transaction) {
    final title = transaction['title'] as String? ?? 'Unknown Item';
    final description = transaction['description'] as String? ?? '';
    final lenderName = transaction['lenderName'] as String? ?? 'Unknown';
    final borrowerName = transaction['borrowerName'] as String? ?? 'Unknown';
    final userRole = transaction['userRole'] as String? ?? 'borrower';
    final category = transaction['category'] as String? ?? 'Other';
    final condition = transaction['condition'] as String? ?? 'Good';
    final location = transaction['location'] as String?;
    final status = transaction['requestStatus'] as String? ?? 'unknown';
    final statusColor = _getStatusColor(status);
    final statusLabel = _getStatusLabel(status);
    final createdAt = _parseDate(transaction['requestCreatedAt']);
    final updatedAt = _parseDate(transaction['requestUpdatedAt']);
    final agreedReturnDate = _parseDate(transaction['agreedReturnDate']);
    final borrowedDate = _parseDate(transaction['borrowedDate']);
    final message = transaction['message'] as String?;
    final images =
        (transaction['images'] as List<dynamic>?)?.cast<String>() ?? [];
    final hasImages = images.isNotEmpty;
    final requestId = transaction['requestId'] as String?;
    final isRated = requestId != null && _ratedRequestIds.contains(requestId);

    // Determine the other party's name based on user's role
    final otherPartyName = userRole == 'borrower' ? lenderName : borrowerName;
    final otherPartyLabel = userRole == 'borrower' ? 'Lender' : 'Borrower';

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
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
                          color: statusColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          statusLabel.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Image
                      if (hasImages)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            height: 250,
                            width: double.infinity,
                            color: Colors.grey[200],
                            child: CachedNetworkImage(
                              imageUrl: _normalizeStorageUrl(images.first),
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: Colors.grey[200],
                                child: const Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                              errorWidget: (context, url, error) {
                                return _buildPlaceholderImage();
                              },
                            ),
                          ),
                        ),
                      if (hasImages) const SizedBox(height: 20),
                      // Title
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Category
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00897B).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          category,
                          style: const TextStyle(
                            color: Color(0xFF00897B),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Role Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: userRole == 'borrower'
                              ? Colors.blue.withValues(alpha: 0.1)
                              : Colors.purple.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: userRole == 'borrower'
                                ? Colors.blue.withValues(alpha: 0.3)
                                : Colors.purple.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              userRole == 'borrower'
                                  ? Icons.shopping_cart
                                  : Icons.inventory_2,
                              size: 16,
                              color: userRole == 'borrower'
                                  ? Colors.blue
                                  : Colors.purple,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              userRole == 'borrower'
                                  ? 'You: Borrower'
                                  : 'You: Lender',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: userRole == 'borrower'
                                    ? Colors.blue
                                    : Colors.purple,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Other Party Info
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
                                  Text(
                                    otherPartyLabel,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  Text(
                                    otherPartyName,
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
                      // Timeline
                      const Text(
                        'Timeline',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (createdAt != null)
                        _buildTimelineItem(
                          'Requested',
                          _formatDate(createdAt),
                          Icons.send,
                        ),
                      if (updatedAt != null && status == 'accepted')
                        _buildTimelineItem(
                          'Approved',
                          _formatDate(updatedAt),
                          Icons.check_circle,
                          isApproved: true,
                        ),
                      if (borrowedDate != null)
                        _buildTimelineItem(
                          'Borrowed',
                          _formatDate(borrowedDate),
                          Icons.shopping_cart,
                        ),
                      if (agreedReturnDate != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF00897B,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(
                                0xFF00897B,
                              ).withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.calendar_today,
                                color: const Color(0xFF00897B),
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
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF00897B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      // Message
                      if (message != null && message.isNotEmpty) ...[
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
                            message,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[800],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      // Location
                      if (location != null && location.isNotEmpty) ...[
                        Row(
                          children: [
                            Icon(Icons.location_on, color: Colors.grey[600]),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Location',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    location,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                      // Condition
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.grey[600]),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Condition',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                condition,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // Description
                      if (description.isNotEmpty) ...[
                        const Text(
                          'Description',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          description,
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.grey[700],
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                      // Action Buttons
                      if (status != 'declined' && status != 'cancelled') ...[
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _messageOtherParty(transaction);
                                },
                                icon: const Icon(Icons.message),
                                label: Text(
                                  userRole == 'borrower'
                                      ? 'Message Lender'
                                      : 'Message Borrower',
                                ),
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
                        // Rating button for returned transactions
                        if (status == 'returned') ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: isRated
                                      ? null
                                      : () {
                                          Navigator.pop(context);
                                          _rateOtherParty(transaction);
                                        },
                                  icon: const Icon(Icons.star_rate_rounded),
                                  label: Text(
                                    isRated
                                        ? (userRole == 'borrower'
                                              ? 'Lender Rated'
                                              : 'Borrower Rated')
                                        : (userRole == 'borrower'
                                              ? 'Rate Lender'
                                              : 'Rate Borrower'),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF00897B),
                                    foregroundColor: Colors.white,
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
                      ],
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
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
      ),
    );
  }
}
