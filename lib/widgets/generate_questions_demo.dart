import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/question_service.dart';

class GenerateQuestionsDemo extends StatefulWidget {
  const GenerateQuestionsDemo({super.key});

  @override
  State<GenerateQuestionsDemo> createState() => _GenerateQuestionsDemoState();
}

class _GenerateQuestionsDemoState extends State<GenerateQuestionsDemo> {
  final _topicController = TextEditingController(text: 'Photosynthesis');
  final _countController = TextEditingController(text: '9');
  final _service = QuestionService();

  Map<String, dynamic>? _result;
  bool _loading = false;
  String? _error;

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final topic = _topicController.text.trim();
      final count = int.tryParse(_countController.text.trim()) ?? 9;
      final data = await _service.generateQuestions(topic: topic, count: count);
      setState(() => _result = data);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Widget _buildResult() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Text('Error: $_error', style: const TextStyle(color: Colors.red));
    }
    if (_result == null) {
      return const Text('No data yet.');
    }
    return Expanded(
      child: SingleChildScrollView(
        child: Text(const JsonEncoder.withIndent('  ').convert(_result)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Generate Questions (DeepSeek via Cloud Function)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _topicController,
              decoration: const InputDecoration(labelText: 'Topic'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _countController,
              decoration: const InputDecoration(labelText: 'Count (3-100)'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loading ? null : _generate,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Generate'),
            ),
            const SizedBox(height: 16),
            _buildResult(),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _topicController.dispose();
    _countController.dispose();
    super.dispose();
  }
}
