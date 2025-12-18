import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/rating_model.dart';
import '../services/rating_service.dart';
import '../providers/user_provider.dart';

class SubmitRatingScreen extends StatefulWidget {
  final String ratedUserId;
  final String? ratedUserName;
  final RatingContext context;
  final String? transactionId;
  final String role; // 'borrower', 'lender', 'owner', 'renter', etc.

  const SubmitRatingScreen({
    super.key,
    required this.ratedUserId,
    this.ratedUserName,
    required this.context,
    this.transactionId,
    required this.role,
  });

  @override
  State<SubmitRatingScreen> createState() => _SubmitRatingScreenState();
}

class _SubmitRatingScreenState extends State<SubmitRatingScreen> {
  final RatingService _ratingService = RatingService();
  final TextEditingController _feedbackController = TextEditingController();
  int _selectedRating = 5;
  bool _isSubmitting = false;
  String? _errorMessage;

  Future<void> _submitRating() async {
    if (_selectedRating < 1 || _selectedRating > 5) {
      setState(() {
        _errorMessage = 'Please select a rating between 1 and 5 stars';
      });
      return;
    }

    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final currentUser = userProvider.currentUser;

    if (currentUser == null) {
      setState(() {
        _errorMessage = 'You must be logged in to submit a rating';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await _ratingService.submitRating(
        ratedUserId: widget.ratedUserId,
        raterUserId: currentUser.uid,
        raterName: currentUser.fullName,
        context: widget.context,
        transactionId: widget.transactionId,
        rating: _selectedRating,
        feedback: _feedbackController.text.trim().isEmpty
            ? null
            : _feedbackController.text.trim(),
        role: widget.role,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rating submitted successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context, true); // Return true to indicate success
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isSubmitting = false;
      });
    }
  }

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  String _getContextTitle() {
    switch (widget.context) {
      case RatingContext.rental:
        return 'Rate Rental Experience';
      case RatingContext.trade:
        return 'Rate Trade Experience';
      case RatingContext.borrow:
        return 'Rate Borrowing Experience';
      case RatingContext.giveaway:
        return 'Rate Giveaway Experience';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Submit Rating'),
        backgroundColor: const Color(0xFF00897B),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _getContextTitle(),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (widget.ratedUserName != null)
              Text(
                'Rate ${widget.ratedUserName}',
                style: TextStyle(fontSize: 16, color: Colors.grey[700]),
              ),
            const SizedBox(height: 32),

            // Star Rating Selection
            const Text(
              'Your Rating',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: List.generate(5, (index) {
                final starNumber = index + 1;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedRating = starNumber;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      starNumber <= _selectedRating
                          ? Icons.star
                          : Icons.star_border,
                      color: starNumber <= _selectedRating
                          ? Colors.amber
                          : Colors.grey,
                      size: 40,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            Text(
              '$_selectedRating out of 5 stars',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 32),

            // Feedback Text Field
            const Text(
              'Your Feedback (Optional)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _feedbackController,
              maxLines: 5,
              decoration: InputDecoration(
                hintText:
                    'Share your experience... What went well? What could be improved?',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
            ),
            const SizedBox(height: 24),

            // Error Message
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red[700]),
                      ),
                    ),
                  ],
                ),
              ),
            if (_errorMessage != null) const SizedBox(height: 16),

            // Submit Button
            ElevatedButton(
              onPressed: _isSubmitting ? null : _submitRating,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00897B),
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
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Submit Rating',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
