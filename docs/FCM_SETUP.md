# Firebase Cloud Messaging (FCM) Setup Guide

This guide explains how to set up and deploy the FCM-based push notification system for the Bridge app.

## Overview

The app now uses Firebase Cloud Messaging (FCM) for push notifications instead of local scheduled notifications. This ensures notifications work reliably even when the app is closed or the device is restarted.

## How It Works

1. **Client Side (Flutter App)**:

   - When a user schedules a reminder, it's saved to Firestore in the `reminders` collection
   - The app gets an FCM device token and saves it to Firestore
   - The app listens for incoming FCM messages

2. **Server Side (Firebase Functions)**:
   - A scheduled function runs every minute
   - It checks for reminders in Firestore where `scheduledTime <= now` and `sent == false`
   - For each due reminder, it:
     - Fetches the user's FCM token
     - Sends a push notification via FCM
     - Marks the reminder as sent
     - For overdue reminders, schedules the next daily notification

## Setup Instructions

### 1. Install Dependencies

First, install the Flutter package:

```bash
flutter pub get
```

### 2. Set Up Firebase Functions

Navigate to the functions directory and install dependencies:

```bash
cd functions
npm install
```

### 3. Deploy Firebase Functions

Make sure you have Firebase CLI installed and are logged in:

```bash
firebase login
```

Deploy the functions:

```bash
firebase deploy --only functions
```

This will deploy:

- `checkAndSendReminders`: A scheduled function that runs every minute
- `manualCheckReminders`: An HTTP function for testing (optional)

### 4. Firestore Indexes

The function queries reminders with:

- `sent == false`
- `scheduledTime <= now`

Firestore will automatically create the necessary index, but you may need to create it manually if you see an error. The index should be on:

- Collection: `reminders`
- Fields: `sent` (Ascending), `scheduledTime` (Ascending)

### 5. Firestore Security Rules

Make sure your Firestore rules allow:

- Users to read/write their own reminders
- The function to read/write all reminders (functions run with admin privileges)

Example rules:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Reminders collection
    match /reminders/{reminderId} {
      allow read, write: if request.auth != null &&
        request.auth.uid == resource.data.userId;
    }

    // FCM tokens collection
    match /fcm_tokens/{userId} {
      allow read, write: if request.auth != null &&
        request.auth.uid == userId;
    }

    // Users collection (for FCM tokens)
    match /users/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null &&
        request.auth.uid == userId;
    }
  }
}
```

### 6. Testing

#### Test FCM Token Registration

1. Run the app and log in
2. Check Firestore console - you should see:
   - A document in `users/{userId}` with `fcmToken` field
   - A document in `fcm_tokens/{userId}` with the token

#### Test Reminder Creation

1. Borrow an item with a return date
2. Check Firestore console - you should see reminders in the `reminders` collection:
   - `{itemId}_24h` - 24 hours before due
   - `{itemId}_1h` - 1 hour before due
   - `{itemId}_due` - At due time

#### Test Notification Sending

1. Create a test reminder with a scheduled time in the past
2. Wait up to 1 minute for the scheduled function to run
3. Check Firebase Functions logs:
   ```bash
   firebase functions:log
   ```
4. You should see the notification being sent

#### Manual Test Function

You can also manually trigger the check:

```bash
curl https://YOUR-PROJECT-ID.cloudfunctions.net/manualCheckReminders
```

## Troubleshooting

### Notifications Not Appearing

1. **Check FCM Token**: Verify the token is saved in Firestore
2. **Check Function Logs**: Look for errors in Firebase Functions logs
3. **Check Reminder Status**: Verify reminders are being created and not marked as sent
4. **Check Device**: Ensure the device has internet connection and notifications are enabled

### Function Not Running

1. **Check Deployment**: Verify the function is deployed:
   ```bash
   firebase functions:list
   ```
2. **Check Schedule**: The function runs every minute, but there may be a delay
3. **Check Quotas**: Ensure you haven't exceeded Firebase quotas

### Token Not Found Errors

- The user may not have granted notification permissions
- The app may not have initialized FCM properly
- The token may have expired (FCM automatically refreshes tokens)

## Monitoring

### View Function Logs

```bash
firebase functions:log --only checkAndSendReminders
```

### View Reminders in Firestore

Go to Firebase Console > Firestore > `reminders` collection

### Monitor Function Execution

Go to Firebase Console > Functions > `checkAndSendReminders` > Logs

## Cost Considerations

- Firebase Functions: Free tier includes 2 million invocations/month
- FCM: Free for unlimited messages
- Firestore: Free tier includes 50K reads/day, 20K writes/day

For a small app, this should be well within free tier limits.

## Next Steps

1. Deploy the functions
2. Test with a real device
3. Monitor the logs for the first few days
4. Adjust the schedule frequency if needed (currently every 1 minute)
