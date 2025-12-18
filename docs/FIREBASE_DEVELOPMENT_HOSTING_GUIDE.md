# Firebase Development Hosting Guide

This guide explains how to set up Firebase Hosting for your Flutter app during development, following best practices for security, cost management, and environment separation.

---

## Table of Contents

1. [Create a Separate Firebase Project for Development](#1-create-a-separate-firebase-project-for-development)
2. [Host on a Development Subdomain or Staging URL](#2-host-on-a-development-subdomain-or-staging-url)
3. [Add Clear Visual Indicators for Development Version](#3-add-clear-visual-indicators-for-development-version)
4. [Use Firebase Security Rules Appropriate for Development](#4-use-firebase-security-rules-appropriate-for-development)
5. [Monitor Costs and Usage](#5-monitor-costs-and-usage)

---

## 1. Create a Separate Firebase Project for Development

### Why?
- **Data Isolation**: Prevents accidental data loss or corruption in production
- **Cost Tracking**: Separate billing helps track development costs
- **Security**: Different security rules for dev vs production
- **Testing**: Safe to experiment without affecting real users

### Steps:

#### Step 1.1: Create New Firebase Project
1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click **"Add project"** or **"Create a project"**
3. Enter project name: `bridge-app-dev` (or `bridge-72b26-dev`)
4. **Disable Google Analytics** (optional, saves resources)
5. Click **"Create project"**

#### Step 1.2: Enable Required Services
In your new development project, enable:
- ✅ **Authentication** (Firebase Auth)
- ✅ **Cloud Firestore** (Database)
- ✅ **Storage** (Firebase Storage)
- ✅ **Hosting** (for web deployment)
- ✅ **Cloud Functions** (if you use them)

#### Step 1.3: Register Web App
1. In Firebase Console, click the **Web icon** (`</>`)
2. Register app name: `bridge_app_web_dev`
3. **Copy the Firebase configuration** (you'll need this)

#### Step 1.4: Update Your Local Configuration

**Option A: Use Environment Variables (Recommended)**

Create a new file: `lib/firebase_options_dev.dart`

```dart
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;

class DevFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      default:
        throw UnsupportedError('Platform not supported');
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'YOUR_DEV_API_KEY',
    appId: 'YOUR_DEV_APP_ID',
    messagingSenderId: 'YOUR_DEV_SENDER_ID',
    projectId: 'bridge-app-dev',
    authDomain: 'bridge-app-dev.firebaseapp.com',
    storageBucket: 'bridge-app-dev.firebasestorage.app',
    measurementId: 'YOUR_DEV_MEASUREMENT_ID',
  );

  // Add other platforms as needed
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'YOUR_DEV_ANDROID_API_KEY',
    appId: 'YOUR_DEV_ANDROID_APP_ID',
    messagingSenderId: 'YOUR_DEV_SENDER_ID',
    projectId: 'bridge-app-dev',
    storageBucket: 'bridge-app-dev.firebasestorage.app',
  );

  // Similar for iOS, macOS, Windows...
}
```

**Option B: Use FlutterFire CLI**

```bash
# Install FlutterFire CLI if not already installed
dart pub global activate flutterfire_cli

# Configure for development project
flutterfire configure --project=bridge-app-dev --out=lib/firebase_options_dev.dart
```

#### Step 1.5: Update .firebaserc

Add your development project to `.firebaserc`:

```json
{
  "projects": {
    "default": "bridge-72b26",
    "dev": "bridge-app-dev",
    "production": "bridge-72b26"
  }
}
```

#### Step 1.6: Switch Between Projects

```bash
# Use development project
firebase use dev

# Use production project
firebase use production

# Check current project
firebase projects:list
```

---

## 2. Host on a Development Subdomain or Staging URL

### Why?
- **Clear Separation**: Users know they're on a development version
- **Easy Access**: Shareable URL for testing
- **No Production Impact**: Completely separate from production

### Steps:

#### Step 2.1: Configure Firebase Hosting

Update your `firebase.json` to include hosting configuration:

```json
{
  "firestore": {
    "database": "(default)",
    "location": "asia-east1",
    "rules": "firestore.rules",
    "indexes": "firestore.indexes.json"
  },
  "storage": {
    "rules": "storage.rules"
  },
  "functions": {
    "source": "functions",
    "predeploy": [
      "npm --prefix \"$RESOURCE_DIR\" run lint"
    ]
  },
  "hosting": {
    "public": "build/web",
    "ignore": [
      "firebase.json",
      "**/.*",
      "**/node_modules/**"
    ],
    "rewrites": [
      {
        "source": "**",
        "destination": "/index.html"
      }
    ],
    "headers": [
      {
        "source": "**/*.@(jpg|jpeg|gif|png|svg|webp|js|css|eot|otf|ttf|ttc|woff|woff2|font.css)",
        "headers": [
          {
            "key": "Cache-Control",
            "value": "max-age=604800"
          }
        ]
      }
    ]
  },
  "flutter": {
    "platforms": {
      "android": {
        "default": {
          "projectId": "bridge-72b26",
          "appId": "1:296102513753:android:4c051d7fec09853a39f548",
          "fileOutput": "android/app/google-services.json"
        }
      },
      "dart": {
        "lib/firebase_options.dart": {
          "projectId": "bridge-72b26",
          "configurations": {
            "android": "1:296102513753:android:4c051d7fec09853a39f548",
            "ios": "1:296102513753:ios:5a96312fa1b4bf9a39f548",
            "web": "1:296102513753:web:d36b005013ba4b2339f548"
          }
        }
      }
    }
  }
}
```

#### Step 2.2: Build Flutter Web App

```bash
# Build for web (production mode)
flutter build web --release

# Or for development with better debugging
flutter build web --web-renderer canvaskit
```

#### Step 2.3: Deploy to Firebase Hosting

```bash
# Switch to development project
firebase use dev

# Deploy to hosting
firebase deploy --only hosting

# Or deploy everything (hosting, functions, rules)
firebase deploy
```

#### Step 2.4: Access Your Development Site

After deployment, you'll get a URL like:
- `https://bridge-app-dev.web.app`
- `https://bridge-app-dev.firebaseapp.com`

#### Step 2.5: Set Up Custom Domain (Optional)

If you have a custom domain:

1. Go to Firebase Console → Hosting
2. Click **"Add custom domain"**
3. Enter subdomain: `dev.yourdomain.com` or `staging.yourdomain.com`
4. Follow DNS configuration instructions
5. Wait for SSL certificate provisioning (usually 24-48 hours)

---

## 3. Add Clear Visual Indicators for Development Version

### Why?
- **Prevent Confusion**: Users know they're testing, not using production
- **Data Safety**: Reminds testers that data may be reset
- **Professional**: Shows you're following best practices

### Implementation:

#### Step 3.1: Create Development Banner Widget

Create `lib/widgets/dev_banner.dart`:

```dart
import 'package:flutter/material.dart';

class DevBanner extends StatelessWidget {
  final Widget child;
  final bool showBanner;

  const DevBanner({
    super.key,
    required this.child,
    this.showBanner = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!showBanner) return child;

    return Banner(
      message: 'DEV',
      location: BannerLocation.topStart,
      color: Colors.red,
      textStyle: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.bold,
      ),
      child: child,
    );
  }
}
```

#### Step 3.2: Add Environment Detection

Create `lib/config/app_config.dart`:

```dart
class AppConfig {
  // Set this based on your Firebase project
  static const String firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'bridge-72b26',
  );

  static bool get isDevelopment {
    return firebaseProjectId.contains('dev') || 
           firebaseProjectId.contains('-dev');
  }

  static bool get isProduction {
    return !isDevelopment;
  }

  static String get environmentName {
    return isDevelopment ? 'Development' : 'Production';
  }
}
```

#### Step 3.3: Update main.dart

Wrap your app with the DevBanner:

```dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'config/app_config.dart';
import 'widgets/dev_banner.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase based on environment
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: AppConfig.isDevelopment 
        ? DevFirebaseOptions.currentPlatform  // Use dev config
        : DefaultFirebaseOptions.currentPlatform,  // Use production config
    );
  }
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DevBanner(
      showBanner: AppConfig.isDevelopment,
      child: MaterialApp(
        title: 'Bridge App',
        // ... rest of your app configuration
      ),
    );
  }
}
```

#### Step 3.4: Add Environment Indicator in UI (Optional)

Add a persistent indicator in your app bar or drawer:

```dart
// In your main screen or app bar
if (AppConfig.isDevelopment)
  Container(
    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.red,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      'DEV',
      style: TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.bold,
      ),
    ),
  ),
```

#### Step 3.5: Build with Environment Variable

```bash
# Build for development
flutter build web --release --dart-define=FIREBASE_PROJECT_ID=bridge-app-dev

# Build for production
flutter build web --release --dart-define=FIREBASE_PROJECT_ID=bridge-72b26
```

---

## 4. Use Firebase Security Rules Appropriate for Development

### Why?
- **Flexible Testing**: Easier to test features without strict rules
- **Debugging**: Can temporarily allow broader access for troubleshooting
- **Safety**: Still maintain some security, but more permissive

### Development Firestore Rules

Create `firestore.dev.rules`:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // More permissive rules for development
    // Allow authenticated users to read/write most collections
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
    
    // Specific rules for sensitive collections (still protect user data)
    match /users/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.uid == userId;
    }
    
    // Admin-only collections
    match /admin/{document=**} {
      allow read, write: if request.auth != null 
        && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.isAdmin == true;
    }
  }
}
```

### Development Storage Rules

Create `storage.dev.rules`:

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    // Allow authenticated users to upload/download
    match /{allPaths=**} {
      allow read, write: if request.auth != null;
    }
    
    // User-specific folders
    match /users/{userId}/{allPaths=**} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

### Deploy Development Rules

```bash
# Switch to dev project
firebase use dev

# Deploy Firestore rules
firebase deploy --only firestore:rules

# Deploy Storage rules
firebase deploy --only storage:rules

# Or deploy both
firebase deploy --only firestore:rules,storage:rules
```

### Production Rules (Keep Strict)

Keep your production `firestore.rules` and `storage.rules` strict:

```javascript
// Example production Firestore rules (more restrictive)
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.uid == userId;
    }
    
    match /rentals/{rentalId} {
      allow read: if request.auth != null;
      allow create: if request.auth != null;
      allow update, delete: if request.auth != null 
        && resource.data.ownerId == request.auth.uid;
    }
    
    // More specific rules for each collection...
  }
}
```

### Switch Rules Based on Project

You can automate rule deployment:

```bash
# deploy-dev.sh
#!/bin/bash
firebase use dev
firebase deploy --only firestore:rules,storage:rules --project dev

# deploy-prod.sh
#!/bin/bash
firebase use production
firebase deploy --only firestore:rules,storage:rules --project production
```

---

## 5. Monitor Costs and Usage

### Why?
- **Budget Control**: Avoid unexpected charges
- **Optimization**: Identify expensive operations
- **Planning**: Understand resource usage patterns

### Steps:

#### Step 5.1: Set Up Billing Alerts

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Select your Firebase project (`bridge-app-dev`)
3. Navigate to **Billing** → **Budgets & alerts**
4. Click **"Create Budget"**
5. Set budget amount (e.g., $10/month for development)
6. Configure alerts:
   - Alert at 50% of budget
   - Alert at 90% of budget
   - Alert at 100% of budget
7. Add email notifications

#### Step 5.2: Monitor Firebase Usage Dashboard

1. Go to Firebase Console → **Usage and billing**
2. Monitor:
   - **Firestore**: Reads, writes, deletes
   - **Storage**: Storage used, downloads, uploads
   - **Hosting**: Bandwidth, requests
   - **Functions**: Invocations, compute time
   - **Authentication**: Users, verifications

#### Step 5.3: Set Up Usage Limits (Optional)

In Google Cloud Console:

1. Go to **IAM & Admin** → **Quotas**
2. Search for services you want to limit:
   - Firestore API: Read requests per day
   - Firestore API: Write requests per day
   - Storage: Download bytes per day
3. Set reasonable limits for development

#### Step 5.4: Use Firebase Emulator Suite (Local Development)

For local development, use emulators to avoid costs:

```bash
# Install Firebase CLI if not already installed
npm install -g firebase-tools

# Initialize emulators
firebase init emulators

# Start emulators
firebase emulators:start
```

Update your app to use emulators in development:

```dart
// In main.dart or a config file
void setupFirebaseEmulators() {
  if (AppConfig.isDevelopment && kDebugMode) {
    FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
    FirebaseStorage.instance.useStorageEmulator('localhost', 9199);
    FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
  }
}
```

#### Step 5.5: Regular Cost Review

**Weekly Checklist:**
- [ ] Check Firebase Console usage dashboard
- [ ] Review billing alerts
- [ ] Check for unusual spikes in usage
- [ ] Review Firestore query patterns
- [ ] Check Storage usage

**Monthly Checklist:**
- [ ] Review total costs
- [ ] Compare dev vs production costs
- [ ] Optimize expensive queries
- [ ] Clean up unused storage files
- [ ] Review and update budget limits

#### Step 5.6: Cost Optimization Tips

1. **Use Indexes**: Proper Firestore indexes reduce read costs
2. **Pagination**: Limit query results to avoid large reads
3. **Cache Data**: Use local caching to reduce Firestore reads
4. **Clean Up**: Regularly delete test data and unused files
5. **Monitor Queries**: Use Firestore query insights to find expensive operations
6. **Use Emulators**: Use Firebase emulators for local development

---

## Quick Reference Commands

### Project Management
```bash
# List all projects
firebase projects:list

# Switch to dev project
firebase use dev

# Switch to production
firebase use production

# Check current project
firebase projects:list
```

### Building and Deploying
```bash
# Build Flutter web app
flutter build web --release

# Deploy to hosting
firebase deploy --only hosting

# Deploy everything
firebase deploy

# Deploy with specific project
firebase deploy --project bridge-app-dev
```

### Rules Deployment
```bash
# Deploy Firestore rules
firebase deploy --only firestore:rules

# Deploy Storage rules
firebase deploy --only storage:rules

# Deploy both
firebase deploy --only firestore:rules,storage:rules
```

### Emulators
```bash
# Start emulators
firebase emulators:start

# Start specific emulators
firebase emulators:start --only firestore,storage,auth
```

---

## Summary Checklist

Before deploying to development hosting:

- [ ] Created separate Firebase project for development
- [ ] Updated `.firebaserc` with dev project
- [ ] Created `firebase_options_dev.dart` or configured FlutterFire CLI
- [ ] Updated `firebase.json` with hosting configuration
- [ ] Added development banner/indicator to app
- [ ] Created and deployed development Firestore rules
- [ ] Created and deployed development Storage rules
- [ ] Set up billing alerts in Google Cloud Console
- [ ] Built Flutter web app (`flutter build web`)
- [ ] Deployed to Firebase Hosting (`firebase deploy --only hosting`)
- [ ] Verified development site is accessible
- [ ] Tested authentication and database operations

---

## Additional Resources

- [Firebase Hosting Documentation](https://firebase.google.com/docs/hosting)
- [Flutter Web Deployment](https://docs.flutter.dev/deployment/web)
- [Firebase Security Rules](https://firebase.google.com/docs/rules)
- [Firebase Pricing](https://firebase.google.com/pricing)
- [Firebase Emulator Suite](https://firebase.google.com/docs/emulator-suite)

---

## Support

If you encounter issues:

1. Check Firebase Console for error logs
2. Review Firebase Hosting deployment logs
3. Verify Firebase project configuration
4. Check Flutter web build output
5. Review browser console for runtime errors

---

**Last Updated**: 2024
**Project**: Bridge App
**Current Production Project**: `bridge-72b26`

