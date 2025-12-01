import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../../services/deepseek_service.dart';
import '../../services/ai_insights_service.dart';
import '../../services/test_result_service.dart';
import '../../services/student_profile_service.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/ai_insight_widgets.dart';

class AiChatPage extends StatefulWidget {
  const AiChatPage({super.key});

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final DeepSeekService _aiService = DeepSeekService();
  final AiInsightsService _insightsService = AiInsightsService();
  final TestResultService _testService = TestResultService();
  final StudentProfileService _profileService = StudentProfileService();
  final List<ChatMessage> _messages = [];
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _restoreChat();
  }

  @override
  void dispose() {
    _controller.dispose();
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

  Future<void> _handleSend() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();

    // Detect insight or study plan requests
    final textLower = text.toLowerCase();
    final isInsightRequest =
        textLower.contains('insight') ||
        textLower.contains('analyse my performance') ||
        textLower.contains('analyze my performance') ||
        textLower.contains('how am i doing') ||
        textLower.contains('my performance');
    final isStudyPlanRequest =
        textLower.contains('study plan') ||
        textLower.contains('what should i study') ||
        textLower.contains('what to study') ||
        textLower.contains('study schedule');

    setState(() {
      _messages.add(ChatMessage(sender: 'student', text: text));
      _isProcessing = true;
    });
    _scrollToEnd();
    await _persistChat();

    try {
      if (isInsightRequest) {
        await _handleInsightRequest();
      } else if (isStudyPlanRequest) {
        await _handleStudyPlanRequest();
      } else {
        await _handleRegularChat(text);
      }
    } catch (e) {
      setState(() {
        _messages.add(
          ChatMessage(sender: 'ai', text: 'Sorry, I encountered an error: $e'),
        );
        _isProcessing = false;
      });
      _scrollToEnd();
      await _persistChat();
    }
  }

  Future<void> _handleInsightRequest() async {
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

      // Generate insights
      final insightText = await _insightsService.generateSmartInsights(results);

      setState(() {
        _messages.add(
          ChatMessage(
            sender: 'ai',
            text: insightText,
            messageType: MessageType.insight,
          ),
        );
        _isProcessing = false;
      });
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

  Future<void> _handleRegularChat(String text) async {
    setState(() {
      _messages.add(ChatMessage(sender: 'ai', text: ''));
    });
    _scrollToEnd();

    final aiIndex = _messages.length - 1;
    await _aiService.chatStream(text, (delta) {
      setState(() {
        final current = _messages[aiIndex].text;
        _messages[aiIndex] = ChatMessage(sender: 'ai', text: current + delta);
      });
      _scrollToEnd();
      _persistChat();
    });
    setState(() {
      _isProcessing = false;
    });
    await _persistChat();
  }

  Future<void> _showExplainTopicDialog() async {
    final topicController = TextEditingController();

    final topic = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Explain Topic',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: topicController,
              autofocus: true,
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
              onSubmitted: (value) {
                if (value.trim().isNotEmpty) {
                  Navigator.pop(context, value.trim());
                }
              },
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
              Navigator.pop(context, topicController.text.trim());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF8A00),
            ),
            child: const Text('Explain', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (topic != null && topic.isNotEmpty) {
      _handleQuickAction('Explain $topic in simple terms with examples');
    }
  }

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
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Tutor',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Ask anything, learn smarter',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.quiz, color: Color(0xFFFF8A00)),
            tooltip: 'Generate Quiz',
            onPressed: _showGenerateQuizDialog,
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Container(
                height: 64,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _ActionBubble(
                      label: 'Generate Quiz',
                      icon: Icons.quiz,
                      onTap: _showGenerateQuizDialog,
                    ),
                    _ActionBubble(
                      label: 'My Insights',
                      icon: Icons.insights,
                      onTap: () => _handleQuickAction(
                        'Give me insights on my performance',
                      ),
                    ),
                    _ActionBubble(
                      label: 'Study Plan',
                      icon: Icons.calendar_today,
                      onTap: () =>
                          _handleQuickAction('Create a study plan for me'),
                    ),
                    _ActionBubble(
                      label: 'Explain Topic',
                      icon: Icons.lightbulb,
                      onTap: _showExplainTopicDialog,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length,
                  itemBuilder: (context, i) {
                    final msg = _messages[i];
                    final isAi = msg.sender == 'ai';
                    return _MessageBubble(message: msg, isAi: isAi);
                  },
                ),
              ),
              _buildComposer(),
            ],
          ),
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

  Widget _buildComposer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A).withOpacity(0.95),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Ask me anything...',
                hintStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: const Color(0xFF2A2A2A),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: const BorderSide(
                    color: Color(0xFFFF8A00),
                    width: 1.5,
                  ),
                ),
              ),
              onSubmitted: (_) => _handleSend(),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 48,
            height: 48,
            child: ElevatedButton(
              onPressed: _handleSend,
              style: ElevatedButton.styleFrom(
                shape: const CircleBorder(),
                backgroundColor: const Color(0xFFFF8A00),
                padding: EdgeInsets.zero,
                elevation: 4,
              ),
              child: const Icon(Icons.send, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _restoreChat() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('ai_chat_messages') ?? [];
      if (list.isNotEmpty) {
        setState(() {
          _messages
            ..clear()
            ..addAll(list.map(ChatMessage.fromStorage));
        });
      } else {
        setState(() {
          _messages.addAll([
            ChatMessage(sender: 'ai', text: 'Hi! I\'m your AI Tutor'),
            ChatMessage(
              sender: 'ai',
              text: 'Ask anything or tap the quiz icon to generate a test!',
            ),
          ]);
        });
      }
    } catch (_) {
      setState(() {
        if (_messages.isEmpty) {
          _messages.addAll([
            ChatMessage(sender: 'ai', text: 'Hi! I\'m your AI Tutor'),
            ChatMessage(
              sender: 'ai',
              text: 'Ask anything or tap the quiz icon to generate a test!',
            ),
          ]);
        }
      });
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

  Future<void> _handleQuickAction(String prompt) async {
    _controller.text = prompt;
    await _handleSend();
  }
}

enum MessageType { normal, insight, studyPlan, quiz }

class ChatMessage {
  final String sender; // 'ai' or 'student'
  final String text;
  final Map<String, dynamic>? quiz;
  final DateTime timestamp;
  final MessageType messageType;

  ChatMessage({
    required this.sender,
    required this.text,
    this.quiz,
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
      timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
      messageType: type,
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isAi;

  const _MessageBubble({required this.message, required this.isAi});

  @override
  Widget build(BuildContext context) {
    // Special rendering for insights and study plans
    if (message.messageType == MessageType.insight) {
      return PerformanceInsightBubble(insightText: message.text);
    }
    if (message.messageType == MessageType.studyPlan) {
      return StudyPlanBubble(planText: message.text);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isAi
            ? MainAxisAlignment.start
            : MainAxisAlignment.end,
        children: [
          if (isAi) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF8A00).withOpacity(0.3),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const CircleAvatar(
                backgroundImage: NetworkImage(
                  'https://lh3.googleusercontent.com/aida-public/AB6AXuD9pcmKfLiLClQbyKb3SfQZxBfLbG-l-xIAA2PojWyI7etev013XuM8mefxbHJdxeQ-seaLFLotA1QIrMyuczKAKWczBgQGodvaU203eB8YOUs-5nIiiyl_dnP6_Fcj_HST4YWOdOf7H9E81q_pmTf6CrCF7Wy6dWhSol47cA2a6_tHcJb7jVdxWrJiGHEopC_Dxfn0wFRYND5Qa2yDXcObiunmBwBlmQ5oBuJCO7Zv-QNxiDztbxGEoTwFEGfYXwJu_WCYl7Rq3m0',
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 500),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: isAi
                      ? const Radius.circular(4)
                      : const Radius.circular(16),
                  bottomRight: isAi
                      ? const Radius.circular(16)
                      : const Radius.circular(4),
                ),
                border: Border.all(
                  color: const Color(0xFFFF8A00).withOpacity(0.2),
                  width: 1,
                ),
              ),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  if (message.quiz != null) ...[
                    const SizedBox(height: 12),
                    _QuizWidget(quizData: message.quiz!),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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

class _ActionBubble extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _ActionBubble({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFFF8A00).withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: const Color(0xFFFF8A00), size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// (duplicate declarations removed)
