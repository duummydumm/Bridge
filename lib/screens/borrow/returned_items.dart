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

class ReturnedItemsScreen extends StatefulWidget {
  const ReturnedItemsScreen({super.key});

  @override
  State<ReturnedItemsScreen> createState() => _ReturnedItemsScreenState();
}

class _ReturnedItemsScreenState extends State<ReturnedItemsScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final Set<String> _ratedRequestIds = <String>{};
  bool _isLoading = true;
  List<Map<String, dynamic>> _returnedItems = [];

  @override
  void initState() {
    super.initState();
    _loadReturnedItems();
  }

  Future<void> _loadReturnedItems() async {
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

      final items = await _firestoreService.getReturnedItemsByBorrower(userId);
      final ratedIds = <String>{};
      for (final item in items) {
        final requestId = item['requestId'] as String?;
        final lenderId = item['lenderId'] as String?;
        if (requestId == null || lenderId == null) continue;
        final hasRated = await _firestoreService.hasExistingRating(
          raterUserId: userId,
          ratedUserId: lenderId,
          transactionId: requestId,
        );
        if (hasRated) {
          ratedIds.add(requestId);
        }
      }
      setState(() {
        _returnedItems = items;
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
            content: Text('Error loading returned items: $e'),
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

  Future<void> _messageLender(Map<String, dynamic> item) async {
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

      final lenderId = item['lenderId'] as String? ?? '';
      final lenderName = item['lenderName'] as String? ?? 'Lender';
      final itemId = item['id'] as String? ?? item['itemId'] as String? ?? '';
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

  Future<void> _rateLender(Map<String, dynamic> item) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.user;
      if (currentUser == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please login to rate lenders'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final lenderId = item['lenderId'] as String? ?? '';
      final lenderName = item['lenderName'] as String? ?? 'Lender';
      final requestId =
          item['requestId'] as String? ?? item['id'] as String? ?? '';

      if (lenderId.isEmpty || requestId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Rating unavailable for this item'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final alreadyRated = await _firestoreService.hasExistingRating(
        raterUserId: currentUser.uid,
        ratedUserId: lenderId,
        transactionId: requestId,
      );
      if (alreadyRated) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You already rated this lender for this return.'),
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
            ratedUserId: lenderId,
            ratedUserName: lenderName,
            context: RatingContext.borrow,
            transactionId: requestId,
            role: 'borrower',
          ),
        ),
      );

      setState(() {
        _ratedRequestIds.add(requestId);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Thanks for rating $lenderName!')),
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
          'Returned Items',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadReturnedItems,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _returnedItems.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.assignment_returned_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No returned items',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Items you have returned will appear here',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadReturnedItems,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _returnedItems.length,
                itemBuilder: (context, index) {
                  final item = _returnedItems[index];
                  return _buildReturnedItemCard(item);
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

  Widget _buildReturnedItemCard(Map<String, dynamic> item) {
    final title = item['title'] as String? ?? 'Unknown Item';
    final lenderName = item['lenderName'] as String? ?? 'Unknown';
    final agreedReturnDate = _parseDate(item['agreedReturnDate']);
    final borrowedDate = _parseDate(item['borrowedDate']);
    final images = (item['images'] as List<dynamic>?)?.cast<String>() ?? [];
    final hasImages = images.isNotEmpty;
    final requestId = item['requestId'] as String?;
    final isRated = requestId != null && _ratedRequestIds.contains(requestId);

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
                          color: Colors.grey[600],
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Returned',
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
                  // Lender Info
                  Row(
                    children: [
                      Icon(
                        Icons.person_outline,
                        size: 16,
                        color: Colors.grey[700],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Lender: $lenderName',
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
                  if (agreedReturnDate != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!, width: 1),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 18,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Expected Return Date',
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
                                    color: Colors.grey[800],
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
                          'Borrowed: ${_formatDate(borrowedDate)}',
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
                    onPressed: () => _messageLender(item),
                    icon: const Icon(Icons.message, size: 18),
                    label: const Text('Message Lender'),
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
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: isRated ? null : () => _rateLender(item),
                    icon: const Icon(Icons.star_rate_rounded, size: 18),
                    label: Text(isRated ? 'Lender Rated' : 'Rate Lender'),
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
    final lenderName = item['lenderName'] as String? ?? 'Unknown';
    final category = item['category'] as String? ?? 'Other';
    final condition = item['condition'] as String? ?? 'Good';
    final location = item['location'] as String?;
    final agreedReturnDate = _parseDate(item['agreedReturnDate']);
    final borrowedDate = _parseDate(item['borrowedDate']);
    final images = (item['images'] as List<dynamic>?)?.cast<String>() ?? [];
    final hasImages = images.isNotEmpty;

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
                          color: Colors.grey[600],
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'RETURNED',
                          style: TextStyle(
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
                                    lenderName,
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
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.grey[300]!,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.calendar_today,
                                color: Colors.grey[600],
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Expected Return Date',
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
                                        color: Colors.grey[800],
                                      ),
                                    ),
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
                                  'Borrowed Date',
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
                                _messageLender(item);
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
}
