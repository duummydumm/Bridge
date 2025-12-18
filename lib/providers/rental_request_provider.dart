import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';
import '../models/rental_request_model.dart';

class RentalRequestProvider extends ChangeNotifier {
  final FirestoreService _firestore = FirestoreService();

  List<RentalRequestModel> _asOwner = [];
  List<RentalRequestModel> _asRenter = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<RentalRequestModel> get requestsAsOwner => _asOwner;
  List<RentalRequestModel> get requestsAsRenter => _asRenter;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadRequestsForOwner(String ownerId) async {
    try {
      _setLoading(true);
      _clearError();
      final data = await _firestore.getRentalRequestsByUser(
        ownerId,
        asOwner: true,
      );
      _asOwner = data
          .map((m) => RentalRequestModel.fromMap(m, m['id'] as String))
          .toList();
      _setLoading(false);
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<void> loadRequestsForRenter(String renterId) async {
    try {
      _setLoading(true);
      _clearError();
      final data = await _firestore.getRentalRequestsByUser(
        renterId,
        asOwner: false,
      );
      _asRenter = data
          .map((m) => RentalRequestModel.fromMap(m, m['id'] as String))
          .toList();
      _setLoading(false);
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<String?> createRequest({
    required String listingId,
    required String itemId,
    required String ownerId,
    required String renterId,
    required DateTime startDate,
    DateTime? endDate, // Optional for long-term rentals
    int? durationDays, // Optional for long-term rentals
    required double priceQuote,
    required double fees,
    required double totalDue,
    double? depositAmount,
    String? notes,
    // Long-term rental parameters
    bool isLongTerm = false,
    double? monthlyPaymentAmount,
    DateTime? nextPaymentDueDate,
    // Payment method
    PaymentMethod paymentMethod = PaymentMethod.meetup,
  }) async {
    try {
      _setLoading(true);
      _clearError();
      final payload = {
        'listingId': listingId,
        'itemId': itemId,
        'ownerId': ownerId,
        'renterId': renterId,
        'startDate': startDate,
        'endDate': endDate,
        'durationDays': durationDays,
        'priceQuote': priceQuote,
        'fees': fees,
        'totalDue': totalDue,
        'depositAmount': depositAmount,
        'status': RentalRequestStatus.requested.name.toLowerCase(),
        'paymentStatus': PaymentStatus.unpaid.name,
        'returnDueDate':
            endDate ??
            startDate.add(
              const Duration(days: 365),
            ), // Default to 1 year if no end date
        'notes': notes,
        // Long-term rental fields
        'isLongTerm': isLongTerm,
        'monthlyPaymentAmount': monthlyPaymentAmount,
        'nextPaymentDueDate': nextPaymentDueDate,
        // Payment method
        'paymentMethod': paymentMethod.name,
        'createdAt': DateTime.now(),
        'updatedAt': DateTime.now(),
      };
      final id = await _firestore.createRentalRequest(payload);
      _setLoading(false);
      notifyListeners();
      return id;
    } catch (e) {
      // Extract clean error message (remove "Exception: " prefix if present)
      String errorMsg = e.toString();
      if (errorMsg.startsWith('Exception: ')) {
        errorMsg = errorMsg.substring(11);
      }
      _setError(errorMsg);
      _setLoading(false);
      notifyListeners();
      return null;
    }
  }

  Future<bool> setStatus(String requestId, RentalRequestStatus status) async {
    try {
      _setLoading(true);
      _clearError();
      await _firestore.updateRentalRequest(requestId, {
        'status': status.name.toLowerCase(),
        'updatedAt': DateTime.now(),
      });
      _setLoading(false);
      notifyListeners();
      return true;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
      return false;
    }
  }

  Future<bool> setPaymentStatus(
    String requestId,
    PaymentStatus paymentStatus,
  ) async {
    try {
      _setLoading(true);
      _clearError();
      await _firestore.updateRentalRequest(requestId, {
        'paymentStatus': paymentStatus.name,
        'updatedAt': DateTime.now(),
      });
      _setLoading(false);
      notifyListeners();
      return true;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
      return false;
    }
  }

  /// Mark payment as received by owner (base price + deposit)
  /// For long-term rentals, also creates a payment record for monthly tracking
  Future<bool> markPaymentReceived(String requestId) async {
    try {
      _setLoading(true);
      _clearError();

      // Get current request to check if we should auto-transition to active
      final currentRequest = await _firestore.getRentalRequest(requestId);
      final status = currentRequest?['status'] as String?;
      final isLongTerm = currentRequest?['isLongTerm'] as bool? ?? false;
      final isActive = (status?.toLowerCase() ?? '') == 'active';

      await _firestore.updateRentalRequest(requestId, {
        'paymentStatus': PaymentStatus.captured.name,
        'updatedAt': DateTime.now(),
      });

      // Auto-transition to active when payment is received
      bool justBecameActive = false;
      if ((status?.toLowerCase() ?? '') == 'ownerapproved') {
        await _firestore.updateRentalRequest(requestId, {
          'status': RentalRequestStatus.active.name.toLowerCase(),
          'updatedAt': DateTime.now(),
        });
        justBecameActive = true;
      }

      // For long-term rentals (active or just became active), create a payment record
      // This ensures the monthly payment tracker shows the month as paid
      if (isLongTerm && (isActive || justBecameActive)) {
        try {
          final monthlyAmount =
              (currentRequest?['monthlyPaymentAmount'] as num?)?.toDouble();
          if (monthlyAmount != null && monthlyAmount > 0) {
            // Check if payment for current month already exists
            final payments = await _firestore.getPaymentsForRequest(requestId);
            final now = DateTime.now();
            final currentMonthKey = '${now.year}-${now.month}';

            bool paymentExists = false;
            for (final payment in payments) {
              final paymentDate =
                  (payment['createdAt'] as Timestamp?)?.toDate() ??
                  DateTime(1970);
              final paymentMonthKey =
                  '${paymentDate.year}-${paymentDate.month}';
              if (paymentMonthKey == currentMonthKey &&
                  (payment['status'] as String? ?? '').toLowerCase() ==
                      'succeeded') {
                paymentExists = true;
                break;
              }
            }

            // Only create payment record if one doesn't exist for current month
            if (!paymentExists) {
              await _firestore.recordMonthlyRentalPayment(
                rentalRequestId: requestId,
                amount: monthlyAmount,
                paymentDate: DateTime.now(),
              );
            }
          }
        } catch (e) {
          // Don't fail the entire operation if payment record creation fails
          // Log error but continue
          debugPrint(
            'Error creating payment record when marking payment received: $e',
          );
        }
      }

      _setLoading(false);
      notifyListeners();
      return true;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
      return false;
    }
  }

  /// Renter initiates return
  Future<bool> initiateReturn(
    String requestId,
    String renterId, {
    String? condition,
    String? conditionNotes,
    List<String>? conditionPhotos,
  }) async {
    try {
      _setLoading(true);
      _clearError();
      await _firestore.initiateRentalReturn(
        requestId: requestId,
        renterId: renterId,
        condition: condition,
        conditionNotes: conditionNotes,
        conditionPhotos: conditionPhotos,
      );
      _setLoading(false);
      notifyListeners();
      return true;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
      return false;
    }
  }

  /// Owner verifies return
  Future<bool> verifyReturn(
    String requestId,
    String ownerId, {
    bool conditionAccepted = true,
    String? ownerConditionNotes,
    List<String>? ownerConditionPhotos,
    Map<String, dynamic>? damageReport,
  }) async {
    try {
      _setLoading(true);
      _clearError();
      await _firestore.verifyRentalReturn(
        requestId: requestId,
        ownerId: ownerId,
        conditionAccepted: conditionAccepted,
        ownerConditionNotes: ownerConditionNotes,
        ownerConditionPhotos: ownerConditionPhotos,
        damageReport: damageReport,
      );
      _setLoading(false);
      notifyListeners();
      return true;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
      return false;
    }
  }

  /// Owner force-terminates a rental (e.g., non-payment or violation)
  Future<bool> ownerTerminateRental(
    String requestId,
    String ownerId, {
    String? reason,
  }) async {
    try {
      _setLoading(true);
      _clearError();
      await _firestore.ownerTerminateRental(
        requestId: requestId,
        ownerId: ownerId,
        reason: reason,
      );
      _setLoading(false);
      notifyListeners();
      return true;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
      return false;
    }
  }

  void _setLoading(bool v) {
    _isLoading = v;
  }

  void _setError(String msg) {
    _errorMessage = msg;
  }

  void _clearError() {
    _errorMessage = null;
  }
}
