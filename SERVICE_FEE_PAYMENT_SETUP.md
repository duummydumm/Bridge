# Service Fee Payment Setup Guide

## Overview

The service fee payment feature has been implemented for manual payment scenarios (meetup + GCash QR code). This allows renters to pay the platform service fee separately from the base rental price.

## What Was Implemented

### 1. **Rental Request Model Updates**

- Added `serviceFeePaid` (boolean) field to track payment status
- Added `serviceFeePaidAt` (DateTime) field to record payment timestamp

### 2. **Service Fee Payment Screen**

- New screen: `lib/screens/service_fee_payment_screen.dart`
- Displays platform GCash QR code
- Shows payment instructions
- Allows renters to mark service fee as paid after scanning

### 3. **Provider Updates**

- Added `markServiceFeePaid()` method to `RentalRequestProvider`
- Automatically sets `serviceFeePaid` to `true` and records timestamp

### 4. **UI Updates**

- **Rent Item Screen**: Added payment breakdown explanation
- **Pending Requests Screen**: Added service fee payment button and status indicator

## Configuration Required

### Step 1: Upload Your Platform QR Codes

1. Generate or obtain your platform GCash QR code image
2. Generate or obtain your platform GoTyme QR code image
3. Upload both to Firebase Storage (or any image hosting service)
4. Get the public URLs of both images

### Step 2: Update the QR Code URLs

Open `lib/screens/service_fee_payment_screen.dart` and find these lines (around lines 26-29):

```dart
static const String _platformGCashQRUrl =
    'https://via.placeholder.com/300x300?text=Platform+GCash+QR+Code';
static const String _platformGoTymeQRUrl =
    'https://via.placeholder.com/300x300?text=Platform+GoTyme+QR+Code';
```

Replace them with your actual QR code image URLs:

```dart
static const String _platformGCashQRUrl =
    'https://your-firebase-storage-url.com/platform-gcash-qr.png';
static const String _platformGoTymeQRUrl =
    'https://your-firebase-storage-url.com/platform-gotyme-qr.png';
```

**Note:** Users can now choose between GCash or GoTyme when paying the service fee!

### Step 3: Test the Feature

1. Create a rental request
2. Navigate to "Pending Requests" → "Rent" tab
3. You should see a "Service Fee Required" section with a "Pay Now" button
4. Click "Pay Now" to see the service fee payment screen
5. After marking as paid, the status should update to "Service Fee Paid"

## How It Works

### Payment Flow

1. **Renter creates rental request**

   - Service fee is calculated (5% of base price)
   - `serviceFeePaid` is set to `false` by default

2. **Renter views pending request**

   - Sees "Service Fee Required" with amount
   - Can click "Pay Now" button

3. **Service Fee Payment Screen**

   - Shows platform GCash QR code
   - Displays payment instructions
   - Renter scans QR code and pays via GCash app

4. **Mark as Paid**

   - Renter confirms payment completion
   - System updates `serviceFeePaid` to `true`
   - Records `serviceFeePaidAt` timestamp

5. **Status Update**
   - Request card shows "Service Fee Paid" with green checkmark
   - Payment button is hidden

## Payment Breakdown

For each rental:

- **Base Price**: Pay to owner via GCash QR in chat
- **Service Fee (5%)**: Pay separately to platform via QR code
- **Security Deposit**: Pay to owner, refundable after return

## Database Fields

The following fields are now stored in `rental_requests` collection:

```javascript
{
  serviceFeePaid: boolean,      // false by default
  serviceFeePaidAt: Timestamp,   // null until paid
  fees: number,                  // Service fee amount (5% of base)
  // ... other existing fields
}
```

## Notes

- Service fee is calculated automatically (5% of base price)
- Service fee payment is separate from owner payment
- Renters can pay service fee anytime after request is created
- Payment status is visible to both renter and owner
- **Users can choose between GCash or GoTyme** when paying the service fee
- Both QR codes should be static images (not dynamic)
- The payment method selector allows users to switch between GCash and GoTyme

## Future Enhancements

Consider adding:

- Admin dashboard to view all service fee payments
- Service fee payment history/reports
- Automatic reminders for unpaid service fees
- Integration with actual payment gateway (if moving to online payments)
