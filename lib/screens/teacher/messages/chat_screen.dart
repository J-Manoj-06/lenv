import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../../models/chat_message.dart';
import '../../../services/messaging_service.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/media_upload_service.dart';
import '../../../services/cloudflare_r2_service.dart';
import '../../../services/local_cache_service.dart';
import '../../../config/cloudflare_config.dart';

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
  final AudioRecorder _recorder = AudioRecorder();

  late final MediaUploadService _mediaUploadService;
  // Track locally pending messages for transient single-tick state
  final Set<String> _pendingMessageIds = <String>{};

  String? _currentUserId;
  bool _isRecording = false;
  bool _isUploading = false;
  double _uploadProgress = 0;

  @override
  void initState() {
    super.initState();
    _initMediaService();
    _messageController.addListener(() => setState(() {}));
    _loadCurrentUser();
    _markAsRead();
  }

  void _initMediaService() {
    final r2 = CloudflareR2Service(
      accountId: CloudflareConfig.accountId,
      bucketName: CloudflareConfig.bucketName,
      accessKeyId: CloudflareConfig.accessKeyId,
      secretAccessKey: CloudflareConfig.secretAccessKey,
      r2Domain: CloudflareConfig.r2Domain,
    );

    _mediaUploadService = MediaUploadService(
      r2Service: r2,
      firestore: _messagingService.firestore,
      cacheService: LocalCacheService(),
    );
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
    _recorder.dispose();
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

  bool get _hasText => _messageController.text.trim().isNotEmpty;

  Future<void> _startRecording() async {
    if (_isRecording) return;
    if (!await _recorder.hasPermission()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission denied')),
      );
      return;
    }

    final dir = await getTemporaryDirectory();
    final path = p.join(
      dir.path,
      'rec_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: path,
    );

    setState(() => _isRecording = true);
  }

  Future<void> _stopRecordingAndSend() async {
    if (!_isRecording) return;
    final path = await _recorder.stop();
    setState(() => _isRecording = false);
    if (path == null) return;
    await _uploadFile(File(path));
  }

  Future<void> _pickAttachmentSheet() async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.insert_drive_file),
                title: const Text('Document (PDF, Word, PPT)'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickDocument();
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Gallery image'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickFile(allowImages: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.audiotrack),
                title: const Text('Audio file'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickFile(allowAudio: true);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickDocument() async {
    await _pickFile(allowDocs: true);
  }

  Future<void> _pickFile({
    bool allowImages = false,
    bool allowAudio = false,
    bool allowDocs = false,
  }) async {
    if (_currentUserId == null) return;

    final allowed = <String>[];
    if (allowImages) {
      allowed.addAll(['jpg', 'jpeg', 'png']);
    }
    if (allowAudio) {
      allowed.addAll(['mp3', 'm4a', 'wav', 'aac']);
    }
    if (allowDocs) {
      allowed.addAll(['pdf', 'doc', 'docx', 'ppt', 'pptx']);
    }

    final result = await FilePicker.platform.pickFiles(
      type: allowed.isEmpty ? FileType.any : FileType.custom,
      allowedExtensions: allowed.isEmpty ? null : allowed,
    );

    if (result == null || result.files.single.path == null) return;
    final file = File(result.files.single.path!);
    await _uploadFile(file);
  }

  Future<void> _uploadFile(File file) async {
    if (_currentUserId == null) return;
    setState(() {
      _isUploading = true;
      _uploadProgress = 0;
    });

    try {
      await _mediaUploadService.uploadMedia(
        file: file,
        conversationId: widget.conversationId,
        senderId: _currentUserId!,
        senderRole: 'teacher',
        onProgress: (progress) {
          setState(() => _uploadProgress = progress.toDouble());
        },
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('File sent')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to send: $e')));
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
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
        // Remove loading indicator - show previous data or empty state immediately
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  'Unable to load messages',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
          );
        }

        final messages = snapshot.data ?? [];

        // Any message IDs that appear in the stream are no longer pending
        // Clean up pending IDs without setState to avoid error overlay
        final appearedIds = messages.map((m) => m.id).toSet();
        if (_pendingMessageIds.isNotEmpty) {
          final remove = _pendingMessageIds
              .where((id) => appearedIds.contains(id))
              .toList();
          if (remove.isNotEmpty) {
            // Use post-frame callback to update state safely
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  for (final id in remove) {
                    _pendingMessageIds.remove(id);
                  }
                });
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
                    _formatMessageTime(message.createdAt),
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

  String _formatMessageTime(DateTime? timestamp) {
    if (timestamp == null) return '';
    try {
      final hour = timestamp.hour > 12
          ? timestamp.hour - 12
          : (timestamp.hour == 0 ? 12 : timestamp.hour);
      final minute = timestamp.minute.toString().padLeft(2, '0');
      final period = timestamp.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $period';
    } catch (e) {
      return '';
    }
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
    // WhatsApp-inspired dark bar regardless of theme for consistent look
    const barColor = Color(0xFF0B141A);
    const bubbleColor = Color(0xFF1F2C34);
    const accentColor = Color(0xFF00A884); // WhatsApp green
    final iconColor = Colors.grey.shade400;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      decoration: const BoxDecoration(
        color: barColor,
        border: Border(top: BorderSide(color: Color(0xFF131C21))),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isUploading)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: LinearProgressIndicator(
                  value: (_uploadProgress.clamp(0, 100)) / 100,
                  backgroundColor: Colors.grey.shade300,
                  color: accentColor,
                  minHeight: 4,
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: bubbleColor,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.sentiment_satisfied_outlined,
                            color: iconColor,
                            size: 26,
                          ),
                          padding: const EdgeInsets.all(8),
                          onPressed: () {},
                        ),
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            decoration: InputDecoration(
                              hintText: _isRecording
                                  ? 'Recording...'
                                  : 'Message',
                              hintStyle: TextStyle(
                                color: iconColor,
                                fontSize: 16,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 10,
                              ),
                            ),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                            enabled: !_isRecording && !_isUploading,
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
                IconButton(
                  icon: Icon(Icons.attach_file, color: iconColor, size: 26),
                  padding: const EdgeInsets.all(8),
                  onPressed: _isUploading ? null : _pickAttachmentSheet,
                ),
                const SizedBox(width: 8),
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _isRecording ? Colors.redAccent : accentColor,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      _isRecording
                          ? Icons.stop
                          : (_hasText ? Icons.send_rounded : Icons.mic),
                      color: Colors.white,
                      size: 24,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: _isUploading
                        ? null
                        : () {
                            if (_isRecording) {
                              _stopRecordingAndSend();
                            } else if (_hasText) {
                              _sendMessage();
                            } else {
                              _startRecording();
                            }
                          },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
