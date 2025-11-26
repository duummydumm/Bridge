import '../../models/trade_item_model.dart';

class TradeMatch {
  final TradeItemModel tradeItem;
  final double matchScore; // 0.0 to 1.0
  final String matchReason;
  final MatchType matchType;
  final TradeItemModel? matchedUserTradeItem; // User's trade item that matched

  TradeMatch({
    required this.tradeItem,
    required this.matchScore,
    required this.matchReason,
    required this.matchType,
    this.matchedUserTradeItem,
  });
}

enum MatchType {
  theyWantWhatYouOffer, // Someone wants what you're offering
  theyOfferWhatYouWant, // Someone offers what you're looking for
  mutualMatch, // Both match each other
}

class TradeMatchingService {
  /// Get matched trades for a user based on their trade listings
  /// Returns matches sorted by score (highest first)
  static List<TradeMatch> getMatches({
    required List<TradeItemModel> userTradeItems, // User's own listings
    required List<TradeItemModel> allOpenTrades, // All open trade listings
    required String currentUserId,
  }) {
    final matches = <TradeMatch>[];

    // Get what user is offering and what they want
    final userOfferedItems = <String, TradeItemModel>{};
    final userDesiredItems = <String, TradeItemModel>{};

    for (var userItem in userTradeItems) {
      if (userItem.isOpen) {
        // What user is offering
        final offeredKey = _normalizeText(userItem.offeredItemName);
        userOfferedItems[offeredKey] = userItem;

        // What user wants
        if (userItem.desiredItemName != null &&
            userItem.desiredItemName!.isNotEmpty) {
          final desiredKey = _normalizeText(userItem.desiredItemName!);
          userDesiredItems[desiredKey] = userItem;
        }
        if (userItem.desiredCategory != null &&
            userItem.desiredCategory!.isNotEmpty) {
          final categoryKey = _normalizeText(userItem.desiredCategory!);
          userDesiredItems[categoryKey] = userItem;
        }
      }
    }

    // Match against all open trades (excluding user's own)
    for (var trade in allOpenTrades) {
      if (trade.offeredBy == currentUserId || !trade.isOpen) {
        continue; // Skip own listings and closed trades
      }

      TradeMatch? match;

      // Check if they want what you're offering
      if (trade.desiredItemName != null && trade.desiredItemName!.isNotEmpty) {
        final desiredKey = _normalizeText(trade.desiredItemName!);
        for (var entry in userOfferedItems.entries) {
          final score = _calculateMatchScore(entry.key, desiredKey);
          if (score > 0.3) {
            // Minimum threshold
            match = TradeMatch(
              tradeItem: trade,
              matchScore: score,
              matchReason:
                  'They want "${trade.desiredItemName}" and you offer "${entry.value.offeredItemName}"',
              matchType: MatchType.theyWantWhatYouOffer,
              matchedUserTradeItem: entry.value,
            );
            break;
          }
        }
      }

      // Check if they offer what you want
      if (match == null || match.matchScore < 0.8) {
        // Only check if no strong match or to find mutual matches
        final offeredKey = _normalizeText(trade.offeredItemName);
        for (var entry in userDesiredItems.entries) {
          final score = _calculateMatchScore(offeredKey, entry.key);
          if (score > 0.3) {
            final newMatch = TradeMatch(
              tradeItem: trade,
              matchScore: score,
              matchReason:
                  'They offer "${trade.offeredItemName}" and you want "${entry.value.desiredItemName ?? entry.value.desiredCategory ?? 'something similar'}"',
              matchType: MatchType.theyOfferWhatYouWant,
              matchedUserTradeItem: entry.value,
            );

            // Check for mutual match
            if (match != null &&
                match.matchType == MatchType.theyWantWhatYouOffer) {
              // Mutual match - both want what the other offers
              match = TradeMatch(
                tradeItem: trade,
                matchScore: (match.matchScore + newMatch.matchScore) / 2 + 0.2,
                matchReason:
                    'Perfect match! You both want what the other offers',
                matchType: MatchType.mutualMatch,
                matchedUserTradeItem: match.matchedUserTradeItem ?? entry.value,
              );
            } else if (match == null ||
                newMatch.matchScore > match.matchScore) {
              match = newMatch;
            }
            break;
          }
        }
      }

      // Check category matches
      if (match == null || match.matchScore < 0.6) {
        // Check if desired category matches offered category
        if (trade.desiredCategory != null &&
            trade.desiredCategory!.isNotEmpty) {
          for (var entry in userOfferedItems.entries) {
            if (entry.value.offeredCategory.toLowerCase() ==
                trade.desiredCategory!.toLowerCase()) {
              final score = 0.5; // Category match gets medium score
              if (match == null || score > match.matchScore) {
                match = TradeMatch(
                  tradeItem: trade,
                  matchScore: score,
                  matchReason:
                      'They want items in "${trade.desiredCategory}" category and you offer "${entry.value.offeredItemName}"',
                  matchType: MatchType.theyWantWhatYouOffer,
                  matchedUserTradeItem: entry.value,
                );
              }
            }
          }
        }

        // Check if offered category matches desired category
        if (match == null || match.matchScore < 0.6) {
          for (var entry in userDesiredItems.entries) {
            if (entry.value.desiredCategory != null &&
                entry.value.desiredCategory!.isNotEmpty &&
                trade.offeredCategory.toLowerCase() ==
                    entry.value.desiredCategory!.toLowerCase()) {
              final score = 0.5;
              if (match == null || score > match.matchScore) {
                match = TradeMatch(
                  tradeItem: trade,
                  matchScore: score,
                  matchReason:
                      'They offer "${trade.offeredItemName}" in "${trade.offeredCategory}" category which you\'re looking for',
                  matchType: MatchType.theyOfferWhatYouWant,
                  matchedUserTradeItem: entry.value,
                );
              }
            }
          }
        }
      }

      if (match != null) {
        matches.add(match);
      }
    }

    // Sort by match score (highest first)
    matches.sort((a, b) => b.matchScore.compareTo(a.matchScore));

    return matches;
  }

  /// Calculate match score between two text strings
  /// Returns a score from 0.0 to 1.0
  static double _calculateMatchScore(String text1, String text2) {
    final normalized1 = _normalizeText(text1);
    final normalized2 = _normalizeText(text2);

    // Exact match
    if (normalized1 == normalized2) {
      return 1.0;
    }

    // One contains the other
    if (normalized1.contains(normalized2) ||
        normalized2.contains(normalized1)) {
      final longer = normalized1.length > normalized2.length
          ? normalized1
          : normalized2;
      final shorter = normalized1.length <= normalized2.length
          ? normalized1
          : normalized2;
      return shorter.length / longer.length * 0.8;
    }

    // Word overlap
    final words1 = normalized1.split(' ').where((w) => w.length > 2).toSet();
    final words2 = normalized2.split(' ').where((w) => w.length > 2).toSet();

    if (words1.isEmpty || words2.isEmpty) {
      return 0.0;
    }

    final intersection = words1.intersection(words2);
    final union = words1.union(words2);

    if (union.isEmpty) {
      return 0.0;
    }

    // Jaccard similarity
    return intersection.length / union.length * 0.6;
  }

  /// Normalize text for comparison (lowercase, trim, remove special chars)
  static String _normalizeText(String text) {
    return text
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Get match badge color based on match type
  static String getMatchBadgeColor(MatchType matchType) {
    switch (matchType) {
      case MatchType.mutualMatch:
        return 'green';
      case MatchType.theyWantWhatYouOffer:
        return 'blue';
      case MatchType.theyOfferWhatYouWant:
        return 'orange';
    }
  }

  /// Get match badge text based on match type
  static String getMatchBadgeText(MatchType matchType) {
    switch (matchType) {
      case MatchType.mutualMatch:
        return 'Perfect Match';
      case MatchType.theyWantWhatYouOffer:
        return 'They Want This';
      case MatchType.theyOfferWhatYouWant:
        return 'You Want This';
    }
  }
}
