import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';
import '../models/giveaway_rating_model.dart';

class GiveawayRatingProvider extends ChangeNotifier {
  final FirestoreService _firestore = FirestoreService();

  List<GiveawayRatingModel> _ratings = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<GiveawayRatingModel> get ratings => _ratings;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<String?> createRating({
    required String giveawayId,
    required String giveawayTitle,
    required String donorId,
    required String donorName,
    required String raterId,
    required String raterName,
    required int rating,
    String? review,
  }) async {
    try {
      _setLoading(true);
      _clearError();

      // Check if rating already exists
      final existing = await _firestore.getRatingForGiveaway(
        giveawayId: giveawayId,
        raterId: raterId,
      );

      if (existing != null) {
        _setError('You have already rated this giveaway');
        _setLoading(false);
        notifyListeners();
        return null;
      }

      final payload = {
        'giveawayId': giveawayId,
        'giveawayTitle': giveawayTitle,
        'donorId': donorId,
        'donorName': donorName,
        'raterId': raterId,
        'raterName': raterName,
        'rating': rating,
        'review': review,
        'createdAt': FieldValue.serverTimestamp(),
      };

      final id = await _firestore.createGiveawayRating(payload);
      _setLoading(false);
      notifyListeners();
      return id;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
      return null;
    }
  }

  Future<void> loadRatingsForDonor(String donorId) async {
    try {
      _setLoading(true);
      _clearError();
      final data = await _firestore.getRatingsForDonor(donorId);
      _ratings = data
          .map((m) => GiveawayRatingModel.fromMap(m, m['id'] as String))
          .toList();
      _setLoading(false);
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<double> getAverageRating(String donorId) async {
    try {
      return await _firestore.getAverageRatingForDonor(donorId);
    } catch (e) {
      return 0.0;
    }
  }

  void _setLoading(bool v) {
    _isLoading = v;
  }

  void _setError(String msg) {
    _errorMessage = msg;
  }

  void _clearError() {
    _errorMessage = null;
  }
}
