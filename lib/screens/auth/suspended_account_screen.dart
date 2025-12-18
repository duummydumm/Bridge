import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';

/// Screen shown when a user's account is suspended
class SuspendedAccountScreen extends StatelessWidget {
  const SuspendedAccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Consumer<UserProvider>(
          builder: (context, userProvider, _) {
            final user = userProvider.currentUser;
            final suspensionReason = user?.suspensionReason ?? '';
            final suspendedAt = user?.suspendedAt;

            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.block, size: 80, color: Colors.red.shade700),
                  const SizedBox(height: 24),
                  Text(
                    'Account Suspended',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Your account has been suspended and you cannot access the app.',
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  if (suspensionReason.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Reason:',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red.shade900,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            suspensionReason,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: Colors.red.shade900),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (suspendedAt != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Suspended on: ${_formatDate(suspendedAt)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 32),
                  Text(
                    'If you believe this is an error, please contact support.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final authProvider = Provider.of<AuthProvider>(
                        context,
                        listen: false,
                      );
                      await authProvider.logout();
                      if (context.mounted) {
                        Navigator.of(context).pushReplacementNamed('/login');
                      }
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('Logout'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
