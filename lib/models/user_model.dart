import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

enum UserRole { borrower, lender, both }

class UserModel {
  final String uid;
  final String firstName;
  final String middleInitial;
  final String lastName;
  final String email;
  final String barangay;
  final String city;
  final String province;
  final String street;
  final UserRole role; // Borrower, Lender, Both
  final bool isVerified;
  final String verificationStatus; // pending, approved, rejected
  final String barangayIdType; // Voter's ID, National ID, Driver's License
  final String barangayIdUrl;
  final String profilePhotoUrl; // User profile picture
  final double reputationScore;
  final bool isAdmin; // Admin flag
  final bool isSuspended; // Suspension flag
  final int violationCount; // Number of violations
  final DateTime createdAt;

  UserModel({
    required this.uid,
    required this.firstName,
    required this.middleInitial,
    required this.lastName,
    required this.email,
    required this.barangay,
    required this.city,
    required this.province,
    required this.street,
    required this.role,
    required this.isVerified,
    required this.verificationStatus,
    required this.barangayIdType,
    required this.barangayIdUrl,
    required this.profilePhotoUrl,
    required this.reputationScore,
    required this.isAdmin,
    required this.isSuspended,
    required this.violationCount,
    required this.createdAt,
  });

  factory UserModel.fromMap(Map<String, dynamic> data, String documentId) {
    // Normalize role: handle both lowercase and original values
    final roleString = (data['role'] ?? 'both').toString().toLowerCase();

    // Debug: Print the role from database for troubleshooting
    debugPrint(
      '🔍 Loading user role from database: "$roleString" (original: ${data['role']})',
    );

    // Parse the actual role from database
    UserRole userRole;
    switch (roleString) {
      case 'borrower':
        userRole = UserRole.borrower;
        break;
      case 'lender':
        userRole = UserRole.lender;
        break;
      case 'both':
      default:
        userRole = UserRole.both;
        break;
    }

    return UserModel(
      uid: documentId,
      firstName: data['firstName'] ?? '',
      middleInitial: data['middleInitial'] ?? '',
      lastName: data['lastName'] ?? '',
      email: data['email'] ?? '',
      barangay: data['barangay'] ?? '',
      city: data['city'] ?? '',
      province: data['province'] ?? '',
      street: data['street'] ?? '',
      role: userRole,
      isVerified: data['isVerified'] ?? false,
      verificationStatus: (data['verificationStatus'] ?? 'pending').toString(),
      barangayIdType: data['barangayIdType'] ?? '',
      barangayIdUrl: data['barangayIdUrl'] ?? '',
      profilePhotoUrl: data['profilePhotoUrl'] ?? '',
      reputationScore: (data['reputationScore'] ?? 0).toDouble(),
      isAdmin: data['isAdmin'] ?? false,
      isSuspended: data['isSuspended'] ?? false,
      violationCount: (data['violationCount'] ?? 0) is int
          ? (data['violationCount'] ?? 0)
          : int.tryParse((data['violationCount'] ?? '0').toString()) ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'firstName': firstName,
      'middleInitial': middleInitial,
      'lastName': lastName,
      'email': email,
      'barangay': barangay,
      'city': city,
      'province': province,
      'street': street,
      'role': role.name.toLowerCase(), // Save lowercase for consistency
      'isVerified': isVerified,
      'verificationStatus': verificationStatus,
      'barangayIdType': barangayIdType,
      'barangayIdUrl': barangayIdUrl,
      'profilePhotoUrl': profilePhotoUrl,
      'reputationScore': reputationScore,
      'isAdmin': isAdmin,
      'isSuspended': isSuspended,
      'violationCount': violationCount,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  // Helper method to capitalize first letter of each word
  String _capitalize(String text) {
    if (text.isEmpty) return text;
    return text
        .split(' ')
        .map((word) {
          if (word.isEmpty) return word;
          if (word.length == 1) return word.toUpperCase();
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        })
        .join(' ');
  }

  String get fullName =>
      '${_capitalize(firstName)} $middleInitial. ${_capitalize(lastName)}';
  String get fullAddress =>
      '${_capitalize(street)}, ${_capitalize(barangay)}, ${_capitalize(city)}, ${_capitalize(province)}';

  // Get capitalized versions for display
  String get displayFirstName => _capitalize(firstName);
  String get displayLastName => _capitalize(lastName);
  String get displayStreet => _capitalize(street);
  String get displayBarangay => _capitalize(barangay);
  String get displayCity => _capitalize(city);
  String get displayProvince => _capitalize(province);

  // Helper methods for role
  bool get canBorrow => role == UserRole.borrower || role == UserRole.both;
  bool get canLend => role == UserRole.lender || role == UserRole.both;
  bool get isBothRoles => role == UserRole.both;
}
