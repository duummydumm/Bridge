# EmailJS Setup Guide

This guide explains how to configure EmailJS for email verification in the Bridge app.

## Prerequisites

1. Sign up for a free account at [EmailJS](https://www.emailjs.com/)
2. Create an email service (Gmail, Outlook, etc.)
3. Create an email template

## Step 1: Get Your EmailJS Credentials

1. Go to [EmailJS Dashboard](https://dashboard.emailjs.com/)
2. Navigate to **Email Services** and create a new service (e.g., Gmail)
3. Navigate to **Email Templates** and create a new template
4. Get your credentials:
   - **Service ID**: Found in Email Services
   - **Template ID**: Found in Email Templates
   - **Public Key (User ID)**: Found in Account → API Keys

## Step 2: Configure EmailJS in Your App

You have two options to configure EmailJS:

### Option 1: Configure Programmatically (Recommended)

Add this code in your `main.dart` or initialization code:

```dart
import 'services/email_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ... other initialization code ...

  // Configure EmailJS
  await EmailService().configure(
    serviceId: 'YOUR_SERVICE_ID',
    templateId: 'YOUR_VERIFICATION_TEMPLATE_ID',  // For OTP verification emails
    publicKey: 'YOUR_PUBLIC_KEY',
    welcomeTemplateId: 'YOUR_WELCOME_TEMPLATE_ID',  // Optional: For welcome emails
  );

  runApp(BridgeApp());
}
```

### Option 2: Configure via SharedPreferences

The EmailJS service will automatically load configuration from SharedPreferences if it was previously saved. You can also set it manually:

```dart
final prefs = await SharedPreferences.getInstance();
await prefs.setString('emailjs_service_id', 'YOUR_SERVICE_ID');
await prefs.setString('emailjs_template_id', 'YOUR_TEMPLATE_ID');
await prefs.setString('emailjs_public_key', 'YOUR_PUBLIC_KEY');
```

## Step 3: Create Email Templates

You need to create two templates in EmailJS:

### Template 1: Verification Email (OTP)

**IMPORTANT:** In your EmailJS verification template, you MUST configure the "To Email" field to use the `{{to_email}}` parameter.

**Steps to configure:**

1. Go to EmailJS Dashboard → Email Templates
2. Select your verification template (`template_oyfh658`)
3. In the "To Email" field, enter: `{{to_email}}` (this is critical!)
4. In the "Subject" field, you can use: `Verify Your Email Address`
5. In the "Content" field, use these template parameters:

Template parameters:

- `{{to_email}}` - Recipient's email address (MUST be used in "To Email" field)
- `{{to_name}}` - Recipient's name
- `{{otp}}` - The 6-digit verification code (this is the most important one!)

Example verification template content:

```
Subject: Verify Your Email Address

Hello {{to_name}},

Your verification code is: {{otp}}

This code will expire in 10 minutes.

If you didn't create an account, please ignore this email.

Thank you,
Bridge Team
```

### Template 2: Welcome Email (Optional)

In your EmailJS welcome template, use these template parameters:

- `{{to_email}}` - Recipient's email address
- `{{to_name}}` - Recipient's name

Example welcome template:

```
Subject: Welcome to Bridge!

Hello {{to_name}},

Welcome to Bridge! We're excited to have you join our community.

Your email has been verified and your account is now active.

Get started by exploring items available for borrowing, renting, trading, or claiming.

If you have any questions, feel free to reach out to our support team.

Thank you,
Bridge Team
```

**Note:** The welcome email is automatically sent after successful email verification. If you don't configure a welcome template, the welcome email will be skipped (verification will still work).

## Step 4: Test Email Verification

1. Register a new user
2. Check your email for the verification link
3. Click the verification link
4. You should be redirected to the app and your email should be verified

## Troubleshooting

### Email not sending

- Check that EmailJS credentials are correctly configured
- Verify your email service is properly connected
- Check EmailJS dashboard for error logs

### Verification link not working

- Ensure the app base URL is correct
- Check that the verification route is properly configured in `main.dart`
- Verify the token is being extracted from the URL correctly

### Token expired

- Tokens expire after 24 hours
- Users can request a new verification email from the verification screen

## Notes

- The verification system stores OTP codes in Firestore under the `email_verifications` collection
- User verification status is stored in the `users` collection with the `emailVerified` field
- OTP codes expire after 10 minutes
- Maximum 5 verification attempts per OTP
- OTP codes are automatically cleaned up after verification or expiration
- Welcome email is automatically sent after successful verification (if configured)
- Welcome email failure won't affect verification - verification will still succeed even if welcome email fails
