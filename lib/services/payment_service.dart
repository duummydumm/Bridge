class PaymentInitResult {
  final String? redirectUrl; // Deep link or checkout URL for GCash
  final String? referenceId; // Gateway reference/token
  final bool requiresAction; // If user needs to complete flow in GCash app

  const PaymentInitResult({
    this.redirectUrl,
    this.referenceId,
    this.requiresAction = false,
  });
}

abstract class PaymentGateway {
  Future<PaymentInitResult> authorize({
    required double amount,
    String currency = 'PHP',
    String? description,
  });

  Future<bool> capture({required String referenceId, double? amount});

  Future<bool> refund({required String referenceId, double? amount});
}

// Stub implementation to integrate GCash through your chosen PSP (e.g., PayMongo)
class GCashPaymentService implements PaymentGateway {
  @override
  Future<PaymentInitResult> authorize({
    required double amount,
    String currency = 'PHP',
    String? description,
  }) async {
    // TODO: Call your backend or PSP SDK to create a GCash source/session.
    // Return a redirectUrl/referenceId for the client to continue the flow.
    return const PaymentInitResult(
      redirectUrl: null,
      referenceId: null,
      requiresAction: true,
    );
  }

  @override
  Future<bool> capture({required String referenceId, double? amount}) async {
    // TODO: Capture/charge the authorized GCash payment via PSP
    return true;
  }

  @override
  Future<bool> refund({required String referenceId, double? amount}) async {
    // TODO: Issue a refund via PSP
    return true;
  }
}
