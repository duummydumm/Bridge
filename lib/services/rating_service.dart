import '../models/rating_model.dart';
import 'firestore_service.dart';

class RatingService {
  final FirestoreService _firestoreService = FirestoreService();

  /// Submit a rating/feedback for another user
  /// NOTE: A valid transactionId is required to prevent fake profile-only reviews.
  Future<String?> submitRating({
    required String ratedUserId,
    required String raterUserId,
    required String raterName,
    required RatingContext context,
    String? transactionId,
    required int rating,
    String? feedback,
    required String role,
  }) async {
    try {
      // Require a non-null, non-empty transactionId
      if (transactionId == null || transactionId.isEmpty) {
        throw Exception(
          'A completed transaction is required before leaving a review.',
        );
      }

      // Check if rating already exists for this transaction
      final existing = await _firestoreService.hasExistingRating(
        raterUserId: raterUserId,
        ratedUserId: ratedUserId,
        transactionId: transactionId,
      );
      if (existing) {
        throw Exception(
          'You have already rated this user for this transaction.',
        );
      }

      final ratingData = {
        'ratedUserId': ratedUserId,
        'raterUserId': raterUserId,
        'raterName': raterName,
        'context': context.name,
        'transactionId': transactionId,
        'rating': rating.clamp(1, 5),
        'feedback': feedback,
        'role': role,
        'createdAt': DateTime.now(),
        'updatedAt': null,
      };

      final ratingId = await _firestoreService.createRating(ratingData);

      // Update the rated user's reputation score
      await _firestoreService.updateUserReputationScore(ratedUserId);

      return ratingId;
    } catch (e) {
      throw Exception('Error submitting rating: $e');
    }
  }

  /// Update an existing rating
  Future<bool> updateRating({
    required String ratingId,
    required int rating,
    String? feedback,
  }) async {
    try {
      final ratingData = await _firestoreService.getRating(ratingId);
      if (ratingData == null) {
        throw Exception('Rating not found');
      }

      final ratedUserId = ratingData['ratedUserId'] as String;

      await _firestoreService.updateRating(ratingId, {
        'rating': rating.clamp(1, 5),
        'feedback': feedback,
        'updatedAt': DateTime.now(),
      });

      // Update the rated user's reputation score
      await _firestoreService.updateUserReputationScore(ratedUserId);

      return true;
    } catch (e) {
      throw Exception('Error updating rating: $e');
    }
  }

  /// Get all ratings for a user (public reviews)
  Future<List<RatingModel>> getRatingsForUser(String userId) async {
    try {
      final ratingsData = await _firestoreService.getRatingsForUser(userId);
      return ratingsData
          .map((data) => RatingModel.fromMap(data, data['id'] as String))
          .toList();
    } catch (e) {
      throw Exception('Error fetching ratings: $e');
    }
  }

  /// Get average rating for a user
  Future<double> getAverageRating(String userId) async {
    try {
      return await _firestoreService.calculateAverageRating(userId);
    } catch (e) {
      throw Exception('Error calculating average rating: $e');
    }
  }

  /// Check if user has already rated another user for a transaction
  Future<bool> hasRated({
    required String raterUserId,
    required String ratedUserId,
    String? transactionId,
  }) async {
    try {
      return await _firestoreService.hasExistingRating(
        raterUserId: raterUserId,
        ratedUserId: ratedUserId,
        transactionId: transactionId,
      );
    } catch (e) {
      return false;
    }
  }
}
