import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/rental_request_provider.dart';

class ServiceFeePaymentScreen extends StatefulWidget {
  final String rentalRequestId;
  final double serviceFeeAmount;

  const ServiceFeePaymentScreen({
    super.key,
    required this.rentalRequestId,
    required this.serviceFeeAmount,
  });

  @override
  State<ServiceFeePaymentScreen> createState() =>
      _ServiceFeePaymentScreenState();
}

class _ServiceFeePaymentScreenState extends State<ServiceFeePaymentScreen> {
  bool _hasPaid = false;
  String _selectedPaymentMethod = 'gcash'; // 'gcash' or 'gotyme'

  // Platform QR code image URLs from Firebase Storage
  // TODO: Replace GCash URL with your actual GCash QR code URL
  static const String _platformGCashQRUrl =
      'https://via.placeholder.com/300x300?text=Platform+GCash+QR+Code';
  // GoTyme QR code URL - Update this if your file path is different
  static const String _platformGoTymeQRUrl =
      'https://firebasestorage.googleapis.com/v0/b/bridge-72b26.firebasestorage.app/o/platformqrCodes%2Fgotyme.jpg?alt=media&token=02de7ecb-47bd-4546-86d3-99304e210f87';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF00897B),
        elevation: 0,
        title: const Text(
          'Pay Service Fee',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Service Fee Info Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.account_balance_wallet,
                      size: 48,
                      color: Color(0xFF00897B),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Service Fee',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '₱${widget.serviceFeeAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF00A676),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        '5% of base rental price',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF1B5E20),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Instructions
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: Color(0xFF00897B),
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Payment Instructions',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildInstructionStep(
                      '1',
                      _selectedPaymentMethod == 'gcash'
                          ? 'Open your GCash app'
                          : 'Open your GoTyme app',
                    ),
                    const SizedBox(height: 12),
                    _buildInstructionStep('2', 'Tap "Scan QR"'),
                    const SizedBox(height: 12),
                    _buildInstructionStep(
                      '3',
                      _selectedPaymentMethod == 'gcash'
                          ? 'Scan the platform GCash QR code below'
                          : 'Scan the platform GoTyme QR code below',
                    ),
                    const SizedBox(height: 12),
                    _buildInstructionStep(
                      '4',
                      'Enter the exact amount: ₱${widget.serviceFeeAmount.toStringAsFixed(2)}',
                    ),
                    const SizedBox(height: 12),
                    _buildInstructionStep('5', 'Complete the payment'),
                    const SizedBox(height: 12),
                    _buildInstructionStep(
                      '6',
                      'Tap "Mark as Paid" below after payment',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Payment Method Selector
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Select Payment Method',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildPaymentMethodOption(
                            'gcash',
                            'GCash',
                            Icons.account_balance_wallet,
                            const Color(0xFF0066CC),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildPaymentMethodOption(
                            'gotyme',
                            'GoTyme',
                            Icons.qr_code_scanner,
                            const Color(0xFF00A676),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // QR Code Display
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      'Platform ${_selectedPaymentMethod == 'gcash' ? 'GCash' : 'GoTyme'} QR Code',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: 300,
                      height: 300,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!, width: 2),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          _selectedPaymentMethod == 'gcash'
                              ? _platformGCashQRUrl
                              : _platformGoTymeQRUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.qr_code_scanner,
                                  size: 64,
                                  color: Colors.grey,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'QR Code Image',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: Text(
                                    'Please configure your platform ${_selectedPaymentMethod == 'gcash' ? 'GCash' : 'GoTyme'} QR code in the code',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFFFFB74D),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Color(0xFFFF9800),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Pay the exact amount: ₱${widget.serviceFeeAmount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFFE65100),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Payment Breakdown
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Payment Breakdown',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildPaymentRow(
                      'Base Price',
                      'Pay to Owner',
                      'via GCash QR in chat',
                    ),
                    const Divider(height: 24),
                    _buildPaymentRow(
                      'Service Fee (5%)',
                      'Pay to Platform',
                      'via QR code above',
                      isHighlighted: true,
                    ),
                    if (widget.serviceFeeAmount > 0) ...[
                      const Divider(height: 24),
                      _buildPaymentRow(
                        'Security Deposit',
                        'Pay to Owner',
                        'held until return',
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Mark as Paid Button
              Consumer<RentalRequestProvider>(
                builder: (context, provider, child) {
                  return SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (_hasPaid || provider.isLoading)
                          ? null
                          : () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Confirm Payment'),
                                  content: Text(
                                    'Have you completed the payment of ₱${widget.serviceFeeAmount.toStringAsFixed(2)} to the platform GCash account?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('Cancel'),
                                    ),
                                    ElevatedButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF00897B,
                                        ),
                                      ),
                                      child: const Text('Yes, I Paid'),
                                    ),
                                  ],
                                ),
                              );

                              if (confirmed == true) {
                                final success = await provider
                                    .markServiceFeePaid(widget.rentalRequestId);

                                if (!mounted) return;

                                if (success) {
                                  setState(() {
                                    _hasPaid = true;
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Service fee marked as paid!',
                                      ),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                  // Wait a bit then pop
                                  Future.delayed(
                                    const Duration(seconds: 1),
                                    () {
                                      if (mounted) {
                                        Navigator.pop(context);
                                      }
                                    },
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        provider.errorMessage ??
                                            'Failed to mark as paid',
                                      ),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _hasPaid
                            ? Colors.grey
                            : const Color(0xFF26A69A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: provider.isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : _hasPaid
                          ? const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.check_circle, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Service Fee Paid',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            )
                          : const Text(
                              'Mark as Paid',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInstructionStep(String number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: const Color(0xFF00897B),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentRow(
    String label,
    String recipient,
    String method, {
    bool isHighlighted = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isHighlighted
                      ? const Color(0xFF00897B)
                      : Colors.grey[800],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                recipient,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 2),
              Text(
                method,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[500],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentMethodOption(
    String method,
    String label,
    IconData icon,
    Color color,
  ) {
    final isSelected = _selectedPaymentMethod == method;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedPaymentMethod = method;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? color : Colors.grey[600], size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? color : Colors.grey[700],
              ),
            ),
            if (isSelected) ...[
              const SizedBox(height: 4),
              Icon(Icons.check_circle, color: color, size: 16),
            ],
          ],
        ),
      ),
    );
  }
}
