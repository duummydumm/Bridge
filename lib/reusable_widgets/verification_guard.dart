import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import 'verification_banner.dart';

/// Wrapper widget that checks admin verification before allowing access to protected features
/// Shows a banner and blocks actions if user is not verified
class VerificationGuard extends StatelessWidget {
  final Widget child;
  final bool showBanner;

  const VerificationGuard({
    super.key,
    required this.child,
    this.showBanner = true,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<UserProvider>(
      builder: (context, userProvider, _) {
        final user = userProvider.currentUser;
        final isVerified = user?.isVerified ?? false;

        if (showBanner && !isVerified) {
          return Column(
            children: [
              const VerificationBanner(),
              Expanded(child: child),
            ],
          );
        }
        return child;
      },
    );
  }

  /// Helper method to check if user is verified
  static bool isUserVerified(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    return userProvider.currentUser?.isVerified ?? false;
  }

  /// Show verification required message
  static void showVerificationMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Your account is pending admin verification. You can browse items but cannot post or transact yet.',
        ),
        backgroundColor: Colors.orange.shade700,
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
