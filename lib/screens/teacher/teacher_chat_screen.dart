import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../services/chat_service.dart';

class TeacherChatScreen extends StatefulWidget {
  final String schoolCode;
  final String teacherId;
  final String parentId;
  final String studentId;
  final String parentName;
  final String className;
  final String? section;
  final String? parentAvatarUrl;

  const TeacherChatScreen({
    super.key,
    required this.schoolCode,
    required this.teacherId,
    required this.parentId,
    required this.studentId,
    required this.parentName,
    required this.className,
    this.section,
    this.parentAvatarUrl,
  });

  @override
  State<TeacherChatScreen> createState() => _TeacherChatScreenState();
}

class _TeacherChatScreenState extends State<TeacherChatScreen> {
  final ChatService _chat = ChatService();
  final TextEditingController _controller = TextEditingController();
  String? _conversationId;
  // Track messages already scheduled for read marking to avoid re-scheduling.
  final Set<String> _scheduledReadIds = <String>{};

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
      if (senderRole != 'teacher') {
        // Incoming from parent – mark delivered immediately.
        if (data['deliveredToTeacher'] != true) {
          deliveryBatch.update(d.reference, {'deliveredToTeacher': true});
          deliveryUpdates = true;
        }
        // Schedule read marking (delayed) if not already read/scheduled.
        final id = d.id;
        if (data['readByTeacher'] != true && !_scheduledReadIds.contains(id)) {
          _scheduledReadIds.add(id);
          toMarkRead.add(d.reference);
        }
      }
    }

    if (deliveryUpdates) {
      await deliveryBatch.commit();
    }

    if (toMarkRead.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 1200), () async {
        if (!mounted || _conversationId == null) return;
        final readBatch = FirebaseFirestore.instance.batch();
        for (final ref in toMarkRead) {
          readBatch.update(ref, {'readByTeacher': true});
        }
        await readBatch.commit();
        await _chat.markAsRead(
          conversationId: _conversationId!,
          viewerRole: 'teacher',
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
    print('🔍 Teacher Chat - Building conversation ID:');
    print('  schoolCode: ${widget.schoolCode}');
    print('  teacherId: ${widget.teacherId}');
    print('  parentId: ${widget.parentId}');
    print('  studentId: ${widget.studentId}');

    final id = await _chat.ensureConversation(
      schoolCode: widget.schoolCode,
      teacherId: widget.teacherId,
      parentId: widget.parentId,
      studentId: widget.studentId,
      studentName: widget.parentName, // not used by teacher, placeholder
      className: widget.className,
      section: widget.section,
    );

    print('✅ Conversation ID: $id');

    setState(() => _conversationId = id);
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
              backgroundImage: widget.parentAvatarUrl != null
                  ? NetworkImage(widget.parentAvatarUrl!)
                  : null,
              child: widget.parentAvatarUrl == null
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
                    widget.parentName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${widget.className}${widget.section != null ? ' - ${widget.section}' : ''}',
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
                      if (_conversationId != null && docs.isNotEmpty) {
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => _batchUpdateIncoming(docs),
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemBuilder: (context, index) {
                          final msg = docs[index].data();
                          final isTeacher = msg['senderRole'] == 'teacher';
                          final deliveredToParent =
                              (msg['deliveredToParent'] ?? false) as bool;
                          final readByParent =
                              (msg['readByParent'] ?? false) as bool;
                          return Align(
                            alignment: isTeacher
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 360),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: isTeacher
                                      ? const Color(0xFF1362EB)
                                      : (isDark
                                            ? const Color(0xFF2A2A2A)
                                            : Colors.grey.shade200),
                                  borderRadius: BorderRadius.circular(12)
                                      .copyWith(
                                        bottomRight: isTeacher
                                            ? const Radius.circular(4)
                                            : null,
                                        bottomLeft: !isTeacher
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
                                          color: isTeacher
                                              ? Colors.white
                                              : (isDark
                                                    ? Colors.white
                                                    : Colors.black87),
                                        ),
                                      ),
                                      if (isTeacher) ...[
                                        const SizedBox(height: 4),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              readByParent
                                                  ? Icons.done_all
                                                  : deliveredToParent
                                                  ? Icons.done_all
                                                  : Icons.done,
                                              size: 16,
                                              color: readByParent
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
              child: Row(
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
                      onPressed: () async {
                        final text = _controller.text.trim();
                        if (text.isEmpty || _conversationId == null) return;
                        await _chat.sendMessage(
                          conversationId: _conversationId!,
                          text: text,
                          senderRole: 'teacher',
                        );
                        _controller.clear();
                      },
                      icon: const Icon(Icons.send, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
