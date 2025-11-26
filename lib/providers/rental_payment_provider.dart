import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../models/rental_payment_model.dart';

class RentalPaymentsProvider extends ChangeNotifier {
  final FirestoreService _firestore = FirestoreService();

  bool _isLoading = false;
  String? _errorMessage;
  List<RentalPaymentModel> _payments = [];

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<RentalPaymentModel> get payments => _payments;

  Future<void> loadPaymentsForRequest(String rentalRequestId) async {
    try {
      _setLoading(true);
      _clearError();
      final data = await _firestore.getPaymentsForRequest(rentalRequestId);
      _payments = data
          .map((m) => RentalPaymentModel.fromMap(m, m['id'] as String))
          .toList();
      _setLoading(false);
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
    }
  }

  // Phase 1: GCash (record result manually or via future webhook)
  Future<String?> recordManualPayment({
    required String rentalRequestId,
    required double amount,
    String currency = 'PHP',
    RentalPaymentType type = RentalPaymentType.capture,
    RentalPaymentStatus status = RentalPaymentStatus.succeeded,
    String? noteRef,
  }) async {
    try {
      _setLoading(true);
      _clearError();
      final payload = {
        'rentalRequestId': rentalRequestId,
        'method': RentalPaymentMethod.manual.name,
        'provider': RentalPaymentProviderEnum.none.name,
        'type': type.name,
        'status': status.name,
        'amount': amount,
        'currency': currency,
        'providerRef': noteRef,
        'createdAt': DateTime.now(),
      };
      final id = await _firestore.createRentalPayment(payload);
      _setLoading(false);
      notifyListeners();
      return id;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
      return null;
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
