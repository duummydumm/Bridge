import 'package:flutter/foundation.dart';
import '../services/firestore_service.dart';

/// Helper class for fetching user names from Firestore
/// Provides reusable methods to get user full names without code duplication
class UserNameHelper {
  /// Get user's full name from user ID
  ///
  /// Parameters:
  /// - [userId]: The user ID to fetch name for
  /// - [firestoreService]: Instance of FirestoreService to access getUser method
  /// - [fallback]: Default name to return if user not found (default: 'Unknown')
  ///
  /// Returns the full name (firstName + lastName) or the fallback value
  static Future<String> getUserFullName(
    String? userId,
    FirestoreService firestoreService, {
    String fallback = 'Unknown',
  }) async {
    if (userId == null || userId.isEmpty) {
      return fallback;
    }

    try {
      final userData = await firestoreService.getUser(userId);
      if (userData != null) {
        final firstName = userData['firstName'] as String? ?? '';
        final lastName = userData['lastName'] as String? ?? '';
        final fullName = '$firstName $lastName'.trim();
        return fullName.isNotEmpty ? fullName : fallback;
      }
    } catch (e) {
      debugPrint('Error fetching user name for userId $userId: $e');
    }

    return fallback;
  }

  /// Get both owner and renter names from a rental request
  ///
  /// Parameters:
  /// - [request]: The rental request map containing ownerId and renterId
  /// - [firestoreService]: Instance of FirestoreService to access getUser method
  /// - [ownerFallback]: Default name for owner if not found (default: 'Owner')
  /// - [renterFallback]: Default name for renter if not found (default: 'Renter')
  ///
  /// Returns a map with 'ownerName' and 'renterName' keys
  static Future<Map<String, String>> getRentalPartyNames(
    Map<String, dynamic> request,
    FirestoreService firestoreService, {
    String ownerFallback = 'Owner',
    String renterFallback = 'Renter',
  }) async {
    final ownerId = request['ownerId'] as String?;
    final renterId = request['renterId'] as String?;

    final ownerName = await getUserFullName(
      ownerId,
      firestoreService,
      fallback: request['ownerName'] as String? ?? ownerFallback,
    );

    final renterName = await getUserFullName(
      renterId,
      firestoreService,
      fallback: request['renterName'] as String? ?? renterFallback,
    );

    return {'ownerName': ownerName, 'renterName': renterName};
  }

  /// Get owner name from a rental request
  ///
  /// Parameters:
  /// - [request]: The rental request map containing ownerId
  /// - [firestoreService]: Instance of FirestoreService to access getUser method
  /// - [fallback]: Default name for owner if not found (default: 'Owner')
  ///
  /// Returns the owner's full name
  static Future<String> getOwnerName(
    Map<String, dynamic> request,
    FirestoreService firestoreService, {
    String fallback = 'Owner',
  }) async {
    final ownerId = request['ownerId'] as String?;
    return await getUserFullName(
      ownerId,
      firestoreService,
      fallback: request['ownerName'] as String? ?? fallback,
    );
  }

  /// Get renter name from a rental request
  ///
  /// Parameters:
  /// - [request]: The rental request map containing renterId
  /// - [firestoreService]: Instance of FirestoreService to access getUser method
  /// - [fallback]: Default name for renter if not found (default: 'Renter')
  ///
  /// Returns the renter's full name
  static Future<String> getRenterName(
    Map<String, dynamic> request,
    FirestoreService firestoreService, {
    String fallback = 'Renter',
  }) async {
    final renterId = request['renterId'] as String?;
    return await getUserFullName(
      renterId,
      firestoreService,
      fallback: request['renterName'] as String? ?? fallback,
    );
  }
}
