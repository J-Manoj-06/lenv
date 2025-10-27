import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/test_model.dart' as tm;
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/test_provider.dart';
import '../../services/teacher_service.dart';
// import 'package:cloud_firestore/cloud_firestore.dart'; // not needed; assignment handled server-side

class AITestGeneratorScreen extends StatefulWidget {
  const AITestGeneratorScreen({Key? key}) : super(key: key);

  @override
  State<AITestGeneratorScreen> createState() => _AITestGeneratorScreenState();
}

class _AITestGeneratorScreenState extends State<AITestGeneratorScreen> {
  final _subjectController = TextEditingController();
  final _topicsController = TextEditingController();
  final _questionCountController = TextEditingController();

  String selectedDifficulty = 'Medium';
  String? selectedClass;
  String? selectedSection; // Display: "Section A"
  int selectedNavIndex = 0;

  bool isGenerating = false;
  bool hasGenerated = false;

  List<GeneratedQuestion> generatedQuestions = [];

  final List<String> difficulties = ['Easy', 'Medium', 'Hard'];
  List<String> classes = [];
  List<String> sections = [];
  bool _loadingMeta = true;

  @override
  void dispose() {
    _subjectController.dispose();
    _topicsController.dispose();
    _questionCountController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadTeacherMeta();
  }

  Future<void> _loadTeacherMeta() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.currentUser;
    if (user == null) {
      setState(() => _loadingMeta = false);
      return;
    }

    try {
      final svc = TeacherService();
      final data = await svc.getTeacherByEmail(user.email);
      final List<String> clzs = (data?['classesHandled'] is List)
          ? List<String>.from(data!['classesHandled'] as List)
          : <String>[];
      List<String> secs = [];
      final rawSections = data?['sections'] ?? data?['section'];
      if (rawSections is List) {
        secs = rawSections
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
      } else if (rawSections is String) {
        secs = rawSections
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
      final sectionDisplay = secs.map((s) => 'Section $s').toList();

      setState(() {
        classes = clzs;
        sections = sectionDisplay;
        selectedClass = classes.isNotEmpty ? classes.first : null;
        selectedSection = sections.isNotEmpty ? sections.first : null;
        _loadingMeta = false;
      });
    } catch (e) {
      setState(() => _loadingMeta = false);
    }
  }

  void _generateQuestions() {
    setState(() {
      isGenerating = true;
    });

    // Simulate AI generation delay
    Future.delayed(const Duration(seconds: 2), () {
      setState(() {
        isGenerating = false;
        hasGenerated = true;
        generatedQuestions = [
          GeneratedQuestion(
            question: 'What is the derivative of x^2?',
            answer: '2x',
            topic: 'Calculus',
            difficulty: 'Medium',
            confidence: 95,
          ),
          GeneratedQuestion(
            question: 'Solve for x: 3x + 5 = 14',
            answer: 'x = 3',
            topic: 'Algebra',
            difficulty: 'Easy',
            confidence: 98,
          ),
          GeneratedQuestion(
            question: 'Calculate the area of a circle with radius 5',
            answer: '25π',
            topic: 'Geometry',
            difficulty: 'Easy',
            confidence: 99,
          ),
        ];
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 80),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInputFields(),
                    const SizedBox(height: 24),
                    _buildGenerateButton(),
                    if (hasGenerated) ...[
                      const SizedBox(height: 32),
                      _buildGeneratedQuestions(),
                      const SizedBox(height: 24),
                      _buildAIMetadata(),
                    ],
                    if (isGenerating) ...[
                      const SizedBox(height: 32),
                      _buildLoadingIndicator(),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new),
                onPressed: () => Navigator.pop(context),
                color: const Color(0xFF6B7280),
              ),
              const Expanded(
                child: Text(
                  'AI Test Generator',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ),
              const SizedBox(width: 48), // Balance the back button
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputFields() {
    if (_loadingMeta) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        _buildTextField(
          label: 'Subject',
          controller: _subjectController,
          placeholder: 'e.g., Mathematics',
        ),
        const SizedBox(height: 16),
        _buildTextField(
          label: 'Topics',
          controller: _topicsController,
          placeholder: 'Algebra, Geometry, Calculus',
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildDropdown(
                label: 'Difficulty',
                value: selectedDifficulty,
                items: difficulties,
                onChanged: (value) {
                  setState(() {
                    selectedDifficulty = value!;
                  });
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTextField(
                label: 'Question Count',
                controller: _questionCountController,
                placeholder: '10',
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildDropdown(
                label: 'Target Class',
                value: selectedClass,
                items: classes,
                onChanged: classes.isEmpty
                    ? null
                    : (value) {
                        setState(() {
                          selectedClass = value;
                        });
                      },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildDropdown(
                label: 'Section',
                value: selectedSection,
                items: sections,
                onChanged: sections.isEmpty
                    ? null
                    : (value) {
                        setState(() {
                          selectedSection = value;
                        });
                      },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required String placeholder,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: placeholder,
            hintStyle: TextStyle(color: Colors.grey[400]),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required void Function(String?)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: DropdownButtonFormField<String>(
            value: (value != null && items.contains(value)) ? value : null,
            isExpanded: true,
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            items: items.map((String item) {
              return DropdownMenuItem<String>(
                value: item,
                child: Text(
                  item,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  softWrap: false,
                ),
              );
            }).toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildGenerateButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: isGenerating ? null : _generateQuestions,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF6366F1),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: isGenerating
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Text(
                'Generate',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Center(
      child: Column(
        children: [
          const CircularProgressIndicator(color: Color(0xFF6366F1)),
          const SizedBox(height: 16),
          Text(
            'Generating questions with AI...',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneratedQuestions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Generated Questions',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),
        const SizedBox(height: 16),
        ...generatedQuestions.map(
          (question) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _buildQuestionCard(question),
          ),
        ),
      ],
    );
  }

  Widget _buildQuestionCard(GeneratedQuestion question) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  question.question,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Suggested Answer: ${question.answer}',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        _buildBadge(
                          question.topic,
                          const Color(0xFFDBEAFE),
                          const Color(0xFF1E40AF),
                        ),
                        const SizedBox(width: 8),
                        _buildBadge(
                          question.difficulty,
                          question.difficulty == 'Easy'
                              ? const Color(0xFFFEF3C7)
                              : question.difficulty == 'Medium'
                              ? const Color(0xFFD1FAE5)
                              : const Color(0xFFFEE2E2),
                          question.difficulty == 'Easy'
                              ? const Color(0xFF92400E)
                              : question.difficulty == 'Medium'
                              ? const Color(0xFF065F46)
                              : const Color(0xFF991B1B),
                        ),
                      ],
                    ),
                    Text(
                      'Confidence: ${question.confidence}%',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            color: const Color(0xFFF9FAFB),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      generatedQuestions.remove(question);
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Question rejected')),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF374151),
                    side: BorderSide(color: Colors.grey[300]!),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Reject',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Question accepted')),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Accept',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String text, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildAIMetadata() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'AI Metadata',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 16),
          _buildMetadataRow(
            'Prompt:',
            'Subject: ${_subjectController.text}, Topics: ${_topicsController.text}, Difficulty: $selectedDifficulty...',
          ),
          const SizedBox(height: 8),
          _buildMetadataRow('Generated:', 'Oct 26, 2023, 2:30 PM'),
          const SizedBox(height: 8),
          _buildMetadataRow('Token Estimate:', '~1500 tokens'),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.security, size: 16, color: Colors.grey[500]),
              const SizedBox(width: 4),
              Text(
                'API key stored server-side',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Draft saved!')),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF374151),
                    side: BorderSide(color: Colors.grey[300]!),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Save as Draft',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    _showAssignDialog();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Assign',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataRow(String label, String value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
        children: [
          TextSpan(
            text: label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const TextSpan(text: ' '),
          TextSpan(text: value),
        ],
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
      ),
      child: SafeArea(
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(
                icon: Icons.dashboard,
                label: 'Dashboard',
                index: 0,
              ),
              _buildNavItem(icon: Icons.school, label: 'Classes', index: 1),
              _buildNavItem(icon: Icons.group, label: 'Students', index: 2),
              _buildNavItem(icon: Icons.chat, label: 'Messages', index: 3),
              _buildNavItem(icon: Icons.settings, label: 'Settings', index: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required int index,
  }) {
    final isSelected = selectedNavIndex == index;
    final color = isSelected
        ? const Color(0xFF6366F1)
        : const Color(0xFF6B7280);

    return InkWell(
      onTap: () {
        setState(() {
          selectedNavIndex = index;
        });
        if (index == 0) {
          Navigator.popUntil(context, (route) => route.isFirst);
          Navigator.pushNamed(context, '/teacher-dashboard');
        }
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  void _showAssignDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Assign Test'),
        content: const Text(
          'Are you sure you want to assign this AI-generated test to students?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _saveGeneratedTest(publish: true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
            ),
            child: const Text('Assign'),
          ),
        ],
      ),
    );
  }
}

// Generated Question model
class GeneratedQuestion {
  final String question;
  final String answer;
  final String topic;
  final String difficulty;
  final int confidence;

  GeneratedQuestion({
    required this.question,
    required this.answer,
    required this.topic,
    required this.difficulty,
    required this.confidence,
  });
}

extension on _AITestGeneratorScreenState {
  Future<void> _saveGeneratedTest({required bool publish}) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final testProv = Provider.of<TestProvider>(context, listen: false);
    final user = auth.currentUser;

    if (user == null || user.role != UserRole.teacher) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login as a teacher to continue')),
      );
      return;
    }

    if (_subjectController.text.trim().isEmpty || generatedQuestions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Generate questions before assigning')),
      );
      return;
    }

    final normalizedSection = (selectedSection ?? '')
        .replaceAll('Section ', '')
        .trim();
    final duration =
        int.tryParse(_questionCountController.text.trim()) ?? 30; // fallback
    final now = DateTime.now();
    final startDate = now;
    final endDate = now.add(Duration(minutes: duration));
    final status = publish ? tm.TestStatus.published : tm.TestStatus.draft;

    final modelQuestions = generatedQuestions.map((gq) {
      return tm.Question(
        id: gq.question.hashCode.toString(),
        type: tm.QuestionType.shortAnswer,
        question: gq.question,
        options: null,
        correctAnswer: gq.answer,
        points: 1,
      );
    }).toList();

    // Pre-compute assigned students when publishing
    List<String> assignedIds = const [];
    if (publish &&
        (selectedClass ?? '').isNotEmpty &&
        normalizedSection.isNotEmpty) {
      try {
        final teacherData = await TeacherService().getTeacherByEmail(
          user.email,
        );
        final schoolCode = teacherData?['schoolCode'] ?? user.instituteId ?? '';
        // Let FirestoreService handle assignment using Auth UIDs post-create
        // to prevent mismatched IDs. Keep empty here; it will be set server-side.
        assignedIds = const [];
      } catch (_) {
        assignedIds = const [];
      }
    }

    final test = tm.TestModel(
      id: '',
      title: '${_subjectController.text.trim()} - AI Generated Test',
      description:
          'Auto-generated by AI from topics: ${_topicsController.text.trim()}',
      teacherId: user.uid,
      teacherName: user.name,
      instituteId: user.instituteId ?? '',
      subject: _subjectController.text.trim(),
      className: selectedClass,
      section: normalizedSection,
      questions: modelQuestions,
      totalPoints: modelQuestions.fold<int>(0, (sum, q) => sum + q.points),
      duration: duration,
      startDate: startDate,
      endDate: endDate,
      status: status,
      assignedStudentIds: assignedIds,
      createdAt: now,
      updatedAt: now,
    );

    final ok = await testProv.createTest(test);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Test created successfully')),
      );
      if (mounted) {
        Navigator.popUntil(context, (route) => route.isFirst);
        Navigator.pushNamed(context, '/teacher-dashboard');
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed: ${testProv.errorMessage ?? 'Unknown error'}'),
        ),
      );
    }
  }
}
