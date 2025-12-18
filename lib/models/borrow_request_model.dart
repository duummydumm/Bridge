import 'package:cloud_firestore/cloud_firestore.dart';

enum BorrowRequestStatus {
  pending,
  accepted,
  declined,
  cancelled,
  returnInitiated,
  returned,
  returnDisputed,
}

class BorrowRequestModel {
  final String id;
  final String itemId;
  final String itemTitle;
  final String lenderId;
  final String lenderName;
  final String borrowerId;
  final String borrowerName;
  final String? message;
  final BorrowRequestStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;

  // Return-related fields
  final DateTime? agreedReturnDate;
  final String? returnInitiatedBy;
  final DateTime? returnInitiatedAt;
  final String? borrowerCondition; // 'same', 'better', 'worse', 'damaged'
  final String? borrowerConditionNotes;
  final List<String>? borrowerConditionPhotos;
  final String? returnConfirmedBy;
  final DateTime? returnConfirmedAt;
  final DateTime? actualReturnDate;
  final String? lenderConditionDecision; // 'accepted', 'disputed'
  final String? lenderConditionNotes;
  final List<String>? lenderConditionPhotos;
  final Map<String, dynamic>? damageReport;

  // Dispute resolution
  final Map<String, dynamic>? disputeResolution;

  // Missing item reporting
  final bool? missingItemReported;
  final DateTime? missingItemReportedAt;
  final String? missingItemReportId;

  BorrowRequestModel({
    required this.id,
    required this.itemId,
    required this.itemTitle,
    required this.lenderId,
    required this.lenderName,
    required this.borrowerId,
    required this.borrowerName,
    this.message,
    required this.status,
    required this.createdAt,
    this.updatedAt,
    this.agreedReturnDate,
    this.returnInitiatedBy,
    this.returnInitiatedAt,
    this.borrowerCondition,
    this.borrowerConditionNotes,
    this.borrowerConditionPhotos,
    this.returnConfirmedBy,
    this.returnConfirmedAt,
    this.actualReturnDate,
    this.lenderConditionDecision,
    this.lenderConditionNotes,
    this.lenderConditionPhotos,
    this.damageReport,
    this.disputeResolution,
    this.missingItemReported,
    this.missingItemReportedAt,
    this.missingItemReportId,
  });

  factory BorrowRequestModel.fromMap(Map<String, dynamic> data, String id) {
    // Parse status
    BorrowRequestStatus requestStatus = BorrowRequestStatus.pending;
    final statusString = (data['status'] ?? 'pending').toString().toLowerCase();
    switch (statusString) {
      case 'pending':
        requestStatus = BorrowRequestStatus.pending;
        break;
      case 'accepted':
        requestStatus = BorrowRequestStatus.accepted;
        break;
      case 'declined':
        requestStatus = BorrowRequestStatus.declined;
        break;
      case 'cancelled':
        requestStatus = BorrowRequestStatus.cancelled;
        break;
      case 'return_initiated':
        requestStatus = BorrowRequestStatus.returnInitiated;
        break;
      case 'returned':
        requestStatus = BorrowRequestStatus.returned;
        break;
      case 'return_disputed':
        requestStatus = BorrowRequestStatus.returnDisputed;
        break;
    }

    return BorrowRequestModel(
      id: id,
      itemId: data['itemId'] ?? '',
      itemTitle: data['itemTitle'] ?? '',
      lenderId: data['lenderId'] ?? '',
      lenderName: data['lenderName'] ?? '',
      borrowerId: data['borrowerId'] ?? '',
      borrowerName: data['borrowerName'] ?? '',
      message: data['message'],
      status: requestStatus,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      agreedReturnDate: (data['agreedReturnDate'] as Timestamp?)?.toDate(),
      returnInitiatedBy: data['returnInitiatedBy'],
      returnInitiatedAt: (data['returnInitiatedAt'] as Timestamp?)?.toDate(),
      borrowerCondition: data['borrowerCondition'],
      borrowerConditionNotes: data['borrowerConditionNotes'],
      borrowerConditionPhotos: data['borrowerConditionPhotos'] != null
          ? List<String>.from(data['borrowerConditionPhotos'])
          : null,
      returnConfirmedBy: data['returnConfirmedBy'],
      returnConfirmedAt: (data['returnConfirmedAt'] as Timestamp?)?.toDate(),
      actualReturnDate: (data['actualReturnDate'] as Timestamp?)?.toDate(),
      lenderConditionDecision: data['lenderConditionDecision'],
      lenderConditionNotes: data['lenderConditionNotes'],
      lenderConditionPhotos: data['lenderConditionPhotos'] != null
          ? List<String>.from(data['lenderConditionPhotos'])
          : null,
      damageReport: data['damageReport'] != null
          ? Map<String, dynamic>.from(data['damageReport'])
          : null,
      disputeResolution: data['disputeResolution'] != null
          ? Map<String, dynamic>.from(data['disputeResolution'])
          : null,
      missingItemReported: data['missingItemReported'] as bool?,
      missingItemReportedAt: (data['missingItemReportedAt'] as Timestamp?)
          ?.toDate(),
      missingItemReportId: data['missingItemReportId'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'itemId': itemId,
      'itemTitle': itemTitle,
      'lenderId': lenderId,
      'lenderName': lenderName,
      'borrowerId': borrowerId,
      'borrowerName': borrowerName,
      'message': message,
      'status': _statusToString(status),
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'agreedReturnDate': agreedReturnDate != null
          ? Timestamp.fromDate(agreedReturnDate!)
          : null,
      'returnInitiatedBy': returnInitiatedBy,
      'returnInitiatedAt': returnInitiatedAt != null
          ? Timestamp.fromDate(returnInitiatedAt!)
          : null,
      'borrowerCondition': borrowerCondition,
      'borrowerConditionNotes': borrowerConditionNotes,
      'borrowerConditionPhotos': borrowerConditionPhotos,
      'returnConfirmedBy': returnConfirmedBy,
      'returnConfirmedAt': returnConfirmedAt != null
          ? Timestamp.fromDate(returnConfirmedAt!)
          : null,
      'actualReturnDate': actualReturnDate != null
          ? Timestamp.fromDate(actualReturnDate!)
          : null,
      'lenderConditionDecision': lenderConditionDecision,
      'lenderConditionNotes': lenderConditionNotes,
      'lenderConditionPhotos': lenderConditionPhotos,
      'damageReport': damageReport,
      'disputeResolution': disputeResolution,
    };
  }

  String _statusToString(BorrowRequestStatus status) {
    switch (status) {
      case BorrowRequestStatus.pending:
        return 'pending';
      case BorrowRequestStatus.accepted:
        return 'accepted';
      case BorrowRequestStatus.declined:
        return 'declined';
      case BorrowRequestStatus.cancelled:
        return 'cancelled';
      case BorrowRequestStatus.returnInitiated:
        return 'return_initiated';
      case BorrowRequestStatus.returned:
        return 'returned';
      case BorrowRequestStatus.returnDisputed:
        return 'return_disputed';
    }
  }

  String get statusDisplay {
    switch (status) {
      case BorrowRequestStatus.pending:
        return 'Pending';
      case BorrowRequestStatus.accepted:
        return 'Accepted';
      case BorrowRequestStatus.declined:
        return 'Declined';
      case BorrowRequestStatus.cancelled:
        return 'Cancelled';
      case BorrowRequestStatus.returnInitiated:
        return 'Return Initiated';
      case BorrowRequestStatus.returned:
        return 'Returned';
      case BorrowRequestStatus.returnDisputed:
        return 'Return Disputed';
    }
  }

  // Helper getters
  bool get isPending => status == BorrowRequestStatus.pending;
  bool get isAccepted => status == BorrowRequestStatus.accepted;
  bool get isDeclined => status == BorrowRequestStatus.declined;
  bool get isCancelled => status == BorrowRequestStatus.cancelled;
  bool get isReturnInitiated => status == BorrowRequestStatus.returnInitiated;
  bool get isReturned => status == BorrowRequestStatus.returned;
  bool get isReturnDisputed => status == BorrowRequestStatus.returnDisputed;
  bool get isActive => isAccepted || isReturnInitiated;
  bool get isCompleted => isReturned || isReturnDisputed;
  bool get hasDisputeResolution => disputeResolution != null;
}
