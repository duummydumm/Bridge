import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ChatTheme { defaultTheme, blue, green, purple, orange, pink, red, dark }

class ChatThemeData {
  final Color primaryColor;
  final Color messageBubbleColor;
  final Color otherMessageBubbleColor;
  final Color backgroundColor;
  final String name;

  const ChatThemeData({
    required this.primaryColor,
    required this.messageBubbleColor,
    required this.otherMessageBubbleColor,
    required this.backgroundColor,
    required this.name,
  });
}

class ChatThemeProvider extends ChangeNotifier {
  static const String _themeKeyPrefix = 'chat_theme_';
  final Map<String, ChatTheme> _conversationThemes = {};
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  ChatThemeProvider() {
    _loadAllThemes();
  }

  Future<void> _loadAllThemes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();

      for (final key in allKeys) {
        if (key.startsWith(_themeKeyPrefix)) {
          final conversationId = key.substring(_themeKeyPrefix.length);
          final themeIndex = prefs.getInt(key);
          if (themeIndex != null &&
              themeIndex >= 0 &&
              themeIndex < ChatTheme.values.length) {
            _conversationThemes[conversationId] = ChatTheme.values[themeIndex];
          }
        }
      }

      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      _isInitialized = true;
      notifyListeners();
    }
  }

  ChatTheme getThemeForConversation(String conversationId) {
    return _conversationThemes[conversationId] ?? ChatTheme.defaultTheme;
  }

  Future<void> setThemeForConversation(
    String conversationId,
    ChatTheme theme,
  ) async {
    if (getThemeForConversation(conversationId) == theme) return;

    _conversationThemes[conversationId] = theme;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('$_themeKeyPrefix$conversationId', theme.index);
    } catch (e) {
      debugPrint('Error saving chat theme preference: $e');
    }
  }

  ChatThemeData getThemeData(String conversationId) {
    final theme = getThemeForConversation(conversationId);
    switch (theme) {
      case ChatTheme.defaultTheme:
        return const ChatThemeData(
          primaryColor: Color(0xFF00897B),
          messageBubbleColor: Color(0xFF00897B),
          otherMessageBubbleColor: Colors.white,
          backgroundColor: Color(0xFFF5F5F5),
          name: 'Default',
        );
      case ChatTheme.blue:
        return const ChatThemeData(
          primaryColor: Color(0xFF1976D2),
          messageBubbleColor: Color(0xFF1976D2),
          otherMessageBubbleColor: Colors.white,
          backgroundColor: Color(0xFFE3F2FD),
          name: 'Blue',
        );
      case ChatTheme.green:
        return const ChatThemeData(
          primaryColor: Color(0xFF388E3C),
          messageBubbleColor: Color(0xFF388E3C),
          otherMessageBubbleColor: Colors.white,
          backgroundColor: Color(0xFFE8F5E9),
          name: 'Green',
        );
      case ChatTheme.purple:
        return const ChatThemeData(
          primaryColor: Color(0xFF7B1FA2),
          messageBubbleColor: Color(0xFF7B1FA2),
          otherMessageBubbleColor: Colors.white,
          backgroundColor: Color(0xFFF3E5F5),
          name: 'Purple',
        );
      case ChatTheme.orange:
        return const ChatThemeData(
          primaryColor: Color(0xFFF57C00),
          messageBubbleColor: Color(0xFFF57C00),
          otherMessageBubbleColor: Colors.white,
          backgroundColor: Color(0xFFFFF3E0),
          name: 'Orange',
        );
      case ChatTheme.pink:
        return const ChatThemeData(
          primaryColor: Color(0xFFC2185B),
          messageBubbleColor: Color(0xFFC2185B),
          otherMessageBubbleColor: Colors.white,
          backgroundColor: Color(0xFFFCE4EC),
          name: 'Pink',
        );
      case ChatTheme.red:
        return const ChatThemeData(
          primaryColor: Color(0xFFD32F2F),
          messageBubbleColor: Color(0xFFD32F2F),
          otherMessageBubbleColor: Colors.white,
          backgroundColor: Color(0xFFFFEBEE),
          name: 'Red',
        );
      case ChatTheme.dark:
        return const ChatThemeData(
          primaryColor: Color(0xFF424242),
          messageBubbleColor: Color(0xFF424242),
          otherMessageBubbleColor: Color(0xFF1E1E1E),
          backgroundColor: Color(0xFF121212),
          name: 'Dark',
        );
    }
  }

  static List<ChatTheme> get availableThemes => ChatTheme.values;

  static String getThemeName(ChatTheme theme) {
    switch (theme) {
      case ChatTheme.defaultTheme:
        return 'Default';
      case ChatTheme.blue:
        return 'Blue';
      case ChatTheme.green:
        return 'Green';
      case ChatTheme.purple:
        return 'Purple';
      case ChatTheme.orange:
        return 'Orange';
      case ChatTheme.pink:
        return 'Pink';
      case ChatTheme.red:
        return 'Red';
      case ChatTheme.dark:
        return 'Dark';
    }
  }

  static Color getThemeColor(ChatTheme theme) {
    switch (theme) {
      case ChatTheme.defaultTheme:
        return const Color(0xFF00897B);
      case ChatTheme.blue:
        return const Color(0xFF1976D2);
      case ChatTheme.green:
        return const Color(0xFF388E3C);
      case ChatTheme.purple:
        return const Color(0xFF7B1FA2);
      case ChatTheme.orange:
        return const Color(0xFFF57C00);
      case ChatTheme.pink:
        return const Color(0xFFC2185B);
      case ChatTheme.red:
        return const Color(0xFFD32F2F);
      case ChatTheme.dark:
        return const Color(0xFF424242);
    }
  }
}
