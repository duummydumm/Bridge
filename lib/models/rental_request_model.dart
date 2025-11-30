import 'package:cloud_firestore/cloud_firestore.dart';

enum RentalRequestStatus {
  draft,
  requested,
  ownerApproved,
  renterPaid,
  active,
  returnInitiated, // Renter has initiated return, waiting for owner verification
  returned,
  cancelled,
  disputed,
}

enum PaymentStatus { unpaid, authorized, captured, refunded, partial }

enum PaymentMethod { online, meetup }

class RentalRequestModel {
  final String id;
  final String listingId;
  final String itemId;
  final String ownerId;
  final String renterId;
  final DateTime startDate;
  final DateTime? endDate; // Nullable for long-term rentals (apartments)
  final int? durationDays; // Nullable for long-term rentals
  final double priceQuote;
  final double fees;
  final double totalDue;
  final double? depositAmount;
  final RentalRequestStatus status;
  final PaymentStatus paymentStatus;
  final DateTime returnDueDate;
  final DateTime? actualReturnDate;
  final String? returnInitiatedBy; // User ID who initiated return
  final DateTime? returnInitiatedAt;
  final String? returnVerifiedBy; // User ID who verified return
  final bool isLongTerm; // For monthly rentals like apartments
  final DateTime? nextPaymentDueDate; // For monthly rentals
  final DateTime? lastPaymentDate; // For monthly rentals
  final double? monthlyPaymentAmount; // For monthly rentals
  final PaymentMethod paymentMethod; // Payment method: online or meetup
  final List<int>?
  assignedRoomNumbers; // For boarding houses: which rooms are assigned to this rental
  final int?
  numberOfOccupants; // For boarding houses: number of people in this rental
  final String? notes;
  final DateTime createdAt;
  final DateTime? updatedAt;

  RentalRequestModel({
    required this.id,
    required this.listingId,
    required this.itemId,
    required this.ownerId,
    required this.renterId,
    required this.startDate,
    required this.endDate,
    required this.durationDays,
    required this.priceQuote,
    required this.fees,
    required this.totalDue,
    this.depositAmount,
    required this.status,
    required this.paymentStatus,
    required this.returnDueDate,
    this.actualReturnDate,
    this.returnInitiatedBy,
    this.returnInitiatedAt,
    this.returnVerifiedBy,
    this.isLongTerm = false,
    this.nextPaymentDueDate,
    this.lastPaymentDate,
    this.monthlyPaymentAmount,
    this.paymentMethod =
        PaymentMethod.meetup, // Default to meetup for backward compatibility
    this.assignedRoomNumbers,
    this.numberOfOccupants,
    this.notes,
    required this.createdAt,
    this.updatedAt,
  });

  factory RentalRequestModel.fromMap(Map<String, dynamic> data, String id) {
    RentalRequestStatus parseStatus(String? s) {
      switch ((s ?? 'requested').toLowerCase()) {
        case 'draft':
          return RentalRequestStatus.draft;
        case 'requested':
          return RentalRequestStatus.requested;
        case 'ownerapproved':
          return RentalRequestStatus.ownerApproved;
        case 'renterpaid':
          return RentalRequestStatus.renterPaid;
        case 'active':
          return RentalRequestStatus.active;
        case 'returninitiated':
          return RentalRequestStatus.returnInitiated;
        case 'returned':
          return RentalRequestStatus.returned;
        case 'cancelled':
          return RentalRequestStatus.cancelled;
        case 'disputed':
          return RentalRequestStatus.disputed;
        default:
          return RentalRequestStatus.requested;
      }
    }

    PaymentStatus parsePayment(String? s) {
      switch ((s ?? 'unpaid').toLowerCase()) {
        case 'unpaid':
          return PaymentStatus.unpaid;
        case 'authorized':
          return PaymentStatus.authorized;
        case 'captured':
          return PaymentStatus.captured;
        case 'refunded':
          return PaymentStatus.refunded;
        case 'partial':
          return PaymentStatus.partial;
        default:
          return PaymentStatus.unpaid;
      }
    }

    PaymentMethod parsePaymentMethod(String? s) {
      switch ((s ?? 'meetup').toLowerCase()) {
        case 'online':
          return PaymentMethod.online;
        case 'meetup':
          return PaymentMethod.meetup;
        default:
          return PaymentMethod.meetup;
      }
    }

    return RentalRequestModel(
      id: id,
      listingId: data['listingId'] ?? '',
      itemId: data['itemId'] ?? '',
      ownerId: data['ownerId'] ?? '',
      renterId: data['renterId'] ?? '',
      startDate: (data['startDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endDate: (data['endDate'] as Timestamp?)?.toDate(),
      durationDays: (data['durationDays'] is int)
          ? data['durationDays'] as int
          : (data['durationDays'] != null
                ? int.tryParse('${data['durationDays']}')
                : null),
      priceQuote: (data['priceQuote'] is num)
          ? (data['priceQuote'] as num).toDouble()
          : 0.0,
      fees: (data['fees'] is num) ? (data['fees'] as num).toDouble() : 0.0,
      totalDue: (data['totalDue'] is num)
          ? (data['totalDue'] as num).toDouble()
          : 0.0,
      depositAmount: (data['depositAmount'] is num)
          ? (data['depositAmount'] as num).toDouble()
          : null,
      status: parseStatus(data['status']?.toString()),
      paymentStatus: parsePayment(data['paymentStatus']?.toString()),
      returnDueDate:
          (data['returnDueDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      actualReturnDate: (data['actualReturnDate'] as Timestamp?)?.toDate(),
      returnInitiatedBy: data['returnInitiatedBy'],
      returnInitiatedAt: (data['returnInitiatedAt'] as Timestamp?)?.toDate(),
      returnVerifiedBy: data['returnVerifiedBy'],
      isLongTerm: data['isLongTerm'] ?? false,
      nextPaymentDueDate: (data['nextPaymentDueDate'] as Timestamp?)?.toDate(),
      lastPaymentDate: (data['lastPaymentDate'] as Timestamp?)?.toDate(),
      monthlyPaymentAmount: (data['monthlyPaymentAmount'] is num)
          ? (data['monthlyPaymentAmount'] as num).toDouble()
          : null,
      paymentMethod: parsePaymentMethod(data['paymentMethod']?.toString()),
      assignedRoomNumbers: data['assignedRoomNumbers'] != null
          ? (data['assignedRoomNumbers'] as List)
                .map((e) => e is int ? e : int.tryParse('$e'))
                .whereType<int>()
                .toList()
          : null,
      numberOfOccupants: (data['numberOfOccupants'] is int)
          ? data['numberOfOccupants'] as int
          : int.tryParse('${data['numberOfOccupants']}'),
      notes: data['notes'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'listingId': listingId,
      'itemId': itemId,
      'ownerId': ownerId,
      'renterId': renterId,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': endDate != null ? Timestamp.fromDate(endDate!) : null,
      'durationDays': durationDays,
      'priceQuote': priceQuote,
      'fees': fees,
      'totalDue': totalDue,
      'depositAmount': depositAmount,
      'status': status.name,
      'paymentStatus': paymentStatus.name,
      'returnDueDate': Timestamp.fromDate(returnDueDate),
      'actualReturnDate': actualReturnDate != null
          ? Timestamp.fromDate(actualReturnDate!)
          : null,
      'returnInitiatedBy': returnInitiatedBy,
      'returnInitiatedAt': returnInitiatedAt != null
          ? Timestamp.fromDate(returnInitiatedAt!)
          : null,
      'returnVerifiedBy': returnVerifiedBy,
      'isLongTerm': isLongTerm,
      'nextPaymentDueDate': nextPaymentDueDate != null
          ? Timestamp.fromDate(nextPaymentDueDate!)
          : null,
      'lastPaymentDate': lastPaymentDate != null
          ? Timestamp.fromDate(lastPaymentDate!)
          : null,
      'monthlyPaymentAmount': monthlyPaymentAmount,
      'paymentMethod': paymentMethod.name,
      'assignedRoomNumbers': assignedRoomNumbers,
      'numberOfOccupants': numberOfOccupants,
      'notes': notes,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    };
  }
}
