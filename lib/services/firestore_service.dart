import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../services/storage_service.dart';
import 'local_notifications_service.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Maximum number of pending borrow requests a user can have at once
  // This prevents abuse and ensures users focus on active requests
  static const int maxPendingBorrowRequests = 5;

  // Maximum number of items a user can have actively borrowed at once
  // This prevents hoarding and ensures items circulate back to the community
  static const int maxActiveBorrows = 3;

  Future<String> createUser(Map<String, dynamic> data) async {
    // Server timestamps for createdAt if provided as DateTime
    final payload = Map<String, dynamic>.from(data);
    if (payload['createdAt'] is DateTime) {
      payload['createdAt'] = Timestamp.fromDate(payload['createdAt']);
    }
    final docRef = await _db.collection('users').add(payload);
    return docRef.id;
  }

  // Borrow request operations
  Future<String?> createBorrowRequest({
    required String itemId,
    required String itemTitle,
    required String lenderId,
    required String lenderName,
    required String borrowerId,
    required String borrowerName,
    String? message,
  }) async {
    try {
      // Validate that lender and borrower are different
      if (lenderId == borrowerId) {
        throw Exception(
          'Cannot create borrow request: lender and borrower are the same',
        );
      }

      // Prevent duplicate pending requests by the same borrower for the same item
      final existing = await _db
          .collection('borrow_requests')
          .where('itemId', isEqualTo: itemId)
          .where('borrowerId', isEqualTo: borrowerId)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) {
        return existing.docs.first.id; // Already requested
      }

      // Check if user has reached the maximum pending requests limit
      final pendingCount = await getPendingBorrowRequestCount(borrowerId);
      if (pendingCount >= maxPendingBorrowRequests) {
        throw Exception(
          'You have reached the maximum limit of $maxPendingBorrowRequests pending borrow requests. '
          'Please wait for some requests to be processed or cancel existing requests before requesting new items.',
        );
      }

      final payload = <String, dynamic>{
        'itemId': itemId,
        'itemTitle': itemTitle,
        'lenderId': lenderId,
        'lenderName': lenderName,
        'borrowerId': borrowerId,
        'borrowerName': borrowerName,
        'message': message ?? '',
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final docRef = await _db.collection('borrow_requests').add(payload);

      // Create a lightweight notification for the lender ONLY (never for borrower)
      // Triple-check: lenderId != borrowerId, lenderId is not empty, and toUserId will be lenderId
      if (lenderId != borrowerId && lenderId.isNotEmpty) {
        // Final safety check: ensure we're never sending notification to borrower
        if (lenderId == borrowerId) {
          debugPrint(
            'ERROR: Attempted to create notification for borrower! lenderId=$lenderId, borrowerId=$borrowerId - ABORTING',
          );
          return docRef.id; // Return without creating notification
        }

        try {
          debugPrint(
            'Creating borrow request notification: toUserId=$lenderId (lender), fromUserId=$borrowerId (borrower), requestId=${docRef.id}',
          );
          final notificationData = {
            'toUserId': lenderId, // MUST be lender, NEVER borrower
            'type': 'borrow_request',
            'itemId': itemId,
            'itemTitle': itemTitle,
            'fromUserId': borrowerId,
            'fromUserName': borrowerName,
            'requestId': docRef.id,
            'status': 'unread',
            'createdAt': FieldValue.serverTimestamp(),
          };

          // Final validation before creating notification
          if (notificationData['toUserId'] == borrowerId) {
            debugPrint(
              'CRITICAL ERROR: Notification toUserId matches borrowerId! Not creating notification.',
            );
            return docRef.id; // Return without creating notification
          }

          await _db.collection('notifications').add(notificationData);
          debugPrint(
            'Borrow request notification created successfully for lender: $lenderId',
          );
          debugPrint(
            'Verification: Notification toUserId=${notificationData['toUserId']}, borrowerId=$borrowerId (should be different)',
          );
        } catch (e) {
          debugPrint('Error creating borrow request notification: $e');
          // Best-effort; don't fail the request if notification write fails
        }
      } else {
        debugPrint(
          'Skipping notification creation: lenderId ($lenderId) and borrowerId ($borrowerId) are the same or lenderId is empty',
        );
      }
      return docRef.id;
    } catch (e) {
      throw Exception('Error creating borrow request: $e');
    }
  }

  Future<bool> hasPendingBorrowRequest({
    required String itemId,
    required String borrowerId,
  }) async {
    final snap = await _db
        .collection('borrow_requests')
        .where('itemId', isEqualTo: itemId)
        .where('borrowerId', isEqualTo: borrowerId)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  Future<Set<String>> getPendingRequestedItemIdsForBorrower(
    String borrowerId,
  ) async {
    final snap = await _db
        .collection('borrow_requests')
        .where('borrowerId', isEqualTo: borrowerId)
        .where('status', isEqualTo: 'pending')
        .get();
    return snap.docs
        .map((d) => (d.data()['itemId'] as String?) ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Future<String?> findPendingBorrowRequestId({
    required String itemId,
    required String borrowerId,
  }) async {
    final snap = await _db
        .collection('borrow_requests')
        .where('itemId', isEqualTo: itemId)
        .where('borrowerId', isEqualTo: borrowerId)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return snap.docs.first.id;
  }

  Future<List<Map<String, dynamic>>> getPendingBorrowRequestsForBorrower(
    String borrowerId,
  ) async {
    try {
      // Dropped orderBy to avoid requiring a composite index
      final snap = await _db
          .collection('borrow_requests')
          .where('borrowerId', isEqualTo: borrowerId)
          .where('status', isEqualTo: 'pending')
          .get();
      return snap.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      throw Exception('Error getting pending borrow requests: $e');
    }
  }

  /// Get the count of pending borrow requests for a borrower
  Future<int> getPendingBorrowRequestCount(String borrowerId) async {
    try {
      final snap = await _db
          .collection('borrow_requests')
          .where('borrowerId', isEqualTo: borrowerId)
          .where('status', isEqualTo: 'pending')
          .get();
      return snap.docs.length;
    } catch (e) {
      throw Exception('Error counting pending borrow requests: $e');
    }
  }

  /// Get the count of items currently borrowed by a borrower
  Future<int> getActiveBorrowCount(String borrowerId) async {
    try {
      final snap = await _db
          .collection('items')
          .where('status', isEqualTo: 'borrowed')
          .where('currentBorrowerId', isEqualTo: borrowerId)
          .get();
      return snap.docs.length;
    } catch (e) {
      throw Exception('Error counting active borrows: $e');
    }
  }

  Future<Map<String, dynamic>?> getBorrowRequestById(String requestId) async {
    try {
      final doc = await _db.collection('borrow_requests').doc(requestId).get();
      if (!doc.exists) return null;
      final data = doc.data();
      data?['id'] = doc.id;
      return data;
    } catch (e) {
      throw Exception('Error getting borrow request: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getPendingBorrowRequestsForLender(
    String lenderId,
  ) async {
    try {
      final snap = await _db
          .collection('borrow_requests')
          .where('lenderId', isEqualTo: lenderId)
          .where('status', isEqualTo: 'pending')
          .get();
      return snap.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      throw Exception('Error getting pending borrow requests for lender: $e');
    }
  }

  /// Get accepted borrow requests for a borrower
  Future<List<Map<String, dynamic>>> getAcceptedBorrowRequestsForBorrower(
    String borrowerId,
  ) async {
    try {
      final snap = await _db
          .collection('borrow_requests')
          .where('borrowerId', isEqualTo: borrowerId)
          .where('status', isEqualTo: 'accepted')
          .get();
      return snap.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      throw Exception('Error getting accepted borrow requests: $e');
    }
  }

  /// Get returned items for a borrower (items that were previously borrowed but are now returned)
  Future<List<Map<String, dynamic>>> getReturnedItemsByBorrower(
    String borrowerId,
  ) async {
    try {
      // Get all accepted borrow requests for this borrower
      final acceptedRequests = await _db
          .collection('borrow_requests')
          .where('borrowerId', isEqualTo: borrowerId)
          .where('status', isEqualTo: 'accepted')
          .get();

      final returnedItems = <Map<String, dynamic>>[];

      for (final requestDoc in acceptedRequests.docs) {
        final requestData = requestDoc.data();
        final itemId = requestData['itemId'] as String?;

        if (itemId == null) continue;

        // Get the item to check its current status
        final itemDoc = await _db.collection('items').doc(itemId).get();
        if (!itemDoc.exists) continue;

        final itemData = itemDoc.data() as Map<String, dynamic>;
        final currentStatus = itemData['status'] as String?;
        final currentBorrowerId = itemData['currentBorrowerId'] as String?;

        // Item is returned if:
        // 1. Status is not 'borrowed', OR
        // 2. Status is 'borrowed' but currentBorrowerId is not this borrower
        final isReturned =
            currentStatus != 'borrowed' ||
            (currentStatus == 'borrowed' && currentBorrowerId != borrowerId);

        if (isReturned) {
          // Combine request data with item data for complete information
          final returnedItem = Map<String, dynamic>.from(itemData);
          returnedItem['id'] = itemDoc.id;
          returnedItem['requestId'] = requestDoc.id;
          returnedItem['agreedReturnDate'] = requestData['agreedReturnDate'];
          returnedItem['requestCreatedAt'] = requestData['createdAt'];
          returnedItem['requestUpdatedAt'] = requestData['updatedAt'];
          returnedItems.add(returnedItem);
        }
      }

      return returnedItems;
    } catch (e) {
      throw Exception('Error getting returned items: $e');
    }
  }

  Future<void> acceptBorrowRequest({
    required String requestId,
    required String itemId,
    required String borrowerId,
    required DateTime returnDate,
  }) async {
    // Check if user has reached the maximum active borrows limit
    final activeCount = await getActiveBorrowCount(borrowerId);
    if (activeCount >= maxActiveBorrows) {
      throw Exception(
        'This borrower has reached the maximum limit of $maxActiveBorrows actively borrowed items. '
        'They must return at least one item before borrowing another.',
      );
    }

    final batch = _db.batch();
    final requestRef = _db.collection('borrow_requests').doc(requestId);
    final itemRef = _db.collection('items').doc(itemId);

    batch.update(requestRef, {
      'status': 'accepted',
      'agreedReturnDate': Timestamp.fromDate(returnDate),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    batch.update(itemRef, {
      'status': 'borrowed',
      'currentBorrowerId': borrowerId,
      'borrowedDate': FieldValue.serverTimestamp(),
      'returnDate': Timestamp.fromDate(returnDate),
      'lastUpdated': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  Future<void> declineBorrowRequest({required String requestId}) async {
    await _db.collection('borrow_requests').doc(requestId).update({
      'status': 'declined',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> cancelBorrowRequest({required String requestId}) async {
    await _db.collection('borrow_requests').doc(requestId).update({
      'status': 'cancelled',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markItemReturned({required String itemId}) async {
    await _db.collection('items').doc(itemId).update({
      'status': 'available',
      'currentBorrowerId': null,
      'returnDate': null,
      'lastUpdated': FieldValue.serverTimestamp(),
    });
  }

  /// Borrower initiates return - sets borrow request status to 'return_initiated'
  Future<bool> initiateBorrowReturn({
    required String requestId,
    required String borrowerId,
    String? condition, // 'same', 'better', 'worse', 'damaged'
    String? conditionNotes,
    List<String>? conditionPhotos, // URLs of uploaded photos
  }) async {
    try {
      final request = await getBorrowRequestById(requestId);
      if (request == null) {
        throw Exception('Borrow request not found');
      }

      final currentStatus = request['status'] as String?;
      if (currentStatus != 'accepted') {
        throw Exception(
          'Can only initiate return for accepted borrow requests',
        );
      }

      final requestBorrowerId = request['borrowerId'] as String?;
      if (requestBorrowerId != borrowerId) {
        throw Exception('Only the borrower can initiate return');
      }

      final updateData = <String, dynamic>{
        'status': 'return_initiated',
        'returnInitiatedBy': borrowerId,
        'returnInitiatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Add condition verification data if provided
      if (condition != null) {
        updateData['borrowerCondition'] = condition;
      }
      if (conditionNotes != null && conditionNotes.isNotEmpty) {
        updateData['borrowerConditionNotes'] = conditionNotes;
      }
      if (conditionPhotos != null && conditionPhotos.isNotEmpty) {
        updateData['borrowerConditionPhotos'] = conditionPhotos;
      }

      await _db.collection('borrow_requests').doc(requestId).update(updateData);

      // Send notification to lender
      final lenderId = request['lenderId'] as String?;
      final itemTitle = request['itemTitle'] as String? ?? 'Item';
      final borrowerName = request['borrowerName'] as String? ?? 'Borrower';

      if (lenderId != null && lenderId.isNotEmpty && lenderId != borrowerId) {
        try {
          await _db.collection('notifications').add({
            'toUserId': lenderId,
            'type': 'borrow_return_initiated',
            'itemId': request['itemId'],
            'itemTitle': itemTitle,
            'fromUserId': borrowerId,
            'fromUserName': borrowerName,
            'requestId': requestId,
            'status': 'unread',
            'createdAt': FieldValue.serverTimestamp(),
          });
        } catch (e) {
          debugPrint('Error creating return notification: $e');
        }
      }

      return true;
    } catch (e) {
      debugPrint('Error initiating borrow return: $e');
      rethrow;
    }
  }

  /// Lender confirms return - sets status to 'returned' and marks item as available
  /// If conditionAccepted is false, status becomes 'return_disputed' for damage reporting
  Future<bool> confirmBorrowReturn({
    required String requestId,
    required String lenderId,
    bool conditionAccepted = true,
    String? lenderConditionNotes,
    List<String>? lenderConditionPhotos,
    Map<String, dynamic>?
    damageReport, // {type, description, estimatedCost, photos}
  }) async {
    try {
      final request = await getBorrowRequestById(requestId);
      if (request == null) {
        throw Exception('Borrow request not found');
      }

      final currentStatus = request['status'] as String?;
      if (currentStatus != 'return_initiated') {
        throw Exception('Return must be initiated by borrower first');
      }

      final requestLenderId = request['lenderId'] as String?;
      if (requestLenderId != lenderId) {
        throw Exception('Only the lender can confirm return');
      }

      final itemId = request['itemId'] as String?;
      if (itemId == null) {
        throw Exception('Item ID not found in request');
      }

      final borrowerId = request['borrowerId'] as String?;
      final itemTitle = request['itemTitle'] as String? ?? 'Item';
      final lenderName = request['lenderName'] as String? ?? 'Lender';

      final batch = _db.batch();
      final requestRef = _db.collection('borrow_requests').doc(requestId);
      final itemRef = _db.collection('items').doc(itemId);

      final updateData = <String, dynamic>{
        'returnConfirmedBy': lenderId,
        'returnConfirmedAt': FieldValue.serverTimestamp(),
        'actualReturnDate': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (conditionAccepted) {
        // Condition accepted - mark as returned
        updateData['status'] = 'returned';
        updateData['lenderConditionDecision'] = 'accepted';

        // Mark item as available
        batch.update(itemRef, {
          'status': 'available',
          'currentBorrowerId': null,
          'returnDate': null,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      } else {
        // Condition disputed - requires damage reporting
        updateData['status'] = 'return_disputed';
        updateData['lenderConditionDecision'] = 'disputed';

        if (lenderConditionNotes != null && lenderConditionNotes.isNotEmpty) {
          updateData['lenderConditionNotes'] = lenderConditionNotes;
        }
        if (lenderConditionPhotos != null && lenderConditionPhotos.isNotEmpty) {
          updateData['lenderConditionPhotos'] = lenderConditionPhotos;
        }
        if (damageReport != null) {
          updateData['damageReport'] = damageReport;
        }
      }

      // Update borrow request
      batch.update(requestRef, updateData);
      await batch.commit();

      // Cancel return reminders
      try {
        final localNotificationsService = LocalNotificationsService();
        await localNotificationsService.cancelReturnReminders(itemId);
        await localNotificationsService.cancelOverdueReminders(itemId);
      } catch (e) {
        debugPrint('Error cancelling reminders: $e');
      }

      // Send notification to borrower
      if (borrowerId != null &&
          borrowerId.isNotEmpty &&
          borrowerId != lenderId) {
        try {
          final notificationType = conditionAccepted
              ? 'borrow_return_confirmed'
              : 'borrow_return_disputed';

          await _db.collection('notifications').add({
            'toUserId': borrowerId,
            'type': notificationType,
            'itemId': itemId,
            'itemTitle': itemTitle,
            'fromUserId': lenderId,
            'fromUserName': lenderName,
            'requestId': requestId,
            'status': 'unread',
            'createdAt': FieldValue.serverTimestamp(),
          });
        } catch (e) {
          debugPrint('Error creating return confirmation notification: $e');
        }
      }

      return true;
    } catch (e) {
      debugPrint('Error confirming borrow return: $e');
      rethrow;
    }
  }

  /// Get disputed returns for a borrower (returns that were disputed by lender)
  Future<List<Map<String, dynamic>>> getDisputedReturnsForBorrower(
    String borrowerId,
  ) async {
    try {
      final snap = await _db
          .collection('borrow_requests')
          .where('borrowerId', isEqualTo: borrowerId)
          .where('status', isEqualTo: 'return_disputed')
          .get();

      final disputedReturns = <Map<String, dynamic>>[];

      for (final doc in snap.docs) {
        final requestData = doc.data();
        final itemId = requestData['itemId'] as String?;

        if (itemId == null) continue;

        // Get item details
        try {
          final itemDoc = await _db.collection('items').doc(itemId).get();
          if (itemDoc.exists) {
            final itemData = itemDoc.data() as Map<String, dynamic>;
            final combined = Map<String, dynamic>.from(requestData);
            combined['id'] = doc.id;
            combined.addAll(itemData);
            combined['itemId'] = itemId;
            disputedReturns.add(combined);
          } else {
            // If item doesn't exist, still include request data
            final combined = Map<String, dynamic>.from(requestData);
            combined['id'] = doc.id;
            disputedReturns.add(combined);
          }
        } catch (e) {
          debugPrint('Error fetching item for disputed return: $e');
          // Still add request data even if item fetch fails
          final combined = Map<String, dynamic>.from(requestData);
          combined['id'] = doc.id;
          disputedReturns.add(combined);
        }
      }

      return disputedReturns;
    } catch (e) {
      throw Exception('Error getting disputed returns for borrower: $e');
    }
  }

  /// Get pending returns for a lender (items waiting for return confirmation)
  Future<List<Map<String, dynamic>>> getPendingReturnsForLender(
    String lenderId,
  ) async {
    try {
      final snap = await _db
          .collection('borrow_requests')
          .where('lenderId', isEqualTo: lenderId)
          .where('status', isEqualTo: 'return_initiated')
          .get();

      final pendingReturns = <Map<String, dynamic>>[];

      for (final doc in snap.docs) {
        final requestData = doc.data();
        final itemId = requestData['itemId'] as String?;

        if (itemId == null) continue;

        // Get item details
        try {
          final itemDoc = await _db.collection('items').doc(itemId).get();
          if (itemDoc.exists) {
            final itemData = itemDoc.data() as Map<String, dynamic>;
            final combined = Map<String, dynamic>.from(requestData);
            combined['id'] = doc.id;
            combined.addAll(itemData);
            combined['itemId'] = itemId;
            pendingReturns.add(combined);
          } else {
            // If item doesn't exist, still include request data
            final combined = Map<String, dynamic>.from(requestData);
            combined['id'] = doc.id;
            pendingReturns.add(combined);
          }
        } catch (e) {
          debugPrint('Error fetching item for pending return: $e');
          // Still add request data even if item fetch fails
          final combined = Map<String, dynamic>.from(requestData);
          combined['id'] = doc.id;
          pendingReturns.add(combined);
        }
      }

      return pendingReturns;
    } catch (e) {
      throw Exception('Error getting pending returns for lender: $e');
    }
  }

  /// Check for overdue items and create notifications
  /// This should be called periodically (e.g., daily or when app opens)
  Future<void> checkAndNotifyOverdueItems() async {
    try {
      final now = DateTime.now();
      final snapshot = await _db
          .collection('items')
          .where('status', isEqualTo: 'borrowed')
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final returnDate = data['returnDate'] as Timestamp?;
        if (returnDate == null) continue;

        final dueDate = returnDate.toDate();
        if (dueDate.isBefore(now)) {
          // Item is overdue
          final itemId = doc.id;
          final itemTitle = data['title'] as String? ?? 'Item';
          final borrowerId = data['currentBorrowerId'] as String?;
          final lenderId = data['lenderId'] as String?;
          final lenderName = data['lenderName'] as String? ?? 'Lender';

          if (borrowerId == null || lenderId == null) continue;

          // Calculate days overdue
          final daysOverdue = now.difference(dueDate).inDays;

          // Get borrower name
          String borrowerName = 'Borrower';
          try {
            final borrowerData = await getUser(borrowerId);
            if (borrowerData != null) {
              final firstName = borrowerData['firstName'] ?? '';
              final lastName = borrowerData['lastName'] ?? '';
              borrowerName = '$firstName $lastName'.trim();
              if (borrowerName.isEmpty) borrowerName = 'Borrower';
            }
          } catch (_) {}

          // Get lender name
          String actualLenderName = lenderName;
          try {
            final lenderData = await getUser(lenderId);
            if (lenderData != null) {
              final firstName = lenderData['firstName'] ?? '';
              final lastName = lenderData['lastName'] ?? '';
              actualLenderName = '$firstName $lastName'.trim();
              if (actualLenderName.isEmpty) actualLenderName = lenderName;
            }
          } catch (_) {}

          // Check if we already sent a notification today for this item
          final today = DateTime(now.year, now.month, now.day);
          final todayStart = Timestamp.fromDate(today);
          final todayEnd = Timestamp.fromDate(
            today.add(const Duration(days: 1)),
          );

          final existingNotification = await _db
              .collection('notifications')
              .where('toUserId', isEqualTo: borrowerId)
              .where('type', isEqualTo: 'item_overdue')
              .where('itemId', isEqualTo: itemId)
              .where('createdAt', isGreaterThanOrEqualTo: todayStart)
              .where('createdAt', isLessThan: todayEnd)
              .limit(1)
              .get();

          // Only send one notification per day per item
          if (existingNotification.docs.isEmpty) {
            // Notify borrower
            await _db.collection('notifications').add({
              'toUserId': borrowerId,
              'type': 'item_overdue',
              'itemId': itemId,
              'itemTitle': itemTitle,
              'lenderId': lenderId,
              'lenderName': actualLenderName,
              'daysOverdue': daysOverdue,
              'status': 'unread',
              'createdAt': FieldValue.serverTimestamp(),
            });
          }

          // Check if we already sent a notification to lender today
          final existingLenderNotification = await _db
              .collection('notifications')
              .where('toUserId', isEqualTo: lenderId)
              .where('type', isEqualTo: 'item_overdue_lender')
              .where('itemId', isEqualTo: itemId)
              .where('createdAt', isGreaterThanOrEqualTo: todayStart)
              .where('createdAt', isLessThan: todayEnd)
              .limit(1)
              .get();

          if (existingLenderNotification.docs.isEmpty) {
            // Notify lender
            await _db.collection('notifications').add({
              'toUserId': lenderId,
              'type': 'item_overdue_lender',
              'itemId': itemId,
              'itemTitle': itemTitle,
              'borrowerId': borrowerId,
              'borrowerName': borrowerName,
              'daysOverdue': daysOverdue,
              'status': 'unread',
              'createdAt': FieldValue.serverTimestamp(),
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking overdue items: $e');
      // Don't throw - this is a background task
    }
  }

  Future<void> markNotificationRead(String notificationId) async {
    await _db.collection('notifications').doc(notificationId).update({
      'status': 'read',
    });
  }

  Future<void> sendDecisionNotification({
    required String toUserId,
    required String itemTitle,
    required String decision, // 'accepted' | 'declined'
    required String requestId,
    String? lenderName,
  }) async {
    await _db.collection('notifications').add({
      'toUserId': toUserId,
      'type': 'borrow_request_decision',
      'itemTitle': itemTitle,
      'requestId': requestId,
      'decision': decision,
      'lenderName': lenderName,
      'status': 'unread',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setUser(String uid, Map<String, dynamic> data) async {
    final payload = Map<String, dynamic>.from(data);
    if (payload['createdAt'] is DateTime) {
      payload['createdAt'] = Timestamp.fromDate(payload['createdAt']);
    }
    await _db
        .collection('users')
        .doc(uid)
        .set(payload, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>?> getUser(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }
      return null;
    } catch (e) {
      throw Exception('Error getting user: $e');
    }
  }

  // Check if a user with the given email already exists
  Future<bool> userExistsByEmail(String email) async {
    try {
      final normalizedEmail = email.trim().toLowerCase();
      final snapshot = await _db
          .collection('users')
          .where('email', isEqualTo: normalizedEmail)
          .limit(1)
          .get();
      return snapshot.docs.isNotEmpty;
    } catch (e) {
      throw Exception('Error checking if user exists by email: $e');
    }
  }

  // Get user by email (if exists)
  Future<Map<String, dynamic>?> getUserByEmail(String email) async {
    try {
      final normalizedEmail = email.trim().toLowerCase();
      final snapshot = await _db
          .collection('users')
          .where('email', isEqualTo: normalizedEmail)
          .limit(1)
          .get();
      if (snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.first.data();
        data['id'] = snapshot.docs.first.id;
        return data;
      }
      return null;
    } catch (e) {
      throw Exception('Error getting user by email: $e');
    }
  }

  // Check if a user with the same name and address already exists
  // This helps prevent the same person from creating multiple accounts
  Future<bool> userExistsByNameAndAddress({
    required String firstName,
    required String lastName,
    required String street,
    required String barangay,
    required String city,
  }) async {
    try {
      final normalizedFirstName = firstName.trim().toLowerCase();
      final normalizedLastName = lastName.trim().toLowerCase();
      final normalizedStreet = _normalizeAddress(street);
      final normalizedBarangay = barangay.trim().toLowerCase();
      final normalizedCity = city.trim().toLowerCase();

      debugPrint('🔍 Checking for duplicate user:');
      debugPrint('   Normalized First Name: $normalizedFirstName');
      debugPrint('   Normalized Last Name: $normalizedLastName');
      debugPrint('   Normalized Street: $normalizedStreet');
      debugPrint('   Normalized Barangay: $normalizedBarangay');
      debugPrint('   Normalized City: $normalizedCity');

      // Try the composite query first
      try {
        final snapshot = await _db
            .collection('users')
            .where('firstName', isEqualTo: normalizedFirstName)
            .where('lastName', isEqualTo: normalizedLastName)
            .where('street', isEqualTo: normalizedStreet)
            .where('barangay', isEqualTo: normalizedBarangay)
            .where('city', isEqualTo: normalizedCity)
            .limit(1)
            .get();

        final found = snapshot.docs.isNotEmpty;
        debugPrint(
          '🔍 Duplicate check result: $found (found ${snapshot.docs.length} matching user(s))',
        );

        if (found) {
          return true;
        }
      } catch (e) {
        debugPrint('⚠️ Composite query failed, trying fallback query: $e');
        // Fall through to fallback query
      }

      // Fallback: Query by last name and location, then filter in memory
      // This doesn't require a composite index
      debugPrint('🔍 Using fallback query (no composite index needed)...');
      final fallbackSnapshot = await _db
          .collection('users')
          .where('lastName', isEqualTo: normalizedLastName)
          .where('barangay', isEqualTo: normalizedBarangay)
          .where('city', isEqualTo: normalizedCity)
          .get();

      debugPrint(
        '🔍 Fallback query found ${fallbackSnapshot.docs.length} users with same last name and location',
      );

      // Filter in memory for exact match
      // Handle both normalized and non-normalized existing data
      for (final doc in fallbackSnapshot.docs) {
        final data = doc.data();
        // Normalize existing data (in case it wasn't normalized when stored)
        final existingFirstName = (data['firstName'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final existingStreet = _normalizeAddress(data['street'] ?? '');

        debugPrint('   Comparing with existing user:');
        debugPrint(
          '     Existing First Name: ${data['firstName']} -> $existingFirstName',
        );
        debugPrint(
          '     Existing Street: ${data['street']} -> $existingStreet',
        );
        debugPrint(
          '     Looking for: $normalizedFirstName / $normalizedStreet',
        );

        if (existingFirstName == normalizedFirstName &&
            existingStreet == normalizedStreet) {
          debugPrint('✅ Duplicate found via fallback query!');
          debugPrint('   Matching user ID: ${doc.id}');
          return true;
        }
      }

      debugPrint('✅ No duplicate found');
      return false;
    } catch (e) {
      // If all queries fail, log error but don't block registration
      // The email check will still prevent duplicates
      debugPrint('❌ Error checking user by name and address: $e');
      debugPrint(
        '⚠️ Note: You may need to create a composite index in Firestore Console',
      );
      debugPrint(
        '   The query requires an index on: firstName, lastName, street, barangay, city',
      );
      return false;
    }
  }

  // Find potential duplicate accounts by similar name and address
  // Returns list of potential duplicates for admin review
  Future<List<Map<String, dynamic>>> findPotentialDuplicates({
    required String firstName,
    required String lastName,
    required String street,
    required String barangay,
    required String city,
  }) async {
    try {
      final normalizedFirstName = firstName.trim().toLowerCase();
      final normalizedLastName = lastName.trim().toLowerCase();
      final normalizedBarangay = barangay.trim().toLowerCase();
      final normalizedCity = city.trim().toLowerCase();

      // Find users with same last name and location (more lenient check)
      // This helps catch cases where someone uses someone else's identity
      final snapshot = await _db
          .collection('users')
          .where('lastName', isEqualTo: normalizedLastName)
          .where('barangay', isEqualTo: normalizedBarangay)
          .where('city', isEqualTo: normalizedCity)
          .get();

      final potentialDuplicates = <Map<String, dynamic>>[];

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final existingFirstName = (data['firstName'] ?? '')
            .toString()
            .toLowerCase();
        final existingStreet = _normalizeAddress(data['street'] ?? '');

        // Check if first name is similar (exact match or similar)
        final firstNameMatch =
            existingFirstName == normalizedFirstName ||
            _isSimilarName(existingFirstName, normalizedFirstName);

        // Check if street is similar
        final streetMatch = _isSimilarAddress(
          existingStreet,
          _normalizeAddress(street),
        );

        if (firstNameMatch && streetMatch) {
          final duplicateData = Map<String, dynamic>.from(data);
          duplicateData['id'] = doc.id;
          duplicateData['matchReason'] = 'Same name and address';
          potentialDuplicates.add(duplicateData);
        }
      }

      return potentialDuplicates;
    } catch (e) {
      debugPrint('Error finding potential duplicates: $e');
      return [];
    }
  }

  // Normalize address to handle variations (St, Street, Ave, Avenue, etc.)
  String _normalizeAddress(String address) {
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

  // Check if two names are similar (handles typos and variations)
  bool _isSimilarName(String name1, String name2) {
    if (name1 == name2) return true;
    // Check if one name contains the other (handles nicknames)
    if (name1.contains(name2) || name2.contains(name1)) {
      // Only consider similar if the shorter name is at least 3 characters
      final shorter = name1.length < name2.length ? name1 : name2;
      if (shorter.length >= 3) return true;
    }
    // Check Levenshtein distance for typos (simple version)
    final distance = _levenshteinDistance(name1, name2);
    final maxLength = name1.length > name2.length ? name1.length : name2.length;
    // Consider similar if distance is small relative to length
    return maxLength > 0 && (distance / maxLength) < 0.3;
  }

  // Check if two addresses are similar
  bool _isSimilarAddress(String addr1, String addr2) {
    if (addr1 == addr2) return true;
    // Check if addresses share significant words
    final words1 = addr1.split(' ').where((w) => w.length > 2).toSet();
    final words2 = addr2.split(' ').where((w) => w.length > 2).toSet();
    final commonWords = words1.intersection(words2);
    // Consider similar if they share at least 2 significant words
    return commonWords.length >= 2;
  }

  // Simple Levenshtein distance calculation
  int _levenshteinDistance(String s1, String s2) {
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    final matrix = List.generate(
      s1.length + 1,
      (i) => List.generate(s2.length + 1, (j) => 0),
    );

    for (int i = 0; i <= s1.length; i++) {
      matrix[i][0] = i;
    }
    for (int j = 0; j <= s2.length; j++) {
      matrix[0][j] = j;
    }

    for (int i = 1; i <= s1.length; i++) {
      for (int j = 1; j <= s2.length; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        matrix[i][j] = [
          matrix[i - 1][j] + 1, // deletion
          matrix[i][j - 1] + 1, // insertion
          matrix[i - 1][j - 1] + cost, // substitution
        ].reduce((a, b) => a < b ? a : b);
      }
    }

    return matrix[s1.length][s2.length];
  }

  Future<List<Map<String, dynamic>>> getAllUsers() async {
    final snapshot = await _db.collection('users').get();
    return snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return data;
    }).toList();
  }

  // Item operations
  Future<String> createItem(Map<String, dynamic> data) async {
    final payload = Map<String, dynamic>.from(data);
    // Convert DateTime fields to Timestamps
    if (payload['createdAt'] is DateTime) {
      payload['createdAt'] = Timestamp.fromDate(payload['createdAt']);
    }
    if (payload['lastUpdated'] is DateTime) {
      payload['lastUpdated'] = Timestamp.fromDate(payload['lastUpdated']);
    }
    if (payload['borrowedDate'] is DateTime) {
      payload['borrowedDate'] = Timestamp.fromDate(payload['borrowedDate']);
    }
    if (payload['returnDate'] is DateTime) {
      payload['returnDate'] = Timestamp.fromDate(payload['returnDate']);
    }
    final docRef = await _db.collection('items').add(payload);
    return docRef.id;
  }

  Future<void> updateItem(String itemId, Map<String, dynamic> data) async {
    final payload = Map<String, dynamic>.from(data);
    // Convert DateTime fields to Timestamps
    if (payload['lastUpdated'] is DateTime) {
      payload['lastUpdated'] = Timestamp.fromDate(payload['lastUpdated']);
    }
    if (payload['borrowedDate'] is DateTime) {
      payload['borrowedDate'] = Timestamp.fromDate(payload['borrowedDate']);
    }
    if (payload['returnDate'] is DateTime) {
      payload['returnDate'] = Timestamp.fromDate(payload['returnDate']);
    }
    await _db.collection('items').doc(itemId).update(payload);
  }

  Future<Map<String, dynamic>?> getItem(String itemId) async {
    try {
      final doc = await _db.collection('items').doc(itemId).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }
      return null;
    } catch (e) {
      throw Exception('Error getting item: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getAllItems() async {
    try {
      final snapshot = await _db.collection('items').get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      throw Exception('Error getting items: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getItemsByLender(String lenderId) async {
    try {
      final snapshot = await _db
          .collection('items')
          .where('lenderId', isEqualTo: lenderId)
          .get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      throw Exception('Error getting items by lender: $e');
    }
  }

  // Stream items by lender for real-time updates and faster initial paint
  Stream<QuerySnapshot<Map<String, dynamic>>> getItemsByLenderStream(
    String lenderId,
  ) {
    // Note: Dropped orderBy('createdAt') to avoid composite index requirement
    // You can add the index in Firebase, then reintroduce orderBy for sorting
    return _db
        .collection('items')
        .where('lenderId', isEqualTo: lenderId)
        .limit(50)
        .snapshots();
  }

  Future<List<Map<String, dynamic>>> getAvailableItems() async {
    try {
      final snapshot = await _db
          .collection('items')
          .where('status', isEqualTo: 'available')
          .get();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      throw Exception('Error getting available items: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getBorrowedItemsByBorrower(
    String borrowerId,
  ) async {
    try {
      // Get items that are borrowed or have return initiated
      final snapshot = await _db
          .collection('items')
          .where('currentBorrowerId', isEqualTo: borrowerId)
          .get();

      final borrowedItems = <Map<String, dynamic>>[];

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final itemId = doc.id;
        final status = data['status'] as String?;

        // Only include items that are borrowed or have return initiated
        if (status == 'borrowed' || status == 'return_initiated') {
          // Get the borrow request to include return status
          try {
            final requestSnapshot = await _db
                .collection('borrow_requests')
                .where('itemId', isEqualTo: itemId)
                .where('borrowerId', isEqualTo: borrowerId)
                .where(
                  'status',
                  whereIn: ['accepted', 'return_initiated', 'returned'],
                )
                .limit(1)
                .get();

            if (requestSnapshot.docs.isNotEmpty) {
              final requestData = requestSnapshot.docs.first.data();
              final requestId = requestSnapshot.docs.first.id;
              final requestStatus = requestData['status'] as String?;

              final itemData = Map<String, dynamic>.from(data);
              itemData['id'] = itemId;
              itemData['requestId'] = requestId;
              itemData['returnStatus'] =
                  requestStatus; // 'accepted', 'return_initiated', or 'returned'
              itemData['returnInitiatedAt'] = requestData['returnInitiatedAt'];
              itemData['returnInitiatedBy'] = requestData['returnInitiatedBy'];
              borrowedItems.add(itemData);
            } else {
              // Fallback: include item even if request not found
              final itemData = Map<String, dynamic>.from(data);
              itemData['id'] = itemId;
              itemData['returnStatus'] = 'accepted'; // Default
              borrowedItems.add(itemData);
            }
          } catch (e) {
            debugPrint('Error fetching borrow request for item $itemId: $e');
            // Fallback: include item even if request fetch fails
            final itemData = Map<String, dynamic>.from(data);
            itemData['id'] = itemId;
            itemData['returnStatus'] = 'accepted'; // Default
            borrowedItems.add(itemData);
          }
        }
      }

      return borrowedItems;
    } catch (e) {
      throw Exception('Error getting borrowed items: $e');
    }
  }

  Future<void> deleteItem(String itemId) async {
    try {
      await _db.collection('items').doc(itemId).delete();
    } catch (e) {
      throw Exception('Error deleting item: $e');
    }
  }

  Stream<QuerySnapshot> getItemsStream() {
    return _db.collection('items').snapshots();
  }

  // Update user's last seen timestamp
  Future<void> updateUserLastSeen(String uid) async {
    try {
      await _db.collection('users').doc(uid).update({
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Error updating last seen: $e');
    }
  }

  // Get user's last seen timestamp
  Future<DateTime?> getUserLastSeen(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      if (doc.exists) {
        final data = doc.data();
        final lastSeen = data?['lastSeen'] as Timestamp?;
        return lastSeen?.toDate();
      }
      return null;
    } catch (e) {
      throw Exception('Error getting last seen: $e');
    }
  }

  // Stream to watch user's last seen status
  Stream<DateTime?> getUserLastSeenStream(String uid) {
    return _db.collection('users').doc(uid).snapshots().map((snapshot) {
      if (snapshot.exists) {
        final data = snapshot.data();
        final lastSeen = data?['lastSeen'] as Timestamp?;
        return lastSeen?.toDate();
      }
      return null;
    });
  }
}

// ---------------- RENTALS (LISTINGS / REQUESTS / PAYMENTS / AUDITS) ----------------
extension FirestoreServiceRentals on FirestoreService {
  // Rental Listing
  Future<String> createRentalListing(Map<String, dynamic> data) async {
    final payload = Map<String, dynamic>.from(data);
    if (payload['createdAt'] is DateTime) {
      payload['createdAt'] = Timestamp.fromDate(payload['createdAt']);
    }
    if (payload['updatedAt'] is DateTime) {
      payload['updatedAt'] = Timestamp.fromDate(payload['updatedAt']);
    }
    final doc = await _db.collection('rental_listings').add(payload);
    return doc.id;
  }

  Future<void> updateRentalListing(String id, Map<String, dynamic> data) async {
    final payload = Map<String, dynamic>.from(data);
    if (payload['updatedAt'] is DateTime) {
      payload['updatedAt'] = Timestamp.fromDate(payload['updatedAt']);
    }
    await _db.collection('rental_listings').doc(id).update(payload);
  }

  Future<Map<String, dynamic>?> getRentalListing(String id) async {
    final doc = await _db.collection('rental_listings').doc(id).get();
    if (!doc.exists) return null;
    final data = doc.data() as Map<String, dynamic>;
    data['id'] = doc.id;
    return data;
  }

  Future<List<Map<String, dynamic>>> getRentalListingsByOwner(
    String ownerId,
  ) async {
    final snap = await _db
        .collection('rental_listings')
        .where('ownerId', isEqualTo: ownerId)
        .get();
    return snap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      return data;
    }).toList();
  }

  /// Fetch rental listings filtered by rentType
  /// If rentType is null, returns all active listings
  /// rentType should be: 'item', 'apartment', 'boarding_house', or 'commercial'
  Future<List<Map<String, dynamic>>> fetchRentListingsByType(
    String? rentType, {
    int limit = 50,
    bool activeOnly = true,
  }) async {
    Query<Map<String, dynamic>> query = _db
        .collection('rental_listings')
        .limit(limit);

    if (activeOnly) {
      query = query.where('isActive', isEqualTo: true);
    }

    if (rentType != null && rentType.isNotEmpty) {
      // Handle both 'boardinghouse' and 'boarding_house' for backward compatibility
      final normalizedType = rentType.toLowerCase();
      if (normalizedType == 'boardinghouse' ||
          normalizedType == 'boarding_house') {
        // Query for both possible values
        query = query.where(
          'rentType',
          whereIn: ['boarding_house', 'boardinghouse'],
        );
      } else {
        query = query.where('rentType', isEqualTo: normalizedType);
      }
    }

    final snap = await query.get();
    return snap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      return data;
    }).toList();
  }

  Future<void> deleteRentalListing(String listingId) async {
    try {
      // Get listing data first to extract image URLs
      final listing = await getRentalListing(listingId);
      if (listing != null) {
        // Collect all image URLs
        final List<String> imageUrls = [];

        // Add single imageUrl if exists
        final imageUrl = listing['imageUrl'] as String?;
        if (imageUrl != null && imageUrl.isNotEmpty) {
          imageUrls.add(imageUrl);
        }

        // Add all images from images array if exists
        final images = listing['images'] as List<dynamic>?;
        if (images != null) {
          for (final img in images) {
            if (img is String && img.isNotEmpty && !imageUrls.contains(img)) {
              imageUrls.add(img);
            }
          }
        }

        // Delete images from Firebase Storage (best effort)
        if (imageUrls.isNotEmpty) {
          try {
            final storageService = StorageService();
            await storageService.deleteImages(imageUrls);
          } catch (e) {
            // Log but don't fail the deletion - continue with Firestore deletion
            debugPrint(
              'Warning: Failed to delete some images from storage: $e',
            );
          }
        }
      }

      // Delete the Firestore document
      await _db.collection('rental_listings').doc(listingId).delete();
    } catch (e) {
      throw Exception('Error deleting rental listing: $e');
    }
  }

  // Check if listing has active rental requests
  Future<bool> hasActiveRentalRequests(String listingId) async {
    try {
      final snap = await _db
          .collection('rental_requests')
          .where('listingId', isEqualTo: listingId)
          .where(
            'status',
            whereIn: [
              'requested',
              'ownerapproved',
              'renterpaid',
              'active',
              'returninitiated',
            ],
          )
          .limit(1)
          .get();
      return snap.docs.isNotEmpty;
    } catch (e) {
      throw Exception('Error checking active rental requests: $e');
    }
  }

  // Get active rental request ID for a listing (for owner's view)
  Future<String?> getActiveRentalRequestId(String listingId) async {
    try {
      final snap = await _db
          .collection('rental_requests')
          .where('listingId', isEqualTo: listingId)
          .where(
            'status',
            whereIn: [
              'requested',
              'ownerapproved',
              'renterpaid',
              'active',
              'returninitiated',
            ],
          )
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      return snap.docs.first.id;
    } catch (e) {
      return null;
    }
  }

  // Get most recent rental request ID for a listing (including completed ones)
  // Useful for navigating to rental history even if no active rental
  Future<String?> getMostRecentRentalRequestId(String listingId) async {
    try {
      final snap = await _db
          .collection('rental_requests')
          .where('listingId', isEqualTo: listingId)
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      return snap.docs.first.id;
    } catch (e) {
      return null;
    }
  }

  // Rental Request
  Future<String> createRentalRequest(Map<String, dynamic> data) async {
    final payload = Map<String, dynamic>.from(data);

    // Prevent duplicate requests: Check if renter already has a pending/active request for this listing
    final listingId = payload['listingId'] as String?;
    final renterId = payload['renterId'] as String?;
    final startDate = payload['startDate'] as DateTime?;

    if (listingId != null && renterId != null) {
      // Check for existing requests with status: requested, ownerApproved, or active
      final existing = await _db
          .collection('rental_requests')
          .where('listingId', isEqualTo: listingId)
          .where('renterId', isEqualTo: renterId)
          .where('status', whereIn: ['requested', 'ownerapproved', 'active'])
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        final existingStatus =
            existing.docs.first.data()['status'] as String? ?? 'requested';
        throw Exception(
          'You already have a ${existingStatus.replaceAll('_', ' ')} rental request for this item. '
          'Please wait for the owner to respond or cancel your existing request first.',
        );
      }
    }

    // Check for date conflicts with other renters (if listing doesn't allow multiple rentals)
    if (listingId != null && startDate != null) {
      final listing = await getRentalListing(listingId);
      if (listing == null) {
        throw Exception('Listing not found');
      }
      final allowMultiple = listing['allowMultipleRentals'] as bool? ?? false;
      final quantity = listing['quantity'] as int?;
      final rentType = (listing['rentType'] ?? 'item').toString().toLowerCase();
      final isBoardingHouse =
          rentType == 'boardinghouse' || rentType == 'boarding_house';
      final isLongTerm = payload['isLongTerm'] as bool? ?? false;
      final requestEndDate = payload['endDate'] as DateTime?;

      if (!allowMultiple) {
        // Check for overlapping dates with active/approved requests
        // Skip conflict checking if this is a month-to-month rental (no end date)
        if (requestEndDate != null || !isLongTerm) {
          final conflictingRequests = await _db
              .collection('rental_requests')
              .where('listingId', isEqualTo: listingId)
              .where(
                'status',
                whereIn: ['requested', 'ownerapproved', 'active'],
              )
              .get();

          for (final doc in conflictingRequests.docs) {
            final reqData = doc.data();
            final reqStart = (reqData['startDate'] as Timestamp?)?.toDate();
            final reqEnd = (reqData['endDate'] as Timestamp?)?.toDate();
            final reqIsLongTerm = reqData['isLongTerm'] as bool? ?? false;

            // Skip if existing request is month-to-month (no end date)
            if (reqIsLongTerm && reqEnd == null) {
              // Month-to-month rental - check if start dates conflict
              if (reqStart != null &&
                  requestEndDate != null &&
                  reqStart.isBefore(requestEndDate)) {
                throw Exception(
                  'This item has an ongoing month-to-month rental. '
                  'Please contact the owner or choose a later start date.',
                );
              }
              continue;
            }

            if (reqStart != null && reqEnd != null && requestEndDate != null) {
              // Check if dates overlap
              if (_datesOverlap(startDate, requestEndDate, reqStart, reqEnd)) {
                throw Exception(
                  'This item is already booked for the selected dates. '
                  'Please choose different dates or contact the owner.',
                );
              }
            }
          }
        }
      } else if (isBoardingHouse) {
        // For boarding houses, check capacity based on available rooms and max occupants
        await _checkBoardingHouseCapacity(
          listingId: listingId,
          listing: listing,
          startDate: startDate,
          endDate: requestEndDate,
          requestedOccupants: payload['numberOfOccupants'] as int? ?? 1,
        );
      } else if (quantity != null && quantity > 1) {
        // For quantity-based rentals (e.g., clothes), check if enough units available
        final activeRequests = await _db
            .collection('rental_requests')
            .where('listingId', isEqualTo: listingId)
            .where('status', whereIn: ['requested', 'ownerapproved', 'active'])
            .get();

        int bookedCount = 0;
        for (final doc in activeRequests.docs) {
          final reqData = doc.data();
          final reqStart = (reqData['startDate'] as Timestamp?)?.toDate();
          final reqEnd = (reqData['endDate'] as Timestamp?)?.toDate();

          if (reqStart != null && reqEnd != null && requestEndDate != null) {
            // Count overlapping requests
            if (_datesOverlap(startDate, requestEndDate, reqStart, reqEnd)) {
              bookedCount++;
            }
          }
        }

        if (bookedCount >= quantity) {
          throw Exception(
            'All ${quantity} units are already booked for the selected dates. '
            'Please choose different dates.',
          );
        }
      }
    }

    // Convert dates
    for (final k in [
      'startDate',
      'endDate',
      'returnDueDate',
      'createdAt',
      'updatedAt',
      'actualReturnDate',
    ]) {
      if (payload[k] is DateTime) payload[k] = Timestamp.fromDate(payload[k]);
    }
    final doc = await _db.collection('rental_requests').add(payload);

    // Create a lightweight notification for the owner
    try {
      // Fetch listing to get item title
      String? itemTitle;
      final listingId = payload['listingId'] as String?;
      if (listingId != null) {
        final listing = await getRentalListing(listingId);
        itemTitle = listing?['title'] as String?;
        // Fallback to item title if listing title not available
        if (itemTitle == null || itemTitle.isEmpty) {
          final itemId = payload['itemId'] as String?;
          if (itemId != null) {
            final item = await getItem(itemId);
            itemTitle = item?['title'] as String? ?? 'Rental Item';
          }
        }
      }
      itemTitle ??= 'Rental Item';

      // Fetch renter name
      String? renterName;
      final renterId = payload['renterId'] as String?;
      if (renterId != null) {
        final renter = await getUser(renterId);
        if (renter != null) {
          final firstName = renter['firstName'] ?? '';
          final lastName = renter['lastName'] ?? '';
          renterName = '$firstName $lastName'.trim();
        }
      }
      renterName ??= 'A user';

      await _db.collection('notifications').add({
        'toUserId': payload['ownerId'],
        'type': 'rent_request',
        'itemId': payload['itemId'],
        'itemTitle': itemTitle,
        'fromUserId': renterId,
        'fromUserName': renterName,
        'requestId': doc.id,
        'status': 'unread',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Best-effort; don't fail the request if notification write fails
    }

    return doc.id;
  }

  Future<void> updateRentalRequest(String id, Map<String, dynamic> data) async {
    final payload = Map<String, dynamic>.from(data);

    // Get current request to check status change
    final currentRequest = await getRentalRequest(id);
    final oldStatus = currentRequest?['status'] as String?;
    final newStatus = payload['status'] as String?;

    for (final k in [
      'startDate',
      'endDate',
      'returnDueDate',
      'updatedAt',
      'actualReturnDate',
    ]) {
      if (payload[k] is DateTime) payload[k] = Timestamp.fromDate(payload[k]);
    }

    // Check if payment status changed to captured
    final oldPaymentStatus = currentRequest?['paymentStatus'] as String?;
    final newPaymentStatus = payload['paymentStatus'] as String?;

    await _db.collection('rental_requests').doc(id).update(payload);

    // Send notification when payment is marked as received
    if (oldPaymentStatus != 'captured' && newPaymentStatus == 'captured') {
      try {
        final renterId = currentRequest?['renterId'] as String?;
        final itemTitle =
            currentRequest?['itemTitle'] as String? ??
            (await getRentalListing(
                  currentRequest?['listingId'] as String? ?? '',
                ))?['title']
                as String? ??
            'Rental Item';

        if (renterId != null) {
          await _db.collection('notifications').add({
            'toUserId': renterId,
            'type': 'rent_payment_received',
            'itemTitle': itemTitle,
            'requestId': id,
            'message': 'Owner has confirmed receipt of your payment',
            'status': 'unread',
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      } catch (_) {
        // Best-effort; don't fail the update if notification write fails
      }
    }

    // Send notification if status changed to accepted or declined
    if (oldStatus != newStatus && newStatus != null && currentRequest != null) {
      try {
        final renterId = currentRequest['renterId'] as String?;
        final ownerId = currentRequest['ownerId'] as String?;
        final itemTitle =
            currentRequest['itemTitle'] as String? ??
            (await getRentalListing(
                  currentRequest['listingId'] as String? ?? '',
                ))?['title']
                as String? ??
            'Rental Item';

        String? ownerName;
        if (ownerId != null) {
          final owner = await getUser(ownerId);
          if (owner != null) {
            final firstName = owner['firstName'] ?? '';
            final lastName = owner['lastName'] ?? '';
            ownerName = '$firstName $lastName'.trim();
          }
        }
        ownerName ??= 'The owner';

        if (newStatus.toLowerCase() == 'ownerapproved' ||
            newStatus.toLowerCase() == 'active') {
          // Deactivate listing if it doesn't allow multiple rentals or isn't quantity-based
          try {
            final listingId = currentRequest['listingId'] as String?;
            if (listingId != null) {
              final listing = await getRentalListing(listingId);
              if (listing != null) {
                final allowMultiple =
                    listing['allowMultipleRentals'] as bool? ?? false;
                final quantity = listing['quantity'] as int?;
                final rentType = (listing['rentType'] ?? 'item')
                    .toString()
                    .toLowerCase();
                final isBoardingHouse =
                    rentType == 'boardinghouse' || rentType == 'boarding_house';

                // For boarding houses, check if capacity is full
                if (isBoardingHouse) {
                  final occupancy = await getBoardingHouseOccupancy(listingId);
                  final availableSlots =
                      occupancy['availableSlots'] as int? ?? 0;
                  if (availableSlots <= 0) {
                    // Capacity is full, deactivate listing
                    await updateRentalListing(listingId, {
                      'isActive': false,
                      'updatedAt': DateTime.now(),
                    });
                  }
                } else if (!allowMultiple &&
                    (quantity == null || quantity <= 1)) {
                  // Only deactivate if it's a single-item listing (not multi-rental, not quantity-based)
                  await updateRentalListing(listingId, {
                    'isActive': false,
                    'updatedAt': DateTime.now(),
                  });
                }
              }
            }
          } catch (_) {
            // Best-effort; don't fail the update if listing update fails
          }

          // Notify renter that request was accepted
          if (renterId != null) {
            final priceQuote =
                (currentRequest['priceQuote'] as num?)?.toDouble() ?? 0.0;
            final fees = (currentRequest['fees'] as num?)?.toDouble() ?? 0.0;
            final depositAmount = (currentRequest['depositAmount'] as num?)
                ?.toDouble();

            await _db.collection('notifications').add({
              'toUserId': renterId,
              'type': 'rent_request_decision',
              'itemTitle': itemTitle,
              'requestId': id,
              'decision': 'accepted',
              'ownerName': ownerName,
              'status': 'unread',
              'createdAt': FieldValue.serverTimestamp(),
            });

            // Send payment reminder notification
            await _db.collection('notifications').add({
              'toUserId': renterId,
              'type': 'rent_payment_reminder',
              'itemTitle': itemTitle,
              'requestId': id,
              'message':
                  'Please pay $ownerName base price (₱${priceQuote.toStringAsFixed(2)})${depositAmount != null && depositAmount > 0 ? ' + deposit (₱${depositAmount.toStringAsFixed(2)})' : ''}',
              'status': 'unread',
              'createdAt': FieldValue.serverTimestamp(),
            });
          }
        } else if (newStatus.toLowerCase() == 'active' &&
            (oldStatus?.toLowerCase() ?? '') == 'ownerapproved') {
          // Notify both parties that rental is now active
          if (renterId != null) {
            await _db.collection('notifications').add({
              'toUserId': renterId,
              'type': 'rent_active',
              'itemTitle': itemTitle,
              'requestId': id,
              'message': 'Your rental is now active!',
              'status': 'unread',
              'createdAt': FieldValue.serverTimestamp(),
            });
          }
          if (ownerId != null) {
            await _db.collection('notifications').add({
              'toUserId': ownerId,
              'type': 'rent_active',
              'itemTitle': itemTitle,
              'requestId': id,
              'message': 'Rental is now active',
              'status': 'unread',
              'createdAt': FieldValue.serverTimestamp(),
            });
          }

          // Schedule rental end reminders for both renter and owner
          try {
            final endDate = (currentRequest['endDate'] as Timestamp?)?.toDate();
            if (endDate != null) {
              // Get user names for reminders
              String? renterName;
              String? ownerName;

              if (renterId != null) {
                final renterData = await getUser(renterId);
                if (renterData != null) {
                  final firstName = renterData['firstName'] ?? '';
                  final lastName = renterData['lastName'] ?? '';
                  renterName = '$firstName $lastName'.trim();
                }
              }
              renterName ??= 'Renter';

              if (ownerId != null) {
                final ownerData = await getUser(ownerId);
                if (ownerData != null) {
                  final firstName = ownerData['firstName'] ?? '';
                  final lastName = ownerData['lastName'] ?? '';
                  ownerName = '$firstName $lastName'.trim();
                }
              }
              ownerName ??= 'Owner';

              // Schedule rental end reminders for both renter and owner
              final itemId = currentRequest['itemId'] as String?;
              if (itemId != null && renterId != null && ownerId != null) {
                try {
                  final localNotificationsService = LocalNotificationsService();
                  await localNotificationsService.scheduleRentalEndReminders(
                    rentalRequestId: id,
                    itemId: itemId,
                    itemTitle: itemTitle,
                    endDateLocal: endDate,
                    renterId: renterId,
                    ownerId: ownerId,
                    renterName: renterName,
                    ownerName: ownerName,
                  );

                  // Also schedule overdue reminders if rental is already overdue
                  final now = DateTime.now();
                  if (endDate.isBefore(now)) {
                    // Schedule overdue reminders for renter
                    await localNotificationsService
                        .scheduleRentalOverdueReminders(
                          rentalRequestId: id,
                          itemId: itemId,
                          itemTitle: itemTitle,
                          endDateLocal: endDate,
                          renterId: renterId,
                          ownerId: ownerId,
                          renterName: renterName,
                          ownerName: ownerName,
                          isRenter: true,
                          targetUserId: renterId,
                        );

                    // Schedule overdue reminders for owner
                    await localNotificationsService
                        .scheduleRentalOverdueReminders(
                          rentalRequestId: id,
                          itemId: itemId,
                          itemTitle: itemTitle,
                          endDateLocal: endDate,
                          renterId: renterId,
                          ownerId: ownerId,
                          renterName: renterName,
                          ownerName: ownerName,
                          isRenter: false,
                          targetUserId: ownerId,
                        );
                  }
                } catch (e) {
                  debugPrint('Error scheduling rental end reminders: $e');
                  // Don't fail the update if reminder scheduling fails
                }
              }

              // For long-term rentals, also schedule monthly payment reminders
              final isLongTerm = currentRequest['isLongTerm'] as bool? ?? false;
              if (isLongTerm) {
                final nextPaymentDueDate =
                    (currentRequest['nextPaymentDueDate'] as Timestamp?)
                        ?.toDate();
                final monthlyAmount =
                    (currentRequest['monthlyPaymentAmount'] as num?)
                        ?.toDouble();

                if (nextPaymentDueDate != null &&
                    monthlyAmount != null &&
                    itemId != null) {
                  try {
                    await scheduleMonthlyPaymentReminders(
                      rentalRequestId: id,
                      itemId: itemId,
                      itemTitle: itemTitle,
                      nextPaymentDueDate: nextPaymentDueDate,
                      renterId: renterId!,
                      ownerId: ownerId!,
                      renterName: renterName,
                      ownerName: ownerName,
                      monthlyAmount: monthlyAmount,
                    );
                  } catch (e) {
                    debugPrint(
                      'Error scheduling monthly payment reminders: $e',
                    );
                    // Don't fail the update if reminder scheduling fails
                  }
                }
              }
            }
          } catch (e) {
            debugPrint('Error preparing rental reminders: $e');
            // Don't fail the update if reminder scheduling fails
          }
        } else if (newStatus == 'returninitiated') {
          // Notify owner that renter has initiated return
          if (ownerId != null) {
            // Get renter name for notification
            String? renterName;
            if (renterId != null) {
              try {
                final renterData = await getUser(renterId);
                if (renterData != null) {
                  final firstName = renterData['firstName'] as String? ?? '';
                  final lastName = renterData['lastName'] as String? ?? '';
                  renterName = '$firstName $lastName'.trim();
                  // If name is empty after trimming, use fallback
                  if (renterName.isEmpty) {
                    renterName = null;
                  }
                  debugPrint(
                    'Fetched renter name: $renterName for renterId: $renterId',
                  );
                } else {
                  debugPrint('Renter data is null for renterId: $renterId');
                }
              } catch (e) {
                debugPrint('Error fetching renter name for notification: $e');
                debugPrint('RenterId was: $renterId');
                // Continue if user fetch fails
              }
            } else {
              debugPrint('RenterId is null, cannot fetch renter name');
            }
            renterName ??= 'Renter';

            await _db.collection('notifications').add({
              'toUserId': ownerId,
              'type': 'rent_return_initiated',
              'itemTitle': itemTitle,
              'requestId': id,
              'renterName': renterName,
              'message': 'Renter has initiated return. Please verify the item.',
              'status': 'unread',
              'createdAt': FieldValue.serverTimestamp(),
            });
          }
        } else if (newStatus == 'returned' && oldStatus == 'returninitiated') {
          // Reactivate listing when rental is returned
          try {
            final listingId = currentRequest['listingId'] as String?;
            if (listingId != null) {
              final listing = await getRentalListing(listingId);
              if (listing != null) {
                final allowMultiple =
                    listing['allowMultipleRentals'] as bool? ?? false;
                final quantity = listing['quantity'] as int?;
                final rentType = (listing['rentType'] ?? 'item')
                    .toString()
                    .toLowerCase();
                final isBoardingHouse =
                    rentType == 'boardinghouse' || rentType == 'boarding_house';

                if (isBoardingHouse) {
                  // For boarding houses, check if capacity is now available
                  final occupancy = await getBoardingHouseOccupancy(listingId);
                  final availableSlots =
                      occupancy['availableSlots'] as int? ?? 0;
                  if (availableSlots > 0) {
                    // Capacity is available, reactivate listing
                    await updateRentalListing(listingId, {
                      'isActive': true,
                      'updatedAt': DateTime.now(),
                    });
                  }
                } else if (!allowMultiple &&
                    (quantity == null || quantity <= 1)) {
                  // Only reactivate if it's a single-item listing (not multi-rental, not quantity-based)
                  // Also check if there are no other active rentals
                  final hasOtherActive = await hasActiveRentalRequests(
                    listingId,
                  );
                  if (!hasOtherActive) {
                    await updateRentalListing(listingId, {
                      'isActive': true,
                      'updatedAt': DateTime.now(),
                    });
                  }
                }
              }
            }
          } catch (_) {
            // Best-effort; don't fail the update if listing update fails
          }

          // Notify renter that owner has verified return
          if (renterId != null) {
            // Get owner name for notification - try to reuse ownerName from earlier in function if available
            String? ownerNameForNotification;
            // Use ownerName if it's available and not the default value
            if (ownerName.isNotEmpty && ownerName != 'The owner') {
              ownerNameForNotification = ownerName;
              debugPrint(
                'Reusing ownerName from earlier: $ownerNameForNotification',
              );
            } else {
              // Fetch owner name if not available
              if (ownerId != null) {
                try {
                  final ownerData = await getUser(ownerId);
                  if (ownerData != null) {
                    final firstName = ownerData['firstName'] as String? ?? '';
                    final lastName = ownerData['lastName'] as String? ?? '';
                    ownerNameForNotification = '$firstName $lastName'.trim();
                    // If name is empty after trimming, use fallback
                    if (ownerNameForNotification.isEmpty) {
                      ownerNameForNotification = null;
                    }
                    debugPrint(
                      'Fetched owner name: $ownerNameForNotification for ownerId: $ownerId',
                    );
                  } else {
                    debugPrint('Owner data is null for ownerId: $ownerId');
                  }
                } catch (e) {
                  debugPrint('Error fetching owner name for notification: $e');
                  debugPrint('OwnerId was: $ownerId');
                  // Continue if user fetch fails
                }
              } else {
                debugPrint('OwnerId is null, cannot fetch owner name');
              }
            }
            ownerNameForNotification ??= 'Owner';

            await _db.collection('notifications').add({
              'toUserId': renterId,
              'type': 'rent_return_verified',
              'itemTitle': itemTitle,
              'requestId': id,
              'ownerName': ownerNameForNotification,
              'message': 'Owner has verified the return. Rental completed!',
              'status': 'unread',
              'createdAt': FieldValue.serverTimestamp(),
            });
          }
        } else if (newStatus == 'cancelled') {
          // Reactivate listing when rental is cancelled (if it's a single-item listing)
          try {
            final listingId = currentRequest['listingId'] as String?;
            if (listingId != null) {
              final listing = await getRentalListing(listingId);
              if (listing != null) {
                final allowMultiple =
                    listing['allowMultipleRentals'] as bool? ?? false;
                final quantity = listing['quantity'] as int?;

                // Only reactivate if it's a single-item listing (not multi-rental, not quantity-based)
                // Also check if there are no other active rentals
                if (!allowMultiple && (quantity == null || quantity <= 1)) {
                  final hasOtherActive = await hasActiveRentalRequests(
                    listingId,
                  );
                  if (!hasOtherActive) {
                    await updateRentalListing(listingId, {
                      'isActive': true,
                      'updatedAt': DateTime.now(),
                    });
                  }
                }
              }
            }
          } catch (_) {
            // Best-effort; don't fail the update if listing update fails
          }

          // Notify renter that request was declined (cancelled by owner)
          if (renterId != null && oldStatus == 'requested') {
            await _db.collection('notifications').add({
              'toUserId': renterId,
              'type': 'rent_request_decision',
              'itemTitle': itemTitle,
              'requestId': id,
              'decision': 'declined',
              'ownerName': ownerName,
              'status': 'unread',
              'createdAt': FieldValue.serverTimestamp(),
            });
          }
        }
      } catch (_) {
        // Best-effort; don't fail the update if notification write fails
      }
    }
  }

  Future<Map<String, dynamic>?> getRentalRequest(String id) async {
    final doc = await _db.collection('rental_requests').doc(id).get();
    if (!doc.exists) return null;
    final data = doc.data() as Map<String, dynamic>;
    data['id'] = doc.id;
    return data;
  }

  Future<List<Map<String, dynamic>>> getRentalRequestsByUser(
    String userId, {
    required bool asOwner,
  }) async {
    final q = _db
        .collection('rental_requests')
        .where(asOwner ? 'ownerId' : 'renterId', isEqualTo: userId);
    final snap = await q.get();
    return snap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      return data;
    }).toList();
  }

  /// Check if a renter already has a pending/active request for a specific listing
  Future<Map<String, dynamic>?> getExistingRentalRequest(
    String listingId,
    String renterId,
  ) async {
    try {
      final snap = await _db
          .collection('rental_requests')
          .where('listingId', isEqualTo: listingId)
          .where('renterId', isEqualTo: renterId)
          .where('status', whereIn: ['requested', 'ownerapproved', 'active'])
          .limit(1)
          .get();

      if (snap.docs.isEmpty) return null;

      final data = snap.docs.first.data();
      data['id'] = snap.docs.first.id;
      return data;
    } catch (e) {
      return null; // Return null on error to allow submission
    }
  }

  Future<List<Map<String, dynamic>>> getPendingRentalRequestsForRenter(
    String renterId,
  ) async {
    try {
      final snap = await _db
          .collection('rental_requests')
          .where('renterId', isEqualTo: renterId)
          .where('status', isEqualTo: 'requested')
          .get();
      return snap.docs.map((d) {
        final data = d.data();
        data['id'] = d.id;
        return data;
      }).toList();
    } catch (e) {
      throw Exception('Error getting pending rental requests: $e');
    }
  }

  Future<void> cancelRentalRequest({required String requestId}) async {
    await _db.collection('rental_requests').doc(requestId).update({
      'status': 'cancelled',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Check if two date ranges overlap
  bool _datesOverlap(
    DateTime start1,
    DateTime end1,
    DateTime start2,
    DateTime end2,
  ) {
    // Normalize dates to start of day for comparison
    final s1 = DateTime(start1.year, start1.month, start1.day);
    final e1 = DateTime(end1.year, end1.month, end1.day);
    final s2 = DateTime(start2.year, start2.month, start2.day);
    final e2 = DateTime(end2.year, end2.month, end2.day);

    // Two ranges overlap if: start1 <= end2 && start2 <= end1
    return s1.isBefore(e2.add(const Duration(days: 1))) &&
        s2.isBefore(e1.add(const Duration(days: 1)));
  }

  /// Check boarding house capacity before creating a rental request
  Future<void> _checkBoardingHouseCapacity({
    required String listingId,
    required Map<String, dynamic> listing,
    required DateTime startDate,
    DateTime? endDate,
    int requestedOccupants = 1,
  }) async {
    final maxOccupants = (listing['maxOccupants'] as num?)?.toInt();
    final occupantsPerRoom = (listing['occupantsPerRoom'] as num?)?.toInt();
    final numberOfRooms = (listing['numberOfRooms'] as num?)?.toInt();

    // Get all active/approved requests for this boarding house
    final activeRequests = await _db
        .collection('rental_requests')
        .where('listingId', isEqualTo: listingId)
        .where('status', whereIn: ['requested', 'ownerapproved', 'active'])
        .get();

    // Calculate current occupancy - start with initial/pre-existing occupants
    final initialOccupants =
        (listing['initialOccupants'] as num?)?.toInt() ?? 0;

    int currentOccupants = initialOccupants;
    final Set<int> occupiedRooms = {};

    for (final doc in activeRequests.docs) {
      final reqData = doc.data();
      final reqStart = (reqData['startDate'] as Timestamp?)?.toDate();
      final reqEnd = (reqData['endDate'] as Timestamp?)?.toDate();
      final reqIsLongTerm = reqData['isLongTerm'] as bool? ?? false;

      // For long-term rentals without end date, always count them
      bool isOverlapping = false;
      if (reqIsLongTerm && reqEnd == null) {
        // Month-to-month rental - always active
        isOverlapping = true;
      } else if (reqStart != null && reqEnd != null && endDate != null) {
        // Check if dates overlap
        isOverlapping = _datesOverlap(startDate, endDate, reqStart, reqEnd);
      } else if (reqStart != null && endDate == null) {
        // New request is month-to-month, check if existing request overlaps
        isOverlapping = reqStart.isBefore(
          DateTime.now().add(const Duration(days: 365)),
        );
      }

      if (isOverlapping) {
        // Count occupants from this request
        final reqOccupants =
            (reqData['numberOfOccupants'] as num?)?.toInt() ?? 1;
        currentOccupants += reqOccupants;

        // Track occupied rooms
        final assignedRooms = reqData['assignedRoomNumbers'] as List<dynamic>?;
        if (assignedRooms != null) {
          for (final room in assignedRooms) {
            if (room is int) {
              occupiedRooms.add(room);
            } else if (room is num) {
              occupiedRooms.add(room.toInt());
            }
          }
        }
      }
    }

    // Check max occupants limit
    if (maxOccupants != null) {
      if (currentOccupants + requestedOccupants > maxOccupants) {
        throw Exception(
          'Boarding house capacity exceeded. Current occupancy: $currentOccupants/$maxOccupants. '
          'Requested: $requestedOccupants. Available slots: ${maxOccupants - currentOccupants}.',
        );
      }
    }

    // Check capacity based on total rooms and occupants per room
    if (numberOfRooms != null && occupantsPerRoom != null) {
      // Fallback: calculate from total rooms and occupants per room
      final totalCapacity = numberOfRooms * occupantsPerRoom;
      if (currentOccupants + requestedOccupants > totalCapacity) {
        throw Exception(
          'Boarding house capacity exceeded. Current occupancy: $currentOccupants/$totalCapacity. '
          'Requested: $requestedOccupants. Available slots: ${totalCapacity - currentOccupants}.',
        );
      }
    }
  }

  /// Get current occupancy for a boarding house
  Future<Map<String, dynamic>> getBoardingHouseOccupancy(
    String listingId,
  ) async {
    final listing = await getRentalListing(listingId);
    if (listing == null) {
      return {
        'currentOccupants': 0,
        'maxOccupants': 0,
        'availableSlots': 0,
        'occupiedRooms': [],
        'availableRooms': [],
      };
    }

    final maxOccupants = (listing['maxOccupants'] as num?)?.toInt();
    final occupantsPerRoom = (listing['occupantsPerRoom'] as num?)?.toInt();
    final numberOfRooms = (listing['numberOfRooms'] as num?)?.toInt();

    // Get all active requests
    final activeRequests = await _db
        .collection('rental_requests')
        .where('listingId', isEqualTo: listingId)
        .where('status', whereIn: ['ownerapproved', 'active'])
        .get();

    // Start with initial/pre-existing occupants
    final initialOccupants =
        (listing['initialOccupants'] as num?)?.toInt() ?? 0;

    int currentOccupants = initialOccupants;
    final Set<int> occupiedRooms = {};

    for (final doc in activeRequests.docs) {
      final reqData = doc.data();
      final reqOccupants = (reqData['numberOfOccupants'] as num?)?.toInt() ?? 1;
      currentOccupants += reqOccupants;

      final assignedRooms = reqData['assignedRoomNumbers'] as List<dynamic>?;
      if (assignedRooms != null) {
        for (final room in assignedRooms) {
          if (room is int) {
            occupiedRooms.add(room);
          } else if (room is num) {
            occupiedRooms.add(room.toInt());
          }
        }
      }
    }

    // Calculate available slots
    final availableSlots = maxOccupants != null
        ? maxOccupants - currentOccupants
        : (numberOfRooms != null && occupantsPerRoom != null
              ? (numberOfRooms * occupantsPerRoom) - currentOccupants
              : 0);

    return {
      'currentOccupants': currentOccupants,
      'maxOccupants': maxOccupants ?? 0,
      'availableSlots': availableSlots,
      'occupiedRooms': occupiedRooms.toList()..sort(),
      'totalRooms': numberOfRooms ?? 0,
      'availableRoomCount': numberOfRooms != null
          ? numberOfRooms - occupiedRooms.length
          : 0,
      'occupiedRoomCount': occupiedRooms.length,
    };
  }

  /// Check availability for a listing on specific dates
  Future<Map<String, dynamic>> checkListingAvailability(
    String listingId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final listing = await getRentalListing(listingId);
    if (listing == null) {
      return {'available': false, 'reason': 'Listing not found'};
    }

    final allowMultiple = listing['allowMultipleRentals'] as bool? ?? false;
    final quantity = listing['quantity'] as int?;
    final isActive = listing['isActive'] as bool? ?? true;

    if (!isActive) {
      return {'available': false, 'reason': 'Listing is not active'};
    }

    // Get all active/approved requests for this listing
    final activeRequests = await _db
        .collection('rental_requests')
        .where('listingId', isEqualTo: listingId)
        .where('status', whereIn: ['requested', 'ownerapproved', 'active'])
        .get();

    if (allowMultiple) {
      // For commercial spaces/apartments - always available if listing is active
      return {'available': true, 'reason': null, 'conflictingRequests': 0};
    } else if (quantity != null && quantity > 1) {
      // For quantity-based rentals (clothes, etc.)
      int conflictingCount = 0;
      for (final doc in activeRequests.docs) {
        final reqData = doc.data();
        final reqStart = (reqData['startDate'] as Timestamp?)?.toDate();
        final reqEnd = (reqData['endDate'] as Timestamp?)?.toDate();

        if (reqStart != null && reqEnd != null) {
          if (_datesOverlap(startDate, endDate, reqStart, reqEnd)) {
            conflictingCount++;
          }
        }
      }

      final available = conflictingCount < quantity;
      return {
        'available': available,
        'reason': available
            ? null
            : 'All $quantity units are booked for these dates',
        'conflictingRequests': conflictingCount,
        'availableUnits': quantity - conflictingCount,
      };
    } else {
      // Single item rental - check for any overlapping dates
      for (final doc in activeRequests.docs) {
        final reqData = doc.data();
        final reqStart = (reqData['startDate'] as Timestamp?)?.toDate();
        final reqEnd = (reqData['endDate'] as Timestamp?)?.toDate();

        if (reqStart != null && reqEnd != null) {
          if (_datesOverlap(startDate, endDate, reqStart, reqEnd)) {
            return {
              'available': false,
              'reason': 'Item is already booked for these dates',
              'conflictingRequestId': doc.id,
            };
          }
        }
      }

      return {'available': true, 'reason': null, 'conflictingRequests': 0};
    }
  }

  // Rental Payments
  Future<String> createRentalPayment(Map<String, dynamic> data) async {
    final payload = Map<String, dynamic>.from(data);
    if (payload['createdAt'] is DateTime) {
      payload['createdAt'] = Timestamp.fromDate(payload['createdAt']);
    }
    final doc = await _db.collection('rental_payments').add(payload);
    return doc.id;
  }

  /// Renter initiates return - sets status to returnInitiated
  Future<bool> initiateRentalReturn({
    required String requestId,
    required String renterId,
    String? condition, // 'same', 'better', 'worse', 'damaged'
    String? conditionNotes,
    List<String>? conditionPhotos, // URLs of uploaded photos
  }) async {
    try {
      final request = await getRentalRequest(requestId);
      if (request == null) {
        throw Exception('Rental request not found');
      }

      final currentStatus = request['status'] as String?;
      if (currentStatus != 'active' && currentStatus != 'ownerapproved') {
        throw Exception('Can only initiate return for active rentals');
      }

      final requestRenterId = request['renterId'] as String?;
      if (requestRenterId != renterId) {
        throw Exception('Only the renter can initiate return');
      }

      final updateData = <String, dynamic>{
        'status': 'returninitiated',
        'returnInitiatedBy': renterId,
        'returnInitiatedAt': DateTime.now(),
        'updatedAt': DateTime.now(),
      };

      // Add condition verification data if provided
      if (condition != null) {
        updateData['renterCondition'] = condition;
      }
      if (conditionNotes != null && conditionNotes.isNotEmpty) {
        updateData['renterConditionNotes'] = conditionNotes;
      }
      if (conditionPhotos != null && conditionPhotos.isNotEmpty) {
        updateData['renterConditionPhotos'] = conditionPhotos;
      }

      await updateRentalRequest(requestId, updateData);

      // Send notification to owner
      final ownerId = request['ownerId'] as String?;
      final itemTitle = request['itemTitle'] as String? ?? 'Rental Item';
      final renterName = request['renterName'] as String? ?? 'Renter';

      if (ownerId != null && ownerId.isNotEmpty && ownerId != renterId) {
        try {
          await _db.collection('notifications').add({
            'toUserId': ownerId,
            'type': 'rent_return_initiated',
            'itemId': request['itemId'],
            'itemTitle': itemTitle,
            'fromUserId': renterId,
            'fromUserName': renterName,
            'requestId': requestId,
            'status': 'unread',
            'createdAt': FieldValue.serverTimestamp(),
          });
        } catch (e) {
          debugPrint('Error creating return notification: $e');
        }
      }

      return true;
    } catch (e) {
      debugPrint('Error initiating return: $e');
      rethrow;
    }
  }

  /// Owner verifies return - sets status to returned or disputed
  /// If conditionAccepted is false, status becomes 'disputed' for damage reporting
  Future<bool> verifyRentalReturn({
    required String requestId,
    required String ownerId,
    bool conditionAccepted = true,
    String? ownerConditionNotes,
    List<String>? ownerConditionPhotos,
    Map<String, dynamic>?
    damageReport, // {type, description, estimatedCost, photos}
  }) async {
    try {
      final request = await getRentalRequest(requestId);
      if (request == null) {
        throw Exception('Rental request not found');
      }

      final currentStatus = request['status'] as String?;
      if (currentStatus != 'returninitiated') {
        throw Exception('Return must be initiated by renter first');
      }

      final requestOwnerId = request['ownerId'] as String?;
      if (requestOwnerId != ownerId) {
        throw Exception('Only the owner can verify return');
      }

      final renterId = request['renterId'] as String?;
      final itemTitle = request['itemTitle'] as String? ?? 'Rental Item';
      final ownerName = request['ownerName'] as String? ?? 'Owner';

      final updateData = <String, dynamic>{
        'returnVerifiedBy': ownerId,
        'returnVerifiedAt': DateTime.now(),
        'actualReturnDate': DateTime.now(),
        'updatedAt': DateTime.now(),
      };

      if (conditionAccepted) {
        // Condition accepted - mark as returned
        updateData['status'] = 'returned';
        updateData['ownerConditionDecision'] = 'accepted';
      } else {
        // Condition disputed - requires damage reporting
        updateData['status'] = 'disputed';
        updateData['ownerConditionDecision'] = 'disputed';

        if (ownerConditionNotes != null && ownerConditionNotes.isNotEmpty) {
          updateData['ownerConditionNotes'] = ownerConditionNotes;
        }
        if (ownerConditionPhotos != null && ownerConditionPhotos.isNotEmpty) {
          updateData['ownerConditionPhotos'] = ownerConditionPhotos;
        }
        if (damageReport != null) {
          updateData['damageReport'] = damageReport;
        }
      }

      await updateRentalRequest(requestId, updateData);

      // Cancel rental reminders
      try {
        final localNotificationsService = LocalNotificationsService();
        final itemId = request['itemId'] as String?;
        if (itemId != null) {
          await localNotificationsService.cancelRentalReminders(requestId);
          await localNotificationsService.cancelRentalOverdueReminders(
            requestId,
          );
        }
      } catch (e) {
        debugPrint('Error cancelling rental reminders: $e');
      }

      // Send notification to renter
      if (renterId != null && renterId.isNotEmpty && renterId != ownerId) {
        try {
          final notificationType = conditionAccepted
              ? 'rent_return_verified'
              : 'rent_return_disputed';

          await _db.collection('notifications').add({
            'toUserId': renterId,
            'type': notificationType,
            'itemId': request['itemId'],
            'itemTitle': itemTitle,
            'fromUserId': ownerId,
            'fromUserName': ownerName,
            'requestId': requestId,
            'status': 'unread',
            'createdAt': FieldValue.serverTimestamp(),
          });
        } catch (e) {
          debugPrint('Error creating return verification notification: $e');
        }
      }

      return true;
    } catch (e) {
      debugPrint('Error verifying return: $e');
      rethrow;
    }
  }

  /// Get disputed rentals for a renter (rentals that were disputed by owner)
  Future<List<Map<String, dynamic>>> getDisputedRentalsForRenter(
    String renterId,
  ) async {
    try {
      final snap = await _db
          .collection('rental_requests')
          .where('renterId', isEqualTo: renterId)
          .where('status', isEqualTo: 'disputed')
          .get();

      final disputedRentals = <Map<String, dynamic>>[];

      for (final doc in snap.docs) {
        final requestData = doc.data();
        final itemId = requestData['itemId'] as String?;
        final listingId = requestData['listingId'] as String?;

        // Get item details
        try {
          if (itemId != null) {
            final itemDoc = await _db.collection('items').doc(itemId).get();
            if (itemDoc.exists) {
              final itemData = itemDoc.data() as Map<String, dynamic>;
              final combined = Map<String, dynamic>.from(requestData);
              combined['id'] = doc.id;
              combined.addAll(itemData);
              combined['itemId'] = itemId;
              disputedRentals.add(combined);
            } else {
              // If item doesn't exist, still include request data
              final combined = Map<String, dynamic>.from(requestData);
              combined['id'] = doc.id;
              disputedRentals.add(combined);
            }
          } else if (listingId != null) {
            // Try to get listing data
            final listing = await getRentalListing(listingId);
            if (listing != null) {
              final combined = Map<String, dynamic>.from(requestData);
              combined['id'] = doc.id;
              combined.addAll(listing);
              disputedRentals.add(combined);
            } else {
              final combined = Map<String, dynamic>.from(requestData);
              combined['id'] = doc.id;
              disputedRentals.add(combined);
            }
          } else {
            final combined = Map<String, dynamic>.from(requestData);
            combined['id'] = doc.id;
            disputedRentals.add(combined);
          }
        } catch (e) {
          debugPrint('Error fetching item/listing for disputed rental: $e');
          // Still add request data even if item/listing fetch fails
          final combined = Map<String, dynamic>.from(requestData);
          combined['id'] = doc.id;
          disputedRentals.add(combined);
        }
      }

      return disputedRentals;
    } catch (e) {
      throw Exception('Error getting disputed rentals for renter: $e');
    }
  }

  /// Get disputed rentals for an owner (rentals that owner disputed)
  Future<List<Map<String, dynamic>>> getDisputedRentalsForOwner(
    String ownerId,
  ) async {
    try {
      final snap = await _db
          .collection('rental_requests')
          .where('ownerId', isEqualTo: ownerId)
          .where('status', isEqualTo: 'disputed')
          .get();

      final disputedRentals = <Map<String, dynamic>>[];

      for (final doc in snap.docs) {
        final requestData = doc.data();
        final itemId = requestData['itemId'] as String?;
        final listingId = requestData['listingId'] as String?;

        // Get item details
        try {
          if (itemId != null) {
            final itemDoc = await _db.collection('items').doc(itemId).get();
            if (itemDoc.exists) {
              final itemData = itemDoc.data() as Map<String, dynamic>;
              final combined = Map<String, dynamic>.from(requestData);
              combined['id'] = doc.id;
              combined.addAll(itemData);
              combined['itemId'] = itemId;
              disputedRentals.add(combined);
            } else {
              final combined = Map<String, dynamic>.from(requestData);
              combined['id'] = doc.id;
              disputedRentals.add(combined);
            }
          } else if (listingId != null) {
            final listing = await getRentalListing(listingId);
            if (listing != null) {
              final combined = Map<String, dynamic>.from(requestData);
              combined['id'] = doc.id;
              combined.addAll(listing);
              disputedRentals.add(combined);
            } else {
              final combined = Map<String, dynamic>.from(requestData);
              combined['id'] = doc.id;
              disputedRentals.add(combined);
            }
          } else {
            final combined = Map<String, dynamic>.from(requestData);
            combined['id'] = doc.id;
            disputedRentals.add(combined);
          }
        } catch (e) {
          debugPrint('Error fetching item/listing for disputed rental: $e');
          final combined = Map<String, dynamic>.from(requestData);
          combined['id'] = doc.id;
          disputedRentals.add(combined);
        }
      }

      return disputedRentals;
    } catch (e) {
      throw Exception('Error getting disputed rentals for owner: $e');
    }
  }

  /// Record a monthly payment for long-term rentals
  Future<String> recordMonthlyRentalPayment({
    required String rentalRequestId,
    required double amount,
    required DateTime paymentDate,
    String? providerRef,
  }) async {
    try {
      final request = await getRentalRequest(rentalRequestId);
      if (request == null) {
        throw Exception('Rental request not found');
      }

      final isLongTerm = request['isLongTerm'] as bool? ?? false;
      if (!isLongTerm) {
        throw Exception('This rental is not a long-term rental');
      }

      // Create payment record
      final paymentId = await createRentalPayment({
        'rentalRequestId': rentalRequestId,
        'method': 'manual',
        'provider': 'none',
        'type': 'capture',
        'status': 'succeeded',
        'amount': amount,
        'currency': 'PHP',
        'providerRef': providerRef,
        'createdAt': paymentDate,
      });

      // Update rental request with payment info
      final nextPaymentDue = request['nextPaymentDueDate'] as Timestamp?;
      DateTime? newNextPaymentDue;

      if (nextPaymentDue != null) {
        // Calculate next month's due date
        final currentDue = nextPaymentDue.toDate();
        newNextPaymentDue = DateTime(
          currentDue.year,
          currentDue.month + 1,
          currentDue.day,
        );
      }

      await updateRentalRequest(rentalRequestId, {
        'lastPaymentDate': paymentDate,
        'nextPaymentDueDate': newNextPaymentDue,
        'updatedAt': DateTime.now(),
      });

      // Schedule monthly payment reminders for the next payment
      if (newNextPaymentDue != null) {
        try {
          final itemId = request['itemId'] as String?;
          final itemTitle =
              request['itemTitle'] as String? ??
              (await getRentalListing(
                    request['listingId'] as String? ?? '',
                  ))?['title']
                  as String? ??
              'Rental Item';
          final renterId = request['renterId'] as String?;
          final ownerId = request['ownerId'] as String?;
          final monthlyAmount = request['monthlyPaymentAmount'] as num?;

          if (itemId != null &&
              renterId != null &&
              ownerId != null &&
              monthlyAmount != null) {
            // Get user names for reminders
            String? renterName;
            String? ownerName;

            final renterData = await getUser(renterId);
            if (renterData != null) {
              final firstName = renterData['firstName'] ?? '';
              final lastName = renterData['lastName'] ?? '';
              renterName = '$firstName $lastName'.trim();
            }
            renterName ??= 'Renter';

            final ownerData = await getUser(ownerId);
            if (ownerData != null) {
              final firstName = ownerData['firstName'] ?? '';
              final lastName = ownerData['lastName'] ?? '';
              ownerName = '$firstName $lastName'.trim();
            }
            ownerName ??= 'Owner';

            await scheduleMonthlyPaymentReminders(
              rentalRequestId: rentalRequestId,
              itemId: itemId,
              itemTitle: itemTitle,
              nextPaymentDueDate: newNextPaymentDue,
              renterId: renterId,
              ownerId: ownerId,
              renterName: renterName,
              ownerName: ownerName,
              monthlyAmount: monthlyAmount.toDouble(),
            );
          }
        } catch (e) {
          debugPrint('Error scheduling monthly payment reminders: $e');
          // Don't fail the payment recording if reminder scheduling fails
        }
      }

      return paymentId;
    } catch (e) {
      debugPrint('Error recording monthly payment: $e');
      rethrow;
    }
  }

  /// Schedule monthly payment reminders for long-term rentals
  Future<void> scheduleMonthlyPaymentReminders({
    required String rentalRequestId,
    required String itemId,
    required String itemTitle,
    required DateTime nextPaymentDueDate,
    required String renterId,
    required String ownerId,
    required String renterName,
    required String ownerName,
    required double monthlyAmount,
  }) async {
    try {
      final now = DateTime.now();
      final dueDate = nextPaymentDueDate;

      // Schedule reminder 3 days before payment due
      final reminder3Days = dueDate.subtract(const Duration(days: 3));
      if (reminder3Days.isAfter(now)) {
        await _createMonthlyPaymentReminder(
          rentalRequestId: rentalRequestId,
          itemId: itemId,
          itemTitle: itemTitle,
          scheduledTime: reminder3Days,
          userId: renterId,
          userName: renterName,
          isRenter: true,
          monthlyAmount: monthlyAmount,
          reminderType: 'monthly_payment_3d',
        );
      }

      // Schedule reminder 1 day before payment due
      final reminder1Day = dueDate.subtract(const Duration(days: 1));
      if (reminder1Day.isAfter(now)) {
        await _createMonthlyPaymentReminder(
          rentalRequestId: rentalRequestId,
          itemId: itemId,
          itemTitle: itemTitle,
          scheduledTime: reminder1Day,
          userId: renterId,
          userName: renterName,
          isRenter: true,
          monthlyAmount: monthlyAmount,
          reminderType: 'monthly_payment_1d',
        );
      }

      // Schedule reminder on payment due date
      if (dueDate.isAfter(now)) {
        await _createMonthlyPaymentReminder(
          rentalRequestId: rentalRequestId,
          itemId: itemId,
          itemTitle: itemTitle,
          scheduledTime: dueDate,
          userId: renterId,
          userName: renterName,
          isRenter: true,
          monthlyAmount: monthlyAmount,
          reminderType: 'monthly_payment_due',
        );
      }

      // Schedule overdue reminder for owner (if payment is late)
      final overdueReminder = dueDate.add(const Duration(days: 1));
      if (overdueReminder.isAfter(now)) {
        await _createMonthlyPaymentReminder(
          rentalRequestId: rentalRequestId,
          itemId: itemId,
          itemTitle: itemTitle,
          scheduledTime: overdueReminder,
          userId: ownerId,
          userName: ownerName,
          isRenter: false,
          monthlyAmount: monthlyAmount,
          reminderType: 'monthly_payment_overdue',
        );
      }
    } catch (e) {
      debugPrint('Error scheduling monthly payment reminders: $e');
      // Don't throw - reminder scheduling failure shouldn't break payment recording
    }
  }

  /// Helper to create monthly payment reminder in Firestore
  Future<void> _createMonthlyPaymentReminder({
    required String rentalRequestId,
    required String itemId,
    required String itemTitle,
    required DateTime scheduledTime,
    required String userId,
    required String userName,
    required bool isRenter,
    required double monthlyAmount,
    required String reminderType,
  }) async {
    try {
      final reminderId = 'monthly_${rentalRequestId}_${reminderType}_$userId';
      String title;
      String body;

      if (isRenter) {
        switch (reminderType) {
          case 'monthly_payment_3d':
            title = 'Monthly payment due in 3 days: $itemTitle';
            body =
                'Your monthly payment of ₱${monthlyAmount.toStringAsFixed(2)} for "$itemTitle" is due in 3 days.';
            break;
          case 'monthly_payment_1d':
            title = 'Monthly payment due tomorrow: $itemTitle';
            body =
                'Your monthly payment of ₱${monthlyAmount.toStringAsFixed(2)} for "$itemTitle" is due tomorrow.';
            break;
          case 'monthly_payment_due':
            title = 'Monthly payment due today: $itemTitle';
            body =
                'Your monthly payment of ₱${monthlyAmount.toStringAsFixed(2)} for "$itemTitle" is due today.';
            break;
          default:
            title = 'Payment reminder: $itemTitle';
            body = 'Payment reminder for "$itemTitle"';
        }
      } else {
        title = 'Payment overdue: $itemTitle';
        body =
            'Monthly payment of ₱${monthlyAmount.toStringAsFixed(2)} for "$itemTitle" by $userName is overdue.';
      }

      await _db.collection('reminders').doc(reminderId).set({
        'userId': userId,
        'itemId': itemId,
        'itemTitle': itemTitle,
        'rentalRequestId': rentalRequestId,
        'scheduledTime': Timestamp.fromDate(scheduledTime),
        'title': title,
        'body': body,
        'reminderType': reminderType,
        'isBorrower': isRenter,
        'sent': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error creating monthly payment reminder: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getPaymentsForRequest(
    String rentalRequestId,
  ) async {
    final snap = await _db
        .collection('rental_payments')
        .where('rentalRequestId', isEqualTo: rentalRequestId)
        .get();
    return snap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      return data;
    }).toList();
  }

  // Rental Audits
  Future<String> createRentalAudit(Map<String, dynamic> data) async {
    final payload = Map<String, dynamic>.from(data);
    if (payload['createdAt'] is DateTime) {
      payload['createdAt'] = Timestamp.fromDate(payload['createdAt']);
    }
    final doc = await _db.collection('rental_audits').add(payload);
    return doc.id;
  }
}

// ---------------- TRADING MODULE ----------------
extension FirestoreServiceTrading on FirestoreService {
  // Trade Item operations
  Future<String> createTradeItem(Map<String, dynamic> data) async {
    final payload = Map<String, dynamic>.from(data);
    // createdAt can be FieldValue.serverTimestamp() or DateTime
    // If DateTime is provided, convert it to Timestamp
    // If FieldValue.serverTimestamp(), keep it as is
    if (payload['createdAt'] is DateTime) {
      payload['createdAt'] = Timestamp.fromDate(payload['createdAt']);
    }
    // FieldValue.serverTimestamp() will pass through as-is
    final doc = await _db.collection('trade_items').add(payload);
    return doc.id;
  }

  Future<void> updateTradeItem(String id, Map<String, dynamic> data) async {
    final payload = Map<String, dynamic>.from(data);
    await _db.collection('trade_items').doc(id).update(payload);
  }

  Future<Map<String, dynamic>?> getTradeItem(String id) async {
    final doc = await _db.collection('trade_items').doc(id).get();
    if (!doc.exists) return null;
    final data = doc.data() as Map<String, dynamic>;
    data['id'] = doc.id;
    return data;
  }

  Future<List<Map<String, dynamic>>> getTradeItemsByUser(String userId) async {
    final snap = await _db
        .collection('trade_items')
        .where('offeredBy', isEqualTo: userId)
        .get();
    return snap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      return data;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getActiveTradeItems() async {
    final snap = await _db
        .collection('trade_items')
        .where('status', isEqualTo: 'Open')
        .get();
    return snap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      return data;
    }).toList();
  }

  Future<void> deleteTradeItem(String tradeItemId) async {
    try {
      // Get trade item data first to extract image URLs
      final tradeItem = await getTradeItem(tradeItemId);
      if (tradeItem != null) {
        // Collect all image URLs
        final List<String> imageUrls = [];

        // Add all images from offeredImageUrls array if exists
        final offeredImages = tradeItem['offeredImageUrls'] as List<dynamic>?;
        if (offeredImages != null) {
          for (final img in offeredImages) {
            if (img is String && img.isNotEmpty && !imageUrls.contains(img)) {
              imageUrls.add(img);
            }
          }
        }

        // Delete images from Firebase Storage (best effort)
        if (imageUrls.isNotEmpty) {
          try {
            final storageService = StorageService();
            await storageService.deleteImages(imageUrls);
          } catch (e) {
            // Log but don't fail the deletion - continue with Firestore deletion
            debugPrint(
              'Warning: Failed to delete some images from storage: $e',
            );
          }
        }
      }

      // Delete the Firestore document
      await _db.collection('trade_items').doc(tradeItemId).delete();
    } catch (e) {
      throw Exception('Error deleting trade item: $e');
    }
  }

  // Check if trade item has active trade offers
  Future<bool> hasActiveTradeOffers(String tradeItemId) async {
    try {
      final snapshot = await _db
          .collection('trade_offers')
          .where('tradeItemId', isEqualTo: tradeItemId)
          .where('status', whereIn: ['pending', 'approved'])
          .limit(1)
          .get();
      return snapshot.docs.isNotEmpty;
    } catch (e) {
      throw Exception('Error checking active trade offers: $e');
    }
  }

  // Trade Offer operations
  Future<String> createTradeOffer(Map<String, dynamic> data) async {
    final payload = Map<String, dynamic>.from(data);

    // Prevent duplicate offers: Check if user already has a pending/approved offer for this trade item
    final tradeItemId = payload['tradeItemId'] as String?;
    final fromUserId = payload['fromUserId'] as String?;

    if (tradeItemId != null && fromUserId != null) {
      // Check for existing offers with status: pending or approved (not declined)
      final existing = await _db
          .collection('trade_offers')
          .where('tradeItemId', isEqualTo: tradeItemId)
          .where('fromUserId', isEqualTo: fromUserId)
          .where('status', whereIn: ['pending', 'approved'])
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        final existingStatus =
            existing.docs.first.data()['status'] as String? ?? 'pending';
        throw Exception(
          'You already have a ${existingStatus} trade offer for this item. '
          'Please wait for the owner to respond or cancel your existing offer first.',
        );
      }
    }

    // createdAt can be FieldValue.serverTimestamp() or DateTime
    if (payload['createdAt'] is DateTime) {
      payload['createdAt'] = Timestamp.fromDate(payload['createdAt']);
    }
    if (payload['updatedAt'] is DateTime) {
      payload['updatedAt'] = Timestamp.fromDate(payload['updatedAt']);
    }
    final doc = await _db.collection('trade_offers').add(payload);

    // Create a lightweight notification for the trade listing owner
    try {
      await _db.collection('notifications').add({
        'toUserId': payload['toUserId'],
        'type': 'trade_offer',
        'tradeItemId': payload['tradeItemId'],
        'itemTitle': payload['originalOfferedItemName'],
        'fromUserId': payload['fromUserId'],
        'fromUserName': payload['fromUserName'],
        'offerId': doc.id,
        'status': 'unread',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Best-effort; don't fail the offer if notification write fails
    }

    return doc.id;
  }

  Future<void> updateTradeOffer(String id, Map<String, dynamic> data) async {
    final payload = Map<String, dynamic>.from(data);

    // Get current offer to check status change
    final currentOffer = await getTradeOffer(id);
    final oldStatus = currentOffer?['status'] as String?;
    final newStatus = payload['status'] as String?;

    if (payload['updatedAt'] is DateTime) {
      payload['updatedAt'] = Timestamp.fromDate(payload['updatedAt']);
    }
    await _db.collection('trade_offers').doc(id).update(payload);

    // Send notification if status changed to approved or declined
    if (oldStatus != newStatus && newStatus != null && currentOffer != null) {
      try {
        final fromUserId = currentOffer['fromUserId'] as String?;
        final toUserId = currentOffer['toUserId'] as String?;
        final itemTitle =
            currentOffer['originalOfferedItemName'] as String? ?? 'Trade Item';

        String? ownerName;
        if (toUserId != null) {
          final owner = await getUser(toUserId);
          if (owner != null) {
            final firstName = owner['firstName'] ?? '';
            final lastName = owner['lastName'] ?? '';
            ownerName = '$firstName $lastName'.trim();
          }
        }
        ownerName ??= 'The owner';

        if (newStatus == 'approved') {
          // Notify offerer that trade was accepted
          if (fromUserId != null) {
            await _db.collection('notifications').add({
              'toUserId': fromUserId,
              'type': 'trade_offer_decision',
              'itemTitle': itemTitle,
              'offerId': id,
              'decision': 'accepted',
              'ownerName': ownerName,
              'status': 'unread',
              'createdAt': FieldValue.serverTimestamp(),
            });
          }
        } else if (newStatus == 'declined') {
          // Notify offerer that trade was declined
          if (fromUserId != null) {
            await _db.collection('notifications').add({
              'toUserId': fromUserId,
              'type': 'trade_offer_decision',
              'itemTitle': itemTitle,
              'offerId': id,
              'decision': 'declined',
              'ownerName': ownerName,
              'status': 'unread',
              'createdAt': FieldValue.serverTimestamp(),
            });
          }
        }
      } catch (_) {
        // Best-effort; don't fail the update if notification write fails
      }
    }
  }

  Future<Map<String, dynamic>?> getTradeOffer(String id) async {
    final doc = await _db.collection('trade_offers').doc(id).get();
    if (!doc.exists) return null;
    final data = doc.data() as Map<String, dynamic>;
    data['id'] = doc.id;
    return data;
  }

  Future<List<Map<String, dynamic>>> getTradeOffersByUser(String userId) async {
    // Get both incoming (toUserId) and outgoing (fromUserId) offers
    final incomingSnap = await _db
        .collection('trade_offers')
        .where('toUserId', isEqualTo: userId)
        .get();
    final outgoingSnap = await _db
        .collection('trade_offers')
        .where('fromUserId', isEqualTo: userId)
        .get();

    final List<Map<String, dynamic>> allOffers = [];
    allOffers.addAll(
      incomingSnap.docs.map((d) {
        final data = d.data();
        data['id'] = d.id;
        return data;
      }),
    );
    allOffers.addAll(
      outgoingSnap.docs.map((d) {
        final data = d.data();
        data['id'] = d.id;
        return data;
      }),
    );

    return allOffers;
  }

  Future<List<Map<String, dynamic>>> getPendingTradeOffersForUser(
    String userId,
  ) async {
    try {
      final snap = await _db
          .collection('trade_offers')
          .where('fromUserId', isEqualTo: userId)
          .where('status', isEqualTo: 'pending')
          .get();
      return snap.docs.map((d) {
        final data = d.data();
        data['id'] = d.id;
        return data;
      }).toList();
    } catch (e) {
      throw Exception('Error getting pending trade offers: $e');
    }
  }

  Future<void> cancelTradeOffer({required String offerId}) async {
    await _db.collection('trade_offers').doc(offerId).update({
      'status': 'cancelled',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<Map<String, dynamic>>> getTradeOffersForTradeItem(
    String tradeItemId,
  ) async {
    final snap = await _db
        .collection('trade_offers')
        .where('tradeItemId', isEqualTo: tradeItemId)
        .get();
    return snap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      return data;
    }).toList();
  }

  // Check if user has a pending or approved offer for a trade item
  Future<bool> hasPendingOrApprovedTradeOffer({
    required String tradeItemId,
    required String userId,
  }) async {
    try {
      final snapshot = await _db
          .collection('trade_offers')
          .where('tradeItemId', isEqualTo: tradeItemId)
          .where('fromUserId', isEqualTo: userId)
          .where('status', whereIn: ['pending', 'approved'])
          .limit(1)
          .get();
      return snapshot.docs.isNotEmpty;
    } catch (e) {
      // Return false on error to allow the button to be enabled
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getIncomingTradeOffers(
    String userId,
  ) async {
    try {
      // Query without orderBy to avoid composite index requirement
      // We'll sort client-side instead
      final snap = await _db
          .collection('trade_offers')
          .where('toUserId', isEqualTo: userId)
          .where('status', isEqualTo: 'pending')
          .get();

      final offers = snap.docs.map((d) {
        final data = d.data();
        data['id'] = d.id;
        return data;
      }).toList();

      // Sort client-side by createdAt (newest first)
      offers.sort((a, b) {
        final aDate = (a['createdAt'] as Timestamp?)?.toDate() ?? DateTime(0);
        final bDate = (b['createdAt'] as Timestamp?)?.toDate() ?? DateTime(0);
        return bDate.compareTo(aDate);
      });

      return offers;
    } catch (e) {
      throw Exception('Error getting incoming trade offers: $e');
    }
  }

  Future<void> acceptTradeOffer({
    required String offerId,
    required String tradeItemId,
  }) async {
    final batch = _db.batch();

    // Get the offer to check details
    final offerDoc = await _db.collection('trade_offers').doc(offerId).get();
    if (!offerDoc.exists) {
      throw Exception('Trade offer not found');
    }
    final offerData = offerDoc.data() as Map<String, dynamic>;
    final fromUserId = offerData['fromUserId'] as String?;

    // Update the accepted offer
    final offerRef = _db.collection('trade_offers').doc(offerId);
    batch.update(offerRef, {
      'status': 'approved',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Update trade item status to Traded
    final tradeItemRef = _db.collection('trade_items').doc(tradeItemId);
    batch.update(tradeItemRef, {
      'status': 'Traded',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Decline all other pending offers for the same trade item
    final otherOffersSnap = await _db
        .collection('trade_offers')
        .where('tradeItemId', isEqualTo: tradeItemId)
        .where('status', isEqualTo: 'pending')
        .get();

    for (var doc in otherOffersSnap.docs) {
      if (doc.id != offerId) {
        batch.update(doc.reference, {
          'status': 'declined',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    await batch.commit();

    // Create notifications
    try {
      if (fromUserId != null) {
        final itemTitle =
            offerData['originalOfferedItemName'] as String? ?? 'Trade Item';
        await _db.collection('notifications').add({
          'toUserId': fromUserId,
          'type': 'trade_offer_decision',
          'itemTitle': itemTitle,
          'offerId': offerId,
          'decision': 'accepted',
          'status': 'unread',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      // Notify other users whose offers were declined
      for (var doc in otherOffersSnap.docs) {
        if (doc.id != offerId) {
          final otherOfferData = doc.data();
          final otherFromUserId = otherOfferData['fromUserId'] as String?;
          if (otherFromUserId != null) {
            final itemTitle =
                otherOfferData['originalOfferedItemName'] as String? ??
                'Trade Item';
            await _db.collection('notifications').add({
              'toUserId': otherFromUserId,
              'type': 'trade_offer_decision',
              'itemTitle': itemTitle,
              'offerId': doc.id,
              'decision': 'declined',
              'status': 'unread',
              'createdAt': FieldValue.serverTimestamp(),
            });
          }
        }
      }
    } catch (_) {
      // Best-effort; don't fail if notification write fails
    }
  }

  Future<void> declineTradeOffer({required String offerId}) async {
    final offerRef = _db.collection('trade_offers').doc(offerId);
    final offerDoc = await offerRef.get();

    if (!offerDoc.exists) {
      throw Exception('Trade offer not found');
    }

    final offerData = offerDoc.data() as Map<String, dynamic>;
    final fromUserId = offerData['fromUserId'] as String?;

    await offerRef.update({
      'status': 'declined',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Create notification
    try {
      if (fromUserId != null) {
        final itemTitle =
            offerData['originalOfferedItemName'] as String? ?? 'Trade Item';
        await _db.collection('notifications').add({
          'toUserId': fromUserId,
          'type': 'trade_offer_decision',
          'itemTitle': itemTitle,
          'offerId': offerId,
          'decision': 'declined',
          'status': 'unread',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (_) {
      // Best-effort; don't fail if notification write fails
    }
  }

  Future<void> completeTradeOffer({required String offerId}) async {
    final offerRef = _db.collection('trade_offers').doc(offerId);
    final offerDoc = await offerRef.get();

    if (!offerDoc.exists) {
      throw Exception('Trade offer not found');
    }

    final offerData = offerDoc.data() as Map<String, dynamic>;
    final fromUserId = offerData['fromUserId'] as String?;
    final toUserId = offerData['toUserId'] as String?;
    final currentStatus = offerData['status'] as String?;

    // Only allow completing approved trades
    if (currentStatus != 'approved') {
      throw Exception('Only approved trades can be marked as completed');
    }

    await offerRef.update({
      'status': 'completed',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Create notifications for both parties
    try {
      final itemTitle =
          offerData['originalOfferedItemName'] as String? ?? 'Trade Item';

      // Notify both parties that trade is completed
      if (fromUserId != null) {
        await _db.collection('notifications').add({
          'toUserId': fromUserId,
          'type': 'trade_completed',
          'itemTitle': itemTitle,
          'offerId': offerId,
          'status': 'unread',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      if (toUserId != null) {
        await _db.collection('notifications').add({
          'toUserId': toUserId,
          'type': 'trade_completed',
          'itemTitle': itemTitle,
          'offerId': offerId,
          'status': 'unread',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (_) {
      // Best-effort; don't fail if notification write fails
    }
  }
}

// ---------------- GIVEAWAY / DONATION MODULE ----------------
extension FirestoreServiceGiveaway on FirestoreService {
  // Giveaway Listing operations
  Future<String> createGiveaway(Map<String, dynamic> data) async {
    final payload = Map<String, dynamic>.from(data);
    // Convert DateTime fields to Timestamps
    if (payload['createdAt'] is DateTime) {
      payload['createdAt'] = Timestamp.fromDate(payload['createdAt']);
    }
    if (payload['updatedAt'] is DateTime) {
      payload['updatedAt'] = Timestamp.fromDate(payload['updatedAt']);
    }
    if (payload['claimedAt'] is DateTime) {
      payload['claimedAt'] = Timestamp.fromDate(payload['claimedAt']);
    }
    // FieldValue.serverTimestamp() will pass through as-is
    final doc = await _db.collection('giveaways').add(payload);
    return doc.id;
  }

  Future<void> updateGiveaway(String id, Map<String, dynamic> data) async {
    final payload = Map<String, dynamic>.from(data);
    // Convert DateTime fields to Timestamps
    if (payload['updatedAt'] is DateTime) {
      payload['updatedAt'] = Timestamp.fromDate(payload['updatedAt']);
    }
    if (payload['claimedAt'] is DateTime) {
      payload['claimedAt'] = Timestamp.fromDate(payload['claimedAt']);
    }
    await _db.collection('giveaways').doc(id).update(payload);
  }

  Future<Map<String, dynamic>?> getGiveaway(String id) async {
    final doc = await _db.collection('giveaways').doc(id).get();
    if (!doc.exists) return null;
    final data = doc.data() as Map<String, dynamic>;
    data['id'] = doc.id;
    return data;
  }

  Future<List<Map<String, dynamic>>> getGiveawaysByUser(String userId) async {
    final snap = await _db
        .collection('giveaways')
        .where('donorId', isEqualTo: userId)
        .get();
    return snap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      return data;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getActiveGiveaways() async {
    final snap = await _db
        .collection('giveaways')
        .where('status', isEqualTo: 'active')
        .get();
    return snap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      return data;
    }).toList();
  }

  // Claim Request operations
  Future<String> createClaimRequest(Map<String, dynamic> data) async {
    final payload = Map<String, dynamic>.from(data);
    // Convert DateTime fields to Timestamps
    for (final k in ['createdAt', 'updatedAt', 'approvedAt', 'rejectedAt']) {
      if (payload[k] is DateTime) {
        payload[k] = Timestamp.fromDate(payload[k]);
      }
    }
    // FieldValue.serverTimestamp() will pass through as-is
    final doc = await _db.collection('giveaway_claims').add(payload);

    // Create a lightweight notification for the donor
    try {
      // Fetch giveaway to get item title
      String? itemTitle;
      final giveawayId = payload['giveawayId'] as String?;
      if (giveawayId != null) {
        final giveaway = await getGiveaway(giveawayId);
        itemTitle = giveaway?['title'] as String? ?? 'Donation Item';
      }
      itemTitle ??= 'Donation Item';

      final claimantName = payload['claimantName'] as String? ?? 'A user';
      final claimantId = payload['claimantId'] as String?;

      await _db.collection('notifications').add({
        'toUserId': payload['donorId'],
        'type': 'donation_request',
        'itemId': giveawayId,
        'itemTitle': itemTitle,
        'fromUserId': claimantId,
        'fromUserName': claimantName,
        'requestId': doc.id,
        'status': 'unread',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Best-effort; don't fail the claim if notification write fails
    }

    return doc.id;
  }

  Future<void> updateClaimRequest(String id, Map<String, dynamic> data) async {
    final payload = Map<String, dynamic>.from(data);

    // Get current claim to check status change
    final currentClaim = await getClaimRequest(id);
    final oldStatus = currentClaim?['status'] as String?;
    final newStatus = payload['status'] as String?;

    // Convert DateTime fields to Timestamps
    for (final k in ['updatedAt', 'approvedAt', 'rejectedAt']) {
      if (payload[k] is DateTime) {
        payload[k] = Timestamp.fromDate(payload[k]);
      }
    }
    await _db.collection('giveaway_claims').doc(id).update(payload);

    // Send notification if status changed to approved or rejected
    if (oldStatus != newStatus && newStatus != null && currentClaim != null) {
      try {
        final claimantId = currentClaim['claimantId'] as String?;
        final donorId = currentClaim['donorId'] as String?;
        final giveawayId = currentClaim['giveawayId'] as String?;

        String? itemTitle;
        if (giveawayId != null) {
          final giveaway = await getGiveaway(giveawayId);
          itemTitle = giveaway?['title'] as String? ?? 'Donation Item';
        }
        itemTitle ??= 'Donation Item';

        String? donorName;
        if (donorId != null) {
          final donor = await getUser(donorId);
          if (donor != null) {
            final firstName = donor['firstName'] ?? '';
            final lastName = donor['lastName'] ?? '';
            donorName = '$firstName $lastName'.trim();
          }
        }
        donorName ??= 'The donor';

        if (newStatus == 'approved') {
          // Notify claimant that claim was accepted
          if (claimantId != null) {
            await _db.collection('notifications').add({
              'toUserId': claimantId,
              'type': 'donation_request_decision',
              'itemTitle': itemTitle,
              'requestId': id,
              'decision': 'accepted',
              'donorName': donorName,
              'status': 'unread',
              'createdAt': FieldValue.serverTimestamp(),
            });
          }
        } else if (newStatus == 'rejected') {
          // Notify claimant that claim was rejected
          if (claimantId != null) {
            await _db.collection('notifications').add({
              'toUserId': claimantId,
              'type': 'donation_request_decision',
              'itemTitle': itemTitle,
              'requestId': id,
              'decision': 'declined',
              'donorName': donorName,
              'status': 'unread',
              'createdAt': FieldValue.serverTimestamp(),
            });
          }
        }
      } catch (_) {
        // Best-effort; don't fail the update if notification write fails
      }
    }
  }

  Future<Map<String, dynamic>?> getClaimRequest(String id) async {
    final doc = await _db.collection('giveaway_claims').doc(id).get();
    if (!doc.exists) return null;
    final data = doc.data() as Map<String, dynamic>;
    data['id'] = doc.id;
    return data;
  }

  Future<List<Map<String, dynamic>>> getClaimRequestsByClaimant(
    String claimantId,
  ) async {
    final snap = await _db
        .collection('giveaway_claims')
        .where('claimantId', isEqualTo: claimantId)
        .get();
    return snap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      return data;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getClaimRequestsByDonor(
    String donorId,
  ) async {
    final snap = await _db
        .collection('giveaway_claims')
        .where('donorId', isEqualTo: donorId)
        .get();
    return snap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      return data;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getClaimRequestsForGiveaway(
    String giveawayId,
  ) async {
    final snap = await _db
        .collection('giveaway_claims')
        .where('giveawayId', isEqualTo: giveawayId)
        .get();
    return snap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      return data;
    }).toList();
  }

  Future<bool> hasPendingClaimRequest({
    required String giveawayId,
    required String claimantId,
  }) async {
    final snap = await _db
        .collection('giveaway_claims')
        .where('giveawayId', isEqualTo: giveawayId)
        .where('claimantId', isEqualTo: claimantId)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }
}

// ---------------- RATING & FEEDBACK MODULE ----------------
extension FirestoreServiceRatings on FirestoreService {
  // Create a rating/feedback
  Future<String> createRating(Map<String, dynamic> data) async {
    final payload = Map<String, dynamic>.from(data);
    // Convert DateTime fields to Timestamps
    if (payload['createdAt'] is DateTime) {
      payload['createdAt'] = Timestamp.fromDate(payload['createdAt']);
    }
    if (payload['updatedAt'] is DateTime) {
      payload['updatedAt'] = Timestamp.fromDate(payload['updatedAt']);
    }
    final doc = await _db.collection('ratings').add(payload);
    return doc.id;
  }

  // Update a rating (if user wants to edit their feedback)
  Future<void> updateRating(String id, Map<String, dynamic> data) async {
    final payload = Map<String, dynamic>.from(data);
    if (payload['updatedAt'] is DateTime) {
      payload['updatedAt'] = Timestamp.fromDate(payload['updatedAt']);
    }
    await _db.collection('ratings').doc(id).update(payload);
  }

  // Get a specific rating
  Future<Map<String, dynamic>?> getRating(String id) async {
    final doc = await _db.collection('ratings').doc(id).get();
    if (!doc.exists) return null;
    final data = doc.data() as Map<String, dynamic>;
    data['id'] = doc.id;
    return data;
  }

  // Get all ratings for a specific user (public reviews)
  Future<List<Map<String, dynamic>>> getRatingsForUser(String userId) async {
    final snap = await _db
        .collection('ratings')
        .where('ratedUserId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .get();
    return snap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      return data;
    }).toList();
  }

  // Get ratings given by a specific user
  Future<List<Map<String, dynamic>>> getRatingsByUser(String userId) async {
    final snap = await _db
        .collection('ratings')
        .where('raterUserId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .get();
    return snap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      return data;
    }).toList();
  }

  // Check if a user has already rated another user for a specific transaction
  Future<bool> hasExistingRating({
    required String raterUserId,
    required String ratedUserId,
    String? transactionId,
  }) async {
    Query<Map<String, dynamic>> query = _db
        .collection('ratings')
        .where('raterUserId', isEqualTo: raterUserId)
        .where('ratedUserId', isEqualTo: ratedUserId);

    if (transactionId != null) {
      query = query.where('transactionId', isEqualTo: transactionId);
    }

    final snap = await query.limit(1).get();
    return snap.docs.isNotEmpty;
  }

  // Get rating for a specific transaction
  Future<Map<String, dynamic>?> getRatingForTransaction({
    required String transactionId,
    required String raterUserId,
  }) async {
    final snap = await _db
        .collection('ratings')
        .where('transactionId', isEqualTo: transactionId)
        .where('raterUserId', isEqualTo: raterUserId)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final data = snap.docs.first.data();
    data['id'] = snap.docs.first.id;
    return data;
  }

  // Calculate average rating for a user
  Future<double> calculateAverageRating(String userId) async {
    final snap = await _db
        .collection('ratings')
        .where('ratedUserId', isEqualTo: userId)
        .get();

    if (snap.docs.isEmpty) return 0.0;

    int totalRating = 0;
    for (final doc in snap.docs) {
      final rating = doc.data()['rating'] as int? ?? 5;
      totalRating += rating;
    }

    return totalRating / snap.docs.length;
  }

  // Update user's reputation score (should be called after creating/updating a rating)
  Future<void> updateUserReputationScore(String userId) async {
    final avgRating = await calculateAverageRating(userId);
    await _db.collection('users').doc(userId).update({
      'reputationScore': avgRating,
    });
  }

  // Get user activity statistics
  Future<Map<String, dynamic>> getUserActivityStats(String userId) async {
    try {
      final results = await Future.wait([
        // Items listed (active)
        _db
            .collection('items')
            .where('lenderId', isEqualTo: userId)
            .where('status', isEqualTo: 'available')
            .count()
            .get()
            .then((snap) => snap.count ?? 0)
            .catchError((_) => 0),
        // Total items listed (all time)
        _db
            .collection('items')
            .where('lenderId', isEqualTo: userId)
            .count()
            .get()
            .then((snap) => snap.count ?? 0)
            .catchError((_) => 0),
        // Items currently borrowed
        _db
            .collection('items')
            .where('status', isEqualTo: 'borrowed')
            .where('currentBorrowerId', isEqualTo: userId)
            .count()
            .get()
            .then((snap) => snap.count ?? 0)
            .catchError((_) => 0),
        // Total items borrowed (all time - count items that have been borrowed by this user)
        _db
            .collection('items')
            .where('borrowHistory', arrayContains: userId)
            .count()
            .get()
            .then((snap) => snap.count ?? 0)
            .catchError((_) {
              // Fallback: count items with currentBorrowerId or borrowHistory
              return _db
                  .collection('items')
                  .where('currentBorrowerId', isEqualTo: userId)
                  .count()
                  .get()
                  .then((snap) => snap.count ?? 0)
                  .catchError((_) => 0);
            }),
        // Trade items
        _db
            .collection('trade_items')
            .where('offeredBy', isEqualTo: userId)
            .count()
            .get()
            .then((snap) => snap.count ?? 0)
            .catchError((_) => 0),
        // Rental listings
        _db
            .collection('rental_listings')
            .where('ownerId', isEqualTo: userId)
            .count()
            .get()
            .then((snap) => snap.count ?? 0)
            .catchError((_) => 0),
        // Giveaways
        _db
            .collection('giveaways')
            .where('donorId', isEqualTo: userId)
            .count()
            .get()
            .then((snap) => snap.count ?? 0)
            .catchError((_) => 0),
      ]);

      return {
        'activeListings': results[0],
        'totalListings': results[1],
        'currentlyBorrowed': results[2],
        'totalBorrowed': results[3],
        'tradeItems': results[4],
        'rentalListings': results[5],
        'giveaways': results[6],
      };
    } catch (e) {
      debugPrint('Error getting user activity stats: $e');
      return {
        'activeListings': 0,
        'totalListings': 0,
        'currentlyBorrowed': 0,
        'totalBorrowed': 0,
        'tradeItems': 0,
        'rentalListings': 0,
        'giveaways': 0,
      };
    }
  }

  // Get user response rate and average response time from messages
  Future<Map<String, dynamic>> getUserResponseStats(String userId) async {
    try {
      // Get all conversations where user is a participant
      final conversationsSnap = await _db
          .collection('conversations')
          .where('participants', arrayContains: userId)
          .get();

      if (conversationsSnap.docs.isEmpty) {
        return {
          'responseRate': 0.0,
          'averageResponseTime': 0.0,
          'totalMessagesReceived': 0,
          'totalMessagesResponded': 0,
        };
      }

      int totalMessagesReceived = 0;
      int totalMessagesResponded = 0;
      int totalResponseTimeMinutes = 0;
      int responseCount = 0;

      // For each conversation, get messages
      for (final convDoc in conversationsSnap.docs) {
        final messagesSnap = await _db
            .collection('conversations')
            .doc(convDoc.id)
            .collection('messages')
            .orderBy('timestamp', descending: false)
            .get();

        if (messagesSnap.docs.isEmpty) continue;

        DateTime? lastOtherUserMessageTime;
        String? lastOtherUserId;

        for (final msgDoc in messagesSnap.docs) {
          final msgData = msgDoc.data();
          final msgSenderId = msgData['senderId'] as String? ?? '';
          final msgTimestamp =
              (msgData['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();

          // If message is from other user
          if (msgSenderId != userId) {
            totalMessagesReceived++;
            lastOtherUserMessageTime = msgTimestamp;
            lastOtherUserId = msgSenderId;
          }
          // If message is from this user and there was a previous message from other user
          else if (msgSenderId == userId &&
              lastOtherUserMessageTime != null &&
              lastOtherUserId != null) {
            totalMessagesResponded++;
            final responseTime = msgTimestamp.difference(
              lastOtherUserMessageTime,
            );
            totalResponseTimeMinutes += responseTime.inMinutes;
            responseCount++;
            // Reset to avoid counting multiple responses to same message
            lastOtherUserMessageTime = null;
            lastOtherUserId = null;
          }
        }
      }

      final responseRate = totalMessagesReceived > 0
          ? (totalMessagesResponded / totalMessagesReceived) * 100
          : 0.0;

      final averageResponseTime = responseCount > 0
          ? totalResponseTimeMinutes / responseCount
          : 0.0;

      return {
        'responseRate': responseRate,
        'averageResponseTime': averageResponseTime,
        'totalMessagesReceived': totalMessagesReceived,
        'totalMessagesResponded': totalMessagesResponded,
      };
    } catch (e) {
      debugPrint('Error getting user response stats: $e');
      return {
        'responseRate': 0.0,
        'averageResponseTime': 0.0,
        'totalMessagesReceived': 0,
        'totalMessagesResponded': 0,
      };
    }
  }
}

// ---------------- CALAMITY DONATION MODULE ----------------
extension FirestoreServiceCalamity on FirestoreService {
  // Calamity Event operations
  Future<String> createCalamityEvent(Map<String, dynamic> data) async {
    final payload = Map<String, dynamic>.from(data);
    // Convert DateTime fields to Timestamps
    if (payload['deadline'] is DateTime) {
      payload['deadline'] = Timestamp.fromDate(payload['deadline']);
    }
    if (payload['createdAt'] is DateTime) {
      payload['createdAt'] = Timestamp.fromDate(payload['createdAt']);
    }
    if (payload['updatedAt'] is DateTime) {
      payload['updatedAt'] = Timestamp.fromDate(payload['updatedAt']);
    }
    // FieldValue.serverTimestamp() will pass through as-is
    final doc = await _db.collection('calamity_events').add(payload);

    // Send notification to all verified users about the new calamity event
    try {
      final eventTitle = payload['title'] as String? ?? 'New Calamity Event';
      final eventId = doc.id;
      await sendCalamityEventNotification(
        eventId: eventId,
        eventTitle: eventTitle,
        calamityType: payload['calamityType'] as String?,
      );
    } catch (_) {
      // Best-effort; don't fail event creation if notification write fails
    }

    return doc.id;
  }

  Future<void> updateCalamityEvent(String id, Map<String, dynamic> data) async {
    final payload = Map<String, dynamic>.from(data);
    // Convert DateTime fields to Timestamps
    if (payload['deadline'] is DateTime) {
      payload['deadline'] = Timestamp.fromDate(payload['deadline']);
    }
    if (payload['updatedAt'] is DateTime) {
      payload['updatedAt'] = Timestamp.fromDate(payload['updatedAt']);
    }
    await _db.collection('calamity_events').doc(id).update(payload);
  }

  Future<Map<String, dynamic>?> getCalamityEvent(String id) async {
    final doc = await _db.collection('calamity_events').doc(id).get();
    if (!doc.exists) return null;
    final data = doc.data() as Map<String, dynamic>;
    data['id'] = doc.id;
    return data;
  }

  Future<List<Map<String, dynamic>>> getAllCalamityEvents() async {
    final snap = await _db
        .collection('calamity_events')
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      return data;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getActiveCalamityEvents() async {
    final snap = await _db
        .collection('calamity_events')
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      return data;
    }).toList();
  }

  Future<void> deleteCalamityEvent(String id) async {
    await _db.collection('calamity_events').doc(id).delete();
  }

  // Calamity Donation operations
  Future<String> createCalamityDonation(Map<String, dynamic> data) async {
    final payload = Map<String, dynamic>.from(data);
    // Convert DateTime fields to Timestamps
    if (payload['createdAt'] is DateTime) {
      payload['createdAt'] = Timestamp.fromDate(payload['createdAt']);
    }
    if (payload['updatedAt'] is DateTime) {
      payload['updatedAt'] = Timestamp.fromDate(payload['updatedAt']);
    }
    // FieldValue.serverTimestamp() will pass through as-is
    final doc = await _db.collection('calamity_donations').add(payload);
    return doc.id;
  }

  Future<void> updateCalamityDonation(
    String id,
    Map<String, dynamic> data,
  ) async {
    final payload = Map<String, dynamic>.from(data);
    // Convert DateTime fields to Timestamps
    if (payload['updatedAt'] is DateTime) {
      payload['updatedAt'] = Timestamp.fromDate(payload['updatedAt']);
    }
    await _db.collection('calamity_donations').doc(id).update(payload);
  }

  Future<Map<String, dynamic>?> getCalamityDonation(String id) async {
    final doc = await _db.collection('calamity_donations').doc(id).get();
    if (!doc.exists) return null;
    final data = doc.data() as Map<String, dynamic>;
    data['id'] = doc.id;
    return data;
  }

  Future<List<Map<String, dynamic>>> getDonationsByEvent(String eventId) async {
    final snap = await _db
        .collection('calamity_donations')
        .where('eventId', isEqualTo: eventId)
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      return data;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getDonationsByDonor(
    String donorEmail,
  ) async {
    final snap = await _db
        .collection('calamity_donations')
        .where('donorEmail', isEqualTo: donorEmail)
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      return data;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getAllCalamityDonations() async {
    final snap = await _db
        .collection('calamity_donations')
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map((d) {
      final data = d.data();
      data['id'] = d.id;
      return data;
    }).toList();
  }

  Future<int> getDonationCountByEvent(String eventId) async {
    try {
      final snap = await _db
          .collection('calamity_donations')
          .where('eventId', isEqualTo: eventId)
          .where('status', isEqualTo: 'received')
          .get();
      return snap.docs.length;
    } catch (e) {
      return 0;
    }
  }

  /// Get unique donors count for a specific event
  Future<int> getUniqueDonorsCountByEvent(String eventId) async {
    try {
      final snap = await _db
          .collection('calamity_donations')
          .where('eventId', isEqualTo: eventId)
          .get();
      final uniqueDonors = <String>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final donorEmail = data['donorEmail'];
        if (donorEmail != null &&
            donorEmail is String &&
            donorEmail.isNotEmpty) {
          uniqueDonors.add(donorEmail);
        }
      }
      return uniqueDonors.length;
    } catch (e) {
      return 0;
    }
  }

  /// Get unique donors count across all events
  Future<int> getTotalUniqueDonorsCount() async {
    try {
      final snap = await _db.collection('calamity_donations').get();
      final uniqueDonors = <String>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final donorEmail = data['donorEmail'];
        if (donorEmail != null &&
            donorEmail is String &&
            donorEmail.isNotEmpty) {
          uniqueDonors.add(donorEmail);
        }
      }
      return uniqueDonors.length;
    } catch (e) {
      return 0;
    }
  }

  Future<void> sendCalamityDonationNotification({
    required String eventId,
    required String donationId,
    required String donorEmail,
    String? donorName,
    required String itemType,
    required int quantity,
  }) async {
    try {
      // Get event details
      final event = await getCalamityEvent(eventId);
      if (event == null) return;

      final eventTitle = event['title'] as String? ?? 'Calamity Event';

      // Find admin users (users with isAdmin = true)
      final adminUsers = await _db
          .collection('users')
          .where('isAdmin', isEqualTo: true)
          .get();

      // Send notification to each admin
      for (final adminDoc in adminUsers.docs) {
        final adminId = adminDoc.id;
        await _db.collection('notifications').add({
          'toUserId': adminId,
          'type': 'calamity_donation',
          'eventId': eventId,
          'eventTitle': eventTitle,
          'donationId': donationId,
          'donorEmail': donorEmail,
          'donorName': donorName,
          'itemType': itemType,
          'quantity': quantity,
          'status': 'unread',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (_) {
      // Best-effort; don't fail if notification write fails
    }
  }

  /// Send notification to all verified users when a new calamity event is created
  Future<void> sendCalamityEventNotification({
    required String eventId,
    required String eventTitle,
    String? calamityType,
  }) async {
    try {
      // Find all verified users (users with isVerified = true)
      final verifiedUsers = await _db
          .collection('users')
          .where('isVerified', isEqualTo: true)
          .get();

      // Send notification to each verified user
      for (final userDoc in verifiedUsers.docs) {
        final userId = userDoc.id;
        await _db.collection('notifications').add({
          'toUserId': userId,
          'type': 'calamity_event_created',
          'eventId': eventId,
          'eventTitle': eventTitle,
          'calamityType': calamityType,
          'status': 'unread',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (_) {
      // Best-effort; don't fail if notification write fails
    }
  }

  // ============================================================================
  // Activity Logs Management
  // ============================================================================

  /// Create an activity log entry
  Future<String?> createActivityLog({
    required String category, // user, transaction, content, admin, system
    required String action,
    required String actorId,
    required String actorName,
    String? targetId,
    String? targetType,
    required String description,
    Map<String, dynamic>? metadata,
    String severity = 'info', // info, warning, critical
  }) async {
    try {
      final logData = {
        'timestamp': FieldValue.serverTimestamp(),
        'category': category,
        'action': action,
        'actorId': actorId,
        'actorName': actorName,
        'targetId': targetId,
        'targetType': targetType,
        'description': description,
        'metadata': metadata ?? {},
        'severity': severity,
      };

      final docRef = await _db.collection('activity_logs').add(logData);
      return docRef.id;
    } catch (e) {
      debugPrint('Error creating activity log: $e');
      return null;
    }
  }

  /// Get activity logs stream with optional filters
  Stream<QuerySnapshot<Map<String, dynamic>>> getActivityLogsStream({
    String? category,
    String? severity,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 50,
  }) {
    Query<Map<String, dynamic>> query = _db.collection('activity_logs');

    // Apply equality filters first (category, severity)
    // Note: Firestore requires composite indexes for multiple where clauses with orderBy
    if (category != null && category != 'all') {
      query = query.where('category', isEqualTo: category);
    }
    if (severity != null && severity != 'all') {
      query = query.where('severity', isEqualTo: severity);
    }

    // Handle date range: Firestore allows only one range query per query
    // If both startDate and endDate are provided, we use a range query
    if (startDate != null && endDate != null) {
      query = query
          .where(
            'timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
          )
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(endDate));
    } else if (startDate != null) {
      query = query.where(
        'timestamp',
        isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
      );
    } else if (endDate != null) {
      query = query.where(
        'timestamp',
        isLessThanOrEqualTo: Timestamp.fromDate(endDate),
      );
    }

    // Order by timestamp (must be last in composite index)
    return query
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots();
  }

  /// Search activity logs by text (searches in description and action fields)
  Future<List<Map<String, dynamic>>> searchActivityLogs({
    required String searchText,
    int limit = 50,
  }) async {
    try {
      // Note: This is a simple implementation. For production,
      // consider using Algolia or similar for full-text search
      final snapshot = await _db
          .collection('activity_logs')
          .orderBy('timestamp', descending: true)
          .limit(limit * 2)
          .get();

      final searchLower = searchText.toLowerCase();
      final results = <Map<String, dynamic>>[];

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final description = (data['description'] ?? '')
            .toString()
            .toLowerCase();
        final action = (data['action'] ?? '').toString().toLowerCase();
        final actorName = (data['actorName'] ?? '').toString().toLowerCase();

        if (description.contains(searchLower) ||
            action.contains(searchLower) ||
            actorName.contains(searchLower)) {
          data['id'] = doc.id;
          results.add(data);
          if (results.length >= limit) break;
        }
      }

      return results;
    } catch (e) {
      debugPrint('Error searching activity logs: $e');
      return [];
    }
  }

  /// Get activity log statistics for dashboard
  Future<Map<String, int>> getActivityLogStats({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _db.collection('activity_logs');

      if (startDate != null) {
        query = query.where(
          'timestamp',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startDate),
        );
      }
      if (endDate != null) {
        query = query.where(
          'timestamp',
          isLessThanOrEqualTo: Timestamp.fromDate(endDate),
        );
      }

      final snapshot = await query.get();
      final stats = <String, int>{
        'total': snapshot.docs.length,
        'user': 0,
        'transaction': 0,
        'content': 0,
        'admin': 0,
        'system': 0,
        'info': 0,
        'warning': 0,
        'critical': 0,
      };

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final category = (data['category'] ?? '').toString();
        final severity = (data['severity'] ?? '').toString();

        if (stats.containsKey(category)) {
          stats[category] = (stats[category] ?? 0) + 1;
        }
        if (stats.containsKey(severity)) {
          stats[severity] = (stats[severity] ?? 0) + 1;
        }
      }

      return stats;
    } catch (e) {
      debugPrint('Error getting activity log stats: $e');
      return {};
    }
  }

  /// Delete old activity logs (cleanup utility)
  /// Deletes logs older than the specified number of days
  Future<int> deleteOldActivityLogs({int daysToKeep = 90}) async {
    try {
      final cutoffDate = DateTime.now().subtract(Duration(days: daysToKeep));
      final snapshot = await _db
          .collection('activity_logs')
          .where('timestamp', isLessThan: Timestamp.fromDate(cutoffDate))
          .limit(500)
          .get();

      final batch = _db.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
      return snapshot.docs.length;
    } catch (e) {
      debugPrint('Error deleting old activity logs: $e');
      return 0;
    }
  }
}
