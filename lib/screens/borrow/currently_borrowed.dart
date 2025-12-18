import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../reusable_widgets/bottom_nav_bar_widget.dart';
import '../chat_detail_screen.dart';

class CurrentlyBorrowedScreen extends StatefulWidget {
  const CurrentlyBorrowedScreen({super.key});

  @override
  State<CurrentlyBorrowedScreen> createState() =>
      _CurrentlyBorrowedScreenState();
}

class _CurrentlyBorrowedScreenState extends State<CurrentlyBorrowedScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final StorageService _storageService = StorageService();
  final ImagePicker _imagePicker = ImagePicker();
  bool _isLoading = true;
  List<Map<String, dynamic>> _borrowedItems = [];

  @override
  void initState() {
    super.initState();
    _loadBorrowedItems();
  }

  Future<void> _loadBorrowedItems() async {
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

      final items = await _firestoreService.getBorrowedItemsByBorrower(userId);
      setState(() {
        _borrowedItems = items;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading borrowed items: $e'),
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

  Color _getStatusColor(DateTime? returnDate) {
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

  Future<void> _initiateReturn(
    Map<String, dynamic> item,
    String requestId,
  ) async {
    // Show condition verification modal
    final conditionData = await _showConditionVerificationModal(item);
    if (conditionData == null) return; // User cancelled

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final borrowerId = authProvider.user?.uid;

      if (borrowerId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please login to return item'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Show loading
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (dialogContext) =>
            const Center(child: CircularProgressIndicator()),
      );

      await _firestoreService.initiateBorrowReturn(
        requestId: requestId,
        borrowerId: borrowerId,
        condition: conditionData['condition'],
        conditionNotes: conditionData['notes'],
        conditionPhotos: conditionData['photos'],
      );

      // Close loading dialog
      if (mounted) {
        final rootNav = Navigator.of(context, rootNavigator: true);
        if (rootNav.canPop()) rootNav.pop();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Return request sent! Waiting for lender confirmation.',
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );

        // Refresh the list
        _loadBorrowedItems();
      }
    } catch (e) {
      if (mounted) {
        final rootNav = Navigator.of(context, rootNavigator: true);
        if (rootNav.canPop()) rootNav.pop();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error initiating return: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<Map<String, dynamic>?> _showConditionVerificationModal(
    Map<String, dynamic> item,
  ) async {
    String? selectedCondition;
    final notesController = TextEditingController();
    final List<XFile> selectedPhotos = [];
    bool isUploading = false;

    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Item Condition Verification'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Please report the condition of the item you are returning:',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                // Condition Selection
                const Text(
                  'Condition:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildConditionChip(
                      'same',
                      'Same',
                      selectedCondition,
                      () => setState(() => selectedCondition = 'same'),
                    ),
                    _buildConditionChip(
                      'better',
                      'Better',
                      selectedCondition,
                      () => setState(() => selectedCondition = 'better'),
                    ),
                    _buildConditionChip(
                      'worse',
                      'Worse',
                      selectedCondition,
                      () => setState(() => selectedCondition = 'worse'),
                    ),
                    _buildConditionChip(
                      'damaged',
                      'Damaged',
                      selectedCondition,
                      () => setState(() => selectedCondition = 'damaged'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Notes
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Additional Notes (Optional)',
                    hintText: 'Describe the condition or any issues...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                // Photo Upload
                const Text(
                  'Photos (Optional):',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                if (selectedPhotos.isNotEmpty)
                  SizedBox(
                    height: 100,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: selectedPhotos.length,
                      itemBuilder: (context, index) {
                        return Stack(
                          children: [
                            Container(
                              margin: const EdgeInsets.only(right: 8),
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  File(selectedPhotos[index].path),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: IconButton(
                                icon: const Icon(Icons.close, size: 20),
                                color: Colors.red,
                                onPressed: () {
                                  setState(() {
                                    selectedPhotos.removeAt(index);
                                  });
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: isUploading
                      ? null
                      : () async {
                          try {
                            final XFile? photo = await _imagePicker.pickImage(
                              source: ImageSource.gallery,
                              imageQuality: 85,
                            );
                            if (photo != null) {
                              setState(() {
                                selectedPhotos.add(photo);
                              });
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error picking image: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                  icon: const Icon(Icons.add_photo_alternate),
                  label: const Text('Add Photo'),
                ),
                if (isUploading) ...[
                  const SizedBox(height: 8),
                  const Center(child: CircularProgressIndicator()),
                  const Center(
                    child: Text(
                      'Uploading photos...',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isUploading
                  ? null
                  : () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isUploading || selectedCondition == null
                  ? null
                  : () async {
                      if (selectedCondition == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please select item condition'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                        return;
                      }

                      setState(() => isUploading = true);

                      // Upload photos if any
                      final List<String> uploadedPhotoUrls = [];
                      if (selectedPhotos.isNotEmpty) {
                        try {
                          final authProvider = Provider.of<AuthProvider>(
                            context,
                            listen: false,
                          );
                          final userId = authProvider.user?.uid;
                          final requestId = item['requestId'] as String? ?? '';

                          if (userId != null && requestId.isNotEmpty) {
                            for (final photo in selectedPhotos) {
                              try {
                                final url = await _storageService
                                    .uploadConditionPhoto(
                                      file: photo,
                                      requestId: requestId,
                                      userId: userId,
                                    );
                                uploadedPhotoUrls.add(url);
                              } catch (e) {
                                debugPrint('Error uploading photo: $e');
                                // Continue with other photos even if one fails
                              }
                            }
                          }
                        } catch (e) {
                          debugPrint('Error uploading photos: $e');
                        }
                      }

                      Navigator.pop(context, {
                        'condition': selectedCondition,
                        'notes': notesController.text.trim(),
                        'photos': uploadedPhotoUrls,
                      });
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00897B),
                foregroundColor: Colors.white,
              ),
              child: const Text('Submit Return'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConditionChip(
    String value,
    String label,
    String? selected,
    VoidCallback onTap,
  ) {
    final isSelected = selected == value;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00897B) : Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF00897B) : Colors.grey[400]!,
            width: 2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[800],
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
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
          'Currently Borrowed',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadBorrowedItems,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _borrowedItems.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.shopping_cart_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No items currently borrowed',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Items you are currently borrowing will appear here',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadBorrowedItems,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _borrowedItems.length,
                itemBuilder: (context, index) {
                  final item = _borrowedItems[index];
                  return _buildBorrowedItemCard(item);
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

  Widget _buildBorrowedItemCard(Map<String, dynamic> item) {
    final title = item['title'] as String? ?? 'Unknown Item';
    final lenderName = item['lenderName'] as String? ?? 'Unknown';
    final returnDate = _parseDate(item['returnDate']);
    final borrowedDate = _parseDate(item['borrowedDate']);
    final images = (item['images'] as List<dynamic>?)?.cast<String>() ?? [];
    final hasImages = images.isNotEmpty;
    final statusColor = _getStatusColor(returnDate);
    final isOverdue = returnDate != null && returnDate.isBefore(DateTime.now());
    final returnStatus = item['returnStatus'] as String? ?? 'accepted';
    final isReturnInitiated = returnStatus == 'return_initiated';
    final requestId = item['requestId'] as String?;

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
                              : (isOverdue ? 'Overdue' : 'Active'),
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
                  if (returnDate != null) ...[
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
                              'Return request sent. Waiting for lender confirmation.',
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
                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _messageLender(item),
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
                      ),
                      if (!isReturnInitiated && requestId != null) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _initiateReturn(item, requestId),
                            icon: const Icon(
                              Icons.assignment_returned,
                              size: 18,
                            ),
                            label: const Text('Return Item'),
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
                    ],
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
    final returnDate = _parseDate(item['returnDate']);
    final borrowedDate = _parseDate(item['borrowedDate']);
    final images = (item['images'] as List<dynamic>?)?.cast<String>() ?? [];
    final hasImages = images.isNotEmpty;
    final statusColor = _getStatusColor(returnDate);
    final isOverdue = returnDate != null && returnDate.isBefore(DateTime.now());

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
                          color: isOverdue ? Colors.red : Colors.green,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isOverdue ? 'OVERDUE' : 'CURRENTLY BORROWED',
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
                      if (returnDate != null) ...[
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
                                        'Please return this item as soon as possible',
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
