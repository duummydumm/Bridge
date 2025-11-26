# Rental Features Analysis & Implementation Plan

## Current Implementation Status

### ✅ What's Already Implemented:

1. **Rental Request Model**

   - Has `startDate`, `endDate`, `returnDueDate`, and `actualReturnDate` fields
   - Status tracking: `draft`, `requested`, `ownerApproved`, `renterPaid`, `active`, `returned`, `cancelled`, `disputed`
   - Payment status tracking: `unpaid`, `authorized`, `captured`, `refunded`, `partial`

2. **Reminder Infrastructure**

   - FCM reminder system with Cloud Functions (`checkAndSendReminders` runs every minute)
   - Local notification service with `scheduleReturnReminders` method
   - Reminder storage in Firestore `reminders` collection
   - **BUT**: Currently only used for **borrow requests**, NOT rentals

3. **Return Tracking**

   - Manual "Mark Returned" button in `rental_detail_screen.dart`
   - `actualReturnDate` field exists in model
   - **BUT**: No verification workflow - just a single button click

4. **Long-Term Rental Support (Partial)**
   - `PricingMode.perMonth` exists in `RentalListingModel`
   - `allowMultipleRentals` flag for apartments/commercial spaces
   - **BUT**: No recurring payment logic or monthly reminders

### ❌ What's Missing:

1. **Automatic Rental End Reminders**

   - No reminders scheduled when rental becomes `active`
   - No automatic reminders for renter and owner when `endDate` approaches
   - Reminder system exists but not connected to rentals

2. **Return Verification Workflow**

   - Currently: Single "Mark Returned" button (anyone can click)
   - Needed: Renter initiates return → Owner verifies → System confirms
   - No two-step verification process

3. **Long-Term Rental Support**
   - No recurring monthly payment tracking
   - No monthly payment reminders
   - No automatic renewal logic
   - No distinction between fixed-term and ongoing rentals

## Implementation Plan

### 1. Automatic Rental End Reminders

- Schedule reminders when rental status changes to `active`
- Create reminders for both renter and owner:
  - 24 hours before end date
  - 1 hour before end date
  - At end date
  - Daily overdue reminders if not returned

### 2. Return Verification Workflow

- Add `returnInitiatedBy` and `returnVerifiedBy` fields to rental request
- Add `returnInitiatedAt` timestamp
- Renter can initiate return → Status: `returnInitiated`
- Owner can verify return → Status: `returned` (with `actualReturnDate`)
- Add UI for both actions

### 3. Long-Term Rental Support

- Add `isLongTerm` boolean to `RentalRequestModel`
- Add `nextPaymentDueDate` for monthly rentals
- Add `lastPaymentDate` tracking
- Add `monthlyPaymentAmount` field
- Create monthly payment reminder system
- Add recurring payment logic
