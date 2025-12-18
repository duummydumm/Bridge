import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/item_provider.dart';
import '../providers/user_provider.dart';
import '../services/storage_service.dart';
import '../models/item_model.dart';

class ListItemScreen extends StatefulWidget {
  const ListItemScreen({super.key});

  @override
  State<ListItemScreen> createState() => _ListItemScreenState();
}

class _ListItemScreenState extends State<ListItemScreen> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();
  final ValueNotifier<String> _progressText = ValueNotifier<String>('');
  bool _submitting = false;

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _selectedCategory = 'Tools';
  String _selectedCondition = 'Good';
  String _listingType = 'lend';
  List<dynamic> _selectedImages = []; // Can store XFile (web) or File (mobile)
  List<String> _existingImageUrls = []; // For edit mode
  bool _isEditMode = false;
  String? _itemId;
  bool _isLoading = false;

  final List<String> _categories = [
    'Tools',
    'Electronics',
    'Furniture',
    'Sports & Recreation',
    'Home & Garden',
    'Appliances',
    'Vehicles',
    'Other',
  ];

  final List<String> _conditions = ['New', 'Like New', 'Good', 'Fair'];

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _progressText.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      if (args['listingType'] is String) {
        _listingType = (args['listingType'] as String);
      }
      if (args['itemId'] is String) {
        _itemId = args['itemId'] as String;
        _isEditMode = true;
        _loadItem();
      }
    }
  }

  Future<void> _loadItem() async {
    if (_itemId == null) return;
    setState(() => _isLoading = true);
    try {
      final provider = Provider.of<ItemProvider>(context, listen: false);
      await provider.loadItemById(_itemId!);
      final item = provider.selectedItem;
      if (item == null || !mounted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Item not found'),
              backgroundColor: Colors.red,
            ),
          );
          Navigator.pop(context);
        }
        return;
      }

      setState(() {
        _titleController.text = item.title;
        _descriptionController.text = item.description;
        _selectedCategory = item.category;
        _selectedCondition = item.condition;
        _listingType = item.type;
        _existingImageUrls = List<String>.from(item.images);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading item: $e'),
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
      final List<dynamic> pickedImages = await _picker.pickMultiImage();
      if (pickedImages.isNotEmpty) {
        setState(() {
          _selectedImages.addAll(pickedImages);
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

  Widget _buildExistingImagePreview(String imageUrl, int index) {
    return Stack(
      children: [
        Container(
          width: 100,
          height: 100,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                color: Colors.grey[300],
                child: const Center(child: CircularProgressIndicator()),
              ),
              errorWidget: (context, url, error) => Container(
                color: Colors.grey[300],
                child: const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.red,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: () {
              setState(() {
                _existingImageUrls.removeAt(index);
              });
            },
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 16),
            ),
          ),
        ),
        Positioned(
          bottom: 4,
          left: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'Current',
              style: TextStyle(color: Colors.white, fontSize: 10),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImagePreview(dynamic image, int index) {
    return Stack(
      children: [
        Container(
          width: 100,
          height: 100,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Builder(
              builder: (context) {
                // Handle web platform where Image.file is not supported
                if (kIsWeb && image is XFile) {
                  return FutureBuilder<List<int>>(
                    future: image.readAsBytes(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Container(
                          color: Colors.grey[300],
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      if (snapshot.hasError || !snapshot.hasData) {
                        debugPrint(
                          '❌ Error loading image bytes: ${snapshot.error}',
                        );
                        return Container(
                          color: Colors.grey[300],
                          child: const Icon(
                            Icons.error_outline,
                            color: Colors.red,
                          ),
                        );
                      }
                      return Image.memory(
                        Uint8List.fromList(snapshot.data!),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          debugPrint('❌ Image.memory error: $error');
                          return Container(
                            color: Colors.grey[300],
                            child: const Icon(
                              Icons.error_outline,
                              color: Colors.red,
                            ),
                          );
                        },
                      );
                    },
                  );
                } else {
                  // Handle non-web platform with File
                  try {
                    final filePath = image is File
                        ? image.path
                        : (image as XFile).path;
                    debugPrint('📸 Building preview for: $filePath');
                    return Image.file(
                      File(filePath),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        debugPrint('❌ Image preview error: $error');
                        debugPrint('Image path: $filePath');
                        return Container(
                          color: Colors.grey[300],
                          child: const Icon(
                            Icons.error_outline,
                            color: Colors.red,
                          ),
                        );
                      },
                    );
                  } catch (e) {
                    debugPrint('❌ Error loading image: $e');
                    return Container(
                      color: Colors.grey[300],
                      child: const Icon(Icons.error_outline, color: Colors.red),
                    );
                  }
                }
              },
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
              child: const Icon(Icons.close, color: Colors.white, size: 16),
            ),
          ),
        ),
      ],
    );
  }

  Future<Uint8List> _compressImage(
    dynamic image, {
    int targetBytes = 600 * 1024, // default ~0.6MB for faster uploads
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
      // In case of any error, return original file bytes path-based
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

  Future<void> _submitItem() async {
    if (_submitting) return; // prevent double submit
    if (!_formKey.currentState!.validate()) return;

    final itemProvider = Provider.of<ItemProvider>(context, listen: false);
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final storageService = StorageService();

    final currentUser = userProvider.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to list items')),
      );
      return;
    }

    // Check if user can lend
    if (!currentUser.canLend) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your account is not set up for lending')),
      );
      return;
    }

    // Show loading dialog for the entire submission process
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
      // Proceed directly on web; skip probe to avoid false timeouts
      if (kIsWeb) {
        _progressText.value = 'Preparing upload…';
      }

      // Upload images first to get URLs (compress before upload)
      List<String> imageUrls = [];
      if (_selectedImages.isNotEmpty) {
        // Create a temporary item ID for uploads
        final tempItemId = DateTime.now().millisecondsSinceEpoch.toString();
        final userId = currentUser.uid;
        // Determine listing type: 'borrow' for lend, 'donate' for donate
        final listingType = _listingType.toLowerCase() == 'donate'
            ? 'donate'
            : 'borrow';

        for (int i = 0; i < _selectedImages.length; i++) {
          final image = _selectedImages[i];
          try {
            _progressText.value =
                'Uploading ${i + 1}/${_selectedImages.length}…';
            // First attempt ~0.9MB
            Uint8List compressedBytes = await _compressImage(image);
            String url;
            try {
              url = await storageService
                  .uploadItemImageBytes(
                    bytes: compressedBytes,
                    itemId: tempItemId,
                    userId: userId,
                    listingType: listingType,
                    cacheControl: 'public, max-age=3600',
                  )
                  .timeout(const Duration(seconds: 45));
            } catch (e) {
              // Retry once with smaller target (~0.4MB)
              compressedBytes = await _compressImage(
                image,
                targetBytes: 400 * 1024,
              );
              try {
                url = await storageService
                    .uploadItemImageBytes(
                      bytes: compressedBytes,
                      itemId: tempItemId,
                      userId: userId,
                      listingType: listingType,
                      cacheControl: 'public, max-age=3600',
                    )
                    .timeout(const Duration(seconds: 45));
              } catch (e2) {
                // Third attempt very small (~0.25MB)
                compressedBytes = await _compressImage(
                  image,
                  targetBytes: 256 * 1024,
                );
                url = await storageService
                    .uploadItemImageBytes(
                      bytes: compressedBytes,
                      itemId: tempItemId,
                      userId: userId,
                      listingType: listingType,
                      cacheControl: 'public, max-age=3600',
                    )
                    .timeout(const Duration(seconds: 45));
              }
            }
            imageUrls.add(url);
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Failed to upload image: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
            return;
          }
        }
      }

      _progressText.value = 'Saving item…';

      // Use user's registration location automatically
      // Include street, barangay, city, province
      final locationParts = <String>[];
      if (currentUser.street.isNotEmpty) {
        locationParts.add(currentUser.street);
      }
      if (currentUser.barangay.isNotEmpty) {
        locationParts.add(currentUser.barangay);
      }
      if (currentUser.city.isNotEmpty) {
        locationParts.add(currentUser.city);
      }
      if (currentUser.province.isNotEmpty) {
        locationParts.add(currentUser.province);
      }
      final location = locationParts.join(', ');

      if (_isEditMode && _itemId != null) {
        // Update existing item
        final existingItem = itemProvider.selectedItem;
        if (existingItem == null) {
          if (mounted) {
            Navigator.pop(context); // Close loading
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Item not found'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }

        // Combine existing images (that weren't removed) with new ones
        final allImageUrls = List<String>.from(_existingImageUrls)
          ..addAll(imageUrls);

        final updatedItem = ItemModel(
          itemId: _itemId!,
          lenderId: existingItem.lenderId,
          lenderName: existingItem.lenderName,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          images: allImageUrls,
          category: _selectedCategory,
          type: _listingType,
          condition: _selectedCondition,
          status: existingItem.status, // Preserve status
          pricePerDay: existingItem.pricePerDay,
          location: location.isNotEmpty ? location : existingItem.location,
          createdAt: existingItem.createdAt,
          lastUpdated: DateTime.now(),
          currentBorrowerId: existingItem.currentBorrowerId,
          borrowedDate: existingItem.borrowedDate,
          returnDate: existingItem.returnDate,
        );

        final success = await itemProvider.updateItem(updatedItem);

        if (mounted) {
          Navigator.pop(context); // Close loading
          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Item updated successfully!'),
                backgroundColor: Colors.green,
              ),
            );
            Navigator.pop(context); // Close screen
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  itemProvider.errorMessage ?? 'Failed to update item',
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } else {
        // Create new item
        final success = await itemProvider.createItem(
          lenderId: currentUser.uid,
          lenderName: currentUser.fullName,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          images: imageUrls,
          category: _selectedCategory,
          type: _listingType,
          condition: _selectedCondition,
          pricePerDay: null,
          location: location.isNotEmpty ? location : null,
        );

        if (mounted) {
          Navigator.pop(context); // Close loading
          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Item listed successfully!'),
                backgroundColor: Colors.green,
              ),
            );
            Navigator.pop(context); // Close screen
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  itemProvider.errorMessage ?? 'Failed to list item',
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } finally {
      // Ensure loading dialog is closed if still open
      if (mounted) {
        final rootNav = Navigator.of(context, rootNavigator: true);
        if (rootNav.canPop()) {
          rootNav.pop();
        }
      }
      _submitting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_isEditMode ? 'Edit Item' : 'List New Item'),
          backgroundColor: const Color(0xFF00897B),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(_isEditMode ? 'Edit Item' : 'List New Item'),
        backgroundColor: const Color(0xFF00897B),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title Field
              _buildSectionTitle('Title'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  hintText: 'Enter item title',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a title';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 24),

              // Images Section
              _buildSectionTitle('Images (Optional)'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Show existing images in edit mode
                    if (_isEditMode && _existingImageUrls.isNotEmpty)
                      Wrap(
                        children: [
                          ...List.generate(
                            _existingImageUrls.length,
                            (index) => _buildExistingImagePreview(
                              _existingImageUrls[index],
                              index,
                            ),
                          ),
                        ],
                      ),
                    // Show new selected images
                    if (_selectedImages.isNotEmpty)
                      Wrap(
                        children: [
                          ...List.generate(
                            _selectedImages.length,
                            (index) => _buildImagePreview(
                              _selectedImages[index],
                              index,
                            ),
                          ),
                        ],
                      ),
                    // Show add button if total images < 5
                    if ((_isEditMode ? _existingImageUrls.length : 0) +
                            _selectedImages.length <
                        5)
                      ElevatedButton.icon(
                        onPressed: _pickImages,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: Text(
                          _isEditMode && _existingImageUrls.isNotEmpty
                              ? 'Add More Photos'
                              : 'Add Photos',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[100],
                          foregroundColor: Colors.grey[700],
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Category Selection
              _buildSectionTitle('Category'),
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

              const SizedBox(height: 24),

              // Description Field
              _buildSectionTitle('Description'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descriptionController,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: 'Describe your item...',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a description';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 24),

              // Condition Selection
              _buildSectionTitle('Condition'),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: DropdownButton<String>(
                  value: _selectedCondition,
                  isExpanded: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  underline: Container(),
                  items: _conditions.map((condition) {
                    return DropdownMenuItem(
                      value: condition,
                      child: Text(condition),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedCondition = value!;
                    });
                  },
                ),
              ),

              const SizedBox(height: 32),

              // Submit Button
              Consumer<ItemProvider>(
                builder: (context, provider, child) {
                  return SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: provider.isLoading ? null : _submitItem,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00897B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: provider.isLoading
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
                              _isEditMode ? 'Update Item' : 'List Item',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }
}
