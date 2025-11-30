import 'dart:io';
import 'dart:async';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:developer';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  StorageService() {
    // Make uploads resilient, especially on web where first-time cold starts are slower
    _storage.setMaxOperationRetryTime(const Duration(minutes: 5));
    _storage.setMaxUploadRetryTime(const Duration(minutes: 5));
    _storage.setMaxDownloadRetryTime(const Duration(minutes: 5));
  }

  Future<String> uploadBarangayIdImage({
    required dynamic
    file, // Changed from File to dynamic to support both File and XFile
    required String userHint,
    bool isFront = true,
  }) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final side = isFront ? 'front' : 'back';
      final ref = _storage
          .ref()
          .child('users')
          .child(userHint)
          .child('barangay_ids')
          .child('id_${side}_$timestamp.jpg');

      const int maxAttempts = 3;
      for (int attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          UploadTask uploadTask;

          if (kIsWeb) {
            if (file is XFile) {
              log('Reading image bytes for web upload...');
              final bytes = await file.readAsBytes();
              log('Image size: ${bytes.length} bytes');
              uploadTask = ref.putData(
                bytes,
                SettableMetadata(
                  contentType: 'image/jpeg',
                  cacheControl: 'public, max-age=31536000, immutable',
                ),
              );
            } else {
              throw Exception('Invalid file type for web platform');
            }
          } else {
            // Mobile platform - handle both XFile and File
            if (file is XFile) {
              // XFile is returned by ImagePicker on mobile in newer versions
              final bytes = await file.readAsBytes();
              log('📦 ID Image size: ${bytes.length} bytes');
              // Basic content type detection
              String contentType = 'image/jpeg';
              if (bytes.length >= 4) {
                if (bytes[0] == 0x89 &&
                    bytes[1] == 0x50 &&
                    bytes[2] == 0x4E &&
                    bytes[3] == 0x47) {
                  contentType = 'image/png';
                } else if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
                  contentType = 'image/jpeg';
                } else if (bytes[0] == 0x52 &&
                    bytes[1] == 0x49 &&
                    bytes[2] == 0x46 &&
                    bytes[3] == 0x46) {
                  contentType = 'image/webp';
                }
              }
              log('📸 Detected ID image format: $contentType');
              uploadTask = ref.putData(
                bytes,
                SettableMetadata(
                  contentType: contentType,
                  cacheControl: 'public, max-age=31536000, immutable',
                ),
              );
            } else if (file is File) {
              // Legacy File support for backward compatibility
              uploadTask = ref.putFile(
                file,
                SettableMetadata(
                  contentType: 'image/jpeg',
                  cacheControl: 'public, max-age=31536000, immutable',
                ),
              );
            } else {
              throw Exception(
                'Invalid file type for mobile platform. Expected XFile or File, got ${file.runtimeType}',
              );
            }
          }

          final snapshot = await uploadTask.timeout(
            const Duration(seconds: 120),
            onTimeout: () {
              throw Exception(
                'Upload timeout - please try again with a smaller image',
              );
            },
          );

          return await snapshot.ref.getDownloadURL();
        } catch (e) {
          if (attempt == maxAttempts) rethrow;
          log('⚠️ Upload attempt $attempt failed, retrying... Error: $e');
          await Future.delayed(Duration(milliseconds: 400 * attempt));
        }
      }

      throw Exception('Unexpected upload failure');
    } catch (e) {
      throw Exception('Failed to upload image: $e');
    }
  }

  /// Generate storage path for listing images
  /// Structure: listings/{type}/{userId}/{itemId}/image_{timestamp}.{ext}
  String _getListingImagePath({
    required String listingType, // 'borrow', 'rent', 'trade', 'donate'
    required String userId,
    required String itemId,
    String? fileExtension,
  }) {
    final ext = fileExtension ?? 'jpg';
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'listings/$listingType/$userId/$itemId/image_$timestamp.$ext';
  }

  /// Upload image for borrow/lend/donate items
  /// Path: listings/borrow/{userId}/{itemId}/image_{timestamp}.jpg
  /// or: listings/donate/{userId}/{itemId}/image_{timestamp}.jpg
  Future<String> uploadItemImage({
    required dynamic file, // Supports both File and XFile
    required String itemId,
    required String userId,
    required String listingType, // 'borrow' (lend), 'donate'
  }) async {
    try {
      // Normalize listing type
      final normalizedType = listingType.toLowerCase();
      if (normalizedType == 'lend') {
        // Map 'lend' to 'borrow' for consistency
        listingType = 'borrow';
      } else {
        listingType = normalizedType;
      }

      // Detect file extension from file
      String? fileExtension;
      if (file is XFile) {
        final fileName = file.name;
        if (fileName.contains('.')) {
          fileExtension = fileName.split('.').last.toLowerCase();
        }
      }

      final imagePath = _getListingImagePath(
        listingType: listingType,
        userId: userId,
        itemId: itemId,
        fileExtension: fileExtension,
      );

      final ref = _storage.ref().child(imagePath);
      log('📤 Uploading image to: $imagePath');

      const int maxAttempts = 3;
      for (int attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          UploadTask uploadTask;

          if (kIsWeb) {
            if (file is XFile) {
              final bytes = await file.readAsBytes();
              log('📦 Image size: ${bytes.length} bytes');
              // Basic content type detection
              String contentType = 'image/jpeg';
              if (bytes.length >= 4) {
                if (bytes[0] == 0x89 &&
                    bytes[1] == 0x50 &&
                    bytes[2] == 0x4E &&
                    bytes[3] == 0x47) {
                  contentType = 'image/png';
                } else if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
                  contentType = 'image/jpeg';
                } else if (bytes[0] == 0x52 &&
                    bytes[1] == 0x49 &&
                    bytes[2] == 0x46 &&
                    bytes[3] == 0x46) {
                  contentType = 'image/webp';
                }
              }
              log('📸 Detected image format: $contentType');
              uploadTask = ref.putData(
                bytes,
                SettableMetadata(
                  contentType: contentType,
                  cacheControl: 'public, max-age=31536000, immutable',
                ),
              );
            } else {
              throw Exception('Invalid file type for web platform');
            }
          } else {
            // Mobile platform - handle both XFile and File
            if (file is XFile) {
              // XFile is returned by ImagePicker on mobile in newer versions
              final bytes = await file.readAsBytes();
              log('📦 Image size: ${bytes.length} bytes');
              // Basic content type detection
              String contentType = 'image/jpeg';
              if (bytes.length >= 4) {
                if (bytes[0] == 0x89 &&
                    bytes[1] == 0x50 &&
                    bytes[2] == 0x4E &&
                    bytes[3] == 0x47) {
                  contentType = 'image/png';
                } else if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
                  contentType = 'image/jpeg';
                } else if (bytes[0] == 0x52 &&
                    bytes[1] == 0x49 &&
                    bytes[2] == 0x46 &&
                    bytes[3] == 0x46) {
                  contentType = 'image/webp';
                }
              }
              log('📸 Detected image format: $contentType');
              uploadTask = ref.putData(
                bytes,
                SettableMetadata(
                  contentType: contentType,
                  cacheControl: 'public, max-age=31536000, immutable',
                ),
              );
            } else if (file is File) {
              // Legacy File support for backward compatibility
              // Read first few bytes to detect format
              final bytes = await file.readAsBytes();
              String contentType = 'image/jpeg';
              if (bytes.length >= 4) {
                if (bytes[0] == 0x89 &&
                    bytes[1] == 0x50 &&
                    bytes[2] == 0x4E &&
                    bytes[3] == 0x47) {
                  contentType = 'image/png';
                } else if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
                  contentType = 'image/jpeg';
                } else if (bytes[0] == 0x52 &&
                    bytes[1] == 0x49 &&
                    bytes[2] == 0x46 &&
                    bytes[3] == 0x46) {
                  contentType = 'image/webp';
                }
              }
              log('📸 Detected image format: $contentType');
              uploadTask = ref.putFile(
                file,
                SettableMetadata(
                  contentType: contentType,
                  cacheControl: 'public, max-age=31536000, immutable',
                ),
              );
            } else {
              throw Exception(
                'Invalid file type for mobile platform. Expected XFile or File, got ${file.runtimeType}',
              );
            }
          }

          final snapshot = await uploadTask.timeout(
            const Duration(seconds: 240),
            onTimeout: () {
              log('❌ Upload timeout');
              throw Exception('Upload timeout - please try again');
            },
          );

          final downloadUrl = await snapshot.ref.getDownloadURL();
          log('✅ Upload successful! URL: $downloadUrl');

          // Best-effort metadata logging
          try {
            final metadata = await snapshot.ref.getMetadata();
            log('📊 Upload metadata:');
            log('   - Content Type: ${metadata.contentType}');
            log('   - Size: ${metadata.size} bytes');
            log('   - Cache Control: ${metadata.cacheControl}');
          } catch (e) {
            log('⚠️ Could not get metadata: $e');
          }

          return downloadUrl;
        } catch (e) {
          if (attempt == maxAttempts) {
            log('❌ Failed to upload item image after $attempt attempts: $e');
            rethrow;
          }
          log('⚠️ Upload attempt $attempt failed, retrying... Error: $e');
          await Future.delayed(Duration(milliseconds: 400 * attempt));
        }
      }

      throw Exception('Unexpected upload failure');
    } catch (e) {
      throw Exception('Failed to upload item image: $e');
    }
  }

  /// Upload already-prepared bytes (e.g., compressed image) for borrow/lend/donate
  /// Path: listings/{type}/{userId}/{itemId}/image_{timestamp}.{ext}
  Future<String> uploadItemImageBytes({
    required Uint8List bytes,
    required String itemId,
    required String userId,
    required String listingType, // 'borrow' (lend), 'donate'
    String contentType = 'image/jpeg',
    String? cacheControl,
  }) async {
    try {
      // Normalize listing type
      final normalizedType = listingType.toLowerCase();
      final type = normalizedType == 'lend' ? 'borrow' : normalizedType;

      // Detect file extension from content type
      String fileExtension = 'jpg';
      if (contentType.contains('png')) {
        fileExtension = 'png';
      } else if (contentType.contains('webp')) {
        fileExtension = 'webp';
      }

      final imagePath = _getListingImagePath(
        listingType: type,
        userId: userId,
        itemId: itemId,
        fileExtension: fileExtension,
      );

      final ref = _storage.ref().child(imagePath);
      log('📤 Uploading compressed image to: $imagePath');
      log('📦 Compressed size: ${bytes.length} bytes');

      const int maxAttempts = 3;
      for (int attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          final uploadTask = ref.putData(
            bytes,
            SettableMetadata(
              contentType: contentType,
              cacheControl:
                  cacheControl ?? 'public, max-age=31536000, immutable',
            ),
          );

          // Robust completion using snapshotEvents + manual cancel on timeout
          final completer = Completer<TaskSnapshot>();
          late final StreamSubscription<TaskSnapshot> sub;
          Timer? timer;
          timer = Timer(const Duration(seconds: 240), () async {
            try {
              await sub.cancel();
            } catch (_) {}
            try {
              await uploadTask.cancel();
            } catch (_) {}
            if (!completer.isCompleted) {
              completer.completeError(TimeoutException('Upload timed out'));
            }
          });

          sub = uploadTask.snapshotEvents.listen(
            (event) {
              // Log state transitions for debugging
              debugPrint(
                '⏫ Upload state: ${event.state} (${event.bytesTransferred}/${event.totalBytes})',
              );
              if (event.state == TaskState.success) {
                if (!completer.isCompleted) completer.complete(event);
              } else if (event.state == TaskState.error ||
                  event.state == TaskState.canceled) {
                if (!completer.isCompleted) {
                  completer.completeError(
                    Exception('Upload ${event.state.name}'),
                  );
                }
              }
            },
            onError: (e) {
              if (!completer.isCompleted) completer.completeError(e);
            },
          );

          final snapshot = await completer.future;
          await sub.cancel();
          timer.cancel();

          // Give Storage a moment to propagate (helps on web)
          await Future.delayed(const Duration(milliseconds: 800));
          final downloadUrl = await snapshot.ref.getDownloadURL();
          debugPrint('✅ Upload successful! URL: $downloadUrl');
          return downloadUrl;
        } catch (e) {
          if (attempt == maxAttempts) rethrow;
          debugPrint(
            '⚠️ Upload attempt $attempt failed, retrying... Error: $e',
          );
          await Future.delayed(Duration(milliseconds: 400 * attempt));
        }
      }

      throw Exception('Unexpected upload failure');
    } catch (e) {
      throw Exception('Failed to upload item image: $e');
    }
  }

  Future<String> uploadProfilePhoto({
    required dynamic file,
    required String userId,
  }) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ref = _storage
          .ref()
          .child('users')
          .child(userId)
          .child('profile')
          .child('profile_$timestamp.jpg');

      UploadTask uploadTask;
      if (kIsWeb) {
        if (file is XFile) {
          final bytes = await file.readAsBytes();
          uploadTask = ref.putData(
            bytes,
            SettableMetadata(
              contentType: 'image/jpeg',
              cacheControl: 'public, max-age=31536000, immutable',
            ),
          );
        } else {
          throw Exception('Invalid file type for web platform');
        }
      } else {
        // Mobile platform - handle both XFile and File
        if (file is XFile) {
          // XFile is returned by ImagePicker on mobile in newer versions
          final bytes = await file.readAsBytes();
          log('📦 Profile image size: ${bytes.length} bytes');
          // Basic content type detection
          String contentType = 'image/jpeg';
          if (bytes.length >= 4) {
            if (bytes[0] == 0x89 &&
                bytes[1] == 0x50 &&
                bytes[2] == 0x4E &&
                bytes[3] == 0x47) {
              contentType = 'image/png';
            } else if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
              contentType = 'image/jpeg';
            } else if (bytes[0] == 0x52 &&
                bytes[1] == 0x49 &&
                bytes[2] == 0x46 &&
                bytes[3] == 0x46) {
              contentType = 'image/webp';
            }
          }
          log('📸 Detected profile image format: $contentType');
          uploadTask = ref.putData(
            bytes,
            SettableMetadata(
              contentType: contentType,
              cacheControl: 'public, max-age=31536000, immutable',
            ),
          );
        } else if (file is File) {
          // Legacy File support for backward compatibility
          uploadTask = ref.putFile(
            file,
            SettableMetadata(
              contentType: 'image/jpeg',
              cacheControl: 'public, max-age=31536000, immutable',
            ),
          );
        } else {
          throw Exception(
            'Invalid file type for mobile platform. Expected XFile or File, got ${file.runtimeType}',
          );
        }
      }

      final snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      throw Exception('Failed to upload profile photo: $e');
    }
  }

  /// Upload condition verification photo for borrow returns
  /// Path: condition_photos/{requestId}/{userId}/photo_{timestamp}.jpg
  Future<String> uploadConditionPhoto({
    required dynamic file, // Supports both File and XFile
    required String requestId,
    required String userId,
  }) async {
    try {
      // Detect file extension from file
      String? fileExtension = 'jpg';
      if (file is XFile) {
        final fileName = file.name;
        if (fileName.contains('.')) {
          fileExtension = fileName.split('.').last.toLowerCase();
        }
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final imagePath =
          'condition_photos/$requestId/$userId/photo_$timestamp.$fileExtension';

      final ref = _storage.ref().child(imagePath);
      log('📤 Uploading condition photo to: $imagePath');

      const int maxAttempts = 3;
      for (int attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          UploadTask uploadTask;

          if (kIsWeb) {
            if (file is XFile) {
              log('Reading condition photo bytes for web upload...');
              final bytes = await file.readAsBytes();
              log('Condition photo size: ${bytes.length} bytes');
              // Basic content type detection
              String contentType = 'image/jpeg';
              if (bytes.length >= 4) {
                if (bytes[0] == 0x89 &&
                    bytes[1] == 0x50 &&
                    bytes[2] == 0x4E &&
                    bytes[3] == 0x47) {
                  contentType = 'image/png';
                } else if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
                  contentType = 'image/jpeg';
                } else if (bytes[0] == 0x52 &&
                    bytes[1] == 0x49 &&
                    bytes[2] == 0x46 &&
                    bytes[3] == 0x46) {
                  contentType = 'image/webp';
                }
              }
              uploadTask = ref.putData(
                bytes,
                SettableMetadata(
                  contentType: contentType,
                  cacheControl: 'public, max-age=31536000, immutable',
                ),
              );
            } else {
              throw Exception('Invalid file type for web platform');
            }
          } else {
            // Mobile platform
            if (file is XFile) {
              final bytes = await file.readAsBytes();
              log('📦 Condition photo size: ${bytes.length} bytes');
              // Basic content type detection
              String contentType = 'image/jpeg';
              if (bytes.length >= 4) {
                if (bytes[0] == 0x89 &&
                    bytes[1] == 0x50 &&
                    bytes[2] == 0x4E &&
                    bytes[3] == 0x47) {
                  contentType = 'image/png';
                } else if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
                  contentType = 'image/jpeg';
                } else if (bytes[0] == 0x52 &&
                    bytes[1] == 0x49 &&
                    bytes[2] == 0x46 &&
                    bytes[3] == 0x46) {
                  contentType = 'image/webp';
                }
              }
              log('📸 Detected condition photo format: $contentType');
              uploadTask = ref.putData(
                bytes,
                SettableMetadata(
                  contentType: contentType,
                  cacheControl: 'public, max-age=31536000, immutable',
                ),
              );
            } else if (file is File) {
              uploadTask = ref.putFile(
                file,
                SettableMetadata(
                  contentType: 'image/jpeg',
                  cacheControl: 'public, max-age=31536000, immutable',
                ),
              );
            } else {
              throw Exception(
                'Invalid file type for mobile platform. Expected XFile or File, got ${file.runtimeType}',
              );
            }
          }

          final snapshot = await uploadTask;
          final downloadUrl = await snapshot.ref.getDownloadURL();
          log('✅ Condition photo uploaded successfully: $downloadUrl');
          return downloadUrl;
        } catch (e) {
          log('⚠️ Upload attempt $attempt failed: $e');
          if (attempt == maxAttempts) {
            rethrow;
          }
          // Wait before retry (exponential backoff)
          await Future.delayed(Duration(seconds: attempt * 2));
        }
      }

      throw Exception(
        'Failed to upload condition photo after $maxAttempts attempts',
      );
    } catch (e) {
      log('❌ Error uploading condition photo: $e');
      throw Exception('Failed to upload condition photo: $e');
    }
  }

  // Quick connectivity probe: attempts a tiny upload to verify Storage reachability
  Future<bool> probeStorageConnection() async {
    try {
      final ref = _storage
          .ref()
          .child('probes')
          .child('ping_${DateTime.now().millisecondsSinceEpoch}.txt');
      final data = Uint8List.fromList('ok'.codeUnits);
      final task = ref.putData(
        data,
        SettableMetadata(contentType: 'text/plain', cacheControl: 'no-cache'),
      );
      final completer = Completer<void>();
      late final StreamSubscription<TaskSnapshot> sub;
      Timer? timer;
      timer = Timer(const Duration(seconds: 10), () async {
        try {
          await sub.cancel();
        } catch (_) {}
        try {
          await task.cancel();
        } catch (_) {}
        if (!completer.isCompleted) {
          completer.completeError(TimeoutException('probe-timeout'));
        }
      });
      sub = task.snapshotEvents.listen(
        (snap) {
          if (snap.state == TaskState.success) {
            if (!completer.isCompleted) completer.complete();
          } else if (snap.state == TaskState.error ||
              snap.state == TaskState.canceled) {
            if (!completer.isCompleted) {
              completer.completeError(Exception('probe-${snap.state.name}'));
            }
          }
        },
        onError: (e) {
          if (!completer.isCompleted) completer.completeError(e);
        },
      );
      await completer.future;
      await sub.cancel();
      timer.cancel();
      return true;
    } catch (e) {
      debugPrint('❌ Storage probe failed: $e');
      return false;
    }
  }

  // Detailed probe that returns an error message if unreachable; null if OK
  Future<String?> probeStorageDetailed() async {
    try {
      final ref = _storage
          .ref()
          .child('probes')
          .child('ping_${DateTime.now().millisecondsSinceEpoch}.txt');
      final data = Uint8List.fromList('ok'.codeUnits);
      final task = ref.putData(
        data,
        SettableMetadata(contentType: 'text/plain', cacheControl: 'no-cache'),
      );

      final completer = Completer<void>();
      late final StreamSubscription<TaskSnapshot> sub;
      Timer? timer;
      timer = Timer(const Duration(seconds: 12), () async {
        try {
          await sub.cancel();
        } catch (_) {}
        try {
          await task.cancel();
        } catch (_) {}
        if (!completer.isCompleted) {
          completer.completeError(TimeoutException('timeout'));
        }
      });

      sub = task.snapshotEvents.listen(
        (snap) {
          if (snap.state == TaskState.success) {
            if (!completer.isCompleted) completer.complete();
          } else if (snap.state == TaskState.error ||
              snap.state == TaskState.canceled) {
            if (!completer.isCompleted) {
              completer.completeError(Exception('state-${snap.state.name}'));
            }
          }
        },
        onError: (e) {
          if (!completer.isCompleted) completer.completeError(e);
        },
      );

      await completer.future;
      await sub.cancel();
      timer.cancel();
      return null; // OK
    } catch (e) {
      String message = e.toString();
      if (e is FirebaseException) {
        message = 'FirebaseException(${e.code}): ${e.message ?? 'unknown'}';
      } else if (e is TimeoutException) {
        message = 'Timeout: ${e.message ?? 'upload timed out'}';
      }
      return message;
    }
  }

  /// Get the public download URL for a file in Firebase Storage
  /// Example: getDownloadUrl('platformqrCodes') for a file at root
  /// Or: getDownloadUrl('platform/gcash-qr.png') for nested paths
  Future<String> getDownloadUrl(String filePath) async {
    try {
      final ref = _storage.ref().child(filePath);
      return await ref.getDownloadURL();
    } catch (e) {
      throw Exception('Failed to get download URL for $filePath: $e');
    }
  }

  /// Delete images from Firebase Storage using their download URLs
  /// Extracts the storage path from the URL and deletes the file
  Future<void> deleteImages(List<String> imageUrls) async {
    if (imageUrls.isEmpty) return;

    for (final url in imageUrls) {
      if (url.isEmpty) continue;

      try {
        // Extract the storage path from the Firebase Storage URL
        // URL format: https://firebasestorage.googleapis.com/v0/b/{bucket}/o/{path}?alt=media&token={token}
        // Or: https://{bucket}.firebasestorage.app/{path}?alt=media&token={token}
        final uri = Uri.parse(url);
        String? storagePath;

        // Try new format first: {bucket}.firebasestorage.app/{path}
        if (uri.host.contains('firebasestorage.app')) {
          // Path is in the pathSegments, need to join them
          if (uri.pathSegments.isNotEmpty) {
            storagePath = uri.pathSegments.join('/');
          }
        } else {
          // Old format: firebasestorage.googleapis.com/v0/b/{bucket}/o/{path}
          final pathSegments = uri.pathSegments;
          final oIndex = pathSegments.indexOf('o');
          if (oIndex != -1 && oIndex + 1 < pathSegments.length) {
            // The path might be split across multiple segments or be URL-encoded
            // Join all segments after 'o' and decode
            final encodedPath = pathSegments.sublist(oIndex + 1).join('/');
            storagePath = Uri.decodeComponent(encodedPath);
          }
        }

        if (storagePath != null && storagePath.isNotEmpty) {
          // Create a reference to the file and delete it
          final ref = _storage.ref().child(storagePath);
          await ref.delete();
          log('✅ Deleted image: $storagePath');
        } else {
          log('⚠️ Could not extract storage path from URL: $url');
        }
      } catch (e) {
        // Log but continue - don't fail the entire operation if one image fails
        log('❌ Failed to delete image $url: $e');
      }
    }
  }

  /// Delete a single image from Firebase Storage using its download URL
  Future<void> deleteImage(String imageUrl) async {
    await deleteImages([imageUrl]);
  }

  /// Upload image for rental listings
  /// Path: listings/rent/{userId}/{listingId}/image_{timestamp}.{ext}
  Future<String> uploadRentalImage({
    required dynamic file,
    required String listingId,
    required String userId,
  }) async {
    return uploadItemImage(
      file: file,
      itemId: listingId,
      userId: userId,
      listingType: 'rent',
    );
  }

  /// Upload image for trade items
  /// Path: listings/trade/{userId}/{itemId}/image_{timestamp}.{ext}
  Future<String> uploadTradeImage({
    required dynamic file,
    required String itemId,
    required String userId,
  }) async {
    return uploadItemImage(
      file: file,
      itemId: itemId,
      userId: userId,
      listingType: 'trade',
    );
  }

  /// Upload compressed bytes for rental listings
  Future<String> uploadRentalImageBytes({
    required Uint8List bytes,
    required String listingId,
    required String userId,
    String contentType = 'image/jpeg',
    String? cacheControl,
  }) async {
    return uploadItemImageBytes(
      bytes: bytes,
      itemId: listingId,
      userId: userId,
      listingType: 'rent',
      contentType: contentType,
      cacheControl: cacheControl,
    );
  }

  /// Upload compressed bytes for trade items
  Future<String> uploadTradeImageBytes({
    required Uint8List bytes,
    required String itemId,
    required String userId,
    String contentType = 'image/jpeg',
    String? cacheControl,
  }) async {
    return uploadItemImageBytes(
      bytes: bytes,
      itemId: itemId,
      userId: userId,
      listingType: 'trade',
      contentType: contentType,
      cacheControl: cacheControl,
    );
  }
}
