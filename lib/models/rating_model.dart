import 'package:cloud_firestore/cloud_firestore.dart';

enum RatingContext { rental, trade, borrow, giveaway }

class RatingModel {
  final String id;
  final String ratedUserId; // The user being rated
  final String raterUserId; // The user giving the rating
  final String raterName;
  final RatingContext context; // rental, trade, borrow, giveaway
  final String? transactionId; // rentalRequestId, tradeOfferId, etc.
  final int rating; // 1-5 stars
  final String? feedback; // Written feedback (optional)
  final String
  role; // 'borrower', 'lender', 'owner', 'renter', 'donor', 'claimant', etc.
  final DateTime createdAt;
  final DateTime? updatedAt;

  RatingModel({
    required this.id,
    required this.ratedUserId,
    required this.raterUserId,
    required this.raterName,
    required this.context,
    this.transactionId,
    required this.rating,
    this.feedback,
    required this.role,
    required this.createdAt,
    this.updatedAt,
  });

  factory RatingModel.fromMap(Map<String, dynamic> data, String id) {
    RatingContext parseContext(String? s) {
      switch ((s ?? 'rental').toLowerCase()) {
        case 'rental':
          return RatingContext.rental;
        case 'trade':
          return RatingContext.trade;
        case 'borrow':
          return RatingContext.borrow;
        case 'giveaway':
          return RatingContext.giveaway;
        default:
          return RatingContext.rental;
      }
    }

    return RatingModel(
      id: id,
      ratedUserId: data['ratedUserId'] ?? '',
      raterUserId: data['raterUserId'] ?? '',
      raterName: data['raterName'] ?? '',
      context: parseContext(data['context']?.toString()),
      transactionId: data['transactionId'],
      rating: (data['rating'] is int)
          ? (data['rating'] as int).clamp(1, 5)
          : int.tryParse('${data['rating']}')?.clamp(1, 5) ?? 5,
      feedback: data['feedback'],
      role: data['role'] ?? 'user',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'ratedUserId': ratedUserId,
      'raterUserId': raterUserId,
      'raterName': raterName,
      'context': context.name,
      'transactionId': transactionId,
      'rating': rating,
      'feedback': feedback,
      'role': role,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    };
  }

  // Helper to get time ago string
  String get timeAgo {
    final now = DateTime.now();
    final difference = now.difference(createdAt);

    if (difference.inDays > 365) {
      final years = (difference.inDays / 365).floor();
      return '$years ${years == 1 ? 'year' : 'years'} ago';
    } else if (difference.inDays > 30) {
      final months = (difference.inDays / 30).floor();
      return '$months ${months == 1 ? 'month' : 'months'} ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} ${difference.inDays == 1 ? 'day' : 'days'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} ${difference.inHours == 1 ? 'hour' : 'hours'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} ${difference.inMinutes == 1 ? 'minute' : 'minutes'} ago';
    } else {
      return 'Just now';
    }
  }
}
