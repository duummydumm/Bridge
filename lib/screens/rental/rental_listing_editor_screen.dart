import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/rental_listing_provider.dart';
import '../../models/rental_listing_model.dart';
import '../../providers/user_provider.dart';
import '../../services/storage_service.dart';
import '../../services/firestore_service.dart';

class RentalListingEditorScreen extends StatefulWidget {
  const RentalListingEditorScreen({super.key});

  @override
  State<RentalListingEditorScreen> createState() =>
      _RentalListingEditorScreenState();
}

class _RentalListingEditorScreenState extends State<RentalListingEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();
  final StorageService _storageService = StorageService();
  PricingMode _mode = PricingMode.perDay;
  final _titleCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _pricePerDayCtrl = TextEditingController();
  final _pricePerWeekCtrl = TextEditingController();
  final _pricePerMonthCtrl = TextEditingController();
  final _minDaysCtrl = TextEditingController();
  final _maxDaysCtrl = TextEditingController();
  final _depositCtrl = TextEditingController();
  final _quantityCtrl = TextEditingController();
  final _bedroomsCtrl = TextEditingController();
  final _bathroomsCtrl = TextEditingController();
  final _floorAreaCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _allowedBusinessCtrl = TextEditingController();
  final _leaseTermCtrl = TextEditingController();
  final _curfewRulesCtrl = TextEditingController();
  final _maxOccupantsCtrl = TextEditingController();
  final _numberOfRoomsCtrl = TextEditingController();
  final _occupantsPerRoomCtrl = TextEditingController();
  final _initialOccupantsCtrl =
      TextEditingController(); // Pre-existing occupants

  String? _selectedCategory;
  String? _selectedCondition;
  String?
  _selectedGenderPreference; // For boarding houses: "Male", "Female", "Mixed", "Any"
  RentalType _rentType = RentalType.item;
  bool _sharedCR = false;
  bool _bedSpaceAvailable = false;
  List<dynamic> _selectedImages = []; // Can store XFile (web) or File (mobile)
  List<String> _existingImageUrls = []; // For edit mode
  bool _isActive = true;
  bool _allowMultipleRentals = false; // For commercial spaces/apartments
  bool _utilitiesIncluded = false;
  bool _uploadingImage = false;
  bool _isEditMode = false;
  String? _listingId;
  String? _itemId;
  bool _isLoading = false;
  final PageController _imagePageController = PageController();
  int _currentImageIndex = 0;

  final List<String> _categories = [
    'Electronics',
    'Tools',
    'Clothing',
    'Furniture',
    'Sports & Recreation',
    'Home & Garden',
    'Appliances',
    'Vehicles',
    'Commercial Rent',
    'Other',
  ];

  final List<String> _conditions = ['New', 'Like New', 'Good', 'Fair'];

  @override
  void dispose() {
    _imagePageController.dispose();
    _titleCtrl.dispose();
    _descriptionCtrl.dispose();
    _locationCtrl.dispose();
    _pricePerDayCtrl.dispose();
    _pricePerWeekCtrl.dispose();
    _pricePerMonthCtrl.dispose();
    _minDaysCtrl.dispose();
    _maxDaysCtrl.dispose();
    _depositCtrl.dispose();
    _quantityCtrl.dispose();
    _bedroomsCtrl.dispose();
    _bathroomsCtrl.dispose();
    _floorAreaCtrl.dispose();
    _addressCtrl.dispose();
    _allowedBusinessCtrl.dispose();
    _leaseTermCtrl.dispose();
    _curfewRulesCtrl.dispose();
    _maxOccupantsCtrl.dispose();
    _numberOfRoomsCtrl.dispose();
    _occupantsPerRoomCtrl.dispose();
    _initialOccupantsCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['listingId'] is String) {
      _listingId = args['listingId'] as String;
      _isEditMode = true;
      _loadListing();
    }
  }

  Future<void> _loadListing() async {
    if (_listingId == null) return;
    setState(() => _isLoading = true);
    try {
      final provider = Provider.of<RentalListingProvider>(
        context,
        listen: false,
      );
      final listing = await provider.getListing(_listingId!);
      if (listing == null || !mounted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Listing not found'),
              backgroundColor: Colors.red,
            ),
          );
          Navigator.pop(context);
        }
        return;
      }

      // Load full data from Firestore to get title, description, etc.
      final firestoreService = FirestoreService();
      final data = await firestoreService.getRentalListing(_listingId!);
      if (data != null) {
        setState(() {
          _itemId = listing.itemId;
          _titleCtrl.text = data['title'] ?? '';
          _descriptionCtrl.text = data['description'] ?? '';
          _locationCtrl.text = data['location'] ?? '';
          _selectedCategory = data['category'];
          _selectedCondition = data['condition'];
          _mode = listing.pricingMode;
          _pricePerDayCtrl.text = listing.pricePerDay?.toString() ?? '';
          _pricePerWeekCtrl.text = listing.pricePerWeek?.toString() ?? '';
          _pricePerMonthCtrl.text = listing.pricePerMonth?.toString() ?? '';
          // Clear min/max days for property rentals (apartment, boarding house, commercial)
          if (listing.rentType == RentalType.apartment ||
              listing.rentType == RentalType.boardingHouse ||
              listing.rentType == RentalType.commercial) {
            _minDaysCtrl.text = '';
            _maxDaysCtrl.text = '';
          } else {
            _minDaysCtrl.text = listing.minDays?.toString() ?? '';
            _maxDaysCtrl.text = listing.maxDays?.toString() ?? '';
          }
          _depositCtrl.text = listing.securityDeposit?.toString() ?? '';
          _isActive = listing.isActive;
          _allowMultipleRentals = listing.allowMultipleRentals;
          _quantityCtrl.text = listing.quantity?.toString() ?? '';
          _rentType = listing.rentType;
          _bedroomsCtrl.text = listing.bedrooms?.toString() ?? '';
          _bathroomsCtrl.text = listing.bathrooms?.toString() ?? '';
          _floorAreaCtrl.text = listing.floorArea?.toString() ?? '';
          _utilitiesIncluded = listing.utilitiesIncluded ?? false;
          _addressCtrl.text = listing.address ?? '';
          _allowedBusinessCtrl.text = listing.allowedBusiness ?? '';
          _leaseTermCtrl.text = listing.leaseTerm?.toString() ?? '';
          _sharedCR = listing.sharedCR ?? false;
          _bedSpaceAvailable = listing.bedSpaceAvailable ?? false;
          _maxOccupantsCtrl.text = listing.maxOccupants?.toString() ?? '';
          _numberOfRoomsCtrl.text = listing.numberOfRooms?.toString() ?? '';
          _occupantsPerRoomCtrl.text =
              listing.occupantsPerRoom?.toString() ?? '';
          _initialOccupantsCtrl.text =
              listing.initialOccupants?.toString() ?? '';
          _selectedGenderPreference = listing.genderPreference;
          _curfewRulesCtrl.text = listing.curfewRules ?? '';
          // Load existing images - support both single imageUrl and multiple images
          if (data['images'] is List) {
            _existingImageUrls = List<String>.from(data['images'] ?? []);
          } else if (data['imageUrl'] is String) {
            _existingImageUrls = [data['imageUrl'] as String];
          } else {
            _existingImageUrls = [];
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading listing: $e'),
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

  String _generateItemId() {
    // Generate a unique item ID using timestamp and random component
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = (timestamp % 10000).toString().padLeft(4, '0');
    return 'item_${timestamp}_$random';
  }

  Future<void> _pickImages(ImageSource source) async {
    try {
      if (source == ImageSource.gallery) {
        // Pick multiple images from gallery
        final List<XFile> pickedImages = await _picker.pickMultiImage();
        if (pickedImages.isNotEmpty) {
          setState(() {
            _selectedImages.addAll(pickedImages);
          });
        }
      } else {
        // Pick single image from camera
        final pickedImage = await _picker.pickImage(source: source);
        if (pickedImage != null) {
          setState(() {
            _selectedImages.add(pickedImage);
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _removeSelectedImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  void _removeExistingImage(int index) {
    setState(() {
      _existingImageUrls.removeAt(index);
    });
  }

  Future<List<String>> _uploadImages(String itemId) async {
    if (_selectedImages.isEmpty) return [];

    final List<String> uploadedUrls = [];
    try {
      setState(() => _uploadingImage = true);

      // Get userId for organized storage
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final userId = userProvider.currentUser?.uid;
      if (userId == null) {
        throw Exception('User not logged in');
      }

      for (int i = 0; i < _selectedImages.length; i++) {
        try {
          final imageUrl = await _storageService.uploadRentalImage(
            file: _selectedImages[i],
            listingId: itemId,
            userId: userId,
          );
          uploadedUrls.add(imageUrl);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to upload image ${i + 1}: $e'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }

      return uploadedUrls;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload images: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return uploadedUrls; // Return whatever was uploaded successfully
    } finally {
      if (mounted) {
        setState(() => _uploadingImage = false);
      }
    }
  }

  Widget _buildPageIndicator(bool isActive) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      height: 8,
      width: isActive ? 24 : 8,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF00897B) : Colors.grey[400],
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Widget _buildImagesSection() {
    final allImages = [
      ..._existingImageUrls.map((url) => {'type': 'url', 'url': url}),
      ..._selectedImages.map((img) => {'type': 'file', 'file': img}),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Item Images', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (allImages.isEmpty)
          Container(
            height: 200,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.image_outlined, size: 48, color: Colors.grey[400]),
                const SizedBox(height: 8),
                Text(
                  'No images selected',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
              ],
            ),
          )
        else ...[
          // Image Carousel
          Container(
            height: 300,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.grey[200],
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: PageView.builder(
                controller: _imagePageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentImageIndex = index;
                  });
                },
                itemCount: allImages.length,
                itemBuilder: (context, index) {
                  final imageData = allImages[index];
                  if (imageData['type'] == 'url') {
                    // Existing image from URL
                    return Stack(
                      children: [
                        CachedNetworkImage(
                          imageUrl: imageData['url'] as String,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          placeholder: (context, url) => Container(
                            color: Colors.grey[300],
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: Colors.grey[300],
                            child: const Icon(
                              Icons.broken_image_outlined,
                              color: Colors.red,
                              size: 48,
                            ),
                          ),
                        ),
                        // Remove button for existing images
                        Positioned(
                          top: 8,
                          right: 8,
                          child: GestureDetector(
                            onTap: () => _removeExistingImage(
                              _existingImageUrls.indexOf(
                                imageData['url'] as String,
                              ),
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                        // "Current" badge for existing images
                        Positioned(
                          bottom: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Current',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  } else {
                    // New selected image
                    final image = imageData['file'] as dynamic;
                    return Stack(
                      children: [
                        Builder(
                          builder: (context) {
                            if (image is XFile) {
                              return FutureBuilder<List<int>>(
                                future: image.readAsBytes(),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState ==
                                      ConnectionState.waiting) {
                                    return Container(
                                      color: Colors.grey[300],
                                      child: const Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    );
                                  }
                                  if (snapshot.hasError || !snapshot.hasData) {
                                    return Container(
                                      color: Colors.grey[300],
                                      child: const Icon(
                                        Icons.error_outline,
                                        color: Colors.red,
                                        size: 48,
                                      ),
                                    );
                                  }
                                  return Image.memory(
                                    Uint8List.fromList(snapshot.data!),
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                  );
                                },
                              );
                            } else if (image is File) {
                              return Image.file(
                                image,
                                fit: BoxFit.cover,
                                width: double.infinity,
                              );
                            } else {
                              return Container(
                                color: Colors.grey[300],
                                child: const Icon(
                                  Icons.error_outline,
                                  color: Colors.red,
                                  size: 48,
                                ),
                              );
                            }
                          },
                        ),
                        // Remove button for new images
                        Positioned(
                          top: 8,
                          right: 8,
                          child: GestureDetector(
                            onTap: () => _removeSelectedImage(
                              _selectedImages.indexOf(image),
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                        // "New" badge for selected images
                        Positioned(
                          bottom: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue[700]!,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'New',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                },
              ),
            ),
          ),
          if (allImages.length > 1) ...[
            const SizedBox(height: 12),
            // Page indicators (dots)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                allImages.length,
                (index) => _buildPageIndicator(index == _currentImageIndex),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                '${_currentImageIndex + 1} of ${allImages.length}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ),
          ],
          const SizedBox(height: 12),
          // Thumbnail grid below carousel
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: allImages.length,
              itemBuilder: (context, index) {
                final imageData = allImages[index];
                return GestureDetector(
                  onTap: () {
                    // Scroll to this image in PageView
                    _imagePageController.animateToPage(
                      index,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                  child: Container(
                    width: 80,
                    height: 80,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!, width: 2),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: imageData['type'] == 'url'
                          ? CachedNetworkImage(
                              imageUrl: imageData['url'] as String,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: Colors.grey[300],
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: Colors.grey[300],
                                child: const Icon(
                                  Icons.broken_image_outlined,
                                  color: Colors.red,
                                  size: 24,
                                ),
                              ),
                            )
                          : Builder(
                              builder: (context) {
                                final image = imageData['file'] as dynamic;
                                if (image is XFile) {
                                  return FutureBuilder<List<int>>(
                                    future: image.readAsBytes(),
                                    builder: (context, snapshot) {
                                      if (snapshot.hasData) {
                                        return Image.memory(
                                          Uint8List.fromList(snapshot.data!),
                                          fit: BoxFit.cover,
                                        );
                                      }
                                      return Container(
                                        color: Colors.grey[300],
                                        child: const Center(
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                } else if (image is File) {
                                  return Image.file(image, fit: BoxFit.cover);
                                } else {
                                  return Container(
                                    color: Colors.grey[300],
                                    child: const Icon(
                                      Icons.error_outline,
                                      color: Colors.red,
                                      size: 24,
                                    ),
                                  );
                                }
                              },
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _uploadingImage
                    ? null
                    : () => _pickImages(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: const Text('Add from Gallery'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _uploadingImage
                    ? null
                    : () => _pickImages(ImageSource.camera),
                icon: const Icon(Icons.camera_alt),
                label: const Text('Take Photo'),
              ),
            ),
          ],
        ),
        if (_uploadingImage) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
          const SizedBox(height: 4),
          Text(
            'Uploading images...',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RentalListingProvider>();
    final userProvider = context.watch<UserProvider>();

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            _isEditMode ? 'Edit Rental Listing' : 'Create Rental Listing',
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditMode ? 'Edit Rental Listing' : 'Create Rental Listing',
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // Rental Type dropdown
              DropdownButtonFormField<RentalType>(
                value: _rentType,
                decoration: const InputDecoration(
                  labelText: 'Rental Type *',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: RentalType.item, child: Text('Item')),
                  DropdownMenuItem(
                    value: RentalType.apartment,
                    child: Text('Apartment'),
                  ),
                  DropdownMenuItem(
                    value: RentalType.boardingHouse,
                    child: Text('Boarding House'),
                  ),
                  DropdownMenuItem(
                    value: RentalType.commercial,
                    child: Text('Commercial Space'),
                  ),
                ],
                validator: (v) =>
                    v == null ? 'Please select rental type' : null,
                onChanged: (v) {
                  final newType = v ?? RentalType.item;
                  setState(() {
                    _rentType = newType;
                    // Clear min/max days when switching to property rentals
                    if (newType == RentalType.apartment ||
                        newType == RentalType.boardingHouse ||
                        newType == RentalType.commercial) {
                      _minDaysCtrl.clear();
                      _maxDaysCtrl.clear();
                    }
                    // Clear boarding house specific fields when switching away from boarding house
                    if (newType != RentalType.boardingHouse) {
                      _selectedGenderPreference = null;
                      _occupantsPerRoomCtrl.clear();
                      _initialOccupantsCtrl.clear();
                    }
                  });
                },
              ),
              const SizedBox(height: 16),

              // Title field
              TextFormField(
                controller: _titleCtrl,
                decoration: InputDecoration(
                  labelText: _rentType == RentalType.item
                      ? 'Item Name *'
                      : _rentType == RentalType.apartment
                      ? 'Apartment Name *'
                      : _rentType == RentalType.boardingHouse
                      ? 'Boarding House Name *'
                      : 'Commercial Space Name *',
                  hintText: _rentType == RentalType.item
                      ? 'e.g., Camera, Drill, etc.'
                      : _rentType == RentalType.apartment
                      ? 'e.g., 2BR Apartment in Downtown'
                      : _rentType == RentalType.boardingHouse
                      ? 'e.g., Cozy Boarding House near University'
                      : 'e.g., Retail Space in Mall',
                  border: const OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Description/Condition field
              TextFormField(
                controller: _descriptionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Description / Condition *',
                  hintText: 'e.g., Slightly used camera, includes charger',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 3,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Description is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Category dropdown (only for items)
              if (_rentType == RentalType.item)
                DropdownButtonFormField<String>(
                  value: _selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Category *',
                    border: OutlineInputBorder(),
                  ),
                  items: _categories.map((category) {
                    return DropdownMenuItem(
                      value: category,
                      child: Text(category),
                    );
                  }).toList(),
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return 'Please select a category';
                    }
                    return null;
                  },
                  onChanged: (v) => setState(() => _selectedCategory = v),
                ),
              if (_rentType == RentalType.item) const SizedBox(height: 16),

              // Condition dropdown (only for items)
              if (_rentType == RentalType.item)
                DropdownButtonFormField<String>(
                  value: _selectedCondition,
                  decoration: const InputDecoration(
                    labelText: 'Condition *',
                    border: OutlineInputBorder(),
                  ),
                  items: _conditions.map((condition) {
                    return DropdownMenuItem(
                      value: condition,
                      child: Text(condition),
                    );
                  }).toList(),
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return 'Please select condition';
                    }
                    return null;
                  },
                  onChanged: (v) => setState(() => _selectedCondition = v),
                ),
              if (_rentType == RentalType.item) const SizedBox(height: 16),

              // Address field (for apartments, boarding houses, and commercial)
              if (_rentType == RentalType.apartment ||
                  _rentType == RentalType.boardingHouse ||
                  _rentType == RentalType.commercial)
                TextFormField(
                  controller: _addressCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Address *',
                    hintText: 'Full address (street, city, barangay)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                  validator: (v) {
                    if ((_rentType == RentalType.apartment ||
                            _rentType == RentalType.boardingHouse ||
                            _rentType == RentalType.commercial) &&
                        (v == null || v.trim().isEmpty)) {
                      return 'Address is required';
                    }
                    return null;
                  },
                ),
              if (_rentType == RentalType.apartment ||
                  _rentType == RentalType.boardingHouse ||
                  _rentType == RentalType.commercial)
                const SizedBox(height: 16),

              // Location field (only for items, not for property rentals)
              if (_rentType == RentalType.item) ...[
                TextFormField(
                  controller: _locationCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Location',
                    hintText: 'Optional location information',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Images upload section
              _buildImagesSection(),
              const SizedBox(height: 24),

              // Pricing Mode
              DropdownButtonFormField<PricingMode>(
                value: _mode,
                decoration: const InputDecoration(
                  labelText: 'Pricing Mode *',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: PricingMode.perDay,
                    child: Text('Per Day'),
                  ),
                  DropdownMenuItem(
                    value: PricingMode.perWeek,
                    child: Text('Per Week'),
                  ),
                  DropdownMenuItem(
                    value: PricingMode.perMonth,
                    child: Text('Per Month'),
                  ),
                ],
                validator: (v) =>
                    v == null ? 'Please select pricing mode' : null,
                onChanged: (v) =>
                    setState(() => _mode = v ?? PricingMode.perDay),
              ),
              const SizedBox(height: 16),

              // Price fields
              if (_mode == PricingMode.perDay)
                TextFormField(
                  controller: _pricePerDayCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Price Per Day *',
                    hintText: '0.00',
                    prefixText: '₱ ',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Price is required';
                    }
                    final price = double.tryParse(v.trim());
                    if (price == null || price <= 0) {
                      return 'Price must be greater than 0';
                    }
                    return null;
                  },
                ),
              if (_mode == PricingMode.perWeek)
                TextFormField(
                  controller: _pricePerWeekCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Price Per Week *',
                    hintText: '0.00',
                    prefixText: '₱ ',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Price is required';
                    }
                    final price = double.tryParse(v.trim());
                    if (price == null || price <= 0) {
                      return 'Price must be greater than 0';
                    }
                    return null;
                  },
                ),
              if (_mode == PricingMode.perMonth)
                TextFormField(
                  controller: _pricePerMonthCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Price Per Month *',
                    hintText: '0.00',
                    prefixText: '₱ ',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Price is required';
                    }
                    final price = double.tryParse(v.trim());
                    if (price == null || price <= 0) {
                      return 'Price must be greater than 0';
                    }
                    return null;
                  },
                ),
              const SizedBox(height: 16),

              // Min/Max Days (only for items, not for property rentals)
              if (_rentType == RentalType.item) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _minDaysCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Min Days',
                          hintText: '1',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          if (v != null && v.trim().isNotEmpty) {
                            final days = int.tryParse(v.trim());
                            if (days != null && days < 1) {
                              return 'Must be at least 1';
                            }
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _maxDaysCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Max Days',
                          hintText: '30',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          if (v != null && v.trim().isNotEmpty) {
                            final days = int.tryParse(v.trim());
                            if (days != null) {
                              if (days < 1) {
                                return 'Must be at least 1';
                              }
                              // Validate max >= min if both are provided
                              final minDays = int.tryParse(
                                _minDaysCtrl.text.trim(),
                              );
                              if (minDays != null && days < minDays) {
                                return 'Must be >= min days';
                              }
                            }
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // Security Deposit
              TextFormField(
                controller: _depositCtrl,
                decoration: const InputDecoration(
                  labelText: 'Security Deposit (optional)',
                  hintText: '0.00',
                  prefixText: '₱ ',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (v) {
                  if (v != null && v.trim().isNotEmpty) {
                    final deposit = double.tryParse(v.trim());
                    if (deposit != null && deposit < 0) {
                      return 'Deposit cannot be negative';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Fields for Items
              if (_rentType == RentalType.item) ...[
                // Allow Multiple Rentals (for items)
                SwitchListTile(
                  title: const Text('Allow Multiple Concurrent Rentals'),
                  subtitle: const Text(
                    'Enable for shared items where multiple renters can use the same listing simultaneously',
                  ),
                  value: _allowMultipleRentals,
                  onChanged: (v) => setState(() => _allowMultipleRentals = v),
                ),
                const SizedBox(height: 16),

                // Quantity (for items like clothes with multiple units)
                TextFormField(
                  controller: _quantityCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Quantity (optional)',
                    hintText: 'e.g., 5 (for 5 units of clothing)',
                    helperText:
                        'Leave empty for single item. Set quantity for items with multiple units (e.g., clothes, tools)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v != null && v.trim().isNotEmpty) {
                      final qty = int.tryParse(v.trim());
                      if (qty == null || qty < 1) {
                        return 'Quantity must be at least 1';
                      }
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
              ],

              // Fields for Apartments
              if (_rentType == RentalType.apartment) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _bedroomsCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Bedrooms *',
                          hintText: 'e.g., 2',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Bedrooms required';
                          }
                          final bedrooms = int.tryParse(v.trim());
                          if (bedrooms == null || bedrooms < 0) {
                            return 'Invalid number';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _bathroomsCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Bathrooms *',
                          hintText: 'e.g., 1',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Bathrooms required';
                          }
                          final bathrooms = int.tryParse(v.trim());
                          if (bathrooms == null || bathrooms < 0) {
                            return 'Invalid number';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _floorAreaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Floor Area (sqm) *',
                    hintText: 'e.g., 50.0',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Floor area required';
                    }
                    final area = double.tryParse(v.trim());
                    if (area == null || area <= 0) {
                      return 'Must be greater than 0';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Utilities Included'),
                  subtitle: const Text(
                    'Water, electricity, internet included in rent',
                  ),
                  value: _utilitiesIncluded,
                  onChanged: (v) => setState(() => _utilitiesIncluded = v),
                ),
                const SizedBox(height: 16),
              ],

              // Fields for Boarding Houses
              if (_rentType == RentalType.boardingHouse) ...[
                // Basic Capacity Information
                TextFormField(
                  controller: _numberOfRoomsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Number of Rooms *',
                    hintText: 'e.g., 5',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Number of rooms required';
                    }
                    final rooms = int.tryParse(v.trim());
                    if (rooms == null || rooms < 1) {
                      return 'Must be at least 1';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _maxOccupantsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Max Occupants *',
                    hintText: 'e.g., 10',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Max occupants required';
                    }
                    final max = int.tryParse(v.trim());
                    if (max == null || max < 1) {
                      return 'Must be at least 1';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _occupantsPerRoomCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Occupants per Room (optional)',
                    hintText: 'e.g., 2',
                    border: OutlineInputBorder(),
                    helperText: 'Standard number of occupants per room',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v != null && v.trim().isNotEmpty) {
                      final occupants = int.tryParse(v.trim());
                      if (occupants == null || occupants < 1) {
                        return 'Must be at least 1';
                      }
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // Pre-existing Occupancy
                TextFormField(
                  controller: _initialOccupantsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Pre-existing Occupants (optional)',
                    hintText: 'e.g., 5',
                    border: OutlineInputBorder(),
                    helperText:
                        'Number of occupants already in the boarding house before listing',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v != null && v.trim().isNotEmpty) {
                      final occupants = int.tryParse(v.trim());
                      if (occupants == null || occupants < 0) {
                        return 'Must be 0 or greater';
                      }
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // Preferences
                DropdownButtonFormField<String>(
                  value: _selectedGenderPreference,
                  decoration: const InputDecoration(
                    labelText: 'Gender Preference *',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Any', child: Text('Any')),
                    DropdownMenuItem(value: 'Male', child: Text('Male Only')),
                    DropdownMenuItem(
                      value: 'Female',
                      child: Text('Female Only'),
                    ),
                    DropdownMenuItem(
                      value: 'Mixed',
                      child: Text('Mixed (Male & Female)'),
                    ),
                  ],
                  validator: (v) =>
                      v == null ? 'Please select gender preference' : null,
                  onChanged: (v) =>
                      setState(() => _selectedGenderPreference = v),
                ),
                const SizedBox(height: 16),
                // Features
                SwitchListTile(
                  title: const Text('Shared Comfort Room'),
                  subtitle: const Text('Bathroom is shared among occupants'),
                  value: _sharedCR,
                  onChanged: (v) => setState(() => _sharedCR = v),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Bed Space Available'),
                  subtitle: const Text('Individual bed spaces are available'),
                  value: _bedSpaceAvailable,
                  onChanged: (v) => setState(() => _bedSpaceAvailable = v),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Utilities Included'),
                  subtitle: const Text(
                    'Water, electricity, internet included in rent',
                  ),
                  value: _utilitiesIncluded,
                  onChanged: (v) => setState(() => _utilitiesIncluded = v),
                ),
                const SizedBox(height: 16),
                // Rules
                TextFormField(
                  controller: _curfewRulesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Curfew Rules (optional)',
                    hintText: 'e.g., No entry after 10 PM',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
              ],

              // Fields for Commercial Spaces
              if (_rentType == RentalType.commercial) ...[
                TextFormField(
                  controller: _floorAreaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Floor Area (sqm) *',
                    hintText: 'e.g., 100.0',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Floor area required';
                    }
                    final area = double.tryParse(v.trim());
                    if (area == null || area <= 0) {
                      return 'Must be greater than 0';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _allowedBusinessCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Allowed Business Type',
                    hintText: 'e.g., Retail, Restaurant, Office, etc.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _leaseTermCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Lease Term (months)',
                    hintText: 'e.g., 12',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v != null && v.trim().isNotEmpty) {
                      final term = int.tryParse(v.trim());
                      if (term == null || term < 1) {
                        return 'Must be at least 1 month';
                      }
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
              ],

              // Active switch
              SwitchListTile(
                title: const Text('Active'),
                subtitle: const Text('Listing will be visible to renters'),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
              ),
              const SizedBox(height: 24),

              // Save button
              ElevatedButton(
                onPressed: (provider.isLoading || _uploadingImage)
                    ? null
                    : () async {
                        if (!_formKey.currentState!.validate()) {
                          return;
                        }

                        final ownerId = userProvider.currentUser?.uid ?? '';
                        final ownerName =
                            userProvider.currentUser?.fullName ?? '';

                        if (ownerId.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Please log in to create a listing',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }

                        if (_isEditMode && _listingId != null) {
                          // Edit mode - update existing listing
                          List<String> allImageUrls = List.from(
                            _existingImageUrls,
                          );
                          if (_selectedImages.isNotEmpty) {
                            // Upload new images
                            final itemId = _itemId ?? _generateItemId();
                            final uploadedUrls = await _uploadImages(itemId);
                            if (uploadedUrls.isEmpty &&
                                _existingImageUrls.isEmpty &&
                                mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Failed to upload images. Please try again.',
                                  ),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              return;
                            }
                            allImageUrls.addAll(uploadedUrls);
                          }

                          // Get location with fallback to user's registration address for items
                          String? locationValue;
                          final locationText = _locationCtrl.text.trim();
                          if (locationText.isNotEmpty) {
                            locationValue = locationText;
                          } else if (_rentType == RentalType.item) {
                            // Use user's registration address as fallback for items
                            locationValue =
                                userProvider.currentUser?.fullAddress;
                          }

                          final success = await provider.updateListing(
                            listingId: _listingId!,
                            title: _titleCtrl.text.trim(),
                            description: _descriptionCtrl.text.trim(),
                            condition: _selectedCondition,
                            category: _selectedCategory,
                            location: locationValue,
                            imageUrl: allImageUrls.isNotEmpty
                                ? allImageUrls.first
                                : null,
                            images: allImageUrls,
                            pricingMode: _mode,
                            pricePerDay: _mode == PricingMode.perDay
                                ? double.tryParse(_pricePerDayCtrl.text.trim())
                                : null,
                            pricePerWeek: _mode == PricingMode.perWeek
                                ? double.tryParse(_pricePerWeekCtrl.text.trim())
                                : null,
                            pricePerMonth: _mode == PricingMode.perMonth
                                ? double.tryParse(
                                    _pricePerMonthCtrl.text.trim(),
                                  )
                                : null,
                            minDays:
                                (_rentType == RentalType.apartment ||
                                    _rentType == RentalType.boardingHouse ||
                                    _rentType == RentalType.commercial)
                                ? null
                                : (_minDaysCtrl.text.trim().isEmpty
                                      ? null
                                      : int.tryParse(_minDaysCtrl.text.trim())),
                            maxDays:
                                (_rentType == RentalType.apartment ||
                                    _rentType == RentalType.boardingHouse ||
                                    _rentType == RentalType.commercial)
                                ? null
                                : (_maxDaysCtrl.text.trim().isEmpty
                                      ? null
                                      : int.tryParse(_maxDaysCtrl.text.trim())),
                            securityDeposit: _depositCtrl.text.trim().isEmpty
                                ? null
                                : double.tryParse(_depositCtrl.text.trim()),
                            isActive: _isActive,
                            allowMultipleRentals: _allowMultipleRentals,
                            quantity: _quantityCtrl.text.trim().isEmpty
                                ? null
                                : int.tryParse(_quantityCtrl.text.trim()),
                            rentType: _rentType,
                            bedrooms: _bedroomsCtrl.text.trim().isEmpty
                                ? null
                                : int.tryParse(_bedroomsCtrl.text.trim()),
                            bathrooms: _bathroomsCtrl.text.trim().isEmpty
                                ? null
                                : int.tryParse(_bathroomsCtrl.text.trim()),
                            floorArea: _floorAreaCtrl.text.trim().isEmpty
                                ? null
                                : double.tryParse(_floorAreaCtrl.text.trim()),
                            utilitiesIncluded:
                                (_rentType == RentalType.apartment ||
                                    _rentType == RentalType.boardingHouse)
                                ? _utilitiesIncluded
                                : null,
                            address: _addressCtrl.text.trim().isEmpty
                                ? null
                                : _addressCtrl.text.trim(),
                            allowedBusiness:
                                _allowedBusinessCtrl.text.trim().isEmpty
                                ? null
                                : _allowedBusinessCtrl.text.trim(),
                            leaseTerm: _leaseTermCtrl.text.trim().isEmpty
                                ? null
                                : int.tryParse(_leaseTermCtrl.text.trim()),
                            sharedCR: _rentType == RentalType.boardingHouse
                                ? _sharedCR
                                : null,
                            bedSpaceAvailable:
                                _rentType == RentalType.boardingHouse
                                ? _bedSpaceAvailable
                                : null,
                            maxOccupants:
                                _rentType == RentalType.boardingHouse &&
                                    _maxOccupantsCtrl.text.trim().isNotEmpty
                                ? int.tryParse(_maxOccupantsCtrl.text.trim())
                                : null,
                            numberOfRooms:
                                _rentType == RentalType.boardingHouse &&
                                    _numberOfRoomsCtrl.text.trim().isNotEmpty
                                ? int.tryParse(_numberOfRoomsCtrl.text.trim())
                                : null,
                            occupantsPerRoom:
                                _rentType == RentalType.boardingHouse &&
                                    _occupantsPerRoomCtrl.text.trim().isNotEmpty
                                ? int.tryParse(
                                    _occupantsPerRoomCtrl.text.trim(),
                                  )
                                : null,
                            genderPreference:
                                _rentType == RentalType.boardingHouse
                                ? _selectedGenderPreference
                                : null,
                            curfewRules:
                                _rentType == RentalType.boardingHouse &&
                                    _curfewRulesCtrl.text.trim().isNotEmpty
                                ? _curfewRulesCtrl.text.trim()
                                : null,
                            initialOccupants:
                                _rentType == RentalType.boardingHouse &&
                                    _initialOccupantsCtrl.text.trim().isNotEmpty
                                ? int.tryParse(
                                    _initialOccupantsCtrl.text.trim(),
                                  )
                                : null,
                          );

                          if (!mounted) return;

                          if (success) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Rental listing updated successfully!',
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                            Navigator.pop(context);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  provider.errorMessage ??
                                      'Failed to update listing',
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        } else {
                          // Create mode - create new listing
                          final itemId = _generateItemId();

                          // Upload images if selected
                          List<String> imageUrls = [];
                          if (_selectedImages.isNotEmpty) {
                            imageUrls = await _uploadImages(itemId);
                            if (imageUrls.isEmpty && mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Failed to upload images. Please try again.',
                                  ),
                                  backgroundColor: Colors.red,
                                ),
                              );
                              return;
                            }
                          }

                          // Get location with fallback to user's registration address for items
                          String? locationValue;
                          final locationText = _locationCtrl.text.trim();
                          if (locationText.isNotEmpty) {
                            locationValue = locationText;
                          } else if (_rentType == RentalType.item) {
                            // Use user's registration address as fallback for items
                            locationValue =
                                userProvider.currentUser?.fullAddress;
                          }

                          final id = await provider.createListing(
                            itemId: itemId,
                            ownerId: ownerId,
                            ownerName: ownerName,
                            title: _titleCtrl.text.trim(),
                            description: _descriptionCtrl.text.trim(),
                            condition: _selectedCondition,
                            category: _selectedCategory,
                            location: locationValue,
                            imageUrl: imageUrls.isNotEmpty
                                ? imageUrls.first
                                : null,
                            images: imageUrls,
                            pricingMode: _mode,
                            pricePerDay: _mode == PricingMode.perDay
                                ? double.tryParse(_pricePerDayCtrl.text.trim())
                                : null,
                            pricePerWeek: _mode == PricingMode.perWeek
                                ? double.tryParse(_pricePerWeekCtrl.text.trim())
                                : null,
                            pricePerMonth: _mode == PricingMode.perMonth
                                ? double.tryParse(
                                    _pricePerMonthCtrl.text.trim(),
                                  )
                                : null,
                            minDays:
                                (_rentType == RentalType.apartment ||
                                    _rentType == RentalType.boardingHouse ||
                                    _rentType == RentalType.commercial)
                                ? null
                                : (_minDaysCtrl.text.trim().isEmpty
                                      ? null
                                      : int.tryParse(_minDaysCtrl.text.trim())),
                            maxDays:
                                (_rentType == RentalType.apartment ||
                                    _rentType == RentalType.boardingHouse ||
                                    _rentType == RentalType.commercial)
                                ? null
                                : (_maxDaysCtrl.text.trim().isEmpty
                                      ? null
                                      : int.tryParse(_maxDaysCtrl.text.trim())),
                            securityDeposit: _depositCtrl.text.trim().isEmpty
                                ? null
                                : double.tryParse(_depositCtrl.text.trim()),
                            isActive: _isActive,
                            allowMultipleRentals: _allowMultipleRentals,
                            quantity: _quantityCtrl.text.trim().isEmpty
                                ? null
                                : int.tryParse(_quantityCtrl.text.trim()),
                            rentType: _rentType,
                            bedrooms: _bedroomsCtrl.text.trim().isEmpty
                                ? null
                                : int.tryParse(_bedroomsCtrl.text.trim()),
                            bathrooms: _bathroomsCtrl.text.trim().isEmpty
                                ? null
                                : int.tryParse(_bathroomsCtrl.text.trim()),
                            floorArea: _floorAreaCtrl.text.trim().isEmpty
                                ? null
                                : double.tryParse(_floorAreaCtrl.text.trim()),
                            utilitiesIncluded:
                                (_rentType == RentalType.apartment ||
                                    _rentType == RentalType.boardingHouse)
                                ? _utilitiesIncluded
                                : null,
                            address: _addressCtrl.text.trim().isEmpty
                                ? null
                                : _addressCtrl.text.trim(),
                            allowedBusiness:
                                _allowedBusinessCtrl.text.trim().isEmpty
                                ? null
                                : _allowedBusinessCtrl.text.trim(),
                            leaseTerm: _leaseTermCtrl.text.trim().isEmpty
                                ? null
                                : int.tryParse(_leaseTermCtrl.text.trim()),
                            sharedCR: _rentType == RentalType.boardingHouse
                                ? _sharedCR
                                : null,
                            bedSpaceAvailable:
                                _rentType == RentalType.boardingHouse
                                ? _bedSpaceAvailable
                                : null,
                            maxOccupants:
                                _rentType == RentalType.boardingHouse &&
                                    _maxOccupantsCtrl.text.trim().isNotEmpty
                                ? int.tryParse(_maxOccupantsCtrl.text.trim())
                                : null,
                            numberOfRooms:
                                _rentType == RentalType.boardingHouse &&
                                    _numberOfRoomsCtrl.text.trim().isNotEmpty
                                ? int.tryParse(_numberOfRoomsCtrl.text.trim())
                                : null,
                            occupantsPerRoom:
                                _rentType == RentalType.boardingHouse &&
                                    _occupantsPerRoomCtrl.text.trim().isNotEmpty
                                ? int.tryParse(
                                    _occupantsPerRoomCtrl.text.trim(),
                                  )
                                : null,
                            genderPreference:
                                _rentType == RentalType.boardingHouse
                                ? _selectedGenderPreference
                                : null,
                            curfewRules:
                                _rentType == RentalType.boardingHouse &&
                                    _curfewRulesCtrl.text.trim().isNotEmpty
                                ? _curfewRulesCtrl.text.trim()
                                : null,
                            initialOccupants:
                                _rentType == RentalType.boardingHouse &&
                                    _initialOccupantsCtrl.text.trim().isNotEmpty
                                ? int.tryParse(
                                    _initialOccupantsCtrl.text.trim(),
                                  )
                                : null,
                          );

                          if (!mounted) return;

                          if (id != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Rental listing created successfully!',
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                            Navigator.pop(context);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  provider.errorMessage ??
                                      'Failed to create listing',
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: const Color(0xFF00897B),
                  foregroundColor: Colors.white,
                ),
                child: (provider.isLoading || _uploadingImage)
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
                        _isEditMode ? 'Update Listing' : 'Save Listing',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
