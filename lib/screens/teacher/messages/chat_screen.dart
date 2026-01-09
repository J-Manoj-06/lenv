import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
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
  final FocusNode _focusNode = FocusNode();

  late final MediaUploadService _mediaUploadService;
  // Track locally pending messages for transient single-tick state
  final Set<String> _pendingMessageIds = <String>{};

  String? _currentUserId;
  bool _isRecording = false;
  bool _isUploading = false;
  double _uploadProgress = 0;
  bool _showEmojiPicker = false;
  String? _recordingPath;
  final ValueNotifier<int> _recordingDuration = ValueNotifier<int>(0);
  double _slideOffsetX = 0;
  bool _isCancelled = false;
  late Timer _recordingTimer;

  @override
  void initState() {
    super.initState();
    _initMediaService();
    _messageController.addListener(() => setState(() {}));
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && _showEmojiPicker) {
        setState(() => _showEmojiPicker = false);
      }
    });
    _loadCurrentUser();
    _markAsRead();
  }

  void _onEmojiSelected(Emoji emoji) {
    _messageController.text += emoji.emoji;
  }

  void _onBackspacePressed() {
    final text = _messageController.text;
    if (text.isNotEmpty) {
      _messageController.text = text.substring(0, text.length - 1);
    }
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
    _focusNode.dispose();
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

  Future<void> _recordAndSendAudio() async {
    try {
      if (_recordingPath == null) return;

      // Stop recording FIRST
      if (_isRecording) {
        try {
          await _recorder.stop();
        } catch (e) {
          print('Error stopping recorder: $e');
        }

        try {
          _recordingTimer.cancel();
        } catch (e) {
          print('Timer cancel error: $e');
        }
      }

      // IMMEDIATELY update UI
      setState(() {
        _isRecording = false;
        _isUploading = true;
      });

      await _uploadFile(File(_recordingPath!));

      // Delete temp file
      try {
        final file = File(_recordingPath!);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        print('Error deleting temp file: $e');
      }

      if (mounted) {
        setState(() {
          _isUploading = false;
          _recordingPath = null;
          _recordingDuration.value = 0;
          _slideOffsetX = 0;
          _isCancelled = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _isRecording = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send audio: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteRecording() async {
    // Stop recording if active
    if (_isRecording) {
      await _recorder.stop();
      try {
        _recordingTimer.cancel();
      } catch (e) {
        print('Timer cancel error: $e');
      }
    }

    // Delete the file
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

    // Clear state
    setState(() {
      _isRecording = false;
      _recordingPath = null;
      _recordingDuration.value = 0;
      _slideOffsetX = 0;
      _isCancelled = false;
    });
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  Widget _buildRecordingOverlay() {
    if (_recordingPath == null && !_isUploading) return const SizedBox();

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        color: const Color(0xFF0B141A),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        child: SafeArea(
          top: false,
          child: _isUploading
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFF00A884),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Sending audio...',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                )
              : Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: _deleteRecording,
                    ),
                    Expanded(
                      child: Center(
                        child: ValueListenableBuilder<int>(
                          valueListenable: _recordingDuration,
                          builder: (context, duration, child) {
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (_isRecording)
                                  Container(
                                    width: 8,
                                    height: 8,
                                    margin: const EdgeInsets.only(right: 8),
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                Text(
                                  _formatDuration(duration),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send, color: Color(0xFF00A884)),
                      onPressed: _recordAndSendAudio,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

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

    setState(() {
      _isRecording = true;
      _recordingPath = path;
      _recordingDuration.value = 0;
      _slideOffsetX = 0;
      _isCancelled = false;
    });

    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _recordingDuration.value++;
    });
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

    return Stack(
      children: [
        Scaffold(
          backgroundColor: isDark
              ? const Color(0xFF130F23)
              : const Color(0xFFF6F5F8),
          appBar: _buildAppBar(theme, isDark),
          body: Column(
            children: [
              Expanded(child: _buildMessageList()),
              _buildComposer(theme, isDark),
              if (_showEmojiPicker)
                EmojiPicker(
                  onEmojiSelected: (category, emoji) => _onEmojiSelected(emoji),
                  onBackspacePressed: _onBackspacePressed,
                  config: Config(
                    height: 250,
                    checkPlatformCompatibility: false,
                    emojiViewConfig: EmojiViewConfig(
                      backgroundColor: const Color(0xFF0B141A),
                      columns: 7,
                      emojiSizeMax: 28,
                    ),
                    categoryViewConfig: CategoryViewConfig(
                      backgroundColor: const Color(0xFF0B141A),
                      iconColorSelected: const Color(0xFF00A884),
                      indicatorColor: const Color(0xFF00A884),
                    ),
                    bottomActionBarConfig: BottomActionBarConfig(
                      backgroundColor: const Color(0xFF0B141A),
                    ),
                  ),
                ),
            ],
          ),
        ),
        _buildRecordingOverlay(),
      ],
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
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: isTeacher
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Material(
              elevation: isDark ? 0 : 1,
              color: isTeacher
                  ? (isDark
                        ? theme.colorScheme.surface
                        : theme.colorScheme.surfaceContainerHighest)
                  : (isDark ? theme.colorScheme.surface : theme.cardColor),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
                bottomLeft: Radius.circular(isTeacher ? 12 : 6),
                bottomRight: Radius.circular(isTeacher ? 6 : 12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Text(
                  message.text,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 5),
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
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                    ),
                  ),
                  if (isTeacher) ...[
                    const SizedBox(width: 5),
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
      return const Icon(Icons.check, size: 13, color: Color(0xFF6B7075));
    }
    if (isRead) {
      return const Icon(
        Icons.done_all,
        size: 13,
        color: Color(0xFF64B5F6), // Subtle blue accent
      );
    }
    return Icon(Icons.done_all, size: 15, color: Colors.grey.shade500);
  }

  Widget _buildComposer(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(color: theme.scaffoldBackgroundColor),
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
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  color: theme.primaryColor,
                  minHeight: 4,
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: isDark
                          ? theme.colorScheme.surface
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.outline.withOpacity(0.5),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.sentiment_satisfied_outlined,
                            color: theme.textTheme.bodySmall?.color,
                            size: 22,
                          ),
                          padding: const EdgeInsets.all(8),
                          onPressed: () {
                            setState(() {
                              _showEmojiPicker = !_showEmojiPicker;
                            });
                            if (!_showEmojiPicker) {
                              _focusNode.requestFocus();
                            } else {
                              _focusNode.unfocus();
                            }
                          },
                        ),
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            focusNode: _focusNode,
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontSize: 15,
                              height: 1.4,
                            ),
                            decoration: InputDecoration(
                              hintText: _isRecording
                                  ? 'Recording...'
                                  : 'Message',
                              hintStyle: TextStyle(
                                color: theme.textTheme.bodySmall?.color,
                                fontSize: 15,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 10,
                              ),
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
                  icon: Icon(
                    Icons.attach_file,
                    color: theme.textTheme.bodySmall?.color,
                    size: 24,
                  ),
                  padding: const EdgeInsets.all(8),
                  onPressed: _isUploading ? null : _pickAttachmentSheet,
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () async {
                    if (_messageController.text.trim().isNotEmpty &&
                        !_isUploading) {
                      _sendMessage();
                    } else if (!_isRecording &&
                        _messageController.text.trim().isEmpty &&
                        !_isUploading) {
                      // Single tap to start recording
                      await _startRecording();
                    }
                  },
                  onHorizontalDragUpdate: (details) {
                    if (!_isRecording) return;
                    setState(() {
                      _slideOffsetX += details.delta.dx;
                      _isCancelled = _slideOffsetX < -80;
                    });
                  },
                  onHorizontalDragEnd: (details) {
                    if (!_isRecording) return;
                    if (_isCancelled) {
                      _deleteRecording();
                    }
                    setState(() {
                      _slideOffsetX = 0;
                      _isCancelled = false;
                    });
                  },
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _isRecording
                          ? theme.colorScheme.error
                          : theme.primaryColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: theme.primaryColor.withOpacity(0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(
                      _isRecording
                          ? Icons.mic
                          : (_hasText ? Icons.send_rounded : Icons.mic),
                      color: theme.colorScheme.onPrimary,
                      size: 24,
                    ),
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
