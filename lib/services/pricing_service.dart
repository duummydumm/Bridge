import 'dart:math';
import '../models/rental_listing_model.dart';

class PricingService {
  const PricingService();

  double _daysBetween(DateTime start, DateTime end) {
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    return max(0, e.difference(s).inDays.toDouble());
  }

  Map<String, dynamic> quote({
    required RentalListingModel listing,
    required DateTime startDate,
    required DateTime endDate,
    double serviceFeeRate = 0.05,
  }) {
    final rawDays = _daysBetween(startDate, endDate);
    final durationDays = rawDays.ceil();

    if (listing.minDays != null && durationDays < listing.minDays!) {
      throw ArgumentError('Minimum rental duration is ${listing.minDays} days');
    }
    if (listing.maxDays != null && durationDays > listing.maxDays!) {
      throw ArgumentError('Maximum rental duration is ${listing.maxDays} days');
    }

    double base = 0.0;
    if (listing.pricingMode == PricingMode.perDay) {
      final rate = listing.pricePerDay ?? 0.0;
      base = rate * durationDays;
    } else if (listing.pricingMode == PricingMode.perWeek) {
      final rate = listing.pricePerWeek ?? 0.0;
      final weeks = (durationDays / 7).ceil();
      base = rate * weeks;
    } else {
      // perMonth
      final rate = listing.pricePerMonth ?? 0.0;
      final months = (durationDays / 30).ceil();
      base = rate * months;
    }

    final fees = base * serviceFeeRate;
    final deposit = listing.securityDeposit ?? 0.0;
    final total = base + fees + deposit;

    return {
      'durationDays': durationDays,
      'priceQuote': base,
      'fees': fees,
      'depositAmount': deposit,
      'totalDue': total,
    };
  }
}
