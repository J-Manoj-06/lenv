import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../models/chat_message.dart';
import '../../../services/messaging_service.dart';
import '../../../providers/auth_provider.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String parentName;
  final String? parentPhotoUrl;
  final String studentName;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.parentName,
    this.parentPhotoUrl,
    required this.studentName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final MessagingService _messagingService = MessagingService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  // Track locally pending messages for transient single-tick state
  final Set<String> _pendingMessageIds = <String>{};

  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _markAsRead();
  }

  void _loadCurrentUser() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _currentUserId = authProvider.currentUser?.uid;
  }

  Future<void> _markAsRead() async {
    await _messagingService.markMessagesAsRead(
      conversationId: widget.conversationId,
      userRole: 'teacher',
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _currentUserId == null) return;

    _messageController.clear();
    final newId = await _messagingService.sendMessage(
      conversationId: widget.conversationId,
      senderId: _currentUserId!,
      senderRole: 'teacher',
      text: text,
    );
    if (newId != null) {
      setState(() {
        _pendingMessageIds.add(newId);
      });
    }

    // Scroll to bottom after sending
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF130F23)
          : const Color(0xFFF6F5F8),
      appBar: _buildAppBar(theme, isDark),
      body: Column(
        children: [
          Expanded(child: _buildMessageList()),
          _buildComposer(theme, isDark),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ThemeData theme, bool isDark) {
    return AppBar(
      backgroundColor: isDark
          ? const Color(0xFF130F23)
          : const Color(0xFFF6F5F8),
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundImage:
                widget.parentPhotoUrl != null &&
                    widget.parentPhotoUrl!.isNotEmpty
                ? NetworkImage(widget.parentPhotoUrl!)
                : null,
            child:
                widget.parentPhotoUrl == null || widget.parentPhotoUrl!.isEmpty
                ? Text(
                    widget.parentName[0].toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.parentName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  widget.studentName,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.textTheme.bodySmall?.color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.more_vert),
          onPressed: () {
            // Placeholder for more options
          },
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(color: theme.dividerColor, height: 1),
      ),
    );
  }

  Widget _buildMessageList() {
    return StreamBuilder<List<ChatMessage>>(
      stream: _messagingService.streamMessages(widget.conversationId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text('Error loading messages: ${snapshot.error}'),
          );
        }

        final messages = snapshot.data ?? [];

        // Any message IDs that appear in the stream are no longer pending
        final appearedIds = messages.map((m) => m.id).toSet();
        if (_pendingMessageIds.isNotEmpty) {
          final remove = _pendingMessageIds
              .where((id) => appearedIds.contains(id))
              .toList();
          if (remove.isNotEmpty) {
            setState(() {
              for (final id in remove) {
                _pendingMessageIds.remove(id);
              }
            });
          }
        }

        if (messages.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 64,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  'Start the conversation',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
          );
        }

        // Auto-scroll to bottom on new messages
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(
              _scrollController.position.maxScrollExtent,
            );
          }
        });

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index];
            final isTeacher = message.senderRole == 'teacher';
            return _buildMessageBubble(message, isTeacher);
          },
        );
      },
    );
  }

  Widget _buildMessageBubble(ChatMessage message, bool isTeacher) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Align(
      alignment: isTeacher ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        margin: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: isTeacher
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isTeacher
                    ? const Color(0xFF7A5CFF)
                    : (isDark ? Colors.grey.shade800 : Colors.white),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isTeacher ? 16 : 4),
                  bottomRight: Radius.circular(isTeacher ? 4 : 16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                message.text,
                style: TextStyle(
                  color: isTeacher
                      ? Colors.white
                      : theme.textTheme.bodyLarge?.color,
                  fontSize: 15,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: EdgeInsets.only(
                left: isTeacher ? 0 : 4,
                right: isTeacher ? 4 : 0,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    DateFormat('h:mm a').format(message.createdAt),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  if (isTeacher) ...[
                    const SizedBox(width: 4),
                    _buildStatusTicks(message),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusTicks(ChatMessage message) {
    // States:
    // 1. Pending local write -> single gray tick
    // 2. Delivered (in stream, not read) -> double gray ticks
    // 3. Read -> double blue ticks
    final isPending =
        _pendingMessageIds.contains(message.id) || message.isPending;
    final isRead = message.readByParent;
    if (isPending) {
      return Icon(Icons.check, size: 15, color: Colors.grey.shade500);
    }
    if (isRead) {
      return Icon(
        Icons.done_all,
        size: 15,
        color: const Color(0xFF34B7F1), // WhatsApp-like blue
      );
    }
    return Icon(Icons.done_all, size: 15, color: Colors.grey.shade500);
  }

  Widget _buildComposer(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF130F23) : const Color(0xFFF6F5F8),
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade800 : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.sentiment_satisfied_outlined,
                        color: Colors.grey.shade600,
                      ),
                      onPressed: () {
                        // Placeholder for emoji picker
                      },
                    ),
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        decoration: InputDecoration(
                          hintText: 'Type a message...',
                          hintStyle: TextStyle(color: Colors.grey.shade500),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                        ),
                        maxLines: null,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFF7A5CFF),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white),
                onPressed: _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
