import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/rating_model.dart';
import '../services/rating_service.dart';
import '../providers/user_provider.dart';

class AllReviewsScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const AllReviewsScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<AllReviewsScreen> createState() => _AllReviewsScreenState();
}

class _AllReviewsScreenState extends State<AllReviewsScreen> {
  final RatingService _ratingService = RatingService();
  List<RatingModel> _reviews = [];
  double _averageRating = 0.0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final reviews = await _ratingService.getRatingsForUser(widget.userId);
      final avgRating = await _ratingService.getAverageRating(widget.userId);

      if (mounted) {
        setState(() {
          _reviews = reviews;
          _averageRating = avgRating;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildStarRating(double rating) {
    final fullStars = rating.floor();
    final hasHalfStar = (rating - fullStars) >= 0.5;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        if (index < fullStars) {
          return const Icon(Icons.star, color: Colors.amber, size: 18);
        } else if (index == fullStars && hasHalfStar) {
          return const Icon(Icons.star_half, color: Colors.amber, size: 18);
        } else {
          return Icon(Icons.star, color: Colors.grey[300], size: 18);
        }
      }),
    );
  }

  Widget _buildReviewItem(RatingModel review) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFF00897B).withValues(alpha: 0.2),
            child: Text(
              review.raterName.isNotEmpty
                  ? review.raterName[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                color: Color(0xFF00897B),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        review.raterName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildStarRating(review.rating.toDouble()),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  review.timeAgo,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                if (review.feedback != null && review.feedback!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    review.feedback!,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                      height: 1.4,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    review.context.name.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = Provider.of<UserProvider>(context).currentUser;
    final isOwnProfile = currentUser?.uid == widget.userId;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isOwnProfile ? 'Your Reviews' : 'Reviews for ${widget.userName}',
        ),
        backgroundColor: const Color(0xFF00897B),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _reviews.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.star_border, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No reviews yet',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Average Rating Summary
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // Use Column layout on very small screens
                        if (constraints.maxWidth < 200) {
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildStarRating(_averageRating),
                              const SizedBox(height: 8),
                              Text(
                                '${_averageRating.toStringAsFixed(1)}',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '(${_reviews.length} ${_reviews.length == 1 ? 'review' : 'reviews'})',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          );
                        }
                        // Use Row layout on larger screens
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildStarRating(_averageRating),
                            const SizedBox(width: 12),
                            Text(
                              '${_averageRating.toStringAsFixed(1)}',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                '(${_reviews.length} ${_reviews.length == 1 ? 'review' : 'reviews'})',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Reviews List
                  ..._reviews.map((review) => _buildReviewItem(review)),
                ],
              ),
            ),
    );
  }
}
