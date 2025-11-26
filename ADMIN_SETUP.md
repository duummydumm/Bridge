# How to Create an Admin Account in Firestore

This guide explains how to manually set a user as an admin in Firestore.

## Method 1: Using Firebase Console (Recommended)

### Steps:

1. **Open Firebase Console**

   - Go to [https://console.firebase.google.com/](https://console.firebase.google.com/)
   - Select your project

2. **Navigate to Firestore Database**

   - Click on "Firestore Database" in the left sidebar
   - Make sure you're in the "Data" tab

3. **Find the User Document**

   - Navigate to the `users` collection
   - Find the document with the user's UID (the document ID is the user's Firebase Auth UID)
   - You can identify the user by their `email` field

4. **Add/Update the `isAdmin` Field**

   - Click on the user document to open it
   - Look for the `isAdmin` field
   - If it doesn't exist, click "Add field"
   - Set the field:
     - **Field name**: `isAdmin`
     - **Field type**: `boolean`
     - **Field value**: `true`
   - If the field already exists and is `false`, click on it and change it to `true`
   - Click "Update" to save

5. **Verify the Change**
   - The `isAdmin` field should now show as `true` (green checkmark)
   - The user will need to log out and log back in for the change to take effect

## Method 2: Using Firebase CLI

If you have Firebase CLI installed, you can use the following command:

```bash
firebase firestore:set users/USER_UID isAdmin true
```

Replace `USER_UID` with the actual Firebase Auth UID of the user.

## Method 3: Programmatically (For Developers)

You can also create an admin programmatically using the Firestore Admin SDK or by adding a function in your app. However, this requires additional setup.

## Important Notes:

1. **User UID**: The document ID in the `users` collection must match the Firebase Auth UID. You can find the UID in:

   - Firebase Console → Authentication → Users
   - Or in your app's user profile

2. **Field Type**: Make sure `isAdmin` is set as a **boolean** (`true` or `false`), not a string

3. **Default Value**: If the `isAdmin` field doesn't exist, the app treats it as `false` by default

4. **Additional Fields**: The user document should have these fields (at minimum):
   - `email` (string)
   - `firstName` (string)
   - `lastName` (string)
   - `isAdmin` (boolean) - set to `true` for admin
   - `isSuspended` (boolean) - defaults to `false`
   - `violationCount` (number) - defaults to `0`
   - `reputationScore` (number) - defaults to `0.0`
   - `createdAt` (timestamp)

## Example User Document Structure:

```json
{
  "email": "admin@example.com",
  "firstName": "Admin",
  "lastName": "User",
  "middleInitial": "",
  "barangay": "example",
  "city": "example",
  "province": "example",
  "street": "example",
  "role": "both",
  "isVerified": true,
  "verificationStatus": "approved",
  "barangayIdType": "National ID",
  "barangayIdUrl": "",
  "profilePhotoUrl": "",
  "reputationScore": 0.0,
  "isAdmin": true, // ← This is the key field
  "isSuspended": false,
  "violationCount": 0,
  "createdAt": "2024-01-01T00:00:00Z"
}
```

## After Making a User Admin:

1. The user should **log out** and **log back in** for the changes to take effect
2. Admin users will:
   - Bypass email verification
   - Have access to the Admin Dashboard
   - Be able to access all protected routes without verification
   - See admin-specific features in the app

## Security Note:

⚠️ **Important**: Only trusted users should be given admin privileges. Admin accounts have full access to the app's administrative features.
