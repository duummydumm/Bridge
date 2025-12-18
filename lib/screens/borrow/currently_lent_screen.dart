import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/firestore_service.dart';
import '../../reusable_widgets/bottom_nav_bar_widget.dart';
import '../chat_detail_screen.dart';

class CurrentlyLentScreen extends StatefulWidget {
  const CurrentlyLentScreen({super.key});

  @override
  State<CurrentlyLentScreen> createState() => _CurrentlyLentScreenState();
}

class _CurrentlyLentScreenState extends State<CurrentlyLentScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  bool _isLoading = true;
  List<Map<String, dynamic>> _lentItems = [];

  @override
  void initState() {
    super.initState();
    _loadLentItems();
  }

  Future<void> _loadLentItems() async {
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

      // Get all items by this lender
      final allItems = await _firestoreService.getItemsByLender(userId);

      // Filter to only show items that are currently borrowed
      final borrowedItems = allItems.where((item) {
        final status = item['status'] as String?;
        return status == 'borrowed' || status == 'return_initiated';
      }).toList();

      // Enrich with borrow request information
      final enrichedItems = <Map<String, dynamic>>[];
      for (final item in borrowedItems) {
        final itemId = item['id'] as String?;
        if (itemId == null) continue;

        try {
          // Get the borrow request for this item
          // Query borrow_requests collection directly
          final db = FirebaseFirestore.instance;
          final requestQuery = await db
              .collection('borrow_requests')
              .where('itemId', isEqualTo: itemId)
              .where('lenderId', isEqualTo: userId)
              .where('status', whereIn: ['accepted', 'return_initiated'])
              .limit(1)
              .get();

          if (requestQuery.docs.isNotEmpty) {
            final request = requestQuery.docs.first.data();
            final requestId = requestQuery.docs.first.id;

            final enrichedItem = Map<String, dynamic>.from(item);
            enrichedItem['requestId'] = requestId;
            enrichedItem['borrowerId'] = request['borrowerId'];
            enrichedItem['borrowerName'] = request['borrowerName'];
            enrichedItem['returnStatus'] = request['status'];
            enrichedItem['agreedReturnDate'] = request['agreedReturnDate'];
            enrichedItem['returnInitiatedAt'] = request['returnInitiatedAt'];
            enrichedItems.add(enrichedItem);
          } else {
            // Still add item even without request data
            enrichedItems.add(item);
          }
        } catch (e) {
          debugPrint('Error fetching borrow request for item $itemId: $e');
          // If request lookup fails, still include the item
          enrichedItems.add(item);
        }
      }

      setState(() {
        _lentItems = enrichedItems;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading lent items: $e'),
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

  String _getDaysRemainingText(DateTime? returnDate) {
    if (returnDate == null) return 'No return date set';

    // Normalize to start of day for accurate day comparison
    final now = DateTime.now();
    final nowStartOfDay = DateTime(now.year, now.month, now.day);
    final returnDateStartOfDay = DateTime(
      returnDate.year,
      returnDate.month,
      returnDate.day,
    );

    final difference = returnDateStartOfDay.difference(nowStartOfDay);
    final daysDifference = difference.inDays;

    if (daysDifference < 0) {
      return 'Overdue by ${daysDifference.abs()} ${daysDifference.abs() == 1 ? 'day' : 'days'}';
    } else if (daysDifference == 0) {
      return 'Due today';
    } else if (daysDifference == 1) {
      return 'Due tomorrow';
    } else {
      return 'Due in ${daysDifference} days';
    }
  }

  Color _getStatusColor(DateTime? returnDate, String? returnStatus) {
    if (returnStatus == 'return_initiated') return Colors.orange;
    if (returnDate == null) return Colors.grey;

    // Normalize to start of day for accurate day comparison
    final now = DateTime.now();
    final nowStartOfDay = DateTime(now.year, now.month, now.day);
    final returnDateStartOfDay = DateTime(
      returnDate.year,
      returnDate.month,
      returnDate.day,
    );

    final difference = returnDateStartOfDay.difference(nowStartOfDay);
    final daysDifference = difference.inDays;

    if (daysDifference < 0) {
      return Colors.red;
    } else if (daysDifference <= 3) {
      return Colors.orange;
    } else {
      return Colors.green;
    }
  }

  Future<void> _messageBorrower(Map<String, dynamic> item) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);

      if (!authProvider.isAuthenticated || authProvider.user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please login to message borrower'),
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

      final borrowerId =
          item['borrowerId'] as String? ??
          item['currentBorrowerId'] as String? ??
          '';
      final borrowerName = item['borrowerName'] as String? ?? 'Borrower';
      final itemId = item['id'] as String? ?? '';
      final itemTitle = item['title'] as String? ?? 'Item';

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

  void _viewDetails(Map<String, dynamic> item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildItemDetailsModal(item),
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
          'Items Currently Lent',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadLentItems,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _lentItems.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No items currently lent',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Items you have lent out will appear here',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadLentItems,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _lentItems.length,
                itemBuilder: (context, index) {
                  final item = _lentItems[index];
                  return _buildLentItemCard(item);
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

  Widget _buildLentItemCard(Map<String, dynamic> item) {
    final title = item['title'] as String? ?? 'Unknown Item';
    final borrowerName =
        item['borrowerName'] as String? ??
        item['currentBorrowerId'] as String? ??
        'Unknown';
    final returnDate = _parseDate(
      item['returnDate'] ?? item['agreedReturnDate'],
    );
    final borrowedDate = _parseDate(item['borrowedDate']);
    final images = (item['images'] as List<dynamic>?)?.cast<String>() ?? [];
    final hasImages = images.isNotEmpty;
    final returnStatus = item['returnStatus'] as String? ?? 'accepted';
    final isReturnInitiated = returnStatus == 'return_initiated';
    final statusColor = _getStatusColor(returnDate, returnStatus);
    final isOverdue =
        returnDate != null &&
        returnDate.isBefore(DateTime.now()) &&
        !isReturnInitiated;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => _viewDetails(item),
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
                          color: isReturnInitiated
                              ? Colors.orange
                              : (isOverdue ? Colors.red : statusColor),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isReturnInitiated
                              ? 'Return Pending'
                              : (isOverdue ? 'Overdue' : 'Lent Out'),
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
                  // Borrower Info
                  Row(
                    children: [
                      Icon(
                        Icons.person_outline,
                        size: 16,
                        color: Colors.grey[700],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Borrower: $borrowerName',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Return Date
                  if (returnDate != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isReturnInitiated
                            ? Colors.orange.withValues(alpha: 0.1)
                            : (isOverdue
                                  ? Colors.red.withValues(alpha: 0.1)
                                  : const Color(
                                      0xFF00897B,
                                    ).withValues(alpha: 0.1)),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isReturnInitiated
                              ? Colors.orange.withValues(alpha: 0.3)
                              : (isOverdue
                                    ? Colors.red.withValues(alpha: 0.3)
                                    : const Color(
                                        0xFF00897B,
                                      ).withValues(alpha: 0.3)),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 18,
                            color: statusColor,
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
                                  _formatDate(returnDate),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: statusColor,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _getDaysRemainingText(returnDate),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: statusColor,
                                    fontStyle: FontStyle.italic,
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
                  // Return Status Banner (if return initiated)
                  if (isReturnInitiated) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.pending_outlined,
                            color: Colors.orange[700],
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Borrower has requested return. Please confirm in Pending Returns.',
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
                  // Borrowed Date
                  if (borrowedDate != null) ...[
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 14,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Lent on: ${_formatDate(borrowedDate)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  // Action Button
                  OutlinedButton.icon(
                    onPressed: () => _messageBorrower(item),
                    icon: const Icon(Icons.message, size: 18),
                    label: const Text('Message Borrower'),
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemDetailsModal(Map<String, dynamic> item) {
    final title = item['title'] as String? ?? 'Unknown Item';
    final description = item['description'] as String? ?? '';
    final borrowerName =
        item['borrowerName'] as String? ??
        item['currentBorrowerId'] as String? ??
        'Unknown';
    final category = item['category'] as String? ?? 'Other';
    final condition = item['condition'] as String? ?? 'Good';
    final location = item['location'] as String?;
    final returnDate = _parseDate(
      item['returnDate'] ?? item['agreedReturnDate'],
    );
    final borrowedDate = _parseDate(item['borrowedDate']);
    final images = (item['images'] as List<dynamic>?)?.cast<String>() ?? [];
    final hasImages = images.isNotEmpty;
    final returnStatus = item['returnStatus'] as String? ?? 'accepted';
    final isReturnInitiated = returnStatus == 'return_initiated';
    final statusColor = _getStatusColor(returnDate, returnStatus);
    final isOverdue =
        returnDate != null &&
        returnDate.isBefore(DateTime.now()) &&
        !isReturnInitiated;

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
                          color: isReturnInitiated
                              ? Colors.orange
                              : (isOverdue ? Colors.red : Colors.green),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isReturnInitiated
                              ? 'RETURN PENDING'
                              : (isOverdue ? 'OVERDUE' : 'CURRENTLY LENT'),
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
                      // Borrower Info
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
                                    'Borrower',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  Text(
                                    borrowerName,
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
                      if (returnDate != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isReturnInitiated
                                ? Colors.orange.withValues(alpha: 0.1)
                                : (isOverdue
                                      ? Colors.red.withValues(alpha: 0.1)
                                      : const Color(
                                          0xFF00897B,
                                        ).withValues(alpha: 0.1)),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isReturnInitiated
                                  ? Colors.orange.withValues(alpha: 0.3)
                                  : (isOverdue
                                        ? Colors.red.withValues(alpha: 0.3)
                                        : const Color(
                                            0xFF00897B,
                                          ).withValues(alpha: 0.3)),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.calendar_today,
                                color: statusColor,
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
                                      _formatDate(returnDate),
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: statusColor,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _getDaysRemainingText(returnDate),
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: statusColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (isOverdue) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Please contact borrower to arrange return',
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
                      // Borrowed Date
                      if (borrowedDate != null) ...[
                        Row(
                          children: [
                            Icon(Icons.access_time, color: Colors.grey[600]),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Lent Date',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  _formatDate(borrowedDate),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
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
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                _messageBorrower(item);
                              },
                              icon: const Icon(Icons.message),
                              label: const Text('Message Borrower'),
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
}
