import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import '../../providers/auth_provider.dart';
import '../../services/cloudflare_r2_service.dart';
import '../../config/cloudflare_config.dart';
import '../../services/media_upload_service.dart';
import '../../services/local_cache_service.dart';
import '../../services/background_upload_service.dart';
import '../create_poll_screen.dart';
import '../../utils/message_scroll_highlight_mixin.dart';
import '../../repositories/local_message_repository.dart';
import '../../services/firebase_message_sync_service.dart';
import 'offline_message_search_page.dart';
import '../../core/constants/app_colors.dart';

/// Configuration for attachment options based on user role
class AttachmentConfig {
  final bool camera;
  final bool image;
  final bool document;
  final bool audio;
  final bool poll;
  final bool mindmap;

  const AttachmentConfig({
    this.camera = true,
    this.image = true,
    this.document = true,
    this.audio = true,
    this.poll = true,
    this.mindmap = false,
  });

  /// Default config for all roles
  static const standard = AttachmentConfig();

  /// Config for teachers with mindmap enabled
  static const teacher = AttachmentConfig(mindmap: true);

  /// Config with restricted features
  static const restricted = AttachmentConfig(
    camera: false,
    image: false,
    document: true,
    audio: true,
    poll: false,
    mindmap: false,
  );
}

/// Base Group Chat Page - Unified implementation for all group chats
/// This replaces: StaffRoomChatPage, GroupChatPage, ParentGroupChatPage
///
/// Features:
/// - Background uploads with progress tracking
/// - Offline-first messaging with caching
/// - PDF downloading and viewing
/// - Multi-image messages
/// - Audio recording and playback
/// - Polls
/// - Role-specific attachment options (e.g., mindmap for teachers)
/// - Message search
/// - Message deletion
///
/// Usage:
/// ```dart
/// BaseGroupChatPage(
///   chatId: 'chat_123',
///   chatName: 'Mathematics - Class 10A',
///   chatType: 'group',
///   currentUserRole: 'teacher',
///   attachmentConfig: AttachmentConfig.teacher, // Teacher-specific features
/// )
/// ```
class BaseGroupChatPage extends StatefulWidget {
  final String chatId;
  final String chatName;
  final String chatType; // 'group', 'staffroom', 'parent-teacher'
  final String currentUserRole; // 'teacher', 'student', 'parent', 'principal'
  final String? subtitle; // Optional subtitle (e.g., teacher name)
  final Color? themeColor; // Optional custom theme color
  final AttachmentConfig attachmentConfig;
  final Map<String, dynamic>? metadata; // Optional additional data

  const BaseGroupChatPage({
    super.key,
    required this.chatId,
    required this.chatName,
    required this.chatType,
    required this.currentUserRole,
    this.subtitle,
    this.themeColor,
    this.attachmentConfig = AttachmentConfig.standard,
    this.metadata,
  });

  @override
  State<BaseGroupChatPage> createState() => _BaseGroupChatPageState();
}

class _BaseGroupChatPageState extends State<BaseGroupChatPage>
    with MessageScrollAndHighlightMixin, WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  late final MediaUploadService _mediaUploadService;
  final ValueNotifier<bool> _isUploading = ValueNotifier<bool>(false);

  // OFFLINE-FIRST SERVICES
  late final LocalMessageRepository _localRepo;
  late final FirebaseMessageSyncService _syncService;

  // Recording variables
  final AudioRecorder _audioRecorder = AudioRecorder();
  final ValueNotifier<bool> _isRecording = ValueNotifier<bool>(false);
  String? _recordingPath;
  final ValueNotifier<int> _recordingDuration = ValueNotifier<int>(0);
  Timer? _recordingTimer;

  // Emoji picker
  bool _showEmojiPicker = false;

  // Pending uploads tracking
  final List<Map<String, dynamic>> _pendingMessages = [];
  final Set<String> _uploadingMessageIds = {};
  final Map<String, double> _pendingUploadProgress = {};
  final Map<String, String> _localFilePaths = {};

  // Selection mode for delete
  final ValueNotifier<Set<String>> _selectedMessages = ValueNotifier({});
  final ValueNotifier<bool> _isSelectionMode = ValueNotifier(false);

  // User info
  String? _userName;
  String? _userId;

  // Theme color
  late Color _accentColor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Set theme color
    _accentColor = widget.themeColor ?? _getDefaultThemeColor();

    // Initialize media upload service
    final r2Service = CloudflareR2Service(
      accountId: CloudflareConfig.accountId,
      bucketName: CloudflareConfig.bucketName,
      accessKeyId: CloudflareConfig.accessKeyId,
      secretAccessKey: CloudflareConfig.secretAccessKey,
      r2Domain: CloudflareConfig.r2Domain,
    );

    _mediaUploadService = MediaUploadService(
      r2Service: r2Service,
      firestore: FirebaseFirestore.instance,
      cacheService: LocalCacheService(),
    );

    // Initialize offline-first services
    _initOfflineFirst();

    // Load user data
    _loadUserData();

    // Bridge background upload progress to UI
    BackgroundUploadService().onUploadProgress = _handleUploadProgress;

    // Focus listener
    _messageFocusNode.addListener(() {
      if (_messageFocusNode.hasFocus && _showEmojiPicker) {
        setState(() => _showEmojiPicker = false);
      }
    });
  }

  void _initOfflineFirst() async {
    _localRepo = LocalMessageRepository();
    _syncService = FirebaseMessageSyncService(_localRepo);

    await _localRepo.initialize();

    print('🔥 BaseGroupChat - Initializing offline-first');
    print('   Chat ID: ${widget.chatId}');
    print('   Chat Type: ${widget.chatType}');

    // Load from cache first
    final cachedMessages = await _localRepo.getMessagesForChat(
      widget.chatId,
      limit: 50,
    );

    if (cachedMessages.isEmpty) {
      print('📥 No cache - fetching initial messages...');
      await _syncService.initialSyncForChat(
        chatId: widget.chatId,
        chatType: widget.chatType,
        limit: 50,
      );
    } else {
      print('✅ Loaded ${cachedMessages.length} messages from cache');
      _syncService.syncNewMessages(
        chatId: widget.chatId,
        chatType: widget.chatType,
        lastTimestamp: cachedMessages.first.timestamp,
      );
    }

    // Start real-time sync
    if (_userId != null) {
      await _syncService.startSyncForChat(
        chatId: widget.chatId,
        chatType: widget.chatType,
        userId: _userId!,
      );
    }
  }

  Future<void> _loadUserData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;

    if (currentUser == null) return;

    setState(() {
      _userId = currentUser.uid;
      _userName = currentUser.name.isNotEmpty
          ? currentUser.name
          : currentUser.email.split('@').first;
    });
  }

  Color _getDefaultThemeColor() {
    switch (widget.currentUserRole.toLowerCase()) {
      case 'teacher':
        return AppColors.teacherColor;
      case 'student':
        return AppColors.studentColor;
      case 'parent':
        return AppColors.parentColor;
      case 'principal':
      case 'institute':
        return AppColors.instituteColor;
      default:
        return AppColors.insightsTeal;
    }
  }

  void _handleUploadProgress(
    String messageId,
    bool isUploading,
    double progress,
  ) {
    if (!mounted) return;
    setState(() {
      if (isUploading) {
        _pendingUploadProgress[messageId] = progress;
      } else {
        _pendingUploadProgress.remove(messageId);
        _removeCompletedUpload(messageId);
      }
    });
  }

  void _removeCompletedUpload(String messageId) {
    // Remove from pending messages after upload completes
    _pendingMessages.removeWhere((msg) => msg['messageId'] == messageId);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _messageFocusNode.dispose();
    scrollController.dispose();
    _audioRecorder.dispose();
    _isRecording.dispose();
    _isUploading.dispose();
    _recordingDuration.dispose();
    _selectedMessages.dispose();
    _isSelectionMode.dispose();
    _recordingTimer?.cancel();
    super.dispose();
  }

  void _showAttachmentOptions() {
    showModernAttachmentSheet(
      context,
      onCameraTap: widget.attachmentConfig.camera ? _pickCamera : null,
      onImageTap: widget.attachmentConfig.image ? _pickImages : null,
      onDocumentTap: widget.attachmentConfig.document ? _pickDocument : null,
      onAudioTap: widget.attachmentConfig.audio ? _pickAudio : null,
      onPollTap: widget.attachmentConfig.poll ? _navigateToCreatePoll : null,
      onMindmapTap: widget.attachmentConfig.mindmap
          ? _navigateToCreateMindmap
          : null,
      cameraEnabled: widget.attachmentConfig.camera,
      imageEnabled: widget.attachmentConfig.image,
      documentEnabled: widget.attachmentConfig.document,
      audioEnabled: widget.attachmentConfig.audio,
      pollEnabled: widget.attachmentConfig.poll,
      mindmapEnabled: widget.attachmentConfig.mindmap,
      color: _accentColor,
    );
  }

  // Attachment handlers (to be implemented with actual upload logic)
  void _pickCamera() async {
    // TODO: Implement camera picker
    print('📷 Camera picker');
  }

  void _pickImages() async {
    // TODO: Implement image picker
    print('🖼️ Image picker');
  }

  void _pickDocument() async {
    // TODO: Implement document picker
    print('📄 Document picker');
  }

  void _pickAudio() async {
    // TODO: Implement audio picker
    print('🎵 Audio picker');
  }

  void _navigateToCreatePoll() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            CreatePollScreen(chatId: widget.chatId, chatType: widget.chatType),
      ),
    );
  }

  void _navigateToCreateMindmap() {
    // TODO: Implement mindmap creation navigation
    print('🧠 Mindmap creator');
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _userId == null || _userName == null) return;

    _messageController.clear();

    // TODO: Implement message sending logic
    print('💬 Sending message: $text');
  }

  Future<void> _startRecording() async {
    final hasPermission = await _audioRecorder.hasPermission();
    if (!hasPermission) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission denied')),
      );
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final path =
        '${tempDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _audioRecorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );

    _isRecording.value = true;
    _recordingPath = path;
    _recordingDuration.value = 0;

    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _recordingDuration.value++;
    });
  }

  Future<void> _stopAndSendRecording() async {
    if (!_isRecording.value) return;

    await _audioRecorder.stop();
    _recordingTimer?.cancel();
    _isRecording.value = false;

    // TODO: Implement audio upload logic
    print('🎤 Sending recording: $_recordingPath');

    _recordingPath = null;
    _recordingDuration.value = 0;
  }

  Future<void> _cancelRecording() async {
    if (!_isRecording.value) return;

    await _audioRecorder.stop();
    _recordingTimer?.cancel();

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

    _isRecording.value = false;
    _recordingPath = null;
    _recordingDuration.value = 0;
  }

  void _openSearch() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => OfflineMessageSearchPage(
              chatId: widget.chatId,
              chatType: widget.chatType,
            ),
          ),
        )
        .then((selectedMessageId) async {
          if (selectedMessageId != null) {
            await scrollToMessage(selectedMessageId, [
              {'id': selectedMessageId},
            ]);
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : theme.scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: _buildAppBar(theme),
      body: Column(
        children: [
          Expanded(child: _buildMessageList()),
          _buildInputArea(theme, isDark),
          if (_showEmojiPicker) _buildEmojiPicker(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ThemeData theme) {
    return AppBar(
      backgroundColor: theme.brightness == Brightness.dark
          ? Colors.black
          : theme.scaffoldBackgroundColor,
      elevation: 0,
      leading: IconButton(
        icon: Icon(
          _isSelectionMode.value ? Icons.close : Icons.arrow_back_ios_new,
          color: theme.iconTheme.color,
          size: 20,
        ),
        onPressed: () {
          if (_isSelectionMode.value) {
            _isSelectionMode.value = false;
            _selectedMessages.value = {};
          } else {
            Navigator.pop(context);
          }
        },
      ),
      title: ValueListenableBuilder<bool>(
        valueListenable: _isSelectionMode,
        builder: (context, selectionMode, _) {
          if (selectionMode) {
            return ValueListenableBuilder<Set<String>>(
              valueListenable: _selectedMessages,
              builder: (context, selected, _) {
                return Text(
                  '${selected.length} selected',
                  style: TextStyle(
                    color: theme.textTheme.bodyLarge?.color,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                );
              },
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.chatName,
                style: TextStyle(
                  color: theme.textTheme.bodyLarge?.color,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (widget.subtitle != null)
                Text(
                  widget.subtitle!,
                  style: TextStyle(
                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
                    fontSize: 12,
                  ),
                ),
            ],
          );
        },
      ),
      actions: [
        ValueListenableBuilder<bool>(
          valueListenable: _isSelectionMode,
          builder: (context, selectionMode, _) {
            if (selectionMode) {
              return ValueListenableBuilder<Set<String>>(
                valueListenable: _selectedMessages,
                builder: (context, selected, _) {
                  return IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: selected.isEmpty
                        ? null
                        : _deleteSelectedMessages,
                  );
                },
              );
            }

            return Row(
              children: [
                IconButton(
                  icon: Icon(Icons.search, color: theme.iconTheme.color),
                  onPressed: _openSearch,
                ),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: theme.iconTheme.color),
                  onSelected: (value) {
                    // TODO: Handle menu actions
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'info',
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 20),
                          SizedBox(width: 12),
                          Text('Group Info'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildMessageList() {
    // TODO: Implement actual message list with offline-first support
    return const Center(child: Text('Messages will appear here'));
  }

  Widget _buildInputArea(ThemeData theme, bool isDark) {
    final backgroundColor = isDark
        ? const Color(0xFF0D0E10)
        : const Color(0xFFF5F5F5);
    final inputFieldColor = isDark ? const Color(0xFF1E2024) : Colors.white;
    final textColor = isDark
        ? const Color(0xFFE8E8E8)
        : const Color(0xFF000000);
    final hintColor = isDark
        ? const Color(0xFF6B6B6B)
        : const Color(0xFF999999);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: isDark
            ? Border(
                top: BorderSide(
                  color: Colors.white.withOpacity(0.05),
                  width: 0.5,
                ),
              )
            : null,
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                decoration: BoxDecoration(
                  color: inputFieldColor,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: isDark
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _showEmojiPicker = !_showEmojiPicker;
                          });
                          if (!_showEmojiPicker) {
                            _messageFocusNode.requestFocus();
                          } else {
                            _messageFocusNode.unfocus();
                          }
                        },
                        child: Icon(
                          _showEmojiPicker
                              ? Icons.keyboard_outlined
                              : Icons.emoji_emotions_outlined,
                          color: _accentColor,
                          size: 23,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        focusNode: _messageFocusNode,
                        cursorColor: _accentColor,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 15,
                          height: 1.4,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Message',
                          hintStyle: TextStyle(color: hintColor, fontSize: 15),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 10,
                          ),
                        ),
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _isUploading,
                        builder: (context, uploading, _) {
                          return GestureDetector(
                            onTap: uploading ? null : _showAttachmentOptions,
                            child: Icon(
                              Icons.attach_file_rounded,
                              color: uploading ? hintColor : _accentColor,
                              size: 22,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _messageController,
              builder: (context, value, child) {
                final hasText = value.text.trim().isNotEmpty;
                return ValueListenableBuilder<bool>(
                  valueListenable: _isRecording,
                  builder: (context, recording, _) {
                    return GestureDetector(
                      onTap: () async {
                        if (recording) {
                          await _stopAndSendRecording();
                        } else if (hasText) {
                          await _sendMessage();
                        } else {
                          await _startRecording();
                        }
                      },
                      onLongPress: !recording && !hasText
                          ? _startRecording
                          : null,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: recording
                              ? theme.colorScheme.error
                              : _accentColor,
                          shape: BoxShape.circle,
                          boxShadow: isDark
                              ? [
                                  BoxShadow(
                                    color:
                                        (recording
                                                ? theme.colorScheme.error
                                                : _accentColor)
                                            .withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : [
                                  BoxShadow(
                                    color:
                                        (recording
                                                ? theme.colorScheme.error
                                                : _accentColor)
                                            .withOpacity(0.25),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                        ),
                        child: Icon(
                          recording
                              ? Icons.stop
                              : (hasText ? Icons.send_rounded : Icons.mic),
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmojiPicker() {
    return EmojiPicker(
      onEmojiSelected: (category, emoji) {
        _messageController.text += emoji.emoji;
      },
      onBackspacePressed: () {
        final text = _messageController.text;
        if (text.isNotEmpty) {
          _messageController.text = text.substring(0, text.length - 1);
        }
      },
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
          iconColorSelected: _accentColor,
          indicatorColor: _accentColor,
        ),
        bottomActionBarConfig: BottomActionBarConfig(
          backgroundColor: const Color(0xFF0B141A),
        ),
      ),
    );
  }

  Future<void> _deleteSelectedMessages() async {
    // TODO: Implement message deletion
    print('🗑️ Deleting ${_selectedMessages.value.length} messages');
    _isSelectionMode.value = false;
    _selectedMessages.value = {};
  }
}

/// Helper function to show the modern attachment sheet
void showModernAttachmentSheet(
  BuildContext context, {
  VoidCallback? onCameraTap,
  VoidCallback? onImageTap,
  VoidCallback? onDocumentTap,
  VoidCallback? onAudioTap,
  VoidCallback? onPollTap,
  VoidCallback? onMindmapTap,
  bool cameraEnabled = true,
  bool imageEnabled = true,
  bool documentEnabled = true,
  bool audioEnabled = true,
  bool pollEnabled = true,
  bool mindmapEnabled = false,
  Color color = const Color(0xFF7C3AED),
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Wrap(
          children: [
            if (cameraEnabled && onCameraTap != null)
              _AttachmentOption(
                icon: Icons.camera_alt,
                label: 'Camera',
                color: color,
                onTap: () {
                  Navigator.pop(context);
                  onCameraTap();
                },
              ),
            if (imageEnabled && onImageTap != null)
              _AttachmentOption(
                icon: Icons.image,
                label: 'Gallery',
                color: color,
                onTap: () {
                  Navigator.pop(context);
                  onImageTap();
                },
              ),
            if (documentEnabled && onDocumentTap != null)
              _AttachmentOption(
                icon: Icons.insert_drive_file,
                label: 'Document',
                color: color,
                onTap: () {
                  Navigator.pop(context);
                  onDocumentTap();
                },
              ),
            if (audioEnabled && onAudioTap != null)
              _AttachmentOption(
                icon: Icons.audiotrack,
                label: 'Audio',
                color: color,
                onTap: () {
                  Navigator.pop(context);
                  onAudioTap();
                },
              ),
            if (pollEnabled && onPollTap != null)
              _AttachmentOption(
                icon: Icons.poll,
                label: 'Poll',
                color: color,
                onTap: () {
                  Navigator.pop(context);
                  onPollTap();
                },
              ),
            if (mindmapEnabled && onMindmapTap != null)
              _AttachmentOption(
                icon: Icons.account_tree,
                label: 'Mind Map',
                color: color,
                onTap: () {
                  Navigator.pop(context);
                  onMindmapTap();
                },
              ),
          ],
        ),
      ),
    ),
  );
}

class _AttachmentOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _AttachmentOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: (MediaQuery.of(context).size.width - 60) / 3,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).textTheme.bodyMedium?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
