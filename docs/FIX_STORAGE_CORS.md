# Fix Firebase Storage CORS for Admin Web App

The images aren't loading because Firebase Storage needs CORS (Cross-Origin Resource Sharing) configuration to allow your deployed admin web app to access images.

## Problem

Your admin app is deployed at:

- `https://bridge-72b26.web.app`
- `https://bridge-72b26.firebaseapp.com`

But Firebase Storage CORS is only configured for `localhost`, so the deployed app can't load images from Storage.

## Solution

Apply the updated CORS configuration to your Firebase Storage bucket.

## Method 1: Using gsutil (Recommended)

### Step 1: Install Google Cloud SDK

If you don't have it installed:

**Windows:**

1. Download from: https://cloud.google.com/sdk/docs/install
2. Run the installer
3. Restart your terminal

**Mac/Linux:**

```bash
# Mac
brew install google-cloud-sdk

# Or download from: https://cloud.google.com/sdk/docs/install
```

### Step 2: Authenticate

```bash
gcloud auth login
```

### Step 3: Set Your Project

```bash
gcloud config set project bridge-72b26
```

### Step 4: Apply CORS Configuration

```bash
gsutil cors set cors.json gs://bridge-72b26.firebasestorage.app
```

**Note:** If your bucket name is different, check it in Firebase Console → Storage. The bucket name is shown at the top right (grey pill) or at the bottom as `gs://{bucket-name}`. Common formats are `{project-id}.appspot.com` or `{project-id}.firebasestorage.app`.

### Step 5: Verify CORS Configuration

```bash
    gsutil cors get gs://bridge-72b26.firebasestorage.app
```

You should see the updated CORS configuration with your Firebase Hosting domains.

## Method 2: Using Firebase Console (Alternative)

Unfortunately, Firebase Console doesn't have a direct CORS configuration UI. You'll need to use gsutil (Method 1) or the Google Cloud Console.

## Method 3: Using Google Cloud Console

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Select your project: `bridge-72b26`
3. Navigate to **Cloud Storage** → **Buckets**
4. Click on your storage bucket (usually `bridge-72b26.firebasestorage.app`)
5. Go to the **Configuration** tab
6. Scroll to **CORS configuration**
7. Click **Edit CORS configuration**
8. Paste the contents of `cors.json`:
   ```json
   [
     {
       "origin": [
         "http://localhost:*",
         "http://127.0.0.1:*",
         "https://bridge-72b26.web.app",
         "https://bridge-72b26.firebaseapp.com"
       ],
       "method": ["GET", "POST", "PUT", "DELETE", "HEAD", "OPTIONS"],
       "responseHeader": [
         "Content-Type",
         "Authorization",
         "x-goog-meta-*",
         "x-goog-acl",
         "x-goog-date"
       ],
       "maxAgeSeconds": 3600
     }
   ]
   ```
9. Click **Save**

## Verify It Works

After applying the CORS configuration:

1. Open your admin app: `https://bridge-72b26.web.app`
2. Navigate to User Verification
3. Open a user's verification details
4. The ID images should now load properly

## Troubleshooting

### If images still don't load:

1. **Check browser console** (F12) for CORS errors
2. **Verify bucket name** - Make sure you're using the correct bucket name:
   ```bash
   gsutil ls
   ```
3. **Wait a few minutes** - CORS changes can take a few minutes to propagate
4. **Clear browser cache** - Hard refresh (Ctrl+Shift+R or Cmd+Shift+R)
5. **Check Storage Rules** - Make sure your `storage.rules` allow read access

### Check Storage Bucket Name

In Firebase Console:

1. Go to **Storage**
2. Click the **Settings** (gear icon)
3. Look for **Bucket** - this is your bucket name

### Your Bucket Name:

- `bridge-72b26.firebasestorage.app` ✅ (This is your bucket - shown in Firebase Console)

If your bucket is different, update the command:

```bash
gsutil cors set cors.json gs://YOUR-BUCKET-NAME
```

## Additional Notes

- **Custom Domains**: If you add a custom domain later, add it to `cors.json` and reapply:

  ```json
  "origin": [
    "http://localhost:*",
    "http://127.0.0.1:*",
    "https://bridge-72b26.web.app",
    "https://bridge-72b26.firebaseapp.com",
    "https://admin.yourdomain.com"  // Add your custom domain
  ]
  ```

- **Wildcards**: The `*` in `localhost:*` means any port. For production domains, specify exact domains without wildcards.

## Quick Command Reference

```bash
# Set CORS
gsutil cors set cors.json gs://bridge-72b26.firebasestorage.app

# Get current CORS
gsutil cors get gs://bridge-72b26.firebasestorage.app

# List buckets
gsutil ls

# Check if gsutil is installed
gsutil version
```
