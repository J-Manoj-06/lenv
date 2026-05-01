import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../constants/app_colors.dart';
import '../../services/school_storage_service.dart';
import 'onboarding_page_widget.dart';

/// Main onboarding (Get Started) screen with PageView
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late PageController _pageController;
  late VideoPlayerController _videoController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _videoController = VideoPlayerController.asset('assets/enter_video.mp4')
      ..setLooping(true)
      ..setVolume(0);
    _videoController.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _videoController.play();
    }).catchError((_) {
      if (mounted) {
        setState(() {});
      }
    });
    _pageController.addListener(() {
      setState(() {
        _currentPage = _pageController.page?.round() ?? 0;
      });
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _videoController.dispose();
    super.dispose();
  }

  /// Navigate to next page
  void _nextPage() {
    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } else {
      _completeOnboarding();
    }
  }

  /// Skip onboarding
  void _skipOnboarding() {
    _completeOnboarding();
  }

  /// Mark onboarding as complete and navigate
  Future<void> _completeOnboarding() async {
    await schoolStorageService.initialize();
    await schoolStorageService.setOnboardingSeen();

    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/school-selection');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          // PageView
          PageView(
            controller: _pageController,
            children: [
              // Page 1: One App for Your Entire School
              OnboardingPage(
                title: 'One App for Your Entire School',
                description:
                    'Bring students, teachers, and parents together in one simple platform.',
                videoController: _videoController,
                backgroundGradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primary.withOpacity(0.1),
                    AppColors.primary.withOpacity(0.05),
                  ],
                ),
              ),

              // Page 2: Everything You Need in One Place
              OnboardingPage(
                title: 'Everything You Need, In One Place',
                bulletPoints: [
                  'Assignments & Homework',
                  'Attendance tracking',
                  'Instant announcements',
                  'Easy communication',
                ],
                videoController: _videoController,
                backgroundGradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    AppColors.primary.withOpacity(0.08),
                    AppColors.primary.withOpacity(0.02),
                  ],
                ),
              ),

              // Page 3: Secure, Reliable, and Ready
              OnboardingPage(
                title: 'Secure, Reliable, and Ready',
                description:
                    'Your school data is safe and accessible anytime. Built with security and reliability as our top priorities.',
                videoController: _videoController,
                backgroundGradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.primary.withOpacity(0.12),
                    AppColors.primary.withOpacity(0.03),
                  ],
                ),
              ),
            ],
          ),

          // Top Skip Button
          Positioned(
            top: 16,
            right: 16,
            child: SafeArea(
              child: TextButton(
                onPressed: _skipOnboarding,
                child: Text(
                  'Skip',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          ),

          // Bottom Controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      (isDark ? Colors.black : Colors.white).withOpacity(0.08),
                      (isDark ? Colors.black : Colors.white).withOpacity(0.22),
                    ],
                    stops: const [0.0, 0.35, 1.0],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 16,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                child: Column(
                  children: [
                    // Page Indicators (Dots)
                    _buildPageIndicators(isDark),

                    const SizedBox(height: 24),

                    // Next / Get Started Button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _nextPage,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 4,
                        ),
                        child: Text(
                          _currentPage == 2 ? 'Get Started' : 'Next',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
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

  /// Build page indicator dots
  Widget _buildPageIndicators(bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        3,
        (index) => AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 6),
          width: _currentPage == index ? 28 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: _currentPage == index
                ? AppColors.primary
                : (isDark
                      ? AppColors.indicatorInactiveDark
                      : AppColors.indicatorInactive),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}
