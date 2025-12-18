import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';

/// Helper class for checking user suspension status
class SuspensionHelper {
  /// Check if the current user is suspended
  /// Returns true if suspended, false otherwise
  static bool isSuspended(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    return userProvider.currentUser?.isSuspended == true;
  }

  /// Show a snackbar message if user is suspended
  /// Returns true if suspended, false otherwise
  static bool checkAndShowMessage(BuildContext context) {
    if (isSuspended(context)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Your account has been suspended. You cannot perform this action.',
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      return true;
    }
    return false;
  }

  /// Get suspension reason for current user
  static String? getSuspensionReason(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final reason = userProvider.currentUser?.suspensionReason;
    return reason?.isNotEmpty == true ? reason : null;
  }
}
