import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/ai_test_service.dart';
import '../../services/firestore_service.dart';
import '../../models/test_question.dart';
import '../../exceptions/ai_exceptions.dart';

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

  // Form controllers
  final _topicController = TextEditingController();
  final _totalMarksController = TextEditingController(text: '10');

  // Form values
  String? _selectedClass;
  String? _selectedSection;
  String? _selectedSubject;
  int _numQuestions = 5;

  // Generated questions
  List<TestQuestion>? _generatedQuestions;
  bool _isGenerating = false;

  // Available options
  final List<String> _classes = [
    'Grade 1',
    'Grade 2',
    'Grade 3',
    'Grade 4',
    'Grade 5',
    'Grade 6',
    'Grade 7',
    'Grade 8',
    'Grade 9',
    'Grade 10',
    'Grade 11',
    'Grade 12',
  ];

  final List<String> _sections = ['A', 'B', 'C', 'D', 'E', 'F'];

  final List<String> _subjects = [
    'Mathematics',
    'Science',
    'English',
    'Social Studies',
    'Physics',
    'Chemistry',
    'Biology',
    'History',
    'Geography',
    'Computer Science',
    'Economics',
    'Literature',
  ];

  @override
  void dispose() {
    _topicController.dispose();
    _totalMarksController.dispose();
    _aiService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Generate Test with AI'), elevation: 0),
      body: _generatedQuestions == null
          ? _buildFormView()
          : _buildPreviewView(),
    );
  }

  /// Form view for entering test parameters
  Widget _buildFormView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.auto_awesome, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'AI Test Generator',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: Colors.blue.shade900,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Automatically generate test questions using AI. Fill in the parameters below and click Generate.',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Class dropdown
            DropdownButtonFormField<String>(
              value: _selectedClass,
              decoration: const InputDecoration(
                labelText: 'Class',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.school),
              ),
              items: _classes.map((cls) {
                return DropdownMenuItem(value: cls, child: Text(cls));
              }).toList(),
              onChanged: (value) => setState(() => _selectedClass = value),
              validator: (value) =>
                  value == null ? 'Please select a class' : null,
            ),
            const SizedBox(height: 16),

            // Section dropdown
            DropdownButtonFormField<String>(
              value: _selectedSection,
              decoration: const InputDecoration(
                labelText: 'Section',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.group),
              ),
              items: _sections.map((section) {
                return DropdownMenuItem(value: section, child: Text(section));
              }).toList(),
              onChanged: (value) => setState(() => _selectedSection = value),
              validator: (value) =>
                  value == null ? 'Please select a section' : null,
            ),
            const SizedBox(height: 16),

            // Subject dropdown
            DropdownButtonFormField<String>(
              value: _selectedSubject,
              decoration: const InputDecoration(
                labelText: 'Subject',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.book),
              ),
              items: _subjects.map((subject) {
                return DropdownMenuItem(value: subject, child: Text(subject));
              }).toList(),
              onChanged: (value) => setState(() => _selectedSubject = value),
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

            // Total marks text field
            TextFormField(
              controller: _totalMarksController,
              decoration: const InputDecoration(
                labelText: 'Total Marks',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.format_list_numbered),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter total marks';
                }
                final marks = int.tryParse(value);
                if (marks == null || marks <= 0) {
                  return 'Please enter a valid number';
                }
                if (marks < _numQuestions) {
                  return 'Total marks must be at least $_numQuestions';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),

            // Generate button
            ElevatedButton.icon(
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
                style: const TextStyle(fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),

            // Info card
            Card(
              color: Colors.amber.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.amber.shade900),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Generation may take 10-30 seconds. Please wait...',
                        style: TextStyle(
                          color: Colors.amber.shade900,
                          fontSize: 13,
                        ),
                      ),
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

  /// Preview view showing generated questions
  Widget _buildPreviewView() {
    final questions = _generatedQuestions!;

    return Column(
      children: [
        // Header
        Container(
          width: double.infinity,
          color: Colors.green.shade50,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green.shade700),
                  const SizedBox(width: 8),
                  Text(
                    'Test Generated Successfully!',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.green.shade900,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${questions.length} questions • Total marks: ${questions.fold<int>(0, (sum, q) => sum + q.marks)}',
                style: TextStyle(color: Colors.grey.shade700),
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
            color: Colors.white,
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
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
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
      child: Padding(
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
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Q${index + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade900,
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
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.star,
                            size: 14,
                            color: Colors.amber.shade700,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${question.marks} marks',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade900,
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
                          ? Colors.green.shade50
                          : Colors.grey.shade50,
                      border: Border.all(
                        color: isCorrect
                            ? Colors.green.shade300
                            : Colors.grey.shade300,
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
                                ? Colors.green.shade700
                                : Colors.grey.shade300,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              optionLetter,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isCorrect ? Colors.white : Colors.black,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(optionText)),
                        if (isCorrect)
                          Icon(
                            Icons.check_circle,
                            color: Colors.green.shade700,
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
                  const Text(
                    'Correct Answer: ',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.green.shade700),
                    ),
                    child: Text(
                      question.correctAnswer.toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade900,
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
          builder: (context) => AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text(
                  'Generating test questions...',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'This may take 10-30 seconds. Please wait.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ],
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

      // Get current user
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      // Calculate total marks
      final totalMarks = _generatedQuestions!.fold<int>(
        0,
        (sum, q) => sum + q.marks,
      );

      // Create test document
      final testDoc = {
        'testName': '${_selectedSubject} - ${_topicController.text.trim()}',
        'className': _selectedClass,
        'section': _selectedSection,
        'subject': _selectedSubject,
        'topic': _topicController.text.trim(),
        'totalMarks': totalMarks,
        'questionCount': _generatedQuestions!.length,
        'teacherId': currentUser.uid,
        'teacherName': currentUser.displayName ?? 'Teacher',
        'teacherEmail': currentUser.email ?? '',
        'questions': _generatedQuestions!.map((q) => q.toFirestore()).toList(),
        'status': 'scheduled',
        'autoPublished': false,
        'resultsPublished': false,
        'generatedByAI': true,
        'aiTopic': _topicController.text.trim(),
      };

      // Save to Firestore
      await _firestoreService.saveScheduledTest(testDoc);

      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Test saved successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        // Go back to previous screen
        Navigator.of(context).pop();
        Navigator.of(context).pop();
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
