# Rental Features Implementation Guide

## Summary

I've implemented all the requested features for your rental app:

### ✅ 1. Automatic Rental End Reminders

- **What**: Both renter and owner receive automatic reminders when rental period ends
- **When**:
  - 24 hours before end date
  - 1 hour before end date
  - At end date
- **How**:
  - Reminders are scheduled when rental status changes to `active`
  - Uses both local notifications (offline) and FCM push notifications (online)
  - Cloud Function processes reminders every minute

### ✅ 2. Return Verification Workflow

- **What**: Two-step verification process for item returns
- **Process**:
  1. **Renter initiates return** → Status changes to `returnInitiated`
  2. **Owner verifies return** → Status changes to `returned` with `actualReturnDate`
- **Security**: Only renter can initiate, only owner can verify
- **Notifications**: Both parties receive notifications at each step

### ✅ 3. Long-Term Rental Support (Monthly Rentals)

- **What**: Support for ongoing rentals like apartments with monthly payments
- **Features**:
  - `isLongTerm` flag in rental request model
  - `monthlyPaymentAmount` tracking
  - `nextPaymentDueDate` and `lastPaymentDate` fields
  - Monthly payment recording via `recordMonthlyRentalPayment()`
  - Automatic monthly payment reminders (3 days before, 1 day before, on due date, overdue)

## Implementation Details

### Model Changes (`lib/models/rental_request_model.dart`)

**New Status:**

- `returnInitiated` - Renter has initiated return, waiting for owner verification

**New Fields:**

- `returnInitiatedBy` - User ID who initiated return
- `returnInitiatedAt` - Timestamp when return was initiated
- `returnVerifiedBy` - User ID who verified return
- `isLongTerm` - Boolean flag for monthly rentals
- `nextPaymentDueDate` - Next monthly payment due date
- `lastPaymentDate` - Last payment date
- `monthlyPaymentAmount` - Monthly payment amount

### Service Methods

#### `LocalNotificationsService`

**New Methods:**

- `scheduleRentalEndReminders()` - Schedules reminders for both renter and owner
- `cancelRentalReminders()` - Cancels all reminders for a rental

**Usage:**

```dart
await LocalNotificationsService().scheduleRentalEndReminders(
  rentalRequestId: requestId,
  itemId: itemId,
  itemTitle: itemTitle,
  endDateLocal: endDate,
  renterId: renterId,
  ownerId: ownerId,
  renterName: renterName,
  ownerName: ownerName,
);
```

#### `FirestoreService`

**New Methods:**

- `initiateRentalReturn()` - Renter initiates return
- `verifyRentalReturn()` - Owner verifies return
- `recordMonthlyRentalPayment()` - Record monthly payment
- `scheduleMonthlyPaymentReminders()` - Schedule monthly payment reminders

**Usage Examples:**

```dart
// Renter initiates return
await firestoreService.initiateRentalReturn(
  requestId: requestId,
  renterId: renterId,
);

// Owner verifies return
await firestoreService.verifyRentalReturn(
  requestId: requestId,
  ownerId: ownerId,
);

// Record monthly payment
await firestoreService.recordMonthlyRentalPayment(
  rentalRequestId: requestId,
  amount: 5000.0,
  paymentDate: DateTime.now(),
);
```

#### `RentalRequestProvider`

**New Methods:**

- `initiateReturn()` - Renter initiates return
- `verifyReturn()` - Owner verifies return

**Usage:**

```dart
// Renter
await rentalProvider.initiateReturn(requestId, renterId);

// Owner
await rentalProvider.verifyReturn(requestId, ownerId);
```

## How to Use

### 1. Schedule Reminders When Rental Becomes Active

When a rental status changes to `active`, you should schedule reminders. Add this to your code where rentals become active:

```dart
// In your screen/provider where rental becomes active
if (newStatus == 'active') {
  final request = await firestoreService.getRentalRequest(requestId);
  if (request != null) {
    final endDate = (request['endDate'] as Timestamp?)?.toDate();
    if (endDate != null) {
      // Get user names
      final renterData = await firestoreService.getUser(renterId);
      final ownerData = await firestoreService.getUser(ownerId);

      await LocalNotificationsService().scheduleRentalEndReminders(
        rentalRequestId: requestId,
        itemId: request['itemId'],
        itemTitle: itemTitle,
        endDateLocal: endDate,
        renterId: renterId,
        ownerId: ownerId,
        renterName: '${renterData['firstName']} ${renterData['lastName']}',
        ownerName: '${ownerData['firstName']} ${ownerData['lastName']}',
      );
    }
  }
}
```

### 2. Return Verification Workflow

**For Renter:**

```dart
// When renter wants to return item
if (request.status == RentalRequestStatus.active) {
  await rentalProvider.initiateReturn(requestId, currentUserId);
  // Status changes to returnInitiated
  // Owner receives notification
}
```

**For Owner:**

```dart
// When owner receives item and verifies
if (request.status == RentalRequestStatus.returnInitiated) {
  await rentalProvider.verifyReturn(requestId, currentUserId);
  // Status changes to returned
  // Renter receives notification
  // actualReturnDate is set
}
```

### 3. Long-Term Rentals (Monthly Payments)

**Creating a Long-Term Rental:**

```dart
// When creating rental request, set isLongTerm = true
final payload = {
  // ... other fields
  'isLongTerm': true,
  'monthlyPaymentAmount': 5000.0,
  'nextPaymentDueDate': DateTime.now().add(Duration(days: 30)),
  // ... rest of fields
};
```

**Recording Monthly Payment:**

```dart
await firestoreService.recordMonthlyRentalPayment(
  rentalRequestId: requestId,
  amount: 5000.0,
  paymentDate: DateTime.now(),
);
// This automatically:
// - Creates payment record
// - Updates lastPaymentDate
// - Calculates nextPaymentDueDate (next month)
```

**Scheduling Monthly Payment Reminders:**

```dart
await firestoreService.scheduleMonthlyPaymentReminders(
  rentalRequestId: requestId,
  itemId: itemId,
  itemTitle: itemTitle,
  nextPaymentDueDate: nextPaymentDue,
  renterId: renterId,
  ownerId: ownerId,
  renterName: renterName,
  ownerName: ownerName,
  monthlyAmount: 5000.0,
);
```

## UI Updates Needed

The `rental_detail_screen.dart` has been updated with a combined "Initiate/Verify Return" button that:

- Shows "Initiate Return" for renters when rental is active
- Shows "Verify Return" for owners when return is initiated
- Handles the workflow automatically

You may want to create separate screens or improve the UI to show:

- Current return status
- Who initiated return and when
- Who verified return and when
- For long-term rentals: next payment due date, last payment date

## Cloud Functions

The existing Cloud Function `checkAndSendReminders` in `functions/index.js` already handles sending reminders. It:

- Runs every minute
- Checks for due reminders
- Sends FCM push notifications
- Handles recurring overdue reminders

No changes needed to Cloud Functions - they already support the new reminder types.

## Testing Checklist

- [ ] Test rental end reminders (24h, 1h, due)
- [ ] Test return initiation by renter
- [ ] Test return verification by owner
- [ ] Test monthly payment recording
- [ ] Test monthly payment reminders
- [ ] Test that reminders are cancelled when rental is returned
- [ ] Test notifications for both parties

## Notes

1. **Reminder Scheduling**: Reminders should be scheduled when rental becomes `active`. You may want to add this to the `updateRentalRequest` method or call it from your UI when status changes.

2. **Long-Term Rentals**: For apartments, you may want to:

   - Set `isLongTerm = true` when creating the rental
   - Set `endDate` to a far future date or null
   - Use `nextPaymentDueDate` for tracking instead of `endDate`

3. **Return Verification**: The two-step process ensures both parties confirm the return, reducing disputes.

4. **Monthly Payments**: Each payment creates a record in `rental_payments` collection and updates the rental request with payment dates.
