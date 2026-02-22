import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../../services/chat_service.dart';
import '../../providers/parent_provider.dart';

class ParentChatScreen extends StatefulWidget {
  final String teacherId;
  final String teacherName;
  final String? teacherSubject;
  final String? teacherAvatarUrl;
  final String className;
  final String? section;

  const ParentChatScreen({
    super.key,
    required this.teacherId,
    required this.teacherName,
    required this.className,
    this.section,
    this.teacherSubject,
    this.teacherAvatarUrl,
  });

  @override
  State<ParentChatScreen> createState() => _ParentChatScreenState();
}

class _ParentChatScreenState extends State<ParentChatScreen> {
  final ChatService _chat = ChatService();
  final TextEditingController _controller = TextEditingController();
  String? _conversationId;
  // Track messages already scheduled for read marking to avoid re-scheduling.
  final Set<String> _scheduledReadIds = <String>{};

  // Audio recording
  final AudioRecorder _audioRecorder = AudioRecorder();
  final ValueNotifier<bool> _isRecording = ValueNotifier<bool>(false);
  final ValueNotifier<int> _recordingDuration = ValueNotifier<int>(0);
  Timer? _recordingTimer;
  String? _recordingPath;

  @override
  void dispose() {
    _controller.dispose();
    _audioRecorder.dispose();
    _recordingTimer?.cancel();
    _isRecording.dispose();
    _recordingDuration.dispose();
    super.dispose();
  }

  Future<void> _batchUpdateIncoming(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (_conversationId == null) return;

    final deliveryBatch = FirebaseFirestore.instance.batch();
    bool deliveryUpdates = false;
    final List<DocumentReference<Map<String, dynamic>>> toMarkRead = [];

    for (final d in docs) {
      final data = d.data();
      final senderRole = (data['senderRole'] ?? '').toString();
      if (senderRole != 'parent') {
        // Incoming from teacher – mark delivered immediately.
        if (data['deliveredToParent'] != true) {
          deliveryBatch.update(d.reference, {'deliveredToParent': true});
          deliveryUpdates = true;
        }
        // Schedule read marking (delayed) if not already read/scheduled.
        final id = d.id;
        if (data['readByParent'] != true && !_scheduledReadIds.contains(id)) {
          _scheduledReadIds.add(id);
          toMarkRead.add(d.reference);
        }
      }
    }

    if (deliveryUpdates) {
      await deliveryBatch.commit();
    }

    if (toMarkRead.isNotEmpty) {
      // Delay read marking so UI shows double tick before blue tick.
      Future.delayed(const Duration(milliseconds: 1200), () async {
        if (!mounted || _conversationId == null) return;
        final readBatch = FirebaseFirestore.instance.batch();
        for (final ref in toMarkRead) {
          readBatch.update(ref, {'readByParent': true});
        }
        await readBatch.commit();
        await _chat.markAsRead(
          conversationId: _conversationId!,
          viewerRole: 'parent',
        );
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureConversation());
  }

  Future<void> _ensureConversation() async {
    final parentProvider = Provider.of<ParentProvider>(context, listen: false);
    final child = parentProvider.children.first; // assume at least one child

    // CRITICAL: Use auth UIDs, not provider IDs that might be null/email
    final parentAuthUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final schoolCode = child.schoolCode ?? '';
    final teacherId = widget.teacherId;
    final studentId = child.uid;

    final id = await _chat.ensureConversation(
      schoolCode: schoolCode,
      teacherId: teacherId,
      parentId: parentAuthUid,
      studentId: studentId,
      studentName: child.name,
      className: widget.className,
      section: widget.section,
    );

    setState(() => _conversationId = id);
  }

  Future<void> _startRecording() async {
    if (!await _audioRecorder.hasPermission()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission needed')),
      );
      return;
    }

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/ptc_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _audioRecorder.start(
      const RecordConfig(encoder: AudioEncoder.aacHe, bitRate: 128000),
      path: path,
    );

    setState(() {
      _isRecording.value = true;
      _recordingPath = path;
      _recordingDuration.value = 0;
    });

    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _recordingDuration.value++,
    );
  }

  Future<void> _stopAndDeleteRecording() async {
    _recordingTimer?.cancel();
    await _audioRecorder.stop();

    if (_recordingPath != null) {
      try {
        final file = File(_recordingPath!);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        print('Error deleting recording: $e');
      }
    }

    setState(() {
      _isRecording.value = false;
      _recordingPath = null;
      _recordingDuration.value = 0;
    });
  }

  Future<void> _stopAndSendRecording() async {
    if (!_isRecording.value) return;
    _recordingTimer?.cancel();

    final path = await _audioRecorder.stop();
    setState(() => _isRecording.value = false);

    if (path == null || _conversationId == null) return;

    // TODO: Implement audio message upload similar to group chat
    // For now, just show a message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Audio upload feature coming soon')),
    );
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF121212)
          : const Color(0xFFF6F7F8),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
        elevation: 0.5,
        titleSpacing: 0,
        title: Row(
          children: [
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.grey.shade800,
              backgroundImage: widget.teacherAvatarUrl != null
                  ? (widget.teacherAvatarUrl!.isNotEmpty
                        ? NetworkImage(widget.teacherAvatarUrl!)
                        : null)
                  : null,
              child: widget.teacherAvatarUrl == null
                  ? const Icon(Icons.person, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.teacherName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${widget.className}${widget.section != null ? ' - ${widget.section}' : ''}${widget.teacherSubject != null ? ' • ${widget.teacherSubject}' : ''}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _conversationId == null
                ? const SizedBox()
                : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _chat.messagesStream(_conversationId!),
                    builder: (context, snapshot) {
                      final docs = snapshot.data?.docs ?? [];
                      // After receiving messages, mark delivered for incoming ones
                      if (_conversationId != null && docs.isNotEmpty) {
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => _batchUpdateIncoming(docs),
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemBuilder: (context, index) {
                          final msg = docs[index].data();
                          final isParent = msg['senderRole'] == 'parent';
                          final deliveredToTeacher =
                              (msg['deliveredToTeacher'] ?? false) as bool;
                          final readByTeacher =
                              (msg['readByTeacher'] ?? false) as bool;

                          return Align(
                            alignment: isParent
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 360),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: isParent
                                      ? const Color(0xFF1362EB)
                                      : (isDark
                                            ? const Color(0xFF2A2A2A)
                                            : Colors.grey.shade200),
                                  borderRadius: BorderRadius.circular(12)
                                      .copyWith(
                                        bottomRight: isParent
                                            ? const Radius.circular(4)
                                            : null,
                                        bottomLeft: !isParent
                                            ? const Radius.circular(4)
                                            : null,
                                      ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        msg['text'] ?? '',
                                        style: TextStyle(
                                          color: isParent
                                              ? Colors.white
                                              : (isDark
                                                    ? Colors.white
                                                    : Colors.black87),
                                        ),
                                      ),
                                      if (isParent) ...[
                                        const SizedBox(height: 4),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              readByTeacher
                                                  ? Icons.done_all
                                                  : deliveredToTeacher
                                                  ? Icons.done_all
                                                  : Icons.done,
                                              size: 16,
                                              // Use lighter accent so blue ticks are visible on blue bubble
                                              color: readByTeacher
                                                  ? Colors.lightBlueAccent
                                                  : Colors.white70,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemCount: docs.length,
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            minimum: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: ValueListenableBuilder<bool>(
                valueListenable: _isRecording,
                builder: (context, isRecording, _) {
                  if (isRecording) {
                    // Show recording UI
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Row(
                        children: [
                          // Delete button
                          Material(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(26),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(26),
                              onTap: _stopAndDeleteRecording,
                              child: const SizedBox(
                                width: 52,
                                height: 52,
                                child: Icon(
                                  Icons.delete,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Timer
                          Expanded(
                            child: ValueListenableBuilder<int>(
                              valueListenable: _recordingDuration,
                              builder: (context, duration, _) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(25),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 12,
                                        height: 12,
                                        decoration: const BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _formatDuration(duration),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Send button
                          Material(
                            color: const Color(0xFF1362EB),
                            borderRadius: BorderRadius.circular(26),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(26),
                              onTap: _stopAndSendRecording,
                              child: const SizedBox(
                                width: 52,
                                height: 52,
                                child: Icon(
                                  Icons.send,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  // Normal input UI
                  return Row(
                    children: [
                      IconButton(
                        onPressed: () {},
                        icon: Icon(
                          Icons.add_circle_outline,
                          color: isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade700,
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Type your message...',
                            filled: true,
                            fillColor: isDark
                                ? const Color(0xFF2A2A2A)
                                : Colors.grey.shade200,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(9999),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      CircleAvatar(
                        backgroundColor: const Color(0xFF1362EB),
                        child: IconButton(
                          onPressed: _controller.text.trim().isNotEmpty
                              ? () async {
                                  final text = _controller.text.trim();
                                  if (text.isEmpty || _conversationId == null) {
                                    return;
                                  }
                                  await _chat.sendMessage(
                                    conversationId: _conversationId!,
                                    text: text,
                                    senderRole: 'parent',
                                  );
                                  _controller.clear();
                                }
                              : _startRecording,
                          icon: Icon(
                            _controller.text.trim().isNotEmpty
                                ? Icons.send
                                : Icons.mic,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
