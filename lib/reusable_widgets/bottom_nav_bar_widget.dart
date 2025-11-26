import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import 'share&exchange.dart';

class BottomNavBarWidget extends StatefulWidget {
  final int? selectedIndex; // Nullable to allow no tab to be selected
  final Function(int) onTap;
  final BuildContext? navigationContext; // Optional context for navigation

  const BottomNavBarWidget({
    super.key,
    this.selectedIndex,
    required this.onTap,
    this.navigationContext,
  });

  @override
  State<BottomNavBarWidget> createState() => _BottomNavBarWidgetState();
}

class _BottomNavBarWidgetState extends State<BottomNavBarWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _glowAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
    _glowController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final chatProvider = Provider.of<ChatProvider>(context);
    final String? currentUserId = authProvider.user?.uid;
    final int unreadCount = currentUserId != null
        ? chatProvider.getTotalUnreadCount(currentUserId)
        : 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -4),
            spreadRadius: 0,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(
                index: 0,
                icon: Icons.home_outlined,
                selectedIcon: Icons.home_rounded,
                label: 'Home',
              ),
              _buildNavItem(
                index: 1,
                icon: Icons.swap_horiz_outlined,
                selectedIcon: Icons.swap_horiz_rounded,
                label: 'Share & Exchange',
              ),
              _buildNavItem(
                index: 2,
                icon: Icons.chat_bubble_outline,
                selectedIcon: Icons.chat_bubble_rounded,
                label: 'Chat',
                badge: unreadCount > 0 ? unreadCount : null,
              ),
              _buildNavItem(
                index: 3,
                icon: Icons.person_outline,
                selectedIcon: Icons.person_rounded,
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    int? badge,
  }) {
    final isSelected =
        widget.selectedIndex != null && widget.selectedIndex == index;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          widget.onTap(index);
          if (widget.navigationContext != null) {
            _navigateToScreen(index, widget.navigationContext!);
          }
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: isSelected
                          ? const Color(0xFF00897B).withOpacity(0.12)
                          : Colors.transparent,
                    ),
                    child: Icon(
                      isSelected ? selectedIcon : icon,
                      size: 24,
                      color: isSelected
                          ? const Color(0xFF00897B)
                          : Colors.grey[600],
                    ),
                  ),
                  // Glowing indicator for selected item
                  if (isSelected)
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _glowAnimation,
                        builder: (context, child) {
                          return Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF26A69A,
                                  ).withOpacity(_glowAnimation.value * 0.5),
                                  blurRadius: 16,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  // Badge for chat
                  if (badge != null && badge > 0)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withOpacity(0.5),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        child: Text(
                          badge > 99 ? '99+' : '$badge',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  fontSize: isSelected ? 12 : 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? const Color(0xFF00897B)
                      : Colors.grey[600],
                ),
                child: Text(label, textAlign: TextAlign.center),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToScreen(int index, BuildContext context) {
    switch (index) {
      case 0: // Home
        Navigator.pushReplacementNamed(context, '/home');
        break;
      case 1: // Exchange (unified for Borrow, Rent, Trade, Give)
        showExchangeOptions(context);
        break;
      case 2: // Chat
        Navigator.pushReplacementNamed(context, '/chat');
        break;
      case 3: // Profile
        Navigator.pushReplacementNamed(context, '/profile');
        break;
    }
  }
}
