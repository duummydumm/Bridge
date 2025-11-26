import 'package:cloud_firestore/cloud_firestore.dart';

enum TradeOfferStatus { pending, approved, declined, completed, cancelled }

class TradeOfferModel {
  final String id;
  final String tradeItemId; // Reference to the original trade listing
  final String fromUserId; // User who made the offer
  final String fromUserName;
  final String toUserId; // Owner of the trade listing
  final String toUserName;

  // What the offerer is offering
  final String offeredItemName;
  final String? offeredItemImageUrl;
  final String? offeredItemDescription;

  // Reference to the original trade listing item
  final String originalOfferedItemName; // What the listing owner is offering
  final String? originalOfferedItemImageUrl;

  final String? message; // Optional message from offerer
  final TradeOfferStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;

  TradeOfferModel({
    required this.id,
    required this.tradeItemId,
    required this.fromUserId,
    required this.fromUserName,
    required this.toUserId,
    required this.toUserName,
    required this.offeredItemName,
    this.offeredItemImageUrl,
    this.offeredItemDescription,
    required this.originalOfferedItemName,
    this.originalOfferedItemImageUrl,
    this.message,
    required this.status,
    required this.createdAt,
    this.updatedAt,
  });

  factory TradeOfferModel.fromMap(Map<String, dynamic> data, String id) {
    // Parse status from string
    TradeOfferStatus offerStatus = TradeOfferStatus.pending;
    final statusString = (data['status'] ?? 'pending').toString().toLowerCase();

    switch (statusString) {
      case 'pending':
        offerStatus = TradeOfferStatus.pending;
        break;
      case 'approved':
        offerStatus = TradeOfferStatus.approved;
        break;
      case 'declined':
        offerStatus = TradeOfferStatus.declined;
        break;
      case 'completed':
        offerStatus = TradeOfferStatus.completed;
        break;
      case 'cancelled':
        offerStatus = TradeOfferStatus.cancelled;
        break;
    }

    return TradeOfferModel(
      id: id,
      tradeItemId: data['tradeItemId'] ?? '',
      fromUserId: data['fromUserId'] ?? '',
      fromUserName: data['fromUserName'] ?? '',
      toUserId: data['toUserId'] ?? '',
      toUserName: data['toUserName'] ?? '',
      offeredItemName: data['offeredItemName'] ?? '',
      offeredItemImageUrl: data['offeredItemImageUrl'],
      offeredItemDescription: data['offeredItemDescription'],
      originalOfferedItemName: data['originalOfferedItemName'] ?? '',
      originalOfferedItemImageUrl: data['originalOfferedItemImageUrl'],
      message: data['message'],
      status: offerStatus,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    String statusString;
    switch (status) {
      case TradeOfferStatus.pending:
        statusString = 'pending';
        break;
      case TradeOfferStatus.approved:
        statusString = 'approved';
        break;
      case TradeOfferStatus.declined:
        statusString = 'declined';
        break;
      case TradeOfferStatus.completed:
        statusString = 'completed';
        break;
      case TradeOfferStatus.cancelled:
        statusString = 'cancelled';
        break;
    }

    return {
      'tradeItemId': tradeItemId,
      'fromUserId': fromUserId,
      'fromUserName': fromUserName,
      'toUserId': toUserId,
      'toUserName': toUserName,
      'offeredItemName': offeredItemName,
      'offeredItemImageUrl': offeredItemImageUrl,
      'offeredItemDescription': offeredItemDescription,
      'originalOfferedItemName': originalOfferedItemName,
      'originalOfferedItemImageUrl': originalOfferedItemImageUrl,
      'message': message,
      'status': statusString,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    };
  }

  String get statusDisplay {
    switch (status) {
      case TradeOfferStatus.pending:
        return 'Pending';
      case TradeOfferStatus.approved:
        return 'Approved';
      case TradeOfferStatus.declined:
        return 'Declined';
      case TradeOfferStatus.completed:
        return 'Completed';
      case TradeOfferStatus.cancelled:
        return 'Cancelled';
    }
  }

  bool get isPending => status == TradeOfferStatus.pending;
  bool get isApproved => status == TradeOfferStatus.approved;
  bool get isDeclined => status == TradeOfferStatus.declined;
  bool get isCompleted => status == TradeOfferStatus.completed;
}
