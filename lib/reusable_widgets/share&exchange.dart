import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';

/// Shows the exchange options modal (Borrow, Rent, Trade, Give)
/// This is a reusable function that can be called from anywhere in the app
void showExchangeOptions(BuildContext context) {
  final userProvider = Provider.of<UserProvider>(context, listen: false);
  final isVerified = userProvider.currentUser?.isVerified ?? false;
  final currentUser = userProvider.currentUser;
  final canBorrow =
      currentUser?.canBorrow ?? true; // Default to true if user is null

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    enableDrag: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => ExchangeModal(
      isVerified: isVerified,
      canBorrow: canBorrow,
      onBorrow: () {
        Navigator.pop(context);
        if (isVerified) {
          Navigator.pushReplacementNamed(context, '/borrow');
        }
      },
      onRent: () {
        Navigator.pop(context);
        if (isVerified) {
          Navigator.pushReplacementNamed(context, '/rent');
        }
      },
      onTrade: () {
        Navigator.pop(context);
        if (isVerified) {
          Navigator.pushReplacementNamed(context, '/trade');
        }
      },
      onGive: () {
        Navigator.pop(context);
        if (isVerified) {
          Navigator.pushReplacementNamed(context, '/giveaway');
        }
      },
    ),
  );
}

/// Reusable exchange modal widget
class ExchangeModal extends StatefulWidget {
  final bool isVerified;
  final bool canBorrow;
  final VoidCallback onBorrow;
  final VoidCallback onRent;
  final VoidCallback onTrade;
  final VoidCallback onGive;

  const ExchangeModal({
    super.key,
    required this.isVerified,
    required this.canBorrow,
    required this.onBorrow,
    required this.onRent,
    required this.onTrade,
    required this.onGive,
  });

  @override
  State<ExchangeModal> createState() => _ExchangeModalState();
}

class _ExchangeModalState extends State<ExchangeModal>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _slideAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.8, curve: Curves.easeOutCubic),
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.8, curve: Curves.easeOutBack),
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _closeModal() {
    _controller.reverse().then((_) {
      if (mounted) {
        Navigator.pop(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _closeModal,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Stack(
            children: [
              // Blurred backdrop
              Positioned.fill(
                child: Opacity(
                  opacity: (_fadeAnimation.value * 0.5).clamp(0.0, 1.0),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(color: Colors.black.withOpacity(0.3)),
                  ),
                ),
              ),
              // Modal content
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: GestureDetector(
                  onTap: () {}, // Prevent tap from closing when tapping content
                  child: Transform.translate(
                    offset: Offset(0, _slideAnimation.value * 100),
                    child: Transform.scale(
                      scale: _scaleAnimation.value.clamp(0.0, 2.0),
                      child: Opacity(
                        opacity: _fadeAnimation.value.clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(28),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 30,
                                offset: const Offset(0, -10),
                              ),
                            ],
                          ),
                          constraints: BoxConstraints(
                            maxHeight:
                                MediaQuery.of(context).size.height * 0.85,
                          ),
                          child: SafeArea(
                            top: false,
                            child: SingleChildScrollView(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 24,
                                  horizontal: 20,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Drag handle
                                    Container(
                                      width: 48,
                                      height: 5,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[300],
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    // Title
                                    const Text(
                                      'Exchange',
                                      style: TextStyle(
                                        fontSize: 26,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1A1A1A),
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Choose an exchange option',
                                      style: TextStyle(
                                        fontSize: 15,
                                        color: Colors.grey[600],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    // Verification warning banner
                                    if (!widget.isVerified) ...[
                                      const SizedBox(height: 16),
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.shade50,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: Colors.orange.shade200,
                                            width: 1,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.info_outline,
                                              color: Colors.orange.shade700,
                                              size: 20,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                'Your account is pending admin verification. You can browse items but cannot post or transact yet.',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.orange.shade900,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 24),
                                    // Exchange options with staggered animation
                                    // Only show Borrow option if user can borrow
                                    if (widget.canBorrow) ...[
                                      _buildAnimatedExchangeOption(
                                        icon: Icons.favorite_outline,
                                        title: 'Borrow',
                                        subtitle: 'Borrow items from neighbors',
                                        color: const Color(0xFF42A5F5),
                                        onTap: widget.onBorrow,
                                        delay: 0,
                                        isEnabled: widget.isVerified,
                                      ),
                                      const SizedBox(height: 16),
                                    ],
                                    _buildAnimatedExchangeOption(
                                      icon: Icons.shopping_bag_outlined,
                                      title: 'Rent',
                                      subtitle: 'Rent items for a fee',
                                      color: const Color(0xFF66BB6A),
                                      onTap: widget.onRent,
                                      delay: 50,
                                      isEnabled: widget.isVerified,
                                    ),
                                    const SizedBox(height: 16),
                                    _buildAnimatedExchangeOption(
                                      icon: Icons.swap_horiz_outlined,
                                      title: 'Trade',
                                      subtitle: 'Swap items with others',
                                      color: const Color(0xFF26A69A),
                                      onTap: widget.onTrade,
                                      delay: 100,
                                      isEnabled: widget.isVerified,
                                    ),
                                    const SizedBox(height: 16),
                                    _buildAnimatedExchangeOption(
                                      icon: Icons.card_giftcard_outlined,
                                      title: 'Donate',
                                      subtitle: 'Donate items for free',
                                      color: const Color(0xFF00897B),
                                      onTap: widget.onGive,
                                      delay: 150,
                                      isEnabled: widget.isVerified,
                                    ),
                                    SizedBox(
                                      height:
                                          MediaQuery.of(
                                            context,
                                          ).padding.bottom +
                                          16,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAnimatedExchangeOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    required int delay,
    bool isEnabled = true,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 350 + delay),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        // Clamp opacity to valid range (0.0 to 1.0)
        final clampedOpacity = value.clamp(0.0, 1.0);
        return Transform.scale(
          scale: 0.85 + (value * 0.15),
          child: Opacity(opacity: clampedOpacity, child: child),
        );
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isEnabled ? onTap : null,
          borderRadius: BorderRadius.circular(20),
          child: Opacity(
            opacity: isEnabled ? 1.0 : 0.5,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color.withOpacity(0.12), color.withOpacity(0.08)],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withOpacity(0.3), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          color.withOpacity(0.2),
                          color.withOpacity(0.15),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: color.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Icon(icon, color: color, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A1A),
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isEnabled)
                    Icon(
                      Icons.chevron_right_rounded,
                      color: color.withOpacity(0.6),
                      size: 24,
                    )
                  else
                    Icon(
                      Icons.lock_outline,
                      color: Colors.grey.shade400,
                      size: 20,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
