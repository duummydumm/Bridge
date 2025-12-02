class DonorAnalyticsModel {
  final int totalGiveaways;
  final int activeGiveaways;
  final int claimedGiveaways;
  final int completedGiveaways;
  final int totalClaimsReceived;
  final int pendingClaims;
  final int approvedClaims;
  final int rejectedClaims;
  final double averageRating;
  final int totalRatings;
  final Map<String, int> giveawaysByCategory; // category -> count
  final Map<String, int> claimsByMonth; // month -> count
  final List<MonthlyStat> monthlyStats;

  DonorAnalyticsModel({
    required this.totalGiveaways,
    required this.activeGiveaways,
    required this.claimedGiveaways,
    required this.completedGiveaways,
    required this.totalClaimsReceived,
    required this.pendingClaims,
    required this.approvedClaims,
    required this.rejectedClaims,
    required this.averageRating,
    required this.totalRatings,
    required this.giveawaysByCategory,
    required this.claimsByMonth,
    required this.monthlyStats,
  });

  factory DonorAnalyticsModel.empty() {
    return DonorAnalyticsModel(
      totalGiveaways: 0,
      activeGiveaways: 0,
      claimedGiveaways: 0,
      completedGiveaways: 0,
      totalClaimsReceived: 0,
      pendingClaims: 0,
      approvedClaims: 0,
      rejectedClaims: 0,
      averageRating: 0.0,
      totalRatings: 0,
      giveawaysByCategory: {},
      claimsByMonth: {},
      monthlyStats: [],
    );
  }
}

class MonthlyStat {
  final String month; // Format: "YYYY-MM"
  final int giveawaysPosted;
  final int claimsReceived;
  final int claimsApproved;
  final double averageRating;

  MonthlyStat({
    required this.month,
    required this.giveawaysPosted,
    required this.claimsReceived,
    required this.claimsApproved,
    required this.averageRating,
  });
}
