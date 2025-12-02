import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../models/donor_analytics_model.dart';

class DonorAnalyticsProvider extends ChangeNotifier {
  final FirestoreService _firestore = FirestoreService();

  DonorAnalyticsModel? _analytics;
  bool _isLoading = false;
  String? _errorMessage;

  DonorAnalyticsModel? get analytics => _analytics;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadAnalytics(String donorId) async {
    try {
      _setLoading(true);
      _clearError();
      final data = await _firestore.getDonorAnalytics(donorId);

      final monthlyStats =
          (data['monthlyStats'] as List<dynamic>?)
              ?.map(
                (m) => MonthlyStat(
                  month: m['month'] as String? ?? '',
                  giveawaysPosted: m['giveawaysPosted'] as int? ?? 0,
                  claimsReceived: m['claimsReceived'] as int? ?? 0,
                  claimsApproved: m['claimsApproved'] as int? ?? 0,
                  averageRating:
                      (m['averageRating'] as num?)?.toDouble() ?? 0.0,
                ),
              )
              .toList() ??
          [];

      _analytics = DonorAnalyticsModel(
        totalGiveaways: data['totalGiveaways'] as int? ?? 0,
        activeGiveaways: data['activeGiveaways'] as int? ?? 0,
        claimedGiveaways: data['claimedGiveaways'] as int? ?? 0,
        completedGiveaways: data['completedGiveaways'] as int? ?? 0,
        totalClaimsReceived: data['totalClaimsReceived'] as int? ?? 0,
        pendingClaims: data['pendingClaims'] as int? ?? 0,
        approvedClaims: data['approvedClaims'] as int? ?? 0,
        rejectedClaims: data['rejectedClaims'] as int? ?? 0,
        averageRating: (data['averageRating'] as num?)?.toDouble() ?? 0.0,
        totalRatings: data['totalRatings'] as int? ?? 0,
        giveawaysByCategory: Map<String, int>.from(
          data['giveawaysByCategory'] as Map? ?? {},
        ),
        claimsByMonth: Map<String, int>.from(
          data['claimsByMonth'] as Map? ?? {},
        ),
        monthlyStats: monthlyStats,
      );

      _setLoading(false);
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
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
