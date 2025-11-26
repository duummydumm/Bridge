import 'package:cloud_firestore/cloud_firestore.dart';

enum ClaimRequestStatus { pending, approved, rejected, cancelled }

class GiveawayClaimRequestModel {
  final String id;
  final String giveawayId;
  final String claimantId;
  final String claimantName;
  final String donorId;
  final String? message; // Message from claimant
  final ClaimRequestStatus status;
  final String? rejectionReason;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? approvedAt;
  final DateTime? rejectedAt;

  GiveawayClaimRequestModel({
    required this.id,
    required this.giveawayId,
    required this.claimantId,
    required this.claimantName,
    required this.donorId,
    this.message,
    required this.status,
    this.rejectionReason,
    required this.createdAt,
    this.updatedAt,
    this.approvedAt,
    this.rejectedAt,
  });

  factory GiveawayClaimRequestModel.fromMap(
    Map<String, dynamic> data,
    String id,
  ) {
    // Parse status
    ClaimRequestStatus claimStatus = ClaimRequestStatus.pending;
    final statusString = (data['status'] ?? 'pending').toString().toLowerCase();
    switch (statusString) {
      case 'pending':
        claimStatus = ClaimRequestStatus.pending;
        break;
      case 'approved':
        claimStatus = ClaimRequestStatus.approved;
        break;
      case 'rejected':
        claimStatus = ClaimRequestStatus.rejected;
        break;
      case 'cancelled':
        claimStatus = ClaimRequestStatus.cancelled;
        break;
    }

    return GiveawayClaimRequestModel(
      id: id,
      giveawayId: data['giveawayId'] ?? '',
      claimantId: data['claimantId'] ?? '',
      claimantName: data['claimantName'] ?? '',
      donorId: data['donorId'] ?? '',
      message: data['message'],
      status: claimStatus,
      rejectionReason: data['rejectionReason'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      approvedAt: (data['approvedAt'] as Timestamp?)?.toDate(),
      rejectedAt: (data['rejectedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'giveawayId': giveawayId,
      'claimantId': claimantId,
      'claimantName': claimantName,
      'donorId': donorId,
      'message': message,
      'status': status.name,
      'rejectionReason': rejectionReason,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'approvedAt': approvedAt != null ? Timestamp.fromDate(approvedAt!) : null,
      'rejectedAt': rejectedAt != null ? Timestamp.fromDate(rejectedAt!) : null,
    };
  }

  String get statusDisplay {
    switch (status) {
      case ClaimRequestStatus.pending:
        return 'Pending';
      case ClaimRequestStatus.approved:
        return 'Approved';
      case ClaimRequestStatus.rejected:
        return 'Rejected';
      case ClaimRequestStatus.cancelled:
        return 'Cancelled';
    }
  }

  bool get isPending => status == ClaimRequestStatus.pending;
  bool get isApproved => status == ClaimRequestStatus.approved;
  bool get isRejected => status == ClaimRequestStatus.rejected;
  bool get isCancelled => status == ClaimRequestStatus.cancelled;
}
