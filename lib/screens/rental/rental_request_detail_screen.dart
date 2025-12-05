import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/rental_request_provider.dart';
import '../../services/firestore_service.dart';
import '../../models/rental_request_model.dart';
import '../../models/rating_model.dart';
import '../../services/rating_service.dart';
import '../chat_detail_screen.dart';
import '../submit_rating_screen.dart';

class RentalRequestDetailScreen extends StatefulWidget {
  final String requestId;

  const RentalRequestDetailScreen({super.key, required this.requestId});

  @override
  State<RentalRequestDetailScreen> createState() =>
      _RentalRequestDetailScreenState();
}

class _RentalRequestDetailScreenState extends State<RentalRequestDetailScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final RatingService _ratingService = RatingService();
  Map<String, dynamic>? _requestData;
  bool _isLoading = true;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _loadRequest();
  }

  Future<void> _loadRequest() async {
    try {
      final data = await _firestoreService.getRentalRequest(widget.requestId);
      if (data == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      // Enrich data with readable renter/owner names, item title, category, and image
      final enrichedData = Map<String, dynamic>.from(data);

      // Get item title from listing first, then fallback to item itself
      final listingId = data['listingId'] as String?;
      if (listingId != null) {
        try {
          final listing = await _firestoreService.getRentalListing(listingId);
          if (listing != null) {
            enrichedData['itemTitle'] = listing['title'] as String?;
            enrichedData['itemCategory'] =
                listing['category'] as String? ??
                listing['rentType'] as String?;
            // Store rentType for return button logic
            enrichedData['rentType'] = listing['rentType'] as String?;

            // Prefer main listing imageUrl, then first image from images[]
            String? imageUrl = listing['imageUrl'] as String?;
            final images = listing['images'] as List<dynamic>?;
            if ((imageUrl == null || imageUrl.isEmpty) &&
                images != null &&
                images.isNotEmpty) {
              final first = images.first;
              if (first is String && first.isNotEmpty) {
                imageUrl = first;
              }
            }
            if (imageUrl != null && imageUrl.isNotEmpty) {
              enrichedData['itemImageUrl'] = imageUrl;
            }
            if (enrichedData['itemTitle'] == null ||
                (enrichedData['itemTitle'] as String).isEmpty) {
              final itemId = data['itemId'] as String?;
              if (itemId != null) {
                final item = await _firestoreService.getItem(itemId);
                if (item != null) {
                  enrichedData['itemTitle'] = item['title'] as String?;
                  enrichedData['itemCategory'] =
                      item['category'] as String? ??
                      enrichedData['itemCategory'];
                  final itemImages = item['images'] as List<dynamic>?;
                  if (itemImages != null && itemImages.isNotEmpty) {
                    final first = itemImages.first;
                    if (first is String && first.isNotEmpty) {
                      enrichedData['itemImageUrl'] ??= first;
                    }
                  }
                }
              }
            }
          }
        } catch (_) {
          // Best-effort enrichment; continue even if listing fetch fails
        }
      }
      enrichedData['itemTitle'] ??= 'Rental Item';
      enrichedData['itemCategory'] ??= 'General';

      // Get renter name from users collection
      final renterId = data['renterId'] as String?;
      if (renterId != null) {
        try {
          final renter = await _firestoreService.getUser(renterId);
          if (renter != null) {
            final firstName = renter['firstName'] ?? '';
            final lastName = renter['lastName'] ?? '';
            enrichedData['renterName'] = '$firstName $lastName'.trim();
          }
        } catch (_) {
          // Ignore enrichment errors
        }
      }
      enrichedData['renterName'] ??= 'Unknown';

      // Get owner name from users collection
      final ownerId = data['ownerId'] as String?;
      if (ownerId != null) {
        try {
          final owner = await _firestoreService.getUser(ownerId);
          if (owner != null) {
            final firstName = owner['firstName'] ?? '';
            final lastName = owner['lastName'] ?? '';
            enrichedData['ownerName'] = '$firstName $lastName'.trim();
          }
        } catch (_) {
          // Ignore enrichment errors
        }
      }
      enrichedData['ownerName'] ??= 'Owner';

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

    // Confirm acceptance
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Accept Rental Request?'),
        content: Text(
          'Are you sure you want to accept the rental request from '
          '${_requestData!['renterName'] ?? 'the renter'}?',
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

    if (confirmed != true) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final reqProvider = Provider.of<RentalRequestProvider>(
        context,
        listen: false,
      );

      // Update status to ownerApproved
      final success = await reqProvider.setStatus(
        widget.requestId,
        RentalRequestStatus.ownerApproved,
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Rental request accepted successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          // Reload request to show updated status
          await _loadRequest();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                reqProvider.errorMessage ?? 'Failed to accept request',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() {
          _isProcessing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error accepting request: $e'),
            backgroundColor: Colors.red,
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
        title: const Text('Decline Rental Request?'),
        content: Text(
          'Are you sure you want to decline the rental request from '
          '${_requestData!['renterName'] ?? 'the renter'}?',
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
      final reqProvider = Provider.of<RentalRequestProvider>(
        context,
        listen: false,
      );

      // Update status to cancelled
      final success = await reqProvider.setStatus(
        widget.requestId,
        RentalRequestStatus.cancelled,
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Rental request declined'),
              backgroundColor: Colors.orange,
            ),
          );
          Navigator.of(context).pop(true); // Return to previous screen
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                reqProvider.errorMessage ?? 'Failed to decline request',
              ),
              backgroundColor: Colors.red,
            ),
          );
          setState(() {
            _isProcessing = false;
          });
        }
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

  Future<void> _markPaymentReceived() async {
    if (_requestData == null) return;

    // Confirm marking payment as received
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark Payment Received?'),
        content: Text(
          _requestData?['paymentMethod'] == 'online'
              ? 'Have you received the payment (base price + deposit) from the renter via online payment?'
              : 'Have you received the cash payment (base price + deposit) from the renter during meetup?',
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
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final reqProvider = Provider.of<RentalRequestProvider>(
        context,
        listen: false,
      );

      final success = await reqProvider.markPaymentReceived(widget.requestId);

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Payment marked as received!'),
              backgroundColor: Colors.green,
            ),
          );
          // Reload request to show updated status
          await _loadRequest();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                reqProvider.errorMessage ?? 'Failed to mark payment',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() {
          _isProcessing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _messageRenter() async {
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

    final renterId = _requestData!['renterId'] as String;
    final renterName = _requestData!['renterName'] as String? ?? 'User';
    final itemId = _requestData!['itemId'] as String;
    final itemTitle = _requestData!['itemTitle'] as String? ?? 'Rental Item';

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
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    if (date is Timestamp) {
      final dt = date.toDate();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }
    if (date is DateTime) {
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }
    return date.toString();
  }

  String _formatCurrency(double? amount) {
    if (amount == null) return '₱0.00';
    return '₱${amount.toStringAsFixed(2)}';
  }

  String _getPaymentInstructions(
    String paymentMethod,
    double priceQuote,
    double? depositAmount,
  ) {
    if (paymentMethod == 'online') {
      return 'Waiting for renter to pay base price (₱${priceQuote.toStringAsFixed(2)})${depositAmount != null && depositAmount > 0 ? ' + deposit (₱${depositAmount.toStringAsFixed(2)})' : ''} via online payment (GCash or payment gateway).';
    } else {
      return 'Waiting for renter to pay base price (₱${priceQuote.toStringAsFixed(2)})${depositAmount != null && depositAmount > 0 ? ' + deposit (₱${depositAmount.toStringAsFixed(2)})' : ''} in cash during meetup.';
    }
  }

  String _getPaymentMethodInstructions(String paymentMethod) {
    if (paymentMethod == 'online') {
      return 'The renter will pay online via GCash or payment gateway. Once payment is confirmed, you can mark it as received.';
    } else {
      return 'The renter will pay cash in person during meetup. Once you receive the cash payment, mark it as received.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rental Request'),
        backgroundColor: const Color(0xFF00897B),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _requestData == null
          ? const Center(child: Text('Request not found'))
          : _buildRequestDetails(),
    );
  }

  Widget _buildRequestDetails() {
    final status = _requestData!['status'] as String? ?? 'requested';
    final renterName = _requestData!['renterName'] as String? ?? 'Unknown';
    final itemTitle = _requestData!['itemTitle'] as String? ?? 'Rental Item';
    final itemCategory = _requestData!['itemCategory'] as String? ?? 'General';
    final itemImageUrl = _requestData!['itemImageUrl'] as String?;
    final notes = _requestData!['notes'] as String? ?? '';
    final createdAt = _requestData!['createdAt'];
    final startDate = _requestData!['startDate'];
    final endDate = _requestData!['endDate'];
    final durationDays = _requestData!['durationDays'] as int? ?? 0;
    final priceQuote = (_requestData!['priceQuote'] as num?)?.toDouble() ?? 0.0;
    final depositAmount = (_requestData!['depositAmount'] as num?)?.toDouble();
    final totalDue = (_requestData!['totalDue'] as num?)?.toDouble() ?? 0.0;
    final paymentStatus = _requestData!['paymentStatus'] as String? ?? 'unpaid';
    final ownerId = _requestData!['ownerId'] as String?;

    // Check if current user is the owner
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = authProvider.user?.uid;
    final isOwner = currentUserId != null && ownerId == currentUserId;

    // Check if request is still pending (requested status)
    final isPending = status == 'requested';
    final isOwnerApproved = status == 'ownerapproved';
    final isActive = status == 'active' || status == 'ownerapproved';
    final isReturnInitiated = status == 'returninitiated';
    final isReturned = status == 'returned';

    // Check if current user is the renter
    final renterId = _requestData!['renterId'] as String?;
    final isRenter = currentUserId != null && renterId == currentUserId;

    return Container(
      color: const Color(0xFFF5F5F5),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header card with status & quick info
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
                            color: status == 'requested'
                                ? Colors.orange
                                : status == 'ownerapproved' ||
                                      status == 'active'
                                ? Colors.green
                                : status == 'cancelled'
                                ? Colors.red
                                : Colors.grey,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            status.toUpperCase().replaceAll('_', ' '),
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
                                _formatDate(createdAt),
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
                          borderRadius: BorderRadius.circular(12),
                          child: itemImageUrl != null && itemImageUrl.isNotEmpty
                              ? Image.network(
                                  itemImageUrl,
                                  width: 72,
                                  height: 72,
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  width: 72,
                                  height: 72,
                                  color: const Color(
                                    0xFF00897B,
                                  ).withOpacity(0.08),
                                  child: const Icon(
                                    Icons.inventory_2,
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
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.person,
                                    size: 16,
                                    color: Color(0xFF00897B),
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      renterName,
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

            // Rental period card
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
                          'Rental Period',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Start',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _formatDate(startDate),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'End',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                endDate == null
                                    ? 'Month-to-month (Ongoing)'
                                    : _formatDate(endDate),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  fontStyle: endDate == null
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (durationDays > 0) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00897B).withOpacity(0.06),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Duration: $durationDays day${durationDays != 1 ? 's' : ''}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF00897B),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Payment breakdown card
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
                          Icons.receipt_long,
                          color: Color(0xFF00897B),
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Payment Breakdown',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildPaymentRow('Base Price', priceQuote),
                    if (depositAmount != null && depositAmount > 0)
                      _buildPaymentRow('Security Deposit', depositAmount),
                    const Divider(height: 20),
                    _buildPaymentRow('Total Due', totalDue, isTotal: true),
                  ],
                ),
              ),
            ),

            // Payment status
            if (isOwner && isOwnerApproved) ...[
              const SizedBox(height: 16),
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                color: paymentStatus == 'captured'
                    ? Colors.green[50]
                    : Colors.orange[50],
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            paymentStatus == 'captured'
                                ? Icons.check_circle
                                : Icons.pending,
                            color: paymentStatus == 'captured'
                                ? Colors.green[700]
                                : Colors.orange[700],
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            paymentStatus == 'captured'
                                ? 'Payment Received'
                                : 'Waiting for Payment',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: paymentStatus == 'captured'
                                  ? Colors.green[900]
                                  : Colors.orange[900],
                            ),
                          ),
                        ],
                      ),
                      // Payment Method Badge
                      if (_requestData != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color:
                                (_requestData!['paymentMethod'] as String? ??
                                        'meetup') ==
                                    'online'
                                ? Colors.blue[100]
                                : Colors.purple[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                (_requestData!['paymentMethod'] as String? ??
                                            'meetup') ==
                                        'online'
                                    ? Icons.payment
                                    : Icons.handshake,
                                size: 14,
                                color:
                                    (_requestData!['paymentMethod']
                                                as String? ??
                                            'meetup') ==
                                        'online'
                                    ? Colors.blue[800]
                                    : Colors.purple[800],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                (_requestData!['paymentMethod'] as String? ??
                                            'meetup') ==
                                        'online'
                                    ? 'Online Payment'
                                    : 'Meetup Payment',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      (_requestData!['paymentMethod']
                                                  as String? ??
                                              'meetup') ==
                                          'online'
                                      ? Colors.blue[800]
                                      : Colors.purple[800],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        paymentStatus == 'captured'
                            ? 'Base price and deposit have been received.'
                            : _getPaymentInstructions(
                                _requestData?['paymentMethod'] as String? ??
                                    'meetup',
                                priceQuote,
                                depositAmount,
                              ),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[700],
                          height: 1.4,
                        ),
                      ),
                      if (paymentStatus != 'captured') ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isProcessing
                                ? null
                                : () => _markPaymentReceived(),
                            icon: const Icon(Icons.payment, size: 18),
                            label: Text(
                              (_requestData?['paymentMethod'] as String? ??
                                          'meetup') ==
                                      'online'
                                  ? 'Mark Online Payment Received'
                                  : 'Mark Payment Received',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00897B),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],

            // Notes
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 16),
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
                            Icons.sticky_note_2_outlined,
                            color: Color(0xFF00897B),
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Notes',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        notes,
                        style: const TextStyle(fontSize: 14, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // Action buttons & overall status
            const SizedBox(height: 20),
            if (isOwnerApproved &&
                isOwner &&
                paymentStatus != 'captured' &&
                !_isProcessing) ...[
              Card(
                elevation: 0,
                color: Colors.blue[50],
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
                          Icon(
                            Icons.info_outline,
                            color: Colors.blue[700],
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Payment Instructions',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.blue[900],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _getPaymentMethodInstructions(
                          _requestData?['paymentMethod'] as String? ?? 'meetup',
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[700],
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            // Pending request actions
            if (isPending && !_isProcessing) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _messageRenter,
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
              const Center(child: CircularProgressIndicator()),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: status == 'ownerapproved' || status == 'active'
                      ? Colors.green[50]
                      : status == 'cancelled'
                      ? Colors.red[50]
                      : Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      status == 'ownerapproved' || status == 'active'
                          ? Icons.check_circle
                          : status == 'cancelled'
                          ? Icons.cancel
                          : Icons.info,
                      color: status == 'ownerapproved' || status == 'active'
                          ? Colors.green
                          : status == 'cancelled'
                          ? Colors.red
                          : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        status == 'ownerapproved' || status == 'active'
                            ? 'This request has been accepted'
                            : status == 'cancelled'
                            ? 'This request has been declined'
                            : 'This request is ${status.replaceAll('_', ' ')}',
                        style: TextStyle(
                          color: status == 'ownerapproved' || status == 'active'
                              ? Colors.green[900]
                              : status == 'cancelled'
                              ? Colors.red[900]
                              : Colors.grey[900],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Renter-side actions: message owner (always available for renters)
            if (isRenter) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _messageOwner,
                  icon: const Icon(Icons.message_sharp),
                  label: const Text('Message Owner'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF00897B),
                    side: const BorderSide(
                      color: Color(0xFF00897B),
                      width: 1.5,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],

            // Return functionality buttons
            if ((isActive || isReturnInitiated) && !_isProcessing) ...[
              const SizedBox(height: 24),
              if (isActive && isRenter) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _initiateReturn,
                    icon: Icon(
                      _getReturnActionText().contains('Return')
                          ? Icons.assignment_return
                          : Icons.exit_to_app,
                    ),
                    label: Text(_getReturnActionText()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.orange[700],
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _getReturnInfoMessage(),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange[900],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (isReturnInitiated && isOwner) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _verifyReturn,
                    icon: const Icon(Icons.verified),
                    label: Text(_getVerifyButtonText()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.blue[700],
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Renter has initiated return. Please verify that you received the item in good condition.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue[900],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (isReturnInitiated && isRenter) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange[300]!),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.hourglass_empty,
                        color: Colors.orange[700],
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Return Initiated',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange[900],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Waiting for owner to verify the return',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.orange[800],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (isReturned) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green[300]!),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: Colors.green[700],
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Item Returned',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.green[900],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'The rental has been completed successfully',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.green[800],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _getReturnActionText() {
    if (_requestData == null) return 'Initiate Return';
    final rentType = (_requestData!['rentType'] as String? ?? 'item')
        .toLowerCase();
    switch (rentType) {
      case 'apartment':
        return 'End Rental';
      case 'boardinghouse':
      case 'boarding_house':
        return 'Move Out';
      case 'commercial':
        return 'End Lease';
      default:
        return 'Initiate Return';
    }
  }

  String _getReturnInfoMessage() {
    if (_requestData == null) {
      return 'Click to initiate return. The owner will verify once you return the item.';
    }
    final rentType = (_requestData!['rentType'] as String? ?? 'item')
        .toLowerCase();
    switch (rentType) {
      case 'apartment':
        return 'Click to end rental. The owner will verify that the apartment is in good condition.';
      case 'boardinghouse':
      case 'boarding_house':
        return 'Click to move out. The owner will verify that the room/space is in good condition.';
      case 'commercial':
        return 'Click to end lease. The owner will verify that the commercial space is in good condition.';
      default:
        return 'Click to initiate return. The owner will verify once you return the item.';
    }
  }

  String _getReturnDialogTitle() {
    if (_requestData == null) return 'Initiate Return?';
    final rentType = (_requestData!['rentType'] as String? ?? 'item')
        .toLowerCase();
    switch (rentType) {
      case 'apartment':
        return 'End Rental?';
      case 'boardinghouse':
      case 'boarding_house':
        return 'Move Out?';
      case 'commercial':
        return 'End Lease?';
      default:
        return 'Initiate Return?';
    }
  }

  String _getReturnDialogMessage() {
    if (_requestData == null) {
      return 'Are you sure you want to initiate the return? '
          'The owner will be notified to verify the return.';
    }
    final rentType = (_requestData!['rentType'] as String? ?? 'item')
        .toLowerCase();
    switch (rentType) {
      case 'apartment':
        return 'Are you sure you want to end this rental? The owner will be notified to verify that the apartment is in good condition.';
      case 'boardinghouse':
      case 'boarding_house':
        return 'Are you sure you want to move out? The owner will be notified to verify that the room/space is in good condition.';
      case 'commercial':
        return 'Are you sure you want to end this lease? The owner will be notified to verify that the commercial space is in good condition.';
      default:
        return 'Are you sure you want to initiate the return? '
            'The owner will be notified to verify the return.';
    }
  }

  String _getReturnSuccessMessage() {
    if (_requestData == null) {
      return 'Return initiated successfully! Owner will verify.';
    }
    final rentType = (_requestData!['rentType'] as String? ?? 'item')
        .toLowerCase();
    switch (rentType) {
      case 'apartment':
        return 'Rental ending initiated successfully! Owner will verify.';
      case 'boardinghouse':
      case 'boarding_house':
        return 'Move out initiated successfully! Owner will verify.';
      case 'commercial':
        return 'Lease termination initiated successfully! Owner will verify.';
      default:
        return 'Return initiated successfully! Owner will verify.';
    }
  }

  String _getVerifyButtonText() {
    if (_requestData == null) return 'Verify Return';
    final rentType = (_requestData!['rentType'] as String? ?? 'item')
        .toLowerCase();
    switch (rentType) {
      case 'apartment':
        return 'Verify Property';
      case 'boardinghouse':
      case 'boarding_house':
        return 'Verify Property';
      case 'commercial':
      case 'commercialspace':
      case 'commercial_space':
        return 'Verify Property';
      default:
        return 'Verify Return';
    }
  }

  Future<void> _initiateReturn() async {
    if (_requestData == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_getReturnDialogTitle()),
        content: Text(_getReturnDialogMessage()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: Text(_getReturnActionText()),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final reqProvider = Provider.of<RentalRequestProvider>(
        context,
        listen: false,
      );
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.user;

      if (currentUser == null) {
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

      final success = await reqProvider.initiateReturn(
        widget.requestId,
        currentUser.uid,
      );

      if (mounted) {
        setState(() {
          _isProcessing = false;
        });

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_getReturnSuccessMessage()),
              backgroundColor: Colors.orange,
            ),
          );
          // Reload request to show updated status
          _loadRequest();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                reqProvider.errorMessage ?? 'Failed to initiate return',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _messageOwner() async {
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

    final ownerId = _requestData!['ownerId'] as String;
    final ownerName = _requestData!['ownerName'] as String? ?? 'Owner';
    final itemId = _requestData!['itemId'] as String;
    final itemTitle = _requestData!['itemTitle'] as String? ?? 'Rental Item';

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
  }

  Future<void> _verifyReturn() async {
    if (_requestData == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${_getVerifyButtonText()}?'),
        content: Text(
          _requestData != null &&
                  [
                    'apartment',
                    'boardinghouse',
                    'boarding_house',
                    'commercial',
                    'commercialspace',
                    'commercial_space',
                  ].contains(
                    (_requestData!['rentType'] as String? ?? 'item')
                        .toLowerCase(),
                  )
              ? 'Have you verified that the property is in good condition? '
                    'This will complete the rental.'
              : 'Have you received the item in good condition? '
                    'This will complete the rental.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: Text(_getVerifyButtonText()),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final reqProvider = Provider.of<RentalRequestProvider>(
        context,
        listen: false,
      );
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.user;

      if (currentUser == null) {
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

      final success = await reqProvider.verifyReturn(
        widget.requestId,
        currentUser.uid,
      );

      if (mounted) {
        setState(() {
          _isProcessing = false;
        });

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Return verified! Rental completed.'),
              backgroundColor: Colors.green,
            ),
          );
          // Reload request to show updated status
          _loadRequest();
          // Prompt for rating after successful verification
          await _promptForRating(widget.requestId);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                reqProvider.errorMessage ?? 'Failed to verify return',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _promptForRating(String requestId) async {
    try {
      // Get rental request details
      final requestData = await _firestoreService.getRentalRequest(requestId);
      if (requestData == null) return;

      final request = RentalRequestModel.fromMap(requestData, requestId);

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.user;

      if (currentUser == null) return;

      // Determine who to rate based on current user
      final isOwner = currentUser.uid == request.ownerId;
      final ratedUserId = isOwner ? request.renterId : request.ownerId;
      final ratedUserName = isOwner ? 'Renter' : 'Owner';

      // Check if already rated
      final hasRated = await _ratingService.hasRated(
        raterUserId: currentUser.uid,
        ratedUserId: ratedUserId,
        transactionId: requestId,
      );

      if (hasRated) {
        // Already rated, skip prompt
        return;
      }

      // Get rated user's name if available
      String? ratedUserNameFull;
      try {
        final ratedUserData = await _firestoreService.getUser(ratedUserId);
        if (ratedUserData != null) {
          ratedUserNameFull =
              '${ratedUserData['firstName']} ${ratedUserData['lastName']}';
        }
      } catch (e) {
        // Silent fail, use default
      }

      // Show rating dialog
      if (!mounted) return;

      final shouldRate = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Rate Your Experience'),
          content: Text(
            'How was your rental experience with ${ratedUserNameFull ?? ratedUserName}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Maybe Later'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00897B),
              ),
              child: const Text('Rate Now'),
            ),
          ],
        ),
      );

      if (shouldRate == true && mounted) {
        // Navigate to rating screen
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SubmitRatingScreen(
              ratedUserId: ratedUserId,
              ratedUserName: ratedUserNameFull ?? ratedUserName,
              context: RatingContext.rental,
              transactionId: requestId,
              role: isOwner ? 'owner' : 'renter',
            ),
          ),
        );
      }
    } catch (e) {
      // Silent fail - don't interrupt user flow
      debugPrint('Error prompting for rating: $e');
    }
  }

  Widget _buildPaymentRow(
    String label,
    double? amount, {
    bool isTotal = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: isTotal ? 16 : 14,
                    fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
                    color: Colors.grey[800],
                  ),
                ),
              ],
            ),
          ),
          Text(
            _formatCurrency(amount),
            style: TextStyle(
              fontSize: isTotal ? 18 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
              color: isTotal ? const Color(0xFF00897B) : Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }
}
