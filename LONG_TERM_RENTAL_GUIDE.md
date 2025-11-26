# Long-Term Rental Guide

## What Does "Set isLongTerm = true" Mean?

When creating a rental request, you need to indicate whether it's a **long-term rental** (like an apartment with monthly payments) or a **short-term rental** (like a tool or equipment with fixed dates).

## How It Works

### Automatic Detection (Recommended)

I've updated `rent_item_screen.dart` to **automatically detect** long-term rentals based on:

1. **Pricing Mode**: If `pricingMode == PricingMode.perMonth`
2. **Listing Type**: If `allowMultipleRentals == true` (typically for apartments/commercial spaces)

When either condition is true, the system automatically:

- Sets `isLongTerm = true`
- Sets `monthlyPaymentAmount` from `listing.pricePerMonth`
- Sets `nextPaymentDueDate` to 30 days from start date

### Manual Setting (If Needed)

If you want to manually control this, you can pass the parameters when creating a rental request:

```dart
final id = await reqProvider.createRequest(
  listingId: listingId,
  itemId: itemId,
  ownerId: ownerId,
  renterId: renterId,
  startDate: startDate,
  endDate: endDate,
  durationDays: durationDays,
  priceQuote: priceQuote,
  fees: fees,
  totalDue: totalDue,
  depositAmount: depositAmount,
  // Long-term rental parameters
  isLongTerm: true,  // Set to true for monthly rentals
  monthlyPaymentAmount: 5000.0,  // Monthly payment amount
  nextPaymentDueDate: DateTime(2024, 2, 1),  // First payment due date
);
```

## Examples

### Example 1: Apartment Rental (Long-Term)

```dart
// Listing has:
// - pricingMode: PricingMode.perMonth
// - pricePerMonth: 5000.0
// - allowMultipleRentals: true

// When creating request:
final id = await reqProvider.createRequest(
  // ... other parameters
  isLongTerm: true,  // Automatically set if pricingMode is perMonth
  monthlyPaymentAmount: 5000.0,  // From listing.pricePerMonth
  nextPaymentDueDate: startDate.add(Duration(days: 30)),  // 30 days from start
);
```

### Example 2: Tool Rental (Short-Term)

```dart
// Listing has:
// - pricingMode: PricingMode.perDay
// - pricePerDay: 100.0

// When creating request:
final id = await reqProvider.createRequest(
  // ... other parameters
  isLongTerm: false,  // Default, not a monthly rental
  // monthlyPaymentAmount: null (not needed)
  // nextPaymentDueDate: null (not needed)
);
```

## What Happens When isLongTerm = true?

1. **Monthly Payment Tracking**: The system tracks `nextPaymentDueDate` and `lastPaymentDate`
2. **Payment Reminders**: Automatic reminders are sent:
   - 3 days before payment due
   - 1 day before payment due
   - On payment due date
   - Overdue reminders if payment is late
3. **Recurring Payments**: Each month, you record a new payment using `recordMonthlyRentalPayment()`
4. **No Fixed End Date**: For apartments, `endDate` might be far in the future or you can extend it monthly

## Recording Monthly Payments

After the rental is active, record monthly payments:

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
// - Schedules next month's payment reminders
```

## UI Considerations

For long-term rentals, you might want to:

1. **Show different UI**: Display "Monthly Payment" instead of "Total Price"
2. **Show payment schedule**: Display next payment due date
3. **Payment history**: Show all monthly payments made
4. **Extend rental**: Allow extending the rental month by month

## Current Implementation

The code in `rent_item_screen.dart` now automatically:

- Detects if listing is monthly (`pricingMode == PricingMode.perMonth`)
- Detects if listing allows multiple rentals (`allowMultipleRentals == true`)
- Sets `isLongTerm = true` for either case
- Sets monthly payment amount and first due date

**You don't need to manually set this anymore** - it's handled automatically! 🎉
