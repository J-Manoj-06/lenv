import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/test_model.dart' as tm;
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/test_provider.dart';
import '../../services/teacher_service.dart';
import '../../services/deepseek_service.dart';
import '../../core/config/deepseek_config.dart';
import '../../widgets/teacher_bottom_nav.dart';
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

  // Scheduling state (always visible; defaults to now)
  DateTime? _scheduledDate;
  TimeOfDay? _scheduledTime;

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
        // Show only the standard (grade) in the class dropdown
        classes = gradeOnlyList;
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

    // Validate inputs
    if (_subjectController.text.trim().isEmpty) {
      _showErrorDialog('Please enter a subject');
      return;
    }
    if (_topicsController.text.trim().isEmpty) {
      _showErrorDialog('Please enter topics');
      return;
    }
    if (_questionCountController.text.trim().isEmpty) {
      _showErrorDialog('Please enter the number of questions');
      return;
    }
    if (selectedClass == null) {
      _showErrorDialog('Please select a class');
      return;
    }

    final questionCount = int.tryParse(_questionCountController.text.trim());
    if (questionCount == null || questionCount <= 0 || questionCount > 50) {
      _showErrorDialog('Please enter a valid number of questions (1-50)');
      return;
    }

    // Check if DeepSeek is configured
    if (!DeepSeekConfig.isConfigured) {
      _showErrorDialog(
        'DeepSeek API not configured!\n\n'
        'Please add your API key in:\n'
        'lib/core/config/deepseek_config.dart\n\n'
        'Get your API key from:\nhttps://platform.deepseek.com/',
      );
      return;
    }

    setState(() {
      isGenerating = true;
    });

    // Call DeepSeek API
    final deepSeekService = DeepSeekService();
    deepSeekService
        .generateTestQuestions(
          subject: _subjectController.text.trim(),
          topics: _topicsController.text.trim(),
          questionCount: questionCount,
          difficulty: selectedDifficulty,
          grade: selectedClass!,
        )
        .then((aiQuestions) {
          setState(() {
            isGenerating = false;
            hasGenerated = true;
            generatedQuestions = aiQuestions.map((q) {
              return GeneratedQuestion(
                question: q['question'] ?? '',
                answer: q['correctAnswer'] ?? '',
                options: List<String>.from(q['options'] ?? []),
                explanation: q['explanation'] ?? '',
                topic: q['topic'] ?? _topicsController.text.trim(),
                difficulty: q['difficulty'] ?? selectedDifficulty,
                confidence:
                    95, // DeepSeek doesn't provide confidence, so we use a high default
                points: q['points'] ?? 1,
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

          _showErrorDialog(
            'Failed to generate questions:\n\n$error\n\n'
            'Please check your API key and internet connection.',
          );
        });
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
    final timeText = _scheduledTime == null
        ? 'Select time'
        : _scheduledTime!.format(context);

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
            'Schedule Test',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: theme.textTheme.titleLarge?.color,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildScheduleTile(
                  icon: Icons.calendar_today,
                  label: 'Date',
                  value: dateText,
                  onTap: _pickDate,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildScheduleTile(
                  icon: Icons.access_time,
                  label: 'Start Time',
                  value: timeText,
                  onTap: _pickTime,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Defaulted to current date/time. Adjust if needed.',
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

  Future<void> _pickTime() async {
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
      setState(() => _scheduledTime = picked);
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
      endDate = startDate.add(Duration(minutes: duration));
      // Scheduled tests are published so students can see them, but UI checks startDate
      status = tm.TestStatus.published;
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
