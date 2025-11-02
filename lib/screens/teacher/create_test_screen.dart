import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/test_model.dart' as tm;
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/test_provider.dart';
import '../../services/teacher_service.dart';
import '../../widgets/teacher_bottom_nav.dart';
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
  final _focusNode = FocusNode();

  String? selectedSubject;
  String? selectedClass;
  String? selectedSection; // Display format: "Section A"
  bool aiAssistanceEnabled = true;

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
    _focusNode.dispose();
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

      // Get subjects (fallback to parse from classAssignments if needed)
      List<String> subjs = (data?['subjectsHandled'] is List)
          ? List<String>.from(data!['subjectsHandled'] as List)
          : <String>[];
      if (subjs.isEmpty && data?['classAssignments'] is List) {
        final Set<String> uniqueSubjects = {};
        for (final assignment in (data!['classAssignments'] as List)) {
          final s = assignment.toString(); // e.g., "Grade 10: A, Science"
          final parts = s.split(':');
          if (parts.length >= 2) {
            final right = parts[1]; // " A, Science"
            final commaParts = right.split(',');
            if (commaParts.length >= 2) {
              final subject = commaParts[1].trim();
              if (subject.isNotEmpty) uniqueSubjects.add(subject);
            }
          }
        }
        subjs = uniqueSubjects.toList()..sort();
      }

      // Get formatted classes using the service (handles both formats)
      final dynamic sectionsData = data?['sections'] ?? data?['section'];
      final List<String> formattedClasses = svc.getTeacherClasses(
        data?['classesHandled'],
        sectionsData,
        classAssignments: data?['classAssignments'],
      );

      // Extract unique sections from formatted classes
      // Format is "10 - A", "10 - B", etc.
      final Set<String> uniqueSections = {};
      final Set<String> uniqueGrades = {};
      for (final cls in formattedClasses) {
        final parts = cls.split(' - ');
        if (parts.length == 2) {
          uniqueSections.add(parts[1]); // Extract "A", "B", etc.
          uniqueGrades.add(
            parts[0].trim(),
          ); // Extract just the standard (e.g., "10")
        }
      }
      final sectionDisplay = uniqueSections.map((s) => 'Section $s').toList()
        ..sort();
      final List<String> gradeOnlyList = uniqueGrades.toList()..sort();

      setState(() {
        subjects = subjs;
        // Show only the standard (grade) in the class dropdown
        classes = gradeOnlyList;
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
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 160),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionHeader('METADATA'),
                        const SizedBox(height: 16),
                        _loadingMeta
                            ? const Center(child: CircularProgressIndicator())
                            : _buildMetadataCard(theme),
                        const SizedBox(height: 32),
                        _buildSectionHeader('QUESTIONS'),
                        const SizedBox(height: 16),
                        _buildQuestions(theme),
                        const SizedBox(height: 16),
                        _buildAddQuestionButton(theme),
                      ],
                    ),
                  ),
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
        color: Theme.of(context).cardColor,
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
                color: Theme.of(context).iconTheme.color,
              ),
              Text(
                'Create Test',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () {
                  // Handle more options
                },
                color: Theme.of(context).iconTheme.color,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.labelSmall?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
        color: theme.colorScheme.onSurface.withOpacity(0.6),
      ),
    );
  }

  Widget _buildMetadataCard(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
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
                  keyboardType: TextInputType.number,
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
                    color: theme.colorScheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'AI Assistance',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
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
                activeColor: theme.colorScheme.primary,
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
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: placeholder,
            hintStyle: TextStyle(
              color: theme.colorScheme.onSurface.withOpacity(0.4),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.dividerColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: theme.dividerColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: theme.colorScheme.primary,
                width: 2,
              ),
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
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.dividerColor),
          ),
          child: DropdownButtonFormField<String>(
            value: (value != null && items.contains(value)) ? value : null,
            isExpanded: true,
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
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

  Widget _buildQuestions(ThemeData theme) {
    return Column(
      children: questions.map((question) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildQuestionCard(theme, question),
        );
      }).toList(),
    );
  }

  Widget _buildQuestionCard(ThemeData theme, Question question) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
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
                  Icon(
                    Icons.drag_indicator,
                    color: theme.iconTheme.color?.withOpacity(0.4),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Question ${question.id}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        question.type == QuestionType.multipleChoice
                            ? 'Multiple Choice'
                            : 'Short Answer',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 14,
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
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
                      color: theme.iconTheme.color?.withOpacity(0.6),
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
                    icon: Icon(
                      Icons.delete,
                      size: 18,
                      color: theme.colorScheme.error,
                    ),
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
              hintStyle: TextStyle(
                color: theme.colorScheme.onSurface.withOpacity(0.4),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: theme.dividerColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: theme.dividerColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: theme.colorScheme.primary,
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
            _buildMultipleChoiceOptions(theme, question),
          ],
        ],
      ),
    );
  }

  Widget _buildMultipleChoiceOptions(ThemeData theme, Question question) {
    return Column(
      children: [
        ...List.generate(question.options!.length, (index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: question.correctAnswerIndex == index
                      ? theme.colorScheme.primary
                      : theme.dividerColor,
                  width: question.correctAnswerIndex == index ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(12),
                color: question.correctAnswerIndex == index
                    ? theme.colorScheme.primary.withOpacity(0.05)
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
                activeColor: theme.colorScheme.primary,
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
              foregroundColor: theme.colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAddQuestionButton(ThemeData theme) {
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
            color: theme.dividerColor,
            width: 2,
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, color: theme.iconTheme.color?.withOpacity(0.6)),
            const SizedBox(width: 8),
            Text(
              'Add Question',
              style: theme.textTheme.bodyLarge?.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withOpacity(0.7),
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
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
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
                        // Dismiss keyboard before saving
                        FocusScope.of(context).unfocus();
                        _saveTest(publish: false);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.surfaceVariant,
                        foregroundColor: theme.colorScheme.onSurface,
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
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary,
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
            const TeacherBottomNav(selectedIndex: 2),
          ],
        ),
      ),
    );
  }

  void _showPublishDialog() {
    // Dismiss keyboard before showing dialog
    FocusScope.of(context).unfocus();

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
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
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

    // Build className and section from separate dropdowns
    final gradeClassName = 'Grade ${selectedClass!.trim()}';
    final normalizedSection = (selectedSection ?? '')
        .replaceAll('Section ', '')
        .trim();

    final test = tm.TestModel(
      id: '',
      title: _titleController.text.trim(),
      description: '',
      teacherId: user.uid,
      teacherName: user.name,
      instituteId: user.instituteId ?? '',
      subject: selectedSubject!,
      className: gradeClassName,
      section: normalizedSection,
      questions: modelQuestions,
      totalPoints: totalPoints,
      duration: duration,
      startDate: startDate,
      endDate: endDate,
      status: status,
      assignedStudentIds: const [],
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
