# Monthly Rental Process Guide

## The Problem

For apartment rentals (monthly rentals), the renter doesn't know when they'll move out. They need:

- **Start Date**: When they move in (required)
- **End Date**: Unknown - rental continues month-to-month (optional)

## The Solution

I've updated the system to handle **month-to-month rentals** where the end date is optional.

## How It Works Now

### For Monthly Rentals (Apartments)

1. **Start Date**: Required - when renter moves in
2. **End Date**: **Optional** - if not provided, rental is "month-to-month" (ongoing)
3. **Monthly Payments**: Automatically tracked and reminded
4. **No Fixed End**: Rental continues until either party ends it

### For Short-Term Rentals (Tools, Equipment)

1. **Start Date**: Required
2. **End Date**: **Required** - fixed rental period
3. **Total Price**: Calculated based on duration
4. **Fixed End**: Rental ends on specified date

## UI Changes

### Date Selection Screen

For **monthly rentals** (when `pricingMode == PricingMode.perMonth` or `allowMultipleRentals == true`):

- **Start Date**: Required (clickable date picker)
- **End Date**:
  - Shows "Month-to-month" with "Optional" badge
  - Disabled (not clickable)
  - Shows "Ongoing rental" subtitle
  - User can still select an end date if they know it (by tapping)

For **short-term rentals**:

- **Start Date**: Required
- **End Date**: Required (clickable date picker)

## Data Model Changes

### RentalRequestModel

```dart
final DateTime startDate;        // Required
final DateTime? endDate;         // Optional (null = month-to-month)
final int? durationDays;          // Optional (null = ongoing)
final bool isLongTerm;            // true for monthly rentals
final DateTime? nextPaymentDueDate; // For monthly payments
final double? monthlyPaymentAmount; // Monthly payment amount
```

## Process Flow

### Creating a Monthly Rental (Apartment)

1. **User selects listing** with `pricingMode: perMonth`
2. **User picks start date** (move-in date)
3. **End date field shows "Month-to-month"** (optional)
4. **User clicks "Calculate Quote"**:
   - If no end date: Calculates for first month only
   - If end date provided: Calculates for full duration
5. **User creates request**:
   - `isLongTerm = true`
   - `endDate = null` (if not selected)
   - `monthlyPaymentAmount` = listing's `pricePerMonth`
   - `nextPaymentDueDate` = start date + 30 days

### Monthly Payment Process

1. **First Month**: Paid upfront (or on start date)
2. **Subsequent Months**:
   - System sends reminders 3 days before, 1 day before, on due date
   - Renter records payment using `recordMonthlyRentalPayment()`
   - System automatically calculates next month's due date
   - Process repeats monthly

### Ending a Monthly Rental

Either party can end the rental:

- **Renter initiates return** → Status: `returnInitiated`
- **Owner verifies return** → Status: `returned`
- **Actual return date** is recorded

## Example Scenarios

### Scenario 1: Apartment - No End Date

```
Start Date: January 1, 2024
End Date: null (month-to-month)
Monthly Payment: ₱5,000
Next Payment Due: February 1, 2024

Process:
- Jan 1: Rental starts, first month paid
- Feb 1: Second month payment due (reminder sent)
- Mar 1: Third month payment due (reminder sent)
- ... continues until either party ends it
```

### Scenario 2: Apartment - With End Date

```
Start Date: January 1, 2024
End Date: June 30, 2024 (6 months)
Monthly Payment: ₱5,000
Next Payment Due: February 1, 2024

Process:
- Jan 1: Rental starts, first month paid
- Feb 1 - Jun 1: Monthly payments
- Jun 30: Rental ends (or earlier if returned)
```

### Scenario 3: Tool Rental - Fixed Dates

```
Start Date: January 1, 2024
End Date: January 5, 2024 (5 days)
Total Price: ₱500 (₱100/day × 5 days)

Process:
- Jan 1: Rental starts
- Jan 5: Rental ends, item must be returned
```

## Code Examples

### Creating Monthly Rental (No End Date)

```dart
final id = await reqProvider.createRequest(
  listingId: listingId,
  itemId: itemId,
  ownerId: ownerId,
  renterId: renterId,
  startDate: DateTime(2024, 1, 1),
  endDate: null,  // Month-to-month
  durationDays: null,  // Ongoing
  priceQuote: 5000.0,  // First month
  fees: 250.0,
  totalDue: 5250.0,
  isLongTerm: true,
  monthlyPaymentAmount: 5000.0,
  nextPaymentDueDate: DateTime(2024, 2, 1),
);
```

### Recording Monthly Payment

```dart
await firestoreService.recordMonthlyRentalPayment(
  rentalRequestId: requestId,
  amount: 5000.0,
  paymentDate: DateTime.now(),
);
// Automatically:
// - Updates lastPaymentDate
// - Calculates nextPaymentDueDate (next month)
// - Schedules next month's reminders
```

## Key Points

1. **End Date is Optional** for monthly rentals
2. **Month-to-Month** means ongoing until terminated
3. **Monthly Payments** are tracked separately from initial payment
4. **Reminders** are sent automatically for monthly payments
5. **Either Party** can end the rental anytime

## UI Display

When showing rental details, for monthly rentals without end date:

- Show: "Start Date: Jan 1, 2024"
- Show: "End Date: Month-to-month (Ongoing)"
- Show: "Next Payment Due: Feb 1, 2024"
- Show: "Monthly Payment: ₱5,000"

This makes it clear the rental is ongoing and when the next payment is due!
