import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firestore_service.dart';
import 'fcm_service.dart';

class LocalNotificationsService {
  LocalNotificationsService._internal();
  static final LocalNotificationsService _instance =
      LocalNotificationsService._internal();
  factory LocalNotificationsService() => _instance;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    // Skip for web where flutter_local_notifications isn't supported
    if (kIsWeb) {
      _initialized = true;
      return;
    }
    // Timezone init
    tz.initializeTimeZones();
    final String localName = await tz.local.name;
    tz.setLocalLocation(tz.getLocation(localName));

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );
    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      macOS: iosSettings,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    // Create channels for Android
    const AndroidNotificationChannel dueChannel = AndroidNotificationChannel(
      'due_reminders',
      'Due Reminders',
      description: 'Reminders for upcoming and due returns',
      importance: Importance.high,
    );
    const AndroidNotificationChannel overdueChannel =
        AndroidNotificationChannel(
          'overdue_reminders',
          'Overdue Reminders',
          description: 'Reminders for overdue items',
          importance: Importance.max,
        );
    const AndroidNotificationChannel borrowRequestsChannel =
        AndroidNotificationChannel(
          'borrow_requests',
          'Borrow Requests',
          description: 'Notifications for new borrow requests',
          importance: Importance.high,
        );
    const AndroidNotificationChannel rentalRequestsChannel =
        AndroidNotificationChannel(
          'rental_requests',
          'Rental Requests',
          description: 'Notifications for new rental requests',
          importance: Importance.high,
        );
    const AndroidNotificationChannel rentalChannel = AndroidNotificationChannel(
      'rental_reminders',
      'Rental Reminders',
      description: 'Reminders for rental periods',
      importance: Importance.high,
    );
    const AndroidNotificationChannel rentalOverdueChannel =
        AndroidNotificationChannel(
          'rental_overdue_reminders',
          'Rental Overdue Reminders',
          description: 'Reminders for overdue rentals',
          importance: Importance.max,
        );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(dueChannel);
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(overdueChannel);
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(borrowRequestsChannel);
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(rentalRequestsChannel);
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(rentalChannel);
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(rentalOverdueChannel);

    _initialized = true;
  }

  /// Check if notification permissions are granted
  Future<bool> areNotificationsEnabled() async {
    if (kIsWeb) return false;
    await initialize();

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidPlugin != null) {
      // Request notification permission (Android 13+)
      final granted = await androidPlugin.requestNotificationsPermission();

      // Request exact alarms permission (Android 12+)
      // This helps with scheduling exact notifications
      try {
        await androidPlugin.requestExactAlarmsPermission();
      } catch (e) {
        // Ignore if not available or already granted
        debugPrint('Could not request exact alarms permission: $e');
      }

      return granted ?? false;
    }

    // For iOS
    final iosPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (iosPlugin != null) {
      return await iosPlugin.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }

    return false;
  }

  /// Request notification permissions
  Future<bool> requestPermissions() async {
    if (kIsWeb) return false;
    await initialize();
    return await areNotificationsEnabled();
  }

  // Build IDs derived from an itemId and offset kind to avoid duplicates
  int _buildId(String itemId, int kind) {
    // kind: 0=24h, 1=1h, 2=due, 4=overdue_daily
    final hash = itemId.hashCode & 0x7fffffff; // positive
    return (hash % 1000000) * 10 + (kind % 10);
  }

  /// Schedule a local notification that works offline
  /// This is independent of Firestore/FCM and works without internet
  Future<void> _scheduleLocalNotification({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required String channelId,
    required String channelName,
    required String channelDescription,
    Importance importance = Importance.high,
    Priority priority = Priority.high,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    if (kIsWeb) return;

    final now = tz.TZDateTime.now(tz.local);

    // Validate scheduled time is in the future
    if (scheduledDate.isBefore(now)) {
      debugPrint(
        'Cannot schedule notification in the past: $scheduledDate (current: $now)',
      );
      return;
    }

    await initialize();

    // Ensure notification channel exists (Android)
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        AndroidNotificationChannel(
          channelId,
          channelName,
          description: channelDescription,
          importance: importance,
        ),
      );
    }

    final NotificationDetails details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        priority: priority,
        importance: importance,
        enableVibration: true,
        playSound: true,
        icon: '@drawable/ic_stat_bridge',
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
      macOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    try {
      // Try with exact alarms first
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: matchDateTimeComponents,
      );
      final timeUntil = scheduledDate.difference(now);
      debugPrint(
        '✅ Local notification scheduled (EXACT): $title at $scheduledDate (ID: $id)',
      );
      debugPrint(
        '   Time until notification: ${timeUntil.inMinutes} minutes ${timeUntil.inSeconds % 60} seconds',
      );
      debugPrint(
        '   ⚠️  NOTE: Some devices may block scheduled notifications due to battery optimization.',
      );
      debugPrint(
        '   If notification doesn\'t fire, check: Settings > Apps > Bridge > Battery > Unrestricted',
      );
    } catch (e) {
      // If exact alarms fail, fall back to inexact alarms
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('exact_alarms_not_permitted') ||
          errorStr.contains('exact alarms are not permitted') ||
          errorStr.contains('schedule_exact_alarm')) {
        debugPrint(
          '⚠️  Exact alarms not permitted, falling back to inexact alarms',
        );
        debugPrint('   Error: $e');
        try {
          await _plugin.zonedSchedule(
            id,
            title,
            body,
            scheduledDate,
            details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            matchDateTimeComponents: matchDateTimeComponents,
          );
          final timeUntil = scheduledDate.difference(now);
          debugPrint(
            '✅ Local notification scheduled (INEXACT): $title at $scheduledDate (ID: $id)',
          );
          debugPrint(
            '   Time until notification: ${timeUntil.inMinutes} minutes ${timeUntil.inSeconds % 60} seconds',
          );
          debugPrint(
            '   ⚠️  INEXACT alarms may be delayed by the system for battery optimization.',
          );
        } catch (e2) {
          debugPrint('❌ Failed to schedule local notification (inexact): $e2');
          debugPrint(
            '   This device may have aggressive battery optimization that blocks scheduled notifications.',
          );
          // Don't rethrow - local notification failure shouldn't break the app
        }
      } else {
        debugPrint('❌ Failed to schedule local notification: $e');
        debugPrint(
          '   This device may have aggressive battery optimization that blocks scheduled notifications.',
        );
        // Don't rethrow - local notification failure shouldn't break the app
      }
    }
  }

  Future<void> scheduleReturnReminders({
    required String itemId,
    required String itemTitle,
    required DateTime returnDateLocal,
    required String borrowerName,
    required String
    borrowerId, // ID of the borrower who should receive reminders
  }) async {
    // Ensure timezone is initialized (needed for timezone operations on mobile)
    if (!_initialized && !kIsWeb) {
      await initialize();
    }

    // For date calculations, use regular DateTime (works on both web and mobile)
    final DateTime due = returnDateLocal;
    final DateTime before24h = due.subtract(const Duration(hours: 24));
    final DateTime before1h = due.subtract(const Duration(hours: 1));
    final DateTime now = DateTime.now();

    // Check if return date is tomorrow (next calendar day)
    // If so, schedule a reminder for today
    final todayStart = DateTime(now.year, now.month, now.day, 0, 0);
    final tomorrowStart = todayStart.add(const Duration(days: 1));
    final dayAfterTomorrowStart = tomorrowStart.add(const Duration(days: 1));

    // Check if return date falls within tomorrow (next calendar day)
    final isTomorrow =
        due.isAfter(tomorrowStart.subtract(const Duration(seconds: 1))) &&
        due.isBefore(dayAfterTomorrowStart);

    debugPrint(
      'scheduleReturnReminders: returnDate=$returnDateLocal, '
      'due=$due, now=$now, isTomorrow=$isTomorrow',
    );

    // Schedule local notifications (works offline) - skip on web
    if (!kIsWeb) {
      // If return date is tomorrow, always schedule a reminder for today
      // Schedule it for 2 minutes from now to ensure backend processes it
      if (isTomorrow) {
        final todayReminder = now.add(const Duration(minutes: 2));
        debugPrint(
          'scheduleReturnReminders: Scheduling tomorrow reminder for $todayReminder',
        );

        // Convert to TZDateTime for local notification (mobile only)
        final todayReminderTz = tz.TZDateTime.from(todayReminder, tz.local);
        await _scheduleLocalNotification(
          id: _buildId(itemId, 4), // kind: 4=tomorrow reminder (use unique ID)
          title: 'Return reminder: $itemTitle',
          body: 'Please return "$itemTitle" to $borrowerName by tomorrow.',
          scheduledDate: todayReminderTz,
          channelId: 'due_reminders',
          channelName: 'Due Reminders',
          channelDescription: 'Reminders for upcoming and due returns',
          importance: Importance.high,
          priority: Priority.high,
        );
      }

      // 24h before (only if return date is NOT tomorrow, to avoid duplicates)
      if (before24h.isAfter(now) && !isTomorrow) {
        final before24hTz = tz.TZDateTime.from(before24h, tz.local);
        await _scheduleLocalNotification(
          id: _buildId(itemId, 0), // kind: 0=24h
          title: 'Return reminder (24h): $itemTitle',
          body: 'Please return "$itemTitle" to $borrowerName by tomorrow.',
          scheduledDate: before24hTz,
          channelId: 'due_reminders',
          channelName: 'Due Reminders',
          channelDescription: 'Reminders for upcoming and due returns',
          importance: Importance.high,
          priority: Priority.high,
        );
      }

      // 1h before
      if (before1h.isAfter(now)) {
        final before1hTz = tz.TZDateTime.from(before1h, tz.local);
        await _scheduleLocalNotification(
          id: _buildId(itemId, 1), // kind: 1=1h
          title: 'Return reminder (1h): $itemTitle',
          body: 'One hour left before "$itemTitle" is due.',
          scheduledDate: before1hTz,
          channelId: 'due_reminders',
          channelName: 'Due Reminders',
          channelDescription: 'Reminders for upcoming and due returns',
          importance: Importance.high,
          priority: Priority.high,
        );
      }

      // At due time
      if (due.isAfter(now)) {
        final dueTz = tz.TZDateTime.from(due, tz.local);
        await _scheduleLocalNotification(
          id: _buildId(itemId, 2), // kind: 2=due
          title: 'Due now: $itemTitle',
          body: '"$itemTitle" is now due for return.',
          scheduledDate: dueTz,
          channelId: 'due_reminders',
          channelName: 'Due Reminders',
          channelDescription: 'Reminders for upcoming and due returns',
          importance: Importance.high,
          priority: Priority.high,
        );
      }
    }

    // Also save reminders to Firestore for FCM push notifications (if online)
    // This is a backup/redundancy - local notifications work offline
    try {
      final fcmService = FCMService();
      await fcmService.initialize();

      // If return date is tomorrow, schedule FCM reminder for today
      if (isTomorrow) {
        final todayReminder = now.add(const Duration(minutes: 2));
        // Use unique reminder ID for tomorrow reminder - use borrowerId, not current user
        final reminderId = '${itemId}_tomorrow_${borrowerId}';
        await fcmService.saveReminderToFirestore(
          reminderId: reminderId,
          userId: borrowerId, // Send to borrower, not lender
          itemId: itemId,
          itemTitle: itemTitle,
          scheduledTime: todayReminder.toUtc(),
          title: 'Return reminder: $itemTitle',
          body: 'Please return "$itemTitle" to $borrowerName by tomorrow.',
          reminderType: '24h',
          borrowerName: borrowerName,
          isBorrower: true,
        );
        debugPrint(
          'scheduleReturnReminders: Saved FCM reminder for borrower $borrowerId, scheduled for $todayReminder',
        );
      }

      // 24h before (only if return date is NOT tomorrow, to avoid duplicates)
      if (before24h.isAfter(now) && !isTomorrow) {
        // Include userId in reminder ID to avoid conflicts and permission issues
        final reminderId = '${itemId}_24h_${borrowerId}';
        await fcmService.saveReminderToFirestore(
          reminderId: reminderId,
          userId: borrowerId, // Send to borrower, not lender
          itemId: itemId,
          itemTitle: itemTitle,
          scheduledTime: before24h.toUtc(),
          title: 'Return reminder (24h): $itemTitle',
          body: 'Please return "$itemTitle" to $borrowerName by tomorrow.',
          reminderType: '24h',
          borrowerName: borrowerName,
          isBorrower: true,
        );
      }

      // 1h before
      if (before1h.isAfter(now)) {
        // Include userId in reminder ID to avoid conflicts and permission issues
        final reminderId = '${itemId}_1h_${borrowerId}';
        await fcmService.saveReminderToFirestore(
          reminderId: reminderId,
          userId: borrowerId, // Send to borrower, not lender
          itemId: itemId,
          itemTitle: itemTitle,
          scheduledTime: before1h.toUtc(),
          title: 'Return reminder (1h): $itemTitle',
          body: 'One hour left before "$itemTitle" is due.',
          reminderType: '1h',
          borrowerName: borrowerName,
          isBorrower: true,
        );
      }

      // At due time
      if (due.isAfter(now)) {
        // Include userId in reminder ID to avoid conflicts and permission issues
        final reminderId = '${itemId}_due_${borrowerId}';
        await fcmService.saveReminderToFirestore(
          reminderId: reminderId,
          userId: borrowerId, // Send to borrower, not lender
          itemId: itemId,
          itemTitle: itemTitle,
          scheduledTime: due.toUtc(),
          title: 'Due now: $itemTitle',
          body: '"$itemTitle" is now due for return.',
          reminderType: 'due',
          borrowerName: borrowerName,
          isBorrower: true,
        );
      }
    } catch (e) {
      // Firestore/FCM failure is okay - local notifications will still work
      debugPrint('Could not save reminders to Firestore (offline?): $e');
    }
  }

  /// Schedule reminders for rental end date (for both renter and owner)
  Future<void> scheduleRentalEndReminders({
    required String rentalRequestId,
    required String itemId,
    required String itemTitle,
    required DateTime endDateLocal,
    required String renterId,
    required String ownerId,
    required String renterName,
    required String ownerName,
    String rentType = 'item', // Default to 'item' for backward compatibility
  }) async {
    // Ensure timezone is initialized (needed for timezone operations on mobile)
    if (!_initialized && !kIsWeb) {
      await initialize();
    }

    // For date calculations, use regular DateTime (works on both web and mobile)
    final DateTime due = endDateLocal;
    final DateTime before24h = due.subtract(const Duration(hours: 24));
    final DateTime before1h = due.subtract(const Duration(hours: 1));
    final DateTime now = DateTime.now();

    // Check if end date is tomorrow (next calendar day)
    // If so, schedule a reminder for today (for demo purposes)
    final todayStart = DateTime(now.year, now.month, now.day, 0, 0);
    final tomorrowStart = todayStart.add(const Duration(days: 1));
    final dayAfterTomorrowStart = tomorrowStart.add(const Duration(days: 1));

    // Check if end date falls within tomorrow (next calendar day)
    final isTomorrow =
        due.isAfter(tomorrowStart.subtract(const Duration(seconds: 1))) &&
        due.isBefore(dayAfterTomorrowStart);

    debugPrint(
      'scheduleRentalEndReminders: endDate=$endDateLocal, '
      'due=$due, now=$now, isTomorrow=$isTomorrow',
    );

    // Schedule reminders for RENTER
    // If end date is tomorrow, schedule reminder for today (2 minutes from now for demo)
    if (isTomorrow) {
      final todayReminder = now.add(const Duration(minutes: 2));
      debugPrint(
        'scheduleRentalEndReminders: Scheduling tomorrow reminder for renter at $todayReminder',
      );

      // Use unique reminder ID for tomorrow reminder to avoid conflicts
      final tomorrowReminderId =
          'rental_${rentalRequestId}_tomorrow_${renterId}';

      // Schedule local notification (skip on web)
      if (!kIsWeb) {
        final localNotificationId = _buildId(tomorrowReminderId, 0);
        final todayReminderTz = tz.TZDateTime.from(todayReminder, tz.local);
        await _scheduleLocalNotification(
          id: localNotificationId,
          title: 'Rental ending soon: $itemTitle',
          body:
              'Your rental of "$itemTitle" ends tomorrow. Please prepare to return it.',
          scheduledDate: todayReminderTz,
          channelId: 'rental_reminders',
          channelName: 'Rental Reminders',
          channelDescription: 'Reminders for rental periods',
          importance: Importance.high,
          priority: Priority.high,
        );
      }

      // Save to Firestore for FCM
      try {
        final fcmService = FCMService();
        await fcmService.initialize();
        await fcmService.saveReminderToFirestore(
          reminderId: tomorrowReminderId,
          userId: renterId,
          itemId: itemId,
          itemTitle: itemTitle,
          scheduledTime: todayReminder.toUtc(),
          title: 'Rental ending soon: $itemTitle',
          body:
              'Your rental of "$itemTitle" ends tomorrow. Please prepare to return it.',
          reminderType: 'rental_24h',
          isBorrower: true,
          rentalRequestId: rentalRequestId,
          ownerName: ownerName,
          renterName: renterName,
          rentType: rentType,
        );
        debugPrint(
          'scheduleRentalEndReminders: Saved FCM reminder for renter $renterId, scheduled for $todayReminder',
        );
      } catch (e) {
        debugPrint(
          'Could not save rental tomorrow reminder to Firestore (offline?): $e',
        );
      }
    }

    // 24h before (only if end date is NOT tomorrow, to avoid duplicates)
    if (before24h.isAfter(now) && !isTomorrow) {
      final before24hTz = !kIsWeb
          ? tz.TZDateTime.from(before24h, tz.local)
          : null;
      if (before24hTz != null) {
        await _scheduleRentalReminderForUser(
          rentalRequestId: rentalRequestId,
          itemId: itemId,
          itemTitle: itemTitle,
          scheduledTime: before24hTz,
          userId: renterId,
          userName: renterName,
          isRenter: true,
          reminderType: 'rental_24h',
          title: 'Rental ending soon (24h): $itemTitle',
          body:
              'Your rental of "$itemTitle" ends tomorrow. Please prepare to return it.',
          renterName: renterName,
          ownerName: ownerName,
          rentType: rentType,
        );
      }
    }

    // 1h before
    if (before1h.isAfter(now)) {
      final before1hTz = !kIsWeb
          ? tz.TZDateTime.from(before1h, tz.local)
          : null;
      if (before1hTz != null) {
        await _scheduleRentalReminderForUser(
          rentalRequestId: rentalRequestId,
          itemId: itemId,
          itemTitle: itemTitle,
          scheduledTime: before1hTz,
          userId: renterId,
          userName: renterName,
          isRenter: true,
          reminderType: 'rental_1h',
          title: 'Rental ending soon (1h): $itemTitle',
          body:
              'Your rental of "$itemTitle" ends in 1 hour. Please return it soon.',
          renterName: renterName,
          ownerName: ownerName,
          rentType: rentType,
        );
      }
    }

    // At end date
    if (due.isAfter(now)) {
      final dueTz = !kIsWeb ? tz.TZDateTime.from(due, tz.local) : null;
      if (dueTz != null) {
        await _scheduleRentalReminderForUser(
          rentalRequestId: rentalRequestId,
          itemId: itemId,
          itemTitle: itemTitle,
          scheduledTime: dueTz,
          userId: renterId,
          userName: renterName,
          isRenter: true,
          reminderType: 'rental_due',
          title: 'Rental period ended: $itemTitle',
          body: 'Your rental of "$itemTitle" has ended. Please return it now.',
          renterName: renterName,
          ownerName: ownerName,
          rentType: rentType,
        );
      }
    }

    // Schedule reminders for OWNER
    // If end date is tomorrow, schedule reminder for today (2 minutes from now for demo)
    if (isTomorrow) {
      final todayReminder = now.add(const Duration(minutes: 2));
      debugPrint(
        'scheduleRentalEndReminders: Scheduling tomorrow reminder for owner at $todayReminder',
      );

      // Use unique reminder ID for tomorrow reminder to avoid conflicts
      final tomorrowReminderId =
          'rental_${rentalRequestId}_tomorrow_${ownerId}';

      // Schedule local notification (skip on web)
      if (!kIsWeb) {
        final localNotificationId = _buildId(tomorrowReminderId, 0);
        final todayReminderTz = tz.TZDateTime.from(todayReminder, tz.local);
        await _scheduleLocalNotification(
          id: localNotificationId,
          title: 'Rental ending soon: $itemTitle',
          body: 'Rental of "$itemTitle" by $renterName ends tomorrow.',
          scheduledDate: todayReminderTz,
          channelId: 'rental_reminders',
          channelName: 'Rental Reminders',
          channelDescription: 'Reminders for rental periods',
          importance: Importance.high,
          priority: Priority.high,
        );
      }

      // Save to Firestore for FCM
      try {
        final fcmService = FCMService();
        await fcmService.initialize();
        await fcmService.saveReminderToFirestore(
          reminderId: tomorrowReminderId,
          userId: ownerId,
          itemId: itemId,
          itemTitle: itemTitle,
          scheduledTime: todayReminder.toUtc(),
          title: 'Rental ending soon: $itemTitle',
          body: 'Rental of "$itemTitle" by $renterName ends tomorrow.',
          reminderType: 'rental_24h',
          isBorrower: false,
          rentalRequestId: rentalRequestId,
          ownerName: ownerName,
          renterName: renterName,
          rentType: rentType,
        );
        debugPrint(
          'scheduleRentalEndReminders: Saved FCM reminder for owner $ownerId, scheduled for $todayReminder',
        );
      } catch (e) {
        debugPrint(
          'Could not save rental tomorrow reminder to Firestore (offline?): $e',
        );
      }
    }

    // 24h before (only if end date is NOT tomorrow, to avoid duplicates)
    if (before24h.isAfter(now) && !isTomorrow) {
      final before24hTz = !kIsWeb
          ? tz.TZDateTime.from(before24h, tz.local)
          : null;
      if (before24hTz != null) {
        await _scheduleRentalReminderForUser(
          rentalRequestId: rentalRequestId,
          itemId: itemId,
          itemTitle: itemTitle,
          scheduledTime: before24hTz,
          userId: ownerId,
          userName: ownerName,
          isRenter: false,
          reminderType: 'rental_24h',
          title: 'Rental ending soon (24h): $itemTitle',
          body: 'Rental of "$itemTitle" by $renterName ends tomorrow.',
          renterName: renterName,
          ownerName: ownerName,
          rentType: rentType,
        );
      }
    }

    // 1h before
    if (before1h.isAfter(now)) {
      final before1hTz = !kIsWeb
          ? tz.TZDateTime.from(before1h, tz.local)
          : null;
      if (before1hTz != null) {
        await _scheduleRentalReminderForUser(
          rentalRequestId: rentalRequestId,
          itemId: itemId,
          itemTitle: itemTitle,
          scheduledTime: before1hTz,
          userId: ownerId,
          userName: ownerName,
          isRenter: false,
          reminderType: 'rental_1h',
          title: 'Rental ending soon (1h): $itemTitle',
          body: 'Rental of "$itemTitle" by $renterName ends in 1 hour.',
          renterName: renterName,
          ownerName: ownerName,
          rentType: rentType,
        );
      }
    }

    // At end date
    if (due.isAfter(now)) {
      final dueTz = !kIsWeb ? tz.TZDateTime.from(due, tz.local) : null;
      if (dueTz != null) {
        await _scheduleRentalReminderForUser(
          rentalRequestId: rentalRequestId,
          itemId: itemId,
          itemTitle: itemTitle,
          scheduledTime: dueTz,
          userId: ownerId,
          userName: ownerName,
          isRenter: false,
          reminderType: 'rental_due',
          title: 'Rental period ended: $itemTitle',
          body:
              'Rental of "$itemTitle" by $renterName has ended. Expect return soon.',
          renterName: renterName,
          ownerName: ownerName,
          rentType: rentType,
        );
      }
    }
  }

  /// Helper method to schedule a rental reminder for a specific user
  Future<void> _scheduleRentalReminderForUser({
    required String rentalRequestId,
    required String itemId,
    required String itemTitle,
    required tz.TZDateTime scheduledTime,
    required String userId,
    required String userName,
    required bool isRenter,
    required String reminderType,
    required String title,
    required String body,
    String? renterName,
    String? ownerName,
    String rentType = 'item', // Default to 'item' for backward compatibility
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Build unique reminder ID: rental_{requestId}_{reminderType}_{userId}
    final reminderId = 'rental_${rentalRequestId}_${reminderType}_$userId';

    // Schedule local notification (skip on web)
    if (!kIsWeb) {
      final localNotificationId = _buildId(reminderId, 0);
      await _scheduleLocalNotification(
        id: localNotificationId,
        title: title,
        body: body,
        scheduledDate: scheduledTime,
        channelId: 'rental_reminders',
        channelName: 'Rental Reminders',
        channelDescription: 'Reminders for rental periods',
        importance: Importance.high,
        priority: Priority.high,
      );
    }

    // Save to Firestore for FCM (works on both web and mobile)
    try {
      final fcmService = FCMService();
      await fcmService.initialize();
      await fcmService.saveReminderToFirestore(
        reminderId: reminderId,
        userId: userId,
        itemId: itemId,
        itemTitle: itemTitle,
        scheduledTime: scheduledTime.toUtc(),
        title: title,
        body: body,
        reminderType: reminderType,
        isBorrower: isRenter,
        rentalRequestId: rentalRequestId,
        ownerName: isRenter ? ownerName : null,
        renterName: isRenter ? null : renterName,
        rentType: rentType,
      );
    } catch (e) {
      debugPrint('Could not save rental reminder to Firestore (offline?): $e');
    }
  }

  /// Cancel all reminders for a rental request
  Future<void> cancelRentalReminders(String rentalRequestId) async {
    if (kIsWeb) return;
    await initialize();

    // Cancel reminders from Firestore (if online)
    try {
      // Query reminders for this rental request
      final reminders = await FirebaseFirestore.instance
          .collection('reminders')
          .where('rentalRequestId', isEqualTo: rentalRequestId)
          .where('sent', isEqualTo: false)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in reminders.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      debugPrint(
        'Could not cancel rental reminders from Firestore (offline?): $e',
      );
    }
  }

  /// Schedule overdue reminders for rental (daily recurring when end date passes)
  Future<void> scheduleRentalOverdueReminders({
    required String rentalRequestId,
    required String itemId,
    required String itemTitle,
    required DateTime endDateLocal,
    required String renterId,
    required String ownerId,
    required String renterName,
    required String ownerName,
    required bool
    isRenter, // true if notification is for renter, false for owner
    String? targetUserId, // ID of the user who should receive the notification
    String rentType = 'item', // Default to 'item' for backward compatibility
  }) async {
    if (kIsWeb) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('No user logged in, cannot schedule overdue reminders');
      return;
    }

    // Determine the target user ID - use provided targetUserId or default to current user
    final String recipientUserId = targetUserId ?? user.uid;

    final now = tz.TZDateTime.now(tz.local);
    final endDate = tz.TZDateTime.from(endDateLocal, tz.local);

    // Only schedule if rental is actually overdue
    if (endDate.isAfter(now)) {
      return; // Not overdue yet
    }

    // Calculate days overdue
    final daysOverdue = now.difference(endDate).inDays;

    // Schedule daily recurring notification at 9 AM
    // If rental is already overdue, schedule immediately (or very soon) so notification fires right away
    // Otherwise, schedule for 9 AM today (or tomorrow if past 9 AM)
    final nextNotification = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      9, // 9 AM
    );

    // If rental is already overdue, schedule for immediate notification (current time)
    // This ensures overdue rentals get notified right away, not waiting until 9 AM
    final scheduledTime = daysOverdue > 0 && nextNotification.isBefore(now)
        ? now.add(
            const Duration(minutes: 1),
          ) // Schedule 1 minute from now for immediate notification
        : (nextNotification.isBefore(now)
              ? nextNotification.add(const Duration(days: 1))
              : nextNotification);

    String title;
    String body;
    if (isRenter) {
      title = '⚠️ Rental Overdue: $itemTitle';
      if (daysOverdue == 0) {
        body =
            'Your rental of "$itemTitle" is due today. Please return it to $ownerName.';
      } else if (daysOverdue == 1) {
        body =
            'Your rental of "$itemTitle" is 1 day overdue. Please return it to $ownerName.';
      } else {
        body =
            'Your rental of "$itemTitle" is $daysOverdue days overdue. Please return it to $ownerName.';
      }
    } else {
      title = '⚠️ Rental Overdue: $itemTitle';
      if (daysOverdue == 0) {
        body = 'The rental of "$itemTitle" by $renterName is due today.';
      } else if (daysOverdue == 1) {
        body = 'The rental of "$itemTitle" by $renterName is 1 day overdue.';
      } else {
        body =
            'The rental of "$itemTitle" by $renterName is $daysOverdue days overdue.';
      }
    }

    // Build unique reminder ID: rental_{requestId}_overdue_{userId}
    final reminderId = 'rental_${rentalRequestId}_overdue_$recipientUserId';
    final localNotificationId = _buildId(reminderId, 0);

    // Schedule local recurring notification (works offline)
    // Use DateTimeComponents.time to make it recur daily at the same time
    await _scheduleLocalNotification(
      id: localNotificationId,
      title: title,
      body: body,
      scheduledDate: scheduledTime,
      channelId: 'rental_overdue_reminders',
      channelName: 'Rental Overdue Reminders',
      channelDescription: 'Reminders for overdue rentals',
      importance: Importance.max,
      priority: Priority.max,
      matchDateTimeComponents: DateTimeComponents.time, // Recur daily at 9 AM
    );

    // Also save to Firestore for FCM (if online)
    try {
      final fcmService = FCMService();
      await fcmService.initialize();
      await fcmService.saveReminderToFirestore(
        reminderId: reminderId,
        userId: recipientUserId,
        itemId: itemId,
        itemTitle: itemTitle,
        scheduledTime: scheduledTime.toUtc(),
        title: title,
        body: body,
        reminderType: 'rental_overdue',
        isBorrower: isRenter,
        rentalRequestId: rentalRequestId,
        ownerName: isRenter ? ownerName : null,
        renterName: isRenter ? null : renterName,
        rentType: rentType,
      );
    } catch (e) {
      debugPrint(
        'Could not save rental overdue reminder to Firestore (offline?): $e',
      );
    }
  }

  /// Cancel overdue reminders for a rental
  Future<void> cancelRentalOverdueReminders(
    String rentalRequestId, {
    String? userId,
  }) async {
    if (kIsWeb) return;
    await initialize();

    // Cancel local notification
    final reminderId = userId != null
        ? 'rental_${rentalRequestId}_overdue_$userId'
        : 'rental_${rentalRequestId}_overdue';
    await _plugin.cancel(_buildId(reminderId, 0));

    // Cancel overdue reminder from Firestore (if online)
    try {
      final fcmService = FCMService();
      if (userId != null) {
        // Cancel reminder for specific user
        final reminderId = 'rental_${rentalRequestId}_overdue_$userId';
        await fcmService.cancelReminderFromFirestore(reminderId);
      } else {
        // Cancel all overdue reminders for this rental (for all users)
        final reminders = await FirebaseFirestore.instance
            .collection('reminders')
            .where('rentalRequestId', isEqualTo: rentalRequestId)
            .where('reminderType', isEqualTo: 'rental_overdue')
            .where('sent', isEqualTo: false)
            .get();

        final batch = FirebaseFirestore.instance.batch();
        for (final doc in reminders.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
    } catch (e) {
      debugPrint(
        'Could not cancel Firestore rental overdue reminder (offline?): $e',
      );
    }
  }

  /// Check and schedule overdue notifications for all overdue rentals
  /// This should be called periodically (e.g., when app opens or daily)
  /// Checks both rentals the user is renting and rentals the user owns
  Future<void> checkAndScheduleRentalOverdueNotifications({
    required String userId,
    required String userName,
  }) async {
    if (kIsWeb) return;
    try {
      await initialize();
      final service = FirestoreService();
      final now = DateTime.now();

      // Check rentals the user is renting
      final renterRentals = await service.getRentalRequestsByUser(
        userId,
        asOwner: false,
      );
      for (final data in renterRentals) {
        final String requestId = data['id'] as String;
        final String itemId = data['itemId'] as String? ?? '';
        final String itemTitle = (data['itemTitle'] ?? 'Rental Item') as String;
        final String status = (data['status'] ?? '') as String;
        final String rentType = (data['rentType'] ?? 'item')
            .toString(); // Get rentType

        // Only check active rentals
        if (status != 'active') continue;

        final Timestamp? endDateTs = data['endDate'] as Timestamp?;
        if (endDateTs == null) continue;

        final DateTime endDate = endDateTs.toDate();
        final String? ownerId = data['ownerId'] as String?;
        String ownerName = (data['ownerName'] ?? 'Owner') as String;

        // Get actual owner name
        if (ownerId != null) {
          try {
            final ownerData = await service.getUser(ownerId);
            if (ownerData != null) {
              ownerName =
                  '${ownerData['firstName'] ?? ''} ${ownerData['lastName'] ?? ''}'
                      .trim();
              if (ownerName.isEmpty)
                ownerName = (data['ownerName'] ?? 'Owner') as String;
            }
          } catch (_) {}
        }

        if (endDate.isBefore(now)) {
          // Rental is overdue - schedule notification for renter
          await scheduleRentalOverdueReminders(
            rentalRequestId: requestId,
            itemId: itemId,
            itemTitle: itemTitle,
            endDateLocal: endDate,
            renterId: userId,
            ownerId: ownerId ?? '',
            renterName: userName,
            ownerName: ownerName,
            isRenter: true,
            targetUserId: userId,
            rentType: rentType,
          );
        } else {
          // Rental is not overdue, cancel any existing overdue reminders
          await cancelRentalOverdueReminders(requestId, userId: userId);
        }
      }

      // Check rentals the user owns
      final ownerRentals = await service.getRentalRequestsByUser(
        userId,
        asOwner: true,
      );
      for (final data in ownerRentals) {
        final String requestId = data['id'] as String;
        final String itemId = data['itemId'] as String? ?? '';
        final String itemTitle = (data['itemTitle'] ?? 'Rental Item') as String;
        final String status = (data['status'] ?? '') as String;
        final String rentType = (data['rentType'] ?? 'item')
            .toString(); // Get rentType

        // Only check active rentals
        if (status != 'active') continue;

        final Timestamp? endDateTs = data['endDate'] as Timestamp?;
        if (endDateTs == null) continue;

        final DateTime endDate = endDateTs.toDate();
        final String? renterId = data['renterId'] as String?;
        String renterName = (data['renterName'] ?? 'Renter') as String;

        // Get actual renter name
        if (renterId != null) {
          try {
            final renterData = await service.getUser(renterId);
            if (renterData != null) {
              renterName =
                  '${renterData['firstName'] ?? ''} ${renterData['lastName'] ?? ''}'
                      .trim();
              if (renterName.isEmpty)
                renterName = (data['renterName'] ?? 'Renter') as String;
            }
          } catch (_) {}
        }

        if (endDate.isBefore(now)) {
          // Rental is overdue - schedule notification for owner
          await scheduleRentalOverdueReminders(
            rentalRequestId: requestId,
            itemId: itemId,
            itemTitle: itemTitle,
            endDateLocal: endDate,
            renterId: renterId ?? '',
            ownerId: userId,
            renterName: renterName,
            ownerName: userName,
            isRenter: false,
            targetUserId: userId,
            rentType: rentType,
          );
        } else {
          // Rental is not overdue, cancel any existing overdue reminders
          await cancelRentalOverdueReminders(requestId, userId: userId);
        }
      }
    } catch (e) {
      debugPrint('Error checking rental overdue notifications: $e');
    }
  }

  Future<void> cancelReturnReminders(String itemId) async {
    if (kIsWeb) return;
    await initialize();

    // Cancel local notifications
    await _plugin.cancel(_buildId(itemId, 0)); // 24h
    await _plugin.cancel(_buildId(itemId, 1)); // 1h
    await _plugin.cancel(_buildId(itemId, 2)); // due

    // Cancel reminders from Firestore (if online)
    try {
      final fcmService = FCMService();
      await fcmService.cancelAllRemindersForItem(itemId);
    } catch (e) {
      debugPrint('Could not cancel Firestore reminders (offline?): $e');
    }
  }

  // Schedule a lightweight nudge after a short delay for a specific item
  Future<void> scheduleNudge({
    required String itemId,
    required String itemTitle,
    Duration delay = const Duration(hours: 2),
  }) async {
    if (kIsWeb) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('No user logged in, cannot schedule nudge');
      return;
    }

    final tz.TZDateTime when = tz.TZDateTime.now(tz.local).add(delay);

    // Schedule local notification (works offline)
    await _scheduleLocalNotification(
      id: _buildId(itemId, 3), // kind: 3=nudge
      title: 'Reminder: $itemTitle',
      body: 'Just a quick nudge to check your borrowed item.',
      scheduledDate: when,
      channelId: 'due_reminders',
      channelName: 'Due Reminders',
      channelDescription: 'Reminders for upcoming and due returns',
      importance: Importance.high,
      priority: Priority.high,
    );

    // Also save to Firestore for FCM (if online)
    try {
      final fcmService = FCMService();
      await fcmService.initialize();
      final reminderId = fcmService.buildReminderId(itemId, 'nudge');
      await fcmService.saveReminderToFirestore(
        reminderId: reminderId,
        userId: user.uid,
        itemId: itemId,
        itemTitle: itemTitle,
        scheduledTime: when.toUtc(),
        title: 'Reminder: $itemTitle',
        body: 'Just a quick nudge to check your borrowed item.',
        reminderType: 'nudge',
        isBorrower: true,
      );
    } catch (e) {
      debugPrint('Could not save nudge to Firestore (offline?): $e');
    }
  }

  /// Schedule recurring overdue notifications for an item
  /// This will send a notification daily until the item is returned
  Future<void> scheduleOverdueReminders({
    required String itemId,
    required String itemTitle,
    required DateTime returnDateLocal,
    required String borrowerName,
    required String lenderName,
    required bool
    isBorrower, // true if notification is for borrower, false for lender
    String? targetUserId, // ID of the user who should receive the notification
  }) async {
    if (kIsWeb) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('No user logged in, cannot schedule overdue reminders');
      return;
    }

    // Determine the target user ID - use provided targetUserId or default to current user
    final String recipientUserId = targetUserId ?? user.uid;

    final now = tz.TZDateTime.now(tz.local);
    final returnDate = tz.TZDateTime.from(returnDateLocal, tz.local);

    // Only schedule if item is actually overdue
    if (returnDate.isAfter(now)) {
      return; // Not overdue yet
    }

    // Calculate days overdue
    final daysOverdue = now.difference(returnDate).inDays;

    // Schedule daily recurring notification at 9 AM
    // If item is already overdue, schedule immediately (or very soon) so notification fires right away
    // Otherwise, schedule for 9 AM today (or tomorrow if past 9 AM)
    final nextNotification = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      9, // 9 AM
    );

    // If item is already overdue, schedule for immediate notification (current time)
    // This ensures overdue items get notified right away, not waiting until 9 AM
    final scheduledTime = daysOverdue > 0 && nextNotification.isBefore(now)
        ? now.add(
            const Duration(minutes: 1),
          ) // Schedule 1 minute from now for immediate notification
        : (nextNotification.isBefore(now)
              ? nextNotification.add(const Duration(days: 1))
              : nextNotification);

    String title;
    String body;
    if (isBorrower) {
      title = '⚠️ Overdue: $itemTitle';
      if (daysOverdue == 0) {
        body =
            'Your borrowed item "$itemTitle" is due today. Please return it to $lenderName.';
      } else if (daysOverdue == 1) {
        body =
            'Your borrowed item "$itemTitle" is 1 day overdue. Please return it to $lenderName.';
      } else {
        body =
            'Your borrowed item "$itemTitle" is $daysOverdue days overdue. Please return it to $lenderName.';
      }
    } else {
      title = '⚠️ Item Overdue: $itemTitle';
      if (daysOverdue == 0) {
        body = 'The item "$itemTitle" borrowed by $borrowerName is due today.';
      } else if (daysOverdue == 1) {
        body =
            'The item "$itemTitle" borrowed by $borrowerName is 1 day overdue.';
      } else {
        body =
            'The item "$itemTitle" borrowed by $borrowerName is $daysOverdue days overdue.';
      }
    }

    // Schedule local recurring notification (works offline)
    // Use DateTimeComponents.time to make it recur daily at the same time
    await _scheduleLocalNotification(
      id: _buildId(itemId, 4), // kind: 4=overdue_daily
      title: title,
      body: body,
      scheduledDate: scheduledTime,
      channelId: 'overdue_reminders',
      channelName: 'Overdue Reminders',
      channelDescription: 'Reminders for overdue items',
      importance: Importance.max,
      priority: Priority.max,
      matchDateTimeComponents: DateTimeComponents.time, // Recur daily at 9 AM
    );

    // Also save to Firestore for FCM (if online)
    try {
      final fcmService = FCMService();
      await fcmService.initialize();
      // Include recipient user ID in reminder ID to make it unique per user
      final reminderId = '${itemId}_overdue_${recipientUserId}';
      await fcmService.saveReminderToFirestore(
        reminderId: reminderId,
        userId:
            recipientUserId, // Use the target user's ID, not current user's ID
        itemId: itemId,
        itemTitle: itemTitle,
        scheduledTime: scheduledTime.toUtc(),
        title: title,
        body: body,
        reminderType: 'overdue',
        borrowerName: borrowerName,
        lenderName: lenderName,
        isBorrower: isBorrower,
      );
    } catch (e) {
      debugPrint('Could not save overdue reminder to Firestore (offline?): $e');
    }
  }

  /// Cancel overdue reminders for an item
  /// If userId is provided, only cancels reminders for that specific user
  /// Otherwise, cancels all overdue reminders for the item (for all users)
  Future<void> cancelOverdueReminders(String itemId, {String? userId}) async {
    if (kIsWeb) return;
    await initialize();

    // Cancel local notification
    await _plugin.cancel(_buildId(itemId, 4)); // overdue_daily

    // Cancel overdue reminder from Firestore (if online)
    try {
      final fcmService = FCMService();
      if (userId != null) {
        // Cancel reminder for specific user
        final reminderId = '${itemId}_overdue_$userId';
        await fcmService.cancelReminderFromFirestore(reminderId);
      } else {
        // Cancel all overdue reminders for this item (for all users)
        await fcmService.cancelAllRemindersForItem(itemId);
      }
    } catch (e) {
      debugPrint('Could not cancel Firestore overdue reminder (offline?): $e');
    }
  }

  /// Check and schedule overdue notifications for all overdue items
  /// This should be called periodically (e.g., when app opens or daily)
  /// Checks both items the user borrowed and items the user lent out
  Future<void> checkAndScheduleOverdueNotifications({
    required String userId,
    required String userName,
  }) async {
    if (kIsWeb) return;
    try {
      await initialize();
      final service = FirestoreService();
      final now = DateTime.now();

      // Check items the user borrowed
      final borrowedItems = await service.getBorrowedItemsByBorrower(userId);
      for (final data in borrowedItems) {
        final String itemId = data['id'] as String;
        final String itemTitle = (data['title'] ?? 'Item') as String;
        final Timestamp? ts = data['returnDate'] as Timestamp?;
        if (ts == null) continue;

        final DateTime returnDate = ts.toDate();
        final String? lenderId = data['lenderId'] as String?;
        String lenderName = (data['lenderName'] ?? 'Lender') as String;

        // Get actual lender name
        if (lenderId != null) {
          try {
            final lenderData = await service.getUser(lenderId);
            if (lenderData != null) {
              lenderName =
                  '${lenderData['firstName'] ?? ''} ${lenderData['lastName'] ?? ''}'
                      .trim();
              if (lenderName.isEmpty)
                lenderName = (data['lenderName'] ?? 'Lender') as String;
            }
          } catch (_) {}
        }

        if (returnDate.isBefore(now)) {
          // Item is overdue - schedule notification for borrower
          await scheduleOverdueReminders(
            itemId: itemId,
            itemTitle: itemTitle,
            returnDateLocal: returnDate,
            borrowerName: userName,
            lenderName: lenderName,
            isBorrower: true,
            targetUserId: userId, // Borrower's ID
          );
        } else {
          // Item is not overdue, cancel any existing overdue reminders
          await cancelOverdueReminders(itemId);
        }
      }

      // Check items the user lent out (that are currently borrowed)
      final myItems = await service.getItemsByLender(userId);
      for (final data in myItems) {
        final String itemId = data['id'] as String;
        final String status = (data['status'] ?? '') as String;
        if (status != 'borrowed') continue; // Only check borrowed items

        final String itemTitle = (data['title'] ?? 'Item') as String;
        final Timestamp? ts = data['returnDate'] as Timestamp?;
        if (ts == null) continue;

        final DateTime returnDate = ts.toDate();
        final String? borrowerId = data['currentBorrowerId'] as String?;
        String borrowerName = 'Borrower';

        // Get actual borrower name
        if (borrowerId != null) {
          try {
            final borrowerData = await service.getUser(borrowerId);
            if (borrowerData != null) {
              borrowerName =
                  '${borrowerData['firstName'] ?? ''} ${borrowerData['lastName'] ?? ''}'
                      .trim();
              if (borrowerName.isEmpty) borrowerName = 'Borrower';
            }
          } catch (_) {}
        }

        if (returnDate.isBefore(now)) {
          // Item is overdue - schedule notification for lender
          await scheduleOverdueReminders(
            itemId: itemId,
            itemTitle: itemTitle,
            returnDateLocal: returnDate,
            borrowerName: borrowerName,
            lenderName: userName,
            isBorrower: false,
            targetUserId: userId, // Lender's ID
          );
        } else {
          // Item is not overdue, cancel any existing overdue reminders
          await cancelOverdueReminders(itemId);
        }
      }
    } catch (e) {
      // Best-effort; don't fail if notification scheduling fails
      debugPrint('Error checking overdue notifications: $e');
    }
  }

  /// Notification response handler (when user taps notification)
  void _onNotificationResponse(NotificationResponse response) {
    _logNotificationReceived(response.id ?? 0, 'tapped');
  }

  /// Log when a notification is received/displayed
  void _logNotificationReceived(int notificationId, String action) {
    debugPrint('🔔 Notification received: ID $notificationId, Action: $action');
  }

  /// Show an immediate notification with custom icon
  /// Used for FCM notifications to ensure they use the custom icon
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    required String channelId,
    required String channelName,
    required String channelDescription,
    Importance importance = Importance.high,
    Priority priority = Priority.high,
  }) async {
    if (kIsWeb) return;

    await initialize();

    // Ensure notification channel exists (Android)
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        AndroidNotificationChannel(
          channelId,
          channelName,
          description: channelDescription,
          importance: importance,
        ),
      );
    }

    final NotificationDetails details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        priority: priority,
        importance: importance,
        enableVibration: true,
        playSound: true,
        icon: '@drawable/ic_stat_bridge',
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
      macOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _plugin.show(id, title, body, details);
  }

  /// Test function: Schedule a local notification for tomorrow
  /// This is a simple test to verify offline notifications work
  /// The notification will fire tomorrow at the same time it was scheduled
  Future<void> testOfflineNotificationTomorrow() async {
    if (kIsWeb) {
      debugPrint('Test notification not supported on web');
      return;
    }

    await initialize();

    // Check permissions first
    final hasPermission = await requestPermissions();
    if (!hasPermission) {
      throw Exception(
        'Notification permissions not granted. Please enable notifications in app settings.',
      );
    }

    // Schedule for tomorrow at 9 AM
    final now = tz.TZDateTime.now(tz.local);
    final scheduledTime = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day + 1,
      9, // 9 AM tomorrow
    );

    await _scheduleLocalNotification(
      id: 999997, // Use a high test ID
      title: '🧪 Test Offline Notification',
      body:
          'This is a test notification to verify offline notifications work! Scheduled for ${scheduledTime.toString().substring(0, 16)}',
      scheduledDate: scheduledTime,
      channelId: 'due_reminders',
      channelName: 'Due Reminders',
      channelDescription: 'Reminders for upcoming and due returns',
      importance: Importance.high,
      priority: Priority.high,
    );

    final timeUntil = scheduledTime.difference(now);
    debugPrint('');
    debugPrint('═══════════════════════════════════════════════════');
    debugPrint('🧪 TEST OFFLINE NOTIFICATION SCHEDULED');
    debugPrint('═══════════════════════════════════════════════════');
    debugPrint('  Scheduled for: $scheduledTime');
    debugPrint('  Current time: $now');
    debugPrint(
      '  Time until notification: ${timeUntil.inHours} hours ${timeUntil.inMinutes % 60} minutes',
    );
    debugPrint('  This notification works OFFLINE (no internet required)');
    debugPrint('═══════════════════════════════════════════════════');
    debugPrint('');
  }

  /// Cancel the test notification
  Future<void> cancelTestOfflineNotification() async {
    if (kIsWeb) return;
    await initialize();
    await _plugin.cancel(999997);
    debugPrint('Test notification cancelled');
  }

  /// Check for missed scheduled notifications and show them
  /// This is a fallback for devices (like Tecno) that block AlarmManager
  /// Call this when the app opens to catch any notifications that should have fired
  Future<void> checkAndShowMissedNotifications({
    required String userId,
    required String userName,
  }) async {
    if (kIsWeb) return;
    try {
      await initialize();
      final service = FirestoreService();
      final now = DateTime.now();

      // Check items the user borrowed that are due soon or overdue
      final borrowedItems = await service.getBorrowedItemsByBorrower(userId);
      for (final data in borrowedItems) {
        final String itemId = data['id'] as String;
        final String itemTitle = (data['title'] ?? 'Item') as String;
        final Timestamp? ts = data['returnDate'] as Timestamp?;
        if (ts == null) continue;

        final DateTime returnDate = ts.toDate();
        final String? lenderId = data['lenderId'] as String?;
        String lenderName = (data['lenderName'] ?? 'Lender') as String;

        // Get actual lender name
        if (lenderId != null) {
          try {
            final lenderData = await service.getUser(lenderId);
            if (lenderData != null) {
              lenderName =
                  '${lenderData['firstName'] ?? ''} ${lenderData['lastName'] ?? ''}'
                      .trim();
              if (lenderName.isEmpty)
                lenderName = (data['lenderName'] ?? 'Lender') as String;
            }
          } catch (_) {}
        }

        // Only show notifications for items that are already overdue (past due date)
        // This is a fallback for devices that block scheduled notifications
        // We don't show future reminders here - FCM handles those
        if (returnDate.isBefore(now)) {
          // Item is overdue - check if it's within the last 24 hours to avoid spamming old overdue items
          final hoursOverdue = now.difference(returnDate).inHours;
          if (hoursOverdue <= 24) {
            // Only show for items overdue within the last 24 hours
            final NotificationDetails details = NotificationDetails(
              android: AndroidNotificationDetails(
                'overdue_reminders',
                'Overdue Reminders',
                channelDescription: 'Reminders for overdue items',
                priority: Priority.max,
                importance: Importance.max,
                enableVibration: true,
                playSound: true,
                icon: '@drawable/ic_stat_bridge',
              ),
              iOS: const DarwinNotificationDetails(
                presentAlert: true,
                presentBadge: true,
                presentSound: true,
              ),
              macOS: const DarwinNotificationDetails(
                presentAlert: true,
                presentBadge: true,
                presentSound: true,
              ),
            );

            final daysOverdue = now.difference(returnDate).inDays;
            String title = '⚠️ Overdue: $itemTitle';
            String body;
            if (daysOverdue == 0) {
              body =
                  'Your borrowed item "$itemTitle" is due today. Please return it to $lenderName.';
            } else if (daysOverdue == 1) {
              body =
                  'Your borrowed item "$itemTitle" is 1 day overdue. Please return it to $lenderName.';
            } else {
              body =
                  'Your borrowed item "$itemTitle" is $daysOverdue days overdue. Please return it to $lenderName.';
            }

            // Show the notification immediately
            await _plugin.show(
              _buildId(
                itemId,
                2,
              ), // Use the same ID as the scheduled notification
              title,
              body,
              details,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking missed notifications: $e');
      // Best-effort; don't fail if this check fails
    }
  }
}
