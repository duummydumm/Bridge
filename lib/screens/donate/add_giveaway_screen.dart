import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/storage_service.dart';
import '../../providers/user_provider.dart';
import '../../providers/giveaway_provider.dart';
import '../../models/giveaway_listing_model.dart';

class AddGiveawayScreen extends StatefulWidget {
  const AddGiveawayScreen({super.key});

  @override
  State<AddGiveawayScreen> createState() => _AddGiveawayScreenState();
}

class _AddGiveawayScreenState extends State<AddGiveawayScreen> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();
  final ValueNotifier<String> _progressText = ValueNotifier<String>('');
  bool _submitting = false;

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _pickupNotesController = TextEditingController();

  String _selectedCategory = 'Electronics';
  String? _selectedCondition;
  ClaimMode _claimMode = ClaimMode.firstCome;
  List<dynamic> _selectedImages = []; // Can store XFile (web) or File (mobile)

  final List<String> _categories = [
    'Electronics',
    'Tools',
    'Furniture',
    'Clothing',
    'Books',
    'Toys',
    'Appliances',
    'Others',
  ];

  final List<String> _conditions = ['New', 'Like New', 'Good', 'Fair', 'Used'];

  static const Color _primaryColor = Color(0xFF2A7A9E);
  static const Color _textColor = Color(0xFF333333);

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _pickupNotesController.dispose();
    _progressText.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    try {
      final List<XFile> pickedImages = await _picker.pickMultiImage();
      if (pickedImages.isNotEmpty) {
        setState(() {
          _selectedImages.addAll(pickedImages);
          if (_selectedImages.length > 5) {
            _selectedImages = _selectedImages.take(5).toList();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Maximum 5 images allowed'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick images: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  Future<Uint8List> _compressImage(
    dynamic image, {
    int targetBytes = 600 * 1024,
  }) async {
    try {
      Uint8List inputBytes;
      if (kIsWeb && image is XFile) {
        inputBytes = Uint8List.fromList(await image.readAsBytes());
      } else {
        final filePath = image is File ? image.path : (image as XFile).path;
        inputBytes = await File(filePath).readAsBytes();
      }

      final decoded = img.decodeImage(inputBytes);
      if (decoded == null) {
        return inputBytes;
      }

      const int maxDimension = 1280;
      img.Image working = decoded;
      if (decoded.width > maxDimension || decoded.height > maxDimension) {
        working = img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? maxDimension : null,
          height: decoded.height > decoded.width ? maxDimension : null,
          interpolation: img.Interpolation.average,
        );
      }

      int quality = 85;
      Uint8List encoded = Uint8List.fromList(
        img.encodeJpg(working, quality: quality),
      );
      while (encoded.lengthInBytes > targetBytes && quality > 50) {
        quality -= 10;
        encoded = Uint8List.fromList(img.encodeJpg(working, quality: quality));
      }
      return encoded;
    } catch (_) {
      try {
        if (kIsWeb && image is XFile) {
          return Uint8List.fromList(await image.readAsBytes());
        } else {
          final filePath = image is File ? image.path : (image as XFile).path;
          return await File(filePath).readAsBytes();
        }
      } catch (e) {
        rethrow;
      }
    }
  }

  Future<void> _submitGiveaway() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;

    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final giveawayProvider = Provider.of<GiveawayProvider>(
      context,
      listen: false,
    );
    final storageService = StorageService();

    final currentUser = userProvider.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to post a giveaway')),
      );
      return;
    }

    if (!mounted) return;
    _submitting = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              ValueListenableBuilder<String>(
                valueListenable: _progressText,
                builder: (_, text, __) => Text(
                  text.isEmpty ? 'Uploading…' : text,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      _progressText.value = 'Preparing upload…';

      // Upload images
      List<String> imageUrls = [];
      if (_selectedImages.isNotEmpty) {
        _progressText.value = 'Uploading images…';
        final userId = currentUser.uid;
        for (int i = 0; i < _selectedImages.length; i++) {
          try {
            final tempGiveawayId = DateTime.now().millisecondsSinceEpoch
                .toString();
            Uint8List compressedBytes = await _compressImage(
              _selectedImages[i],
            );
            try {
              final imageUrl = await storageService
                  .uploadItemImageBytes(
                    bytes: compressedBytes,
                    itemId: '$tempGiveawayId-$i',
                    userId: userId,
                    listingType: 'donate',
                    cacheControl: 'public, max-age=3600',
                  )
                  .timeout(const Duration(seconds: 45));
              imageUrls.add(imageUrl);
            } catch (e) {
              // Retry with smaller target
              compressedBytes = await _compressImage(
                _selectedImages[i],
                targetBytes: 400 * 1024,
              );
              try {
                final imageUrl = await storageService
                    .uploadItemImageBytes(
                      bytes: compressedBytes,
                      itemId: '$tempGiveawayId-$i',
                      userId: userId,
                      listingType: 'donate',
                      cacheControl: 'public, max-age=3600',
                    )
                    .timeout(const Duration(seconds: 45));
                imageUrls.add(imageUrl);
              } catch (e2) {
                compressedBytes = await _compressImage(
                  _selectedImages[i],
                  targetBytes: 256 * 1024,
                );
                final imageUrl = await storageService
                    .uploadItemImageBytes(
                      bytes: compressedBytes,
                      itemId: '$tempGiveawayId-$i',
                      userId: userId,
                      listingType: 'donate',
                      cacheControl: 'public, max-age=3600',
                    )
                    .timeout(const Duration(seconds: 45));
                imageUrls.add(imageUrl);
              }
            }
          } catch (e) {
            if (mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Failed to upload image ${i + 1}: $e'),
                  backgroundColor: Colors.red,
                ),
              );
              _submitting = false;
              return;
            }
          }
        }
      }

      _progressText.value = 'Saving giveaway…';

      final location =
          currentUser.barangay.isNotEmpty || currentUser.city.isNotEmpty
          ? '${currentUser.barangay}, ${currentUser.city}'
          : currentUser.city.isNotEmpty
          ? currentUser.city
          : 'Location not set';

      final giveawayId = await giveawayProvider.createGiveaway(
        donorId: currentUser.uid,
        donorName: currentUser.fullName,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        images: imageUrls,
        category: _selectedCategory,
        condition: _selectedCondition,
        location: location,
        claimMode: _claimMode,
        pickupNotes: _pickupNotesController.text.trim().isNotEmpty
            ? _pickupNotesController.text.trim()
            : null,
      );

      if (giveawayId == null) {
        throw Exception(
          giveawayProvider.errorMessage ?? 'Failed to create giveaway',
        );
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Giveaway posted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        final errorMsg = giveawayProvider.errorMessage ?? e.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to post giveaway: $errorMsg'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      _submitting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final currentUser = userProvider.currentUser;
    final location =
        currentUser != null &&
            (currentUser.barangay.isNotEmpty || currentUser.city.isNotEmpty)
        ? '${currentUser.barangay}, ${currentUser.city}'
        : currentUser?.city.isNotEmpty == true
        ? currentUser!.city
        : 'Location not set';

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Post Giveaway',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Item Details Section
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.card_giftcard, color: _primaryColor),
                        const SizedBox(width: 8),
                        Text(
                          'Item Details',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _textColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Title
                    TextFormField(
                      controller: _titleController,
                      decoration: InputDecoration(
                        labelText: 'Item Title *',
                        hintText: 'Enter item title',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: _primaryColor,
                            width: 2,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a title';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    // Category
                    Text(
                      'Category *',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _textColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: DropdownButton<String>(
                        value: _selectedCategory,
                        isExpanded: true,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        underline: Container(),
                        items: _categories.map((category) {
                          return DropdownMenuItem(
                            value: category,
                            child: Text(category),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedCategory = value!;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Condition
                    Text(
                      'Condition (Optional)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _textColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: DropdownButton<String?>(
                        value: _selectedCondition,
                        isExpanded: true,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        underline: Container(),
                        hint: const Text('Select condition (optional)'),
                        items: _conditions.map((condition) {
                          return DropdownMenuItem(
                            value: condition,
                            child: Text(condition),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedCondition = value;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Description
                    TextFormField(
                      controller: _descriptionController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: 'Description *',
                        hintText: 'Describe the item...',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: _primaryColor,
                            width: 2,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a description';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    // Image Picker
                    Text(
                      'Item Photos (Optional, max 5)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _textColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_selectedImages.isEmpty)
                      OutlinedButton.icon(
                        onPressed: _pickImages,
                        icon: const Icon(Icons.add_photo_alternate),
                        label: const Text('Upload Photos'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _primaryColor,
                          side: BorderSide(color: _primaryColor),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: List.generate(_selectedImages.length, (
                          index,
                        ) {
                          return Stack(
                            children: [
                              Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey[300]!),
                                  color: Colors.grey[100],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child:
                                      kIsWeb && _selectedImages[index] is XFile
                                      ? FutureBuilder<List<int>>(
                                          future:
                                              (_selectedImages[index] as XFile)
                                                  .readAsBytes(),
                                          builder: (context, snapshot) {
                                            if (snapshot.connectionState ==
                                                ConnectionState.waiting) {
                                              return const Center(
                                                child:
                                                    CircularProgressIndicator(),
                                              );
                                            }
                                            if (snapshot.hasData) {
                                              return Image.memory(
                                                Uint8List.fromList(
                                                  snapshot.data!,
                                                ),
                                                fit: BoxFit.cover,
                                              );
                                            }
                                            return const Icon(Icons.error);
                                          },
                                        )
                                      : Image.file(
                                          File(
                                            _selectedImages[index] is File
                                                ? (_selectedImages[index]
                                                          as File)
                                                      .path
                                                : (_selectedImages[index]
                                                          as XFile)
                                                      .path,
                                          ),
                                          fit: BoxFit.cover,
                                        ),
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: () => _removeImage(index),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }),
                      ),
                    if (_selectedImages.isNotEmpty &&
                        _selectedImages.length < 5)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: TextButton.icon(
                          onPressed: _pickImages,
                          icon: const Icon(Icons.add),
                          label: const Text('Add More Photos'),
                          style: TextButton.styleFrom(
                            foregroundColor: _primaryColor,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Claim Mode Section
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.how_to_reg, color: _primaryColor),
                        const SizedBox(width: 8),
                        Text(
                          'Claim Mode',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _textColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    RadioListTile<ClaimMode>(
                      title: const Text('First Come, First Served'),
                      subtitle: const Text(
                        'First person to claim gets the item',
                      ),
                      value: ClaimMode.firstCome,
                      groupValue: _claimMode,
                      onChanged: (value) {
                        setState(() {
                          _claimMode = value!;
                        });
                      },
                      activeColor: _primaryColor,
                    ),
                    RadioListTile<ClaimMode>(
                      title: const Text('Approval Required'),
                      subtitle: const Text(
                        'You approve claim requests manually',
                      ),
                      value: ClaimMode.approvalRequired,
                      groupValue: _claimMode,
                      onChanged: (value) {
                        setState(() {
                          _claimMode = value!;
                        });
                      },
                      activeColor: _primaryColor,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Pickup Notes Section
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.location_on, color: _primaryColor),
                        const SizedBox(width: 8),
                        Text(
                          'Location & Pickup',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: _textColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Location (Read-only)
                    TextFormField(
                      initialValue: location,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'Location',
                        filled: true,
                        fillColor: Colors.grey[100],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        suffixIcon: const Icon(Icons.lock_outline),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Pickup Notes
                    TextFormField(
                      controller: _pickupNotesController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Pickup Notes (Optional)',
                        hintText: 'Instructions for pickup coordination...',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: _primaryColor,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Submit and Cancel Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _submitting
                        ? null
                        : () {
                            Navigator.pop(context);
                          },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _textColor,
                      side: BorderSide(color: Colors.grey[300]!),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _submitGiveaway,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    child: _submitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Text(
                            'Post Giveaway',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
