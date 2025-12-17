import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../../services/deepseek_service.dart';
import '../../services/ai_insights_service.dart';
import '../../services/test_result_service.dart';
import '../../services/student_profile_service.dart';
import '../../providers/auth_provider.dart';
import '../games/brain_games_menu_screen.dart';
import '../../widgets/swipe_card_deck.dart';
import 'motivation_fullscreen_page.dart';
import '../../widgets/history_card_deck.dart';
import 'history_fullscreen_page.dart';
// Removed insight widgets import since chat bubbles are no longer used.
import 'fact_fullscreen_page.dart';
import 'quiz_fullscreen_page.dart';
import 'insights_fullscreen_page.dart';
import 'study_plan_fullscreen_page.dart';
import 'time_management_fullscreen_page.dart';

class AiChatPage extends StatefulWidget {
  const AiChatPage({super.key});

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  final ScrollController _scrollController = ScrollController();
  final DeepSeekService _aiService = DeepSeekService();
  final AiInsightsService _insightsService = AiInsightsService();
  final TestResultService _testService = TestResultService();
  final StudentProfileService _profileService = StudentProfileService();
  final List<ChatMessage> _messages = [];
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
    _restoreChat();
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
              InsightsFullScreenPage(
                insightsText: _todayInsightsText!,
                subjectAverages: _todayInsightsAverages ?? {},
              ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curve = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            return FadeTransition(opacity: curve, child: child);
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
        setState(() {
          _messages.add(
            ChatMessage(
              sender: 'ai',
              text: 'Please log in to view your performance insights.',
            ),
          );
          _isProcessing = false;
        });
        _scrollToEnd();
        await _persistChat();
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
              InsightsFullScreenPage(
                insightsText: insightResult.text,
                subjectAverages: insightResult.subjectAverages,
              ),
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
        _messages.add(
          ChatMessage(
            sender: 'ai',
            text: '📊 Insights viewed',
            messageType: MessageType.insight,
            performanceData: insightResult.subjectAverages,
          ),
        );
        _isProcessing = false;
      });
      await _markInsightUsed();
      _scrollToEnd();
      await _persistChat();
    } catch (e) {
      setState(() {
        _messages.add(
          ChatMessage(sender: 'ai', text: 'Failed to generate insights: $e'),
        );
        _isProcessing = false;
      });
      _scrollToEnd();
      await _persistChat();
    }
  }

  Future<void> _handleStudyPlanRequest() async {
    // If already generated today, just reopen stored content
    if (_studyPlanUsedToday && _todayStudyPlanText != null) {
      await Navigator.of(context).push(
        PageRouteBuilder(
          opaque: true,
          pageBuilder: (context, animation, secondaryAnimation) =>
              StudyPlanFullScreenPage(planText: _todayStudyPlanText!),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curve = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            return FadeTransition(opacity: curve, child: child);
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
        setState(() {
          _messages.add(
            ChatMessage(
              sender: 'ai',
              text: 'Please log in to get a personalized study plan.',
            ),
          );
          _isProcessing = false;
        });
        _scrollToEnd();
        await _persistChat();
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
        _messages.add(
          ChatMessage(
            sender: 'ai',
            text: '🗓 Study plan viewed',
            messageType: MessageType.studyPlan,
          ),
        );
        _isProcessing = false;
      });
      await _markStudyPlanUsed();
      _scrollToEnd();
      await _persistChat();
    } catch (e) {
      setState(() {
        _messages.add(
          ChatMessage(sender: 'ai', text: 'Failed to generate study plan: $e'),
        );
        _isProcessing = false;
      });
      _scrollToEnd();
      await _persistChat();
    }
  }

  Future<void> _handleMotivationQuotes() async {
    try {
      setState(() => _isProcessing = true);
      final uri = Uri.parse('https://zenquotes.io/api/today');
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}');
      }

      final decoded = json.decode(resp.body);
      if (decoded is! List || decoded.isEmpty) {
        throw Exception('Unexpected response');
      }

      final item = decoded.first as Map<String, dynamic>;
      final quote = (item['q'] ?? '').toString();
      final author = (item['a'] ?? 'Unknown').toString();

      await _showSwipeableMotivation(
        quote,
        author,
      ); // Call to the updated method

      // Store to history
      _messages.add(ChatMessage(sender: 'ai', text: '“$quote” — $author'));
      await _persistChat();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load quote: $e')));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
      _scrollToEnd();
    }
  }

  Future<void> _showSwipeableMotivation(String quote, String author) async {
    final cards = [
      CardData(category: 'Motivation', text: quote, author: '— $author'),
    ];
    if (!mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (context, animation, secondaryAnimation) =>
            MotivationFullScreenPage(cards: cards),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curve = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(opacity: curve, child: child);
        },
      ),
    );
  }


  Future<void> _handleDailyFact() async {
    try {
      setState(() => _isProcessing = true);
      final uri = Uri.parse(
        'https://uselessfacts.jsph.pl/random.json?language=en',
      );
      String factText;
      try {
        final resp = await http.get(uri).timeout(const Duration(seconds: 10));
        if (resp.statusCode != 200) {
          throw Exception('HTTP ${resp.statusCode}');
        }
        final decoded = json.decode(resp.body);
        if (decoded is Map && decoded['text'] != null) {
          factText = decoded['text'].toString();
        } else {
          throw Exception('Unexpected response shape');
        }
      } catch (e) {
        // Fallback list if API fails
        final fallback = [
          'The Eiffel Tower can be 15 cm taller during hot days due to thermal expansion.',
          'Octopuses have three hearts and blue blood.',
          'Bananas are berries, but strawberries are not.',
          'Honeybees can recognize human faces.',
          'A day on Venus is longer than its year.',
        ];
        factText = (fallback..shuffle()).first;
      }

      await _showFactFullscreen(factText);

      setState(() {
        _messages.add(ChatMessage(sender: 'ai', text: factText));
        _isProcessing = false;
      });
      _scrollToEnd();
      await _persistChat();
    } catch (e) {
      setState(() {
        _messages.add(
          ChatMessage(sender: 'ai', text: 'Failed to load daily fact: $e'),
        );
        _isProcessing = false;
      });
      _scrollToEnd();
      await _persistChat();
    }
  }

  Future<void> _showFactFullscreen(String fact) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (context, animation, secondaryAnimation) =>
            FactFullScreenPage(facts: [fact]),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curve = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(opacity: curve, child: child);
        },
      ),
    );
  }

  Future<void> _handleTodayInHistory() async {
    try {
      setState(() => _isProcessing = true);
      final now = DateTime.now();
      final mm = now.month.toString().padLeft(2, '0');
      final dd = now.day.toString().padLeft(2, '0');
      final uri = Uri.parse(
        'https://api.wikimedia.org/feed/v1/wikipedia/en/onthisday/all/$mm/$dd',
      );

      final resp = await http
          .get(
            uri,
            headers: const {
              'Accept': 'application/json',
              'User-Agent': 'LenV-Edu/1.0 (AI Assistant)',
            },
          )
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              throw TimeoutException(
                'The request took too long. Please check your internet connection and try again.',
              );
            },
          );

      if (resp.statusCode != 200) {
        if (resp.statusCode == 404) {
          throw Exception(
            'No historical events found for today. Please try again later.',
          );
        } else if (resp.statusCode >= 500) {
          throw Exception(
            'The history service is temporarily unavailable. Please try again in a few moments.',
          );
        } else {
          throw Exception(
            'Unable to fetch history (Error ${resp.statusCode}). Please try again.',
          );
        }
      }

      final data = json.decode(resp.body) as Map<String, dynamic>;

      List<Map<String, String>> items = [];

      List<Map<String, String>> extract(List? arr, String category) {
        if (arr == null) return [];
        return arr
            .take(8)
            .map<Map<String, String>>((e) {
              final m = e as Map<String, dynamic>;
              String title = '';
              String thumb = '';
              final pages = m['pages'];
              if (pages is List && pages.isNotEmpty) {
                final p0 = pages.first as Map<String, dynamic>;
                final titles = p0['titles'] as Map<String, dynamic>?;
                title = (titles?['display'] ?? p0['title'] ?? '').toString();
                final thumbMap = p0['thumbnail'] as Map<String, dynamic>?;
                thumb = (thumbMap?['source'] ?? '').toString();
              }
              return {
                'text': (m['text'] ?? '').toString(),
                'year': (m['year'] ?? '').toString(),
                'title': title,
                'thumb': thumb,
                'category': category,
              };
            })
            .where((m) => (m['text'] ?? '').isNotEmpty)
            .toList();
      }

      items.addAll(extract(data['selected'] as List?, 'Selected'));
      items.addAll(extract(data['events'] as List?, 'Event'));
      if (items.isEmpty) {
        throw Exception(
          'No historical events available for today. Please try again later.',
        );
      }

      await _showHistorySheet(items);

      // Persist a concise summary to chat history
      final top = items
          .take(3)
          .map((e) {
            final y = e['year']?.isNotEmpty == true ? '(${e['year']}) ' : '';
            return '• $y${e['text']}';
          })
          .join('\n');
      _messages.add(
        ChatMessage(sender: 'ai', text: 'Today in History\n\n$top'),
      );
      await _persistChat();
    } on TimeoutException {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.access_time, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Request timeout. Please check your connection and try again.',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.orange.shade700,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on FormatException {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: const [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text('Received invalid data. Please try again later.'),
                ),
              ],
            ),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        final errorMessage = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    errorMessage.length > 100
                        ? 'Unable to load history. Please try again.'
                        : errorMessage,
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red.shade800,
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'RETRY',
              textColor: Colors.white,
              onPressed: _handleTodayInHistory,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
      _scrollToEnd();
    }
  }

  Future<void> _showHistorySheet(List<Map<String, String>> items) async {
    // Convert history items to HistoryCardData with rich details
    final RegExp htmlTag = RegExp(r'<[^>]+>');
    final RegExp spanTitle = RegExp(
      r'<span[^>]*>(.*?)<\/span>',
      caseSensitive: false,
    );
    String cleanTitle(String raw) {
      // Prefer extracting from <span> if present, else strip all tags
      final match = spanTitle.firstMatch(raw);
      if (match != null && match.groupCount > 0) {
        return match.group(1)!.replaceAll(htmlTag, '').trim();
      }
      return raw.replaceAll(htmlTag, '').trim();
    }

    final cards = items.take(10).map((it) {
      final year = it['year'] ?? '';
      final text = it['text'] ?? '';
      final titleRaw = it['title'] ?? '';
      final title = cleanTitle(titleRaw);
      final thumb = it['thumb'] ?? '';
      final category = it['category'] ?? 'Events';

      return HistoryCardData(
        title: title.isNotEmpty ? title : text,
        description: title.isNotEmpty ? text : 'Historical event from $year',
        year: year.isNotEmpty ? year : 'Unknown',
        imageUrl: thumb,
        category: category,
      );
    }).toList();

    // Present as a full-screen page for immersive experience
    if (!mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (context, animation, secondaryAnimation) =>
            HistoryFullScreenPage(cards: cards),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curve = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(opacity: curve, child: child);
        },
      ),
    );
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
            TimeManagementFullScreenPage(userId: uid),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curve = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(opacity: curve, child: child);
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

    final topicController = TextEditingController();
    int numQuestions = 3; // Default to 3

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
      _generateQuiz(result['topic'], result['count']);
    }
  }

  Future<void> _generateQuiz(String topic, int count) async {
    setState(() {
      _messages.add(
        ChatMessage(
          sender: 'student',
          text: 'Generate $count-question quiz on: $topic',
        ),
      );
      _isProcessing = true;
    });
    _scrollToEnd();

    try {
      final quizData = await _aiService.generateQuiz(topic, count);
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
        _messages.add(
          ChatMessage(
            sender: 'ai',
            text:
                '📝 ${quizData['title'] ?? 'Quiz'} (opened) - Attempt $_quizAttemptsToday/2',
            quiz: quizData,
            messageType: MessageType.quiz,
          ),
        );
        _isProcessing = false;
      });
      _scrollToEnd();
      await _persistChat();
    } catch (e) {
      setState(() {
        _messages.add(
          ChatMessage(sender: 'ai', text: 'Failed to generate quiz: $e'),
        );
        _isProcessing = false;
      });
      _scrollToEnd();
      await _persistChat();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDarkTheme ? const Color(0xFF1A1A1A) : Colors.white;
    final appBarColor = isDarkTheme ? const Color(0xFF1A1A1A) : Colors.white;
    final textColor = isDarkTheme ? Colors.white : Colors.black87;
    final iconColor = isDarkTheme ? Colors.white70 : Colors.black87;
    
    return Scaffold(
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
            title: 'Motivation Quotes',
            icon: Icons.format_quote,
            color: Colors.purpleAccent,
            onTap: _handleMotivationQuotes,
          ),
          _ActionCard(
            title: 'Daily Fact',
            icon: Icons.lightbulb_outline,
            color: Colors.amber,
            onTap: _handleDailyFact,
          ),
          _ActionCard(
            title: 'Today in History',
            icon: Icons.history_edu,
            color: Colors.deepOrange,
            onTap: _handleTodayInHistory,
          ),
          _ActionCard(
            title: 'Study Time Manager',
            icon: Icons.timer,
            color: Colors.cyan,
            onTap: _handleStudyTimeManager,
          ),
          _ActionCard(
            title: 'Games',
            icon: Icons.videogame_asset,
            color: Colors.teal,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const BrainGamesMenuScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // Mini actions row removed along with chat list to simplify UI.

  Future<void> _restoreChat() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('ai_chat_messages') ?? [];
      // Do not restore or prefill greeting messages; keep UI clean.
      if (list.isNotEmpty) {
        setState(() {
          _messages
            ..clear()
            ..addAll(list.map(ChatMessage.fromStorage));
        });
      }
    } catch (_) {
      // Ignore errors and show only action cards.
    }
  }

  Future<void> _persistChat() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        'ai_chat_messages',
        _messages.map((m) => m.toStorage()).toList(),
      );
    } catch (_) {}
  }

  // Quick actions now directly call their handlers; free-form prompt removed.
}

enum MessageType { normal, insight, studyPlan, quiz }

class ChatMessage {
  final String sender; // 'ai' or 'student'
  final String text;
  final Map<String, dynamic>? quiz;
  final Map<String, dynamic>? performanceData;
  final DateTime timestamp;
  final MessageType messageType;

  ChatMessage({
    required this.sender,
    required this.text,
    this.quiz,
    this.performanceData,
    DateTime? timestamp,
    this.messageType = MessageType.normal,
  }) : timestamp = timestamp ?? DateTime.now();

  String toStorage() {
    final ts = timestamp.millisecondsSinceEpoch;
    final quizStr = quiz == null ? '' : quiz.toString();
    final typeStr = messageType.toString().split('.').last;
    return '$sender|$ts|$text|$quizStr|$typeStr';
  }

  static ChatMessage fromStorage(String raw) {
    final parts = raw.split('|');
    final sender = parts.isNotEmpty ? parts[0] : 'ai';
    final ts = parts.length > 1
        ? int.tryParse(parts[1]) ?? DateTime.now().millisecondsSinceEpoch
        : DateTime.now().millisecondsSinceEpoch;
    final text = parts.length > 2 ? parts[2] : '';
    final typeStr = parts.length > 4 ? parts[4] : 'normal';

    MessageType type = MessageType.normal;
    if (typeStr == 'insight') {
      type = MessageType.insight;
    } else if (typeStr == 'studyPlan') {
      type = MessageType.studyPlan;
    } else if (typeStr == 'quiz') {
      type = MessageType.quiz;
    }

    return ChatMessage(
      sender: sender,
      text: text,
      quiz: null,
      performanceData: null,
      timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
      messageType: type,
    );
  }
}

// Message bubble removed with chat list.

class _QuizWidget extends StatefulWidget {
  final Map<String, dynamic> quizData;

  const _QuizWidget({required this.quizData});

  @override
  State<_QuizWidget> createState() => _QuizWidgetState();
}

class _QuizWidgetState extends State<_QuizWidget> {
  final Map<int, int?> _answers = {};
  final Map<int, bool> _submitted = {};

  @override
  Widget build(BuildContext context) {
    final questions = widget.quizData['questions'] as List<dynamic>? ?? [];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFF8A00).withOpacity(0.3)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: questions.asMap().entries.map((entry) {
          final i = entry.key;
          final q = entry.value;
          final questionText = q['question'] ?? '';
          final options = (q['options'] as List<dynamic>?) ?? [];
          final correctIndex = q['correctIndex'] ?? 0;
          final selectedIndex = _answers[i];
          final isSubmitted = _submitted[i] ?? false;

          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Q${i + 1}. $questionText',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                ...options.asMap().entries.map((optEntry) {
                  final optIndex = optEntry.key;
                  final optText = optEntry.value.toString();
                  final isSelected = selectedIndex == optIndex;
                  final isCorrect = optIndex == correctIndex;

                  Color bgColor = const Color(0xFF2A2A2A);
                  if (isSubmitted) {
                    if (isCorrect) {
                      bgColor = Colors.green.withOpacity(0.3);
                    } else if (isSelected && !isCorrect) {
                      bgColor = Colors.red.withOpacity(0.3);
                    }
                  } else if (isSelected) {
                    bgColor = const Color(0xFFFF8A00).withOpacity(0.2);
                  }

                  return GestureDetector(
                    onTap: isSubmitted
                        ? null
                        : () => setState(() => _answers[i] = optIndex),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSubmitted && isCorrect
                              ? Colors.green
                              : isSubmitted && isSelected
                              ? Colors.red
                              : isSelected
                              ? const Color(0xFFFF8A00)
                              : Colors.white24,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              optText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          if (isSubmitted && isCorrect)
                            const Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 18,
                            ),
                          if (isSubmitted && isSelected && !isCorrect)
                            const Icon(
                              Icons.cancel,
                              color: Colors.red,
                              size: 18,
                            ),
                        ],
                      ),
                    ),
                  );
                }),
                if (!isSubmitted && selectedIndex != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: ElevatedButton(
                      onPressed: () => setState(() => _submitted[i] = true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF8A00),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      child: const Text(
                        'Submit',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// Removed ActionBubble since mini actions were removed.

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

// (duplicate declarations removed)
