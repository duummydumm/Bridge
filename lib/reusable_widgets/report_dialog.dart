import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/storage_service.dart';

/// Reusable report dialog widget with image upload functionality
class ReportDialog {
  static final StorageService _storageService = StorageService();
  static final ImagePicker _imagePicker = ImagePicker();

  /// Show dialog for reporting a user
  static Future<void> showReportUserDialog({
    required BuildContext context,
    required String reportedUserId,
    required String reportedUserName,
    String? contextType,
    String? contextId,
    required Future<void> Function({
      required String reason,
      String? description,
      List<String>? evidenceImageUrls,
    })
    onSubmit,
    String? successMessage,
    String? errorMessage,
  }) async {
    String selectedReason = 'spam';
    final TextEditingController descriptionController = TextEditingController();
    List<XFile> selectedImages = [];
    bool isUploading = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Report User'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Please select a reason for reporting:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                RadioListTile<String>(
                  title: const Text('Spam'),
                  value: 'spam',
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setDialogState(() {
                      selectedReason = value!;
                    });
                  },
                ),
                RadioListTile<String>(
                  title: const Text('Harassment'),
                  value: 'harassment',
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setDialogState(() {
                      selectedReason = value!;
                    });
                  },
                ),
                RadioListTile<String>(
                  title: const Text('Inappropriate Content'),
                  value: 'inappropriate_content',
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setDialogState(() {
                      selectedReason = value!;
                    });
                  },
                ),
                RadioListTile<String>(
                  title: const Text('Fraud'),
                  value: 'fraud',
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setDialogState(() {
                      selectedReason = value!;
                    });
                  },
                ),
                RadioListTile<String>(
                  title: const Text('Other'),
                  value: 'other',
                  groupValue: selectedReason,
                  onChanged: (value) {
                    setDialogState(() {
                      selectedReason = value!;
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Additional details (optional)',
                    hintText: 'Please provide more information...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Evidence (optional):',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: isUploading
                      ? null
                      : () async {
                          try {
                            final XFile? image = await _imagePicker.pickImage(
                              source: ImageSource.gallery,
                              imageQuality: 85,
                            );
                            if (image != null) {
                              setDialogState(() {
                                selectedImages.add(image);
                              });
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error picking image: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                  icon: const Icon(Icons.add_photo_alternate),
                  label: const Text('Add Evidence Photo'),
                ),
                if (selectedImages.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 100,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: selectedImages.length,
                      itemBuilder: (context, index) {
                        final image = selectedImages[index];
                        return Stack(
                          children: [
                            Container(
                              width: 100,
                              height: 100,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: kIsWeb
                                    ? FutureBuilder<List<int>>(
                                        future: image.readAsBytes(),
                                        builder: (context, snapshot) {
                                          if (snapshot.connectionState ==
                                              ConnectionState.waiting) {
                                            return Container(
                                              color: Colors.grey[300],
                                              child: const Center(
                                                child:
                                                    CircularProgressIndicator(),
                                              ),
                                            );
                                          }
                                          if (snapshot.hasError ||
                                              !snapshot.hasData) {
                                            return const Icon(
                                              Icons.image_not_supported,
                                            );
                                          }
                                          return Image.memory(
                                            Uint8List.fromList(snapshot.data!),
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) {
                                                  return const Icon(
                                                    Icons.image_not_supported,
                                                  );
                                                },
                                          );
                                        },
                                      )
                                    : Image.file(
                                        File(image.path),
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) {
                                              return const Icon(
                                                Icons.image_not_supported,
                                              );
                                            },
                                      ),
                              ),
                            ),
                            Positioned(
                              top: 0,
                              right: 0,
                              child: IconButton(
                                icon: const Icon(Icons.close, size: 20),
                                color: Colors.red,
                                onPressed: () {
                                  setDialogState(() {
                                    selectedImages.removeAt(index);
                                  });
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isUploading ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: isUploading
                  ? null
                  : () async {
                      setDialogState(() {
                        isUploading = true;
                      });

                      final parentContext = context;
                      Navigator.pop(parentContext);

                      final authProvider = Provider.of<AuthProvider>(
                        parentContext,
                        listen: false,
                      );

                      if (authProvider.user == null) return;

                      try {
                        // Upload evidence images first
                        List<String> evidenceImageUrls = [];
                        if (selectedImages.isNotEmpty) {
                          final tempReportId =
                              'temp_${DateTime.now().millisecondsSinceEpoch}';
                          for (final image in selectedImages) {
                            try {
                              final url = await _storageService
                                  .uploadReportEvidenceImage(
                                    file: image,
                                    reportId: tempReportId,
                                    userId: authProvider.user!.uid,
                                  );
                              evidenceImageUrls.add(url);
                            } catch (e) {
                              debugPrint('Error uploading evidence image: $e');
                            }
                          }
                        }

                        // Submit report
                        await onSubmit(
                          reason: selectedReason,
                          description:
                              descriptionController.text.trim().isNotEmpty
                              ? descriptionController.text.trim()
                              : null,
                          evidenceImageUrls: evidenceImageUrls.isNotEmpty
                              ? evidenceImageUrls
                              : null,
                        );

                        if (parentContext.mounted) {
                          ScaffoldMessenger.of(parentContext).showSnackBar(
                            SnackBar(
                              content: Text(
                                successMessage ??
                                    'Report submitted successfully. Thank you for keeping the community safe.',
                              ),
                              backgroundColor: Colors.green,
                              duration: const Duration(seconds: 3),
                            ),
                          );
                        }
                      } catch (e) {
                        if (parentContext.mounted) {
                          ScaffoldMessenger.of(parentContext).showSnackBar(
                            SnackBar(
                              content: Text(
                                errorMessage ?? 'Error submitting report: $e',
                              ),
                              backgroundColor: Colors.red,
                              duration: const Duration(seconds: 3),
                            ),
                          );
                        }
                      }
                    },
              child: isUploading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Report',
                      style: TextStyle(color: Colors.orange),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Show dialog for reporting content (items, trades, rentals, giveaways)
  static Future<void> showReportContentDialog({
    required BuildContext context,
    required String contentType, // 'item', 'trade', 'rental', 'giveaway'
    List<String>? availableReasons, // Custom reasons, defaults to standard set
    required Future<void> Function({
      required String reason,
      String? description,
      List<String>? evidenceImageUrls,
    })
    onSubmit,
    String? successMessage,
    String? errorMessage,
  }) async {
    String selectedReason = 'spam';
    final TextEditingController descriptionController = TextEditingController();
    List<XFile> selectedImages = [];
    bool isUploading = false;

    // Default reasons for content reports
    final defaultReasons = [
      {'value': 'spam', 'label': 'Spam'},
      {'value': 'inappropriate_content', 'label': 'Inappropriate Content'},
      {'value': 'fraud', 'label': 'Fraud'},
      {'value': 'other', 'label': 'Other'},
    ];

    // For giveaways, add 'no_longer_available'
    final reasons = contentType == 'giveaway'
        ? [
            ...defaultReasons,
            {'value': 'no_longer_available', 'label': 'No Longer Available'},
          ]
        : defaultReasons;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            'Report ${contentType[0].toUpperCase()}${contentType.substring(1)}',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Please select a reason for reporting:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ...reasons.map(
                  (reason) => RadioListTile<String>(
                    title: Text(reason['label']!),
                    value: reason['value']!,
                    groupValue: selectedReason,
                    onChanged: (value) {
                      setDialogState(() {
                        selectedReason = value!;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Additional details (optional)',
                    hintText: 'Please provide more information...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Evidence (optional):',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: isUploading
                      ? null
                      : () async {
                          try {
                            final XFile? image = await _imagePicker.pickImage(
                              source: ImageSource.gallery,
                              imageQuality: 85,
                            );
                            if (image != null) {
                              setDialogState(() {
                                selectedImages.add(image);
                              });
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error picking image: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                  icon: const Icon(Icons.add_photo_alternate),
                  label: const Text('Add Evidence Photo'),
                ),
                if (selectedImages.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 100,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: selectedImages.length,
                      itemBuilder: (context, index) {
                        final image = selectedImages[index];
                        return Stack(
                          children: [
                            Container(
                              width: 100,
                              height: 100,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: kIsWeb
                                    ? FutureBuilder<List<int>>(
                                        future: image.readAsBytes(),
                                        builder: (context, snapshot) {
                                          if (snapshot.connectionState ==
                                              ConnectionState.waiting) {
                                            return Container(
                                              color: Colors.grey[300],
                                              child: const Center(
                                                child:
                                                    CircularProgressIndicator(),
                                              ),
                                            );
                                          }
                                          if (snapshot.hasError ||
                                              !snapshot.hasData) {
                                            return const Icon(
                                              Icons.image_not_supported,
                                            );
                                          }
                                          return Image.memory(
                                            Uint8List.fromList(snapshot.data!),
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) {
                                                  return const Icon(
                                                    Icons.image_not_supported,
                                                  );
                                                },
                                          );
                                        },
                                      )
                                    : Image.file(
                                        File(image.path),
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) {
                                              return const Icon(
                                                Icons.image_not_supported,
                                              );
                                            },
                                      ),
                              ),
                            ),
                            Positioned(
                              top: 0,
                              right: 0,
                              child: IconButton(
                                icon: const Icon(Icons.close, size: 20),
                                color: Colors.red,
                                onPressed: () {
                                  setDialogState(() {
                                    selectedImages.removeAt(index);
                                  });
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isUploading ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: isUploading
                  ? null
                  : () async {
                      setDialogState(() {
                        isUploading = true;
                      });

                      final parentContext = context;
                      Navigator.pop(parentContext);

                      final authProvider = Provider.of<AuthProvider>(
                        parentContext,
                        listen: false,
                      );

                      if (authProvider.user == null) return;

                      try {
                        // Upload evidence images first
                        List<String> evidenceImageUrls = [];
                        if (selectedImages.isNotEmpty) {
                          final tempReportId =
                              'temp_${DateTime.now().millisecondsSinceEpoch}';
                          for (final image in selectedImages) {
                            try {
                              final url = await _storageService
                                  .uploadReportEvidenceImage(
                                    file: image,
                                    reportId: tempReportId,
                                    userId: authProvider.user!.uid,
                                  );
                              evidenceImageUrls.add(url);
                            } catch (e) {
                              debugPrint('Error uploading evidence image: $e');
                            }
                          }
                        }

                        // Submit report
                        await onSubmit(
                          reason: selectedReason,
                          description:
                              descriptionController.text.trim().isNotEmpty
                              ? descriptionController.text.trim()
                              : null,
                          evidenceImageUrls: evidenceImageUrls.isNotEmpty
                              ? evidenceImageUrls
                              : null,
                        );

                        if (parentContext.mounted) {
                          ScaffoldMessenger.of(parentContext).showSnackBar(
                            SnackBar(
                              content: Text(
                                successMessage ??
                                    'Report submitted successfully. Thank you for keeping the community safe.',
                              ),
                              backgroundColor: Colors.green,
                              duration: const Duration(seconds: 3),
                            ),
                          );
                        }
                      } catch (e) {
                        if (parentContext.mounted) {
                          ScaffoldMessenger.of(parentContext).showSnackBar(
                            SnackBar(
                              content: Text(
                                errorMessage ?? 'Error submitting report: $e',
                              ),
                              backgroundColor: Colors.red,
                              duration: const Duration(seconds: 3),
                            ),
                          );
                        }
                      }
                    },
              child: isUploading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Report',
                      style: TextStyle(color: Colors.orange),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
