import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

    print('🔍 Parent Chat - Building conversation ID:');
    print('  schoolCode: $schoolCode');
    print('  teacherId: $teacherId');
    print('  parentId: $parentAuthUid');
    print('  studentId: $studentId');

    final id = await _chat.ensureConversation(
      schoolCode: schoolCode,
      teacherId: teacherId,
      parentId: parentAuthUid,
      studentId: studentId,
      studentName: child.name,
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
              backgroundImage: widget.teacherAvatarUrl != null
                  ? NetworkImage(widget.teacherAvatarUrl!)
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
            child: Padding(
              padding: const EdgeInsets.all(8.0),
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
                          senderRole: 'parent',
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
