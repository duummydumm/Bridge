import 'package:cloud_firestore/cloud_firestore.dart';

class GiveawayRatingModel {
  final String id;
  final String giveawayId;
  final String giveawayTitle;
  final String donorId;
  final String donorName;
  final String raterId; // User who gave the rating (claimant)
  final String raterName;
  final int rating; // 1-5 stars
  final String? review; // Optional text review
  final DateTime createdAt;
  final DateTime? updatedAt;

  GiveawayRatingModel({
    required this.id,
    required this.giveawayId,
    required this.giveawayTitle,
    required this.donorId,
    required this.donorName,
    required this.raterId,
    required this.raterName,
    required this.rating,
    this.review,
    required this.createdAt,
    this.updatedAt,
  });

  factory GiveawayRatingModel.fromMap(Map<String, dynamic> data, String id) {
    return GiveawayRatingModel(
      id: id,
      giveawayId: data['giveawayId'] ?? '',
      giveawayTitle: data['giveawayTitle'] ?? '',
      donorId: data['donorId'] ?? '',
      donorName: data['donorName'] ?? '',
      raterId: data['raterId'] ?? '',
      raterName: data['raterName'] ?? '',
      rating: (data['rating'] is int)
          ? data['rating']
          : int.tryParse(data['rating'].toString()) ?? 5,
      review: data['review'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'giveawayId': giveawayId,
      'giveawayTitle': giveawayTitle,
      'donorId': donorId,
      'donorName': donorName,
      'raterId': raterId,
      'raterName': raterName,
      'rating': rating,
      'review': review,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    };
  }
}
