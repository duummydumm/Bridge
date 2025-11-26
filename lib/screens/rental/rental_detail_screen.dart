import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/rental_request_provider.dart';
import '../../providers/rental_payment_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/rental_request_model.dart';
import '../../models/rating_model.dart';
import '../../services/firestore_service.dart';
import '../../services/rating_service.dart';
import '../submit_rating_screen.dart';

class RentalDetailScreen extends StatefulWidget {
  const RentalDetailScreen({super.key});

  @override
  State<RentalDetailScreen> createState() => _RentalDetailScreenState();
}

class _RentalDetailScreenState extends State<RentalDetailScreen> {
  final _requestIdCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final FirestoreService _firestoreService = FirestoreService();
  final RatingService _ratingService = RatingService();

  @override
  void dispose() {
    _requestIdCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reqProvider = context.watch<RentalRequestProvider>();
    final payProvider = context.watch<RentalPaymentsProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Rental Detail')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            TextField(
              controller: _requestIdCtrl,
              decoration: const InputDecoration(labelText: 'Rental Request ID'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: reqProvider.isLoading
                      ? null
                      : () async {
                          final ok = await reqProvider.setStatus(
                            _requestIdCtrl.text.trim(),
                            RentalRequestStatus.ownerApproved,
                          );
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(ok ? 'Approved' : 'Failed')),
                          );
                        },
                  child: const Text('Approve'),
                ),
                ElevatedButton(
                  onPressed: reqProvider.isLoading
                      ? null
                      : () async {
                          final ok = await reqProvider.setStatus(
                            _requestIdCtrl.text.trim(),
                            RentalRequestStatus.active,
                          );
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(ok ? 'Activated' : 'Failed'),
                            ),
                          );
                        },
                  child: const Text('Mark Active'),
                ),
                // Return verification buttons
                ElevatedButton(
                  onPressed: reqProvider.isLoading
                      ? null
                      : () async {
                          final requestId = _requestIdCtrl.text.trim();
                          final authProvider = Provider.of<AuthProvider>(
                            context,
                            listen: false,
                          );
                          final currentUser = authProvider.user;
                          if (currentUser == null) return;

                          // Get request to check if user is renter or owner
                          final requestData = await _firestoreService
                              .getRentalRequest(requestId);
                          if (requestData == null) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Request not found'),
                              ),
                            );
                            return;
                          }

                          final request = RentalRequestModel.fromMap(
                            requestData,
                            requestId,
                          );
                          final isRenter = currentUser.uid == request.renterId;
                          final isOwner = currentUser.uid == request.ownerId;

                          bool ok = false;
                          if (isRenter &&
                              request.status == RentalRequestStatus.active) {
                            // Renter initiates return
                            ok = await reqProvider.initiateReturn(
                              requestId,
                              currentUser.uid,
                            );
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  ok
                                      ? 'Return initiated. Waiting for owner verification.'
                                      : 'Failed to initiate return',
                                ),
                                backgroundColor: ok
                                    ? Colors.orange
                                    : Colors.red,
                              ),
                            );
                          } else if (isOwner &&
                              request.status ==
                                  RentalRequestStatus.returnInitiated) {
                            // Owner verifies return
                            ok = await reqProvider.verifyReturn(
                              requestId,
                              currentUser.uid,
                            );
                            if (!mounted) return;
                            if (ok) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Return verified successfully!',
                                  ),
                                  backgroundColor: Colors.green,
                                ),
                              );
                              // Prompt for rating after successful return
                              await _promptForRating(requestId);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Failed to verify return'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          } else {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  isRenter
                                      ? 'Return already initiated or rental not active'
                                      : isOwner
                                      ? 'Return not initiated by renter yet'
                                      : 'You are not authorized',
                                ),
                                backgroundColor: Colors.orange,
                              ),
                            );
                          }
                        },
                  child: const Text('Initiate/Verify Return'),
                ),
              ],
            ),
            const Divider(height: 32),
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Payment Amount (manual)',
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: payProvider.isLoading
                  ? null
                  : () async {
                      final id = await payProvider.recordManualPayment(
                        rentalRequestId: _requestIdCtrl.text.trim(),
                        amount: double.tryParse(_amountCtrl.text.trim()) ?? 0,
                      );
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            id != null ? 'Payment saved' : 'Payment failed',
                          ),
                        ),
                      );
                    },
              child: const Text('Record Manual Payment'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: reqProvider.isLoading
                  ? null
                  : () async {
                      final ok = await reqProvider.setPaymentStatus(
                        _requestIdCtrl.text.trim(),
                        PaymentStatus.captured,
                      );
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ok ? 'Payment marked captured' : 'Failed',
                          ),
                        ),
                      );
                    },
              child: const Text('Mark Payment Captured'),
            ),
          ],
        ),
      ),
    );
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
}
