import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../../services/deepseek_service.dart';
import '../../services/ai_insights_service.dart';
import '../../services/test_result_service.dart';
import '../../services/student_profile_service.dart';
import '../../providers/auth_provider.dart';
// Removed insight widgets import since chat bubbles are no longer used.
import 'quiz_fullscreen_page.dart';
import 'insights_fullscreen_page.dart';
import 'study_plan_fullscreen_page.dart';
import 'time_management_fullscreen_page.dart';

// Small wrapper that allows left-to-right swipe to pop the current route.
class _SwipeToPopWrapper extends StatelessWidget {
  final Widget child;
  const _SwipeToPopWrapper({required this.child});

  static const double _swipeBackVelocityThreshold = 300.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0.0;
        // Left-to-right swipe (positive velocity) -> pop
        if (v > _swipeBackVelocityThreshold) {
          if (Navigator.canPop(context)) Navigator.pop(context);
        }
      },
      child: child,
    );
  }
}

class AiChatPage extends StatefulWidget {
  const AiChatPage({super.key});

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  static const double _swipeBackVelocityThreshold = 300.0;

  final ScrollController _scrollController = ScrollController();
  final DeepSeekService _aiService = DeepSeekService();
  final AiInsightsService _insightsService = AiInsightsService();
  final TestResultService _testService = TestResultService();
  final StudentProfileService _profileService = StudentProfileService();
  bool _isProcessing = false;
  bool _insightsUsedToday = false;
  bool _studyPlanUsedToday = false;
  int _quizAttemptsToday = 0; // Track daily quiz attempts (max 2)
  String? _currentUserId; // Track user to scope daily usage keys
  String? _todayInsightsText;
  Map<String, double>? _todayInsightsAverages;
  String? _todayStudyPlanText;

  @override
  void initState() {
    super.initState();
    _checkDailyUsage();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Detect auth user changes and re-evaluate daily usage flags
    final authProvider = Provider.of<AuthProvider>(context);
    final uid = authProvider.currentUser?.uid;
    if (uid != _currentUserId) {
      _currentUserId = uid;
      _checkDailyUsage();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 100,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Chat composer removed to reduce token usage; actions are card-based only.

  Future<void> _handleInsightRequest() async {
    // If already generated today, just reopen stored content
    if (_insightsUsedToday && _todayInsightsText != null) {
      await Navigator.of(context).push(
        PageRouteBuilder(
          opaque: true,
          pageBuilder: (context, animation, secondaryAnimation) =>
              _SwipeToPopWrapper(
                child: InsightsFullScreenPage(
                  insightsText: _todayInsightsText!,
                  subjectAverages: _todayInsightsAverages ?? {},
                ),
              ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            final offset = Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(curved);
            return SlideTransition(position: offset, child: child);
          },
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      // Get student ID from auth
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final studentId = authProvider.currentUser?.uid;

      if (studentId == null) {
        setState(() => _isProcessing = false);
        _scrollToEnd();
        return;
      }

      // Fetch recent test results
      final results = await _testService.getRecentTestResults(studentId);

      // Generate insights with performance data
      final insightResult = await _insightsService.generateSmartInsights(
        results,
      );

      if (!mounted) return;

      // Persist today's insights so user can re-view
      await _saveTodayInsights(
        insightResult.text,
        insightResult.subjectAverages,
      );

      await Navigator.of(context).push(
        PageRouteBuilder(
          opaque: true,
          pageBuilder: (context, animation, secondaryAnimation) =>
              _SwipeToPopWrapper(
                child: InsightsFullScreenPage(
                  insightsText: insightResult.text,
                  subjectAverages: insightResult.subjectAverages,
                ),
              ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            final offset = Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(curved);
            return SlideTransition(position: offset, child: child);
          },
        ),
      );
      setState(() {
        _isProcessing = false;
      });
      await _markInsightUsed();
      _scrollToEnd();
    } catch (e) {
      setState(() => _isProcessing = false);
      _scrollToEnd();
    }
  }

  Future<void> _handleStudyPlanRequest() async {
    // If already generated today, just reopen stored content
    if (_studyPlanUsedToday && _todayStudyPlanText != null) {
      await Navigator.of(context).push(
        PageRouteBuilder(
          opaque: true,
          pageBuilder: (context, animation, secondaryAnimation) =>
              _SwipeToPopWrapper(
                child: StudyPlanFullScreenPage(planText: _todayStudyPlanText!),
              ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            final offset = Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(curved);
            return SlideTransition(position: offset, child: child);
          },
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      // Get student ID from auth
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final studentId = authProvider.currentUser?.uid;

      if (studentId == null) {
        setState(() => _isProcessing = false);
        _scrollToEnd();
        return;
      }

      // Fetch subjects and test results
      final subjects = await _profileService.getStudentSubjects(studentId);
      final results = await _testService.getRecentTestResults(studentId);

      // Generate study plan
      final planText = await _insightsService.generateStudyPlan(
        subjects,
        results,
      );

      if (!mounted) return;

      // Persist today's study plan
      await _saveTodayStudyPlan(planText);

      await Navigator.of(context).push(
        PageRouteBuilder(
          opaque: true,
          pageBuilder: (context, animation, secondaryAnimation) =>
              StudyPlanFullScreenPage(planText: planText),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curve = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            return FadeTransition(opacity: curve, child: child);
          },
        ),
      );
      setState(() {
        _isProcessing = false;
      });
      await _markStudyPlanUsed();
      _scrollToEnd();
    } catch (e) {
      setState(() => _isProcessing = false);
      _scrollToEnd();
    }
  }

  Future<void> _handleStudyTimeManager() async {
    // Navigate to the new Time Management full-screen tool
    if (!mounted) return;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final uid = authProvider.currentUser?.uid;
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (context, animation, secondaryAnimation) =>
            _SwipeToPopWrapper(
              child: TimeManagementFullScreenPage(userId: uid),
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          final offset = Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(curved);
          return SlideTransition(position: offset, child: child);
        },
      ),
    );
  }

  Future<void> _checkDailyUsage() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final uid = authProvider.currentUser?.uid;
    _currentUserId = uid; // keep in sync

    if (uid == null) {
      setState(() {
        _insightsUsedToday = false;
        _studyPlanUsedToday = false;
      });
      return;
    }

    final insightKey = 'last_insight_date_$uid';
    final studyPlanKey = 'last_study_plan_date_$uid';
    final quizAttemptsKey =
        'quiz_attempts_${uid}_$today'; // Track quiz attempts per day
    final insightContentKey = 'insights_content_${uid}_$today';
    final insightAveragesKey = 'insights_avgs_${uid}_$today';
    final studyPlanContentKey = 'study_plan_content_${uid}_$today';

    final lastInsightDate = prefs.getString(insightKey) ?? '';
    final lastStudyPlanDate = prefs.getString(studyPlanKey) ?? '';
    final quizAttempts = prefs.getInt(quizAttemptsKey) ?? 0;

    // Load persisted content if present
    final storedInsight = prefs.getString(insightContentKey);
    final storedInsightAverages = prefs.getString(insightAveragesKey);
    final storedStudyPlan = prefs.getString(studyPlanContentKey);

    setState(() {
      _insightsUsedToday = lastInsightDate == today;
      _studyPlanUsedToday = lastStudyPlanDate == today;
      _quizAttemptsToday = quizAttempts;
      _todayInsightsText = storedInsight;
      if (storedInsightAverages != null) {
        try {
          final map =
              json.decode(storedInsightAverages) as Map<String, dynamic>;
          _todayInsightsAverages = map.map(
            (k, v) => MapEntry(k, (v as num).toDouble()),
          );
        } catch (_) {
          _todayInsightsAverages = null;
        }
      }
      _todayStudyPlanText = storedStudyPlan;
    });
  }

  Future<void> _markInsightUsed() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];
    if (_currentUserId == null) return; // no user -> don't persist
    final key = 'last_insight_date_${_currentUserId!}';
    await prefs.setString(key, today);
    setState(() {
      _insightsUsedToday = true;
    });
  }

  Future<void> _markStudyPlanUsed() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];
    if (_currentUserId == null) return;
    final key = 'last_study_plan_date_${_currentUserId!}';
    await prefs.setString(key, today);
    setState(() {
      _studyPlanUsedToday = true;
    });
  }

  Future<void> _saveTodayInsights(
    String text,
    Map<String, double> averages,
  ) async {
    if (_currentUserId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];
    await prefs.setString('insights_content_${_currentUserId!}_$today', text);
    await prefs.setString(
      'insights_avgs_${_currentUserId!}_$today',
      json.encode(averages),
    );
    _todayInsightsText = text;
    _todayInsightsAverages = averages;
  }

  Future<void> _saveTodayStudyPlan(String text) async {
    if (_currentUserId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];
    await prefs.setString('study_plan_content_${_currentUserId!}_$today', text);
    _todayStudyPlanText = text;
  }

  Future<void> _incrementQuizAttempt() async {
    if (_currentUserId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];
    final key = 'quiz_attempts_${_currentUserId!}_$today';
    final newCount = _quizAttemptsToday + 1;
    await prefs.setInt(key, newCount);
    setState(() {
      _quizAttemptsToday = newCount;
    });
  }

  // Free-form chat handler removed; page uses card-based actions only.

  // Removed unused _showExplainTopicDialog to satisfy lint.

  Future<void> _showGenerateQuizDialog() async {
    // Check if user has exceeded daily quiz attempts (max 2 per day)
    if (_quizAttemptsToday >= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Daily quiz limit reached! You can generate 2 quizzes per day. ($_quizAttemptsToday/2 used)',
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final studentId = authProvider.currentUser?.uid;
    if (studentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to generate a quiz')),
      );
      return;
    }

    final subjects = await _profileService.getStudentSubjects(studentId);
    final profile = await _profileService.getStudentProfile(studentId);

    final profileStandard = _extractStandardFromProfile(profile);
    final selectedStandard = profileStandard.isNotEmpty
        ? profileStandard
        : 'Not set';

    final subjectOptions = subjects;
    if (subjectOptions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No enrolled subjects found for your profile. Please contact your school.',
          ),
        ),
      );
      return;
    }

    final topicController = TextEditingController();
    int numQuestions = 3; // Default to 3
    String selectedSubject = subjectOptions.first;
    String selectedDifficulty = 'Medium';

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Generate Quiz',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: topicController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Enter topic (e.g., Photosynthesis)',
                  hintStyle: const TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: const Color(0xFF1A1A1A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Subject:', style: TextStyle(color: Colors.white)),
                  DropdownButton<String>(
                    value: selectedSubject,
                    dropdownColor: const Color(0xFF2A2A2A),
                    style: const TextStyle(color: Colors.white),
                    items: subjectOptions
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setDialogState(() => selectedSubject = v);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Standard:',
                    style: TextStyle(color: Colors.white),
                  ),
                  Text(
                    selectedStandard,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Difficulty:',
                    style: TextStyle(color: Colors.white),
                  ),
                  DropdownButton<String>(
                    value: selectedDifficulty,
                    dropdownColor: const Color(0xFF2A2A2A),
                    style: const TextStyle(color: Colors.white),
                    items: const ['Easy', 'Medium', 'Hard']
                        .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setDialogState(() => selectedDifficulty = v);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Number of questions:',
                    style: TextStyle(color: Colors.white),
                  ),
                  DropdownButton<int>(
                    value: numQuestions,
                    dropdownColor: const Color(0xFF2A2A2A),
                    style: const TextStyle(color: Colors.white),
                    items:
                        [1, 2, 3, 4, 5] // Limited to 1-5 questions
                            .map(
                              (n) =>
                                  DropdownMenuItem(value: n, child: Text('$n')),
                            )
                            .toList(),
                    onChanged: (v) => setDialogState(() => numQuestions = v!),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                if (topicController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a topic')),
                  );
                  return;
                }
                Navigator.pop(context, {
                  'topic': topicController.text.trim(),
                  'count': numQuestions,
                  'subject': selectedSubject,
                  'standard': selectedStandard,
                  'difficulty': selectedDifficulty,
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF8A00),
              ),
              child: const Text(
                'Generate',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      _generateQuiz(
        topic: result['topic'] as String,
        count: result['count'] as int,
        subject: result['subject'] as String,
        standard: result['standard'] as String,
        difficulty: result['difficulty'] as String,
      );
    }
  }

  String _extractStandardFromProfile(Map<String, dynamic> profile) {
    final candidates = [
      profile['standard'],
      profile['class'],
      profile['className'],
      profile['grade'],
    ];

    for (final value in candidates) {
      if (value == null) continue;
      final raw = value.toString().trim();
      if (raw.isEmpty) continue;
      final firstPart = raw.split('-').first.trim();
      if (firstPart.isNotEmpty) return firstPart;
    }
    return '';
  }

  Future<void> _generateQuiz({
    required String topic,
    required int count,
    required String subject,
    required String standard,
    required String difficulty,
  }) async {
    setState(() {
      _isProcessing = true;
    });
    _scrollToEnd();

    try {
      final quizData = await _aiService.generateQuiz(
        topic,
        count,
        subject: subject,
        standard: standard,
        difficulty: difficulty,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        PageRouteBuilder(
          opaque: true,
          pageBuilder: (context, animation, secondaryAnimation) =>
              QuizFullScreenPage(quizData: quizData),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curve = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            return FadeTransition(opacity: curve, child: child);
          },
        ),
      );
      // Increment quiz attempt count
      await _incrementQuizAttempt();

      setState(() {
        _isProcessing = false;
      });
      _scrollToEnd();
    } catch (e) {
      setState(() => _isProcessing = false);
      _scrollToEnd();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDarkTheme
        ? const Color(0xFF1A1A1A)
        : Colors.white;
    final appBarColor = isDarkTheme ? const Color(0xFF1A1A1A) : Colors.white;
    final textColor = isDarkTheme ? Colors.white : Colors.black87;
    final iconColor = isDarkTheme ? Colors.white70 : Colors.black87;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0.0;
        if (velocity > _swipeBackVelocityThreshold &&
            Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          backgroundColor: appBarColor,
          elevation: 2,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new, color: iconColor),
            onPressed: () => Navigator.pop(context),
          ),
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF8A00).withOpacity(0.4),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const CircleAvatar(
                  backgroundImage: NetworkImage(
                    'https://lh3.googleusercontent.com/aida-public/AB6AXuDulQ-roKdSREmCPaSWq2QcOcr8XXXgHWBCekXFS9cITawaQ3Guu-9ynd45OzE4LCsZFGB4XapNfiu_8aRyzdlkw3niFsjAzy4Vts8INkkbK0AI7KFB01N881QNGoEFHRiowph5WvsbZJ0UKQUlW7Q1weyAR7kaW6D01ILaA7DaIoXB2kPLX8TImYQb79pqEGBjOUNR8Pc1BBgsGiJG0QhpaVsCHKhdC6Qx24ePPLRRaJVHlYAvz5flu3bV2RvJxjU6h-WMjd3uTBY',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Personal Assistant',
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        body: Stack(
          children: [
            SingleChildScrollView(child: _buildActionCards()),
            if (_isProcessing)
              Positioned.fill(
                child: Container(
                  color: Colors.black38,
                  child: const Center(
                    child: SizedBox(
                      width: 60,
                      height: 60,
                      child: CircularProgressIndicator(
                        strokeWidth: 4,
                        color: Color(0xFFFF8A00),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCards() {
    // Large initial cards grid
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.6,
        children: [
          _ActionCard(
            title: 'Generate Quiz',
            icon: Icons.quiz,
            color: const Color(0xFFFF8A00),
            onTap: _showGenerateQuizDialog,
            remainingCount: 2 - _quizAttemptsToday,
            showRemainingCount: true,
          ),
          _ActionCard(
            title: _insightsUsedToday ? 'View Insights' : 'My Insights',
            icon: Icons.insights,
            color: Colors.blueAccent,
            disabled: false,
            onTap: _handleInsightRequest,
          ),
          _ActionCard(
            title: _studyPlanUsedToday ? 'View Study Plan' : 'Study Plan',
            icon: Icons.calendar_today,
            color: Colors.green,
            disabled: false,
            onTap: _handleStudyPlanRequest,
          ),
          _ActionCard(
            title: 'Study Time Manager',
            icon: Icons.timer,
            color: Colors.cyan,
            onTap: _handleStudyTimeManager,
          ),
        ],
      ),
    );
  }

  // Mini actions row removed along with chat list to simplify UI.

  // Quick actions now directly call their handlers; free-form prompt removed.
}

class _ActionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool disabled;
  final int? remainingCount;
  final bool showRemainingCount;

  const _ActionCard({
    required this.title,
    required this.icon,
    required this.color,
    this.onTap,
    this.disabled = false,
    this.remainingCount,
    this.showRemainingCount = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDarkTheme ? const Color(0xFF2A2A2A) : Colors.white;
    final textColor = isDarkTheme ? Colors.white : Colors.black87;

    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (disabled)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: const Text(
                    'Today used',
                    style: TextStyle(color: Colors.grey, fontSize: 10),
                  ),
                ),
              ),
            if (showRemainingCount && remainingCount != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    remainingCount! > 0
                        ? 'You have $remainingCount'
                        : 'You have 0',
                    style: TextStyle(
                      color: remainingCount! > 0
                          ? Colors.grey
                          : Colors.redAccent,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
