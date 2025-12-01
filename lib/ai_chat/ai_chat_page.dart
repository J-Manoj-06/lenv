import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'chat_message.dart';
import 'ai_service.dart';
import 'ai_quiz_models.dart';
import 'ai_quiz_renderer.dart';

class AiChatPage extends StatefulWidget {
  const AiChatPage({super.key});

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AiService _ai = AiService();
  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _messages.clear();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _addMessage(ChatMessage msg) {
    setState(() {
      _messages.add(msg);
    });
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendText() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();
    _addMessage(
      ChatMessage(id: UniqueKey().toString(), sender: 'student', text: text),
    );

    // Simple AI echo/solution mock
    _addMessage(
      ChatMessage(
        id: UniqueKey().toString(),
        sender: 'ai',
        text:
            'Here is an explanation for: "$text"\n\n1) Understand the problem.\n2) Apply rules.\n3) Verify result.',
      ),
    );
  }

  Future<void> _pickImageAndAnalyze({required bool forQuiz}) async {
    final source = await _chooseSource();
    if (source == null) return;
    final xfile = await _picker.pickImage(source: source, imageQuality: 85);
    if (xfile == null) return;
    final file = File(xfile.path);

    _addMessage(
      ChatMessage(
        id: UniqueKey().toString(),
        sender: 'student',
        text: forQuiz ? 'Generate quiz from image' : 'Scan doubt from image',
        imageUrl: xfile.path,
      ),
    );

    if (!forQuiz) {
      final res = await _ai.analyzeDoubt(file);
      _addMessage(
        ChatMessage(
          id: UniqueKey().toString(),
          sender: 'ai',
          text: res.explanation.join('\n'),
        ),
      );
      // Similar questions card
      _addMessage(
        ChatMessage(
          id: UniqueKey().toString(),
          sender: 'ai',
          text:
              'Similar questions:\n- ${res.similarQuestions.join('\n- ')}\n\nTap any to ask again.',
        ),
      );
    } else {
      final quiz = await _ai.generateQuizFromImage(file);
      _addMessage(
        ChatMessage(
          id: UniqueKey().toString(),
          sender: 'ai',
          quiz: quiz,
          text: 'Generated quiz from image:',
        ),
      );
    }
  }

  Future<ImageSource?> _chooseSource() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  void _onSimilarQuestionTap(String q) {
    _addMessage(
      ChatMessage(id: UniqueKey().toString(), sender: 'student', text: q),
    );
    _addMessage(
      ChatMessage(
        id: UniqueKey().toString(),
        sender: 'ai',
        text:
            'Solution for "$q":\n\n1) Note given values.\n2) Apply rule.\n3) Compute carefully.',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const botColor = Color(0xFFF27F0D);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: botColor,
        title: const Text('AI Chatbot'),
      ),
      body: Column(
        children: [
          // Quick Action Chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _chip(
                    'Scan Doubt 📸',
                    () => _pickImageAndAnalyze(forQuiz: false),
                  ),
                  const SizedBox(width: 8),
                  _chip(
                    'Generate Quiz 🧪',
                    () => _pickImageAndAnalyze(forQuiz: true),
                  ),
                  const SizedBox(width: 8),
                  _chip('Explain My Mistake ❓', () {
                    // Focus input for text
                    FocusScope.of(context).requestFocus(FocusNode());
                  }),
                ],
              ),
            ),
          ),

          // Chat list
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (_, i) {
                final m = _messages[i];
                final isStudent = m.sender == 'student';
                return Align(
                  alignment: isStudent
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.all(12),
                    constraints: const BoxConstraints(maxWidth: 340),
                    decoration: BoxDecoration(
                      color: isStudent
                          ? Colors.blue.shade600
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: isStudent
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        if (m.text != null)
                          Text(
                            m.text!,
                            style: TextStyle(
                              color: isStudent ? Colors.white : Colors.black87,
                            ),
                          ),
                        if (m.imageUrl != null) ...[
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(
                              File(m.imageUrl!),
                              width: 280,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ],
                        if (m.quiz != null) ...[
                          const SizedBox(height: 8),
                          Card(
                            elevation: 0,
                            color: Colors.white,
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: AiQuizRenderer(
                                quiz: m.quiz as AiGeneratedQuiz,
                              ),
                            ),
                          ),
                        ],
                        if (!isStudent &&
                            (m.text?.startsWith('Similar questions:') ??
                                false)) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children:
                                (m.text!
                                        .split('\n')
                                        .where((e) => e.startsWith('- '))
                                        .map((e) => e.substring(2))
                                        .toList())
                                    .map(
                                      (q) => ActionChip(
                                        label: Text(q),
                                        onPressed: () =>
                                            _onSimilarQuestionTap(q),
                                      ),
                                    )
                                    .toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Input bar
          _inputBar(),
        ],
      ),
    );
  }

  Widget _chip(String label, VoidCallback onTap) => ActionChip(
    label: Text(label),
    onPressed: onTap,
    backgroundColor: Colors.orange.shade100,
  );

  Widget _inputBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.camera_alt),
              onPressed: () => _pickImageAndAnalyze(forQuiz: false),
            ),
            IconButton(
              icon: const Icon(Icons.photo_library),
              onPressed: () => _pickImageAndAnalyze(forQuiz: true),
            ),
            Expanded(
              child: TextField(
                controller: _inputController,
                decoration: const InputDecoration(
                  hintText: 'Type your question...',
                ),
              ),
            ),
            IconButton(icon: const Icon(Icons.send), onPressed: _sendText),
          ],
        ),
      ),
    );
  }
}
