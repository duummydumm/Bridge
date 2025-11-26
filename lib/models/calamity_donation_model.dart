import 'package:cloud_firestore/cloud_firestore.dart';

enum CalamityDonationStatus { pending, received }

class CalamityDonationModel {
  final String donationId;
  final String eventId;
  final String donorEmail;
  final String itemType;
  final int quantity;
  final String? notes;
  final CalamityDonationStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;

  CalamityDonationModel({
    required this.donationId,
    required this.eventId,
    required this.donorEmail,
    required this.itemType,
    required this.quantity,
    this.notes,
    required this.status,
    required this.createdAt,
    this.updatedAt,
  });

  factory CalamityDonationModel.fromMap(Map<String, dynamic> data, String id) {
    // Parse status
    CalamityDonationStatus donationStatus = CalamityDonationStatus.pending;
    final statusString = (data['status'] ?? 'pending').toString().toLowerCase();
    switch (statusString) {
      case 'pending':
        donationStatus = CalamityDonationStatus.pending;
        break;
      case 'received':
        donationStatus = CalamityDonationStatus.received;
        break;
    }

    return CalamityDonationModel(
      donationId: id,
      eventId: data['eventId'] ?? '',
      donorEmail: data['donorEmail'] ?? '',
      itemType: data['itemType'] ?? '',
      quantity: (data['quantity'] ?? 0) is int
          ? (data['quantity'] ?? 0)
          : int.tryParse('${data['quantity']}') ?? 0,
      notes: data['notes'],
      status: donationStatus,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'eventId': eventId,
      'donorEmail': donorEmail,
      'itemType': itemType,
      'quantity': quantity,
      'notes': notes,
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    };
  }

  String get statusDisplay {
    switch (status) {
      case CalamityDonationStatus.pending:
        return 'Pending';
      case CalamityDonationStatus.received:
        return 'Received';
    }
  }

  bool get isPending => status == CalamityDonationStatus.pending;
  bool get isReceived => status == CalamityDonationStatus.received;
}
