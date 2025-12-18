# Admin Interface Firebase Hosting Guide

This guide explains how to host your admin interface on Firebase Hosting.

## Prerequisites

1. **Firebase CLI installed**

   ```bash
   npm install -g firebase-tools
   ```

2. **Logged into Firebase**

   ```bash
   firebase login
   ```

3. **Flutter SDK installed** (for building the web app)

## Step 1: Build the Admin Web App

Since your admin interface uses `main_admin.dart` as the entry point, you need to build it specifically for web:

```bash
# Build the admin app for web (production mode)
flutter build web --release --target=lib/main_admin.dart

# Or for development with better debugging
flutter build web --target=lib/main_admin.dart
```

This will create the web build files in the `build/web` directory.

## Step 2: Verify Firebase Configuration

Make sure your `.firebaserc` file has the correct project:

```json
{
  "projects": {
    "default": "bridge-72b26"
  }
}
```

If you need to switch projects:

```bash
firebase use bridge-72b26
```

## Step 3: Deploy to Firebase Hosting

Once the build is complete, deploy to Firebase Hosting:

```bash
# Deploy only hosting
firebase deploy --only hosting

# Or deploy everything (hosting, functions, rules, etc.)
firebase deploy
```

## Step 4: Access Your Admin Interface

After deployment, your admin interface will be available at:

- `https://bridge-72b26.web.app`
- `https://bridge-72b26.firebaseapp.com`

## Quick Deploy Script

You can create a simple script to automate the build and deploy process:

### For Windows (PowerShell):

Create `deploy-admin.ps1`:

```powershell
Write-Host "Building admin web app..." -ForegroundColor Green
flutter build web --release --target=lib/main_admin.dart

if ($LASTEXITCODE -eq 0) {
    Write-Host "Deploying to Firebase Hosting..." -ForegroundColor Green
    firebase deploy --only hosting
} else {
    Write-Host "Build failed!" -ForegroundColor Red
}
```

Run it with:

```powershell
.\deploy-admin.ps1
```

### For Linux/Mac (Bash):

Create `deploy-admin.sh`:

```bash
#!/bin/bash
echo "Building admin web app..."
flutter build web --release --target=lib/main_admin.dart

if [ $? -eq 0 ]; then
    echo "Deploying to Firebase Hosting..."
    firebase deploy --only hosting
else
    echo "Build failed!"
    exit 1
fi
```

Make it executable and run:

```bash
chmod +x deploy-admin.sh
./deploy-admin.sh
```

## Custom Domain (Optional)

If you want to use a custom domain for your admin interface:

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project (`bridge-72b26`)
3. Navigate to **Hosting** in the left sidebar
4. Click **"Add custom domain"**
5. Enter your domain (e.g., `admin.yourdomain.com`)
6. Follow the DNS configuration instructions
7. Wait for SSL certificate provisioning (usually 24-48 hours)

## Troubleshooting

### Build Errors

- Make sure all dependencies are installed: `flutter pub get`
- Check that `main_admin.dart` exists and is valid
- Verify Firebase configuration in `lib/firebase_options.dart`

### Deployment Errors

- Ensure you're logged in: `firebase login`
- Check your project is set correctly: `firebase use bridge-72b26`
- Verify `firebase.json` has the hosting configuration

### Runtime Errors

- Check browser console for errors
- Verify Firebase configuration matches your project
- Ensure Firestore rules allow admin access
- Check that authentication is working correctly

## Updating the Admin Interface

To update your hosted admin interface:

1. Make your changes to the code
2. Rebuild: `flutter build web --release --target=lib/main_admin.dart`
3. Redeploy: `firebase deploy --only hosting`

## Security Considerations

1. **Firestore Rules**: Ensure your Firestore security rules properly restrict admin-only operations
2. **Authentication**: The admin interface requires authentication and admin privileges
3. **HTTPS**: Firebase Hosting automatically provides HTTPS
4. **Access Control**: Consider adding additional access controls if needed

## Additional Resources

- [Firebase Hosting Documentation](https://firebase.google.com/docs/hosting)
- [Flutter Web Deployment](https://docs.flutter.dev/deployment/web)
- [Firebase CLI Reference](https://firebase.google.com/docs/cli)
