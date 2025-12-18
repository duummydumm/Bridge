# Mobile OTP Setup Guide

This guide explains how to enable OTP verification on mobile apps (Android/iOS) using a backend service with EmailJS.

## Problem

EmailJS's public API key only works in browser environments. Mobile apps get a 403 error when trying to use the public API key directly. To enable OTP on mobile, you need to use EmailJS's **private API key** through a backend service.

## Solution: Backend API Proxy

Create a backend server that:

1. Receives email requests from your Flutter app
2. Uses EmailJS's private API key to send emails
3. Returns the result to your Flutter app

## Step 1: Get Your EmailJS Private API Key

1. Go to [EmailJS Dashboard](https://dashboard.emailjs.com/)
2. Navigate to **Account → API Keys**
3. Copy your **Private Key** (NOT the Public Key!)
   - ⚠️ **IMPORTANT**: Never expose the private key in your Flutter app
   - The private key should only be used in your backend server

## Step 2: Set Up Backend Server

### Option A: Use the Example Backend (Node.js/Express)

1. **Clone or copy the backend example:**

   ```bash
   cd backend-example
   ```

2. **Install dependencies:**

   ```bash
   npm install
   ```

3. **Create `.env` file:**

   ```bash
   cp .env.example .env
   ```

4. **Edit `.env` file with your credentials:**

   ```env
   EMAILJS_SERVICE_ID=service_hql50hi
   EMAILJS_TEMPLATE_ID=template_oyfh658
   EMAILJS_WELCOME_TEMPLATE_ID=template_dx6t43s
   EMAILJS_PRIVATE_KEY=your_private_api_key_here
   PORT=3000
   ```

5. **Run the server:**

   ```bash
   npm start
   ```

   Or for development with auto-reload:

   ```bash
   npm run dev
   ```

### Option B: Deploy to Cloud Platform

#### Deploy to Heroku

1. **Install Heroku CLI** (if not installed):

   ```bash
   # macOS
   brew install heroku/brew/heroku

   # Windows
   # Download from https://devcenter.heroku.com/articles/heroku-cli
   ```

2. **Login to Heroku:**

   ```bash
   heroku login
   ```

3. **Create a new Heroku app:**

   ```bash
   heroku create your-app-name
   ```

4. **Set environment variables:**

   ```bash
   heroku config:set EMAILJS_SERVICE_ID=service_hql50hi
   heroku config:set EMAILJS_TEMPLATE_ID=template_oyfh658
   heroku config:set EMAILJS_WELCOME_TEMPLATE_ID=template_dx6t43s
   heroku config:set EMAILJS_PRIVATE_KEY=your_private_api_key_here
   ```

5. **Deploy:**

   ```bash
   git init
   git add .
   git commit -m "Initial commit"
   git push heroku main
   ```

6. **Get your backend URL:**
   ```bash
   heroku info
   # Your backend URL will be: https://your-app-name.herokuapp.com
   ```

#### Deploy to Vercel

1. **Install Vercel CLI:**

   ```bash
   npm i -g vercel
   ```

2. **Create `vercel.json`:**

   ```json
   {
     "version": 2,
     "builds": [
       {
         "src": "server.js",
         "use": "@vercel/node"
       }
     ],
     "routes": [
       {
         "src": "/(.*)",
         "dest": "server.js"
       }
     ]
   }
   ```

3. **Deploy:**

   ```bash
   vercel
   ```

4. **Set environment variables in Vercel dashboard:**
   - Go to your project settings
   - Add all environment variables from `.env.example`

#### Deploy to Railway

1. **Install Railway CLI:**

   ```bash
   npm i -g @railway/cli
   ```

2. **Login:**

   ```bash
   railway login
   ```

3. **Initialize and deploy:**

   ```bash
   railway init
   railway up
   ```

4. **Set environment variables in Railway dashboard**

## Step 3: Update Flutter App Configuration

Update your `main.dart` to include the backend API URL:

```dart
import 'services/email_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ... other initialization code ...

  // Configure EmailJS with backend API URL
  await EmailService().configure(
    serviceId: 'service_hql50hi',
    templateId: 'template_oyfh658',
    publicKey: 'V4g4u9Bklz22oCTI1', // Public key (still needed for web)
    welcomeTemplateId: 'template_dx6t43s',
    backendApiUrl: 'https://your-backend-url.com', // Add your backend URL here
  );

  runApp(BridgeApp());
}
```

**For local development:**

- Android Emulator: Use `http://10.0.2.2:3000` (Android emulator's special IP for localhost)
- iOS Simulator: Use `http://localhost:3000`
- Physical Device: Use your computer's local IP (e.g., `http://192.168.1.100:3000`)

**For production:**

- Use your deployed backend URL (e.g., `https://your-app-name.herokuapp.com`)

## Step 4: Test OTP on Mobile

1. **Run your Flutter app on a mobile device/emulator**
2. **Register a new user**
3. **Check your email for the OTP code**
4. **Enter the OTP in the app**
5. **Verify that verification succeeds**

## How It Works

### Without Backend (Web Only)

```
Flutter App → EmailJS Public API → ❌ 403 Error on Mobile
```

### With Backend (Mobile + Web)

```
Flutter App → Your Backend API → EmailJS Private API → ✅ Email Sent
```

The backend server:

1. Receives the email request from your Flutter app
2. Replaces the public key with the private key
3. Sends the request to EmailJS API
4. Returns the result to your Flutter app

## Security Best Practices

1. **Never expose your private API key** in your Flutter app
2. **Use HTTPS** for your backend API in production
3. **Add rate limiting** to prevent abuse (optional but recommended)
4. **Add authentication** to your backend API (optional but recommended)
5. **Monitor your EmailJS usage** to prevent unexpected costs

## Optional: Add Rate Limiting

Install `express-rate-limit`:

```bash
npm install express-rate-limit
```

Add to `server.js`:

```javascript
const rateLimit = require("express-rate-limit");

const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // limit each IP to 100 requests per windowMs
});

app.use("/send-verification-email", limiter);
app.use("/send-welcome-email", limiter);
```

## Optional: Add API Authentication

Add a simple API key check:

```javascript
const API_KEY = process.env.API_KEY;

app.use("/send-verification-email", (req, res, next) => {
  const apiKey = req.headers["x-api-key"];
  if (apiKey !== API_KEY) {
    return res.status(401).json({ error: "Unauthorized" });
  }
  next();
});
```

Then in your Flutter app, add the API key to headers:

```dart
final response = await http.post(
  Uri.parse(apiUrl),
  headers: {
    'Content-Type': 'application/json',
    'x-api-key': 'your-api-key-here',
  },
  body: jsonEncode(emailData),
);
```

## Troubleshooting

### Backend returns 500 error

- Check that all environment variables are set correctly
- Verify your EmailJS private key is correct
- Check backend server logs for detailed error messages

### OTP emails not received

- Verify EmailJS service is properly connected
- Check EmailJS dashboard for error logs
- Verify email template configuration

### CORS errors

- Make sure CORS is enabled in your backend (already included in example)
- Check that your backend URL is correct

### Network errors on mobile

- For Android emulator, use `http://10.0.2.2:3000`
- For iOS simulator, use `http://localhost:3000`
- For physical devices, use your computer's local IP address
- Make sure your device and computer are on the same network

## Alternative: Firebase Cloud Functions

If you prefer using Firebase, you can create a Cloud Function instead:

```javascript
const functions = require("firebase-functions");
const axios = require("axios");

exports.sendVerificationEmail = functions.https.onRequest(async (req, res) => {
  // Same logic as backend server
  // Deploy with: firebase deploy --only functions
});
```

## Summary

1. ✅ Get EmailJS private API key
2. ✅ Set up backend server (Node.js example provided)
3. ✅ Deploy backend to cloud (Heroku, Vercel, Railway, etc.)
4. ✅ Update Flutter app with backend URL
5. ✅ Test OTP on mobile device

Now your OTP verification will work on both web and mobile! 🎉
