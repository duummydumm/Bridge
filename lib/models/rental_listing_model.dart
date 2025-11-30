import 'package:cloud_firestore/cloud_firestore.dart';

enum PricingMode { perDay, perWeek, perMonth }

enum RentalType { item, apartment, boardingHouse, commercial }

class RentalListingModel {
  final String id;
  final String itemId;
  final String ownerId;
  final PricingMode pricingMode;
  final double? pricePerDay;
  final double? pricePerWeek;
  final double? pricePerMonth;
  final int? minDays;
  final int? maxDays;
  final double? securityDeposit;
  final String? cancellationPolicy;
  final String? termsUrl;
  final bool isActive;
  final bool
  allowMultipleRentals; // For commercial spaces/apartments - allow multiple concurrent rentals
  final int? quantity; // For items like clothes - how many units available
  final DateTime createdAt;
  final DateTime? updatedAt;

  // Rental type field
  final RentalType rentType; // item, apartment, boardingHouse, commercial

  // Fields for apartments
  final int? bedrooms;
  final int? bathrooms;
  final double? floorArea; // in square meters
  final bool? utilitiesIncluded;
  final String?
  address; // Full address for apartments/commercial/boarding houses

  // Fields for commercial spaces
  final String? allowedBusiness; // Type of business allowed
  final int? leaseTerm; // Lease term in months

  // Fields for boarding houses
  final bool? sharedCR; // Shared comfort room (bathroom)
  final bool? bedSpaceAvailable; // Bed space available
  final int? maxOccupants; // Maximum number of occupants
  final int? numberOfRooms; // Number of rooms in the boarding house
  final int? occupantsPerRoom; // Standard occupants per room
  final String?
  genderPreference; // Gender preference: "Male", "Female", "Mixed", "Any"
  final String? curfewRules; // Optional curfew rules
  final int?
  initialOccupants; // Pre-existing occupants before listing (not tracked in app)

  RentalListingModel({
    required this.id,
    required this.itemId,
    required this.ownerId,
    required this.pricingMode,
    this.pricePerDay,
    this.pricePerWeek,
    this.pricePerMonth,
    this.minDays,
    this.maxDays,
    this.securityDeposit,
    this.cancellationPolicy,
    this.termsUrl,
    required this.isActive,
    this.allowMultipleRentals = false, // Default: single rental at a time
    this.quantity, // null means single item, >1 means multiple units
    required this.createdAt,
    this.updatedAt,
    this.rentType =
        RentalType.item, // Default to item for backward compatibility
    this.bedrooms,
    this.bathrooms,
    this.floorArea,
    this.utilitiesIncluded,
    this.address,
    this.allowedBusiness,
    this.leaseTerm,
    this.sharedCR,
    this.bedSpaceAvailable,
    this.maxOccupants,
    this.numberOfRooms,
    this.occupantsPerRoom,
    this.genderPreference,
    this.curfewRules,
    this.initialOccupants,
  });

  factory RentalListingModel.fromMap(Map<String, dynamic> data, String id) {
    final modeString = (data['pricingMode'] ?? 'perDay')
        .toString()
        .toLowerCase();
    PricingMode mode;
    if (modeString == 'permonth') {
      mode = PricingMode.perMonth;
    } else if (modeString == 'perweek') {
      mode = PricingMode.perWeek;
    } else {
      mode = PricingMode.perDay;
    }

    // Parse rentType with backward compatibility (default to 'item' if not present)
    RentalType rentType = RentalType.item;
    final rentTypeString = (data['rentType'] ?? 'item')
        .toString()
        .toLowerCase();
    if (rentTypeString == 'apartment') {
      rentType = RentalType.apartment;
    } else if (rentTypeString == 'boardinghouse' ||
        rentTypeString == 'boarding_house') {
      rentType = RentalType.boardingHouse;
    } else if (rentTypeString == 'commercial') {
      rentType = RentalType.commercial;
    } else {
      rentType = RentalType.item;
    }

    return RentalListingModel(
      id: id,
      itemId: data['itemId'] ?? '',
      ownerId: data['ownerId'] ?? '',
      pricingMode: mode,
      pricePerDay: (data['pricePerDay'] is num)
          ? (data['pricePerDay'] as num).toDouble()
          : null,
      pricePerWeek: (data['pricePerWeek'] is num)
          ? (data['pricePerWeek'] as num).toDouble()
          : null,
      pricePerMonth: (data['pricePerMonth'] is num)
          ? (data['pricePerMonth'] as num).toDouble()
          : null,
      minDays: (data['minDays'] is int)
          ? data['minDays'] as int
          : int.tryParse('${data['minDays']}'),
      maxDays: (data['maxDays'] is int)
          ? data['maxDays'] as int
          : int.tryParse('${data['maxDays']}'),
      securityDeposit: (data['securityDeposit'] is num)
          ? (data['securityDeposit'] as num).toDouble()
          : null,
      cancellationPolicy: data['cancellationPolicy'],
      termsUrl: data['termsUrl'],
      isActive: data['isActive'] ?? true,
      allowMultipleRentals: data['allowMultipleRentals'] ?? false,
      quantity: (data['quantity'] is int) ? data['quantity'] as int : null,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      rentType: rentType,
      bedrooms: (data['bedrooms'] is int)
          ? data['bedrooms'] as int
          : int.tryParse('${data['bedrooms']}'),
      bathrooms: (data['bathrooms'] is int)
          ? data['bathrooms'] as int
          : int.tryParse('${data['bathrooms']}'),
      floorArea: (data['floorArea'] is num)
          ? (data['floorArea'] as num).toDouble()
          : null,
      utilitiesIncluded: data['utilitiesIncluded'] as bool?,
      address: data['address'] as String?,
      allowedBusiness: data['allowedBusiness'] as String?,
      leaseTerm: (data['leaseTerm'] is int)
          ? data['leaseTerm'] as int
          : int.tryParse('${data['leaseTerm']}'),
      sharedCR: data['sharedCR'] as bool?,
      bedSpaceAvailable: data['bedSpaceAvailable'] as bool?,
      maxOccupants: (data['maxOccupants'] is int)
          ? data['maxOccupants'] as int
          : int.tryParse('${data['maxOccupants']}'),
      numberOfRooms: (data['numberOfRooms'] is int)
          ? data['numberOfRooms'] as int
          : int.tryParse('${data['numberOfRooms']}'),
      occupantsPerRoom: (data['occupantsPerRoom'] is int)
          ? data['occupantsPerRoom'] as int
          : int.tryParse('${data['occupantsPerRoom']}'),
      genderPreference: data['genderPreference'] as String?,
      curfewRules: data['curfewRules'] as String?,
      initialOccupants: (data['initialOccupants'] is int)
          ? data['initialOccupants'] as int
          : int.tryParse('${data['initialOccupants']}'),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'itemId': itemId,
      'ownerId': ownerId,
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
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
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
  }

  RentalListingModel copyWith({
    String? id,
    String? itemId,
    String? ownerId,
    PricingMode? pricingMode,
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
    DateTime? createdAt,
    DateTime? updatedAt,
    RentalType? rentType,
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
    List<int>? availableRoomNumbers,
    String? curfewRules,
    int? initialOccupants,
  }) {
    return RentalListingModel(
      id: id ?? this.id,
      itemId: itemId ?? this.itemId,
      ownerId: ownerId ?? this.ownerId,
      pricingMode: pricingMode ?? this.pricingMode,
      pricePerDay: pricePerDay ?? this.pricePerDay,
      pricePerWeek: pricePerWeek ?? this.pricePerWeek,
      pricePerMonth: pricePerMonth ?? this.pricePerMonth,
      minDays: minDays ?? this.minDays,
      maxDays: maxDays ?? this.maxDays,
      securityDeposit: securityDeposit ?? this.securityDeposit,
      cancellationPolicy: cancellationPolicy ?? this.cancellationPolicy,
      termsUrl: termsUrl ?? this.termsUrl,
      isActive: isActive ?? this.isActive,
      allowMultipleRentals: allowMultipleRentals ?? this.allowMultipleRentals,
      quantity: quantity ?? this.quantity,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rentType: rentType ?? this.rentType,
      bedrooms: bedrooms ?? this.bedrooms,
      bathrooms: bathrooms ?? this.bathrooms,
      floorArea: floorArea ?? this.floorArea,
      utilitiesIncluded: utilitiesIncluded ?? this.utilitiesIncluded,
      address: address ?? this.address,
      allowedBusiness: allowedBusiness ?? this.allowedBusiness,
      leaseTerm: leaseTerm ?? this.leaseTerm,
      sharedCR: sharedCR ?? this.sharedCR,
      bedSpaceAvailable: bedSpaceAvailable ?? this.bedSpaceAvailable,
      maxOccupants: maxOccupants ?? this.maxOccupants,
      numberOfRooms: numberOfRooms ?? this.numberOfRooms,
      occupantsPerRoom: occupantsPerRoom ?? this.occupantsPerRoom,
      genderPreference: genderPreference ?? this.genderPreference,
      curfewRules: curfewRules ?? this.curfewRules,
      initialOccupants: initialOccupants ?? this.initialOccupants,
    );
  }
}
