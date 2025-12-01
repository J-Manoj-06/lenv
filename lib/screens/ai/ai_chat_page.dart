import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../../services/deepseek_service.dart';
import '../../services/ai_insights_service.dart';
import '../../services/test_result_service.dart';
import '../../services/student_profile_service.dart';
import '../../providers/auth_provider.dart';
import '../games/brain_games_menu_screen.dart';
// Removed insight widgets import since chat bubbles are no longer used.

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

  @override
  void initState() {
    super.initState();
    _restoreChat();
    _checkDailyUsage();
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
    // Check if already used today
    if (_insightsUsedToday) {
      setState(() {
        _messages.add(
          ChatMessage(
            sender: 'ai',
            text:
                '⏰ You\'ve already used My Insights today. Come back tomorrow for fresh insights!',
          ),
        );
        _isProcessing = false;
      });
      _scrollToEnd();
      await _persistChat();
      return;
    }

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

      setState(() {
        _messages.add(
          ChatMessage(
            sender: 'ai',
            text: insightResult.text,
            messageType: MessageType.insight,
            performanceData: insightResult.subjectAverages,
          ),
        );
        _isProcessing = false;
      });

      // Mark as used today
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
    // Check if already used today
    if (_studyPlanUsedToday) {
      setState(() {
        _messages.add(
          ChatMessage(
            sender: 'ai',
            text:
                '⏰ You\'ve already received a Study Plan today. Come back tomorrow for a new plan!',
          ),
        );
        _isProcessing = false;
      });
      _scrollToEnd();
      await _persistChat();
      return;
    }

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

      setState(() {
        _messages.add(
          ChatMessage(
            sender: 'ai',
            text: planText,
            messageType: MessageType.studyPlan,
          ),
        );
        _isProcessing = false;
      });

      // Mark as used today
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
      // Temporary fallback until service method is added.
      // Replace with service or Firestore-backed fetch when available.
      final items = <String>[
        'Believe in yourself; you are stronger than you think.',
        'Small steps every day lead to big results.',
        'Mistakes are proof that you are trying.',
        'Discipline beats motivation. Show up and do the work.',
        'Learning is a journey—enjoy the process.',
      ];
      final text = items.isEmpty
          ? 'No quotes available right now.'
          : items.join('\n\n');
      setState(() {
        _messages.add(ChatMessage(sender: 'ai', text: text));
        _isProcessing = false;
      });
      _scrollToEnd();
      await _persistChat();
    } catch (e) {
      setState(() {
        _messages.add(
          ChatMessage(sender: 'ai', text: 'Failed to load quotes: $e'),
        );
        _isProcessing = false;
      });
      _scrollToEnd();
      await _persistChat();
    }
  }

  Future<void> _handleDailyFact() async {
    try {
      setState(() => _isProcessing = true);
      // Educational facts - can be fetched from Firestore or API
      final facts = <String>[
        '🧠 The human brain has approximately 86 billion neurons.',
        '🌍 The Earth\'s core is as hot as the surface of the Sun.',
        '📚 Reading for just 6 minutes can reduce stress levels by 68%.',
        '🔬 Honey never spoils. Archaeologists have found 3000-year-old honey that\'s still edible.',
        '⚡ Lightning strikes the Earth about 100 times every second.',
        '🌊 The Pacific Ocean is larger than all of Earth\'s land area combined.',
      ];
      final randomFact = (facts..shuffle()).first;
      setState(() {
        _messages.add(ChatMessage(sender: 'ai', text: randomFact));
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

  Future<void> _handleTodayInHistory() async {
    try {
      setState(() => _isProcessing = true);
      final today = DateTime.now();
      final monthDay = '${today.month}/${today.day}';

      // Historical events - can be expanded or fetched from API
      final events = <String, String>{
        '12/2':
            '📅 December 2, 1804: Napoleon Bonaparte crowned himself Emperor of France in a lavish ceremony at Notre-Dame Cathedral.',
        '1/1':
            '📅 January 1, 1863: The Emancipation Proclamation was issued by President Abraham Lincoln.',
        '7/4':
            '📅 July 4, 1776: The Declaration of Independence was adopted by the Continental Congress.',
        '10/12':
            '📅 October 12, 1492: Christopher Columbus reached the Americas.',
      };

      final event =
          events[monthDay] ??
          '📅 On this day in history: Many significant events occurred throughout the ages. Check back tomorrow for another historical fact!';

      setState(() {
        _messages.add(ChatMessage(sender: 'ai', text: event));
        _isProcessing = false;
      });
      _scrollToEnd();
      await _persistChat();
    } catch (e) {
      setState(() {
        _messages.add(
          ChatMessage(sender: 'ai', text: 'Failed to load history: $e'),
        );
        _isProcessing = false;
      });
      _scrollToEnd();
      await _persistChat();
    }
  }

  Future<void> _handleStudyTimeManager() async {
    try {
      setState(() => _isProcessing = true);

      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().split('T')[0];
      final lastStudyDate = prefs.getString('last_study_date') ?? '';
      final studyMinutes = prefs.getInt('study_minutes_today') ?? 0;

      String message;
      if (lastStudyDate == today) {
        final hours = studyMinutes ~/ 60;
        final mins = studyMinutes % 60;
        message = '⏱️ **Study Time Manager**\n\n';
        message += 'Today\'s Progress: ${hours}h ${mins}m\n\n';
        message += '📊 Keep going! Consistent study leads to success.\n\n';
        message += 'Recommended daily goal: 2-3 hours\n';
        if (studyMinutes < 120) {
          message +=
              '💪 You\'re ${120 - studyMinutes} minutes away from your goal!';
        } else {
          message += '🎉 Great job! You\'ve met your daily goal!';
        }
      } else {
        message = '⏱️ **Study Time Manager**\n\n';
        message += 'Start tracking your study time today!\n\n';
        message += '📚 Tips for effective studying:\n';
        message += '• Use Pomodoro: 25 min study, 5 min break\n';
        message += '• Eliminate distractions\n';
        message += '• Take notes actively\n';
        message += '• Review regularly\n\n';
        message += 'Recommended: 2-3 hours daily';
      }

      setState(() {
        _messages.add(ChatMessage(sender: 'ai', text: message));
        _isProcessing = false;
      });
      _scrollToEnd();
      await _persistChat();
    } catch (e) {
      setState(() {
        _messages.add(
          ChatMessage(sender: 'ai', text: 'Failed to load study manager: $e'),
        );
        _isProcessing = false;
      });
      _scrollToEnd();
      await _persistChat();
    }
  }

  Future<void> _checkDailyUsage() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];

    final lastInsightDate = prefs.getString('last_insight_date') ?? '';
    final lastStudyPlanDate = prefs.getString('last_study_plan_date') ?? '';

    setState(() {
      _insightsUsedToday = lastInsightDate == today;
      _studyPlanUsedToday = lastStudyPlanDate == today;
    });
  }

  Future<void> _markInsightUsed() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];
    await prefs.setString('last_insight_date', today);
    setState(() {
      _insightsUsedToday = true;
    });
  }

  Future<void> _markStudyPlanUsed() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];
    await prefs.setString('last_study_plan_date', today);
    setState(() {
      _studyPlanUsedToday = true;
    });
  }

  // Free-form chat handler removed; page uses card-based actions only.

  // Removed unused _showExplainTopicDialog to satisfy lint.

  Future<void> _showGenerateQuizDialog() async {
    final topicController = TextEditingController();
    int numQuestions = 5;

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
                    items: [3, 5, 10]
                        .map(
                          (n) => DropdownMenuItem(value: n, child: Text('$n')),
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
      setState(() {
        _messages.add(
          ChatMessage(
            sender: 'ai',
            text: '📝 ${quizData['title'] ?? 'Quiz'}',
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
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        elevation: 2,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white70),
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
            const Text(
              'Personal Assistant',
              style: TextStyle(
                color: Colors.white,
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
          ),
          _ActionCard(
            title: 'My Insights',
            icon: Icons.insights,
            color: Colors.blueAccent,
            disabled: _insightsUsedToday,
            onTap: _insightsUsedToday ? null : _handleInsightRequest,
          ),
          _ActionCard(
            title: 'Study Plan',
            icon: Icons.calendar_today,
            color: Colors.green,
            disabled: _studyPlanUsedToday,
            onTap: _studyPlanUsedToday ? null : _handleStudyPlanRequest,
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

  const _ActionCard({
    required this.title,
    required this.icon,
    required this.color,
    this.onTap,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
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
                  style: const TextStyle(
                    color: Colors.white,
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
          ],
        ),
      ),
    );
  }
}

// (duplicate declarations removed)
