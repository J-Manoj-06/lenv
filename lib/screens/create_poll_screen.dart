/// Create Poll Screen - Allows users to create polls in chat
/// Min 2 options, Max 6 options, Single/Multi-select toggle
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/poll_model.dart';
import '../services/poll_service.dart';
import '../core/constants/app_colors.dart';
import '../providers/auth_provider.dart' as local_auth;

class CreatePollScreen extends StatefulWidget {
  final String chatId;
  final String chatType; // 'community', 'group', 'individual'

  const CreatePollScreen({
    super.key,
    required this.chatId,
    required this.chatType,
  });

  @override
  State<CreatePollScreen> createState() => _CreatePollScreenState();
}

class _CreatePollScreenState extends State<CreatePollScreen> {
  final _formKey = GlobalKey<FormState>();
  final _questionController = TextEditingController();
  final List<TextEditingController> _optionControllers = [
    TextEditingController(),
    TextEditingController(),
  ];

  bool _allowMultiple = false;
  bool _isSending = false;
  String? _errorMessage;

  final int _minOptions = 2;
  final int _maxOptions = 6;

  @override
  void initState() {
    super.initState();
    print('🔵 CreatePollScreen initState called');
    print('🔵 Chat ID: ${widget.chatId}');
    print('🔵 Chat Type: ${widget.chatType}');
  }

  @override
  void dispose() {
    print('🔵 CreatePollScreen disposed');
    _questionController.dispose();
    for (final controller in _optionControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    if (_optionControllers.length < _maxOptions) {
      setState(() {
        _optionControllers.add(TextEditingController());
      });
    }
  }

  void _removeOption(int index) {
    if (_optionControllers.length > _minOptions) {
      setState(() {
        _optionControllers[index].dispose();
        _optionControllers.removeAt(index);
      });
    }
  }

  bool _isValid() {
    final question = _questionController.text.trim();
    if (question.isEmpty) return false;

    int validOptions = 0;
    for (final controller in _optionControllers) {
      if (controller.text.trim().isNotEmpty) {
        validOptions++;
      }
    }

    return validOptions >= _minOptions;
  }

  Future<void> _sendPoll() async {
    print('🔵 _sendPoll called');
    if (!_isValid()) {
      print('🔵 ❌ Poll validation failed');
      setState(() {
        _errorMessage =
            'Please enter a question and at least $_minOptions options';
      });
      return;
    }
    print('🔵 ✅ Poll validation passed');

    setState(() {
      _isSending = true;
      _errorMessage = null;
    });

    try {
      print('🔵 Getting auth provider...');
      final authProvider = Provider.of<local_auth.AuthProvider>(
        context,
        listen: false,
      );
      final currentUser = authProvider.currentUser;
      print('🔵 Current user: ${currentUser?.uid} - ${currentUser?.name}');

      if (currentUser == null) {
        print('🔵 ❌ User not authenticated');
        throw Exception('User not authenticated');
      }

      // Build poll options
      print('🔵 Building poll options...');
      final options = <PollOption>[];
      for (int i = 0; i < _optionControllers.length; i++) {
        final text = _optionControllers[i].text.trim();
        if (text.isNotEmpty) {
          options.add(
            PollOption(
              id: 'opt_${DateTime.now().millisecondsSinceEpoch}_$i',
              text: text,
            ),
          );
          print('🔵 Option $i: $text');
        }
      }
      print('🔵 Total options: ${options.length}');

      // Create poll model
      print('🔵 Creating poll model...');
      final poll = PollModel(
        question: _questionController.text.trim(),
        options: options,
        allowMultiple: _allowMultiple,
        createdBy: currentUser.uid,
        createdByName: currentUser.name,
        createdByRole: currentUser.role.toString().split('.').last,
      );
      print('🔵 Poll question: ${poll.question}');
      print('🔵 Allow multiple: ${poll.allowMultiple}');

      // Send poll
      print('🔵 Sending poll to Firestore...');
      print('🔵 Chat ID: ${widget.chatId}');
      print('🔵 Chat Type: ${widget.chatType}');
      final pollService = PollService();
      final messageId = await pollService.sendPoll(
        chatId: widget.chatId,
        poll: poll,
        chatType: widget.chatType,
      );
      print('🔵 ✅ Poll sent successfully! Message ID: $messageId');

      // Success - go back to chat
      if (mounted) {
        print('🔵 Navigating back to chat...');
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Poll sent successfully!'),
            backgroundColor: AppColors.success,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('🔵 ❌ ERROR sending poll: $e');
      print('🔵 Stack trace: ${StackTrace.current}');
      setState(() {
        _isSending = false;
        _errorMessage = 'Failed to send poll: ${e.toString()}';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_errorMessage!),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    print('🔵 CreatePollScreen build method called');
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Poll'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Question field
            TextFormField(
              controller: _questionController,
              decoration: const InputDecoration(
                labelText: 'Poll Question',
                hintText: 'Ask a question...',
                prefixIcon: Icon(Icons.poll),
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 24),

            // Options header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Options',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${_optionControllers.length}/$_maxOptions',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Options list
            ..._optionControllers.asMap().entries.map((entry) {
              final index = entry.key;
              final controller = entry.value;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: controller,
                        decoration: InputDecoration(
                          labelText: 'Option ${index + 1}',
                          hintText: 'Enter option text...',
                          border: const OutlineInputBorder(),
                          prefixIcon: Icon(
                            _allowMultiple
                                ? Icons.check_box_outline_blank
                                : Icons.radio_button_unchecked,
                            color: primaryColor,
                          ),
                        ),
                        maxLength: 100,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    if (_optionControllers.length > _minOptions)
                      IconButton(
                        icon: const Icon(
                          Icons.remove_circle_outline,
                          color: Colors.red,
                        ),
                        onPressed: () => _removeOption(index),
                        tooltip: 'Remove option',
                      ),
                  ],
                ),
              );
            }),

            // Add option button
            if (_optionControllers.length < _maxOptions)
              OutlinedButton.icon(
                onPressed: _addOption,
                icon: const Icon(Icons.add),
                label: const Text('Add Option'),
                style: OutlinedButton.styleFrom(foregroundColor: primaryColor),
              ),
            const SizedBox(height: 24),

            // Allow multiple answers toggle
            Card(
              child: SwitchListTile(
                title: const Text('Allow multiple answers'),
                subtitle: const Text('Users can select more than one option'),
                value: _allowMultiple,
                activeThumbColor: primaryColor,
                onChanged: (value) {
                  setState(() {
                    _allowMultiple = value;
                  });
                },
              ),
            ),
            const SizedBox(height: 24),

            // Error message
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),

            // Send button
            ElevatedButton(
              onPressed: _isSending || !_isValid() ? null : _sendPoll,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isSending
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Send Poll',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),

            // Validation hint
            if (!_isValid())
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Enter a question and at least $_minOptions options to send',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
