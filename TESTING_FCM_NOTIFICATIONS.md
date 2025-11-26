# Testing FCM Push Notifications

This guide will help you test the FCM notification system step by step.

## Prerequisites

1. ✅ Firebase Functions deployed
2. ✅ Firestore index created (wait for it to be "Enabled")
3. ✅ App installed on a physical device (FCM doesn't work well on emulators)

## Step 1: Verify FCM Token Registration

### In the App:

1. Run the app on a **physical device** (not emulator)
2. Log in with a user account
3. The app should automatically request notification permissions
4. Grant notification permissions when prompted

### Check Firestore:

1. Go to [Firebase Console](https://console.firebase.google.com/project/bridge-72b26/firestore/data)
2. Navigate to `users` collection
3. Find your user document
4. Verify it has an `fcmToken` field with a long token string
5. Also check `fcm_tokens/{userId}` collection - should have the same token

**✅ Success:** If you see the token in Firestore, FCM is initialized correctly!

---

## Step 2: Create a Test Reminder

### Option A: Create via App (Recommended)

1. In the app, borrow an item with a return date
2. The app will automatically create reminders in Firestore

### Option B: Create Manually in Firestore (For Quick Testing)

1. Go to Firestore Console
2. Navigate to `reminders` collection
3. Click "Add document"
4. Use document ID: `test_item_due` (or any unique ID)
5. Add these fields:
   ```
   userId: [your-user-id]
   itemId: test_item
   itemTitle: Test Item
   scheduledTime: [Timestamp - set to 2 minutes from now]
   title: Test Notification
   body: This is a test notification
   reminderType: due
   sent: false
   createdAt: [Timestamp - now]
   updatedAt: [Timestamp - now]
   ```

**✅ Success:** You should see the reminder document in Firestore!

---

## Step 3: Test the Manual Function

This tests if the function can find and process reminders:

```bash
curl https://us-central1-bridge-72b26.cloudfunctions.net/manualCheckReminders
```

**Expected Response:**

```json
{
  "success": true,
  "message": "Found X due reminders",
  "reminders": [...]
}
```

**✅ Success:** If you see reminders listed, the function is working!

---

## Step 4: Test Scheduled Function (Wait for Notification)

### Quick Test (2-5 minutes):

1. Create a reminder with `scheduledTime` set to **2-3 minutes in the future**
2. Wait for the scheduled function to run (runs every minute)
3. Check your device - you should receive a push notification!

### Monitor Function Logs:

```bash
firebase functions:log
```

Or view in [Firebase Console](https://console.firebase.google.com/project/bridge-72b26/functions/logs)

**Look for:**

- "Checking for due reminders at: [timestamp]"
- "Found X due reminders"
- "Successfully sent reminder [id] to user [userId]"

**✅ Success:** If you see "Successfully sent reminder" in logs, the notification was sent!

---

## Step 5: Verify Notification Received

### On Your Device:

1. You should see a notification in the notification tray
2. Title should match what you set in the reminder
3. Body should match what you set in the reminder
4. Tap the notification - it should open the app

### Check Firestore:

1. Go back to the `reminders` collection
2. Find your test reminder document
3. Verify:
   - `sent: true`
   - `sentAt: [timestamp]` (should be recent)

**✅ Success:** If notification appears and reminder is marked as sent, everything works!

---

## Step 6: Test Different Scenarios

### Test 1: App Closed

1. Create a reminder for 2 minutes in the future
2. **Close the app completely** (swipe away from recent apps)
3. Wait 2-3 minutes
4. You should still receive the notification! ✅

### Test 2: Device Restarted

1. Create a reminder for 5 minutes in the future
2. Restart your device
3. Wait 5 minutes
4. You should still receive the notification! ✅

### Test 3: Different Reminder Types

Test each reminder type:

- `24h` - 24 hours before due
- `1h` - 1 hour before due
- `due` - At due time
- `overdue` - Daily overdue reminders

---

## Troubleshooting

### No FCM Token in Firestore

- **Check:** Did you grant notification permissions?
- **Check:** Is the app running on a physical device?
- **Fix:** Reinstall the app and grant permissions again

### Reminder Not Being Sent

- **Check:** Is `scheduledTime` in the past or very near future?
- **Check:** Is `sent: false`?
- **Check:** Does the user have a valid `fcmToken`?
- **Check:** Function logs for errors

### Notification Not Appearing

- **Check:** Device notification settings - are notifications enabled for the app?
- **Check:** Device is connected to internet
- **Check:** Function logs show "Successfully sent reminder"
- **Check:** FCM token is still valid (tokens can expire)

### Function Not Running

- **Check:** Is the scheduled function deployed?
- **Check:** Function logs - should see entries every minute
- **Check:** [Firebase Console - Functions](https://console.firebase.google.com/project/bridge-72b26/functions)

---

## Quick Test Script

Here's a quick way to test everything:

1. **Create test reminder** (set scheduledTime to 2 minutes from now)
2. **Wait 3 minutes**
3. **Check logs:** `firebase functions:log | grep "checkAndSendReminders"`
4. **Check device:** Should have notification
5. **Check Firestore:** Reminder should have `sent: true`

---

## Expected Timeline

- **0:00** - Create reminder with scheduledTime = now + 2 minutes
- **0:01** - Scheduled function runs (reminder not due yet, skipped)
- **0:02** - Scheduled function runs (reminder is due, sends notification)
- **0:02** - Device receives notification
- **0:02** - Reminder marked as `sent: true` in Firestore

---

## Success Criteria

✅ FCM token saved in Firestore  
✅ Reminder created in Firestore  
✅ Function finds due reminders  
✅ Function sends FCM notification  
✅ Device receives notification  
✅ Notification works when app is closed  
✅ Reminder marked as sent

If all these pass, your FCM notification system is working perfectly! 🎉
