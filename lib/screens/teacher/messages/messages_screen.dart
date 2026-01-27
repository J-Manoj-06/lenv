import 'package:flutter/material.dart';

/// MessagesScreen
/// Converted from provided HTML empty state.
/// Optionally receives a student to start a conversation.
class MessagesScreen extends StatelessWidget {
  final String? studentId;
  final String? studentName;

  const MessagesScreen({super.key, this.studentId, this.studentName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFF6F5F8),
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : const Color(0xFFF6F5F8),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.iconTheme.color),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text(
          'Messages',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: theme.textTheme.bodyLarge?.color,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.search, color: theme.iconTheme.color),
            onPressed: () {}, // TODO: implement search
          ),
        ],
      ),
      body: _buildBody(context),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'teacher_messages_new_message_fab',
        onPressed: () {
          // Placeholder for compose action
          _showComposeDialog(context);
        },
        backgroundColor: const Color(0xFF7A5CFF),
        icon: const Icon(Icons.add_comment),
        label: Text(
          studentName != null ? 'Message $studentName' : 'New Message',
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Illustration
            SizedBox(
              width: 280,
              child: Image.network(
                'https://lh3.googleusercontent.com/aida-public/AB6AXuAkbCC_JSXZQlfJEuK0ujgXqlA_x4TcaD8OqnVAr9S06zKI85_Gv2pBdlMlNJwbaQRLtWiL9riQLrzHiOdeI_aZxaU0crn0h02Cg_fIbnJZhJoo6MRRNZE3JEoXvcVhnVU7I8-N5tRdsRRIsGItja34qq1XUR1Av7vB3kAMEUtRdhK0Cn33RFu4xtzevSS_HRdRuMEUVLWINXiaiAqG5JIWt_rZ-B15nyOiIjKdhKBBjGXVvr7espM77UmFe5MIdjYL-_PoyzRi6Sjn',
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              studentName != null
                  ? 'Start a conversation with $studentName'
                  : 'Start a conversation',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Connect with parents, students, or colleagues by sending your first message.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => _showComposeDialog(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7A5CFF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 3,
              ),
              icon: const Icon(Icons.add_comment),
              label: Text(
                studentName != null ? 'Message $studentName' : 'New Message',
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showComposeDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          studentName != null ? 'Message $studentName' : 'New Message',
        ),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Type your message...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              // Placeholder send logic
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Message sent (placeholder)'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }
}
