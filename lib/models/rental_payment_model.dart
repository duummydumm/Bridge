import 'package:cloud_firestore/cloud_firestore.dart';

enum RentalPaymentMethod { manual, wallet, externalProvider }

enum RentalPaymentProviderEnum {
  none,
  gcash,
  stripe,
  paystack,
  flutterwave,
  paypal,
  custom,
}

enum RentalPaymentType { authorization, capture, refund, adjustment }

enum RentalPaymentStatus { pending, succeeded, failed }

class RentalPaymentModel {
  final String id;
  final String rentalRequestId;
  final RentalPaymentMethod method;
  final RentalPaymentProviderEnum provider;
  final RentalPaymentType type;
  final RentalPaymentStatus status;
  final double amount;
  final String currency;
  final String? providerRef;
  final DateTime createdAt;

  RentalPaymentModel({
    required this.id,
    required this.rentalRequestId,
    required this.method,
    required this.provider,
    required this.type,
    required this.status,
    required this.amount,
    required this.currency,
    this.providerRef,
    required this.createdAt,
  });

  factory RentalPaymentModel.fromMap(Map<String, dynamic> data, String id) {
    T parseEnum<T>(String? s, List<T> values, T fallback) {
      final val = (s ?? '').toLowerCase();
      for (final v in values) {
        if (v.toString().split('.').last.toLowerCase() == val) return v;
      }
      return fallback;
    }

    return RentalPaymentModel(
      id: id,
      rentalRequestId: data['rentalRequestId'] ?? '',
      method: parseEnum<RentalPaymentMethod>(
        data['method']?.toString(),
        RentalPaymentMethod.values,
        RentalPaymentMethod.manual,
      ),
      provider: parseEnum<RentalPaymentProviderEnum>(
        data['provider']?.toString(),
        RentalPaymentProviderEnum.values,
        RentalPaymentProviderEnum.none,
      ),
      type: parseEnum<RentalPaymentType>(
        data['type']?.toString(),
        RentalPaymentType.values,
        RentalPaymentType.capture,
      ),
      status: parseEnum<RentalPaymentStatus>(
        data['status']?.toString(),
        RentalPaymentStatus.values,
        RentalPaymentStatus.pending,
      ),
      amount: (data['amount'] is num)
          ? (data['amount'] as num).toDouble()
          : 0.0,
      currency: data['currency'] ?? 'PHP',
      providerRef: data['providerRef'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'rentalRequestId': rentalRequestId,
      'method': method.name,
      'provider': provider.name,
      'type': type.name,
      'status': status.name,
      'amount': amount,
      'currency': currency,
      'providerRef': providerRef,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
