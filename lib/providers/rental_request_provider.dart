import 'package:flutter/material.dart';
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
  Future<bool> markPaymentReceived(String requestId) async {
    try {
      _setLoading(true);
      _clearError();

      // Get current request to check if we should auto-transition to active
      final currentRequest = await _firestore.getRentalRequest(requestId);
      final status = currentRequest?['status'] as String?;

      await _firestore.updateRentalRequest(requestId, {
        'paymentStatus': PaymentStatus.captured.name,
        'updatedAt': DateTime.now(),
      });

      // Auto-transition to active when payment is received
      if ((status?.toLowerCase() ?? '') == 'ownerapproved') {
        await _firestore.updateRentalRequest(requestId, {
          'status': RentalRequestStatus.active.name.toLowerCase(),
          'updatedAt': DateTime.now(),
        });
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
