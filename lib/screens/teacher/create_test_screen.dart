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

  // Scheduling fields (always enabled with current date/time by default)
  DateTime? scheduledDate;
  TimeOfDay? scheduledTime;

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
              padding: const EdgeInsets.only(bottom: 100),
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
                            // Update sections based on selected class
                            final grade = (selectedClass ?? '').trim();
                            final secList = _gradeSections[grade] ?? <String>[];
                            sections = secList.map((s) => 'Section $s').toList()
                              ..sort();
                            // Reset selectedSection if not in new list
                            if (!sections.contains(selectedSection)) {
                              selectedSection = sections.isNotEmpty
                                  ? sections.first
                                  : null;
                            }
                            // Update subjects filtered by new class/section
                            subjects = _filteredSubjectsForSelection();
                            if (!subjects.contains(selectedSubject)) {
                              selectedSubject = subjects.isNotEmpty
                                  ? subjects.first
                                  : null;
                            }
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
                      subjects = _filteredSubjectsForSelection();
                      if (!subjects.contains(selectedSubject)) {
                        selectedSubject = subjects.isNotEmpty
                            ? subjects.first
                            : null;
                      }
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
          // Schedule Test (always shown)
          Row(
            children: [
              Icon(Icons.schedule, color: theme.colorScheme.primary, size: 24),
              const SizedBox(width: 8),
              Text(
                'Schedule Test',
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: scheduledDate ?? DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (date != null) {
                      setState(() {
                        scheduledDate = date;
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.dividerColor),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            scheduledDate == null
                                ? '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}'
                                : '${scheduledDate!.day}/${scheduledDate!.month}/${scheduledDate!.year}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 14,
                              color: scheduledDate == null
                                  ? theme.colorScheme.onSurface.withOpacity(0.4)
                                  : theme.colorScheme.onSurface,
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
                      initialTime: scheduledTime ?? TimeOfDay.now(),
                    );
                    if (time != null) {
                      setState(() {
                        scheduledTime = time;
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.dividerColor),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            scheduledTime == null
                                ? TimeOfDay.now().format(context)
                                : scheduledTime!.format(context),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 14,
                              color: scheduledTime == null
                                  ? theme.colorScheme.onSurface.withOpacity(0.4)
                                  : theme.colorScheme.onSurface,
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
                            matchPairs: question.matchPairs != null
                                ? question.matchPairs!
                                      .map(
                                        (p) => MatchPair(
                                          left: p.left,
                                          right: p.right,
                                        ),
                                      )
                                      .toList()
                                : null,
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Question'),
        content: SingleChildScrollView(
          child: Column(
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
                title: const Text('True or False'),
                leading: const Icon(Icons.check_circle_outline),
                onTap: () {
                  setState(() {
                    questions.add(
                      Question(
                        id: questions.length + 1,
                        type: QuestionType.trueFalse,
                        questionText: '',
                        options: ['True', 'False'],
                        correctAnswerIndex: 0,
                      ),
                    );
                  });
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('Match the Following'),
                leading: const Icon(Icons.compare_arrows),
                onTap: () {
                  setState(() {
                    questions.add(
                      Question(
                        id: questions.length + 1,
                        type: QuestionType.matchFollowing,
                        questionText: '',
                        matchPairs: [
                          MatchPair(left: '', right: ''),
                          MatchPair(left: '', right: ''),
                        ],
                      ),
                    );
                  });
                  Navigator.pop(context);
                },
              ),
            ],
          ),
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
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                _showScheduleDialog();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
              child: const Text(
                'Schedule Test',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
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
              await _saveTest(publish: true, schedule: false);
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
      builder: (context) => AlertDialog(
        title: const Text('Schedule Test'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This test will be scheduled for:',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.calendar_today,
                  size: 18,
                  color: Colors.orange,
                ),
                const SizedBox(width: 8),
                Text(formattedDate),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.access_time, size: 18, color: Colors.orange),
                const SizedBox(width: 8),
                Text(formattedTime),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Students will be able to access it at the scheduled time.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _saveTest(publish: false, schedule: true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
            ),
            child: const Text('Schedule'),
          ),
        ],
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
  Future<void> _saveTest({
    required bool publish,
    required bool schedule,
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

    // If scheduled, we need to also store the schedule info in scheduledTests collection
    if (schedule && scheduledDate != null && scheduledTime != null) {
      final ok = await testProv.createScheduledTest(
        test,
        scheduledDate: scheduledDate!,
        scheduledTime: scheduledTime!,
      );
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Test scheduled successfully!')),
        );
        if (mounted) {
          Navigator.pop(context);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed: ${testProv.errorMessage ?? 'Unknown error'}',
            ),
          ),
        );
      }
    } else {
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
            content: Text(
              'Failed: ${testProv.errorMessage ?? 'Unknown error'}',
            ),
          ),
        );
      }
    }
  }
}
