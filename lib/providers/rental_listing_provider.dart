import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../models/rental_listing_model.dart';

class RentalListingProvider extends ChangeNotifier {
  final FirestoreService _firestore = FirestoreService();

  List<RentalListingModel> _myListings = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<RentalListingModel> get myListings => _myListings;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadMyListings(String ownerId) async {
    try {
      _setLoading(true);
      _clearError();
      final data = await _firestore.getRentalListingsByOwner(ownerId);
      _myListings = data
          .map((m) => RentalListingModel.fromMap(m, m['id'] as String))
          .toList();
      _setLoading(false);
      notifyListeners();
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<String?> createListing({
    required String itemId,
    required String ownerId,
    required String ownerName,
    required String title,
    String? description,
    String? condition,
    String? category,
    String? location,
    String? imageUrl,
    List<String>? images,
    required PricingMode pricingMode,
    double? pricePerDay,
    double? pricePerWeek,
    double? pricePerMonth,
    int? minDays,
    int? maxDays,
    double? securityDeposit,
    String? cancellationPolicy,
    String? termsUrl,
    bool isActive = true,
    bool allowMultipleRentals = false,
    int? quantity,
    required RentalType rentType,
    int? bedrooms,
    int? bathrooms,
    double? floorArea,
    bool? utilitiesIncluded,
    String? address,
    String? allowedBusiness,
    int? leaseTerm,
    bool? sharedCR,
    bool? bedSpaceAvailable,
    int? maxOccupants,
    int? numberOfRooms,
    int? occupantsPerRoom,
    String? genderPreference,
    String? curfewRules,
    int? initialOccupants,
  }) async {
    try {
      _setLoading(true);
      _clearError();
      final payload = {
        'itemId': itemId,
        'ownerId': ownerId,
        'ownerName': ownerName,
        'title': title,
        'description': description,
        'condition': condition,
        'category': category,
        'location': location,
        'imageUrl': imageUrl,
        'images': images ?? (imageUrl != null ? [imageUrl] : null),
        'pricingMode': pricingMode.name,
        'pricePerDay': pricePerDay,
        'pricePerWeek': pricePerWeek,
        'pricePerMonth': pricePerMonth,
        'minDays': minDays,
        'maxDays': maxDays,
        'securityDeposit': securityDeposit,
        'cancellationPolicy': cancellationPolicy,
        'termsUrl': termsUrl,
        'isActive': isActive,
        'allowMultipleRentals': allowMultipleRentals,
        'quantity': quantity,
        'createdAt': DateTime.now(),
        'updatedAt': DateTime.now(),
        'rentType': rentType == RentalType.boardingHouse
            ? 'boarding_house'
            : rentType.name,
        'bedrooms': bedrooms,
        'bathrooms': bathrooms,
        'floorArea': floorArea,
        'utilitiesIncluded': utilitiesIncluded,
        'address': address,
        'allowedBusiness': allowedBusiness,
        'leaseTerm': leaseTerm,
        'sharedCR': sharedCR,
        'bedSpaceAvailable': bedSpaceAvailable,
        'maxOccupants': maxOccupants,
        'numberOfRooms': numberOfRooms,
        'occupantsPerRoom': occupantsPerRoom,
        'genderPreference': genderPreference,
        'curfewRules': curfewRules,
        'initialOccupants': initialOccupants,
      };
      final id = await _firestore.createRentalListing(payload);
      _setLoading(false);
      notifyListeners();
      return id;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
      return null;
    }
  }

  Future<bool> setListingActive(String listingId, bool isActive) async {
    try {
      _setLoading(true);
      _clearError();
      await _firestore.updateRentalListing(listingId, {
        'isActive': isActive,
        'updatedAt': DateTime.now(),
      });
      _setLoading(false);
      notifyListeners();
      return true;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
      return false;
    }
  }

  Future<RentalListingModel?> getListing(String listingId) async {
    try {
      _setLoading(true);
      _clearError();
      final data = await _firestore.getRentalListing(listingId);
      if (data == null) {
        _setLoading(false);
        notifyListeners();
        return null;
      }
      final listing = RentalListingModel.fromMap(data, data['id'] as String);
      _setLoading(false);
      notifyListeners();
      return listing;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
      return null;
    }
  }

  Future<bool> updateListing({
    required String listingId,
    required String title,
    String? description,
    String? condition,
    String? category,
    String? location,
    String? imageUrl,
    List<String>? images,
    required PricingMode pricingMode,
    double? pricePerDay,
    double? pricePerWeek,
    double? pricePerMonth,
    int? minDays,
    int? maxDays,
    double? securityDeposit,
    String? cancellationPolicy,
    String? termsUrl,
    bool? isActive,
    bool? allowMultipleRentals,
    int? quantity,
    required RentalType rentType,
    int? bedrooms,
    int? bathrooms,
    double? floorArea,
    bool? utilitiesIncluded,
    String? address,
    String? allowedBusiness,
    int? leaseTerm,
    bool? sharedCR,
    bool? bedSpaceAvailable,
    int? maxOccupants,
    int? numberOfRooms,
    int? occupantsPerRoom,
    String? genderPreference,
    String? curfewRules,
    int? initialOccupants,
  }) async {
    try {
      _setLoading(true);
      _clearError();
      final payload = <String, dynamic>{
        'title': title,
        'description': description,
        'condition': condition,
        'category': category,
        'location': location,
        'pricingMode': pricingMode.name,
        'pricePerDay': pricePerDay,
        'pricePerWeek': pricePerWeek,
        'pricePerMonth': pricePerMonth,
        'minDays': minDays,
        'maxDays': maxDays,
        'securityDeposit': securityDeposit,
        'cancellationPolicy': cancellationPolicy,
        'termsUrl': termsUrl,
        'updatedAt': DateTime.now(),
        'rentType': rentType == RentalType.boardingHouse
            ? 'boarding_house'
            : rentType.name,
        'bedrooms': bedrooms,
        'bathrooms': bathrooms,
        'floorArea': floorArea,
        'utilitiesIncluded': utilitiesIncluded,
        'address': address,
        'allowedBusiness': allowedBusiness,
        'leaseTerm': leaseTerm,
        'sharedCR': sharedCR,
        'bedSpaceAvailable': bedSpaceAvailable,
        'maxOccupants': maxOccupants,
        'numberOfRooms': numberOfRooms,
        'occupantsPerRoom': occupantsPerRoom,
        'curfewRules': curfewRules,
        'initialOccupants': initialOccupants,
      };
      if (imageUrl != null) {
        payload['imageUrl'] = imageUrl;
      }
      if (images != null) {
        payload['images'] = images;
        // Also set imageUrl to first image for backward compatibility
        if (images.isNotEmpty && imageUrl == null) {
          payload['imageUrl'] = images.first;
        }
      }
      if (isActive != null) {
        payload['isActive'] = isActive;
      }
      if (allowMultipleRentals != null) {
        payload['allowMultipleRentals'] = allowMultipleRentals;
      }
      if (quantity != null) {
        payload['quantity'] = quantity;
      } else {
        payload['quantity'] = null; // Explicitly set to null if not provided
      }
      await _firestore.updateRentalListing(listingId, payload);
      _setLoading(false);
      notifyListeners();
      return true;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
      return false;
    }
  }

  void _setLoading(bool v) {
    _isLoading = v;
  }

  void _setError(String msg) {
    _errorMessage = msg;
  }

  void _clearError() {
    _errorMessage = null;
  }

  Future<bool> deleteListing(String listingId) async {
    try {
      _setLoading(true);
      _clearError();

      // Check if listing has active rental requests
      final hasActive = await _firestore.hasActiveRentalRequests(listingId);
      if (hasActive) {
        _setError(
          'Cannot delete listing with active rental requests. Please wait for all rentals to complete.',
        );
        _setLoading(false);
        notifyListeners();
        return false;
      }

      // Delete the listing
      await _firestore.deleteRentalListing(listingId);

      // Remove from local list
      _myListings.removeWhere((listing) => listing.id == listingId);

      _setLoading(false);
      notifyListeners();
      return true;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
      return false;
    }
  }
}
