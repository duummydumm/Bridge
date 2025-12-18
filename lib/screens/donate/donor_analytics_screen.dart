import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/donor_analytics_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/donor_analytics_model.dart';

class DonorAnalyticsScreen extends StatefulWidget {
  const DonorAnalyticsScreen({super.key});

  @override
  State<DonorAnalyticsScreen> createState() => _DonorAnalyticsScreenState();
}

class _DonorAnalyticsScreenState extends State<DonorAnalyticsScreen> {
  static const Color _primaryColor = Color(0xFF2A7A9E);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final analyticsProvider = Provider.of<DonorAnalyticsProvider>(
        context,
        listen: false,
      );
      if (authProvider.user != null) {
        analyticsProvider.loadAnalytics(authProvider.user!.uid);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final analyticsProvider = Provider.of<DonorAnalyticsProvider>(context);

    if (authProvider.user == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          title: const Text('Donor Analytics'),
        ),
        body: const Center(child: Text('Please log in to view analytics')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        title: const Text('Donor Analytics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              analyticsProvider.loadAnalytics(authProvider.user!.uid);
            },
          ),
        ],
      ),
      body: analyticsProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : analyticsProvider.analytics == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.analytics_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No analytics data available',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () async {
                await analyticsProvider.loadAnalytics(authProvider.user!.uid);
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildOverviewCards(analyticsProvider.analytics!),
                    const SizedBox(height: 24),
                    _buildRatingCard(analyticsProvider.analytics!),
                    const SizedBox(height: 24),
                    _buildCategoryBreakdown(analyticsProvider.analytics!),
                    const SizedBox(height: 24),
                    _buildMonthlyStats(analyticsProvider.analytics!),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildOverviewCards(DonorAnalyticsModel analytics) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        _buildStatCard(
          'Total Giveaways',
          analytics.totalGiveaways.toString(),
          Icons.card_giftcard,
          Colors.blue,
        ),
        _buildStatCard(
          'Active',
          analytics.activeGiveaways.toString(),
          Icons.check_circle,
          Colors.green,
        ),
        _buildStatCard(
          'Claimed',
          analytics.claimedGiveaways.toString(),
          Icons.inventory_2,
          Colors.orange,
        ),
        _buildStatCard(
          'Completed',
          analytics.completedGiveaways.toString(),
          Icons.done_all,
          Colors.purple,
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildRatingCard(DonorAnalyticsModel analytics) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.star, color: Colors.amber, size: 28),
              const SizedBox(width: 12),
              Text(
                'Rating',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                analytics.averageRating.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: _primaryColor,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '/ 5.0',
                  style: TextStyle(fontSize: 20, color: Colors.grey[600]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Based on ${analytics.totalRatings} ${analytics.totalRatings == 1 ? 'rating' : 'ratings'}',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBreakdown(DonorAnalyticsModel analytics) {
    if (analytics.giveawaysByCategory.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Giveaways by Category',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 16),
          ...analytics.giveawaysByCategory.entries.map((entry) {
            final percentage = analytics.totalGiveaways > 0
                ? (entry.value / analytics.totalGiveaways) * 100
                : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        entry.key,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[800],
                        ),
                      ),
                      Text(
                        '${entry.value} (${percentage.toStringAsFixed(1)}%)',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: percentage / 100,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
                      minHeight: 8,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildMonthlyStats(DonorAnalyticsModel analytics) {
    if (analytics.monthlyStats.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Monthly Statistics (Last 6 Months)',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 16),
          ...analytics.monthlyStats.map((stat) {
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stat.month,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _primaryColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildMiniStat(
                          'Posted',
                          stat.giveawaysPosted.toString(),
                          Icons.add_circle_outline,
                        ),
                      ),
                      Expanded(
                        child: _buildMiniStat(
                          'Claims',
                          stat.claimsReceived.toString(),
                          Icons.inbox_outlined,
                        ),
                      ),
                      Expanded(
                        child: _buildMiniStat(
                          'Approved',
                          stat.claimsApproved.toString(),
                          Icons.check_circle_outline,
                        ),
                      ),
                      if (stat.averageRating > 0)
                        Expanded(
                          child: _buildMiniStat(
                            'Rating',
                            stat.averageRating.toStringAsFixed(1),
                            Icons.star_outline,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.grey[800],
          ),
        ),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }
}
