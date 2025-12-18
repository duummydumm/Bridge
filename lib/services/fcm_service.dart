import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, debugPrint;
import 'package:firebase_auth/firebase_auth.dart';
import 'local_notifications_service.dart';

/// Top-level function to handle background messages
/// Must be a top-level function, not a class method
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Handling background message: ${message.messageId}');
  debugPrint('Title: ${message.notification?.title}');
  debugPrint('Body: ${message.notification?.body}');
}

class FCMService {
  FCMService._internal();
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String? _currentToken;
  bool _initialized = false;

  /// Initialize FCM and get device token
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      if (kIsWeb) {
        // Web-specific initialization
        try {
          // Request notification permissions for web
          final settings = await _messaging.requestPermission(
            alert: true,
            badge: true,
            sound: true,
            provisional: false,
          );

          if (settings.authorizationStatus == AuthorizationStatus.authorized) {
            debugPrint('User granted notification permission (web)');
          } else {
            debugPrint(
              'User declined or has not accepted notification permission (web)',
            );
            _initialized = true;
            return;
          }

          // Get FCM token for web
          // The service worker will be automatically registered by Firebase Messaging
          final token = await _messaging.getToken();
          if (token != null) {
            _currentToken = token;
            debugPrint('FCM Token (web): $token');
            final user = FirebaseAuth.instance.currentUser;
            if (user != null) {
              await _saveTokenForUser(token, user.uid);
            } else {
              debugPrint(
                'No user logged in during initialization, cannot save token',
              );
            }
          }

          // Listen for token refresh on web
          _messaging.onTokenRefresh.listen((newToken) {
            _currentToken = newToken;
            debugPrint('FCM Token refreshed (web): $newToken');
            final user = FirebaseAuth.instance.currentUser;
            if (user != null) {
              _saveTokenForUser(newToken, user.uid);
            } else {
              debugPrint(
                'No user logged in during token refresh, cannot save token',
              );
            }
          });

          // Handle foreground messages on web
          FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
            debugPrint(
              'Received foreground message (web): ${message.messageId}',
            );
            debugPrint('Title: ${message.notification?.title}');
            debugPrint('Body: ${message.notification?.body}');
            // On web, notifications are handled by the browser's notification API
            // The service worker handles background messages
          });

          // Handle notification taps when app is in background (web)
          FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
            debugPrint('Notification opened app (web): ${message.messageId}');
          });

          // Check if app was opened from a notification (web)
          final initialMessage = await _messaging.getInitialMessage();
          if (initialMessage != null) {
            debugPrint(
              'App opened from notification (web): ${initialMessage.messageId}',
            );
          }

          _initialized = true;
        } catch (e) {
          debugPrint('Error initializing FCM for web: $e');
          _initialized =
              true; // Mark as initialized even on error to prevent retry loops
        }
        return;
      }

      // Mobile-specific initialization
      // Request notification permissions
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('User granted notification permission');
      } else if (settings.authorizationStatus ==
          AuthorizationStatus.provisional) {
        debugPrint('User granted provisional notification permission');
      } else {
        debugPrint('User declined or has not accepted notification permission');
        _initialized = true;
        return;
      }

      // Set up background message handler (mobile only)
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // Get FCM token
      final token = await _messaging.getToken();
      if (token != null) {
        _currentToken = token;
        debugPrint('FCM Token: $token');
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await _saveTokenForUser(token, user.uid);
        } else {
          debugPrint(
            'No user logged in during initialization, cannot save token',
          );
        }
      }

      // Listen for token refresh
      _messaging.onTokenRefresh.listen((newToken) {
        _currentToken = newToken;
        debugPrint('FCM Token refreshed: $newToken');
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          _saveTokenForUser(newToken, user.uid);
        } else {
          debugPrint(
            'No user logged in during token refresh, cannot save token',
          );
        }
      });

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
        debugPrint('Received foreground message: ${message.messageId}');
        debugPrint('Title: ${message.notification?.title}');
        debugPrint('Body: ${message.notification?.body}');

        // Show as local notification with custom icon
        if (message.notification != null) {
          await _showFCMAsLocalNotification(message);
        }
      });

      // Handle notification taps when app is in background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('Notification opened app: ${message.messageId}');
      });

      // Check if app was opened from a notification
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('App opened from notification: ${initialMessage.messageId}');
      }

      _initialized = true;
    } catch (e) {
      debugPrint('Error initializing FCM: $e');
      _initialized =
          true; // Mark as initialized even on error to prevent retry loops
    }
  }

  /// Get current FCM token
  String? get currentToken => _currentToken;

  /// Update FCM token for current user (call this when user logs in or switches accounts)
  Future<void> updateTokenForCurrentUser() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('No user logged in, cannot update FCM token');
        return;
      }

      final token = await _messaging.getToken();
      if (token != null) {
        _currentToken = token;
        debugPrint('FCM Token updated for user ${user.uid}: $token');
        // Use _saveTokenForUser to ensure it's saved for the correct user
        await _saveTokenForUser(token, user.uid);
        debugPrint('FCM Token saved successfully for user ${user.uid}');
      } else {
        debugPrint('Failed to get FCM token');
      }
    } catch (e) {
      debugPrint('Error updating FCM token: $e');
    }
  }

  /// Clear FCM token for a user (call this when user logs out)
  Future<void> clearTokenForUser(String userId) async {
    try {
      // Clear token from user's document
      await _db.collection('users').doc(userId).update({
        'fcmToken': FieldValue.delete(),
        'fcmTokenUpdatedAt': FieldValue.delete(),
      });

      // Clear token from fcm_tokens collection
      await _db.collection('fcm_tokens').doc(userId).delete();

      debugPrint('FCM token cleared for user: $userId');
    } catch (e) {
      debugPrint('Error clearing FCM token for user $userId: $e');
    }
  }

  /// Save FCM token to Firestore under a specific user's document
  Future<void> _saveTokenForUser(String token, String userId) async {
    try {
      // Save token to user's document
      await _db.collection('users').doc(userId).set({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Also save to a separate tokens collection for easier querying
      await _db.collection('fcm_tokens').doc(userId).set({
        'userId': userId,
        'token': token,
        'updatedAt': FieldValue.serverTimestamp(),
        'platform': defaultTargetPlatform.toString(),
      }, SetOptions(merge: true));

      debugPrint('FCM token saved to Firestore for user: $userId');
    } catch (e) {
      debugPrint('Error saving FCM token to Firestore for user $userId: $e');
    }
  }

  /// Save a reminder to Firestore for server-side scheduling
  Future<void> saveReminderToFirestore({
    required String reminderId,
    required String userId,
    required String itemId,
    required String itemTitle,
    required DateTime scheduledTime,
    required String title,
    required String body,
    required String
    reminderType, // '24h', '1h', 'due', 'overdue', 'nudge', 'rental_overdue'
    String? borrowerName,
    String? lenderName,
    bool isBorrower = true,
    String? rentalRequestId, // For rental reminders
    String? ownerName, // For rental reminders
    String? renterName, // For rental reminders
    String rentType = 'item', // For rental reminders - default to 'item'
  }) async {
    try {
      final reminderData = {
        'userId': userId,
        'itemId': itemId,
        'itemTitle': itemTitle,
        'scheduledTime': Timestamp.fromDate(scheduledTime),
        'title': title,
        'body': body,
        'reminderType': reminderType,
        'borrowerName': borrowerName,
        'lenderName': lenderName,
        'isBorrower': isBorrower,
        'sent': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Add rental-specific fields if provided
      if (rentalRequestId != null) {
        reminderData['rentalRequestId'] = rentalRequestId;
        // Always include rentType for rental reminders
        reminderData['rentType'] = rentType;
      }
      if (ownerName != null) {
        reminderData['ownerName'] = ownerName;
      }
      if (renterName != null) {
        reminderData['renterName'] = renterName;
      }

      await _db.collection('reminders').doc(reminderId).set(reminderData);
      debugPrint('Reminder saved to Firestore: $reminderId');
    } catch (e) {
      debugPrint('Error saving reminder to Firestore: $e');
      rethrow;
    }
  }

  /// Cancel/delete a reminder from Firestore
  Future<void> cancelReminderFromFirestore(String reminderId) async {
    try {
      await _db.collection('reminders').doc(reminderId).delete();
      debugPrint('Reminder cancelled in Firestore: $reminderId');
    } catch (e) {
      debugPrint('Error cancelling reminder from Firestore: $e');
    }
  }

  /// Cancel all reminders for a specific item
  Future<void> cancelAllRemindersForItem(String itemId) async {
    try {
      final reminders = await _db
          .collection('reminders')
          .where('itemId', isEqualTo: itemId)
          .where('sent', isEqualTo: false)
          .get();

      final batch = _db.batch();
      for (final doc in reminders.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      debugPrint(
        'Cancelled ${reminders.docs.length} reminders for item: $itemId',
      );
    } catch (e) {
      debugPrint('Error cancelling reminders for item: $e');
    }
  }

  /// Build reminder ID from itemId and reminder type
  String buildReminderId(String itemId, String reminderType) {
    return '${itemId}_$reminderType';
  }

  /// Show FCM message as a local notification with custom icon
  /// This ensures all notifications use the same custom icon
  Future<void> _showFCMAsLocalNotification(RemoteMessage message) async {
    if (kIsWeb) return;

    try {
      final localNotifications = LocalNotificationsService();
      await localNotifications.initialize();

      final notification = message.notification;
      if (notification == null) return;

      // Determine channel based on notification type or data
      String channelId = 'borrow_requests';
      String channelName = 'Borrow Requests';
      String channelDescription = 'Notifications for new borrow requests';

      final data = message.data;
      final notificationType = data['type'] as String?;

      if (notificationType == 'borrow_request') {
        channelId = 'borrow_requests';
        channelName = 'Borrow Requests';
        channelDescription = 'Notifications for new borrow requests';
      } else if (notificationType == 'rent_request') {
        channelId = 'rental_requests';
        channelName = 'Rental Requests';
        channelDescription = 'Notifications for new rental requests';
      } else if (notificationType == 'reminder') {
        final reminderType = data['reminderType'] as String?;
        if (reminderType == 'overdue') {
          channelId = 'overdue_reminders';
          channelName = 'Overdue Reminders';
          channelDescription = 'Reminders for overdue items';
        } else if (reminderType == 'rental_overdue') {
          channelId = 'rental_overdue_reminders';
          channelName = 'Rental Overdue Reminders';
          channelDescription = 'Reminders for overdue rentals';
        } else if (reminderType != null && reminderType.startsWith('rental_')) {
          // Handle rental_24h, rental_1h, rental_due
          channelId = 'rental_reminders';
          channelName = 'Rental Reminders';
          channelDescription = 'Reminders for rental periods';
        } else {
          channelId = 'due_reminders';
          channelName = 'Due Reminders';
          channelDescription = 'Reminders for upcoming and due returns';
        }
      } else {
        // Check channelId from Android notification payload (fallback)
        final androidChannelId = message.notification?.android?.channelId;
        if (androidChannelId != null) {
          channelId = androidChannelId;
          if (androidChannelId == 'overdue_reminders') {
            channelName = 'Overdue Reminders';
            channelDescription = 'Reminders for overdue items';
          } else if (androidChannelId == 'due_reminders') {
            channelName = 'Due Reminders';
            channelDescription = 'Reminders for upcoming and due returns';
          } else if (androidChannelId == 'rental_overdue_reminders') {
            channelName = 'Rental Overdue Reminders';
            channelDescription = 'Reminders for overdue rentals';
          } else if (androidChannelId == 'rental_reminders') {
            channelName = 'Rental Reminders';
            channelDescription = 'Reminders for rental periods';
          } else if (androidChannelId == 'rental_requests') {
            channelName = 'Rental Requests';
            channelDescription = 'Notifications for new rental requests';
          }
        }
      }

      // Generate a unique ID from message ID or timestamp
      final notificationId =
          message.messageId?.hashCode ??
          DateTime.now().millisecondsSinceEpoch % 1000000;

      // Show the notification using local notifications service
      // We'll need to add a method to show immediate notifications
      await localNotifications.showNotification(
        id: notificationId,
        title: notification.title ?? 'Notification',
        body: notification.body ?? '',
        channelId: channelId,
        channelName: channelName,
        channelDescription: channelDescription,
      );
    } catch (e) {
      debugPrint('Error showing FCM as local notification: $e');
    }
  }
}
