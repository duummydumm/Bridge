import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final int _totalPages = 6; // Increased to 6 pages
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeIn));
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));

    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentPage = index;
    });
    // Reset and restart animations for new page
    _fadeController.reset();
    _slideController.reset();
    _fadeController.forward();
    _slideController.forward();
  }

  void _nextPage() async {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      // Mark onboarding as completed
      try {
        final prefs = await SharedPreferences.getInstance();
        final success = await prefs.setBool('has_seen_onboarding', true);
        // Force a small delay to ensure web localStorage is committed
        if (!success) {
          // Retry once if it fails
          await Future.delayed(const Duration(milliseconds: 50));
          await prefs.setBool('has_seen_onboarding', true);
        }
        // Additional delay for web to ensure persistence
        await Future.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        debugPrint('Error saving onboarding status: $e');
      }

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  void _skipOnboarding() async {
    // Mark onboarding as completed
    try {
      final prefs = await SharedPreferences.getInstance();
      final success = await prefs.setBool('has_seen_onboarding', true);
      // Force a small delay to ensure web localStorage is committed
      if (!success) {
        // Retry once if it fails
        await Future.delayed(const Duration(milliseconds: 50));
        await prefs.setBool('has_seen_onboarding', true);
      }
      // Additional delay for web to ensure persistence
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (e) {
      debugPrint('Error saving onboarding status: $e');
    }

    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final padding = mediaQuery.padding;

    return Scaffold(
      body: Stack(
        children: [
          // Page View - full screen
          PageView.builder(
            controller: _pageController,
            onPageChanged: _onPageChanged,
            itemCount: _totalPages,
            itemBuilder: (context, index) {
              return _buildPage(index);
            },
          ),

          // Skip button - positioned at top
          Positioned(
            top: padding.top + 8,
            right: 16,
            child: TextButton(
              onPressed: _skipOnboarding,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text(
                    'Skip',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.arrow_forward, size: 16, color: Colors.white),
                ],
              ),
            ),
          ),

          // Page indicators and navigation - positioned at bottom
          Positioned(
            bottom: padding.bottom,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24.0,
                  vertical: 20.0,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Page indicators
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        _totalPages,
                        (index) => _buildPageIndicator(index == _currentPage),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Navigation buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Back button
                        if (_currentPage > 0)
                          TextButton.icon(
                            onPressed: () {
                              _pageController.previousPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            },
                            icon: const Icon(Icons.arrow_back, size: 18),
                            label: const Text(
                              'Back',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1E88E5),
                              ),
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                            ),
                          )
                        else
                          const SizedBox.shrink(),

                        // Next/Get Started button
                        ElevatedButton.icon(
                          onPressed: _nextPage,
                          icon: Icon(
                            _currentPage == _totalPages - 1
                                ? Icons.rocket_launch
                                : Icons.arrow_forward,
                            size: 18,
                          ),
                          label: Text(
                            _currentPage == _totalPages - 1
                                ? 'Get Started'
                                : 'Next',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E88E5),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 28,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 3,
                            shadowColor: const Color(
                              0xFF1E88E5,
                            ).withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageIndicator(bool isActive) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      height: 8,
      width: isActive ? 32 : 8,
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFF1E88E5) : Colors.grey[300],
        borderRadius: BorderRadius.circular(4),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: const Color(0xFF1E88E5).withValues(alpha: 0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
    );
  }

  Widget _buildPage(int index) {
    final pages = [
      _OnboardingPage(
        title: 'Welcome to Bridge',
        description:
            'Your community sharing platform. Connect with neighbors to borrow, rent, trade, and share items. Building stronger communities, one connection at a time.',
        icon: Icons.handshake_outlined,
        gradientColors: const [
          Color(0xFF1E88E5),
          Color(0xFF42A5F5),
          Color(0xFF64B5F6),
        ],
        fadeAnimation: _fadeAnimation,
        slideAnimation: _slideAnimation,
      ),
      _FeatureShowcasePage(
        title: 'Borrow Items',
        description:
            'Need something temporarily? Borrow tools, books, electronics, and more from your neighbors. Free, easy, and community-driven.',
        icon: Icons.favorite_outline,
        iconColor: const Color(0xFF42A5F5),
        gradientColors: const [
          Color(0xFF42A5F5),
          Color(0xFF64B5F6),
          Color(0xFF90CAF9),
        ],
        features: ['Free to borrow', 'Community trust', 'Easy returns'],
        fadeAnimation: _fadeAnimation,
        slideAnimation: _slideAnimation,
      ),
      _FeatureShowcasePage(
        title: 'Rent Items',
        description:
            'Rent items for a fee when you need them for longer periods. Perfect for events, projects, or temporary needs.',
        icon: Icons.shopping_bag_outlined,
        iconColor: const Color(0xFF66BB6A),
        gradientColors: const [
          Color(0xFF66BB6A),
          Color(0xFF81C784),
          Color(0xFFA5D6A7),
        ],
        features: ['Affordable rates', 'Flexible terms', 'Secure transactions'],
        fadeAnimation: _fadeAnimation,
        slideAnimation: _slideAnimation,
      ),
      _FeatureShowcasePage(
        title: 'Trade Items',
        description:
            'Swap items you no longer need for something you want. Trade books, clothes, electronics, and more with community members.',
        icon: Icons.swap_horiz_outlined,
        iconColor: const Color(0xFF26A69A),
        gradientColors: const [
          Color(0xFF26A69A),
          Color(0xFF4DB6AC),
          Color(0xFF80CBC4),
        ],
        features: ['Fair exchanges', 'Mutual benefit', 'No money needed'],
        fadeAnimation: _fadeAnimation,
        slideAnimation: _slideAnimation,
      ),
      _FeatureShowcasePage(
        title: 'Give & Donate',
        description:
            'Have items to give away? Donate to neighbors in need. Spread kindness and reduce waste in your community.',
        icon: Icons.card_giftcard,
        iconColor: const Color(0xFFEF5350),
        gradientColors: const [
          Color(0xFFEF5350),
          Color(0xFFE57373),
          Color(0xFFEF9A9A),
        ],
        features: [
          'Free giveaways',
          'Help neighbors',
          'Reduce waste',
          'Calamity cause',
        ],
        fadeAnimation: _fadeAnimation,
        slideAnimation: _slideAnimation,
      ),
      _OnboardingPage(
        title: 'Start Your Journey',
        description:
            'Join a verified community of neighbors. Create your account, get verified, and start sharing today. Let\'s build a stronger community together!',
        icon: Icons.rocket_launch_outlined,
        gradientColors: const [
          Color(0xFF1E88E5),
          Color(0xFF42A5F5),
          Color(0xFF64B5F6),
        ],
        fadeAnimation: _fadeAnimation,
        slideAnimation: _slideAnimation,
        showFeatures: true,
      ),
    ];

    return pages[index];
  }
}

class _OnboardingPage extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final List<Color> gradientColors;
  final Animation<double>? fadeAnimation;
  final Animation<Offset>? slideAnimation;
  final bool showFeatures;

  const _OnboardingPage({
    required this.title,
    required this.description,
    required this.icon,
    required this.gradientColors,
    this.fadeAnimation,
    this.slideAnimation,
    this.showFeatures = false,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 600;
    final mediaQuery = MediaQuery.of(context);
    // Calculate bottom nav height: indicators (8) + spacing (20) + buttons (~50) + padding (40) + extra (20) = ~138
    final bottomNavHeight = 180.0;
    final availableHeight = mediaQuery.size.height - bottomNavHeight;

    return Container(
      height: double.infinity,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 64.0 : 24.0,
          vertical: 0,
        ),
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: availableHeight),
            child: Padding(
              padding: EdgeInsets.only(
                top: mediaQuery.padding.top + 60,
                bottom: bottomNavHeight,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Icon container with animated background
                  FadeTransition(
                    opacity: fadeAnimation ?? const AlwaysStoppedAnimation(1.0),
                    child: SlideTransition(
                      position:
                          slideAnimation ??
                          const AlwaysStoppedAnimation(Offset.zero),
                      child: Container(
                        width: isDesktop ? 200 : 160,
                        height: isDesktop ? 200 : 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 30,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Animated circles
                            TweenAnimationBuilder<double>(
                              duration: const Duration(seconds: 4),
                              tween: Tween(begin: 0.0, end: 2 * math.pi),
                              builder: (context, value, child) {
                                return CustomPaint(
                                  size: Size(
                                    isDesktop ? 200 : 160,
                                    isDesktop ? 200 : 160,
                                  ),
                                  painter: _CirclePainter(
                                    progress: value,
                                    color: Colors.white.withValues(alpha: 0.1),
                                  ),
                                );
                              },
                              onEnd: () {},
                            ),
                            // Icon
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                              ),
                              child: Icon(
                                icon,
                                size: isDesktop ? 80 : 64,
                                color: gradientColors[0],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: isDesktop ? 60 : 48),

                  // Title
                  FadeTransition(
                    opacity: fadeAnimation ?? const AlwaysStoppedAnimation(1.0),
                    child: SlideTransition(
                      position:
                          slideAnimation ??
                          const AlwaysStoppedAnimation(Offset.zero),
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: isDesktop ? 32 : 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: isDesktop ? 24 : 20),

                  // Description
                  FadeTransition(
                    opacity: fadeAnimation ?? const AlwaysStoppedAnimation(1.0),
                    child: SlideTransition(
                      position:
                          slideAnimation ??
                          const AlwaysStoppedAnimation(Offset.zero),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: isDesktop ? 600 : screenWidth * 0.9,
                        ),
                        child: Text(
                          description,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: isDesktop ? 18 : 16,
                            color: Colors.white.withValues(alpha: 0.95),
                            height: 1.6,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                  ),

                  if (showFeatures) ...[
                    SizedBox(height: isDesktop ? 40 : 32),
                    FadeTransition(
                      opacity:
                          fadeAnimation ?? const AlwaysStoppedAnimation(1.0),
                      child: _buildFeatureGrid(context, isDesktop),
                    ),
                  ],

                  SizedBox(height: isDesktop ? 80 : 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureGrid(BuildContext context, bool isDesktop) {
    final features = [
      _FeatureItem(Icons.favorite_outline, 'Borrow', const Color(0xFF42A5F5)),
      _FeatureItem(
        Icons.shopping_bag_outlined,
        'Rent',
        const Color(0xFF66BB6A),
      ),
      _FeatureItem(Icons.swap_horiz_outlined, 'Trade', const Color(0xFF26A69A)),
      _FeatureItem(Icons.card_giftcard, 'Donate', const Color(0xFFEF5350)),
    ];

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      alignment: WrapAlignment.center,
      children: features.map((feature) {
        return Container(
          width: isDesktop ? 120 : 100,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                feature.icon,
                color: Colors.white,
                size: isDesktop ? 32 : 28,
              ),
              const SizedBox(height: 8),
              Text(
                feature.label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isDesktop ? 14 : 12,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _FeatureItem {
  final IconData icon;
  final String label;
  final Color color;

  _FeatureItem(this.icon, this.label, this.color);
}

class _FeatureShowcasePage extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final Color iconColor;
  final List<Color> gradientColors;
  final List<String> features;
  final Animation<double>? fadeAnimation;
  final Animation<Offset>? slideAnimation;

  const _FeatureShowcasePage({
    required this.title,
    required this.description,
    required this.icon,
    required this.iconColor,
    required this.gradientColors,
    required this.features,
    this.fadeAnimation,
    this.slideAnimation,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 600;
    final mediaQuery = MediaQuery.of(context);
    // Calculate bottom nav height: indicators (8) + spacing (20) + buttons (~50) + padding (40) + extra (20) = ~138
    final bottomNavHeight = 180.0;
    final availableHeight = mediaQuery.size.height - bottomNavHeight;

    return Container(
      height: double.infinity,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 64.0 : 24.0,
          vertical: 0,
        ),
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: availableHeight),
            child: Padding(
              padding: EdgeInsets.only(
                top: mediaQuery.padding.top + 60,
                bottom: bottomNavHeight,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Large icon with animation
                  FadeTransition(
                    opacity: fadeAnimation ?? const AlwaysStoppedAnimation(1.0),
                    child: SlideTransition(
                      position:
                          slideAnimation ??
                          const AlwaysStoppedAnimation(Offset.zero),
                      child: Container(
                        width: isDesktop ? 180 : 140,
                        height: isDesktop ? 180 : 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 30,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Icon(
                          icon,
                          size: isDesktop ? 90 : 70,
                          color: iconColor,
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: isDesktop ? 50 : 40),

                  // Title
                  FadeTransition(
                    opacity: fadeAnimation ?? const AlwaysStoppedAnimation(1.0),
                    child: SlideTransition(
                      position:
                          slideAnimation ??
                          const AlwaysStoppedAnimation(Offset.zero),
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: isDesktop ? 32 : 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: isDesktop ? 20 : 16),

                  // Description
                  FadeTransition(
                    opacity: fadeAnimation ?? const AlwaysStoppedAnimation(1.0),
                    child: SlideTransition(
                      position:
                          slideAnimation ??
                          const AlwaysStoppedAnimation(Offset.zero),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: isDesktop ? 600 : screenWidth * 0.9,
                        ),
                        child: Text(
                          description,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: isDesktop ? 18 : 16,
                            color: Colors.white.withValues(alpha: 0.95),
                            height: 1.6,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: isDesktop ? 40 : 32),

                  // Feature list
                  FadeTransition(
                    opacity: fadeAnimation ?? const AlwaysStoppedAnimation(1.0),
                    child: SlideTransition(
                      position:
                          slideAnimation ??
                          const AlwaysStoppedAnimation(Offset.zero),
                      child: Center(
                        child: IntrinsicWidth(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: features.map((feature) {
                              return Padding(
                                padding: EdgeInsets.symmetric(
                                  vertical: isDesktop ? 8 : 6,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: Icon(
                                        Icons.check_circle_outline,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      feature,
                                      style: TextStyle(
                                        fontSize: isDesktop ? 16 : 15,
                                        color: Colors.white.withValues(
                                          alpha: 0.9,
                                        ),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: isDesktop ? 80 : 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CirclePainter extends CustomPainter {
  final double progress;
  final Color color;

  _CirclePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;

    canvas.drawCircle(center, radius + math.sin(progress) * 10, paint);

    canvas.drawCircle(
      center,
      radius + math.cos(progress * 1.5) * 8,
      paint..color = color.withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(_CirclePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
