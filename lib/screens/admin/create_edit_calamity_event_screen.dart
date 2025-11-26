import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../providers/calamity_provider.dart';
import '../../models/calamity_event_model.dart';
import '../../services/storage_service.dart';

class CreateEditCalamityEventScreen extends StatefulWidget {
  final CalamityEventModel? event;

  const CreateEditCalamityEventScreen({super.key, this.event});

  @override
  State<CreateEditCalamityEventScreen> createState() =>
      _CreateEditCalamityEventScreenState();

  /// Show as a dialog (for web platform)
  static Future<void> show(
    BuildContext context, {
    CalamityEventModel? event,
  }) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CreateEditCalamityEventScreen(event: event),
    );
  }
}

class _CreateEditCalamityEventScreenState
    extends State<CreateEditCalamityEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _dropoffLocationController =
      TextEditingController();
  // Predefined calamity types
  static const List<String> _calamityTypes = [
    'Typhoon',
    'Flood',
    'Earthquake',
    'Fire',
    'Landslide',
    'Drought',
    'Volcanic Eruption',
    'Tsunami',
    'Other',
  ];

  // Predefined needed items options
  static const List<String> _neededItemsOptions = [
    'Water',
    'Food Packs',
    'Canned Goods',
    'Clothes',
    'Blankets',
    'Hygiene Kits',
    'Medicine',
    'Baby Supplies',
    'Powerbanks',
    'Flashlights',
    'Slippers',
  ];
  final ValueNotifier<String> _progressText = ValueNotifier<String>('');

  String? _selectedCalamityType;
  List<String> _neededItems = [];
  DateTime? _selectedDeadline;
  String? _bannerUrl;
  XFile? _selectedBanner;
  bool _submitting = false;

  static const Color _primaryColor = Color(0xFF2A7A9E);

  @override
  void initState() {
    super.initState();
    if (widget.event != null) {
      _titleController.text = widget.event!.title;
      _descriptionController.text = widget.event!.description;
      _dropoffLocationController.text = widget.event!.dropoffLocation;
      _selectedCalamityType = widget.event!.calamityType;
      _neededItems = List.from(widget.event!.neededItems);
      _selectedDeadline = widget.event!.deadline;
      _bannerUrl = widget.event!.bannerUrl;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _dropoffLocationController.dispose();
    _progressText.dispose();
    super.dispose();
  }

  Future<void> _pickBanner() async {
    try {
      final XFile? pickedImage = await _picker.pickImage(
        source: ImageSource.gallery,
      );
      if (pickedImage != null) {
        setState(() {
          _selectedBanner = pickedImage;
          _bannerUrl = null; // Clear old URL when new image is selected
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

  Future<Uint8List> _compressImage(
    dynamic image, {
    int targetBytes = 800 * 1024,
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
      if (decoded == null) return inputBytes;

      const int maxDimension = 1920;
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

  Future<void> _submitEvent() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCalamityType == null || _selectedCalamityType!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a calamity type'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_neededItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one needed item'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_selectedDeadline == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a deadline'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final provider = Provider.of<CalamityProvider>(context, listen: false);
    final storageService = StorageService();

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
                  text.isEmpty ? 'Processing…' : text,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      String? finalBannerUrl = _bannerUrl;

      // Upload banner if new image selected
      if (_selectedBanner != null) {
        _progressText.value = 'Uploading banner image…';
        try {
          final compressedBytes = await _compressImage(_selectedBanner!);
          final tempEventId =
              widget.event?.eventId ??
              DateTime.now().millisecondsSinceEpoch.toString();
          finalBannerUrl = await storageService
              .uploadItemImageBytes(
                bytes: compressedBytes,
                itemId: 'banner-$tempEventId',
                userId: 'admin',
                listingType: 'donate',
                cacheControl: 'public, max-age=3600',
              )
              .timeout(const Duration(seconds: 45));
        } catch (e) {
          if (mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to upload banner: $e'),
                backgroundColor: Colors.red,
              ),
            );
            _submitting = false;
            return;
          }
        }
      }

      if (finalBannerUrl == null || finalBannerUrl.isEmpty) {
        throw Exception('Banner image is required');
      }

      _progressText.value = 'Saving event…';

      if (widget.event != null) {
        // Update existing event
        final success = await provider.updateCalamityEvent(
          eventId: widget.event!.eventId,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          bannerUrl: finalBannerUrl,
          calamityType: _selectedCalamityType!,
          neededItems: _neededItems,
          dropoffLocation: _dropoffLocationController.text.trim(),
          deadline: _selectedDeadline!,
        );

        if (mounted) {
          Navigator.pop(context);
          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Event updated successfully!'),
                backgroundColor: Colors.green,
              ),
            );
            if (mounted) {
              Navigator.of(context).pop();
            }
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Failed to update event: ${provider.errorMessage}',
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } else {
        // Create new event
        final eventId = await provider.createCalamityEvent(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          bannerUrl: finalBannerUrl,
          calamityType: _selectedCalamityType!,
          neededItems: _neededItems,
          dropoffLocation: _dropoffLocationController.text.trim(),
          deadline: _selectedDeadline!,
        );

        if (mounted) {
          Navigator.pop(context);
          if (eventId != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Event created successfully!'),
                backgroundColor: Colors.green,
              ),
            );
            if (mounted) {
              Navigator.of(context).pop();
            }
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Failed to create event: ${provider.errorMessage}',
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      _submitting = false;
    }
  }

  Future<void> _selectDeadline() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate:
          _selectedDeadline ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      final TimeOfDay? time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );
      if (time != null) {
        setState(() {
          _selectedDeadline = DateTime(
            picked.year,
            picked.month,
            picked.day,
            time.hour,
            time.minute,
          );
        });
      }
    }
  }

  void _toggleNeededItem(String item) {
    setState(() {
      if (_neededItems.contains(item)) {
        _neededItems.remove(item);
      } else {
        _neededItems.add(item);
      }
    });
  }

  String _formatDeadline(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final amPm = date.hour < 12 ? 'AM' : 'PM';
    return '${months[date.month - 1]} ${date.day.toString().padLeft(2, '0')}, ${date.year} $hour:$minute $amPm';
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.event != null;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 900),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: _primaryColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      isEditing
                          ? 'Edit Calamity Event'
                          : 'Create Calamity Event',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            // Form Content
            Flexible(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  shrinkWrap: true,
                  children: [
                    // Banner Image Section
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Banner Image *',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[800],
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (_selectedBanner != null || _bannerUrl != null)
                              Stack(
                                children: [
                                  Container(
                                    height: 200,
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      color: Colors.grey[200],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: _selectedBanner != null
                                          ? kIsWeb
                                                ? FutureBuilder<List<int>>(
                                                    future: _selectedBanner!
                                                        .readAsBytes(),
                                                    builder: (context, snapshot) {
                                                      if (snapshot.hasData) {
                                                        return Image.memory(
                                                          Uint8List.fromList(
                                                            snapshot.data!,
                                                          ),
                                                          fit: BoxFit.cover,
                                                        );
                                                      }
                                                      return const Center(
                                                        child:
                                                            CircularProgressIndicator(),
                                                      );
                                                    },
                                                  )
                                                : Image.file(
                                                    File(_selectedBanner!.path),
                                                    fit: BoxFit.cover,
                                                  )
                                          : _bannerUrl != null
                                          ? Image.network(
                                              _bannerUrl!,
                                              fit: BoxFit.cover,
                                            )
                                          : const Icon(Icons.image, size: 48),
                                    ),
                                  ),
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: IconButton(
                                      icon: const Icon(
                                        Icons.close,
                                        color: Colors.white,
                                      ),
                                      style: IconButton.styleFrom(
                                        backgroundColor: Colors.black54,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _selectedBanner = null;
                                          _bannerUrl = null;
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              )
                            else
                              OutlinedButton.icon(
                                onPressed: _pickBanner,
                                icon: const Icon(Icons.add_photo_alternate),
                                label: const Text('Select Banner Image'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _primaryColor,
                                  side: BorderSide(color: _primaryColor),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Title
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: TextFormField(
                          controller: _titleController,
                          decoration: InputDecoration(
                            labelText: 'Event Title *',
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
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Calamity Type
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Calamity Type *',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[800],
                              ),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              value: _selectedCalamityType,
                              decoration: InputDecoration(
                                hintText: 'Select calamity type',
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
                              items: _calamityTypes.map((type) {
                                return DropdownMenuItem<String>(
                                  value: type,
                                  child: Text(type),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  _selectedCalamityType = value;
                                });
                              },
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please select a calamity type';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Description
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: TextFormField(
                          controller: _descriptionController,
                          maxLines: 5,
                          decoration: InputDecoration(
                            labelText: 'Description *',
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
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Needed Items
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Needed Items *',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[800],
                                  ),
                                ),
                                const Spacer(),
                                if (_neededItems.isNotEmpty)
                                  Text(
                                    '${_neededItems.length} selected',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _neededItemsOptions.map((item) {
                                final isSelected = _neededItems.contains(item);
                                return FilterChip(
                                  label: Text(item),
                                  selected: isSelected,
                                  onSelected: (_) => _toggleNeededItem(item),
                                  selectedColor: _primaryColor.withOpacity(0.2),
                                  checkmarkColor: _primaryColor,
                                  labelStyle: TextStyle(
                                    color: isSelected
                                        ? _primaryColor
                                        : Colors.grey[700],
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                  side: BorderSide(
                                    color: isSelected
                                        ? _primaryColor
                                        : Colors.grey[300]!,
                                    width: isSelected ? 2 : 1,
                                  ),
                                );
                              }).toList(),
                            ),
                            if (_neededItems.isEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Please select at least one item',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.orange[700],
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Dropoff Location
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: TextFormField(
                          controller: _dropoffLocationController,
                          decoration: InputDecoration(
                            labelText: 'Dropoff Location *',
                            hintText: 'Enter dropoff address',
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
                              return 'Please enter dropoff location';
                            }
                            return null;
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Deadline
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Deadline *',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[800],
                              ),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _selectDeadline,
                              icon: const Icon(Icons.calendar_today),
                              label: Text(
                                _selectedDeadline != null
                                    ? _formatDeadline(_selectedDeadline!)
                                    : 'Select deadline',
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _primaryColor,
                                side: BorderSide(color: _primaryColor),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _submitting ? null : _submitEvent,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
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
                                isEditing ? 'Update Event' : 'Create Event',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
