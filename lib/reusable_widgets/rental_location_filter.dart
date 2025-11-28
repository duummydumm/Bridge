import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Reusable collapsible location filter for rental screens.
///
/// Loads barangays from `assets/data/oroquieta_barangays.json` and exposes the
/// selected barangay via [onChanged]. UI is similar to the filter section used
/// in `RentItemsScreen`, but only includes location filtering.
class RentalLocationFilter extends StatefulWidget {
  const RentalLocationFilter({
    super.key,
    required this.onChanged,
    this.labelText = 'Filter by Barangay',
  });

  final ValueChanged<String?> onChanged;
  final String labelText;

  @override
  State<RentalLocationFilter> createState() => _RentalLocationFilterState();
}

class _RentalLocationFilterState extends State<RentalLocationFilter> {
  bool _isExpanded = false;
  List<String> _barangays = [];
  String? _selectedBarangay;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadBarangays();
  }

  Future<void> _loadBarangays() async {
    try {
      final String jsonString = await rootBundle.loadString(
        'assets/data/oroquieta_barangays.json',
      );
      final List<dynamic> jsonData = json.decode(jsonString);
      setState(() {
        _barangays = jsonData.cast<String>();
        _loading = false;
      });
    } catch (e) {
      // Fallback to empty list on error
      setState(() {
        _barangays = [];
        _loading = false;
      });
      // ignore: avoid_print
      print('Error loading barangays in RentalLocationFilter: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on_outlined, color: Color(0xFF00897B)),
              const SizedBox(width: 8),
              Text(
                'Location Filter',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[800],
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(
                  _isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.grey[700],
                ),
                onPressed: () {
                  setState(() {
                    _isExpanded = !_isExpanded;
                  });
                },
                tooltip: _isExpanded
                    ? 'Hide location filter'
                    : 'Show location filter',
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _isExpanded
                ? Column(
                    children: [
                      const SizedBox(height: 8),
                      _loading
                          ? const Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            )
                          : DropdownButtonFormField<String>(
                              value: _selectedBarangay,
                              decoration: InputDecoration(
                                labelText: widget.labelText,
                                prefixIcon: const Icon(Icons.location_city),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: Colors.grey[100],
                              ),
                              hint: const Text('All Barangays'),
                              items: [
                                const DropdownMenuItem<String>(
                                  value: null,
                                  child: Text('All Barangays'),
                                ),
                                ..._barangays.map((barangay) {
                                  return DropdownMenuItem<String>(
                                    value: barangay,
                                    child: Text(barangay),
                                  );
                                }),
                              ],
                              onChanged: (value) {
                                setState(() {
                                  _selectedBarangay = value;
                                });
                                widget.onChanged(value);
                              },
                            ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            setState(() {
                              _selectedBarangay = null;
                            });
                            widget.onChanged(null);
                          },
                          child: const Text('Clear location filter'),
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
