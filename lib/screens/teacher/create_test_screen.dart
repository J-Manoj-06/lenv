import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/test_model.dart' as tm;
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/test_provider.dart';
import '../../services/teacher_service.dart';
// import 'package:cloud_firestore/cloud_firestore.dart'; // no longer needed: assignment computed server-side

class CreateTestScreen extends StatefulWidget {
  const CreateTestScreen({Key? key}) : super(key: key);

  @override
  State<CreateTestScreen> createState() => _CreateTestScreenState();
}

class _CreateTestScreenState extends State<CreateTestScreen> {
  final _titleController = TextEditingController();
  final _totalMarksController = TextEditingController();
  final _timeLimitController = TextEditingController();

  String? selectedSubject;
  String? selectedClass;
  String? selectedSection; // Display format: "Section A"
  bool aiAssistanceEnabled = true;
  int selectedNavIndex = 0;

  List<Question> questions = [
    Question(
      id: 1,
      type: QuestionType.multipleChoice,
      questionText: '',
      options: ['3', '4', '5'],
      correctAnswerIndex: 1,
    ),
    Question(id: 2, type: QuestionType.shortAnswer, questionText: ''),
  ];
  // Dynamic lists populated from teacher profile
  List<String> subjects = [];
  List<String> classes = [];
  List<String> sections = [];

  bool _loadingMeta = true;

  @override
  void dispose() {
    _titleController.dispose();
    _totalMarksController.dispose();
    _timeLimitController.dispose();
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
      final List<String> subjs = (data?['subjectsHandled'] is List)
          ? List<String>.from(data!['subjectsHandled'] as List)
          : <String>[];
      final List<String> clzs = (data?['classesHandled'] is List)
          ? List<String>.from(data!['classesHandled'] as List)
          : <String>[];
      // sections may be list or comma-separated string
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
      // Display sections as "Section X"
      final sectionDisplay = secs.map((s) => 'Section $s').toList();

      setState(() {
        subjects = subjs;
        classes = clzs;
        sections = sectionDisplay;
        selectedSubject = subjects.isNotEmpty ? subjects.first : null;
        selectedClass = classes.isNotEmpty ? classes.first : null;
        selectedSection = sections.isNotEmpty ? sections.first : null;
        _loadingMeta = false;
      });
    } catch (e) {
      setState(() => _loadingMeta = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 160),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader('METADATA'),
                    const SizedBox(height: 16),
                    _loadingMeta
                        ? const Center(child: CircularProgressIndicator())
                        : _buildMetadataCard(),
                    const SizedBox(height: 32),
                    _buildSectionHeader('QUESTIONS'),
                    const SizedBox(height: 16),
                    _buildQuestions(),
                    const SizedBox(height: 16),
                    _buildAddQuestionButton(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomSection(),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
                color: const Color(0xFF2D3748),
              ),
              const Text(
                'Create Test',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D3748),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () {
                  // Handle more options
                },
                color: const Color(0xFF2D3748),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: Color(0xFF6B7280),
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildMetadataCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          _buildTextField(
            label: 'Title',
            controller: _titleController,
            placeholder: 'e.g. Mid-term Algebra Exam',
          ),
          const SizedBox(height: 16),
          // Subject and Class
          Row(
            children: [
              Expanded(
                child: _buildDropdown(
                  label: 'Subject',
                  value: selectedSubject,
                  items: subjects,
                  onChanged: subjects.isEmpty
                      ? null
                      : (value) {
                          setState(() {
                            selectedSubject = value;
                          });
                        },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildDropdown(
                  label: 'Class',
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
            ],
          ),
          const SizedBox(height: 16),
          // Section
          _buildDropdown(
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
          const SizedBox(height: 16),
          // Total Marks and Time Limit
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  label: 'Total Marks',
                  controller: _totalMarksController,
                  placeholder: 'e.g. 100',
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildTextField(
                  label: 'Time Limit',
                  controller: _timeLimitController,
                  placeholder: 'e.g. 90 mins',
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // AI Assistance Toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome,
                    color: const Color(0xFF6366F1),
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'AI Assistance',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF2D3748),
                    ),
                  ),
                ],
              ),
              Switch(
                value: aiAssistanceEnabled,
                onChanged: (value) {
                  setState(() {
                    aiAssistanceEnabled = value;
                  });
                },
                activeColor: const Color(0xFF6366F1),
              ),
            ],
          ),
        ],
      ),
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

  Widget _buildQuestions() {
    return Column(
      children: questions.map((question) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildQuestionCard(question),
        );
      }).toList(),
    );
  }

  Widget _buildQuestionCard(Question question) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Question header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.drag_indicator, color: Colors.grey[400]),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Question ${question.id}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D3748),
                        ),
                      ),
                      Text(
                        question.type == QuestionType.multipleChoice
                            ? 'Multiple Choice'
                            : 'Short Answer',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.content_copy,
                      size: 18,
                      color: Colors.grey[600],
                    ),
                    onPressed: () {
                      // Duplicate question
                      setState(() {
                        questions.add(
                          Question(
                            id: questions.length + 1,
                            type: question.type,
                            questionText: question.questionText,
                            options: question.options != null
                                ? List.from(question.options!)
                                : null,
                            correctAnswerIndex: question.correctAnswerIndex,
                          ),
                        );
                      });
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                    onPressed: () {
                      // Delete question
                      setState(() {
                        questions.removeWhere((q) => q.id == question.id);
                        // Renumber questions
                        for (int i = 0; i < questions.length; i++) {
                          questions[i].id = i + 1;
                        }
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Question text
          TextField(
            maxLines: 3,
            decoration: InputDecoration(
              hintText: question.type == QuestionType.multipleChoice
                  ? 'What is 2 + 2?'
                  : 'Explain the theory of relativity.',
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
                borderSide: const BorderSide(
                  color: Color(0xFF6366F1),
                  width: 2,
                ),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
            onChanged: (value) {
              question.questionText = value;
            },
          ),
          if (question.type == QuestionType.multipleChoice) ...[
            const SizedBox(height: 16),
            _buildMultipleChoiceOptions(question),
          ],
        ],
      ),
    );
  }

  Widget _buildMultipleChoiceOptions(Question question) {
    return Column(
      children: [
        ...List.generate(question.options!.length, (index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: question.correctAnswerIndex == index
                      ? const Color(0xFF6366F1)
                      : Colors.grey[300]!,
                  width: question.correctAnswerIndex == index ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(12),
                color: question.correctAnswerIndex == index
                    ? const Color(0xFF6366F1).withOpacity(0.05)
                    : Colors.transparent,
              ),
              child: RadioListTile<int>(
                value: index,
                groupValue: question.correctAnswerIndex,
                onChanged: (value) {
                  setState(() {
                    question.correctAnswerIndex = value;
                  });
                },
                activeColor: const Color(0xFF6366F1),
                title: TextField(
                  controller: TextEditingController(
                    text: question.options![index],
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (value) {
                    question.options![index] = value;
                  },
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () {
              setState(() {
                question.options!.add('');
              });
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Option'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF6366F1),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAddQuestionButton() {
    return InkWell(
      onTap: () {
        _showAddQuestionDialog();
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          border: Border.all(
            color: Colors.grey[300]!,
            width: 2,
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, color: Colors.grey[600]),
            const SizedBox(width: 8),
            Text(
              'Add Question',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddQuestionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Question'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Multiple Choice'),
              leading: const Icon(Icons.radio_button_checked),
              onTap: () {
                setState(() {
                  questions.add(
                    Question(
                      id: questions.length + 1,
                      type: QuestionType.multipleChoice,
                      questionText: '',
                      options: ['', '', ''],
                      correctAnswerIndex: 0,
                    ),
                  );
                });
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Short Answer'),
              leading: const Icon(Icons.short_text),
              onTap: () {
                setState(() {
                  questions.add(
                    Question(
                      id: questions.length + 1,
                      type: QuestionType.shortAnswer,
                      questionText: '',
                    ),
                  );
                });
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Action buttons
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        _saveTest(publish: false);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE5E7EB),
                        foregroundColor: const Color(0xFF2D3748),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Save Draft',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        _showPublishDialog();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Publish & Assign',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Bottom navigation
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey[200]!)),
              ),
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
                    _buildNavItem(
                      icon: Icons.school,
                      label: 'Classes',
                      index: 1,
                    ),
                    _buildNavItem(
                      icon: Icons.assignment,
                      label: 'Tests',
                      index: 2,
                    ),
                    _buildNavItem(
                      icon: Icons.leaderboard,
                      label: 'Leaderboard',
                      index: 3,
                    ),
                    _buildNavItem(
                      icon: Icons.person,
                      label: 'Profile',
                      index: 4,
                    ),
                  ],
                ),
              ),
            ),
          ],
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
    final color = isSelected ? const Color(0xFF6366F1) : Colors.grey[500];

    return InkWell(
      onTap: () {
        setState(() {
          selectedNavIndex = index;
        });
        // Handle navigation
        if (index == 0) {
          Navigator.pop(context); // Go back to dashboard
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

  void _showPublishDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Publish Test'),
        content: const Text(
          'Are you sure you want to publish and assign this test to students?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _saveTest(publish: true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
            ),
            child: const Text('Publish'),
          ),
        ],
      ),
    );
  }
}

// Question model
enum QuestionType { multipleChoice, shortAnswer }

class Question {
  int id;
  QuestionType type;
  String questionText;
  List<String>? options;
  int? correctAnswerIndex;

  Question({
    required this.id,
    required this.type,
    required this.questionText,
    this.options,
    this.correctAnswerIndex,
  });
}

extension on _CreateTestScreenState {
  Future<void> _saveTest({required bool publish}) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final testProv = Provider.of<TestProvider>(context, listen: false);
    final user = auth.currentUser;

    if (user == null || user.role != UserRole.teacher) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login as a teacher to continue')),
      );
      return;
    }

    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a test title')),
      );
      return;
    }

    if (selectedSubject == null || selectedSubject!.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a subject')));
      return;
    }
    if (selectedClass == null || selectedClass!.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a class')));
      return;
    }
    if (selectedSection == null || selectedSection!.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a section')));
      return;
    }

    // Normalize fields
    final normalizedSection = selectedSection!
        .replaceAll('Section ', '')
        .trim();
    final duration = int.tryParse(_timeLimitController.text.trim()) ?? 60;
    final now = DateTime.now();
    final startDate = now;
    final endDate = now.add(Duration(minutes: duration));
    final status = publish ? tm.TestStatus.published : tm.TestStatus.draft;

    // Map local questions to model questions
    final modelQuestions = questions.map((q) {
      return tm.Question(
        id: q.id.toString(),
        type: q.type == QuestionType.multipleChoice
            ? tm.QuestionType.multipleChoice
            : tm.QuestionType.shortAnswer,
        question: q.questionText,
        options: q.options,
        correctAnswer:
            (q.type == QuestionType.multipleChoice &&
                q.correctAnswerIndex != null &&
                q.options != null &&
                q.correctAnswerIndex! >= 0 &&
                q.correctAnswerIndex! < q.options!.length)
            ? q.options![q.correctAnswerIndex!]
            : null,
        points: 1,
      );
    }).toList();

    final totalPoints =
        int.tryParse(_totalMarksController.text.trim()) ??
        modelQuestions.fold<int>(0, (sum, q) => sum + q.points);

    // Let the backend service compute correct assignedStudentIds using Auth UIDs
    // to avoid race conditions or mismatched IDs from the students collection.
    final List<String> assignedIds = const [];

    final test = tm.TestModel(
      id: '',
      title: _titleController.text.trim(),
      description: '',
      teacherId: user.uid,
      teacherName: user.name,
      instituteId: user.instituteId ?? '',
      subject: selectedSubject!,
      className: selectedClass!,
      section: normalizedSection,
      questions: modelQuestions,
      totalPoints: totalPoints,
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
      if (publish) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Test published successfully!')),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Draft saved!')));
      }
      if (mounted) {
        Navigator.pop(context);
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
