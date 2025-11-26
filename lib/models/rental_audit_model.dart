import 'package:cloud_firestore/cloud_firestore.dart';

enum RentalAuditAction {
  statusChange,
  dateChange,
  priceAdjust,
  disputeOpen,
  disputeResolve,
}

class RentalAuditModel {
  final String id;
  final String rentalRequestId;
  final String actorId;
  final RentalAuditAction action;
  final String? oldValue;
  final String? newValue;
  final String? note;
  final DateTime createdAt;

  RentalAuditModel({
    required this.id,
    required this.rentalRequestId,
    required this.actorId,
    required this.action,
    this.oldValue,
    this.newValue,
    this.note,
    required this.createdAt,
  });

  factory RentalAuditModel.fromMap(Map<String, dynamic> data, String id) {
    RentalAuditAction parseAction(String? s) {
      final val = (s ?? '').toLowerCase();
      for (final a in RentalAuditAction.values) {
        if (a.name.toLowerCase() == val) return a;
      }
      return RentalAuditAction.statusChange;
    }

    return RentalAuditModel(
      id: id,
      rentalRequestId: data['rentalRequestId'] ?? '',
      actorId: data['actorId'] ?? '',
      action: parseAction(data['action']?.toString()),
      oldValue: data['oldValue']?.toString(),
      newValue: data['newValue']?.toString(),
      note: data['note']?.toString(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'rentalRequestId': rentalRequestId,
      'actorId': actorId,
      'action': action.name,
      'oldValue': oldValue,
      'newValue': newValue,
      'note': note,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
