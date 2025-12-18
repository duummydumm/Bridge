import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui';

/// Tutorial step data model
class TutorialStep {
  final String title;
  final String description;
  final GlobalKey targetKey;
  final Alignment tooltipAlignment;
  final Offset tooltipOffset;

  const TutorialStep({
    required this.title,
    required this.description,
    required this.targetKey,
    this.tooltipAlignment = Alignment.center,
    this.tooltipOffset = Offset.zero,
  });
}

/// Home page tutorial overlay widget
class HomeTutorial extends StatefulWidget {
  final VoidCallback? onComplete;
  final VoidCallback? onSkip;
  final List<GlobalKey> targetKeys;

  const HomeTutorial({
    super.key,
    this.onComplete,
    this.onSkip,
    required this.targetKeys,
  });

  /// Check if tutorial has been shown before
  static Future<bool> hasBeenShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('home_tutorial_shown') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Mark tutorial as shown
  static Future<void> markAsShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('home_tutorial_shown', true);
    } catch (_) {}
  }

  /// Reset tutorial (for testing or re-showing)
  static Future<void> reset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('home_tutorial_shown', false);
    } catch (_) {}
  }

  @override
  State<HomeTutorial> createState() => _HomeTutorialState();
}

/// Helper function to create tutorial target keys
List<GlobalKey> createTutorialKeys() {
  return List.generate(7, (index) => GlobalKey());
}

class _HomeTutorialState extends State<HomeTutorial>
    with TickerProviderStateMixin {
  int _currentStep = 0;
  late AnimationController _overlayController;
  late AnimationController _pulseController;
  late AnimationController _tooltipController;
  late Animation<double> _overlayAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _tooltipAnimation;
  bool _targetsVerified = false; // Track if targets have been verified

  // Tutorial steps configuration
  late List<TutorialStep> _steps;

  @override
  void initState() {
    super.initState();

    // Define tutorial steps using provided keys
    _steps = [
      TutorialStep(
        title: 'Welcome to BRIDGE!',
        description:
            'This is your home screen. Let\'s explore the key features together.',
        targetKey: widget.targetKeys[0],
        tooltipAlignment: Alignment.topCenter,
        tooltipOffset: const Offset(0, -20),
      ),
      TutorialStep(
        title: 'Header Actions',
        description:
            'Access notifications, your listings, and settings from the top bar.',
        targetKey: widget.targetKeys[1],
        tooltipAlignment: Alignment.topRight,
        tooltipOffset: const Offset(-20, 20),
      ),
      TutorialStep(
        title: 'Welcome Banner',
        description:
            'Your personalized dashboard showing your reputation score and quick actions.',
        targetKey: widget.targetKeys[2],
        tooltipAlignment: Alignment.topCenter,
        tooltipOffset: const Offset(0, -20),
      ),
      TutorialStep(
        title: 'Statistics Cards',
        description:
            'Track your pending requests, borrowed items, and due dates at a glance.',
        targetKey: widget.targetKeys[3],
        tooltipAlignment: Alignment.topCenter,
        tooltipOffset: const Offset(0, -20),
      ),
      TutorialStep(
        title: 'Recent Activity',
        description:
            'See your latest borrowing and lending activities in one place.',
        targetKey: widget.targetKeys[4],
        tooltipAlignment: Alignment.topCenter,
        tooltipOffset: const Offset(0, -20),
      ),
      TutorialStep(
        title: 'Create Button',
        description:
            'Tap here to create new listings - lend, rent, trade, or donate items.',
        targetKey: widget.targetKeys[5],
        tooltipAlignment: Alignment.topLeft,
        tooltipOffset: const Offset(20, -20),
      ),
      TutorialStep(
        title: 'Navigation Bar',
        description:
            'Navigate between Home, Share & Exchange, Chat, and Profile sections.',
        targetKey: widget.targetKeys[6],
        tooltipAlignment: Alignment.bottomCenter,
        tooltipOffset: const Offset(0, -20),
      ),
    ];

    // Initialize animation controllers
    _overlayController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _overlayAnimation = CurvedAnimation(
      parent: _overlayController,
      curve: Curves.easeOut,
    );

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _tooltipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _tooltipAnimation = CurvedAnimation(
      parent: _tooltipController,
      curve: Curves.easeOut,
    );

    // Start the tutorial
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Verify that at least the first target is available before starting
      _verifyTargetsAndStart();
    });
  }

  Future<void> _verifyTargetsAndStart() async {
    // Wait a bit and verify that at least the first target is available
    // Try multiple times to ensure elements are rendered
    bool targetReady = false;
    for (int i = 0; i < 10; i++) {
      if (!mounted) return;

      await Future.delayed(const Duration(milliseconds: 200));

      // Check if the first target key has a valid render box
      final renderBox =
          _steps[0].targetKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null && renderBox.hasSize) {
        targetReady = true;
        break;
      }
    }

    if (!targetReady) {
      // Targets not ready after multiple attempts - auto-complete tutorial to prevent blocking UI
      if (mounted) {
        await _completeTutorial();
      }
      return;
    }

    // Targets are ready - mark as verified and start the tutorial
    if (mounted) {
      setState(() {
        _targetsVerified = true;
      });
      _overlayController.forward();
      _tooltipController.forward();
    }
  }

  @override
  void dispose() {
    _overlayController.dispose();
    _pulseController.dispose();
    _tooltipController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < _steps.length - 1) {
      // Animate tooltip out, then change step and animate in
      _tooltipController.reverse().then((_) {
        if (mounted) {
          setState(() {
            _currentStep++;
          });
          _tooltipController.forward();
        }
      });
    } else {
      _completeTutorial();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      // Animate tooltip out, then change step and animate in
      _tooltipController.reverse().then((_) {
        if (mounted) {
          setState(() {
            _currentStep--;
          });
          _tooltipController.forward();
        }
      });
    }
  }

  void _skipTutorial() {
    _completeTutorial();
    widget.onSkip?.call();
  }

  Future<void> _completeTutorial() async {
    await HomeTutorial.markAsShown();
    if (mounted) {
      await _overlayController.reverse();
      widget.onComplete?.call();
    }
  }

  Rect? _getTargetRect() {
    final RenderBox? renderBox =
        _steps[_currentStep].targetKey.currentContext?.findRenderObject()
            as RenderBox?;
    if (renderBox == null) return null;

    final size = renderBox.size;
    final position = renderBox.localToGlobal(Offset.zero);
    return Rect.fromLTWH(position.dx, position.dy, size.width, size.height);
  }

  @override
  Widget build(BuildContext context) {
    // Don't render anything until targets are verified
    if (!_targetsVerified) {
      return const SizedBox.shrink();
    }

    // Don't render if targets aren't ready yet
    final targetRect = _getTargetRect();
    if (targetRect == null && _overlayAnimation.value == 0) {
      return const SizedBox.shrink();
    }

    return FadeTransition(
      opacity: _overlayAnimation,
      child: Stack(
        children: [
          // Dark overlay with cutout
          _buildOverlay(),
          // Tooltip (with buttons inside)
          _buildTooltip(),
        ],
      ),
    );
  }

  Widget _buildOverlay() {
    // Don't show overlay if target isn't ready
    final targetRect = _getTargetRect();
    if (targetRect == null) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      // Allow scrolling to pass through the overlay
      ignoring: true,
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulseAnimation, _tooltipAnimation]),
        builder: (context, child) {
          return CustomPaint(
            painter: TutorialOverlayPainter(
              targetRect: _getTargetRect(),
              pulseValue: _pulseAnimation.value,
            ),
            child: Container(color: Colors.transparent),
          );
        },
      ),
    );
  }

  Widget _buildTooltip() {
    final step = _steps[_currentStep];
    final targetRect = _getTargetRect();

    if (targetRect == null) {
      return const SizedBox.shrink();
    }

    // Calculate tooltip position based on alignment
    Offset tooltipPosition;
    final screenSize = MediaQuery.of(context).size;
    final padding = 16.0;
    final tooltipWidth = screenSize.width * 0.85;
    final estimatedTooltipHeight =
        240.0; // Approximate height of tooltip (includes buttons)
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final bottomNavHeight = 80.0; // Bottom nav bar height
    // Buttons are now inside tooltip, so we only need space for bottom nav
    final reservedBottomSpace = bottomNavHeight + bottomPadding + 16;
    final availableBottomSpace =
        screenSize.height - targetRect.bottom - reservedBottomSpace;

    // Determine if we should place tooltip above or below based on available space
    final bool placeAbove =
        availableBottomSpace < estimatedTooltipHeight + padding ||
        targetRect.bottom > screenSize.height * 0.65;

    switch (step.tooltipAlignment) {
      case Alignment.topCenter:
        tooltipPosition = Offset(
          targetRect.center.dx - (tooltipWidth / 2),
          placeAbove
              ? targetRect.top - estimatedTooltipHeight - padding
              : targetRect.top - padding,
        );
        break;
      case Alignment.topLeft:
        tooltipPosition = Offset(
          targetRect.left - tooltipWidth - padding,
          placeAbove
              ? targetRect.top - estimatedTooltipHeight - padding
              : targetRect.top - padding,
        );
        break;
      case Alignment.topRight:
        tooltipPosition = Offset(
          targetRect.right + padding,
          placeAbove
              ? targetRect.top - estimatedTooltipHeight - padding
              : targetRect.top - padding,
        );
        break;
      case Alignment.bottomCenter:
        // For bottom elements, always place above
        tooltipPosition = Offset(
          targetRect.center.dx - (tooltipWidth / 2),
          targetRect.top - estimatedTooltipHeight - padding,
        );
        break;
      default:
        tooltipPosition = Offset(
          targetRect.center.dx - (tooltipWidth / 2),
          placeAbove
              ? targetRect.top - estimatedTooltipHeight - padding
              : targetRect.top - padding,
        );
    }

    // Apply offset
    tooltipPosition += step.tooltipOffset;

    // Clamp to screen bounds with proper consideration for tooltip height and navigation buttons
    final minY = padding;
    final maxY =
        screenSize.height -
        estimatedTooltipHeight -
        reservedBottomSpace -
        padding;

    tooltipPosition = Offset(
      tooltipPosition.dx.clamp(
        padding,
        screenSize.width - tooltipWidth - padding,
      ),
      tooltipPosition.dy.clamp(minY, maxY),
    );

    return Positioned(
      left: tooltipPosition.dx,
      top: tooltipPosition.dy,
      child: GestureDetector(
        onTap: _nextStep,
        child: AnimatedBuilder(
          animation: _tooltipAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: 0.8 + (_tooltipAnimation.value * 0.2),
              child: Opacity(
                opacity: _tooltipAnimation.value,
                child: Transform.translate(
                  offset: Offset(0, 20 * (1 - _tooltipAnimation.value)),
                  child: child,
                ),
              ),
            );
          },
          child: Container(
            constraints: BoxConstraints(
              maxWidth: screenSize.width * 0.85,
              minWidth: 200,
            ),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20,
                  spreadRadius: 2,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF00897B),
                            Color(0xFF26A69A),
                            Color(0xFF4DD0E1),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.lightbulb_outline,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        step.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                    ),
                    Text(
                      '${_currentStep + 1}/${_steps.length}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  step.description,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey[700],
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                // Navigation buttons inside tooltip
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: _skipTutorial,
                      child: const Text(
                        'Skip',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        if (_currentStep > 0)
                          TextButton(
                            onPressed: _previousStep,
                            child: const Text(
                              'Previous',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF00897B),
                              ),
                            ),
                          ),
                        if (_currentStep > 0) const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _nextStep,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00897B),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 2,
                          ),
                          child: Text(
                            _currentStep == _steps.length - 1
                                ? 'Got it!'
                                : 'Next',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom painter for tutorial overlay with spotlight effect
class TutorialOverlayPainter extends CustomPainter {
  final Rect? targetRect;
  final double pulseValue;

  TutorialOverlayPainter({required this.targetRect, required this.pulseValue});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.7)
      ..style = PaintingStyle.fill;

    // Draw dark overlay
    final overlayPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    if (targetRect != null) {
      // Create spotlight effect with padding
      final padding = 8.0 * pulseValue;
      final spotlightRect = Rect.fromLTWH(
        targetRect!.left - padding,
        targetRect!.top - padding,
        targetRect!.width + (padding * 2),
        targetRect!.height + (padding * 2),
      );

      // Create rounded rectangle for spotlight
      final spotlightPath = Path()
        ..addRRect(
          RRect.fromRectAndRadius(spotlightRect, const Radius.circular(16)),
        );

      // Cut out the spotlight from overlay
      final cutoutPath = Path.combine(
        PathOperation.difference,
        overlayPath,
        spotlightPath,
      );

      canvas.drawPath(cutoutPath, paint);

      // Draw pulsing border around spotlight
      final borderPaint = Paint()
        ..color = const Color(0xFF00897B).withOpacity(0.6 * pulseValue)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;

      canvas.drawRRect(
        RRect.fromRectAndRadius(spotlightRect, const Radius.circular(16)),
        borderPaint,
      );
    } else {
      canvas.drawPath(overlayPath, paint);
    }
  }

  @override
  bool shouldRepaint(TutorialOverlayPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect ||
        oldDelegate.pulseValue != pulseValue;
  }
}
