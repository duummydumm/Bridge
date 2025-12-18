import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../providers/admin_provider.dart';
import 'package:fl_chart/fl_chart.dart';

class AnalyticsTab extends StatefulWidget {
  const AnalyticsTab({super.key});

  @override
  State<AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<AnalyticsTab> {
  bool _hasLoaded = false;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _compareMode = false;
  DateTime? _compareStartDate;
  DateTime? _compareEndDate;

  @override
  void initState() {
    super.initState();
    // Auto-load analytics when tab is first opened
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final admin = Provider.of<AdminProvider>(context, listen: false);
      if (admin.analyticsData == null && !admin.isBusy) {
        admin.loadAnalytics();
        _hasLoaded = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AdminProvider>(
      builder: (context, admin, _) {
        final data = admin.analyticsData;

        // Auto-load if not loaded yet and not busy
        if (!_hasLoaded && data == null && !admin.isBusy) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            admin.loadAnalytics();
            _hasLoaded = true;
          });
        }

        return RefreshIndicator(
          onRefresh: () async {
            await admin.loadAnalytics();
            _hasLoaded = true;
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [const Color(0xFF00897B), const Color(0xFF00695C)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00897B).withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.analytics,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Text(
                          'Analytics Overview',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.date_range,
                            color: Colors.white,
                          ),
                          onPressed: () => _showDateRangePicker(context),
                          tooltip: 'Select date range',
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.2,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            _compareMode
                                ? Icons.compare_arrows
                                : Icons.timeline,
                            color: Colors.white,
                          ),
                          onPressed: () {
                            setState(() => _compareMode = !_compareMode);
                          },
                          tooltip: 'Toggle comparison mode',
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.2,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh, color: Colors.white),
                          onPressed: () {
                            admin.loadAnalytics();
                            _hasLoaded = true;
                          },
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_startDate != null || _endDate != null || _compareMode)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Row(
                    children: [
                      if (_startDate != null || _endDate != null)
                        Expanded(
                          child: Text(
                            'Date Range: ${_startDate != null ? DateFormat('MMM dd, yyyy').format(_startDate!) : 'Start'} - ${_endDate != null ? DateFormat('MMM dd, yyyy').format(_endDate!) : 'End'}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      if (_compareMode)
                        Expanded(
                          child: Text(
                            'Comparison: ${_compareStartDate != null ? DateFormat('MMM dd').format(_compareStartDate!) : 'Period 1'} vs ${_compareEndDate != null ? DateFormat('MMM dd').format(_compareEndDate!) : 'Period 2'}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _startDate = null;
                            _endDate = null;
                            _compareMode = false;
                            _compareStartDate = null;
                            _compareEndDate = null;
                          });
                        },
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              if (admin.isBusy)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: CircularProgressIndicator(),
                  ),
                ),
              if (!admin.isBusy && data == null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        Icon(
                          Icons.analytics_outlined,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          admin.error != null
                              ? 'Error loading analytics'
                              : 'Loading analytics...',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (admin.error != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red[200]!),
                            ),
                            child: Text(
                              admin.error!,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.red[700],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          'Pull down to refresh',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (data != null) ...[
                _KpiGrid(
                  totalUsers: data.totals.totalUsers,
                  activeUsers30d: data.totals.activeUsers30d,
                  activeListings: data.totals.activeListings,
                  reports30d: data.totals.reports30d,
                ),
                const SizedBox(height: 16),
                // Calamity Relief Section
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFE57373,
                              ).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.emergency_outlined,
                              color: Color(0xFFE57373),
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Calamity Relief',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _CalamityKpiGrid(
                        totalEvents: data.totals.totalCalamityEvents,
                        activeEvents: data.totals.activeCalamityEvents,
                        totalDonations: data.totals.totalCalamityDonations,
                        totalDonors: data.totals.totalCalamityDonors,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _CardWrap(
                        title: 'User Growth',
                        showExport: true,
                        child: _UsersGrowthChart(
                          points: data.usersMonthly,
                          onExport: () => _exportChart(context, 'user_growth'),
                          onDrillDown: () => _showDrillDown(context, 'users'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _CardWrap(
                        title: 'Popular Categories (30d)',
                        showExport: true,
                        child: _CategoriesPieChart(
                          slices: data.categories30d,
                          onExport: () => _exportChart(context, 'categories'),
                          onDrillDown: () =>
                              _showDrillDown(context, 'categories'),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _CardWrap(
                  title: 'Most Reported Issues (30d)',
                  showExport: true,
                  child: _IssuesBarChart(
                    issues: data.issues30d,
                    onExport: () => _exportChart(context, 'issues'),
                    onDrillDown: () => _showDrillDown(context, 'issues'),
                  ),
                ),
                const SizedBox(height: 16),
                if (data.usersMonthly.length >= 3)
                  _CardWrap(
                    title: 'Growth Trends & Predictions',
                    showExport: false,
                    child: _GrowthTrendsWidget(points: data.usersMonthly),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _showDateRangePicker(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
        if (_compareMode) {
          final duration = _endDate!.difference(_startDate!);
          _compareStartDate = _startDate!.subtract(duration);
          _compareEndDate = _startDate!;
        }
      });
    }
  }

  Future<void> _exportChart(BuildContext context, String chartType) async {
    try {
      final admin = Provider.of<AdminProvider>(context, listen: false);
      final data = admin.analyticsData;
      if (data == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No data available to export'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      String csv = '';

      switch (chartType) {
        case 'user_growth':
          csv = _exportUserGrowthData(data.usersMonthly);
          break;
        case 'categories':
          csv = _exportCategoriesData(data.categories30d);
          break;
        case 'issues':
          csv = _exportIssuesData(data.issues30d);
          break;
        default:
          csv =
              'Chart Type: $chartType\n'
              'Export Date: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}';
      }

      await Clipboard.setData(ClipboardData(text: csv));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$chartType data exported as CSV and copied to clipboard!\n'
              'You can paste it into Excel or Google Sheets.',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error exporting chart: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _exportUserGrowthData(List<dynamic> points) {
    final csv = StringBuffer();
    csv.writeln('Month,User Count');
    for (final point in points) {
      final month = point.month as String;
      final count = point.count as int;
      // Format month as readable date (e.g., "2024-01" -> "January 2024")
      final year = month.substring(0, 4);
      final monthNum = month.substring(5, 7);
      final monthNames = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ];
      final monthName = monthNames[int.parse(monthNum) - 1];
      csv.writeln('$monthName $year,$count');
    }
    return csv.toString();
  }

  String _exportCategoriesData(List<dynamic> slices) {
    final csv = StringBuffer();
    csv.writeln('Category,Count,Percentage');
    final total = slices.fold<int>(0, (a, b) => a + (b.count as int));
    for (final slice in slices) {
      final name = slice.name as String;
      final count = slice.count as int;
      final percentage = total > 0
          ? (count / total * 100).toStringAsFixed(1)
          : '0.0';
      csv.writeln('$name,$count,$percentage%');
    }
    csv.writeln('Total,$total,100.0%');
    return csv.toString();
  }

  String _exportIssuesData(List<dynamic> issues) {
    final csv = StringBuffer();
    csv.writeln('Issue Type,Count');
    for (final issue in issues) {
      final issueType = issue.issueType as String;
      final count = issue.count as int;
      csv.writeln('$issueType,$count');
    }
    final total = issues.fold<int>(0, (a, b) => a + (b.count as int));
    csv.writeln('Total,$total');
    return csv.toString();
  }

  void _showDrillDown(BuildContext context, String metricType) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${metricType.toUpperCase()} Details'),
        content: SizedBox(
          width: double.maxFinite,
          child: Text('Detailed breakdown for $metricType would appear here.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  final int totalUsers;
  final int activeUsers30d;
  final int activeListings;
  final int reports30d;
  const _KpiGrid({
    required this.totalUsers,
    required this.activeUsers30d,
    required this.activeListings,
    required this.reports30d,
  });

  @override
  Widget build(BuildContext context) {
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.5,
      ),
      children: [
        _KpiTile(
          color: const Color(0xFF00897B),
          icon: Icons.groups_outlined,
          label: 'Total Users',
          value: totalUsers,
        ),
        _KpiTile(
          color: const Color(0xFF1976D2),
          icon: Icons.person_search_outlined,
          label: 'Active Users (30d)',
          value: activeUsers30d,
        ),
        _KpiTile(
          color: const Color(0xFF7B1FA2),
          icon: Icons.storefront_outlined,
          label: 'Active Listings',
          value: activeListings,
        ),
        _KpiTile(
          color: const Color(0xFFD32F2F),
          icon: Icons.report_gmailerrorred_outlined,
          label: 'Reports (30d)',
          value: reports30d,
        ),
      ],
    );
  }
}

class _KpiTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final Color color;
  const _KpiTile({
    required this.color,
    required this.icon,
    required this.label,
    required this.value,
  });
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: 0.1),
              color.withValues(alpha: 0.05),
              Colors.white,
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2), width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      color.withValues(alpha: 0.2),
                      color.withValues(alpha: 0.1),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 28, color: color),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color.withValues(alpha: 0.8),
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$value',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalamityKpiGrid extends StatelessWidget {
  final int totalEvents;
  final int activeEvents;
  final int totalDonations;
  final int totalDonors;
  const _CalamityKpiGrid({
    required this.totalEvents,
    required this.activeEvents,
    required this.totalDonations,
    required this.totalDonors,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        int crossAxisCount = 2;
        if (width >= 800) {
          crossAxisCount = 4;
        } else if (width >= 600) {
          crossAxisCount = 3;
        }

        return GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.5,
          ),
          children: [
            _KpiTile(
              color: const Color(0xFFE57373),
              icon: Icons.event,
              label: 'Total Events',
              value: totalEvents,
            ),
            _KpiTile(
              color: const Color(0xFF66BB6A),
              icon: Icons.check_circle,
              label: 'Active Events',
              value: activeEvents,
            ),
            _KpiTile(
              color: const Color(0xFFEF5350),
              icon: Icons.favorite,
              label: 'Total Donations',
              value: totalDonations,
            ),
            _KpiTile(
              color: const Color(0xFFAB47BC),
              icon: Icons.people,
              label: 'Total Donors',
              value: totalDonors,
            ),
          ],
        );
      },
    );
  }
}

class _CardWrap extends StatelessWidget {
  final String title;
  final Widget child;
  final bool showExport;
  const _CardWrap({
    required this.title,
    required this.child,
    this.showExport = false,
  });
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, const Color(0xFFF5F7FA), Colors.white],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey[200]!, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF00897B).withValues(alpha: 0.1),
                            const Color(0xFF00695C).withValues(alpha: 0.05),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Color(0xFF004D40),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                  if (showExport && child is _ExportableChart)
                    IconButton(
                      icon: const Icon(Icons.download, size: 20),
                      onPressed: () => (child as _ExportableChart).onExport(),
                      tooltip: 'Export chart',
                    ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(height: 220, child: child),
            ],
          ),
        ),
      ),
    );
  }
}

abstract class _ExportableChart extends StatelessWidget {
  final VoidCallback onExport;
  final VoidCallback? onDrillDown;
  const _ExportableChart({required this.onExport, this.onDrillDown});
}

class _UsersGrowthChart extends _ExportableChart {
  final List<dynamic> points; // UsersMonthlyPoint
  const _UsersGrowthChart({
    required this.points,
    required super.onExport,
    super.onDrillDown,
  });
  @override
  Widget build(BuildContext context) {
    final primaryColor = const Color(0xFF00897B);
    final secondaryColor = const Color(0xFF7B1FA2);
    final barGroups = <BarChartGroupData>[];
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final value = (p.count as num).toDouble();
      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: value,
              width: 20,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [primaryColor, secondaryColor],
              ),
            ),
          ],
        ),
      );
    }

    String monthLabel(int index) {
      if (index < 0 || index >= points.length) return '';
      final mm = points[index].month.substring(5); // 'MM'
      const names = {
        '01': 'Jan',
        '02': 'Feb',
        '03': 'Mar',
        '04': 'Apr',
        '05': 'May',
        '06': 'Jun',
        '07': 'Jul',
        '08': 'Aug',
        '09': 'Sep',
        '10': 'Oct',
        '11': 'Nov',
        '12': 'Dec',
      };
      return names[mm] ?? mm;
    }

    return GestureDetector(
      onTap: onDrillDown,
      child: Column(
        children: [
          Expanded(
            child: BarChart(
              BarChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 0.5,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: Colors.grey[300]!,
                      strokeWidth: 1,
                      dashArray: [5, 5],
                    );
                  },
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border(
                    bottom: BorderSide(color: Colors.grey[400]!, width: 1),
                    left: BorderSide(color: Colors.grey[400]!, width: 1),
                  ),
                ),
                alignment: BarChartAlignment.spaceAround,
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, __) => Text(
                        monthLabel(v.toInt()),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toInt().toString(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                          ),
                        );
                      },
                    ),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                barGroups: barGroups,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  primaryColor.withValues(alpha: 0.1),
                  secondaryColor.withValues(alpha: 0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: primaryColor.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [primaryColor, secondaryColor],
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'users',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: Color(0xFF004D40),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoriesPieChart extends _ExportableChart {
  final List<dynamic> slices; // CategorySlice
  const _CategoriesPieChart({
    required this.slices,
    required super.onExport,
    super.onDrillDown,
  });

  static const List<Color> _colors = [
    Color(0xFF00897B),
    Color(0xFF1976D2),
    Color(0xFF7B1FA2),
    Color(0xFFD32F2F),
    Color(0xFFF57C00),
    Color(0xFF388E3C),
    Color(0xFF5E35B1),
    Color(0xFFC2185B),
  ];

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<int>(0, (a, b) => a + (b.count as int));
    if (total == 0) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'No data',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: onDrillDown,
      child: PieChart(
        PieChartData(
          sectionsSpace: 3,
          centerSpaceRadius: 50,
          sections: [
            for (int i = 0; i < slices.length; i++)
              PieChartSectionData(
                value: (slices[i].count as num).toDouble(),
                title:
                    '${slices[i].name}\n${((slices[i].count as num).toDouble() / total * 100).toStringAsFixed(0)}%',
                radius: 65,
                titleStyle: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                color: _colors[i % _colors.length],
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _colors[i % _colors.length],
                    _colors[i % _colors.length].withValues(alpha: 0.7),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _IssuesBarChart extends _ExportableChart {
  final List<dynamic> issues; // IssueCount
  const _IssuesBarChart({
    required this.issues,
    required super.onExport,
    super.onDrillDown,
  });
  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'No data',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: onDrillDown,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 1,
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: Colors.grey[300]!,
                strokeWidth: 1,
                dashArray: [5, 5],
              );
            },
          ),
          borderData: FlBorderData(
            show: true,
            border: Border(
              bottom: BorderSide(color: Colors.grey[400]!, width: 1),
              left: BorderSide(color: Colors.grey[400]!, width: 1),
            ),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, __) {
                  final idx = v.toInt();
                  if (idx < 0 || idx >= issues.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      issues[idx].issueType,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toInt().toString(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
                    ),
                  );
                },
              ),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          barGroups: [
            for (int i = 0; i < issues.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: (issues[i].count as num).toDouble(),
                    width: 20,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      topRight: Radius.circular(4),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        const Color(0xFFD32F2F),
                        const Color(0xFFB71C1C),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _GrowthTrendsWidget extends StatelessWidget {
  final List<dynamic> points; // UsersMonthlyPoint
  const _GrowthTrendsWidget({required this.points});

  double _calculateGrowthRate(List<dynamic> points) {
    if (points.length < 2) return 0.0;
    final recent = points.sublist(points.length - 3);
    final older = points.sublist(0, points.length - 3);
    if (older.isEmpty) return 0.0;
    final recentAvg =
        recent.fold<int>(0, (a, b) => a + (b.count as int)) / recent.length;
    final olderAvg =
        older.fold<int>(0, (a, b) => a + (b.count as int)) / older.length;
    if (olderAvg == 0) return 0.0;
    return ((recentAvg - olderAvg) / olderAvg) * 100;
  }

  int _predictNextMonth(List<dynamic> points) {
    if (points.length < 2) return 0;
    final last = points.last.count as int;
    final secondLast = points[points.length - 2].count as int;
    final growth = last - secondLast;
    return (last + growth).round();
  }

  @override
  Widget build(BuildContext context) {
    final growthRate = _calculateGrowthRate(points);
    final prediction = _predictNextMonth(points);
    final isPositive = growthRate >= 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _TrendCard(
                title: 'Growth Rate',
                value: '${growthRate.toStringAsFixed(1)}%',
                icon: isPositive ? Icons.trending_up : Icons.trending_down,
                color: isPositive ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _TrendCard(
                title: 'Next Month Prediction',
                value: '$prediction',
                icon: Icons.auto_graph,
                color: Colors.blue,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Trend Analysis',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Text(
                isPositive
                    ? 'User growth is trending upward. Based on current patterns, expect continued growth in the coming months.'
                    : 'User growth is declining. Consider reviewing user acquisition strategies.',
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TrendCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _TrendCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
