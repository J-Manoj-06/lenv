import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../../services/ai_test_service.dart';
import '../../services/firestore_service.dart';
import '../../services/teacher_service.dart';
import '../../models/test_question.dart';
import '../../exceptions/ai_exceptions.dart';
import '../../models/test_model.dart' as tm;
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart' as auth_provider;
import '../../providers/test_provider.dart';

/// Screen for generating tests using AI
///
/// Allows teachers to input test parameters and generate questions automatically
/// using the DeepSeek AI via a secure proxy server.
class CreateAITestScreen extends StatefulWidget {
  const CreateAITestScreen({super.key});

  @override
  State<CreateAITestScreen> createState() => _CreateAITestScreenState();
}

class _CreateAITestScreenState extends State<CreateAITestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _aiService = AITestService();
  final _firestoreService = FirestoreService();
  final _teacherService = TeacherService();

  // Form controllers
  final _titleController = TextEditingController();
  final _topicController = TextEditingController();
  final _totalMarksController = TextEditingController(text: '10');
  final _timeLimitController = TextEditingController();

  // Form values
  String? _selectedClass;
  String? _selectedSection;
  String? _selectedSubject;
  String _selectedDifficulty = 'Medium';
  int _numQuestions = 5;

  // Scheduling fields
  DateTime? _scheduledDate;
  TimeOfDay? _scheduledTime;

  // Generated questions
  List<TestQuestion>? _generatedQuestions;
  bool _isGenerating = false;
  bool _isLoadingTeacherData = true;

  // Available options (dynamically loaded from teacher data)
  List<String> _classes = [];
  List<String> _sections = [];
  List<String> _subjects = [];
  final Map<String, List<String>> _gradeSections = {};
  Map<String, List<String>> _classSectionSubjectsMap = {};

  @override
  void initState() {
    super.initState();
    _loadTeacherData();
    // Default schedule: current date and time
    _scheduledDate = DateTime.now();
    _scheduledTime = TimeOfDay.now();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _topicController.dispose();
    _totalMarksController.dispose();
    _timeLimitController.dispose();
    _aiService.dispose();
    super.dispose();
  }

  /// Load teacher's assigned classes and sections
  Future<void> _loadTeacherData() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null || currentUser.email == null) {
        setState(() => _isLoadingTeacherData = false);
        return;
      }

      final teacherData = await _teacherService.getTeacherByEmail(
        currentUser.email!,
      );
      if (teacherData == null) {
        setState(() => _isLoadingTeacherData = false);
        return;
      }

      // Get formatted classes using the service
      final dynamic sectionsData =
          teacherData['sections'] ?? teacherData['section'];
      final List<String> formattedClasses = _teacherService.getTeacherClasses(
        teacherData['classesHandled'],
        sectionsData,
        classAssignments: teacherData['classAssignments'],
      );

      // Build grade -> sections map AND grade|section -> subjects map
      _gradeSections.clear();
      final Map<String, List<String>> classSectionSubjects = {};

      // Parse classAssignments to build both maps
      if (teacherData['classAssignments'] != null) {
        final classAssignments = teacherData['classAssignments'];
        if (classAssignments is List) {
          for (final assignment in classAssignments) {
            final s = assignment
                .toString(); // e.g., "Grade 9: A, social studies"
            final parts = s.split(':');
            if (parts.length >= 2) {
              final gradePart = parts[0].replaceAll('Grade', '').trim(); // "9"
              final right = parts[1]; // " A, social studies"
              final commaParts = right.split(',');
              if (commaParts.length >= 2) {
                final section = commaParts[0].trim(); // "A"
                final subject = commaParts[1].trim(); // "social studies"

                // Add to grade->sections map
                _gradeSections.putIfAbsent(gradePart, () => <String>[]);
                if (!_gradeSections[gradePart]!.contains(section)) {
                  _gradeSections[gradePart]!.add(section);
                }

                // Add to grade|section->subjects map
                final key = '$gradePart|$section';
                classSectionSubjects.putIfAbsent(key, () => <String>[]);
                if (!classSectionSubjects[key]!.contains(subject)) {
                  classSectionSubjects[key]!.add(subject);
                }
              }
            }
          }
        }
      }

      // Also process formatted classes for backward compatibility
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

      // Initialize sections and subjects for the first grade
      final String? initialGrade = gradeOnlyList.isNotEmpty
          ? gradeOnlyList.first
          : null;
      final List<String> initialSections = initialGrade != null
          ? (_gradeSections[initialGrade] ?? <String>[])
          : <String>[];
      final String? initialSection = initialSections.isNotEmpty
          ? initialSections.first
          : null;

      // Get subjects for initial grade+section combination
      List<String> initialSubjects = [];
      if (initialGrade != null && initialSection != null) {
        final key = '$initialGrade|$initialSection';
        final allSubjects = classSectionSubjects[key] ?? [];
        // Filter out "math" if there are other subjects available
        final filtered = allSubjects
            .where((s) => s.toLowerCase() != 'math')
            .toList();
        // If only math exists, keep it; otherwise use non-math subjects
        initialSubjects = filtered.isEmpty ? allSubjects : filtered;
        initialSubjects.sort();
      }

      setState(() {
        _classes = gradeOnlyList;
        _sections = initialSections;
        _subjects = initialSubjects;
        _classSectionSubjectsMap = classSectionSubjects;
        _selectedClass = initialGrade;
        _selectedSection = initialSection;
        _selectedSubject = initialSubjects.isNotEmpty
            ? initialSubjects.first
            : null;
        _isLoadingTeacherData = false;
      });
    } catch (e) {
      setState(() => _isLoadingTeacherData = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Generate Test with AI'), elevation: 0),
      body: _generatedQuestions == null
          ? _buildFormView()
          : _buildPreviewView(),
      bottomNavigationBar: _generatedQuestions == null
          ? _buildBottomSection()
          : null,
    );
  }

  /// Form view for entering test parameters
  Widget _buildFormView() {
    if (_isLoadingTeacherData) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading teacher data...'),
          ],
        ),
      );
    }

    if (_classes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.orange),
              const SizedBox(height: 16),
              const Text(
                'No Classes Assigned',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'You don\'t have any classes assigned. Please contact your administrator.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 100),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Class dropdown
            DropdownButtonFormField<String>(
              initialValue: _selectedClass,
              decoration: const InputDecoration(
                labelText: 'Class',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.school),
              ),
              items: _isLoadingTeacherData
                  ? []
                  : _classes.map((cls) {
                      return DropdownMenuItem(
                        value: cls,
                        child: Text('Grade $cls'),
                      );
                    }).toList(),
              onChanged: _classes.isEmpty
                  ? null
                  : (value) {
                      setState(() {
                        _selectedClass = value;
                        // Update sections based on selected class
                        final grade = (value ?? '').trim();
                        final secList = _gradeSections[grade] ?? <String>[];
                        _sections = secList;
                        _selectedSection = _sections.isNotEmpty
                            ? _sections.first
                            : null;
                        // Update subjects based on new class+section
                        if (value != null && _selectedSection != null) {
                          final key = '${value.trim()}|$_selectedSection';
                          final allSubjects =
                              _classSectionSubjectsMap[key] ?? [];
                          // Filter out "math" if there are other subjects available
                          final filtered = allSubjects
                              .where((s) => s.toLowerCase() != 'math')
                              .toList();
                          _subjects = filtered.isEmpty ? allSubjects : filtered;
                          _subjects.sort();
                          _selectedSubject = _subjects.isNotEmpty
                              ? _subjects.first
                              : null;
                        } else {
                          _subjects = [];
                          _selectedSubject = null;
                        }
                      });
                    },
              validator: (value) =>
                  value == null ? 'Please select a class' : null,
            ),
            const SizedBox(height: 16),

            // Section dropdown
            DropdownButtonFormField<String>(
              initialValue: _selectedSection,
              decoration: const InputDecoration(
                labelText: 'Section',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.group),
              ),
              items: _isLoadingTeacherData
                  ? []
                  : _sections.map((section) {
                      return DropdownMenuItem(
                        value: section,
                        child: Text('Section $section'),
                      );
                    }).toList(),
              onChanged: _sections.isEmpty
                  ? null
                  : (value) {
                      setState(() {
                        _selectedSection = value;
                        // Update subjects based on selected class+section
                        if (_selectedClass != null && value != null) {
                          final key = '$_selectedClass|$value';
                          final allSubjects =
                              _classSectionSubjectsMap[key] ?? [];
                          // Filter out "math" if there are other subjects available
                          final filtered = allSubjects
                              .where((s) => s.toLowerCase() != 'math')
                              .toList();
                          _subjects = filtered.isEmpty ? allSubjects : filtered;
                          _subjects.sort();
                          _selectedSubject = _subjects.isNotEmpty
                              ? _subjects.first
                              : null;
                        }
                      });
                    },
              validator: (value) =>
                  value == null ? 'Please select a section' : null,
            ),
            const SizedBox(height: 16),

            // Title field
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Test Title',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.title),
                hintText: 'e.g., Mathematics Mid-Term Test',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a test title';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Subject dropdown
            DropdownButtonFormField<String>(
              initialValue: _selectedSubject,
              decoration: const InputDecoration(
                labelText: 'Subject',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.book),
              ),
              items: _isLoadingTeacherData
                  ? []
                  : _subjects.map((subject) {
                      return DropdownMenuItem(
                        value: subject,
                        child: Text(subject),
                      );
                    }).toList(),
              onChanged: _subjects.isEmpty
                  ? null
                  : (value) => setState(() => _selectedSubject = value),
              validator: (value) =>
                  value == null ? 'Please select a subject' : null,
            ),
            const SizedBox(height: 16),

            // Topic text field
            TextFormField(
              controller: _topicController,
              decoration: const InputDecoration(
                labelText: 'Topic',
                hintText: 'e.g., Pythagorean Theorem',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.topic),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a topic';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Difficulty dropdown
            DropdownButtonFormField<String>(
              initialValue: _selectedDifficulty,
              decoration: const InputDecoration(
                labelText: 'Difficulty Level',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.trending_up),
              ),
              items: const [
                DropdownMenuItem(value: 'Easy', child: Text('Easy')),
                DropdownMenuItem(value: 'Medium', child: Text('Medium')),
                DropdownMenuItem(value: 'Hard', child: Text('Hard')),
                DropdownMenuItem(value: 'Mixed', child: Text('Mixed')),
              ],
              onChanged: (value) =>
                  setState(() => _selectedDifficulty = value!),
            ),
            const SizedBox(height: 16),

            // Number of questions slider
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Number of Questions: $_numQuestions',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Slider(
                      value: _numQuestions.toDouble(),
                      min: 1,
                      max: 20,
                      divisions: 19,
                      label: _numQuestions.toString(),
                      onChanged: (value) {
                        setState(() => _numQuestions = value.toInt());
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Total marks and time limit
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _totalMarksController,
                    decoration: const InputDecoration(
                      labelText: 'Total Marks',
                      hintText: 'e.g. 100',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.format_list_numbered),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Required';
                      }
                      final marks = int.tryParse(value);
                      if (marks == null || marks <= 0) {
                        return 'Invalid number';
                      }
                      if (marks < _numQuestions) {
                        return 'Min $_numQuestions';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _timeLimitController,
                    decoration: const InputDecoration(
                      labelText: 'Time Limit',
                      hintText: 'e.g. 90 mins',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.timer),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Required';
                      }
                      final time = int.tryParse(value);
                      if (time == null || time <= 0) {
                        return 'Invalid time';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Schedule Test Section
            Row(
              children: [
                Icon(Icons.schedule, color: Colors.blue.shade700, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Schedule Test',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Date and Time Pickers
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _scheduledDate ?? DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (date != null) {
                        setState(() {
                          _scheduledDate = date;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 20,
                            color: Colors.blue.shade700,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _scheduledDate == null
                                  ? '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}'
                                  : '${_scheduledDate!.day}/${_scheduledDate!.month}/${_scheduledDate!.year}',
                              style: TextStyle(
                                fontSize: 14,
                                color:
                                    Theme.of(
                                      context,
                                    ).textTheme.bodyMedium?.color ??
                                    Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: _scheduledTime ?? TimeOfDay.now(),
                      );
                      if (time != null) {
                        setState(() {
                          _scheduledTime = time;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 20,
                            color: Colors.blue.shade700,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _scheduledTime == null
                                  ? TimeOfDay.now().format(context)
                                  : _scheduledTime!.format(context),
                              style: TextStyle(
                                fontSize: 14,
                                color:
                                    Theme.of(
                                      context,
                                    ).textTheme.bodyMedium?.color ??
                                    Colors.black87,
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
            // const SizedBox(height: 2),
          ],
        ),
      ),
    );
  }

  /// Fixed bottom section with Generate button
  Widget _buildBottomSection() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1E1E1E)
            : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isGenerating ? null : _generateTest,
              icon: _isGenerating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(
                _isGenerating ? 'Generating...' : 'Generate Test with AI',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Preview view showing generated questions
  Widget _buildPreviewView() {
    final questions = _generatedQuestions!;
    final title = _titleController.text.trim().isEmpty
        ? 'Generated Test'
        : _titleController.text.trim();

    return Column(
      children: [
        // Header
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF1B4332)
                : Colors.green.shade50,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.green.shade700
                    : Colors.green.withOpacity(0.3),
                width: 1,
              ),
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$title • with AI',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.green.shade300
                      : Colors.green.shade900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${questions.length} questions • Total marks: ${questions.fold<int>(0, (sum, q) => sum + q.marks)}',
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey.shade400
                      : Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildInfoChip(
                    icon: Icons.school,
                    label: _selectedClass != null
                        ? 'Grade ${_selectedClass!}'
                        : 'Class',
                  ),
                  if (_selectedSection != null && _selectedSection!.isNotEmpty)
                    _buildInfoChip(
                      icon: Icons.group,
                      label: 'Section ${_selectedSection!}',
                    ),
                  if (_selectedSubject != null)
                    _buildInfoChip(icon: Icons.book, label: _selectedSubject!),
                  _buildInfoChip(
                    icon: Icons.timer,
                    label:
                        '${int.tryParse(_timeLimitController.text) ?? 60} mins',
                  ),
                ],
              ),
            ],
          ),
        ),

        // Questions list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: questions.length,
            itemBuilder: (context, index) {
              final question = questions[index];
              return _buildQuestionCard(question, index);
            },
          ),
        ),

        // Action buttons
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF1E1E1E)
                : Colors.white,
            border: Border(
              top: BorderSide(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey.shade800
                    : Theme.of(context).dividerColor,
                width: 1,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _regenerateTest,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Regenerate'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _saveTest,
                  icon: const Icon(Icons.save),
                  label: const Text('Save Test'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Build a card for a single question
  Widget _buildQuestionCard(TestQuestion question, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey.shade700
                : Colors.grey.shade300,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Question header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.blue.withOpacity(0.2)
                        : Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Q${index + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.blue.shade300
                          : Colors.blue.shade900,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        question.type == QuestionTypeAI.mcq
                            ? 'Multiple Choice'
                            : 'True/False',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.star,
                            size: 14,
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? Colors.amber.shade400
                                : Colors.amber.shade700,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${question.marks} marks',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.amber.shade400
                                  : Colors.amber.shade900,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Edit marks button
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => _editQuestionMarks(index),
                  tooltip: 'Edit marks',
                ),
                // Delete button
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () => _deleteQuestion(index),
                  tooltip: 'Remove question',
                  color: Colors.red,
                ),
              ],
            ),
            const Divider(height: 24),

            // Question text
            Text(
              question.questionText,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),

            // Options for MCQ
            if (question.type == QuestionTypeAI.mcq &&
                question.options != null) ...[
              ...question.options!.asMap().entries.map((entry) {
                final optionIndex = entry.key;
                final optionText = entry.value;
                final optionLetter = String.fromCharCode(
                  65 + optionIndex,
                ); // A, B, C, D
                final isCorrect = question.correctAnswer == optionLetter;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isCorrect
                          ? (Theme.of(context).brightness == Brightness.dark
                                ? const Color(0xFF1B4332)
                                : Colors.green.shade50)
                          : (Theme.of(context).brightness == Brightness.dark
                                ? const Color(0xFF2D2D2D)
                                : Colors.grey.shade50),
                      border: Border.all(
                        color: isCorrect
                            ? (Theme.of(context).brightness == Brightness.dark
                                  ? Colors.green.shade400
                                  : Colors.green.shade300)
                            : (Theme.of(context).brightness == Brightness.dark
                                  ? Colors.grey.shade600
                                  : Colors.grey.shade300),
                        width: isCorrect ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: isCorrect
                                ? (Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.green.shade600
                                      : Colors.green.shade700)
                                : (Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.grey.shade700
                                      : Colors.grey.shade300),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              optionLetter,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            optionText,
                            style: TextStyle(
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.white
                                  : Colors.black87,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (isCorrect)
                          Icon(
                            Icons.check_circle,
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? Colors.green.shade400
                                : Colors.green.shade700,
                          ),
                      ],
                    ),
                  ),
                );
              }),
            ],

            // Answer for True/False
            if (question.type == QuestionTypeAI.trueFalse) ...[
              Row(
                children: [
                  Text(
                    'Correct Answer: ',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.green.withOpacity(0.2)
                          : Colors.green.shade100,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.green.shade400
                            : Colors.green.shade700,
                      ),
                    ),
                    child: Text(
                      question.correctAnswer.toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.green.shade300
                            : Colors.green.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip({required IconData icon, required String label}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.green.withOpacity(0.12) : Colors.green.shade100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isDark ? Colors.green.shade700 : Colors.green.shade300,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: isDark ? Colors.green.shade300 : Colors.green.shade900,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.green.shade300 : Colors.green.shade900,
            ),
          ),
        ],
      ),
    );
  }

  /// Generate test using AI
  Future<void> _generateTest() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isGenerating = true);

    try {
      // Show loading dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            elevation: 0,
            backgroundColor: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withOpacity(0.3),
                    spreadRadius: 2,
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // AI Icon with glow effect
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      size: 48,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Title
                  const Text(
                    '✨ AI Magic in Progress',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  // Loading indicator
                  const SizedBox(
                    height: 4,
                    child: LinearProgressIndicator(
                      backgroundColor: Colors.white24,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Description
                  Text(
                    'Crafting intelligent questions\njust for you...',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.9),
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  // Time estimate
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.schedule,
                          size: 16,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '10-30 seconds',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.95),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      // Fetch previous questions for context
      final previousQuestions = await _firestoreService.fetchPreviousQuestions(
        className: _selectedClass!,
        section: _selectedSection!,
        subject: _selectedSubject!,
      );

      // Generate test
      final questions = await _aiService.generateTest(
        className: _selectedClass!,
        section: _selectedSection!,
        subject: _selectedSubject!,
        topic: _topicController.text.trim(),
        difficulty: _selectedDifficulty,
        totalMarks: int.parse(_totalMarksController.text),
        numQuestions: _numQuestions,
        previousQuestions: previousQuestions.isNotEmpty
            ? previousQuestions
            : null,
      );

      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      // Show success and update state
      setState(() {
        _generatedQuestions = questions;
        _isGenerating = false;
      });
    } on RateLimitException catch (e) {
      if (mounted) Navigator.of(context).pop();
      setState(() => _isGenerating = false);
      _showErrorDialog(
        'Rate Limit Exceeded',
        e.userMessage,
        retryAfter: e.retryAfterSeconds,
      );
    } on NetworkException catch (e) {
      if (mounted) Navigator.of(context).pop();
      setState(() => _isGenerating = false);
      _showErrorDialog('Network Error', e.userMessage);
    } on ParseException catch (e) {
      if (mounted) Navigator.of(context).pop();
      setState(() => _isGenerating = false);
      _showErrorDialog('Generation Failed', e.userMessage);
    } on DuplicateQuestionException catch (e) {
      if (mounted) Navigator.of(context).pop();
      setState(() => _isGenerating = false);
      _showErrorDialog('Duplicate Questions', e.userMessage);
    } on ValidationException catch (e) {
      if (mounted) Navigator.of(context).pop();
      setState(() => _isGenerating = false);
      _showErrorDialog('Invalid Input', e.userMessage);
    } on TimeoutException catch (e) {
      if (mounted) Navigator.of(context).pop();
      setState(() => _isGenerating = false);
      _showErrorDialog('Request Timeout', e.userMessage);
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      setState(() => _isGenerating = false);
      _showErrorDialog(
        'Unexpected Error',
        'An unexpected error occurred: ${e.toString()}',
      );
    }
  }

  /// Regenerate test with same parameters
  void _regenerateTest() {
    setState(() => _generatedQuestions = null);
  }

  /// Edit marks for a question
  void _editQuestionMarks(int index) {
    final question = _generatedQuestions![index];
    final controller = TextEditingController(text: question.marks.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Marks'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Marks',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final newMarks = int.tryParse(controller.text);
              if (newMarks != null && newMarks > 0) {
                setState(() {
                  _generatedQuestions![index] = question.copyWith(
                    marks: newMarks,
                  );
                });
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  /// Delete a question
  void _deleteQuestion(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Question'),
        content: const Text('Are you sure you want to remove this question?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _generatedQuestions!.removeAt(index);
              });
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  /// Save test to Firestore
  Future<void> _saveTest() async {
    if (_generatedQuestions == null || _generatedQuestions!.isEmpty) {
      _showErrorDialog('No Questions', 'Please generate questions first.');
      return;
    }

    // Validate title
    if (_titleController.text.trim().isEmpty) {
      _showErrorDialog('Missing Title', 'Please enter a test title.');
      return;
    }

    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Saving test...'),
            ],
          ),
        ),
      );

      final auth = Provider.of<auth_provider.AuthProvider>(
        context,
        listen: false,
      );
      final testProv = Provider.of<TestProvider>(context, listen: false);
      final user = auth.currentUser;

      if (user == null || user.role != UserRole.teacher) {
        throw Exception('Please login as a teacher to continue');
      }

      // Parse time limit
      final timeLimit = int.tryParse(_timeLimitController.text) ?? 60;

      // Create scheduled DateTime
      final scheduledDateTime = DateTime(
        _scheduledDate?.year ?? DateTime.now().year,
        _scheduledDate?.month ?? DateTime.now().month,
        _scheduledDate?.day ?? DateTime.now().day,
        _scheduledTime?.hour ?? TimeOfDay.now().hour,
        _scheduledTime?.minute ?? TimeOfDay.now().minute,
      );

      final endDate = scheduledDateTime.add(Duration(minutes: timeLimit));

      // Convert AI questions to test model questions
      final modelQuestions = _generatedQuestions!.map((q) {
        tm.QuestionType questionType;
        if (q.type == QuestionTypeAI.mcq) {
          questionType = tm.QuestionType.multipleChoice;
        } else {
          questionType = tm.QuestionType.trueFalse;
        }

        return tm.Question(
          id: q.questionText.hashCode.toString(),
          type: questionType,
          question: q.questionText,
          options: q.options,
          correctAnswer: q.correctAnswer,
          points: q.marks,
        );
      }).toList();

      final totalPoints = _generatedQuestions!.fold<int>(
        0,
        (sum, q) => sum + q.marks,
      );

      // Build className and section
      final gradeClassName = 'Grade ${_selectedClass!.trim()}';
      final normalizedSection = (_selectedSection ?? '').trim();

      final test = tm.TestModel(
        id: '',
        title: _titleController.text.trim(),
        description:
            'Generated by AI for topic: ${_topicController.text.trim()}',
        teacherId: user.uid,
        teacherName: user.name,
        instituteId: user.instituteId ?? '',
        subject: _selectedSubject!,
        className: gradeClassName,
        section: normalizedSection,
        questions: modelQuestions,
        totalPoints: totalPoints,
        duration: timeLimit,
        startDate: scheduledDateTime,
        endDate: endDate,
        status: tm.TestStatus.published, // Published so students can see it
        assignedStudentIds: const [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Save as scheduled test to assign to students
      final ok = await testProv.createScheduledTest(
        test,
        scheduledDate: _scheduledDate ?? DateTime.now(),
        scheduledTime: _scheduledTime ?? TimeOfDay.now(),
      );

      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      if (ok) {
        // Stream will automatically update with new test
        // No need to manually refresh

        // Show success message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Test scheduled and assigned successfully!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );

          // Go back to previous screen
          Navigator.of(context).pop();
        }
      } else {
        _showErrorDialog(
          'Save Failed',
          'Failed to save test: ${testProv.errorMessage ?? 'Unknown error'}',
        );
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      _showErrorDialog('Save Failed', 'Failed to save test: ${e.toString()}');
    }
  }

  /// Show error dialog
  void _showErrorDialog(String title, String message, {int? retryAfter}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            if (retryAfter != null) ...[
              const SizedBox(height: 12),
              Text(
                'Please wait $retryAfter seconds before trying again.',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (retryAfter == null)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _generateTest();
              },
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}
