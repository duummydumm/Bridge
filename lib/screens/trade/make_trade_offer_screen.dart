import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/trade_item_model.dart';
import '../../models/trade_offer_model.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../providers/user_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';

class MakeTradeOfferScreen extends StatefulWidget {
  const MakeTradeOfferScreen({super.key});

  @override
  State<MakeTradeOfferScreen> createState() => _MakeTradeOfferScreenState();
}

class _MakeTradeOfferScreenState extends State<MakeTradeOfferScreen> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();
  final ValueNotifier<String> _progressText = ValueNotifier<String>('');
  bool _submitting = false;

  final FirestoreService _firestore = FirestoreService();
  final StorageService _storage = StorageService();

  TradeItemModel? _tradeItem;
  bool _loading = true;
  String? _error;

  // Edit / counter-offer support
  bool _initialized = false;
  String? _offerId;
  TradeOfferModel? _existingOffer;
  String? _existingOfferedImageUrl;
  bool _isCounter = false;
  String? _counterToUserId;
  String? _counterToUserName;
  String? _parentOfferId;

  // Form controllers
  final _itemNameController = TextEditingController();
  final _itemDescriptionController = TextEditingController();
  final _messageController = TextEditingController();

  dynamic _selectedImage;

  // BRIDGE Trade theme color
  static const Color _primaryColor = Color(0xFF2A7A9E);
  static const Color _textColor = Color(0xFF333333);

  @override
  void dispose() {
    _itemNameController.dispose();
    _itemDescriptionController.dispose();
    _messageController.dispose();
    _progressText.dispose();
    super.dispose();
  }

  bool _isMatched = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['tradeItemId'] is String) {
      // Check if this is a matched trade (pre-filled data)
      if (args['isMatched'] == 'true') {
        _isMatched = true;
        // Pre-fill form with matched item data
        if (args['matchedItemName'] != null) {
          _itemNameController.text = args['matchedItemName'] as String;
        }
        if (args['matchedItemDescription'] != null) {
          _itemDescriptionController.text =
              args['matchedItemDescription'] as String;
        }
        // Pre-load image if available
        if (args['matchedItemImageUrls'] != null) {
          final imageUrls = args['matchedItemImageUrls'] as List<dynamic>;
          if (imageUrls.isNotEmpty) {
            // Note: We can't directly load network images into the picker,
            // but we can show a note that the image is already available
            // The user can still pick a new image if needed
          }
        }
      }

      // Check if we're editing an existing offer
      if (args['offerId'] is String) {
        _offerId = args['offerId'] as String;
      }

      // Counter-offer mode (listing owner responding back)
      if (args['isCounter'] == 'true') {
        _isCounter = true;
        if (args['counterToUserId'] is String) {
          _counterToUserId = args['counterToUserId'] as String;
        }
        if (args['counterToUserName'] is String) {
          _counterToUserName = args['counterToUserName'] as String;
        }
        if (args['parentOfferId'] is String) {
          _parentOfferId = args['parentOfferId'] as String;
        }
      }

      _loadTradeItem(args['tradeItemId'] as String).then((_) {
        if (_offerId != null) {
          _loadExistingOffer(_offerId!);
        }
      });
    } else if (_loading) {
      setState(() {
        _error = 'Missing tradeItemId in route arguments';
        _loading = false;
      });
    }
  }

  Future<void> _loadTradeItem(String tradeItemId) async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });
      final data = await _firestore.getTradeItem(tradeItemId);
      if (data == null) {
        setState(() {
          _error = 'Trade listing not found';
          _loading = false;
        });
        return;
      }
      setState(() {
        _tradeItem = TradeItemModel.fromMap(data, data['id'] as String);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadExistingOffer(String offerId) async {
    try {
      final data = await _firestore.getTradeOffer(offerId);
      if (data == null) return;

      final offer = TradeOfferModel.fromMap(data, offerId);

      // Only pending offers can be edited
      if (!offer.isPending) return;

      setState(() {
        _existingOffer = offer;
        _itemNameController.text = offer.offeredItemName;
        _itemDescriptionController.text = offer.offeredItemDescription ?? '';
        _messageController.text = offer.message ?? '';
        _existingOfferedImageUrl = offer.offeredItemImageUrl;
      });
    } catch (_) {
      // Silent fail – editing is best-effort
    }
  }

  Future<void> _pickImage() async {
    try {
      final dynamic pickedImage = await _picker.pickImage(
        source: ImageSource.gallery,
      );
      if (pickedImage != null) {
        setState(() {
          _selectedImage = pickedImage;
        });
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

  void _removeImage() {
    setState(() {
      _selectedImage = null;
    });
  }

  void _removeExistingImage() {
    setState(() {
      _existingOfferedImageUrl = null;
    });
  }

  Widget _buildImagePreview() {
    return Stack(
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
            color: Colors.grey[100],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Builder(
              builder: (context) {
                if (kIsWeb && _selectedImage is XFile) {
                  return FutureBuilder<List<int>>(
                    future: (_selectedImage as XFile).readAsBytes(),
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
                  try {
                    final filePath = _selectedImage is File
                        ? (_selectedImage as File).path
                        : (_selectedImage as XFile).path;
                    return Image.file(
                      File(filePath),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
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
            onTap: _removeImage,
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

  Widget _buildExistingImagePreview() {
    if (_existingOfferedImageUrl == null || _existingOfferedImageUrl!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
            color: Colors.grey[100],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              _existingOfferedImageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: Colors.grey[300],
                  child: const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.red,
                  ),
                );
              },
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: _removeExistingImage,
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

  Future<void> _submitOffer() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;
    if (_tradeItem == null) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final currentUser = userProvider.currentUser;
    final currentAuthUser = authProvider.user;

    if (currentUser == null || currentAuthUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to make an offer')),
      );
      return;
    }

    // Prevent users from making offers on their own listings (only for new offers, not counters)
    if (_offerId == null &&
        !_isCounter &&
        _tradeItem!.offeredBy == currentUser.uid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You cannot make an offer on your own listing'),
          backgroundColor: Colors.red,
        ),
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
                  text.isEmpty ? 'Submitting offer…' : text,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      _progressText.value = 'Uploading image…';

      // Upload image if selected; otherwise keep existing image (for edit mode)
      String? imageUrl = _existingOfferedImageUrl;
      if (_selectedImage != null) {
        try {
          final tempOfferId = DateTime.now().millisecondsSinceEpoch.toString();
          final userId = currentUser.uid;
          Uint8List compressedBytes = await _compressImage(_selectedImage);
          try {
            imageUrl = await _storage
                .uploadTradeImageBytes(
                  bytes: compressedBytes,
                  itemId: tempOfferId,
                  userId: userId,
                  cacheControl: 'public, max-age=3600',
                )
                .timeout(const Duration(seconds: 45));
          } catch (e) {
            // Retry with smaller target
            compressedBytes = await _compressImage(
              _selectedImage,
              targetBytes: 400 * 1024,
            );
            try {
              imageUrl = await _storage
                  .uploadTradeImageBytes(
                    bytes: compressedBytes,
                    itemId: tempOfferId,
                    userId: userId,
                    cacheControl: 'public, max-age=3600',
                  )
                  .timeout(const Duration(seconds: 45));
            } catch (e2) {
              // Final attempt with very small size
              compressedBytes = await _compressImage(
                _selectedImage,
                targetBytes: 256 * 1024,
              );
              imageUrl = await _storage
                  .uploadTradeImageBytes(
                    bytes: compressedBytes,
                    itemId: tempOfferId,
                    userId: userId,
                    cacheControl: 'public, max-age=3600',
                  )
                  .timeout(const Duration(seconds: 45));
            }
          }
        } catch (e) {
          if (mounted) {
            Navigator.pop(context); // Close loading dialog
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to upload image: $e'),
                backgroundColor: Colors.red,
              ),
            );
            _submitting = false;
            return;
          }
        }
      }

      _progressText.value = _offerId == null
          ? 'Creating offer…'
          : 'Updating offer…';

      // Get the listing owner's info
      final listingOwnerData = await _firestore.getUser(_tradeItem!.offeredBy);
      final listingOwnerName = listingOwnerData != null
          ? '${listingOwnerData['firstName']} ${listingOwnerData['lastName']}'
          : 'Unknown User';

      if (_offerId != null &&
          _existingOffer != null &&
          _existingOffer!.isPending) {
        // Edit existing pending offer
        await _firestore.updateTradeOffer(_offerId!, {
          'offeredItemName': _itemNameController.text.trim(),
          'offeredItemImageUrl': imageUrl,
          'offeredItemDescription': _itemDescriptionController.text.trim(),
          'message': _messageController.text.trim().isNotEmpty
              ? _messageController.text.trim()
              : null,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        if (mounted) {
          Navigator.pop(context); // Close loading dialog
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Trade offer updated successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context); // Return to previous screen
        }
      } else {
        // Create new trade offer (normal or counter)
        final toUserId =
            _isCounter &&
                _counterToUserId != null &&
                _counterToUserId!.isNotEmpty
            ? _counterToUserId!
            : _tradeItem!.offeredBy;
        final toUserName =
            _isCounter &&
                _counterToUserName != null &&
                _counterToUserName!.isNotEmpty
            ? _counterToUserName!
            : listingOwnerName;

        final offerData = {
          'tradeItemId': _tradeItem!.id,
          'fromUserId': currentUser.uid,
          'fromUserName': currentUser.fullName,
          'toUserId': toUserId,
          'toUserName': toUserName,
          'offeredItemName': _itemNameController.text.trim(),
          'offeredItemImageUrl': imageUrl,
          'offeredItemDescription': _itemDescriptionController.text.trim(),
          'originalOfferedItemName': _tradeItem!.offeredItemName,
          'originalOfferedItemImageUrl': _tradeItem!.offeredImageUrls.isNotEmpty
              ? _tradeItem!.offeredImageUrls.first
              : null,
          'message': _messageController.text.trim().isNotEmpty
              ? _messageController.text.trim()
              : null,
          if (_isCounter) 'isCounter': true,
          if (_isCounter && _parentOfferId != null)
            'parentOfferId': _parentOfferId,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        };

        await _firestore.createTradeOffer(offerData);

        // After creating the trade offer, seed a chat so both parties can communicate
        try {
          final chatProvider = Provider.of<ChatProvider>(
            context,
            listen: false,
          );

          // Get item title
          final itemTitle = _tradeItem!.offeredItemName;

          // Get image URL
          String? listingImageUrl;
          if (_tradeItem!.offeredImageUrls.isNotEmpty) {
            listingImageUrl = _tradeItem!.offeredImageUrls.first;
          }

          // Create or get conversation
          final conversationId = await chatProvider.createOrGetConversation(
            userId1: currentUser.uid,
            userId1Name: currentUser.fullName,
            userId2: toUserId,
            userId2Name: toUserName,
            itemId: _tradeItem!.id,
            itemTitle: itemTitle,
          );

          if (conversationId != null) {
            // Seed default message with optional first image of the item
            final String content = 'I want to offer your trade: $itemTitle';
            await chatProvider.sendMessage(
              conversationId: conversationId,
              senderId: currentUser.uid,
              senderName: currentUser.fullName,
              content: content,
              imageUrl: listingImageUrl,
            );
          }
        } catch (_) {
          // best-effort; failure to seed chat shouldn't block the offer
        }

        if (mounted) {
          Navigator.pop(context); // Close loading dialog
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Trade offer submitted successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context); // Return to previous screen
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit offer: $e'),
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
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Make Trade Offer',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Go Back'),
                    ),
                  ],
                ),
              ),
            )
          : _tradeItem == null
          ? const Center(child: Text('Trade listing not found'))
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Section: What you're trading for
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
                              Icon(Icons.info_outline, color: _primaryColor),
                              const SizedBox(width: 8),
                              Text(
                                'You\'re Trading For',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: _textColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Item image
                          if (_tradeItem!.hasImage &&
                              _tradeItem!.offeredImageUrls.isNotEmpty)
                            Container(
                              height: 150,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: Colors.grey[200],
                                image: DecorationImage(
                                  image: NetworkImage(
                                    _tradeItem!.offeredImageUrls.first,
                                  ),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                          Text(
                            _tradeItem!.offeredItemName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              _tradeItem!.offeredCategory,
                              style: TextStyle(
                                color: _primaryColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _tradeItem!.offeredDescription,
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Section: What you're offering
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
                              Expanded(
                                child: Text(
                                  'What You\'re Offering',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: _textColor,
                                  ),
                                ),
                              ),
                              if (_isMatched)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.green,
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.auto_awesome,
                                        size: 14,
                                        color: Colors.green[700],
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '100% Match',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.green[700],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          if (_isMatched) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.blue.withOpacity(0.2),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    size: 16,
                                    color: Colors.blue[700],
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'This is a perfect match! Your item details are pre-filled.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.blue[900],
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),

                          // Item Name
                          TextFormField(
                            controller: _itemNameController,
                            readOnly: _isMatched,
                            decoration: InputDecoration(
                              labelText: 'Item Name *',
                              hintText: 'Enter the name of your item',
                              filled: true,
                              fillColor: _isMatched
                                  ? Colors.grey[100]
                                  : Colors.white,
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

                          // Description/Condition
                          TextFormField(
                            controller: _itemDescriptionController,
                            readOnly: _isMatched,
                            maxLines: 4,
                            decoration: InputDecoration(
                              labelText: 'Description / Condition *',
                              hintText:
                                  'Describe your item and its condition...',
                              filled: true,
                              fillColor: _isMatched
                                  ? Colors.grey[100]
                                  : Colors.white,
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
                            'Item Photo (Optional)',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _textColor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_selectedImage != null)
                            _buildImagePreview()
                          else if (_existingOfferedImageUrl != null &&
                              _existingOfferedImageUrl!.isNotEmpty)
                            _buildExistingImagePreview()
                          else
                            OutlinedButton.icon(
                              onPressed: _pickImage,
                              icon: const Icon(Icons.add_photo_alternate),
                              label: const Text('Upload Item Photo'),
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
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Section: Message
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
                              Icon(Icons.message, color: _primaryColor),
                              const SizedBox(width: 8),
                              Text(
                                'Message (Optional)',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: _textColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _messageController,
                            maxLines: 3,
                            decoration: InputDecoration(
                              hintText: 'Add a message to the trade owner...',
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
                          onPressed: _submitting ? null : _submitOffer,
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
                                  'Submit Offer',
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
