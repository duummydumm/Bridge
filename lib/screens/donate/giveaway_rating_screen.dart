import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/giveaway_rating_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';

class GiveawayRatingScreen extends StatefulWidget {
  final String giveawayId;
  final String donorId;
  final String donorName;
  final String giveawayTitle;

  const GiveawayRatingScreen({
    super.key,
    required this.giveawayId,
    required this.donorId,
    required this.donorName,
    required this.giveawayTitle,
  });

  @override
  State<GiveawayRatingScreen> createState() => _GiveawayRatingScreenState();
}

class _GiveawayRatingScreenState extends State<GiveawayRatingScreen> {
  int _selectedRating = 5;
  final TextEditingController _reviewController = TextEditingController();
  bool _isSubmitting = false;

  static const Color _primaryColor = Color(0xFF2A7A9E);

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  Future<void> _submitRating() async {
    if (_isSubmitting) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final ratingProvider = Provider.of<GiveawayRatingProvider>(
      context,
      listen: false,
    );

    final currentUser = userProvider.currentUser;
    if (currentUser == null || authProvider.user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to submit a rating'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final success = await ratingProvider.createRating(
      giveawayId: widget.giveawayId,
      giveawayTitle: widget.giveawayTitle,
      donorId: widget.donorId,
      donorName: widget.donorName,
      raterId: authProvider.user!.uid,
      raterName: currentUser.fullName,
      rating: _selectedRating,
      review: _reviewController.text.trim().isNotEmpty
          ? _reviewController.text.trim()
          : null,
    );

    setState(() {
      _isSubmitting = false;
    });

    if (!mounted) return;

    if (success != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rating submitted successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true); // Return true to indicate success
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ratingProvider.errorMessage ?? 'Failed to submit rating',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        title: const Text('Rate Donation'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text(
              'How was your experience?',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Rate ${widget.donorName} for donating "${widget.giveawayTitle}"',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 32),

            // Rating Stars
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (index) {
                  final starIndex = index + 1;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedRating = starIndex;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        starIndex <= _selectedRating
                            ? Icons.star
                            : Icons.star_border,
                        size: 40,
                        color: starIndex <= _selectedRating
                            ? Colors.amber
                            : Colors.grey[400],
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                _getRatingText(_selectedRating),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: _primaryColor,
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Review Text Field
            Text(
              'Write a review (Optional)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reviewController,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: 'Share your experience with this donation...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _primaryColor, width: 2),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 32),

            // Submit Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitRating,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSubmitting
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
                        'Submit Rating',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getRatingText(int rating) {
    switch (rating) {
      case 1:
        return 'Poor';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Very Good';
      case 5:
        return 'Excellent';
      default:
        return '';
    }
  }
}
