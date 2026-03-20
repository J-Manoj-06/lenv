import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import '../../models/test_model.dart' as tm;
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/test_provider.dart';
import 'package:intl/intl.dart';
import '../../providers/test_assignment_lock_provider.dart';
import '../../services/teacher_service.dart';
import '../../widgets/test_assignment_lock_banner.dart';
import '../../widgets/test_schedule_picker.dart';
import 'tests_screen.dart';
// import 'package:cloud_firestore/cloud_firestore.dart'; // no longer needed: assignment computed server-side

class CreateTestScreen extends StatefulWidget {
  const CreateTestScreen({super.key});

  @override
  State<CreateTestScreen> createState() => _CreateTestScreenState();
}

class _CreateTestScreenState extends State<CreateTestScreen> {
  // Teacher brand color for selections and borders
  static const Color _teacherColor = Color(0xFF355872);

  final _titleController = TextEditingController();
  final _totalMarksController = TextEditingController();
  final _timeLimitController = TextEditingController();
  final _focusNode = FocusNode();

  String? selectedSubject;
  String? selectedClass;
  String? selectedSection; // Display format: "Section A"

  // Scheduling fields (always enabled with current date/time by default)
  DateTime? scheduledDate;
  TimeOfDay? scheduledTime;
  String? _lastSaveError;

  List<Question> questions = [
    Question(
      id: 1,
      type: QuestionType.multipleChoice,
      questionText: '',
      options: ['3', '4', '5'],
      correctAnswerIndex: 1,
    ),
  ];
  // Dynamic lists populated from teacher profile
  List<String> subjects = [];
  List<String> classes = [];
  List<String> sections = [];
  // Map of grade -> sections available for that grade (e.g., {"8": ["A"], "9": ["A","B"]})
  final Map<String, List<String>> _gradeSections = {};
  // Map of grade|section -> subjects handled specifically for that combination
  final Map<String, List<String>> _classSectionSubjects = {};
  // Fallback full subject list (all handled by teacher across classes)
  List<String> _allSubjectsFallback = [];

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
    // Default schedule: current date and time
    scheduledDate = DateTime.now();
    scheduledTime = TimeOfDay.now();
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

      // Build mapping of subjects per class-section from classAssignments
      List<String> globalSubjects = (data?['subjectsHandled'] is List)
          ? List<String>.from(data!['subjectsHandled'] as List)
          : <String>[];
      _classSectionSubjects.clear();
      if (data?['classAssignments'] is List) {
        for (final assignment in (data!['classAssignments'] as List)) {
          final raw = assignment.toString(); // "Grade 10: A, Science"
          final colonParts = raw.split(':');
          if (colonParts.length < 2) continue;
          final gradePart = colonParts[0].trim(); // "Grade 10"
          final rightSide = colonParts[1]; // " A, Science"
          final commaParts = rightSide.split(',');
          if (commaParts.isEmpty) continue;
          final sectionPart = commaParts[0].trim();
          String? subjectPart;
          if (commaParts.length > 1) subjectPart = commaParts[1].trim();
          final gradeNormalized = gradePart
              .replaceAll('Grade ', '')
              .replaceAll('grade ', '')
              .trim();
          final key = '$gradeNormalized|$sectionPart';
          if (subjectPart != null && subjectPart.isNotEmpty) {
            _classSectionSubjects.putIfAbsent(key, () => <String>[]);
            if (!_classSectionSubjects[key]!.contains(subjectPart)) {
              _classSectionSubjects[key]!.add(subjectPart);
            }
            if (!globalSubjects.contains(subjectPart)) {
              globalSubjects.add(subjectPart);
            }
          }
        }
      }
      // Normalize fallback subject list
      if (globalSubjects.isEmpty && _classSectionSubjects.isNotEmpty) {
        globalSubjects = _classSectionSubjects.values
            .expand((e) => e)
            .toSet()
            .toList();
      }
      globalSubjects.sort();
      _allSubjectsFallback = globalSubjects;

      // Get formatted classes using the service (handles both formats)
      final dynamic sectionsData = data?['sections'] ?? data?['section'];
      final List<String> formattedClasses = svc.getTeacherClasses(
        data?['classesHandled'],
        sectionsData,
        classAssignments: data?['classAssignments'],
      );

      // Build grade -> sections map from formatted classes (e.g., "10 - A")
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
      // Determine initial class and its sections
      final String? initialGrade = gradeOnlyList.isNotEmpty
          ? gradeOnlyList.first
          : null;
      final List<String> initialSections = initialGrade != null
          ? (_gradeSections[initialGrade] ?? <String>[])
          : <String>[];
      final List<String> sectionDisplay =
          initialSections.map((s) => 'Section $s').toList()..sort();

      // Determine initial class and its sections
      setState(() {
        // Show only the standard (grade) in the class dropdown
        classes = gradeOnlyList;
        sections = sectionDisplay;
        selectedClass = initialGrade;
        selectedSection = sections.isNotEmpty ? sections.first : null;
        // Populate subjects filtered by initial selection
        subjects = _filteredSubjectsForSelection();
        selectedSubject = subjects.isNotEmpty ? subjects.first : null;
        _loadingMeta = false;
      });
      // Start real-time lock watch once initial class + subject are known.
      WidgetsBinding.instance.addPostFrameCallback((_) => _watchLockIfReady());
    } catch (e) {
      setState(() => _loadingMeta = false);
    }
  }

  List<String> _filteredSubjectsForSelection() {
    final grade = selectedClass?.trim();
    if (grade == null || grade.isEmpty) return _allSubjectsFallback;
    final sectionLabel = selectedSection?.trim();
    String? section;
    if (sectionLabel != null &&
        sectionLabel.toLowerCase().startsWith('section ')) {
      section = sectionLabel.substring(8).trim();
    }
    if (section == null || section.isEmpty) {
      // Return empty list if no section specified - force teacher to select section first
      return [];
    }
    final key = '$grade|$section';
    final list = _classSectionSubjects[key];
    if (list != null && list.isNotEmpty) {
      // Filter out "math" if there are other subjects available
      final filtered = list.where((s) => s.toLowerCase() != 'math').toList();
      // If only math exists, return it; otherwise return non-math subjects
      final result = filtered.isEmpty ? list.toList() : filtered;
      return (result..sort());
    }
    // No subjects found for this exact class+section combination
    return [];
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Lock helpers
  // ──────────────────────────────────────────────────────────────────────────

  /// Subscribes to real-time lock updates for the current class + section.
  void _watchLockIfReady() {
    final cls = selectedClass?.trim();
    if (cls == null || cls.isEmpty) return;
    final rawSection = selectedSection ?? '';
    final sec = rawSection
        .replaceAll(RegExp(r'^Section\s+', caseSensitive: false), '')
        .trim();
    if (sec.isEmpty) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final instituteId = auth.currentUser?.instituteId ?? '';
    final lockProv = Provider.of<TestAssignmentLockProvider>(
      context,
      listen: false,
    );
    lockProv.watchLock(
      instituteId: instituteId,
      classId: 'Grade $cls',
      sectionId: sec,
    );
  }

  String _formatLockTime(DateTime dt) {
    final now = DateTime.now();
    final isToday =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    return isToday
        ? DateFormat('h:mm a').format(dt)
        : DateFormat('d MMM, h:mm a').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : theme.scaffoldBackgroundColor;
    return Scaffold(
      backgroundColor: bgColor,
      body: Column(
        children: [
          Container(
            color: bgColor,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new),
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
                    const SizedBox(width: 48),
                  ],
                ),
              ),
            ),
          ),
          // Lock banner – shown when another teacher has already assigned a test
          Consumer<TestAssignmentLockProvider>(
            builder: (context, lockProv, _) {
              final auth = Provider.of<AuthProvider>(context, listen: false);
              final uid = auth.currentUser?.uid ?? '';
              return TestAssignmentLockBanner(
                lock: lockProv.currentLock,
                currentTeacherId: uid,
              );
            },
          ),
          Expanded(
            child: _loadingMeta
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Loading teacher data...'),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 16,
                      bottom: 100,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Class dropdown
                        DropdownButtonFormField<String>(
                          initialValue: selectedClass,
                          decoration: const InputDecoration(
                            labelText: 'Class',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.school),
                          ),
                          items: classes.map((cls) {
                            return DropdownMenuItem(
                              value: cls,
                              child: Text('Grade $cls'),
                            );
                          }).toList(),
                          onChanged: classes.isEmpty
                              ? null
                              : (value) {
                                  setState(() {
                                    selectedClass = value;
                                    final grade = (selectedClass ?? '').trim();
                                    final secList =
                                        _gradeSections[grade] ?? <String>[];
                                    sections =
                                        secList
                                            .map((s) => 'Section $s')
                                            .toList()
                                          ..sort();
                                    if (!sections.contains(selectedSection)) {
                                      selectedSection = sections.isNotEmpty
                                          ? sections.first
                                          : null;
                                    }
                                    subjects = _filteredSubjectsForSelection();
                                    if (!subjects.contains(selectedSubject)) {
                                      selectedSubject = subjects.isNotEmpty
                                          ? subjects.first
                                          : null;
                                    }
                                  });
                                  _watchLockIfReady();
                                },
                        ),
                        const SizedBox(height: 16),

                        // Section dropdown
                        DropdownButtonFormField<String>(
                          initialValue: selectedSection,
                          decoration: const InputDecoration(
                            labelText: 'Section',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.group),
                          ),
                          items: sections.map((section) {
                            return DropdownMenuItem(
                              value: section,
                              child: Text(section),
                            );
                          }).toList(),
                          onChanged: sections.isEmpty
                              ? null
                              : (value) {
                                  setState(() {
                                    selectedSection = value;
                                    if (selectedClass != null &&
                                        value != null) {
                                      subjects =
                                          _filteredSubjectsForSelection();
                                      if (!subjects.contains(selectedSubject)) {
                                        selectedSubject = subjects.isNotEmpty
                                            ? subjects.first
                                            : null;
                                      }
                                    }
                                  });
                                  _watchLockIfReady();
                                },
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
                        ),
                        const SizedBox(height: 16),

                        // Subject dropdown
                        DropdownButtonFormField<String>(
                          initialValue: selectedSubject,
                          decoration: const InputDecoration(
                            labelText: 'Subject',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.book),
                          ),
                          items: subjects.map((subject) {
                            return DropdownMenuItem(
                              value: subject,
                              child: Text(subject),
                            );
                          }).toList(),
                          onChanged: subjects.isEmpty
                              ? null
                              : (value) {
                                  setState(() => selectedSubject = value);
                                  _watchLockIfReady();
                                },
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
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Schedule Test Section
                        Row(
                          children: [
                            Icon(
                              Icons.schedule,
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.white
                                  : const Color(0xFF355872),
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Schedule Test',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Date and Time Picker
                        InkWell(
                          onTap: () async {
                            await TestSchedulePicker.show(
                              context: context,
                              initialDate: scheduledDate ?? DateTime.now(),
                              initialTime: scheduledTime ?? TimeOfDay.now(),
                              onComplete: (dateTime) {
                                setState(() {
                                  scheduledDate = DateTime(
                                    dateTime.year,
                                    dateTime.month,
                                    dateTime.day,
                                  );
                                  scheduledTime = TimeOfDay(
                                    hour: dateTime.hour,
                                    minute: dateTime.minute,
                                  );
                                });
                              },
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.grey.shade700
                                    : Colors.grey.shade300,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? const Color(0xFF1E1E2E)
                                  : Colors.grey.shade50,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.calendar_month_rounded,
                                  size: 24,
                                  color: const Color(0xFF355872),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        scheduledDate == null
                                            ? '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}'
                                            : '${scheduledDate!.day}/${scheduledDate!.month}/${scheduledDate!.year}',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: scheduledDate == null
                                              ? Theme.of(context)
                                                    .textTheme
                                                    .bodyLarge
                                                    ?.color
                                                    ?.withOpacity(0.4)
                                              : Theme.of(
                                                  context,
                                                ).textTheme.bodyLarge?.color,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        scheduledTime == null
                                            ? TimeOfDay.now().format(context)
                                            : scheduledTime!.format(context),
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: scheduledTime == null
                                              ? Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.color
                                                    ?.withOpacity(0.4)
                                              : Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.color
                                                    ?.withOpacity(0.7),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  size: 16,
                                  color: Theme.of(
                                    context,
                                  ).iconTheme.color?.withOpacity(0.4),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Questions header
                        Row(
                          children: [
                            Icon(
                              Icons.help_outline,
                              color: const Color(0xFF355872),
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Questions',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildQuestions(Theme.of(context)),
                        const SizedBox(height: 16),
                        _buildAddQuestionButton(Theme.of(context)),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomSection(),
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
                            : question.type == QuestionType.trueFalse
                            ? 'True or False'
                            : question.type == QuestionType.matchFollowing
                            ? 'Match the Following'
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
                            matchPairs: question.matchPairs
                                ?.map(
                                  (p) =>
                                      MatchPair(left: p.left, right: p.right),
                                )
                                .toList(),
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
                  : question.type == QuestionType.trueFalse
                  ? 'The Earth is flat.'
                  : question.type == QuestionType.matchFollowing
                  ? 'Match the items in Column A with Column B'
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
                borderSide: const BorderSide(
                  color: Color(0xFF355872),
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
          if (question.type == QuestionType.trueFalse) ...[
            const SizedBox(height: 16),
            _buildTrueFalseOptions(theme, question),
          ],
          if (question.type == QuestionType.matchFollowing) ...[
            const SizedBox(height: 16),
            _buildMatchFollowingOptions(theme, question),
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
                      ? _teacherColor
                      : theme.dividerColor,
                  width: question.correctAnswerIndex == index ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(12),
                color: question.correctAnswerIndex == index
                    ? _teacherColor.withOpacity(0.05)
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
                activeColor: _teacherColor,
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
            style: TextButton.styleFrom(foregroundColor: _teacherColor),
          ),
        ),
      ],
    );
  }

  Widget _buildTrueFalseOptions(ThemeData theme, Question question) {
    return Column(
      children: [
        ...List.generate(2, (index) {
          final option = question.options![index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: question.correctAnswerIndex == index
                      ? _teacherColor
                      : theme.dividerColor,
                  width: question.correctAnswerIndex == index ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(12),
                color: question.correctAnswerIndex == index
                    ? _teacherColor.withOpacity(0.05)
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
                activeColor: _teacherColor,
                title: Text(
                  option,
                  style: TextStyle(
                    fontWeight: question.correctAnswerIndex == index
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildMatchFollowingOptions(ThemeData theme, Question question) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Column A',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                'Column B',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 40),
          ],
        ),
        const SizedBox(height: 12),
        ...List.generate(question.matchPairs!.length, (index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: TextEditingController(
                      text: question.matchPairs![index].left,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Item ${index + 1}',
                      hintStyle: TextStyle(
                        color: theme.colorScheme.onSurface.withOpacity(0.4),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: theme.dividerColor),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    onChanged: (value) {
                      question.matchPairs![index].left = value;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: TextEditingController(
                      text: question.matchPairs![index].right,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Match ${index + 1}',
                      hintStyle: TextStyle(
                        color: theme.colorScheme.onSurface.withOpacity(0.4),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: theme.dividerColor),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    onChanged: (value) {
                      question.matchPairs![index].right = value;
                    },
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, size: 18),
                  onPressed: () {
                    if (question.matchPairs!.length > 2) {
                      setState(() {
                        question.matchPairs!.removeAt(index);
                      });
                    }
                  },
                  color: theme.colorScheme.error,
                ),
              ],
            ),
          );
        }),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () {
              setState(() {
                question.matchPairs!.add(MatchPair(left: '', right: ''));
              });
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Pair'),
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
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => AddQuestionModal(
        onSelect: (questionType) {
          setState(() {
            if (questionType == QuestionType.multipleChoice) {
              questions.add(
                Question(
                  id: questions.length + 1,
                  type: QuestionType.multipleChoice,
                  questionText: '',
                  options: ['', '', ''],
                  correctAnswerIndex: 0,
                ),
              );
            } else if (questionType == QuestionType.trueFalse) {
              questions.add(
                Question(
                  id: questions.length + 1,
                  type: QuestionType.trueFalse,
                  questionText: '',
                  options: ['True', 'False'],
                  correctAnswerIndex: 0,
                ),
              );
            }
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  Widget _buildBottomSection() {
    return Consumer<TestAssignmentLockProvider>(
      builder: (context, lockProv, _) {
        final uid =
            Provider.of<AuthProvider>(
              context,
              listen: false,
            ).currentUser?.uid ??
            '';
        final locked = lockProv.isLockedForOther(uid);
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
                child: LockedButtonWrapper(
                  isDisabled: locked,
                  child: ElevatedButton.icon(
                    onPressed: locked ? null : _showScheduleDialog,
                    icon: Icon(
                      locked ? Icons.lock_rounded : Icons.check_circle,
                    ),
                    label: Text(
                      locked ? 'Assignment Locked' : 'Schedule Test',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: locked
                          ? Colors.grey.shade400
                          : const Color(0xFF355872),
                      foregroundColor: Colors.white,
                      elevation: locked ? 0 : 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showScheduleDialog() {
    // Dismiss keyboard before showing dialog
    FocusScope.of(context).unfocus();

    // Validate date and time
    if (scheduledDate == null || scheduledTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select both date and time')),
      );
      return;
    }

    final formattedDate =
        '${scheduledDate!.day}/${scheduledDate!.month}/${scheduledDate!.year}';
    final formattedTime = scheduledTime!.format(context);

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (context) => ScheduleTestDialog(
        date: formattedDate,
        time: formattedTime,
        onSchedule: () async {
          final navigator = Navigator.of(context);
          final scaffoldMessenger = ScaffoldMessenger.of(context);

          navigator.pop(); // Close schedule dialog

          // Show loading dialog
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext dialogContext) {
              return const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFF355872),
                          ),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Scheduling test...',
                          style: TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );

          // Save the test
          final success = await _saveTest(publish: false, schedule: true);

          if (mounted) {
            // Close loading dialog
            navigator.pop();

            if (success) {
              // Navigate to tests page
              navigator.pushReplacement(
                MaterialPageRoute(builder: (context) => const TestsScreen()),
              );

              // Show success message after navigation
              Future.delayed(const Duration(milliseconds: 100), () {
                scaffoldMessenger.showSnackBar(
                  const SnackBar(content: Text('Test scheduled successfully!')),
                );
              });
            } else {
              final reason = _lastSaveError ?? 'Unknown error';
              scaffoldMessenger.showSnackBar(
                SnackBar(content: Text('Failed to schedule test: $reason')),
              );
            }
          }
        },
      ),
    );
  }
}

// Question model
enum QuestionType { multipleChoice, trueFalse, matchFollowing }

class Question {
  int id;
  QuestionType type;
  String questionText;
  List<String>? options;
  int? correctAnswerIndex;
  // For match the following
  List<MatchPair>? matchPairs;

  Question({
    required this.id,
    required this.type,
    required this.questionText,
    this.options,
    this.correctAnswerIndex,
    this.matchPairs,
  });
}

class MatchPair {
  String left;
  String right;

  MatchPair({required this.left, required this.right});
}

extension on _CreateTestScreenState {
  Future<bool> _saveTest({
    required bool publish,
    required bool schedule,
  }) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final testProv = Provider.of<TestProvider>(context, listen: false);
    final user = auth.currentUser;
    _lastSaveError = null;
    final canonicalTeacherId =
      fb_auth.FirebaseAuth.instance.currentUser?.uid ?? user?.uid ?? '';

    if (user == null || user.role != UserRole.teacher || canonicalTeacherId.isEmpty) {
      _lastSaveError = 'Please login as a teacher to continue';
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login as a teacher to continue')),
      );
      return false;
    }

    if (_titleController.text.trim().isEmpty) {
      _lastSaveError = 'Please enter a test title';
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a test title')),
      );
      return false;
    }

    if (selectedSubject == null || selectedSubject!.trim().isEmpty) {
      _lastSaveError = 'Please select a subject';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a subject')));
      return false;
    }
    if (selectedClass == null || selectedClass!.trim().isEmpty) {
      _lastSaveError = 'Please select a class';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a class')));
      return false;
    }
    if (selectedSection == null || selectedSection!.trim().isEmpty) {
      _lastSaveError = 'Please select a section';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a section')));
      return false;
    }

    final duration = int.tryParse(_timeLimitController.text.trim()) ?? 60;
    final now = DateTime.now();
    DateTime startDate = now;

    // Handle scheduling
    if (schedule && scheduledDate != null && scheduledTime != null) {
      startDate = DateTime(
        scheduledDate!.year,
        scheduledDate!.month,
        scheduledDate!.day,
        scheduledTime!.hour,
        scheduledTime!.minute,
      );
    }

    final endDate = startDate.add(Duration(minutes: duration));
    final tm.TestStatus status;

    if (schedule) {
      // Scheduled tests should be published so students can see them
      // The UI will check startDate to determine if they can actually take it
      status = tm.TestStatus.published;
    } else {
      status = publish ? tm.TestStatus.published : tm.TestStatus.draft;
    }

    // Map local questions to model questions
    final modelQuestions = questions.map((q) {
      // Determine question type
      tm.QuestionType questionType;
      if (q.type == QuestionType.multipleChoice) {
        questionType = tm.QuestionType.multipleChoice;
      } else if (q.type == QuestionType.trueFalse) {
        questionType = tm.QuestionType.trueFalse;
      } else {
        questionType = tm.QuestionType.shortAnswer;
      }

      // Determine correct answer
      String? correctAnswer;
      List<String>? options;

      if (q.type == QuestionType.multipleChoice ||
          q.type == QuestionType.trueFalse) {
        options = q.options;
        if (q.correctAnswerIndex != null &&
            q.options != null &&
            q.correctAnswerIndex! >= 0 &&
            q.correctAnswerIndex! < q.options!.length) {
          correctAnswer = q.options![q.correctAnswerIndex!];
        }
      } else if (q.type == QuestionType.matchFollowing &&
          q.matchPairs != null) {
        // Store match pairs as JSON string in correctAnswer
        final pairsMap = q.matchPairs!.asMap().map(
          (idx, pair) => MapEntry(idx.toString(), {
            'left': pair.left,
            'right': pair.right,
          }),
        );
        correctAnswer = pairsMap.toString();
      }

      return tm.Question(
        id: q.id.toString(),
        type: questionType,
        question: q.questionText,
        options: options,
        correctAnswer: correctAnswer,
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
      teacherId: canonicalTeacherId,
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

    // ── Acquire assignment lock before saving ──────────────────────────────
    final lockProv = Provider.of<TestAssignmentLockProvider>(
      context,
      listen: false,
    );
    final gradeClassId = 'Grade ${selectedClass!.trim()}';
    final lockAcquired = await lockProv.acquireLock(
      instituteId: user.instituteId ?? '',
      classId: gradeClassId,
      sectionId: normalizedSection,
      subjectName: selectedSubject!,
      teacherId: canonicalTeacherId,
      teacherName: user.name,
      nextAvailableTimestamp: endDate,
    );

    if (!lockAcquired) {
      final existingLock = lockProv.lockForOther(canonicalTeacherId);
      if (existingLock != null) {
        _lastSaveError =
            'Another teacher has already assigned this class for now.';
        if (mounted) {
          final when = _formatLockTime(existingLock.nextAvailableTimestamp);
          final who = existingLock.assignedByTeacherName;
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Test Already Assigned'),
              content: Text(
                '$who has already assigned a test for this class.\n\n'
                'You can assign the next test after $when or choose a later time.',
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return false;
      }

      // Lock check failed (permissions/network), but no conflicting active lock
      // was found; proceed so scheduling is not incorrectly blocked.
      debugPrint(
        '⚠️ Lock verification unavailable, continuing save without lock. '
        'Error: ${lockProv.errorMessage ?? 'unknown'}',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not verify active assignment lock. Scheduling anyway.',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
    // ── End lock acquisition ────────────────────────────────────────────────

    // If scheduled, we need to also store the schedule info in scheduledTests collection
    if (schedule && scheduledDate != null && scheduledTime != null) {
      final ok = await testProv.createScheduledTest(
        test,
        scheduledDate: scheduledDate!,
        scheduledTime: scheduledTime!,
      );
      if (!ok) {
        _lastSaveError = testProv.errorMessage?.trim().isNotEmpty == true
            ? testProv.errorMessage!.trim()
            : 'Unknown error';
      }
      if (!ok) {
        // Release lock if test creation failed
        await lockProv.releaseLock(
          instituteId: user.instituteId ?? '',
          classId: gradeClassId,
          sectionId: normalizedSection,
          teacherId: canonicalTeacherId,
        );
      }
      return ok;
    } else {
      final ok = await testProv.createTest(test);
      if (!ok) {
        _lastSaveError = testProv.errorMessage?.trim().isNotEmpty == true
            ? testProv.errorMessage!.trim()
            : 'Unknown error';
      }
      if (!ok) {
        await lockProv.releaseLock(
          instituteId: user.instituteId ?? '',
          classId: gradeClassId,
          sectionId: normalizedSection,
          teacherId: canonicalTeacherId,
        );
      }
      return ok;
    }
  }
}

/// Modern Add Question Modal with premium UI
class AddQuestionModal extends StatefulWidget {
  final Function(QuestionType) onSelect;

  const AddQuestionModal({super.key, required this.onSelect});

  @override
  State<AddQuestionModal> createState() => _AddQuestionModalState();
}

class _AddQuestionModalState extends State<AddQuestionModal>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF355872).withOpacity(0.98),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF355872).withOpacity(0.2),
                blurRadius: 30,
                offset: const Offset(0, -10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              // Title
              Row(
                children: [
                  const SizedBox(width: 24),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF355872), Color(0xFF557E98)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF355872).withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.add_circle_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'Add Question',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 24, right: 24),
                child: Text(
                  'Choose the question type for your test',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.6),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              // Options
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    QuestionOptionTile(
                      icon: Icons.format_list_bulleted_rounded,
                      title: 'Multiple Choice',
                      subtitle: 'Create questions with multiple options',
                      delay: 100,
                      onTap: () => widget.onSelect(QuestionType.multipleChoice),
                    ),
                    const SizedBox(height: 16),
                    QuestionOptionTile(
                      icon: Icons.check_circle_rounded,
                      title: 'True or False',
                      subtitle: 'Simple yes/no or true/false questions',
                      delay: 200,
                      onTap: () => widget.onSelect(QuestionType.trueFalse),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

/// Individual option tile with animations
class QuestionOptionTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final int delay;

  const QuestionOptionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.delay = 0,
  });

  @override
  State<QuestionOptionTile> createState() => _QuestionOptionTileState();
}

class _QuestionOptionTileState extends State<QuestionOptionTile>
    with SingleTickerProviderStateMixin {
  bool _isPressed = false;
  bool _isVisible = false;

  @override
  void initState() {
    super.initState();
    // Staggered animation entrance
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) {
        setState(() {
          _isVisible = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _isVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      child: AnimatedScale(
        scale: _isPressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: GestureDetector(
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) {
            setState(() => _isPressed = false);
            widget.onTap();
          },
          onTapCancel: () => setState(() => _isPressed = false),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A3E).withOpacity(0.6),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF355872).withOpacity(0.2),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: _isPressed
                      ? const Color(0xFF355872).withOpacity(0.3)
                      : Colors.transparent,
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(20),
                splashColor: const Color(0xFF355872).withOpacity(0.2),
                highlightColor: const Color(0xFF355872).withOpacity(0.1),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      // Icon container
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF355872).withOpacity(0.2),
                              const Color(0xFF557E98).withOpacity(0.1),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(0xFF355872).withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          widget.icon,
                          color: const Color(0xFF557E98),
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Text content
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.subtitle,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withOpacity(0.5),
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Arrow icon
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: const Color(0xFF355872).withOpacity(0.6),
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Modern Schedule Test Dialog with premium UI
class ScheduleTestDialog extends StatefulWidget {
  final String date;
  final String time;
  final VoidCallback onSchedule;

  const ScheduleTestDialog({
    super.key,
    required this.date,
    required this.time,
    required this.onSchedule,
  });

  @override
  State<ScheduleTestDialog> createState() => _ScheduleTestDialogState();
}

class _ScheduleTestDialogState extends State<ScheduleTestDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2E).withOpacity(0.98),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF355872).withOpacity(0.25),
                  blurRadius: 40,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icon and Title
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF355872), Color(0xFF4A7A9B)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF355872).withOpacity(0.4),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.event_available_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Schedule Test',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: -0.5,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Confirm schedule details',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.white54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  // Date Card
                  _buildInfoCard(
                    icon: Icons.calendar_today_rounded,
                    label: 'Date',
                    value: widget.date,
                  ),
                  const SizedBox(height: 16),
                  // Time Card
                  _buildInfoCard(
                    icon: Icons.access_time_rounded,
                    label: 'Time',
                    value: widget.time,
                  ),
                  const SizedBox(height: 24),
                  // Info Message
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF355872).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF355872).withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: const Color(0xFF4A7A9B).withOpacity(0.8),
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Students will be able to access it at the scheduled time.',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withOpacity(0.7),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: _ScheduleButton(
                          label: 'Cancel',
                          isPrimary: false,
                          onTap: () => Navigator.pop(context),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ScheduleButton(
                          label: 'Schedule',
                          isPrimary: true,
                          onTap: widget.onSchedule,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A3E).withOpacity(0.5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF355872).withOpacity(0.15),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF355872).withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFF4A7A9B), size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withOpacity(0.5),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Animated Schedule Button
class _ScheduleButton extends StatefulWidget {
  final String label;
  final bool isPrimary;
  final VoidCallback onTap;

  const _ScheduleButton({
    required this.label,
    required this.isPrimary,
    required this.onTap,
  });

  @override
  State<_ScheduleButton> createState() => _ScheduleButtonState();
}

class _ScheduleButtonState extends State<_ScheduleButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _isPressed ? 0.95 : 1.0,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            gradient: widget.isPrimary
                ? const LinearGradient(
                    colors: [Color(0xFF355872), Color(0xFF4A7A9B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: widget.isPrimary
                ? null
                : const Color(0xFF2A2A3E).withOpacity(0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.isPrimary
                  ? Colors.transparent
                  : const Color(0xFF355872).withOpacity(0.2),
              width: 1.5,
            ),
            boxShadow: widget.isPrimary
                ? [
                    BoxShadow(
                      color: const Color(0xFF355872).withOpacity(0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: widget.isPrimary
                    ? Colors.white
                    : Colors.white.withOpacity(0.7),
                letterSpacing: -0.3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
