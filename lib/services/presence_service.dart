import 'dart:async';
import 'firestore_service.dart';

class PresenceService {
  final FirestoreService _firestoreService = FirestoreService();
  Timer? _heartbeatTimer;
  String? _currentUserId;

  // Start updating user's presence (last seen) every minute
  void startPresenceTracking(String userId) {
    _currentUserId = userId;

    // Update immediately
    _firestoreService.updateUserLastSeen(userId);

    // Then update every minute to keep status fresh
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (_currentUserId != null) {
        _firestoreService.updateUserLastSeen(_currentUserId!);
      }
    });
  }

  // Stop tracking when user logs out or app closes
  void stopPresenceTracking() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _currentUserId = null;
  }

  // Check if user is online based on last seen (10 minutes threshold)
  bool isUserOnline(DateTime? lastSeen) {
    if (lastSeen == null) return false;
    final now = DateTime.now();
    final difference = now.difference(lastSeen);
    return difference.inMinutes < 10;
  }

  // Get formatted status text
  String getStatusText(DateTime? lastSeen) {
    if (isUserOnline(lastSeen)) {
      return 'Online';
    }
    if (lastSeen == null) {
      return 'Offline';
    }

    final now = DateTime.now();
    final difference = now.difference(lastSeen);

    if (difference.inMinutes < 60) {
      return 'Active ${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return 'Active ${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return 'Active ${difference.inDays}d ago';
    } else {
      return 'Offline';
    }
  }

  // Get stream of user's last seen status
  Stream<DateTime?> getUserLastSeenStream(String uid) {
    return _firestoreService.getUserLastSeenStream(uid);
  }
}
