import 'package:flutter/material.dart';

class CreateTestScreen extends StatefulWidget {
  const CreateTestScreen({Key? key}) : super(key: key);

  @override
  State<CreateTestScreen> createState() => _CreateTestScreenState();
}

class _CreateTestScreenState extends State<CreateTestScreen> {
  final _titleController = TextEditingController();
  final _totalMarksController = TextEditingController();
  final _timeLimitController = TextEditingController();

  String selectedSubject = 'Mathematics';
  String selectedClass = 'Grade 8';
  String selectedSection = 'Section A';
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
    Question(
      id: 2,
      type: QuestionType.shortAnswer,
      questionText: '',
    ),
  ];

  final List<String> subjects = ['Mathematics', 'Science', 'History'];
  final List<String> classes = ['Grade 8', 'Grade 9', 'Grade 10'];
  final List<String> sections = ['Section A', 'Section B', 'Section C'];

  @override
  void dispose() {
    _titleController.dispose();
    _totalMarksController.dispose();
    _timeLimitController.dispose();
    super.dispose();
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
                    _buildMetadataCard(),
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
                  onChanged: (value) {
                    setState(() {
                      selectedSubject = value!;
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
                  onChanged: (value) {
                    setState(() {
                      selectedClass = value!;
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
            onChanged: (value) {
              setState(() {
                selectedSection = value!;
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
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    required void Function(String?) onChanged,
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
            value: value,
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            items: items.map((String item) {
              return DropdownMenuItem<String>(
                value: item,
                child: Text(item),
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
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.content_copy, size: 18, color: Colors.grey[600]),
                    onPressed: () {
                      // Duplicate question
                      setState(() {
                        questions.add(Question(
                          id: questions.length + 1,
                          type: question.type,
                          questionText: question.questionText,
                          options: question.options != null
                              ? List.from(question.options!)
                              : null,
                          correctAnswerIndex: question.correctAnswerIndex,
                        ));
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
                borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2),
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
                  controller: TextEditingController(text: question.options![index]),
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
                  questions.add(Question(
                    id: questions.length + 1,
                    type: QuestionType.multipleChoice,
                    questionText: '',
                    options: ['', '', ''],
                    correctAnswerIndex: 0,
                  ));
                });
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Short Answer'),
              leading: const Icon(Icons.short_text),
              onTap: () {
                setState(() {
                  questions.add(Question(
                    id: questions.length + 1,
                    type: QuestionType.shortAnswer,
                    questionText: '',
                  ));
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
                        // Save draft
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Draft saved!')),
                        );
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
                        // Publish and assign
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
                border: Border(
                  top: BorderSide(color: Colors.grey[200]!),
                ),
              ),
              child: SizedBox(
                height: 64,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildNavItem(icon: Icons.dashboard, label: 'Dashboard', index: 0),
                    _buildNavItem(icon: Icons.school, label: 'Classes', index: 1),
                    _buildNavItem(icon: Icons.assignment, label: 'Tests', index: 2),
                    _buildNavItem(icon: Icons.leaderboard, label: 'Leaderboard', index: 3),
                    _buildNavItem(icon: Icons.person, label: 'Profile', index: 4),
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
        content: const Text('Are you sure you want to publish and assign this test to students?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context); // Go back to dashboard
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Test published successfully!')),
              );
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
