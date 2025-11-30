import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;

class AdminSidebar extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback? onToggle;
  const AdminSidebar({
    super.key,
    required this.selected,
    required this.onSelect,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final entries = const [
      (Icons.dashboard_outlined, 'Dashboard'),
      (Icons.verified_user_outlined, 'User Verification'),
      (Icons.monitor_heart_outlined, 'Activity Monitoring'),
      (Icons.report_gmailerrorred_outlined, 'Reports & Violations'),
      (Icons.analytics_outlined, 'Analytics'),
      (Icons.manage_accounts_outlined, 'Account Management'),
      (Icons.notifications_outlined, 'Notifications'),
      (Icons.emergency_outlined, 'Calamity Events'),
      (Icons.article_outlined, 'Activity Logs'),
    ];

    return Container(
      width: 260,
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 20, 8, 12),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.admin_panel_settings,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Bridge Admin',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                if (onToggle != null)
                  IconButton(
                    tooltip: 'Collapse sidebar',
                    icon: const Icon(Icons.chevron_left, color: Colors.white),
                    onPressed: onToggle,
                  ),
                IconButton(
                  tooltip: 'Sign out',
                  icon: const Icon(Icons.logout, color: Colors.white),
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
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: entries.length,
              itemBuilder: (context, i) {
                final e = entries[i];
                final isSelected = selected == i;
                return InkWell(
                  onTap: () => onSelect(i),
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      gradient: isSelected
                          ? LinearGradient(
                              colors: [
                                Colors.white.withOpacity(0.25),
                                Colors.white.withOpacity(0.15),
                              ],
                            )
                          : null,
                      color: isSelected ? null : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: isSelected
                          ? Border.all(
                              color: Colors.white.withOpacity(0.3),
                              width: 1,
                            )
                          : null,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          e.$1,
                          color: isSelected
                              ? Colors.white
                              : Colors.white.withOpacity(0.7),
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            e.$2,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: isSelected
                                  ? Colors.white
                                  : Colors.white.withOpacity(0.9),
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        if (isSelected)
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
