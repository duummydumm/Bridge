import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/storage_service.dart';
import '../../providers/user_provider.dart';
import '../../providers/trade_item_provider.dart';

class AddTradeItemScreen extends StatefulWidget {
  const AddTradeItemScreen({super.key});

  @override
  State<AddTradeItemScreen> createState() => _AddTradeItemScreenState();
}

class _AddTradeItemScreenState extends State<AddTradeItemScreen> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();
  final ValueNotifier<String> _progressText = ValueNotifier<String>('');
  bool _submitting = false;

  final _offeredItemNameController = TextEditingController();
  final _offeredDescriptionController = TextEditingController();
  final _desiredItemNameController = TextEditingController();
  final _notesController = TextEditingController();

  String _selectedCategory = 'Electronics';
  String? _selectedDesiredCategory;
  bool _isActive = true;
  List<dynamic> _selectedImages = []; // Can store XFile (web) or File (mobile)
  List<String> _existingImageUrls = []; // For edit mode
  bool _isEditMode = false;
  String? _tradeItemId;
  bool _isLoading = false;
  static const int _maxImages = 5; // Maximum number of images allowed

  final List<String> _categories = [
    'Electronics',
    'Tools',
    'Furniture',
    'Clothing',
    'Books',
    'Others',
  ];

  // BRIDGE theme color
  static const Color _primaryColor = Color(0xFF2A7A9E);
  static const Color _textColor = Color(0xFF333333);
  static const String _defaultPlaceholderImage =
      'https://via.placeholder.com/400x300?text=No+Image';

  @override
  void dispose() {
    _offeredItemNameController.dispose();
    _offeredDescriptionController.dispose();
    _desiredItemNameController.dispose();
    _notesController.dispose();
    _progressText.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['tradeItemId'] is String) {
      _tradeItemId = args['tradeItemId'] as String;
      _isEditMode = true;
      _loadTradeItem();
    }
  }

  Future<void> _loadTradeItem() async {
    if (_tradeItemId == null) return;
    setState(() => _isLoading = true);
    try {
      final provider = Provider.of<TradeItemProvider>(context, listen: false);
      final tradeItem = await provider.getTradeItem(_tradeItemId!);
      if (tradeItem == null || !mounted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Trade item not found'),
              backgroundColor: Colors.red,
            ),
          );
          Navigator.pop(context);
        }
        return;
      }

      setState(() {
        _offeredItemNameController.text = tradeItem.offeredItemName;
        _offeredDescriptionController.text = tradeItem.offeredDescription;
        _desiredItemNameController.text = tradeItem.desiredItemName ?? '';
        _notesController.text = tradeItem.notes ?? '';
        _selectedCategory = tradeItem.offeredCategory;
        _selectedDesiredCategory = tradeItem.desiredCategory;
        _isActive = tradeItem.isOpen;
        _existingImageUrls = tradeItem.offeredImageUrls;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading trade item: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pickImages() async {
    try {
      // Check if we've reached max images
      final totalImages = _selectedImages.length + _existingImageUrls.length;
      if (totalImages >= _maxImages) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Maximum $_maxImages images allowed'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final remainingSlots = _maxImages - totalImages;
      final dynamic pickedImages = await _picker.pickMultiImage();

      if (pickedImages != null && pickedImages.isNotEmpty) {
        // Limit to remaining slots
        final imagesToAdd = pickedImages.length > remainingSlots
            ? pickedImages.take(remainingSlots).toList()
            : pickedImages;

        setState(() {
          _selectedImages.addAll(imagesToAdd);
        });

        if (pickedImages.length > remainingSlots && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Only $remainingSlots image(s) added. Maximum $_maxImages images allowed.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
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

  void _removeImage(int index, bool isExisting) {
    setState(() {
      if (isExisting) {
        _existingImageUrls.removeAt(index);
      } else {
        _selectedImages.removeAt(index);
      }
    });
  }

  Widget _buildImagePreview() {
    final allImages = <Widget>[];

    // Add existing images (from edit mode)
    for (int i = 0; i < _existingImageUrls.length; i++) {
      allImages.add(
        _buildImageItem(
          imageUrl: _existingImageUrls[i],
          index: i,
          isExisting: true,
        ),
      );
    }

    // Add newly selected images
    for (int i = 0; i < _selectedImages.length; i++) {
      allImages.add(
        _buildImageItem(image: _selectedImages[i], index: i, isExisting: false),
      );
    }

    if (allImages.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(spacing: 12, runSpacing: 12, children: allImages);
  }

  Widget _buildImageItem({
    String? imageUrl,
    dynamic image,
    required int index,
    required bool isExisting,
  }) {
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
            child: isExisting && imageUrl != null
                ? Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.grey[300],
                        child: const Icon(
                          Icons.broken_image_outlined,
                          color: Colors.red,
                          size: 32,
                        ),
                      );
                    },
                  )
                : _buildLocalImagePreview(image),
          ),
        ),
        if (isExisting)
          Positioned(
            top: 4,
            left: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Current',
                style: TextStyle(color: Colors.white, fontSize: 9),
              ),
            ),
          ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: () => _removeImage(index, isExisting),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLocalImagePreview(dynamic image) {
    if (kIsWeb && image is XFile) {
      return FutureBuilder<List<int>>(
        future: image.readAsBytes(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Container(
              color: Colors.grey[300],
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Container(
              color: Colors.grey[300],
              child: const Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 32,
              ),
            );
          }
          return Image.memory(
            Uint8List.fromList(snapshot.data!),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: Colors.grey[300],
                child: const Icon(
                  Icons.error_outline,
                  color: Colors.red,
                  size: 32,
                ),
              );
            },
          );
        },
      );
    } else {
      try {
        final filePath = image is File ? image.path : (image as XFile).path;
        return Image.file(
          File(filePath),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: Colors.grey[300],
              child: const Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 32,
              ),
            );
          },
        );
      } catch (e) {
        return Container(
          color: Colors.grey[300],
          child: const Icon(Icons.error_outline, color: Colors.red, size: 32),
        );
      }
    }
  }

  Future<Uint8List> _compressImage(
    dynamic image, {
    int targetBytes = 600 * 1024, // default ~0.6MB
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
        return inputBytes; // Fallback: cannot decode
      }

      // Resize if needed (keep aspect ratio), target max dimension ~1280px
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

      // Encode to JPEG and iterate quality to hit target size
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
      // In case of any error, return original file bytes
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

  Future<void> _submitTradeItem() async {
    if (_submitting) return; // prevent double submit
    if (!_formKey.currentState!.validate()) return;

    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final tradeItemProvider = Provider.of<TradeItemProvider>(
      context,
      listen: false,
    );
    final storageService = StorageService();

    final currentUser = userProvider.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to list items for trade')),
      );
      return;
    }

    // Show loading dialog
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

      // Upload images if selected
      List<String> imageUrls = List.from(
        _existingImageUrls,
      ); // Keep existing images

      if (_selectedImages.isNotEmpty) {
        try {
          final tempTradeId = DateTime.now().millisecondsSinceEpoch.toString();
          final userId = currentUser.uid;

          for (int i = 0; i < _selectedImages.length; i++) {
            _progressText.value =
                'Uploading image ${i + 1}/${_selectedImages.length}…';

            try {
              Uint8List compressedBytes = await _compressImage(
                _selectedImages[i],
              );
              try {
                final imageUrl = await storageService
                    .uploadTradeImageBytes(
                      bytes: compressedBytes,
                      itemId: '${tempTradeId}_$i',
                      userId: userId,
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
                      .uploadTradeImageBytes(
                        bytes: compressedBytes,
                        itemId: '${tempTradeId}_$i',
                        userId: userId,
                        cacheControl: 'public, max-age=3600',
                      )
                      .timeout(const Duration(seconds: 45));
                  imageUrls.add(imageUrl);
                } catch (e2) {
                  // Final attempt with very small size
                  compressedBytes = await _compressImage(
                    _selectedImages[i],
                    targetBytes: 256 * 1024,
                  );
                  final imageUrl = await storageService
                      .uploadTradeImageBytes(
                        bytes: compressedBytes,
                        itemId: '${tempTradeId}_$i',
                        userId: userId,
                        cacheControl: 'public, max-age=3600',
                      )
                      .timeout(const Duration(seconds: 45));
                  imageUrls.add(imageUrl);
                }
              }
            } catch (e) {
              // Skip failed image but continue with others
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to upload image ${i + 1}: $e'),
                    backgroundColor: Colors.orange,
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            }
          }

          if (imageUrls.isEmpty) {
            // Use default placeholder if no images uploaded
            imageUrls = [_defaultPlaceholderImage];
          }
        } catch (e) {
          if (mounted) {
            Navigator.pop(context); // Close loading dialog
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to upload images: $e'),
                backgroundColor: Colors.red,
              ),
            );
            _submitting = false;
            return;
          }
        }
      } else if (imageUrls.isEmpty) {
        // No existing images and no new images selected
        imageUrls = [_defaultPlaceholderImage];
      }

      _progressText.value = 'Saving trade listing…';

      // Prepare location string - use full address
      final location = currentUser.fullAddress.isNotEmpty
          ? currentUser.fullAddress
          : 'Location not set';

      if (_isEditMode && _tradeItemId != null) {
        // Update existing trade item
        final success = await tradeItemProvider.updateTradeItem(
          tradeItemId: _tradeItemId!,
          offeredItemName: _offeredItemNameController.text.trim(),
          offeredCategory: _selectedCategory,
          offeredDescription: _offeredDescriptionController.text.trim(),
          offeredImageUrls: imageUrls,
          desiredItemName: _desiredItemNameController.text.trim().isNotEmpty
              ? _desiredItemNameController.text.trim()
              : null,
          desiredCategory: _selectedDesiredCategory,
          notes: _notesController.text.trim().isNotEmpty
              ? _notesController.text.trim()
              : null,
          location: location,
          isActive: _isActive,
        );

        if (!success) {
          throw Exception(
            tradeItemProvider.errorMessage ?? 'Failed to update trade item',
          );
        }

        if (mounted) {
          Navigator.pop(context); // Close loading dialog
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Trade item updated successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context); // Return to previous screen
        }
      } else {
        // Create new trade item
        final tradeItemId = await tradeItemProvider.createTradeItem(
          offeredItemName: _offeredItemNameController.text.trim(),
          offeredCategory: _selectedCategory,
          offeredDescription: _offeredDescriptionController.text.trim(),
          offeredImageUrls: imageUrls,
          desiredItemName: _desiredItemNameController.text.trim().isNotEmpty
              ? _desiredItemNameController.text.trim()
              : null,
          desiredCategory: _selectedDesiredCategory,
          notes: _notesController.text.trim().isNotEmpty
              ? _notesController.text.trim()
              : null,
          location: location,
          offeredBy: currentUser.uid,
          isActive: _isActive,
        );

        if (tradeItemId == null) {
          throw Exception(
            tradeItemProvider.errorMessage ?? 'Failed to create trade item',
          );
        }

        if (mounted) {
          Navigator.pop(context); // Close loading dialog
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Item listed for trade successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context); // Return to previous screen
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        final errorMsg = tradeItemProvider.errorMessage ?? e.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create trade listing: $errorMsg'),
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
    final location = currentUser != null && currentUser.fullAddress.isNotEmpty
        ? currentUser.fullAddress
        : 'Location not set';

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          _isEditMode ? 'Edit Trade Item' : 'Post Item for Trade',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Section 1: Item You're Offering
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
                              Icon(Icons.inventory_2, color: _primaryColor),
                              const SizedBox(width: 8),
                              Text(
                                'Item You\'re Offering',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: _textColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Item Name
                          TextFormField(
                            controller: _offeredItemNameController,
                            decoration: InputDecoration(
                              labelText: 'Item Name *',
                              hintText: 'Enter item name',
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
                                return 'Please enter an item name';
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
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

                          // Description
                          TextFormField(
                            controller: _offeredDescriptionController,
                            maxLines: 4,
                            decoration: InputDecoration(
                              labelText: 'Description / Condition *',
                              hintText:
                                  'Describe your item and its condition...',
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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Item Photos (Optional)',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: _textColor,
                                ),
                              ),
                              if (_selectedImages.length +
                                      _existingImageUrls.length <
                                  _maxImages)
                                Text(
                                  '${_selectedImages.length + _existingImageUrls.length}/$_maxImages',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _pickImages,
                            icon: const Icon(Icons.add_photo_alternate),
                            label: Text(
                              _selectedImages.isEmpty &&
                                      _existingImageUrls.isEmpty
                                  ? 'Upload Photos'
                                  : 'Add More Photos',
                            ),
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
                          ),
                          if (_selectedImages.isNotEmpty ||
                              _existingImageUrls.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _buildImagePreview(),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Section 2: Item You're Looking For
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
                              Icon(Icons.search, color: _primaryColor),
                              const SizedBox(width: 8),
                              Text(
                                'Item You\'re Looking For',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: _textColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Desired Item Name
                          TextFormField(
                            controller: _desiredItemNameController,
                            decoration: InputDecoration(
                              labelText: 'Desired Item Name (Optional)',
                              hintText: 'What are you looking for?',
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
                          const SizedBox(height: 16),

                          // Preferred Category
                          Text(
                            'Preferred Category (Optional)',
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
                              value: _selectedDesiredCategory,
                              isExpanded: true,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              underline: Container(),
                              hint: const Text('Select category (optional)'),
                              items: _categories.map((category) {
                                return DropdownMenuItem(
                                  value: category,
                                  child: Text(category),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedDesiredCategory = value;
                                });
                              },
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Notes
                          TextFormField(
                            controller: _notesController,
                            maxLines: 3,
                            decoration: InputDecoration(
                              labelText:
                                  'Notes or Additional Details (Optional)',
                              hintText: 'Any additional information...',
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
                  const SizedBox(height: 16),

                  // Section 3: Location & Status
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
                                'Location & Status',
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

                          // Active Listing Switch
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Active Listing',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: _textColor,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Make this listing visible to others',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: _isActive,
                                onChanged: (value) {
                                  setState(() {
                                    _isActive = value;
                                  });
                                },
                                activeColor: _primaryColor,
                              ),
                            ],
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
                          onPressed: _submitting ? null : _submitTradeItem,
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
                              : Text(
                                  _isEditMode
                                      ? 'Update Listing'
                                      : 'Save Listing',
                                  style: const TextStyle(
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
