import 'package:flutter/material.dart';
import '../reusable_widgets/bottom_nav_bar_widget.dart';
import 'verification_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: const Color(0xFF00897B),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Account Settings Section
            _buildSectionTitle('Account Settings'),
            const SizedBox(height: 8),
            _buildSettingsCard(
              children: [
                _buildSettingsItem(
                  icon: Icons.person_outline,
                  title: 'Edit Profile',
                  subtitle: 'Change your personal information',
                  onTap: () {},
                ),
                const Divider(height: 1),
                _buildSettingsItem(
                  icon: Icons.lock_outline,
                  title: 'Change Password',
                  subtitle: 'Update your password',
                  onTap: () {},
                ),
                const Divider(height: 1),
                _buildSettingsItem(
                  icon: Icons.verified_outlined,
                  title: 'Verification',
                  subtitle: 'Verify your account',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const VerificationScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),

            // App Settings Section
            _buildSectionTitle('App Settings'),
            const SizedBox(height: 8),
            _buildSettingsCard(
              children: [
                _buildSettingsItem(
                  icon: Icons.notifications_outlined,
                  title: 'Notifications',
                  subtitle: 'Manage your notifications',
                  onTap: () {},
                ),
                const Divider(height: 1),
                _buildSettingsItem(
                  icon: Icons.language_outlined,
                  title: 'Language',
                  subtitle: 'English',
                  onTap: () {},
                ),
                const Divider(height: 1),
                _buildSettingsItem(
                  icon: Icons.dark_mode_outlined,
                  title: 'Theme',
                  subtitle: 'Light',
                  onTap: () {},
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Support Section
            _buildSectionTitle('Support'),
            const SizedBox(height: 8),
            _buildSettingsCard(
              children: [
                _buildSettingsItem(
                  icon: Icons.help_outline,
                  title: 'Help Center',
                  subtitle: 'Get help and support',
                  onTap: () {},
                ),
                const Divider(height: 1),
                _buildSettingsItem(
                  icon: Icons.feedback_outlined,
                  title: 'Send Feedback',
                  subtitle: 'Share your thoughts',
                  onTap: () {},
                ),
                const Divider(height: 1),
                _buildSettingsItem(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy Policy',
                  subtitle: 'Read our privacy policy',
                  onTap: () {},
                ),
                const Divider(height: 1),
                _buildSettingsItem(
                  icon: Icons.description_outlined,
                  title: 'Terms of Service',
                  subtitle: 'Read our terms and conditions',
                  onTap: () {},
                ),
              ],
            ),
            const SizedBox(height: 24),

            const SizedBox(height: 32),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavBarWidget(
        selectedIndex: null, // No tab selected on Settings screen
        onTap: (_) {},
        navigationContext: context,
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.grey,
        ),
      ),
    );
  }

  Widget _buildSettingsCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildSettingsItem({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              icon,
              color: isDestructive ? Colors.red : Colors.grey[700],
              size: 24,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      color: isDestructive ? Colors.red : Colors.black,
                      fontWeight: isDestructive
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}
