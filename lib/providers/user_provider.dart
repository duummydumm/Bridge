import 'dart:async';
import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../services/storage_service.dart';
import '../models/user_model.dart';

class UserProvider extends ChangeNotifier {
  final FirestoreService _firestoreService = FirestoreService();
  final StorageService _storageService = StorageService();

  UserModel? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;
  StreamSubscription<Map<String, dynamic>?>? _userStreamSubscription;

  // Getters
  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasUser => _currentUser != null;

  // Create user profile
  Future<bool> createUserProfile({
    required String uid,
    required String firstName,
    required String middleInitial,
    required String lastName,
    required String email,
    required String province,
    required String city,
    required String barangay,
    required String street,
    required String role,
    required String barangayIdType,
    required String barangayIdUrl,
    String? barangayIdUrlBack,
  }) async {
    try {
      _setLoading(true);
      _clearError();

      // Normalize email and address fields to lowercase for consistent duplicate checking
      final normalizedEmail = email.trim().toLowerCase();

      // Check for potential duplicates (similar name/address) for admin review
      final potentialDuplicates = await _firestoreService
          .findPotentialDuplicates(
            firstName: firstName.trim(),
            lastName: lastName.trim(),
            street: street.trim(),
            barangay: barangay.trim(),
            city: city.trim(),
          );

      // Normalize street address for storage
      final normalizedStreet = _normalizeAddressForStorage(street.trim());

      final userData = {
        'firstName': firstName
            .trim()
            .toLowerCase(), // Normalized for duplicate checking
        'middleInitial': middleInitial.trim(),
        'lastName': lastName
            .trim()
            .toLowerCase(), // Normalized for duplicate checking
        'email': normalizedEmail,
        'province': province.trim(),
        'city': city.trim().toLowerCase(), // Normalized for duplicate checking
        'barangay': barangay
            .trim()
            .toLowerCase(), // Normalized for duplicate checking
        'street': normalizedStreet, // Normalized for duplicate checking
        'role': role,
        'isVerified': false,
        'verificationStatus': 'pending',
        'barangayIdType': barangayIdType,
        'barangayIdUrl': barangayIdUrl,
        if (barangayIdUrlBack != null) 'barangayIdUrlBack': barangayIdUrlBack,
        'reputationScore': 0.0,
        'profilePhotoUrl': '',
        'isSuspended':
            false, // Always set this field so Firestore rules can check it
        'createdAt': DateTime.now(),
        // Flag for admin review if potential duplicates found
        'hasPotentialDuplicates': potentialDuplicates.isNotEmpty,
        'potentialDuplicateCount': potentialDuplicates.length,
      };

      await _firestoreService.setUser(uid, userData);

      // Load the created user
      await loadUserProfile(uid);

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

  // Load user profile
  Future<bool> loadUserProfile(String uid) async {
    try {
      // Prevent multiple simultaneous calls for the same user
      if (_isLoading && _currentUser?.uid == uid) {
        // Already loading this user, wait for it to complete
        return true;
      }

      // If we already have this user loaded and not loading, skip
      if (!_isLoading &&
          _currentUser?.uid == uid &&
          _userStreamSubscription != null) {
        return true;
      }

      _setLoading(true);
      _clearError();

      if (uid.isEmpty) {
        _setLoading(false);
        notifyListeners();
        return false;
      }

      // Cancel existing stream subscription if any
      await _userStreamSubscription?.cancel();

      // First, load user data once to get initial state
      final userData = await _firestoreService.getUser(uid);

      if (userData != null) {
        _currentUser = UserModel.fromMap(userData, uid);
        _setLoading(false);
        notifyListeners();

        // Start listening to real-time updates
        _userStreamSubscription = _firestoreService
            .getUserStream(uid)
            .listen(
              (updatedUserData) {
                if (updatedUserData != null) {
                  final newUser = UserModel.fromMap(updatedUserData, uid);
                  // Only notify listeners if user data actually changed
                  // This prevents unnecessary rebuilds
                  if (_currentUser?.uid != newUser.uid ||
                      _currentUser?.email != newUser.email ||
                      _currentUser?.isVerified != newUser.isVerified ||
                      _currentUser?.isAdmin != newUser.isAdmin ||
                      _currentUser?.verificationStatus !=
                          newUser.verificationStatus) {
                    _currentUser = newUser;
                    notifyListeners();
                  } else {
                    // Update silently if only minor fields changed
                    _currentUser = newUser;
                  }
                }
              },
              onError: (error) {
                debugPrint('Error in user stream: $error');
                // Don't update user on stream error, keep current state
              },
            );

        return true;
      }

      _setLoading(false);
      notifyListeners();
      return false;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
      return false;
    }
  }

  // Upload ID image
  Future<String?> uploadIdImage(
    dynamic file,
    String userHint, {
    bool isFront = true,
  }) async {
    try {
      _setLoading(true);
      _clearError();

      final imageUrl = await _storageService.uploadBarangayIdImage(
        file: file,
        userHint: userHint,
        isFront: isFront,
      );

      // If user was previously rejected, reset verification status to pending
      // when they upload a new ID
      if (_currentUser != null &&
          _currentUser!.verificationStatus == 'rejected') {
        await _firestoreService.setUser(_currentUser!.uid, {
          'barangayIdUrl': imageUrl,
          'verificationStatus': 'pending',
          'isVerified': false,
          'rejectionReason': '', // Clear previous rejection reason
        });
        // Reload user profile to reflect changes
        await loadUserProfile(_currentUser!.uid);
      } else if (_currentUser != null) {
        // Just update the ID URL if not rejected
        await _firestoreService.setUser(_currentUser!.uid, {
          'barangayIdUrl': imageUrl,
        });
        await loadUserProfile(_currentUser!.uid);
      }

      _setLoading(false);
      notifyListeners();
      return imageUrl;
    } catch (e) {
      _setError(e.toString());
      _setLoading(false);
      notifyListeners();
      return null;
    }
  }

  // Upload and save profile photo
  Future<bool> uploadProfilePhoto({required dynamic file}) async {
    try {
      if (_currentUser == null) return false;
      _setLoading(true);
      _clearError();

      final url = await _storageService.uploadProfilePhoto(
        file: file,
        userId: _currentUser!.uid,
      );

      await _firestoreService.setUser(_currentUser!.uid, {
        'profilePhotoUrl': url,
      });

      // Create activity log for profile photo update
      try {
        await _firestoreService.createActivityLog(
          category: 'user',
          action: 'profile_photo_updated',
          actorId: _currentUser!.uid,
          actorName: '${_currentUser!.firstName} ${_currentUser!.lastName}'
              .trim(),
          targetId: _currentUser!.uid,
          targetType: 'user',
          description: 'User updated their profile photo',
          metadata: {'userId': _currentUser!.uid, 'photoUrl': url},
          severity: 'info',
        );
      } catch (e) {
        debugPrint('Error creating activity log for profile photo: $e');
        // Don't fail photo upload if logging fails
      }

      // reload current user
      await loadUserProfile(_currentUser!.uid);

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

  // Update user information (resets verification status if previously rejected)
  Future<bool> updateUserInformation({
    String? firstName,
    String? middleInitial,
    String? lastName,
    String? province,
    String? city,
    String? barangay,
    String? street,
    String? barangayIdType,
    String? barangayIdUrl,
  }) async {
    try {
      if (_currentUser == null) return false;
      _setLoading(true);
      _clearError();

      final updateData = <String, dynamic>{};

      if (firstName != null) {
        updateData['firstName'] = firstName.trim().toLowerCase();
      }

      if (middleInitial != null) {
        updateData['middleInitial'] = middleInitial.trim();
      }
      if (lastName != null) {
        updateData['lastName'] = lastName.trim().toLowerCase();
      }
      if (province != null) updateData['province'] = province.trim();
      if (city != null) updateData['city'] = city.trim().toLowerCase();
      if (barangay != null)
        updateData['barangay'] = barangay.trim().toLowerCase();
      if (street != null)
        updateData['street'] = _normalizeAddressForStorage(street.trim());
      if (barangayIdType != null) updateData['barangayIdType'] = barangayIdType;
      if (barangayIdUrl != null) updateData['barangayIdUrl'] = barangayIdUrl;

      // If user was previously rejected and they're updating their info,
      // reset verification status to pending
      if (_currentUser!.verificationStatus == 'rejected') {
        updateData['verificationStatus'] = 'pending';
        updateData['isVerified'] = false;
        updateData['rejectionReason'] = ''; // Clear previous rejection reason
      }

      await _firestoreService.setUser(_currentUser!.uid, updateData);

      // Reload user profile to reflect changes
      await loadUserProfile(_currentUser!.uid);

      // Create activity log for profile update
      try {
        final fieldsUpdated = <String>[];
        if (firstName != null) fieldsUpdated.add('firstName');
        if (lastName != null) fieldsUpdated.add('lastName');
        if (middleInitial != null) fieldsUpdated.add('middleInitial');
        if (province != null) fieldsUpdated.add('province');
        if (city != null) fieldsUpdated.add('city');
        if (barangay != null) fieldsUpdated.add('barangay');
        if (street != null) fieldsUpdated.add('street');
        if (barangayIdType != null) fieldsUpdated.add('barangayIdType');
        if (barangayIdUrl != null) fieldsUpdated.add('barangayIdUrl');

        await _firestoreService.createActivityLog(
          category: 'user',
          action: 'profile_updated',
          actorId: _currentUser!.uid,
          actorName: '${_currentUser!.firstName} ${_currentUser!.lastName}'
              .trim(),
          description: 'User updated their profile information',
          metadata: {
            'fieldsUpdated': fieldsUpdated.join(', '),
            'userId': _currentUser!.uid,
          },
          severity: 'info',
        );
      } catch (e) {
        // Don't fail profile update if logging fails
        debugPrint('Error creating activity log for profile update: $e');
      }

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

  // Helper methods
  void _setLoading(bool loading) {
    _isLoading = loading;
  }

  void _setError(String error) {
    _errorMessage = error;
  }

  void _clearError() {
    _errorMessage = null;
  }

  void clearError() {
    _clearError();
    notifyListeners();
  }

  void clearUser() {
    // Cancel stream subscription when user logs out
    _userStreamSubscription?.cancel();
    _userStreamSubscription = null;
    _currentUser = null;
    notifyListeners();
  }

  @override
  void dispose() {
    // Clean up stream subscription when provider is disposed
    _userStreamSubscription?.cancel();
    super.dispose();
  }

  // Check if a user with the given email already exists
  Future<bool> checkEmailExists(String email) async {
    try {
      _clearError();
      return await _firestoreService.userExistsByEmail(email);
    } catch (e) {
      _setError(e.toString());
      return false;
    }
  }

  // Check if a user with the same name and address already exists
  Future<bool> checkUserExistsByNameAndAddress({
    required String firstName,
    required String lastName,
    required String street,
    required String barangay,
    required String city,
  }) async {
    try {
      _clearError();
      return await _firestoreService.userExistsByNameAndAddress(
        firstName: firstName,
        lastName: lastName,
        street: street,
        barangay: barangay,
        city: city,
      );
    } catch (e) {
      _setError(e.toString());
      return false;
    }
  }

  // Find potential duplicate accounts (for admin review)
  Future<List<Map<String, dynamic>>> findPotentialDuplicates({
    required String firstName,
    required String lastName,
    required String street,
    required String barangay,
    required String city,
  }) async {
    try {
      _clearError();
      return await _firestoreService.findPotentialDuplicates(
        firstName: firstName,
        lastName: lastName,
        street: street,
        barangay: barangay,
        city: city,
      );
    } catch (e) {
      _setError(e.toString());
      return [];
    }
  }

  // Normalize address for storage (same logic as FirestoreService)
  String _normalizeAddressForStorage(String address) {
    if (address.isEmpty) return '';
    String normalized = address.trim().toLowerCase();
    // Replace common address abbreviations
    normalized = normalized.replaceAll(RegExp(r'\bst\b'), 'street');
    normalized = normalized.replaceAll(RegExp(r'\bave\b'), 'avenue');
    normalized = normalized.replaceAll(RegExp(r'\bblvd\b'), 'boulevard');
    normalized = normalized.replaceAll(RegExp(r'\bdr\b'), 'drive');
    normalized = normalized.replaceAll(RegExp(r'\brd\b'), 'road');
    normalized = normalized.replaceAll(RegExp(r'\bct\b'), 'court');
    // Remove extra spaces and special characters
    normalized = normalized.replaceAll(RegExp(r'[^\w\s]'), '');
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ');
    return normalized.trim();
  }
}
