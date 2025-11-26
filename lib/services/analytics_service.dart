import 'package:cloud_firestore/cloud_firestore.dart';

class AnalyticsTotals {
  final int totalUsers;
  final int activeUsers30d;
  final int activeListings;
  final int reports30d;
  // Calamity metrics
  final int totalCalamityEvents;
  final int activeCalamityEvents;
  final int totalCalamityDonations;
  final int totalCalamityDonors;

  const AnalyticsTotals({
    required this.totalUsers,
    required this.activeUsers30d,
    required this.activeListings,
    required this.reports30d,
    required this.totalCalamityEvents,
    required this.activeCalamityEvents,
    required this.totalCalamityDonations,
    required this.totalCalamityDonors,
  });
}

class UsersMonthlyPoint {
  final String month; // YYYY-MM
  final int count;
  const UsersMonthlyPoint(this.month, this.count);
}

class CategorySlice {
  final String name;
  final int count;
  const CategorySlice(this.name, this.count);
}

class IssueCount {
  final String issueType;
  final int count;
  const IssueCount(this.issueType, this.count);
}

class AdminAnalyticsData {
  final AnalyticsTotals totals;
  final List<UsersMonthlyPoint> usersMonthly;
  final List<CategorySlice> categories30d;
  final List<IssueCount> issues30d;

  const AdminAnalyticsData({
    required this.totals,
    required this.usersMonthly,
    required this.categories30d,
    required this.issues30d,
  });
}

class AnalyticsService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Helper method to safely convert dynamic values to int
  int _safeInt(dynamic value, int defaultValue) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is num) return value.toInt();
    try {
      return int.parse(value.toString());
    } catch (_) {
      return defaultValue;
    }
  }

  Future<AdminAnalyticsData> fetchAnalytics() async {
    final totalsDoc = await _db.collection('analytics').doc('totals').get();
    final usersSeriesDoc = await _db
        .collection('analytics')
        .doc('series_users_monthly')
        .get();
    final categoriesDoc = await _db
        .collection('analytics')
        .doc('categories_30d')
        .get();
    final issuesDoc = await _db
        .collection('analytics')
        .doc('reports_issues_30d')
        .get();

    final totalsData = totalsDoc.data() ?? {};
    final usersMap = usersSeriesDoc.data() ?? {};
    final categoriesMap = categoriesDoc.data() ?? {};
    final issuesMap = issuesDoc.data() ?? {};

    final totals = await _computeTotalsWithFallback(totalsData);

    var usersMonthly =
        usersMap.entries
            .map(
              (e) => UsersMonthlyPoint(e.key.toString(), (e.value ?? 0) as int),
            )
            .toList()
          ..sort((a, b) => a.month.compareTo(b.month));
    if (usersMonthly.isEmpty) {
      usersMonthly = await _computeUsersMonthlyFallback();
    }

    var categories =
        categoriesMap.entries
            .map((e) => CategorySlice(e.key.toString(), (e.value ?? 0) as int))
            .toList()
          ..sort((a, b) => b.count.compareTo(a.count));
    if (categories.isEmpty) {
      categories = await _computeCategoriesFallback();
    }

    var issues =
        issuesMap.entries
            .map((e) => IssueCount(e.key.toString(), (e.value ?? 0) as int))
            .toList()
          ..sort((a, b) => b.count.compareTo(a.count));
    if (issues.isEmpty) {
      issues = await _computeIssuesFallback();
    }

    return AdminAnalyticsData(
      totals: totals,
      usersMonthly: usersMonthly,
      categories30d: categories,
      issues30d: issues,
    );
  }

  Future<AnalyticsTotals> _computeTotalsWithFallback(
    Map<String, dynamic> totalsData,
  ) async {
    int totalUsers = _safeInt(totalsData['users']?['total'], -1);
    int activeUsers30d = _safeInt(totalsData['users']?['active_30d'], -1);
    int activeListings = _safeInt(totalsData['listings']?['active'], -1);
    int reports30d = _safeInt(totalsData['reports']?['count_30d'], -1);
    // Calamity metrics from cached data
    int totalCalamityEvents = _safeInt(
      totalsData['calamity']?['total_events'],
      -1,
    );
    int activeCalamityEvents = _safeInt(
      totalsData['calamity']?['active_events'],
      -1,
    );
    int totalCalamityDonations = _safeInt(
      totalsData['calamity']?['total_donations'],
      -1,
    );
    int totalCalamityDonors = _safeInt(
      totalsData['calamity']?['total_donors'],
      -1,
    );

    // Users total
    if (totalUsers < 0) {
      try {
        totalUsers = (await _db.collection('users').count().get()).count ?? 0;
      } catch (_) {
        totalUsers = 0;
      }
    }

    // Active users in 30d via lastSeen
    if (activeUsers30d < 0) {
      try {
        final since = Timestamp.fromDate(
          DateTime.now().subtract(const Duration(days: 30)),
        );
        activeUsers30d =
            (await _db
                    .collection('users')
                    .where('lastSeen', isGreaterThanOrEqualTo: since)
                    .count()
                    .get())
                .count ??
            0;
      } catch (_) {
        activeUsers30d = 0;
      }
    }

    // Active listings: try multiple common fields
    if (activeListings < 0) {
      int count = 0;
      try {
        count =
            (await _db
                    .collection('items')
                    .where('status', isEqualTo: 'active')
                    .count()
                    .get())
                .count ??
            0;
      } catch (_) {}
      if (count == 0) {
        try {
          count =
              (await _db
                      .collection('items')
                      .where('isActive', isEqualTo: true)
                      .count()
                      .get())
                  .count ??
              0;
        } catch (_) {}
      }
      if (count == 0) {
        try {
          count = (await _db.collection('items').count().get()).count ?? 0;
        } catch (_) {}
      }
      activeListings = count;
    }

    // Reports last 30 days
    if (reports30d < 0) {
      try {
        final since = Timestamp.fromDate(
          DateTime.now().subtract(const Duration(days: 30)),
        );
        reports30d =
            (await _db
                    .collection('reports')
                    .where('createdAt', isGreaterThanOrEqualTo: since)
                    .count()
                    .get())
                .count ??
            0;
      } catch (_) {
        try {
          reports30d =
              (await _db.collection('reports').count().get()).count ?? 0;
        } catch (_) {
          reports30d = 0;
        }
      }
    }

    // Calamity Events - Total
    if (totalCalamityEvents < 0) {
      try {
        totalCalamityEvents =
            (await _db.collection('calamity_events').count().get()).count ?? 0;
      } catch (_) {
        totalCalamityEvents = 0;
      }
    }

    // Calamity Events - Active (not expired, not closed)
    if (activeCalamityEvents < 0) {
      try {
        final now = DateTime.now();
        final activeSnap = await _db
            .collection('calamity_events')
            .where('status', isEqualTo: 'active')
            .get();
        activeCalamityEvents = activeSnap.docs.where((doc) {
          final data = doc.data();
          final deadline = data['deadline'];
          if (deadline == null) return false;
          if (deadline is! Timestamp) return false;
          return deadline.toDate().isAfter(now);
        }).length;
      } catch (_) {
        activeCalamityEvents = 0;
      }
    }

    // Calamity Donations - Total
    if (totalCalamityDonations < 0) {
      try {
        totalCalamityDonations =
            (await _db.collection('calamity_donations').count().get()).count ??
            0;
      } catch (_) {
        totalCalamityDonations = 0;
      }
    }

    // Calamity Donors - Unique donors
    if (totalCalamityDonors < 0) {
      try {
        final donationsSnap = await _db.collection('calamity_donations').get();
        final uniqueDonors = <String>{};
        for (final doc in donationsSnap.docs) {
          final data = doc.data();
          final donorEmail = data['donorEmail'];
          if (donorEmail != null &&
              donorEmail is String &&
              donorEmail.isNotEmpty) {
            uniqueDonors.add(donorEmail);
          }
        }
        totalCalamityDonors = uniqueDonors.length;
      } catch (_) {
        totalCalamityDonors = 0;
      }
    }

    return AnalyticsTotals(
      totalUsers: totalUsers < 0 ? 0 : totalUsers,
      activeUsers30d: activeUsers30d < 0 ? 0 : activeUsers30d,
      activeListings: activeListings < 0 ? 0 : activeListings,
      reports30d: reports30d < 0 ? 0 : reports30d,
      totalCalamityEvents: totalCalamityEvents < 0 ? 0 : totalCalamityEvents,
      activeCalamityEvents: activeCalamityEvents < 0 ? 0 : activeCalamityEvents,
      totalCalamityDonations: totalCalamityDonations < 0
          ? 0
          : totalCalamityDonations,
      totalCalamityDonors: totalCalamityDonors < 0 ? 0 : totalCalamityDonors,
    );
  }

  Future<List<UsersMonthlyPoint>> _computeUsersMonthlyFallback() async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month - 11, 1);
    final snap = await _db
        .collection('users')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .get();
    final Map<String, int> byMonth = {
      for (int i = 0; i < 12; i++)
        '${DateTime(from.year, from.month + i, 1).year}-${DateTime(from.year, from.month + i, 1).month.toString().padLeft(2, '0')}':
            0,
    };
    for (final d in snap.docs) {
      final ts = d.data()['createdAt'];
      if (ts is! Timestamp) continue;
      final date = ts.toDate();
      final key = '${date.year}-${date.month.toString().padLeft(2, '0')}';
      if (byMonth.containsKey(key)) {
        byMonth[key] = (byMonth[key] ?? 0) + 1;
      }
    }
    final list =
        byMonth.entries.map((e) => UsersMonthlyPoint(e.key, e.value)).toList()
          ..sort((a, b) => a.month.compareTo(b.month));
    return list;
  }

  Future<List<CategorySlice>> _computeCategoriesFallback() async {
    final since = Timestamp.fromDate(
      DateTime.now().subtract(const Duration(days: 30)),
    );
    final snap = await _db
        .collection('items')
        .where('createdAt', isGreaterThanOrEqualTo: since)
        .get();
    final Map<String, int> counts = {};
    for (final d in snap.docs) {
      final cat = (d.data()['category'] ?? 'Other').toString();
      counts[cat] = (counts[cat] ?? 0) + 1;
    }
    final list =
        counts.entries.map((e) => CategorySlice(e.key, e.value)).toList()
          ..sort((a, b) => b.count.compareTo(a.count));
    return list;
  }

  Future<List<IssueCount>> _computeIssuesFallback() async {
    final since = Timestamp.fromDate(
      DateTime.now().subtract(const Duration(days: 30)),
    );
    final snap = await _db
        .collection('reports')
        .where('createdAt', isGreaterThanOrEqualTo: since)
        .get();
    final Map<String, int> counts = {};
    for (final d in snap.docs) {
      final t = (d.data()['issueType'] ?? 'Other').toString();
      counts[t] = (counts[t] ?? 0) + 1;
    }
    final list = counts.entries.map((e) => IssueCount(e.key, e.value)).toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    return list;
  }

  // Dev helper: seed sample analytics documents for UI testing
  Future<void> seedSampleData() async {
    final now = DateTime.now();
    final months = List.generate(12, (i) {
      final d = DateTime(now.year, now.month - 11 + i, 1);
      return '${d.year}-${d.month.toString().padLeft(2, '0')}';
    });

    final usersSeries = {
      for (int i = 0; i < months.length; i++) months[i]: (100 + i * 40),
    };

    await _db.collection('analytics').doc('totals').set({
      'users': {'total': 2547, 'active_30d': 1834},
      'listings': {'active': 456},
      'reports': {'count_30d': 32},
    }, SetOptions(merge: true));

    await _db
        .collection('analytics')
        .doc('series_users_monthly')
        .set(usersSeries);
    await _db.collection('analytics').doc('categories_30d').set({
      'Electronics': 35,
      'Books': 15,
      'Furniture': 15,
      'Sports': 25,
      'Other': 10,
    });
    await _db.collection('analytics').doc('reports_issues_30d').set({
      'Not Returned': 12,
      'Damaged': 8,
      'Spam': 5,
      'Behavior': 4,
      'Other': 3,
    });
  }
}
