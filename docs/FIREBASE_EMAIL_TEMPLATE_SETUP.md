# Firebase Email Template Setup - Prevent Spam

This guide shows you how to customize Firebase email templates to improve deliverability and prevent emails from going to spam.

## Step 1: Customize Firebase Email Template

### Go to Firebase Console

1. **Open Firebase Console**: https://console.firebase.google.com/
2. **Select your project**
3. **Navigate to**: Authentication → Templates
4. **Click on**: "Email address verification"

### Customize the Email Template

#### Subject Line (Important!)

Use a clear, professional subject line:

```
Verify Your Bridge Account Email
```

**Avoid spam trigger words:**

- ❌ "FREE", "URGENT", "ACT NOW"
- ✅ "Verify", "Confirm", "Welcome"

#### Email Body Template

Use this template for better deliverability:

```
Hello,

Please verify your email address by clicking the link below:

[Verification Link]

This link will expire in 24 hours.

If you didn't create a Bridge account, please ignore this email.

Best regards,
Bridge Team
```

**Best Practices:**

- ✅ Clear, professional language
- ✅ Include your app name (Bridge)
- ✅ Mention expiration time
- ✅ Include "ignore if not you" message
- ✅ No excessive capitalization
- ✅ No spam trigger words

### Save the Template

Click "Save" after customizing.

---

## Step 2: Configure Action URL (Optional but Recommended)

This allows users to verify directly in your app.

### Steps:

1. **Go to**: Authentication → Settings
2. **Scroll to**: "Authorized domains"
3. **Add your domain** (if you have one)
4. **Set Action URL** (optional):
   - Format: `https://your-app.com/verify-email`
   - This allows deep linking to your app

---

## Step 3: Add Instructions in Your App

Your app already includes instructions to check spam folder (updated in `verify_email.dart`).

The verification screen now shows:

- ✅ "Check your spam/junk folder" message
- ✅ Warning that email may take a few minutes

---

## Step 4: Additional Firebase Settings

### Configure Authorized Domains

1. **Go to**: Authentication → Settings
2. **Under "Authorized domains"**, ensure:
   - Your app domain is listed
   - Firebase default domains are included

### Email Action Handler (Advanced)

If you have a custom domain:

1. **Set up custom email handler**:
   - Configure DNS records
   - Set up email action handler URL
   - This improves deliverability

---

## Step 5: Test Email Deliverability

### Test Your Emails

1. **Register a test user**
2. **Check email inbox** (should arrive in inbox)
3. **Check spam folder** (should not be there)
4. **Test with different email providers**:
   - Gmail
   - Outlook
   - Yahoo
   - Others

### Use Email Testing Tools

- **Mail-tester.com**: Test spam score
- **MXToolbox**: Check email authentication
- **Gmail/Outlook**: Test in real inboxes

---

## Quick Checklist

- [ ] Customized email subject line
- [ ] Updated email body with professional content
- [ ] Removed spam trigger words
- [ ] Added app name and branding
- [ ] Configured authorized domains
- [ ] Tested email deliverability
- [ ] App shows spam folder instructions

---

## Why This Helps

### Customized Templates:

- ✅ Better deliverability than default templates
- ✅ Professional appearance
- ✅ Users recognize your app name
- ✅ Less likely to be marked as spam

### App Instructions:

- ✅ Users know to check spam folder
- ✅ Reduces support requests
- ✅ Better user experience

---

## Troubleshooting

### Emails Still Going to Spam?

1. **Check email content**:

   - Remove any spam trigger words
   - Use professional language
   - Include your app name

2. **Test with different email providers**:

   - Some providers are stricter than others
   - Gmail is usually most strict

3. **Wait for reputation to build**:

   - New email senders may have lower deliverability
   - It improves over time with good practices

4. **Consider custom domain** (Advanced):
   - Set up SPF/DKIM records
   - Use your own domain for emails
   - Better long-term deliverability

---

## Summary

1. ✅ Customize Firebase email template (Subject + Body)
2. ✅ Remove spam trigger words
3. ✅ Add professional content
4. ✅ Configure authorized domains
5. ✅ Test email deliverability
6. ✅ App already shows spam folder instructions

**Result**: Better email deliverability and fewer spam issues! 🎉

---

## Next Steps

If emails still go to spam after these steps, consider:

- Using EmailJS backend (better deliverability)
- Setting up custom domain with SPF/DKIM
- Using Firebase Extensions for custom email service
