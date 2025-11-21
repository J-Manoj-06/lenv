import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/test_model.dart' as tm;
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/test_provider.dart';
import '../../services/teacher_service.dart';
import '../../services/ai_test_service.dart';
import '../../widgets/teacher_bottom_nav.dart';
// import 'package:cloud_firestore/cloud_firestore.dart'; // not needed; assignment handled server-side

class AITestGeneratorScreen extends StatefulWidget {
  const AITestGeneratorScreen({Key? key}) : super(key: key);

  @override
  State<AITestGeneratorScreen> createState() => _AITestGeneratorScreenState();
}

class _AITestGeneratorScreenState extends State<AITestGeneratorScreen> {
  final _testNameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _subjectController = TextEditingController();
  final _topicsController = TextEditingController();
  final _questionCountController = TextEditingController();
  final _totalMarksController = TextEditingController();

  String selectedDifficulty = 'Medium';
  String? selectedClass;
  String? selectedSection; // Display: "Section A"
  int selectedNavIndex = 0;

  bool isGenerating = false;
  bool hasGenerated = false;
  bool autoPublish = false;

  List<GeneratedQuestion> generatedQuestions = [];

  final List<String> difficulties = ['Easy', 'Medium', 'Hard', 'Mixed'];
  List<String> classes = [];
  List<String> sections = [];
  // Map of grade -> sections available for that grade
  final Map<String, List<String>> _gradeSections = {};
  bool _loadingMeta = true;

  // Scheduling state (always visible; defaults to now)
  DateTime? _scheduledDate;
  TimeOfDay? _scheduledTime;
  TimeOfDay? _endTime;
  Duration? _calculatedDuration;

  @override
  void dispose() {
    _testNameController.dispose();
    _descriptionController.dispose();
    _subjectController.dispose();
    _topicsController.dispose();
    _questionCountController.dispose();
    _totalMarksController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadTeacherMeta();
    final now = DateTime.now();
    _scheduledDate = DateTime(now.year, now.month, now.day);
    _scheduledTime = TimeOfDay(hour: now.hour, minute: now.minute);
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

      // Get formatted classes using the service (handles both formats)
      final dynamic sectionsData = data?['sections'] ?? data?['section'];
      final List<String> formattedClasses = svc.getTeacherClasses(
        data?['classesHandled'],
        sectionsData,
        classAssignments: data?['classAssignments'],
      );

      // Build grade -> sections map
      _gradeSections.clear();
      for (final cls in formattedClasses) {
        final parts = cls.split(' - ');
        if (parts.length == 2) {
          final grade = parts[0].trim();
          final section = parts[1].trim();
          _gradeSections.putIfAbsent(grade, () => <String>[]);
          if (!_gradeSections[grade]!.contains(section)) {
            _gradeSections[grade]!.add(section);
          }
        }
      }
      // Sort grades and sections
      final List<String> gradeOnlyList = _gradeSections.keys.toList()..sort();
      for (final entry in _gradeSections.entries) {
        entry.value.sort();
      }
      // Initialize sections for the first grade
      final String? initialGrade = gradeOnlyList.isNotEmpty
          ? gradeOnlyList.first
          : null;
      final List<String> initialSections = initialGrade != null
          ? (_gradeSections[initialGrade] ?? <String>[])
          : <String>[];
      final List<String> sectionDisplay =
          initialSections.map((s) => 'Section $s').toList()..sort();

      setState(() {
        // Show only the standard (grade) in the class dropdown
        classes = gradeOnlyList;
        sections = sectionDisplay;
        selectedClass = initialGrade;
        selectedSection = sections.isNotEmpty ? sections.first : null;
        _loadingMeta = false;
      });
    } catch (e) {
      setState(() => _loadingMeta = false);
    }
  }

  void _generateQuestions() {
    // Validate inputs
    if (_testNameController.text.trim().isEmpty) {
      _showErrorDialog('\u26a0\ufe0f Please enter a test name');
      setState(() => isGenerating = false);
      return;
    }
    if (selectedClass == null || selectedClass!.isEmpty) {
      _showErrorDialog('\u26a0\ufe0f Please select a class');
      setState(() => isGenerating = false);
      return;
    }
    if (selectedSection == null || selectedSection!.isEmpty) {
      _showErrorDialog('\u26a0\ufe0f Please select a section');
      setState(() => isGenerating = false);
      return;
    }
    if (_subjectController.text.trim().isEmpty) {
      _showErrorDialog('\u26a0\ufe0f Please enter a subject');
      setState(() => isGenerating = false);
      return;
    }
    if (_topicsController.text.trim().isEmpty) {
      _showErrorDialog('\u26a0\ufe0f Please enter a topic');
      setState(() => isGenerating = false);
      return;
    }
    if (_questionCountController.text.trim().isEmpty) {
      _showErrorDialog('\u26a0\ufe0f Please enter the number of questions');
      setState(() => isGenerating = false);
      return;
    }
    if (_totalMarksController.text.trim().isEmpty) {
      _showErrorDialog('\u26a0\ufe0f Please enter total marks');
      setState(() => isGenerating = false);
      return;
    }

    final questionCount = int.tryParse(_questionCountController.text.trim());
    if (questionCount == null || questionCount <= 0 || questionCount > 50) {
      _showErrorDialog(
        '\u26a0\ufe0f Please enter a valid number of questions (1-50)',
      );
      setState(() => isGenerating = false);
      return;
    }

    final totalMarks = int.tryParse(_totalMarksController.text.trim());
    if (totalMarks == null || totalMarks <= 0) {
      _showErrorDialog('\u26a0\ufe0f Please enter valid total marks');
      setState(() => isGenerating = false);
      return;
    }

    if (totalMarks < questionCount) {
      _showErrorDialog(
        '\u26a0\ufe0f Total marks must be at least equal to number of questions',
      );
      setState(() => isGenerating = false);
      return;
    }

    setState(() {
      isGenerating = true;
    });

    // Call AI Test Service (Firebase proxy)
    final aiTestService = AITestService();

    // Extract section from selectedSection (format: "Section A" -> "A")
    String sectionValue = selectedSection?.replaceFirst('Section ', '') ?? 'A';

    // Fetch previous questions for uniqueness check
    _fetchPreviousQuestions(
          className: selectedClass!,
          section: sectionValue,
          subject: _subjectController.text.trim(),
        )
        .then((previousQuestions) {
          return aiTestService.generateTest(
            className: selectedClass!,
            section: sectionValue,
            subject: _subjectController.text.trim(),
            topic: _topicsController.text.trim(),
            difficulty: selectedDifficulty,
            totalMarks: totalMarks,
            numQuestions: questionCount,
            previousQuestions: previousQuestions,
          );
        })
        .then((testQuestions) {
          setState(() {
            isGenerating = false;
            hasGenerated = true;
            generatedQuestions = testQuestions.map((q) {
              return GeneratedQuestion(
                question: q.questionText,
                answer: q.correctAnswer,
                options: q.options ?? [],
                explanation: '', // TestQuestion model doesn't have explanation
                topic: _topicsController.text.trim(),
                difficulty: selectedDifficulty,
                confidence: 95, // High confidence for AI-generated questions
                points: q.marks,
              );
            }).toList();
          });

          if (mounted && generatedQuestions.isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '✨ Generated ${generatedQuestions.length} questions successfully!',
                ),
                backgroundColor: Colors.green,
              ),
            );
          }
        })
        .catchError((error) {
          setState(() {
            isGenerating = false;
          });

          String errorMessage = 'Failed to generate questions.';
          if (error.toString().contains('network') ||
              error.toString().contains('connection')) {
            errorMessage =
                'Network error. Please check your internet connection.';
          } else if (error.toString().contains('timeout')) {
            errorMessage = 'Request timed out. Please try again.';
          } else if (error.toString().contains('rate limit')) {
            errorMessage =
                'Too many requests. Please wait a moment and try again.';
          }

          _showErrorDialog('$errorMessage\n\n$error');
        });
  }

  /// Fetch previous questions from Firestore for the same class, section, and subject
  Future<List<Map<String, dynamic>>> _fetchPreviousQuestions({
    required String className,
    required String section,
    required String subject,
  }) async {
    try {
      final tests = await FirebaseFirestore.instance
          .collection('scheduledTests')
          .where('className', isEqualTo: className)
          .where('section', isEqualTo: section)
          .where('subject', isEqualTo: subject)
          .orderBy('createdAt', descending: true)
          .limit(5) // Get last 5 tests
          .get();

      final List<Map<String, dynamic>> allQuestions = [];

      for (var testDoc in tests.docs) {
        final testData = testDoc.data();
        final questions = testData['questions'] as List<dynamic>?;

        if (questions != null) {
          for (var q in questions) {
            if (q is Map<String, dynamic>) {
              allQuestions.add({
                'questionText': q['question'] ?? q['questionText'] ?? '',
                'type': q['type'] ?? 'mcq',
              });
            }
          }
        }
      }

      print(
        '📚 Fetched ${allQuestions.length} previous questions for uniqueness check',
      );
      return allQuestions;
    } catch (e) {
      print('⚠️ Error fetching previous questions: $e');
      return [];
    }
  }

  void _showErrorDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new),
                onPressed: () => Navigator.pop(context),
                color: Theme.of(context).iconTheme.color,
              ),
              Expanded(
                child: Text(
                  'AI Test Generator',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.headlineLarge?.color,
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header: Test Metadata
        Text(
          '📝 Test Metadata',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).primaryColor,
          ),
        ),
        const SizedBox(height: 16),

        // Test Name (Required)
        _buildTextField(
          label: 'Test Name *',
          controller: _testNameController,
          placeholder: 'e.g., Chapter 5 Quiz',
        ),
        const SizedBox(height: 16),

        // Description (Optional)
        _buildTextField(
          label: 'Description (Optional)',
          controller: _descriptionController,
          placeholder: 'Brief description of the test...',
          maxLines: 2,
        ),
        const SizedBox(height: 16),

        // 2-Column Grid: Class and Section
        Row(
          children: [
            Expanded(
              child: _buildDropdown(
                label: 'Class *',
                value: selectedClass,
                items: classes,
                onChanged: classes.isEmpty
                    ? null
                    : (value) {
                        setState(() {
                          selectedClass = value;
                          // Update sections based on selected class
                          final grade = (selectedClass ?? '').trim();
                          final secList = _gradeSections[grade] ?? <String>[];
                          sections = secList.map((s) => 'Section $s').toList()
                            ..sort();
                          if (!sections.contains(selectedSection)) {
                            selectedSection = sections.isNotEmpty
                                ? sections.first
                                : null;
                          }
                        });
                      },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildDropdown(
                label: 'Section *',
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
        const SizedBox(height: 16),

        // Subject and Topic
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                label: 'Subject *',
                controller: _subjectController,
                placeholder: 'e.g., Mathematics',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTextField(
                label: 'Topic *',
                controller: _topicsController,
                placeholder: 'e.g., Algebra',
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Section Header: AI Question Generation
        Text(
          '🤖 AI Question Generation',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).primaryColor,
          ),
        ),
        const SizedBox(height: 16),

        // Difficulty, Question Count, Total Marks
        Row(
          children: [
            Expanded(
              child: _buildDropdown(
                label: 'Difficulty *',
                value: selectedDifficulty,
                items: difficulties,
                onChanged: (value) {
                  setState(() {
                    selectedDifficulty = value!;
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTextField(
                label: 'Questions *',
                controller: _questionCountController,
                placeholder: '10',
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTextField(
                label: 'Total Marks *',
                controller: _totalMarksController,
                placeholder: '20',
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildScheduleSection(),
      ],
    );
  }

  Widget _buildScheduleSection() {
    final theme = Theme.of(context);
    final dateText = _scheduledDate == null
        ? 'Select date'
        : '${_scheduledDate!.year}-${_scheduledDate!.month.toString().padLeft(2, '0')}-${_scheduledDate!.day.toString().padLeft(2, '0')}';
    final startTimeText = _scheduledTime == null
        ? 'Select time'
        : _scheduledTime!.format(context);
    final endTimeText = _endTime == null
        ? 'Select time'
        : _endTime!.format(context);
    final durationText = _calculatedDuration != null
        ? '${_calculatedDuration!.inMinutes} min'
        : 'Auto';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '🗓️ Schedule Test',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: theme.textTheme.titleLarge?.color,
            ),
          ),
          const SizedBox(height: 12),
          // Date Picker
          _buildScheduleTile(
            icon: Icons.calendar_today,
            label: 'Date',
            value: dateText,
            onTap: _pickDate,
          ),
          const SizedBox(height: 12),
          // Start and End Time (2 columns)
          Row(
            children: [
              Expanded(
                child: _buildScheduleTile(
                  icon: Icons.access_time,
                  label: 'Start Time',
                  value: startTimeText,
                  onTap: _pickStartTime,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildScheduleTile(
                  icon: Icons.access_time_filled,
                  label: 'End Time',
                  value: endTimeText,
                  onTap: _pickEndTime,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Duration Display
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.timer_outlined, size: 20, color: theme.primaryColor),
                const SizedBox(width: 8),
                Text(
                  'Duration: $durationText',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: theme.primaryColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Auto-publish Switch
          Container(
            decoration: BoxDecoration(
              color: theme.primaryColor.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.primaryColor.withOpacity(0.2)),
            ),
            child: SwitchListTile(
              title: Text(
                'Auto-publish when test starts',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: theme.textTheme.bodyLarge?.color,
                ),
              ),
              subtitle: Text(
                'Students will see test automatically at start time',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.textTheme.bodySmall?.color,
                ),
              ),
              value: autoPublish,
              activeColor: theme.primaryColor,
              onChanged: (value) {
                setState(() {
                  autoPublish = value;
                });
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tip: Set start/end times to auto-calculate duration',
            style: TextStyle(
              fontSize: 12,
              color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleTile({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.dividerColor),
          color: theme.inputDecorationTheme.fillColor ?? theme.cardColor,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: theme.iconTheme.color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: theme.textTheme.bodyLarge?.color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required String placeholder,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
          decoration: InputDecoration(
            hintText: placeholder,
            hintStyle: TextStyle(color: Theme.of(context).hintColor),
            filled: true,
            fillColor:
                Theme.of(context).inputDecorationTheme.fillColor ??
                Theme.of(context).cardColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).dividerColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).dividerColor),
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
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).dividerColor),
            color:
                Theme.of(context).inputDecorationTheme.fillColor ??
                Theme.of(context).cardColor,
          ),
          child: DropdownButtonFormField<String>(
            value: (value != null && items.contains(value)) ? value : null,
            isExpanded: true,
            dropdownColor: Theme.of(context).cardColor,
            style: TextStyle(
              color: Theme.of(context).textTheme.bodyLarge?.color,
            ),
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
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(
                context,
              ).textTheme.bodyMedium?.color?.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneratedQuestions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Generated Questions',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).textTheme.headlineLarge?.color,
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
        color: Theme.of(context).cardColor,
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
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).textTheme.titleLarge?.color,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Suggested Answer: ${question.answer}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.color?.withOpacity(0.7),
                  ),
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
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Regenerate button
                OutlinedButton.icon(
                  onPressed: () {
                    // TODO: Implement regenerate single question
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('\ud83d\udd04 Regenerating question...'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Regenerate'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF6366F1),
                    side: const BorderSide(color: Color(0xFF6366F1)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                Row(
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
                        foregroundColor: Theme.of(
                          context,
                        ).textTheme.bodyLarge?.color,
                        side: BorderSide(color: Theme.of(context).dividerColor),
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
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
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
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
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
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AI Metadata',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).textTheme.titleLarge?.color,
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
              Icon(
                Icons.security,
                size: 16,
                color: Theme.of(context).iconTheme.color?.withOpacity(0.5),
              ),
              const SizedBox(width: 4),
              Text(
                'API key stored server-side',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(
                    context,
                  ).textTheme.bodySmall?.color?.withOpacity(0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Preview Button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                // TODO: Implement preview in student view
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      '\ud83d\udc41\ufe0f Opening student preview...',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Preview in Student View'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF6366F1),
                side: const BorderSide(color: Color(0xFF6366F1)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
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
                    foregroundColor: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.color,
                    side: BorderSide(color: Theme.of(context).dividerColor),
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
                    _showScheduleDialog();
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
                    'Schedule Test',
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
        style: TextStyle(
          fontSize: 14,
          color: Theme.of(context).textTheme.bodyMedium?.color,
        ),
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
    return const TeacherBottomNav(selectedIndex: 2);
  }

  void _showScheduleDialog() {
    final date = _scheduledDate;
    final time = _scheduledTime;
    if (date == null || time == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a schedule date and time')),
      );
      return;
    }

    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final timeStr = time.format(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Schedule'),
        content: Text('Schedule this test on\n$dateStr at $timeStr?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _saveGeneratedTest(publish: false, schedule: true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final first = DateTime(now.year - 1);
    final last = DateTime(now.year + 5);
    final picked = await showDatePicker(
      context: context,
      initialDate: _scheduledDate ?? now,
      firstDate: first,
      lastDate: last,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(primary: const Color(0xFF6366F1)),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _scheduledDate = picked);
    }
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _scheduledTime ?? TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(primary: const Color(0xFF6366F1)),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _scheduledTime = picked;
        _calculateDuration();
      });
    }
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime ?? TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(primary: const Color(0xFF6366F1)),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _endTime = picked;
        _calculateDuration();
      });
    }
  }

  void _calculateDuration() {
    if (_scheduledTime != null && _endTime != null) {
      final start = Duration(
        hours: _scheduledTime!.hour,
        minutes: _scheduledTime!.minute,
      );
      final end = Duration(hours: _endTime!.hour, minutes: _endTime!.minute);

      if (end > start) {
        setState(() {
          _calculatedDuration = end - start;
        });
      } else {
        setState(() {
          _calculatedDuration = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ End time must be after start time')),
        );
      }
    }
  }
}

// Generated Question model
class GeneratedQuestion {
  final String question;
  final String answer;
  final List<String> options;
  final String explanation;
  final String topic;
  final String difficulty;
  final int confidence;
  final int points;

  GeneratedQuestion({
    required this.question,
    required this.answer,
    this.options = const [],
    this.explanation = '',
    required this.topic,
    required this.difficulty,
    required this.confidence,
    this.points = 1,
  });
}

extension on _AITestGeneratorScreenState {
  Future<void> _saveGeneratedTest({
    required bool publish,
    bool schedule = false,
  }) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final testProv = Provider.of<TestProvider>(context, listen: false);
    final user = auth.currentUser;

    if (user == null || user.role != UserRole.teacher) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login as a teacher to continue')),
      );
      return;
    }

    if (_testNameController.text.trim().isEmpty || generatedQuestions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Generate questions before assigning')),
      );
      return;
    }

    final normalizedSection = (selectedSection ?? '')
        .replaceAll('Section ', '')
        .trim();

    // Use calculated duration or fallback
    final duration =
        _calculatedDuration?.inMinutes ??
        int.tryParse(_questionCountController.text.trim()) ??
        30; // fallback minutes
    final now = DateTime.now();

    // Determine dates based on schedule or immediate publish/draft
    DateTime startDate;
    DateTime endDate;
    tm.TestStatus status;
    if (schedule) {
      final d = _scheduledDate ?? DateTime.now();
      final t = _scheduledTime ?? TimeOfDay.now();
      startDate = DateTime(d.year, d.month, d.day, t.hour, t.minute);

      // Use end time if available, otherwise add duration
      if (_endTime != null) {
        endDate = DateTime(
          d.year,
          d.month,
          d.day,
          _endTime!.hour,
          _endTime!.minute,
        );
      } else {
        endDate = startDate.add(Duration(minutes: duration));
      }

      // Scheduled tests: check auto-publish setting
      status = autoPublish ? tm.TestStatus.published : tm.TestStatus.draft;
    } else {
      startDate = now;
      endDate = now.add(Duration(minutes: duration));
      status = publish ? tm.TestStatus.published : tm.TestStatus.draft;
    }

    final modelQuestions = generatedQuestions.map((gq) {
      return tm.Question(
        id: gq.question.hashCode.toString(),
        type: gq.options.isNotEmpty
            ? tm.QuestionType.multipleChoice
            : tm.QuestionType.shortAnswer,
        question: gq.question,
        options: gq.options.isNotEmpty ? gq.options : null,
        correctAnswer: gq.answer,
        points: gq.points,
      );
    }).toList();

    // Pre-compute assigned students when publishing
    List<String> assignedIds = const [];
    if (publish &&
        (selectedClass ?? '').isNotEmpty &&
        normalizedSection.isNotEmpty) {
      try {
        // Let FirestoreService handle assignment using Auth UIDs post-create
        // to prevent mismatched IDs. Keep empty here; it will be set server-side.
        assignedIds = const [];
      } catch (_) {
        assignedIds = const [];
      }
    }

    final test = tm.TestModel(
      id: '',
      title: _testNameController.text.trim(),
      description: _descriptionController.text.trim().isNotEmpty
          ? _descriptionController.text.trim()
          : 'Auto-generated by AI from topics: ${_topicsController.text.trim()}',
      teacherId: user.uid,
      teacherName: user.name,
      instituteId: user.instituteId ?? '',
      subject: _subjectController.text.trim(),
      className: selectedClass,
      section: normalizedSection,
      questions: modelQuestions,
      totalPoints:
          int.tryParse(_totalMarksController.text.trim()) ??
          modelQuestions.fold<int>(0, (sum, q) => sum + q.points),
      duration: duration,
      startDate: startDate,
      endDate: endDate,
      status: status,
      assignedStudentIds: assignedIds,
      createdAt: now,
      updatedAt: now,
    );

    bool ok;
    if (schedule) {
      ok = await testProv.createScheduledTest(
        test,
        scheduledDate: _scheduledDate ?? DateTime.now(),
        scheduledTime: _scheduledTime ?? TimeOfDay.now(),
      );
    } else {
      ok = await testProv.createTest(test);
    }
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            schedule
                ? 'Test scheduled successfully'
                : 'Test created successfully',
          ),
        ),
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
