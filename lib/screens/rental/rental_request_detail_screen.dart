import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/rental_request_provider.dart';
import '../../services/firestore_service.dart';
import '../../models/rental_request_model.dart';
import '../chat_detail_screen.dart';
import '../service_fee_payment_screen.dart';

class RentalRequestDetailScreen extends StatefulWidget {
  final String requestId;

  const RentalRequestDetailScreen({super.key, required this.requestId});

  @override
  State<RentalRequestDetailScreen> createState() =>
      _RentalRequestDetailScreenState();
}

class _RentalRequestDetailScreenState extends State<RentalRequestDetailScreen> {
  final FirestoreService _firestoreService = FirestoreService();
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
      if (mounted) {
        setState(() {
          _requestData = data;
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
        content: const Text(
          'Have you received the payment (base price + deposit) from the renter via GCash?',
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
    final notes = _requestData!['notes'] as String? ?? '';
    final createdAt = _requestData!['createdAt'];
    final startDate = _requestData!['startDate'];
    final endDate = _requestData!['endDate'];
    final durationDays = _requestData!['durationDays'] as int? ?? 0;
    final priceQuote = (_requestData!['priceQuote'] as num?)?.toDouble() ?? 0.0;
    final fees = (_requestData!['fees'] as num?)?.toDouble() ?? 0.0;
    final depositAmount = (_requestData!['depositAmount'] as num?)?.toDouble();
    final totalDue = (_requestData!['totalDue'] as num?)?.toDouble() ?? 0.0;
    final paymentStatus = _requestData!['paymentStatus'] as String? ?? 'unpaid';
    final serviceFeePaid = _requestData!['serviceFeePaid'] as bool? ?? false;
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: status == 'requested'
                  ? Colors.orange
                  : status == 'ownerapproved' || status == 'active'
                  ? Colors.green
                  : status == 'cancelled'
                  ? Colors.red
                  : Colors.grey,
              borderRadius: BorderRadius.circular(12),
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
          const SizedBox(height: 24),

          // Renter info
          const Text(
            'Renter',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.person, color: Color(0xFF00897B)),
              const SizedBox(width: 8),
              Text(renterName, style: const TextStyle(fontSize: 16)),
            ],
          ),
          const SizedBox(height: 24),

          // Item info
          const Text(
            'Item',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.inventory_2, color: Color(0xFF00897B)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(itemTitle, style: const TextStyle(fontSize: 16)),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Rental Period
          const Text(
            'Rental Period',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.calendar_today, color: Color(0xFF00897B)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Start: ${_formatDate(startDate)}',
                      style: const TextStyle(fontSize: 14),
                    ),
                    Text(
                      endDate == null
                          ? 'End: Month-to-month (Ongoing)'
                          : 'End: ${_formatDate(endDate)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontStyle: endDate == null
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                    ),
                    if (durationDays > 0)
                      Text(
                        'Duration: $durationDays day${durationDays != 1 ? 's' : ''}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF00897B),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Payment Breakdown
          const Text(
            'Payment Breakdown',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                _buildPaymentRow('Base Price', priceQuote),
                _buildPaymentRow('Service Fee (5%)', fees, isServiceFee: true),
                if (depositAmount != null && depositAmount > 0)
                  _buildPaymentRow('Security Deposit', depositAmount),
                const Divider(height: 16),
                _buildPaymentRow('Total Due', totalDue, isTotal: true),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Payment Status Section (for owners when approved)
          if (isOwner && isOwnerApproved) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: paymentStatus == 'captured'
                    ? Colors.green[50]
                    : Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: paymentStatus == 'captured'
                      ? Colors.green[300]!
                      : Colors.orange[300]!,
                  width: 1,
                ),
              ),
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
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        paymentStatus == 'captured'
                            ? 'Payment Received'
                            : 'Waiting for Payment',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: paymentStatus == 'captured'
                              ? Colors.green[900]
                              : Colors.orange[900],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    paymentStatus == 'captured'
                        ? 'Base price and deposit have been received.'
                        : 'Waiting for renter to pay base price (₱${priceQuote.toStringAsFixed(2)})${depositAmount != null && depositAmount > 0 ? ' + deposit (₱${depositAmount.toStringAsFixed(2)})' : ''} via GCash.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
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
                        label: const Text('Mark Payment Received'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00897B),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Service Fee Status (visible to both owners and renters)
          if (isOwnerApproved || isActive) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: serviceFeePaid ? Colors.green[50] : Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: serviceFeePaid
                      ? Colors.green[300]!
                      : Colors.orange[300]!,
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        serviceFeePaid ? Icons.check_circle : Icons.pending,
                        color: serviceFeePaid
                            ? Colors.green[700]
                            : Colors.orange[700],
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          serviceFeePaid
                              ? 'Service Fee Paid'
                              : 'Service Fee Pending (₱${fees.toStringAsFixed(2)})',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: serviceFeePaid
                                ? Colors.green[900]
                                : Colors.orange[900],
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Show Pay Service Fee button for renters when fee is not paid and request is approved/active
                  if (!serviceFeePaid &&
                      isRenter &&
                      (isOwnerApproved || isActive) &&
                      fees > 0) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isProcessing
                            ? null
                            : () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        ServiceFeePaymentScreen(
                                          rentalRequestId: widget.requestId,
                                          serviceFeeAmount: fees,
                                        ),
                                  ),
                                ).then((_) {
                                  // Reload request to show updated status
                                  _loadRequest();
                                });
                              },
                        icon: const Icon(Icons.payment, size: 18),
                        label: const Text('Pay Service Fee'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF9800),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Notes
          if (notes.isNotEmpty) ...[
            const Text(
              'Notes',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(notes, style: const TextStyle(fontSize: 14)),
            ),
            const SizedBox(height: 24),
          ],

          // Request date
          if (createdAt != null) ...[
            const Text(
              'Request Date',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _formatDate(createdAt),
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 24),
          ],

          // Action buttons
          if (isOwnerApproved &&
              isOwner &&
              paymentStatus != 'captured' &&
              !_isProcessing) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[200]!),
              ),
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
                          fontWeight: FontWeight.w600,
                          color: Colors.blue[900],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Share your GCash QR code in the chat. Once the renter pays, mark the payment as received.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (isPending && !_isProcessing) ...[
            const SizedBox(height: 16),
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
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ] else ...[
            const SizedBox(height: 16),
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

          // Return functionality buttons
          if ((isActive || isReturnInitiated) && !_isProcessing) ...[
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            if (isActive && isRenter) ...[
              // Renter can initiate return
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _initiateReturn,
                  icon: const Icon(Icons.assignment_return),
                  label: const Text('Initiate Return'),
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
                        'Click to initiate return. The owner will verify once you return the item.',
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
              // Owner can verify return
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _verifyReturn,
                  icon: const Icon(Icons.verified),
                  label: const Text('Verify Return'),
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
                    Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Renter has initiated return. Please verify that you received the item in good condition.',
                        style: TextStyle(fontSize: 12, color: Colors.blue[900]),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (isReturnInitiated && isRenter) ...[
              // Renter waiting for owner verification
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
              // Item has been returned
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
    );
  }

  Future<void> _initiateReturn() async {
    if (_requestData == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Initiate Return?'),
        content: const Text(
          'Are you sure you want to initiate the return? '
          'The owner will be notified to verify the return.',
        ),
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
            child: const Text('Initiate Return'),
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
            const SnackBar(
              content: Text(
                'Return initiated successfully! Owner will verify.',
              ),
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

  Future<void> _verifyReturn() async {
    if (_requestData == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Verify Return?'),
        content: const Text(
          'Have you received the item in good condition? '
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
            child: const Text('Verify Return'),
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

  Widget _buildPaymentRow(
    String label,
    double? amount, {
    bool isServiceFee = false,
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
                if (isServiceFee)
                  Text(
                    'Pay separately to platform',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
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
