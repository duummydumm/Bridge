import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
// import removed: admin provider used in sub-widgets
import 'widgets/admin_sidebar.dart';
import 'widgets/user_verification_board.dart';
import 'widgets/activity_monitoring.dart';
import 'widgets/reports_tab.dart';
import 'widgets/analytics.dart';
import 'widgets/account_management.dart';
import 'widgets/logs.dart';
import 'widgets/dashboard_quick_stats.dart';
import 'admin_notifications_screen.dart';
import 'calamity_events_admin_screen.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  int _selected = 0;
  bool _isSidebarCollapsed = false;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      // Web: Sidebar layout
      return Scaffold(
        body: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              width: _isSidebarCollapsed ? 0 : 260,
              child: _isSidebarCollapsed
                  ? const SizedBox.shrink()
                  : AdminSidebar(
                      selected: _selected,
                      onSelect: (i) => setState(() => _selected = i),
                      onToggle: () =>
                          setState(() => _isSidebarCollapsed = true),
                    ),
            ),
            Expanded(
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFFF5F7FA),
                          const Color(0xFFE8EDF2),
                          Colors.white,
                        ],
                      ),
                    ),
                    child: SafeArea(child: _buildPage(_selected)),
                  ),
                  // Floating button to expand sidebar when collapsed
                  if (_isSidebarCollapsed)
                    Positioned(
                      left: 8,
                      top: 16,
                      child: Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          onTap: () =>
                              setState(() => _isSidebarCollapsed = false),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  const Color(0xFF00897B),
                                  const Color(0xFF00695C),
                                  const Color(0xFF004D40),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.menu,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Mobile/Desktop app builds (non-web): Bottom navigation + logout in AppBar
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bridge Admin'),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [const Color(0xFF00897B), const Color(0xFF00695C)],
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await fb_auth.FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil('/login', (route) => false);
              }
            },
          ),
        ],
      ),
      body: SafeArea(child: _buildPage(_selected)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selected > 8 ? 0 : _selected,
        onDestinationSelected: (i) => setState(() => _selected = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.verified_user_outlined),
            label: 'Verify',
          ),
          NavigationDestination(
            icon: Icon(Icons.monitor_heart_outlined),
            label: 'Activity',
          ),
          NavigationDestination(
            icon: Icon(Icons.report_gmailerrorred_outlined),
            label: 'Reports',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            label: 'Analytics',
          ),
          NavigationDestination(
            icon: Icon(Icons.manage_accounts_outlined),
            label: 'Users',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            label: 'Notifications',
          ),
          NavigationDestination(
            icon: Icon(Icons.emergency_outlined),
            label: 'Calamity',
          ),
          NavigationDestination(
            icon: Icon(Icons.article_outlined),
            label: 'Logs',
          ),
        ],
      ),
    );
  }

  Widget _buildPage(int index) {
    switch (index) {
      case 0:
        return const DashboardQuickStats();
      case 1:
        return const UserVerificationBoard();
      case 2:
        return const ActivityMonitoringTab();
      case 3:
        return const ReportsTab();
      case 4:
        return const AnalyticsTab();
      case 5:
        return const AccountManagementTab();
      case 6:
        return const AdminNotificationsScreen();
      case 7:
        return const CalamityEventsAdminScreen();
      case 8:
        return const ActivityLogsTab();
      default:
        return const SizedBox.shrink();
    }
  }
}

// Sidebar moved to widgets/admin_sidebar.dart

// User verification components moved to widgets/user_verification_board.dart and widgets/user_verification_detail_dialog.dart

// (removed unused helper)

// Activity Monitoring moved to widgets/activity_monitoring.dart

// Activity Monitoring moved to widgets/activity_monitoring.dart

// Activity Monitoring moved to widgets/activity_monitoring.dart

// Activity Monitoring moved to widgets/activity_monitoring.dart

// Reports tab moved to widgets/reports_tab.dart

// Analytics tab moved to widgets/analytics.dart

// Account Management moved to widgets/account_management.dart
