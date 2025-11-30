import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/notification_preferences_provider.dart';
import '../../services/local_notifications_service.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  bool _checkingPermissions = false;

  Future<void> _checkNotificationPermissions() async {
    setState(() => _checkingPermissions = true);
    try {
      final localNotifications = LocalNotificationsService();
      final hasPermission = await localNotifications.areNotificationsEnabled();

      if (mounted) {
        if (!hasPermission) {
          final granted = await localNotifications.requestPermissions();
          if (granted && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Notification permissions granted!'),
                backgroundColor: Colors.green,
              ),
            );
          } else if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Notification permissions are required. Please enable them in your device settings.',
                ),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 4),
              ),
            );
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Notifications are enabled'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error checking permissions: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _checkingPermissions = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Notification Settings'),
        backgroundColor: const Color(0xFF00897B),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Consumer<NotificationPreferencesProvider>(
        builder: (context, prefsProvider, _) {
          if (prefsProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // System Permissions Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.blue[900]?.withOpacity(0.3)
                        : Colors.blue[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.blue[700]! : Colors.blue[200]!,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: isDark ? Colors.blue[300] : Colors.blue[700],
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Device Permissions',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? Colors.blue[200]
                                    : Colors.blue[900],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Make sure notifications are enabled in your device settings. These app settings control which types of notifications you receive.',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.blue[200] : Colors.blue[900],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _checkingPermissions
                              ? null
                              : _checkNotificationPermissions,
                          icon: _checkingPermissions
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.settings),
                          label: const Text('Check Permissions'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isDark
                                ? Colors.blue[300]
                                : Colors.blue[700],
                            side: BorderSide(
                              color: isDark
                                  ? Colors.blue[700]!
                                  : Colors.blue[300]!,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Notification Types Section
                Text(
                  'Notification Types',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 12),

                // Borrow Requests
                _buildNotificationToggle(
                  context: context,
                  title: 'Borrow Requests',
                  subtitle:
                      'Get notified when someone requests to borrow your items',
                  icon: Icons.shopping_cart_outlined,
                  value: prefsProvider.borrowRequests,
                  onChanged: (value) =>
                      prefsProvider.updateBorrowRequests(value),
                ),
                const SizedBox(height: 12),

                // Rental Requests
                _buildNotificationToggle(
                  context: context,
                  title: 'Rental Requests',
                  subtitle: 'Get notified about rental requests and updates',
                  icon: Icons.home_outlined,
                  value: prefsProvider.rentalRequests,
                  onChanged: (value) =>
                      prefsProvider.updateRentalRequests(value),
                ),
                const SizedBox(height: 12),

                // Trade Offers
                _buildNotificationToggle(
                  context: context,
                  title: 'Trade Offers',
                  subtitle: 'Get notified about trade offers and responses',
                  icon: Icons.swap_horiz_outlined,
                  value: prefsProvider.tradeOffers,
                  onChanged: (value) => prefsProvider.updateTradeOffers(value),
                ),
                const SizedBox(height: 12),

                // Donations
                _buildNotificationToggle(
                  context: context,
                  title: 'Donations & Giveaways',
                  subtitle:
                      'Get notified about new giveaways and donation opportunities',
                  icon: Icons.card_giftcard_outlined,
                  value: prefsProvider.donations,
                  onChanged: (value) => prefsProvider.updateDonations(value),
                ),
                const SizedBox(height: 12),

                // Messages
                _buildNotificationToggle(
                  context: context,
                  title: 'Messages',
                  subtitle: 'Get notified when you receive new messages',
                  icon: Icons.chat_bubble_outline,
                  value: prefsProvider.messages,
                  onChanged: (value) => prefsProvider.updateMessages(value),
                ),
                const SizedBox(height: 12),

                // Reminders
                _buildNotificationToggle(
                  context: context,
                  title: 'Reminders',
                  subtitle: 'Get reminders for due dates and returns',
                  icon: Icons.notifications_active_outlined,
                  value: prefsProvider.reminders,
                  onChanged: (value) => prefsProvider.updateReminders(value),
                ),
                const SizedBox(height: 12),

                // System Updates
                _buildNotificationToggle(
                  context: context,
                  title: 'System Updates',
                  subtitle:
                      'Important updates about your account and verification',
                  icon: Icons.info_outline,
                  value: prefsProvider.systemUpdates,
                  onChanged: (value) =>
                      prefsProvider.updateSystemUpdates(value),
                ),
                const SizedBox(height: 12),

                // Marketing (Optional)
                _buildNotificationToggle(
                  context: context,
                  title: 'Marketing & Promotions',
                  subtitle:
                      'Receive updates about new features and special offers',
                  icon: Icons.campaign_outlined,
                  value: prefsProvider.marketing,
                  onChanged: (value) => prefsProvider.updateMarketing(value),
                ),
                const SizedBox(height: 32),

                // Info Footer
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[800] : Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lightbulb_outline,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'You can still receive important system notifications even if some types are disabled. These settings help you control which activity notifications you want to see.',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.grey[400] : Colors.grey[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildNotificationToggle({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.grey[800]
                  : const Color(0xFF00897B).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: isDark ? Colors.grey[400] : const Color(0xFF00897B),
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF00897B),
          ),
        ],
      ),
    );
  }
}
