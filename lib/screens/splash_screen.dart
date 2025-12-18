import 'package:flutter/material.dart';
import 'dart:async';

class SplashScreen extends StatefulWidget {
  final Widget child;
  final Duration duration;

  const SplashScreen({
    super.key,
    required this.child,
    this.duration = const Duration(seconds: 2),
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _pulseController;
  late AnimationController _ringController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rotationAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _ringRotationAnimation;
  late Animation<double> _shimmerAnimation;

  @override
  void initState() {
    super.initState();

    // Main animation controller for initial entrance
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    // Pulse controller for continuous breathing effect
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    // Ring rotation controller for spinning border
    _ringController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();

    // Fade animation (logo fades in)
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeIn),
      ),
    );

    // Scale animation (logo scales up with bounce)
    _scaleAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.8, curve: Curves.elasticOut),
      ),
    );

    // Rotation animation (logo rotates slightly on entrance)
    _rotationAnimation = Tween<double>(begin: -0.2, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.8, curve: Curves.easeOutCubic),
      ),
    );

    // Pulse animation (continuous breathing effect)
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Ring rotation animation
    _ringRotationAnimation = Tween<double>(
      begin: 0.0,
      end: 2 * 3.14159,
    ).animate(CurvedAnimation(parent: _ringController, curve: Curves.linear));

    // Shimmer animation (for glow effect)
    _shimmerAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Start main animation
    _controller.forward();

    // Wait for both animation and minimum duration, then navigate
    _navigateAfterDelay();
  }

  Future<void> _navigateAfterDelay() async {
    // Wait for minimum duration
    await Future.delayed(widget.duration);

    // Give a small additional delay to ensure initialization completes
    await Future.delayed(const Duration(milliseconds: 500));

    if (mounted) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => widget.child));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _pulseController.dispose();
    _ringController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF1E88E5),
              const Color(0xFF42A5F5),
              const Color(0xFF64B5F6),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: Center(
          child: AnimatedBuilder(
            animation: Listenable.merge([
              _controller,
              _pulseController,
              _ringController,
            ]),
            builder: (context, child) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animated logo container with multiple effects
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      // Rotating ring/border with gradient
                      Transform.rotate(
                        angle: _ringRotationAnimation.value,
                        child: Container(
                          width: 140 * _pulseAnimation.value,
                          height: 140 * _pulseAnimation.value,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: SweepGradient(
                              colors: [
                                Colors.white.withValues(
                                  alpha: 0.8 * _shimmerAnimation.value,
                                ),
                                Colors.white.withValues(alpha: 0.2),
                                Colors.white.withValues(
                                  alpha: 0.8 * _shimmerAnimation.value,
                                ),
                                Colors.white.withValues(alpha: 0.2),
                              ],
                              stops: const [0.0, 0.3, 0.6, 1.0],
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(3.0),
                            child: Container(
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.transparent,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Glow effect
                      Container(
                        width: 130 * _pulseAnimation.value,
                        height: 130 * _pulseAnimation.value,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withValues(
                                alpha: 0.4 * _shimmerAnimation.value,
                              ),
                              blurRadius: 30 * _pulseAnimation.value,
                              spreadRadius: 5,
                            ),
                            BoxShadow(
                              color: const Color(0xFF1E88E5).withValues(
                                alpha: 0.3 * _shimmerAnimation.value,
                              ),
                              blurRadius: 40 * _pulseAnimation.value,
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                      ),
                      // Main logo with entrance animation
                      Transform.scale(
                        scale: _scaleAnimation.value * _pulseAnimation.value,
                        child: Transform.rotate(
                          angle: _rotationAnimation.value,
                          child: Opacity(
                            opacity: _fadeAnimation.value,
                            child: Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    blurRadius: 25,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: Image.asset(
                                  'assets/logo.png',
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  // App name with fade and subtle pulse
                  Opacity(
                    opacity: _fadeAnimation.value,
                    child: Transform.scale(
                      scale: 0.95 + (0.05 * _pulseAnimation.value),
                      child: const Text(
                        'BRIDGE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          shadows: [
                            Shadow(
                              color: Colors.black26,
                              blurRadius: 10,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
