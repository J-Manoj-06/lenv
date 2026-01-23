import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:dio/dio.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/link_utils.dart';
import '../../models/group_chat_message.dart';
import '../../models/media_metadata.dart';
import '../../services/group_messaging_service.dart';
import '../../services/media_upload_service.dart';
import '../../services/background_upload_service.dart';
import '../../services/whatsapp_media_upload_service.dart';
import '../../services/cloudflare_r2_service.dart';
import '../../services/local_cache_service.dart';
import '../../config/cloudflare_config.dart';
import '../../providers/auth_provider.dart';
import '../../providers/unread_count_provider.dart';
import '../../widgets/media_preview_card.dart';
import '../../widgets/modern_attachment_sheet.dart';
import '../../widgets/multi_image_message_bubble.dart';

class GroupChatPage extends StatefulWidget {
  final String classId;
  final String subjectId;
  final String subjectName;
  final String teacherName;
  final String icon;
  final String? className;
  final String? section;

  const GroupChatPage({
    super.key,
    required this.classId,
    required this.subjectId,
    required this.subjectName,
    required this.teacherName,
    required this.icon,
    this.className,
    this.section,
  });

  @override
  State<GroupChatPage> createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage> {
  final GroupMessagingService _messagingService = GroupMessagingService();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String? _lastTopMessageId;
  final FocusNode _messageFocusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();
  late final MediaUploadService _mediaUploadService;
  bool _isUploading = false;
  bool _isRecording = false;
  String _uploadingMediaType =
      ''; // Track what type of media is uploading: 'image', 'pdf', 'audio'
  bool _showEmojiPicker = false;
  String? _recordingPath;
  final ValueNotifier<int> _recordingDuration = ValueNotifier<int>(0);
  Timer? _recordingTimer;
  double _slideOffsetX = 0;
  bool _isCancelled = false;
  final Set<String> _selectedMessages = {};
  bool _isSelectionMode = false;
  // Optimistic UI: pending messages added locally before Firestore confirms
  final List<GroupChatMessage> _pendingMessages = [];
  // Track upload progress per pending messageId
  final Map<String, double> _pendingUploadProgress = {};
  // Track which messages are currently uploading
  final Set<String> _uploadingMessageIds = {};
  // Local media paths for the sender (so they view from disk, no re-download)
  final Map<String, String> _localSenderMediaPaths = {};
  // Map every rendered message to a GlobalKey for precise scrolling/highlight
  final Map<String, GlobalKey> _messageKeys = {};
  Set<String> _visibleMessageIds = {};
  String? _highlightMessageId;
  Timer? _highlightResetTimer;
  // Stream lastReadAt dynamically for real-time splitter updates
  late Stream<Timestamp?> _lastReadAtStream;
  bool _initializedFirstSnapshot = false;
  String? _lastIncomingTopMessageId;
  DateTime _lastSoundPlayedAt = DateTime.fromMillisecondsSinceEpoch(0);
  final Duration _soundDebounce = const Duration(milliseconds: 500);
  // Show unread split inside chat to aid context (user requested)
  final bool _showUnreadDivider = true;
  UnreadCountProvider? _unreadRef;

  // Cache keys for pending messages persistence
  late String _pendingMessagesCacheKey;
  // ignore: unused_field
  late String _uploadProgressCacheKey;
  // ignore: unused_field
  late WhatsAppMediaUploadService _whatsappMediaUpload;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cache provider reference to avoid context lookup in dispose
    _unreadRef ??= Provider.of<UnreadCountProvider>(context, listen: false);
  }

  // ===== Pending messages persistence =====
  void _restorePendingMessagesFromCacheSync() {
    try {
      final cacheService = LocalCacheService();

      // Restore pending messages from conversation cache
      final cachedMessages = cacheService.getCachedMessages(
        _pendingMessagesCacheKey,
      );

      debugPrint(
        '\n📦 CACHE RESTORE: Found ${cachedMessages?.length ?? 0} cached messages',
      );

      if (cachedMessages != null && cachedMessages.isNotEmpty) {
        _pendingMessages.clear();
        for (final msgMap in cachedMessages) {
          try {
            // Use fromFirestore to deserialize from cached JSON
            final msg = GroupChatMessage.fromFirestore(
              msgMap.cast<String, dynamic>(),
              msgMap['id'] as String? ?? 'pending:unknown',
            );
            _pendingMessages.add(msg);
            debugPrint('   ✅ Restored pending: ${msg.id}');

            // Restore upload progress for each media item
            if (msg.multipleMedia != null) {
              for (final media in msg.multipleMedia!) {
                _uploadingMessageIds.add(media.messageId);
                _pendingUploadProgress[media.messageId] = 0.0;
                // Restore local paths
                if (media.localPath != null && media.localPath!.isNotEmpty) {
                  _localSenderMediaPaths[media.messageId] = media.localPath!;
                }
              }
            }
            if (msg.mediaMetadata != null) {
              _uploadingMessageIds.add(msg.mediaMetadata!.messageId);
              _pendingUploadProgress[msg.mediaMetadata!.messageId] = 0.0;
              // Restore local path
              if (msg.mediaMetadata!.localPath != null &&
                  msg.mediaMetadata!.localPath!.isNotEmpty) {
                _localSenderMediaPaths[msg.mediaMetadata!.messageId] =
                    msg.mediaMetadata!.localPath!;
              }
            }
          } catch (e) {
            debugPrint('   ❌ Failed to restore message: $e');
          }
        }
        debugPrint(
          '📦 CACHE RESTORE COMPLETE: ${_pendingMessages.length} messages restored\n',
        );
      }
    } catch (e) {
      debugPrint('❌ Cache restoration failed: $e');
    }
  }

  /// Cache pending messages SYNCHRONOUSLY to ensure data persists even on immediate navigation
  void _cachePendingMessages() {
    try {
      final cacheService = LocalCacheService();

      if (_pendingMessages.isNotEmpty) {
        debugPrint(
          '💾 CACHING ${_pendingMessages.length} pending messages SYNCHRONOUSLY',
        );
        final messages = _pendingMessages.map((m) {
          final firestore = m.toFirestore();
          firestore['id'] = m.id;
          // Preserve device-local paths in cache so thumbnails/audio remain
          if (m.mediaMetadata?.localPath != null) {
            firestore['mediaMetadata'] ??= {};
            (firestore['mediaMetadata'] as Map<String, dynamic>)['localPath'] =
                m.mediaMetadata!.localPath;
          }
          if (m.multipleMedia != null) {
            final list = firestore['multipleMedia'] as List<dynamic>?;
            if (list != null) {
              for (int i = 0; i < list.length; i++) {
                final original = m.multipleMedia![i];
                if (original.localPath != null) {
                  (list[i] as Map<String, dynamic>)['localPath'] =
                      original.localPath;
                }
              }
            }
          }
          return firestore;
        }).toList();
        // Use synchronous write to guarantee completion
        cacheService.cacheMessagesSync(
          conversationId: _pendingMessagesCacheKey,
          messages: messages,
        );
        debugPrint('✅ SYNC Cache saved immediately');
      } else {
        debugPrint('🗑️ Clearing cache (no pending messages)');
        cacheService.clearCacheSync(_pendingMessagesCacheKey);
      }
    } catch (e) {
      debugPrint('❌ Cache operation failed: $e');
    }
  }

  /// Rebuild pending message placeholders for any in-flight uploads that
  /// were already queued before this screen mounted. Without this, uploads
  /// that continue in the background can lose their optimistic bubbles and
  /// appear to "disappear" until Firestore confirms.
  Future<void> _hydrateInFlightUploads() async {
    try {
      final uploadService = BackgroundUploadService();
      final conversationId = '${widget.classId}_${widget.subjectId}';

      final uploads = uploadService.uploads.where((u) {
        final sameConversation = u.conversationId == conversationId;
        // Keep completed uploads too so pending bubbles persist until Firestore
        final stillRelevant =
            u.status != UploadStatus.failed &&
            u.status != UploadStatus.cancelled;
        return sameConversation && stillRelevant;
      }).toList();

      if (uploads.isEmpty) return;

      // Group multi-image uploads using groupId so they render as one bubble
      final Map<String, List<PendingUpload>> grouped = {};
      for (final upload in uploads) {
        final groupKey = upload.groupId ?? upload.id;
        grouped.putIfAbsent(groupKey, () => []).add(upload);
      }

      setState(() {
        grouped.forEach((groupKey, items) {
          // Avoid duplicating if cache already restored this pending message
          final pendingId = 'pending:$groupKey';
          if (_pendingMessages.any((m) => m.id == pendingId)) return;

          final mediaList = <MediaMetadata>[];

          for (final upload in items) {
            final file = File(upload.filePath);
            final fileSize = file.existsSync() ? file.lengthSync() : null;

            mediaList.add(
              MediaMetadata(
                messageId: upload.id,
                r2Key: 'pending/${upload.id}',
                publicUrl: '',
                thumbnail: file.existsSync() ? file.path : '',
                localPath: file.path,
                expiresAt: DateTime.now().add(const Duration(days: 30)),
                uploadedAt: DateTime.now(),
                originalFileName: upload.fileName,
                fileSize: fileSize,
                mimeType: upload.mimeType,
              ),
            );

            _uploadingMessageIds.add(upload.id);
            _pendingUploadProgress[upload.id] = upload.progress;
            if (file.path.isNotEmpty) {
              _localSenderMediaPaths[upload.id] = file.path;
            }
          }

          if (mediaList.isEmpty) return;

          final first = items.first;
          final pendingMessage = GroupChatMessage(
            id: pendingId,
            senderId: first.senderId,
            senderName: first.senderName ?? 'You',
            message: '',
            timestamp: DateTime.now().millisecondsSinceEpoch,
            mediaMetadata: mediaList.first,
            multipleMedia: mediaList.length > 1 ? mediaList : null,
          );

          _pendingMessages.insert(0, pendingMessage);
        });
      });

      _cachePendingMessages();
    } catch (e) {
      debugPrint('❌ Hydrate pending uploads failed: $e');
    }
  }

  // ===== Date helpers for day separators =====
  String _formatDayLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final d = DateTime(dt.year, dt.month, dt.day);
    if (d == today) return 'Today';
    if (d == yesterday) return 'Yesterday';
    return DateFormat('MMM dd, yyyy').format(dt);
  }

  Widget _buildDayDivider(DateTime dt) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF262A30) : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(14),
            border: isDark
                ? null
                : Border.all(color: Colors.grey.shade300, width: 1),
          ),
          child: Text(
            _formatDayLabel(dt),
            style: TextStyle(
              color: isDark ? const Color(0xFF9E9E9E) : Colors.grey.shade700,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnreadDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: const [
          Expanded(child: Divider(color: Color(0x339E9E9E), thickness: 1)),
          SizedBox(width: 8),
          Text(
            'Unread messages',
            style: TextStyle(
              color: Color(0xFFFF8800),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(width: 8),
          Expanded(child: Divider(color: Color(0x339E9E9E), thickness: 1)),
        ],
      ),
    );
  }

  Widget _buildMessageList(
    List<GroupChatMessage> messages,
    int lastReadMs,
    String? currentUserId, {
    bool showDivider = true,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Track which messages are currently visible so we can scroll/highlight safely
    final currentIds = messages.map((m) => m.id).toSet();
    _visibleMessageIds = currentIds;
    _messageKeys.removeWhere((key, _) => !currentIds.contains(key));

    // Pre-compute a single divider position: the first read message after unread ones
    // BUT: only show divider if there are unread messages from OTHER users (not self)
    int? unreadDividerIndex;
    bool hasUnread = false;
    bool hasRead = false;
    bool hasUnreadFromOthers = false;

    for (int i = 0; i < messages.length; i++) {
      final isUnread = messages[i].timestamp > lastReadMs;
      final isFromOthers = messages[i].senderId != currentUserId;

      hasUnread = hasUnread || isUnread;
      hasRead = hasRead || !isUnread;

      // Track if there are any unread messages from other users
      if (isUnread && isFromOthers) {
        hasUnreadFromOthers = true;
      }

      if (i > 0) {
        final prevUnread = messages[i - 1].timestamp > lastReadMs;
        if (prevUnread && !isUnread && unreadDividerIndex == null) {
          unreadDividerIndex = i;
        }
      }
    }
    // If both read and unread exist but no boundary found (edge cases), place at last item
    if (unreadDividerIndex == null && hasUnread && hasRead) {
      unreadDividerIndex = messages.length - 1;
    }

    // Only show divider if there are unread messages from OTHER users
    if (!hasUnreadFromOthers) {
      unreadDividerIndex = null;
    }

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.all(16),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        // Skip deleted messages - don't display them at all
        if (message.isDeleted) {
          return const SizedBox.shrink();
        }
        final isMe = message.senderId == currentUserId;
        final isSelected = _selectedMessages.contains(message.id);
        final isPending =
            message.id.startsWith('pending:') ||
            (message.mediaMetadata?.r2Key.startsWith('pending/') ?? false);
        final uploadProgress = isPending
            ? _pendingUploadProgress[message.mediaMetadata?.messageId]
            : null;

        // Show a day divider above the first message of each day.
        // List is reverse + sorted desc, so the "next" item (index+1)
        // is the previous day in the vertical order.
        final currentDate = DateTime.fromMillisecondsSinceEpoch(
          message.timestamp,
        );
        final isOldest = index == messages.length - 1;
        final nextDate = isOldest
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                messages[index + 1].timestamp,
              );
        final showDayDivider =
            isOldest ||
            _formatDayLabel(currentDate) != _formatDayLabel(nextDate!);

        if (_showUnreadDivider && showDivider && unreadDividerIndex == index) {}

        final msgKey = _messageKeys.putIfAbsent(message.id, () => GlobalKey());
        final isHighlighted = _highlightMessageId == message.id;
        final highlightColor = isDark
            ? theme.colorScheme.primary.withOpacity(0.16)
            : theme.colorScheme.primary.withOpacity(0.12);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_showUnreadDivider &&
                showDivider &&
                unreadDividerIndex == index)
              _buildUnreadDivider(),
            if (showDayDivider) _buildDayDivider(currentDate),
            TweenAnimationBuilder<double>(
              key: msgKey,
              tween: Tween<double>(begin: 0, end: isHighlighted ? 1 : 0),
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeInOut,
              builder: (context, value, child) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    color: Color.lerp(
                      Colors.transparent,
                      highlightColor,
                      value,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: child,
                );
              },
              child: GestureDetector(
                key: ValueKey('msg-${message.id}'),
                onLongPress: isMe
                    ? () {
                        setState(() {
                          _isSelectionMode = true;
                          _selectedMessages.add(message.id);
                        });
                      }
                    : null,
                onTap: _isSelectionMode && isMe
                    ? () {
                        setState(() {
                          if (isSelected) {
                            _selectedMessages.remove(message.id);
                            if (_selectedMessages.isEmpty) {
                              _isSelectionMode = false;
                            }
                          } else {
                            _selectedMessages.add(message.id);
                          }
                        });
                      }
                    : null,
                child: Row(
                  children: [
                    Expanded(
                      child: _MessageBubble(
                        message: message,
                        isMe: isMe,
                        uploading: isPending,
                        uploadProgress: uploadProgress,
                        localSenderMediaPaths: _localSenderMediaPaths,
                        selectionMode: _isSelectionMode,
                        uploadingMessageIds: _uploadingMessageIds,
                        pendingUploadProgress: _pendingUploadProgress,
                        key: ValueKey('bubble-${message.id}'),
                      ),
                    ),
                    if (_isSelectionMode && isMe)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Icon(
                          isSelected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: isSelected
                              ? const Color(0xFFFFA929)
                              : Colors.grey,
                          size: 24,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // Extract R2 key from full URL
  // https://files.lenv1.tech/media/1234567/file.pdf → media/1234567/file.pdf
  String _extractR2Key(String url) {
    final uri = Uri.parse(url);
    // Remove leading slash if present
    final path = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
    return path;
  }

  @override
  void initState() {
    super.initState();

    // Initialize cache keys for this chat session
    _pendingMessagesCacheKey =
        'pending_msgs_${widget.classId}_${widget.subjectId}';
    _uploadProgressCacheKey =
        'upload_progress_${widget.classId}_${widget.subjectId}';

    // Restore pending messages and progress from cache SYNCHRONOUSLY
    // This must complete before StreamBuilder starts to prevent messages from disappearing
    _restorePendingMessagesFromCacheSync();

    // Also recreate optimistic placeholders for any uploads already running
    // (e.g., after app resume or navigation) so they remain visible immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _hydrateInFlightUploads();
    });

    // Remove global setState - it causes image blinking
    // Only rebuild when focus/emoji picker changes
    _messageFocusNode.addListener(() {
      if (_messageFocusNode.hasFocus && _showEmojiPicker) {
        setState(() => _showEmojiPicker = false);
      }
    });

    // Listen to background upload progress
    final uploadService = BackgroundUploadService();
    uploadService.onUploadProgress = (messageId, isUploading, progress) {
      if (mounted) {
        setState(() {
          if (isUploading) {
            _uploadingMessageIds.add(messageId);
            _pendingUploadProgress[messageId] = progress;
          } else {
            // Upload complete - only remove uploading state, keep pending visible
            // Dedup logic will remove pending when server message arrives
            _uploadingMessageIds.remove(messageId);
            _pendingUploadProgress.remove(messageId);
          }
        });
        // Cache progress updates
        _cachePendingMessages();
      }
    };

    // Initialize MediaUploadService with CloudflareConfig
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

    // Initialize WhatsApp media upload service
    _whatsappMediaUpload = WhatsAppMediaUploadService(
      workerBaseUrl:
          'https://whatsapp-media-worker.giridharannj.workers.dev', // TODO: Update with actual worker URL
    );

    // Set up stream to track lastReadAt in real-time
    _setupLastReadStream();

    // Scroll to bottom on initial load AND mark as read after frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scrollToBottom(force: true);
        // Mark as read on entry so splitter can detect read messages
        // Schedule this separately to avoid build conflicts
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            _markAsRead();
          }
        });
      }
    });
  }

  void _setupLastReadStream() {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;
      if (currentUser == null) return;
      final chatId = '${widget.classId}|${widget.subjectId}';

      _lastReadAtStream = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('chatReads')
          .doc(chatId)
          .snapshots()
          .map((doc) {
            if (doc.exists && doc.data() != null && doc['lastReadAt'] != null) {
              final timestamp = doc['lastReadAt'] as Timestamp;
              return timestamp;
            }
            return Timestamp.fromDate(
              DateTime.now().subtract(const Duration(days: 30)),
            );
          });
    } catch (e) {
      // Fallback to static stream
      _lastReadAtStream = Stream.value(
        Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 30))),
      );
    }
  }

  Future<void> _markAsRead() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;
      if (currentUser != null) {
        // Update centralized unread tracker (this updates Firestore)
        await _markChatAsReadForUser();

        // Update legacy group doc for backward compatibility
        await _messagingService.markGroupAsRead(
          widget.classId,
          widget.subjectId,
          currentUser.uid,
        );
      }
    } catch (e) {}
  }

  Future<void> _markChatAsReadForUser() async {
    if (!mounted) return; // Don't try to access context if widget is disposed

    try {
      final unread = Provider.of<UnreadCountProvider>(context, listen: false);
      final chatId = '${widget.classId}|${widget.subjectId}';
      await unread.markChatAsRead(chatId);
    } catch (e) {}
  }

  @override
  void dispose() {
    // CRITICAL EMERGENCY SAVE: Last chance to persist pending messages
    // Must happen SYNCHRONOUSLY before any cleanup
    if (_pendingMessages.isNotEmpty) {
      debugPrint(
        '🆘 DISPOSE EMERGENCY: Saving ${_pendingMessages.length} pending messages SYNCHRONOUSLY',
      );
      try {
        final cacheService = LocalCacheService();
        final messages = _pendingMessages.map((m) {
          final firestore = m.toFirestore();
          firestore['id'] = m.id;
          return firestore;
        }).toList();
        // Use SYNCHRONOUS write to guarantee save before dispose completes
        cacheService.cacheMessagesSync(
          conversationId: _pendingMessagesCacheKey,
          messages: messages,
        );
        debugPrint('✅ EMERGENCY CACHE SAVED SYNCHRONOUSLY');
      } catch (e) {
        debugPrint('❌ EMERGENCY CACHE ERROR: $e');
      }
    }

    // Final mark as read
    try {
      final unread = _unreadRef;
      final chatId = '${widget.classId}|${widget.subjectId}';
      Future.microtask(() {
        unread?.markChatAsRead(chatId);
      });
    } catch (e) {}

    _messageController.dispose();
    _scrollController.dispose();
    _messageFocusNode.dispose();
    _audioRecorder.dispose();
    _recordingTimer?.cancel();
    _highlightResetTimer?.cancel();
    _messageKeys.clear();
    super.dispose();
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

  void _scrollToBottom({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        // Only auto-scroll if user is at bottom (within 100 pixels) or force is true
        if (force || _scrollController.offset < 100) {
          _scrollController.jumpTo(0);
        }
      }
    });
  }

  Future<void> _bumpLastActivity(int timestampMs) async {
    try {
      await FirebaseFirestore.instance
          .collection('classes')
          .doc(widget.classId)
          .collection('subjects')
          .doc(widget.subjectId)
          .set({'lastActivity': timestampMs}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Failed to bump lastActivity: $e');
    }
  }

  Future<void> _sendMessage({
    String? imageUrl,
    MediaMetadata? mediaMetadata,
  }) async {
    final text = _messageController.text.trim();
    if (text.isEmpty && imageUrl == null && mediaMetadata == null) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;

    if (currentUser == null) return;

    _messageController.clear();

    _messageFocusNode.requestFocus();

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _bumpLastActivity(now);

      final message = GroupChatMessage(
        id: '',
        senderId: currentUser.uid,
        senderName: currentUser.name,
        message: text,
        imageUrl: imageUrl,
        mediaMetadata: mediaMetadata,
        timestamp: now,
      );

      await _messagingService.sendGroupMessage(
        widget.classId,
        widget.subjectId,
        message,
      );
      // Scroll to latest so sender immediately sees their message
      _scrollToLatest();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send message: $e')));
      }
    }
  }

  void _scrollToLatest() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _locateMessageInList(GroupChatMessage message) async {
    final targetId = message.id;
    if (targetId.isEmpty) return;

    // Only act if the message is already present in the current window
    if (!_visibleMessageIds.contains(targetId)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message is outside the currently loaded window'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    setState(() {
      _highlightMessageId = targetId;
    });

    // Let the frame build before scrolling
    await Future.delayed(const Duration(milliseconds: 30));

    final contextForTarget = _messageKeys[targetId]?.currentContext;
    if (contextForTarget != null && mounted) {
      await Scrollable.ensureVisible(
        contextForTarget,
        alignment: 0.5,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOut,
      );
    }

    _highlightResetTimer?.cancel();
    _highlightResetTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted && _highlightMessageId == targetId) {
        setState(() => _highlightMessageId = null);
      }
    });
  }

  void _openSearch() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    Navigator.of(context)
        .push<GroupChatMessage?>(
          MaterialPageRoute(
            builder: (_) => GroupMessageSearchScreen(
              classId: widget.classId,
              subjectId: widget.subjectId,
              messagingService: _messagingService,
              currentUserId: currentUser.uid,
            ),
          ),
        )
        .then((selected) {
          if (selected != null) {
            _locateMessageInList(selected);
          }
        });
  }

  Future<void> _pickAndSendImage() async {
    try {
      final List<XFile> images = await _imagePicker.pickMultiImage(
        limit: 5, // Limit selection to 5 images at picker level
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (images.isEmpty) return;

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUserId = authProvider.currentUser?.uid;
      final currentUserName = authProvider.currentUser?.name ?? 'You';

      if (currentUserId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User not authenticated')),
          );
        }
        return;
      }

      final conversationId = '${widget.classId}_${widget.subjectId}';
      final baseTimestamp = DateTime.now().millisecondsSinceEpoch;
      final List<MediaMetadata> mediaList = [];
      final List<String> localPaths = [];
      final groupMessageId =
          'upload_${baseTimestamp}_${currentUserId.hashCode}';

      // Create metadata for each image with local path
      for (int i = 0; i < images.length; i++) {
        final image = images[i];
        final file = File(image.path);

        if (!file.existsSync()) continue;

        final messageId = '${groupMessageId}_$i';
        localPaths.add(file.path);

        mediaList.add(
          MediaMetadata(
            messageId: messageId,
            r2Key: 'pending/$messageId',
            publicUrl: '',
            thumbnail: file.path,
            localPath: file.path, // Store local path in metadata
            expiresAt: DateTime.now().add(const Duration(days: 30)),
            uploadedAt: DateTime.now(),
            originalFileName: file.path.split('/').last,
            fileSize: await file.length(),
            mimeType: 'image/jpeg',
          ),
        );
      }

      if (mediaList.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No valid images found')),
          );
        }
        return;
      }

      // Create single pending message with multiple media items
      final pendingMessage = GroupChatMessage(
        id: 'pending:$groupMessageId',
        senderId: currentUserId,
        senderName: currentUserName,
        message: '',
        timestamp: baseTimestamp,
        mediaMetadata: mediaList.first, // Primary image
        multipleMedia: mediaList.length > 1 ? mediaList : null,
      );

      await _bumpLastActivity(baseTimestamp);

      setState(() {
        _pendingMessages.insert(0, pendingMessage);
        for (int i = 0; i < mediaList.length; i++) {
          final messageId = mediaList[i].messageId;
          _uploadingMessageIds.add(messageId);
          _pendingUploadProgress[messageId] = 0.0;
          _localSenderMediaPaths[messageId] = localPaths[i];
        }
      });
      // Persist to cache
      _cachePendingMessages();

      // Queue each image for upload
      for (int i = 0; i < images.length; i++) {
        final image = images[i];
        final file = File(image.path);
        if (!file.existsSync()) continue;

        final messageId = '${groupMessageId}_$i';

        await BackgroundUploadService().queueUpload(
          file: file,
          conversationId: conversationId,
          senderId: currentUserId,
          senderRole: 'group',
          mediaType: 'message',
          chatType: 'group',
          senderName: currentUserName,
          messageId: messageId,
          groupId: groupMessageId, // Group all uploads together
        );
      }

      // Scroll to show the new message
      _scrollToBottom(force: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to queue images: $e')));
      }
    }
  }

  Future<void> _pickAndSendPDF() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result == null || result.files.isEmpty) return;

      final file = File(result.files.single.path!);

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUserId = authProvider.currentUser?.uid;
      final currentUserName = authProvider.currentUser?.name ?? 'You';

      if (currentUserId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User not authenticated')),
          );
        }
        return;
      }

      if (!file.existsSync()) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('PDF file not found')));
        }
        return;
      }

      final conversationId = '${widget.classId}_${widget.subjectId}';
      final messageId =
          'upload_${DateTime.now().millisecondsSinceEpoch}_${currentUserId.hashCode}';

      // Create pending message for immediate display
      final pendingMessage = GroupChatMessage(
        id: 'pending:$messageId',
        senderId: currentUserId,
        senderName: currentUserName,
        message: '',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        mediaMetadata: MediaMetadata(
          messageId: messageId,
          r2Key: 'pending/$messageId',
          publicUrl: '', // Will be set after upload
          thumbnail: '', // PDF has no thumbnail
          expiresAt: DateTime.now().add(const Duration(days: 30)),
          uploadedAt: DateTime.now(),
          originalFileName: file.path.split('/').last,
          fileSize: await file.length(),
          mimeType: 'application/pdf',
        ),
      );

      await _bumpLastActivity(pendingMessage.timestamp);

      debugPrint(
        '📝 Created pending message: id=${pendingMessage.id}, messageId=$messageId',
      );

      setState(() {
        _pendingMessages.insert(0, pendingMessage);
        _uploadingMessageIds.add(messageId);
        _pendingUploadProgress[messageId] = 0.0;
        _localSenderMediaPaths[messageId] = file.path;
      });

      // Ensure UI updates before scrolling
      await Future.delayed(const Duration(milliseconds: 100));

      // Queue upload in background service
      await BackgroundUploadService().queueUpload(
        file: file,
        conversationId: conversationId,
        senderId: currentUserId,
        senderRole: 'group',
        mediaType: 'message',
        chatType: 'group',
        senderName: currentUserName,
        messageId: messageId,
      );

      // Scroll to show the new message immediately after setState has taken effect
      if (mounted) {
        _scrollToBottom(force: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to queue PDF: $e')));
      }
    }
  }

  Future<void> _pickAndSendAudio() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.audio);

      if (result == null || result.files.isEmpty) return;

      final file = File(result.files.single.path!);

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUserId = authProvider.currentUser?.uid;
      final currentUserName = authProvider.currentUser?.name ?? 'You';

      if (currentUserId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User not authenticated')),
          );
        }
        return;
      }

      if (!file.existsSync()) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Audio file not found')));
        }
        return;
      }

      final conversationId = '${widget.classId}_${widget.subjectId}';
      final messageId =
          'upload_${DateTime.now().millisecondsSinceEpoch}_${currentUserId.hashCode}';

      // Create pending message for immediate display
      final pendingMessage = GroupChatMessage(
        id: 'pending:$messageId',
        senderId: currentUserId,
        senderName: currentUserName,
        message: '',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        mediaMetadata: MediaMetadata(
          messageId: messageId,
          r2Key: 'pending/$messageId',
          publicUrl: '', // Will be set after upload
          thumbnail: '', // Audio has no thumbnail
          expiresAt: DateTime.now().add(const Duration(days: 30)),
          uploadedAt: DateTime.now(),
          originalFileName: file.path.split('/').last,
          fileSize: await file.length(),
          mimeType: 'audio/mpeg',
        ),
      );

      await _bumpLastActivity(pendingMessage.timestamp);

      setState(() {
        _pendingMessages.insert(0, pendingMessage);
        _uploadingMessageIds.add(messageId);
        _pendingUploadProgress[messageId] = 0.0;
        _localSenderMediaPaths[messageId] = file.path;
      });

      // Queue upload in background service
      await BackgroundUploadService().queueUpload(
        file: file,
        conversationId: conversationId,
        senderId: currentUserId,
        senderRole: 'group',
        mediaType: 'message',
        chatType: 'group',
        senderName: currentUserName,
        messageId: messageId,
      );

      // Scroll to show the new message
      _scrollToBottom(force: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to queue audio: $e')));
      }
    }
  }

  Future<void> _recordAndSendAudio() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUserId = authProvider.currentUser?.uid;

      if (currentUserId == null) {
        throw Exception('User not authenticated');
      }

      // Stop recording FIRST
      if (_isRecording) {
        try {
          await _audioRecorder.stop();
        } catch (e) {}

        _recordingTimer?.cancel();
      }

      // Optimistic pending message for recorded audio
      final messageId = DateTime.now().millisecondsSinceEpoch.toString();
      final pendingMetadata = MediaMetadata(
        messageId: messageId,
        r2Key: 'pending/$messageId',
        publicUrl: '',
        localPath: _recordingPath,
        thumbnail: '',
        deletedLocally: false,
        serverStatus: ServerStatus.available,
        expiresAt: DateTime.now().add(const Duration(days: 365)),
        uploadedAt: DateTime.now(),
        fileSize: _recordingPath != null
            ? await File(_recordingPath!).length()
            : null,
        mimeType: 'audio/aac',
        originalFileName: _recordingPath != null
            ? Uri.file(_recordingPath!).pathSegments.last
            : null,
      );
      final pendingMsg = GroupChatMessage(
        id: 'pending:$messageId',
        senderId: currentUserId,
        senderName: authProvider.currentUser?.name ?? 'You',
        message: '',
        imageUrl: null,
        mediaMetadata: pendingMetadata,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      await _bumpLastActivity(pendingMsg.timestamp);

      setState(() {
        _isRecording = false;
        _isUploading = true;
        _uploadingMediaType = 'audio';
        _pendingMessages.insert(0, pendingMsg);
        _pendingUploadProgress[messageId] = 0.0;
      });
      _scrollToLatest();

      // Upload to Cloudflare R2 using MediaUploadService
      final conversationId = '${widget.classId}_${widget.subjectId}';

      final mediaMessage = await _mediaUploadService.uploadMedia(
        file: File(_recordingPath!),
        conversationId: conversationId,
        senderId: currentUserId,
        senderRole: 'student',
        mediaType: 'message',
        onProgress: (progress) {
          final doubleVal = (progress as num).toDouble();
          final normalized = doubleVal > 1 ? (doubleVal / 100.0) : doubleVal;
          setState(() {
            _pendingUploadProgress[messageId] = normalized;
          });
        },
      );

      final r2Key = _extractR2Key(mediaMessage.r2Url);

      // Copy the recorded audio to app directory so sender can play immediately
      String? cachedPath;
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final cacheDir = Directory('${appDir.path}/audio_cache');
        if (!await cacheDir.exists()) {
          await cacheDir.create(recursive: true);
        }

        final fileName = r2Key.split('/').last;
        final cachedFile = File('${cacheDir.path}/$fileName');
        await File(_recordingPath!).copy(cachedFile.path);
        cachedPath = cachedFile.path;
      } catch (e) {
        // Continue anyway - user will download if needed
      }

      final metadata = MediaMetadata(
        messageId: mediaMessage.id,
        r2Key: r2Key,
        publicUrl: mediaMessage.r2Url,
        thumbnail: '',
        expiresAt: DateTime.now().add(const Duration(days: 365)),
        uploadedAt: DateTime.now(),
        fileSize: mediaMessage.fileSize,
        mimeType: mediaMessage.fileType,
        localPath: cachedPath, // Include local path for immediate playback
        originalFileName: mediaMessage.fileName,
      );

      await _sendMessage(mediaMetadata: metadata);
      setState(() {
        _pendingMessages.removeWhere(
          (m) => m.mediaMetadata?.messageId == messageId,
        );
        _pendingUploadProgress.remove(messageId);
      });
      // Cache after removal
      _cachePendingMessages();

      // Now safe to delete temp recording file (we have it cached)
      try {
        final file = File(_recordingPath!);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Audio sent successfully'),
            duration: Duration(seconds: 1),
          ),
        );
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
        setState(() {
          _pendingMessages.removeWhere((m) => m.id.startsWith('pending:'));
          _pendingUploadProgress.clear();
        });
        // Cache after clear
        _cachePendingMessages();
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
      await _audioRecorder.stop();
      _recordingTimer?.cancel();
    }

    // Delete the file
    if (_recordingPath != null) {
      try {
        final file = File(_recordingPath!);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {}
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

  Widget _buildRecordingOverlay() {
    // Hide bottom bar entirely while any media is uploading (image/pdf/audio)
    if (_isUploading &&
        (_uploadingMediaType == 'image' ||
            _uploadingMediaType == 'pdf' ||
            _uploadingMediaType == 'audio')) {
      return const SizedBox();
    }
    if (_recordingPath == null && !_isUploading) return const SizedBox();

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        color: const Color(0xFF2A2A2A),
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
                    Text(
                      _uploadingMediaType == 'pdf'
                          ? 'Sending PDF...'
                          : _uploadingMediaType == 'audio'
                          ? 'Sending audio...'
                          : 'Uploading...',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
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

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final currentUserId = authProvider.currentUser?.uid;
    final theme = Theme.of(context);

    return Stack(
      children: [
        Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: AppBar(
            backgroundColor: theme.scaffoldBackgroundColor,
            elevation: 0,
            leading: IconButton(
              icon: Icon(
                _isSelectionMode ? Icons.close : Icons.arrow_back_ios_new,
                color: theme.iconTheme.color,
                size: 20,
              ),
              onPressed: () {
                if (_isSelectionMode) {
                  setState(() {
                    _isSelectionMode = false;
                    _selectedMessages.clear();
                  });
                } else {
                  Navigator.pop(context);
                }
              },
            ),
            title: _isSelectionMode
                ? Text(
                    '${_selectedMessages.length} selected',
                    style: TextStyle(
                      color: theme.textTheme.bodyLarge?.color,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : Row(
                    children: [
                      Text(widget.icon, style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.subjectName,
                              style: TextStyle(
                                color: theme.textTheme.bodyLarge?.color,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.className != null && widget.section != null
                                  ? '${widget.className} - Section ${widget.section}'
                                  : widget.teacherName,
                              style: TextStyle(
                                color: theme.textTheme.bodySmall?.color,
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
            actions: _isSelectionMode
                ? [
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.redAccent,
                        size: 24,
                      ),
                      onPressed: _selectedMessages.isEmpty
                          ? null
                          : _showDeleteDialog,
                    ),
                  ]
                : [
                    IconButton(
                      icon: Icon(
                        Icons.search,
                        color: Theme.of(context).iconTheme.color,
                      ),
                      onPressed: _openSearch,
                    ),
                  ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(
                height: 1,
                color: theme.dividerColor.withOpacity(0.1),
              ),
            ),
          ),
          body: Column(
            children: [
              // Messages List
              Expanded(
                child: StreamBuilder<List<GroupChatMessage>>(
                  stream: _messagingService.getGroupMessages(
                    widget.classId,
                    widget.subjectId,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Error loading messages',
                          style: TextStyle(color: Colors.white70),
                        ),
                      );
                    }

                    // Always proceed to merge with optimistic pending messages,
                    // even while the stream is still connecting. This ensures
                    // the pending preview appears immediately.

                    // Filter out messages deleted by current user
                    // DO NOT merge pending messages here - let the nested StreamBuilder handle it
                    final messages =
                        (snapshot.data ?? const <GroupChatMessage>[])
                            .where(
                              (m) =>
                                  !(m.deletedFor?.contains(currentUserId) ??
                                      false),
                            )
                            .toList();

                    debugPrint(
                      '📥 FIRESTORE SNAPSHOT: ${messages.length} messages received',
                    );
                    for (var msg in messages.take(3)) {
                      debugPrint(
                        '   msg.id=${msg.id}, msgId=${msg.mediaMetadata?.messageId}, sender=${msg.senderId}',
                      );
                    }

                    // Auto-scroll when a new newest message arrives (keep latest in view)
                    final newestId = messages.isNotEmpty
                        ? messages.first.id
                        : null;
                    if (newestId != null && newestId != _lastTopMessageId) {
                      _lastTopMessageId = newestId;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _scrollToLatest();
                      });
                      // Play subtle pop for new incoming messages (not self, not pending)
                      final newestMsg = messages.first;
                      final isIncoming =
                          newestMsg.senderId != currentUserId &&
                          !(newestMsg.id.startsWith('pending:'));
                      final now = DateTime.now();
                      if (_initializedFirstSnapshot &&
                          isIncoming &&
                          now.difference(_lastSoundPlayedAt) > _soundDebounce &&
                          _lastIncomingTopMessageId != newestId) {
                        _lastIncomingTopMessageId = newestId;
                        _lastSoundPlayedAt = now;
                        SystemSound.play(SystemSoundType.click);
                      }
                      // Avoid playing sound on the very first snapshot
                      _initializedFirstSnapshot = true;
                    }

                    // If no Firestore messages but we have pending messages, show them
                    if (messages.isEmpty && _pendingMessages.isNotEmpty) {
                      return _buildMessageList(
                        _pendingMessages,
                        0, // No last read timestamp since no messages yet
                        currentUserId,
                        showDivider: false,
                      );
                    }

                    if (messages.isEmpty) {
                      return const Center(
                        child: Text(
                          'No messages yet.\nBe the first to say hello! 👋',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54),
                        ),
                      );
                    }

                    return StreamBuilder<Timestamp?>(
                      stream: _lastReadAtStream,
                      builder: (context, readSnapshot) {
                        // Only consider it valid data if we actually received a non-null timestamp
                        final hasValidData = readSnapshot.data != null;
                        final lastReadMs =
                            readSnapshot.data
                                ?.toDate()
                                .millisecondsSinceEpoch ??
                            DateTime.now()
                                .subtract(const Duration(days: 30))
                                .millisecondsSinceEpoch;

                        // Merge pending messages with Firestore messages, removing duplicates
                        // (pending messages that have been successfully uploaded to Firestore)
                        debugPrint(
                          '\n🔄 MERGE: ${_pendingMessages.length} pending + ${messages.length} firestore',
                        );
                        if (_pendingMessages.isNotEmpty) {
                          for (var p in _pendingMessages) {
                            debugPrint(
                              '   PENDING: id=${p.id}, msgId=${p.mediaMetadata?.messageId ?? p.multipleMedia?.first.messageId}',
                            );
                          }
                        } else {
                          debugPrint(
                            '   ⚠️ WARNING: No pending messages in memory!',
                          );
                        }
                        for (var f in messages.take(3)) {
                          debugPrint(
                            '   FIRESTORE: id=${f.id}, msgId=${f.mediaMetadata?.messageId ?? f.multipleMedia?.first.messageId}',
                          );
                        }

                        final allMessages = <GroupChatMessage>[
                          ..._pendingMessages,
                          ...messages,
                        ];

                        // SAFETY CHECK: Snapshot uploading IDs before dedup
                        final uploadingMessageIds = <String>{
                          ..._uploadingMessageIds,
                        };
                        debugPrint(
                          '🔐 DEDUP SAFETY: ${uploadingMessageIds.length} messages still uploading',
                        );

                        // Remove pending messages that now have a corresponding Firestore message
                        allMessages.removeWhere((pendingMsg) {
                          // Only process pending messages
                          if (!pendingMsg.id.startsWith('pending:')) {
                            return false;
                          }

                          // GOLDEN RULE: Keep any message where ANY media is still uploading
                          if (pendingMsg.multipleMedia != null &&
                              pendingMsg.multipleMedia!.isNotEmpty) {
                            final anyStillUploading = pendingMsg.multipleMedia!
                                .any(
                                  (m) =>
                                      uploadingMessageIds.contains(m.messageId),
                                );
                            if (anyStillUploading) {
                              debugPrint(
                                '⏳ KEEP PENDING GROUP: ${pendingMsg.id} (${pendingMsg.multipleMedia!.length} media, some uploading)',
                              );
                              return false; // Keep it
                            }
                          } else if (pendingMsg.mediaMetadata != null) {
                            if (uploadingMessageIds.contains(
                              pendingMsg.mediaMetadata!.messageId,
                            )) {
                              debugPrint(
                                '⏳ KEEP PENDING SINGLE: ${pendingMsg.id} (still uploading)',
                              );
                              return false; // Keep it
                            }
                          }

                          // Now check if server has confirmed this message
                          bool hasServerVersion = false;

                          if (pendingMsg.multipleMedia != null &&
                              pendingMsg.multipleMedia!.isNotEmpty) {
                            // For multi-image: ALL media must be on server
                            final allMediaOnServer = pendingMsg.multipleMedia!
                                .every((pm) {
                                  return messages.any((fsMsg) {
                                    // Check if this media ID is in the Firestore message
                                    final inPrimary =
                                        fsMsg.mediaMetadata?.messageId ==
                                        pm.messageId;
                                    final inArray =
                                        fsMsg.multipleMedia?.any(
                                          (m) => m.messageId == pm.messageId,
                                        ) ??
                                        false;
                                    return inPrimary || inArray;
                                  });
                                });
                            hasServerVersion = allMediaOnServer;
                            if (allMediaOnServer) {
                              debugPrint(
                                '✅ ALL MEDIA CONFIRMED: ${pendingMsg.id}',
                              );
                            } else {
                              debugPrint(
                                '⏳ WAITING FOR MEDIA: ${pendingMsg.id} (${pendingMsg.multipleMedia!.length} items)',
                              );
                            }
                          } else if (pendingMsg.mediaMetadata != null) {
                            // For single media: find by messageId
                            hasServerVersion = messages.any((fsMsg) {
                              final inPrimary =
                                  fsMsg.mediaMetadata?.messageId ==
                                  pendingMsg.mediaMetadata!.messageId;
                              final inArray =
                                  fsMsg.multipleMedia?.any(
                                    (m) =>
                                        m.messageId ==
                                        pendingMsg.mediaMetadata!.messageId,
                                  ) ??
                                  false;
                              return inPrimary || inArray;
                            });
                            if (hasServerVersion) {
                              debugPrint(
                                '✅ SINGLE MEDIA CONFIRMED: ${pendingMsg.id}',
                              );
                            }
                          } else {
                            // Text-only: match by sender + timestamp
                            hasServerVersion = messages.any((fsMsg) {
                              final senderMatch =
                                  fsMsg.senderId == pendingMsg.senderId;
                              final timeMatch =
                                  (fsMsg.timestamp - pendingMsg.timestamp)
                                      .abs() <
                                  15000;
                              return senderMatch && timeMatch;
                            });
                            if (hasServerVersion) {
                              debugPrint(
                                '✅ TEXT MESSAGE CONFIRMED: ${pendingMsg.id}',
                              );
                            }
                          }

                          if (hasServerVersion) {
                            // Preserve local paths before removing
                            if (pendingMsg.multipleMedia != null) {
                              for (final pm in pendingMsg.multipleMedia!) {
                                if (pm.localPath != null &&
                                    pm.localPath!.isNotEmpty) {
                                  _localSenderMediaPaths[pm.messageId] =
                                      pm.localPath!;
                                }
                              }
                            }
                            if (pendingMsg.mediaMetadata?.localPath != null) {
                              _localSenderMediaPaths[pendingMsg
                                      .mediaMetadata!
                                      .messageId] =
                                  pendingMsg.mediaMetadata!.localPath!;
                            }
                            return true; // Remove from pending
                          }

                          return false; // Keep in pending
                        });

                        // Sort by timestamp (newest first)
                        allMessages.sort(
                          (a, b) => b.timestamp.compareTo(a.timestamp),
                        );

                        return _buildMessageList(
                          allMessages,
                          lastReadMs,
                          currentUserId,
                          showDivider:
                              hasValidData, // Only show divider with valid Firestore data
                        );
                      },
                    );
                  },
                ),
              ),

              // Input Bar
              _buildInputBar(),
              if (_showEmojiPicker)
                EmojiPicker(
                  onEmojiSelected: (category, emoji) => _onEmojiSelected(emoji),
                  onBackspacePressed: _onBackspacePressed,
                  config: Config(
                    height: 300,
                    checkPlatformCompatibility: false,
                    emojiViewConfig: EmojiViewConfig(
                      backgroundColor: const Color(0xFF1A1A1A),
                      columns: 7,
                      emojiSizeMax: 28,
                    ),
                    categoryViewConfig: CategoryViewConfig(
                      backgroundColor: const Color(0xFF1A1A1A),
                      iconColorSelected: const Color(0xFF00A884),
                      indicatorColor: const Color(0xFF00A884),
                    ),
                    bottomActionBarConfig: BottomActionBarConfig(
                      backgroundColor: const Color(0xFF1A1A1A),
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

  Widget _buildInputBar() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Get current user role to determine color scheme
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;
    final isTeacher = currentUser?.role.toString() == 'UserRole.teacher';

    // Premium dark theme palette - integrated with chat screen
    final backgroundColor = isDark
        ? const Color(0xFF0D0E10) // Near-black, blends with chat
        : const Color(0xFFF5F5F5);
    final inputFieldColor = isDark
        ? const Color(0xFF1E2024) // Slightly lighter for depth
        : Colors.white;
    final textColor = isDark
        ? const Color(0xFFE8E8E8) // Bright, readable
        : const Color(0xFF000000);
    final hintColor = isDark
        ? const Color(0xFF6B6B6B) // Subdued gray
        : const Color(0xFF999999);

    // Dynamic colors based on user role
    final iconColor = isDark
        ? (isTeacher
              ? const Color(0xFF9A95CC) // Soft muted violet for teachers
              : const Color(0xFFFFB380)) // Soft muted orange for students
        : (isTeacher
              ? const Color(0xFF6C63FF) // Violet for teachers
              : const Color(0xFFFF8F00)); // Orange for students

    final iconDisabledColor = isDark
        ? const Color(0xFF3A3A3C)
        : const Color(0xFFBBBBBB);

    final accentColor = isTeacher
        ? const Color(0xFF7C3AED) // Cool violet for teachers
        : const Color(0xFFFF9800); // Orange for students

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
            // Input container - pill-shaped with subtle depth
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
                    // Emoji toggle - inside input, left side
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
                          color: iconColor,
                          size: 23,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Text input - primary focus
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        focusNode: _messageFocusNode,
                        cursorColor: accentColor,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 15,
                          height: 1.4,
                          fontWeight: FontWeight.w400,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Message',
                          hintStyle: TextStyle(
                            color: hintColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 10,
                          ),
                        ),
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.newline,
                        enabled: !_isRecording && !_isUploading,
                        onSubmitted: (_) {
                          _sendMessage();
                          Future.delayed(const Duration(milliseconds: 50), () {
                            _messageFocusNode.requestFocus();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Attachment - inside input, right side
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: _isUploading ? null : _showMediaOptions,
                        child: Icon(
                          Icons.attach_file_rounded,
                          color: _isUploading ? iconDisabledColor : iconColor,
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Mic/Send button - balanced size, outside input
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _messageController,
              builder: (context, value, child) {
                final hasText = value.text.trim().isNotEmpty;
                return GestureDetector(
                  onTap: () async {
                    if (hasText && !_isUploading) {
                      _sendMessage();
                    } else if (!_isRecording && !hasText && !_isUploading) {
                      // Single tap to start recording
                      final hasPermission = await _audioRecorder
                          .hasPermission();
                      if (!hasPermission) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Microphone permission denied. Please enable it in Settings.',
                              ),
                            ),
                          );
                        }
                        return;
                      }
                      final tempDir = await getTemporaryDirectory();
                      final path =
                          '${tempDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
                      await _audioRecorder.start(
                        const RecordConfig(encoder: AudioEncoder.aacLc),
                        path: path,
                      );
                      setState(() {
                        _isRecording = true;
                        _recordingPath = path;
                        _recordingDuration.value = 0;
                        _slideOffsetX = 0;
                        _isCancelled = false;
                      });
                      _recordingTimer = Timer.periodic(
                        const Duration(seconds: 1),
                        (_) {
                          _recordingDuration.value++;
                        },
                      );
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
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _isRecording
                          ? theme.colorScheme.error
                          : accentColor,
                      shape: BoxShape.circle,
                      boxShadow: isDark
                          ? [
                              BoxShadow(
                                color: accentColor.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : [
                              BoxShadow(
                                color: accentColor.withOpacity(0.25),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                    ),
                    child: Icon(
                      _isRecording
                          ? Icons.mic
                          : (hasText ? Icons.send_rounded : Icons.mic),
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showMediaOptions() {
    showModernAttachmentSheet(
      context,
      onImageTap: _pickAndSendImage,
      onPdfTap: _pickAndSendPDF,
      onAudioTap: _pickAndSendAudio,
    );
  }

  Future<void> _deleteMessages(bool deleteForEveryone) async {
    final messagesToDelete = _selectedMessages.toList();
    if (messagesToDelete.isEmpty) return;

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUserId = authProvider.currentUser?.uid;
      if (currentUserId == null) {
        throw Exception('User not found');
      }

      for (final messageId in messagesToDelete) {
        final messageRef = FirebaseFirestore.instance
            .collection('classes')
            .doc(widget.classId)
            .collection('subjects')
            .doc(widget.subjectId)
            .collection('messages')
            .doc(messageId);

        // Get message to check sender and media
        final docSnapshot = await messageRef.get();

        if (!docSnapshot.exists) {
          continue;
        }

        final data = docSnapshot.data();
        final senderId = data?['senderId'] as String?;
        if (senderId == null || senderId != currentUserId) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('You can only delete your own messages'),
                backgroundColor: Colors.red,
              ),
            );
          }
          continue;
        }

        // Delete media from Cloudflare if exists
        if (data?['mediaMetadata'] != null) {
          final r2Key = data!['mediaMetadata']['r2Key'] as String?;
          if (r2Key != null) {
            try {
              final r2Service = CloudflareR2Service(
                accountId: CloudflareConfig.accountId,
                bucketName: CloudflareConfig.bucketName,
                accessKeyId: CloudflareConfig.accessKeyId,
                secretAccessKey: CloudflareConfig.secretAccessKey,
                r2Domain: CloudflareConfig.r2Domain,
              );
              await r2Service.deleteFile(key: r2Key);
            } catch (e) {}
          }
        }

        // ✅ FIXED: Mark message as deleted instead of completely deleting
        // This preserves chat history and allows proper filtering
        await messageRef.update({
          'isDeleted': true,
          'message': '', // Clear content
          'mediaMetadata': null, // Clear media metadata
          'imageUrl': null,
        });
      }

      setState(() {
        _selectedMessages.clear();
        _isSelectionMode = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message deleted'),
            backgroundColor: Color(0xFF4CAF50),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Messages',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Delete message for everyone?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteMessages(true);
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final GroupChatMessage message;
  final bool isMe;
  final bool uploading; // for pending messages
  final double? uploadProgress;
  final Map<String, String> localSenderMediaPaths;
  final bool selectionMode;
  final Set<String> uploadingMessageIds;
  final Map<String, double> pendingUploadProgress;

  const _MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.uploading = false,
    this.uploadProgress,
    required this.localSenderMediaPaths,
    this.selectionMode = false,
    required this.uploadingMessageIds,
    required this.pendingUploadProgress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final myBubbleColor = const Color(0xFFFFE8D1);
    final otherBubbleColor = isDark
        ? theme.colorScheme.surface
        : theme.cardColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            // Avatar for others
            CircleAvatar(
              radius: 14,
              backgroundColor: theme.primaryColor.withOpacity(0.2),
              child: Text(
                message.senderName[0].toUpperCase(),
                style: TextStyle(
                  color: theme.primaryColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],

          // Message Content
          Flexible(
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      message.senderName,
                      style: TextStyle(
                        color: theme.textTheme.bodySmall?.color,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                // Multiple media handling (WhatsApp-style grid) - NO outer bubble
                if (message.multipleMedia != null &&
                    message.multipleMedia!.isNotEmpty)
                  Column(
                    crossAxisAlignment: isMe
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MultiImageMessageBubble(
                        imageUrls: message.multipleMedia!
                            .map((m) => m.localPath ?? m.publicUrl)
                            .toList(),
                        isMe: isMe,
                        uploadProgress: message.multipleMedia!
                            .map((m) => pendingUploadProgress[m.messageId])
                            .toList(),
                        onImageTap: (index) async {
                          // Open image gallery - it handles loading from cache or network
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => _ImageGalleryViewer(
                                mediaList: message.multipleMedia!,
                                initialIndex: index,
                                localSenderMediaPaths: localSenderMediaPaths,
                                isMe: isMe,
                              ),
                            ),
                          );
                        },
                      ),
                      if (message.message.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Material(
                          elevation: 0,
                          color: isMe ? myBubbleColor : otherBubbleColor,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(12),
                            topRight: const Radius.circular(12),
                            bottomLeft: Radius.circular(isMe ? 12 : 6),
                            bottomRight: Radius.circular(isMe ? 6 : 12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            child: Linkify(
                              onOpen: (link) async {
                                final uri = Uri.parse(link.url);
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(
                                    uri,
                                    mode: LaunchMode.externalApplication,
                                  );
                                }
                              },
                              text: LinkUtils.addProtocolToBareUrls(
                                message.message,
                              ),
                              options: const LinkifyOptions(
                                defaultToHttps: true,
                              ),
                              style: TextStyle(
                                color: isMe
                                    ? const Color(0xFF1A1D21)
                                    : theme.colorScheme.onSurface,
                                fontSize: 14,
                                height: 1.5,
                              ),
                              linkStyle: TextStyle(
                                color: isMe
                                    ? const Color(0xFF0066CC)
                                    : theme.colorScheme.primary,
                                fontSize: 14,
                                height: 1.5,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  )
                // Single media or text-only messages
                else
                  Material(
                    elevation: 0,
                    color: isMe ? myBubbleColor : otherBubbleColor,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(12),
                      topRight: const Radius.circular(12),
                      bottomLeft: Radius.circular(isMe ? 12 : 6),
                      bottomRight: Radius.circular(isMe ? 6 : 12),
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        // Tighter padding for media-only bubbles to maximize image area
                        horizontal:
                            (message.mediaMetadata != null ||
                                    message.imageUrl != null) &&
                                message.message.isEmpty
                            ? 6
                            : 14,
                        // Reduce bottom border for media-only bubbles
                        vertical:
                            (message.mediaMetadata != null ||
                                    message.imageUrl != null) &&
                                message.message.isEmpty
                            ? 0
                            : 12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Single media handling
                          if (message.mediaMetadata != null) ...[
                            _buildMetadataAttachment(
                              context,
                              message.mediaMetadata!,
                            ),
                            if (message.message.isNotEmpty)
                              const SizedBox(height: 8),
                          ]
                          // Legacy URL support (images/PDFs)
                          else if (message.imageUrl != null) ...[
                            _buildLegacyAttachment(context, message.imageUrl!),
                            if (message.message.isNotEmpty)
                              const SizedBox(height: 8),
                          ],
                          if (message.message.isNotEmpty)
                            Linkify(
                              onOpen: (link) async {
                                final uri = Uri.parse(link.url);
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(
                                    uri,
                                    mode: LaunchMode.externalApplication,
                                  );
                                }
                              },
                              text: LinkUtils.addProtocolToBareUrls(
                                message.message,
                              ),
                              options: const LinkifyOptions(
                                defaultToHttps: true,
                              ),
                              style: TextStyle(
                                color: isMe
                                    ? const Color(0xFF1A1D21)
                                    : theme.colorScheme.onSurface,
                                fontSize: 14,
                                height: 1.5,
                              ),
                              linkStyle: TextStyle(
                                color: isMe
                                    ? const Color(0xFF0066CC)
                                    : theme.colorScheme.primary,
                                fontSize: 14,
                                height: 1.5,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  _formatTime(message.timestamp),
                  style: TextStyle(
                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataAttachment(
    BuildContext context,
    MediaMetadata metadata,
  ) {
    // Use optimized MediaPreviewCard for ALL media types
    // This prevents auto-downloads and provides on-demand loading
    final fileSize = metadata.fileSize ?? 0;

    // Check if this specific message is uploading
    final isUploading = uploadingMessageIds.contains(metadata.messageId);
    final uploadProgressVal = pendingUploadProgress[metadata.messageId];

    return MediaPreviewCard(
      key: ValueKey('media-${metadata.messageId}-${metadata.r2Key}'),
      r2Key: metadata.r2Key,
      fileName: _fileNameFromMetadata(metadata),
      mimeType: metadata.mimeType ?? 'application/octet-stream',
      fileSize: fileSize,
      thumbnailBase64: metadata.thumbnail,
      localPath:
          metadata.localPath ?? localSenderMediaPaths[metadata.messageId],
      isMe: isMe,
      uploading: isUploading,
      uploadProgress: uploadProgressVal,
      selectionMode: selectionMode,
    );
  }

  // ignore: unused_element
  Widget _buildMultipleMediaGrid(
    BuildContext context,
    List<MediaMetadata> mediaList,
  ) {
    final count = mediaList.length;

    // Constrain max width for better WhatsApp-style appearance
    Widget gridContent;

    // WhatsApp-style grid layout
    if (count == 2) {
      // 2 images: side by side
      gridContent = Row(
        children: [
          Expanded(
            child: _buildGridImage(
              context,
              mediaList[0],
              allMedia: mediaList,
              currentIndex: 0,
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: _buildGridImage(
              context,
              mediaList[1],
              allMedia: mediaList,
              currentIndex: 1,
            ),
          ),
        ],
      );
    } else if (count == 3) {
      // 3 images: 1 large on left, 2 stacked on right
      gridContent = Row(
        children: [
          Expanded(
            flex: 2,
            child: _buildGridImage(
              context,
              mediaList[0],
              allMedia: mediaList,
              currentIndex: 0,
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Column(
              children: [
                _buildGridImage(
                  context,
                  mediaList[1],
                  allMedia: mediaList,
                  currentIndex: 1,
                ),
                const SizedBox(height: 2),
                _buildGridImage(
                  context,
                  mediaList[2],
                  allMedia: mediaList,
                  currentIndex: 2,
                ),
              ],
            ),
          ),
        ],
      );
    } else if (count == 4) {
      // 4 images: 2x2 grid
      gridContent = Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildGridImage(
                  context,
                  mediaList[0],
                  allMedia: mediaList,
                  currentIndex: 0,
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: _buildGridImage(
                  context,
                  mediaList[1],
                  allMedia: mediaList,
                  currentIndex: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: _buildGridImage(
                  context,
                  mediaList[2],
                  allMedia: mediaList,
                  currentIndex: 2,
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: _buildGridImage(
                  context,
                  mediaList[3],
                  allMedia: mediaList,
                  currentIndex: 3,
                ),
              ),
            ],
          ),
        ],
      );
    } else if (count >= 5) {
      // 5+ images: 2x2 grid + vertical strip for remaining
      gridContent = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left side: 2x2 grid with clean gaps
          Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildGridImage(
                        context,
                        mediaList[0],
                        allMedia: mediaList,
                        currentIndex: 0,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: _buildGridImage(
                        context,
                        mediaList[1],
                        allMedia: mediaList,
                        currentIndex: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: _buildGridImage(
                        context,
                        mediaList[2],
                        allMedia: mediaList,
                        currentIndex: 2,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: _buildGridImage(
                        context,
                        mediaList[3],
                        allMedia: mediaList,
                        currentIndex: 3,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 2),
          // Right side: Vertical scroll for remaining images
          SizedBox(
            width: 140,
            child: ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: count - 4,
              itemBuilder: (context, index) {
                final mediaIndex = index + 4;
                return Column(
                  children: [
                    if (index > 0) const SizedBox(height: 2),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => _ImageGalleryViewer(
                              mediaList: mediaList,
                              initialIndex: mediaIndex,
                              localSenderMediaPaths: localSenderMediaPaths,
                              isMe: isMe,
                            ),
                          ),
                        );
                      },
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: _buildGridImage(
                          context,
                          mediaList[mediaIndex],
                          allMedia: mediaList,
                          currentIndex: mediaIndex,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      );
    } else {
      // Fallback for single image
      gridContent = _buildGridImage(
        context,
        mediaList[0],
        allMedia: mediaList,
        currentIndex: 0,
      );
    }

    // Check if ANY image in the grid is uploading (progress < 1.0)
    final uploadingMediaWithProgress = mediaList
        .where(
          (media) =>
              uploadingMessageIds.contains(media.messageId) &&
              (pendingUploadProgress[media.messageId] ?? 0.0) < 1.0,
        )
        .toList();

    final isAnyUploading = uploadingMediaWithProgress.isNotEmpty;

    // Calculate average upload progress for the grid
    double gridUploadProgress = 0.0;
    if (isAnyUploading) {
      final totalProgress = uploadingMediaWithProgress.fold<double>(
        0.0,
        (sum, media) => sum + (pendingUploadProgress[media.messageId] ?? 0.0),
      );
      gridUploadProgress =
          totalProgress /
          (uploadingMediaWithProgress.isEmpty
              ? 1
              : uploadingMediaWithProgress.length);
    }

    // Constrain width for better appearance
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Stack(
        children: [
          gridContent,
          // Single loading overlay on entire grid
          if (isAnyUploading)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        strokeWidth: 3,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${(gridUploadProgress * 100).toInt()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Uploading ${mediaList.length} ${mediaList.length == 1 ? "image" : "images"}...',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGridImage(
    BuildContext context,
    MediaMetadata metadata, {
    List<MediaMetadata>? allMedia,
    int? currentIndex,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(
        aspectRatio: 1,
        child: GestureDetector(
          onTap: () {
            // Open gallery viewer when tapping grid image
            if (allMedia != null && currentIndex != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _ImageGalleryViewer(
                    mediaList: allMedia,
                    initialIndex: currentIndex,
                    localSenderMediaPaths: localSenderMediaPaths,
                    isMe: isMe,
                  ),
                ),
              );
            }
          },
          child: MediaPreviewCard(
            key: ValueKey('grid-${metadata.messageId}'),
            r2Key: metadata.r2Key,
            fileName: _fileNameFromMetadata(metadata),
            mimeType: metadata.mimeType ?? 'image/jpeg',
            fileSize: metadata.fileSize ?? 0,
            thumbnailBase64: metadata.thumbnail,
            localPath:
                metadata.localPath ?? localSenderMediaPaths[metadata.messageId],
            isMe: isMe,
            uploading: false, // No individual upload progress in grid
            uploadProgress: null,
            selectionMode: selectionMode,
          ),
        ),
      ),
    );
  }

  Widget _buildLegacyAttachment(BuildContext context, String url) {
    // Extract R2 key from URL for legacy messages
    // URL format: https://files.lenv1.tech/media/timestamp/filename.ext
    final uri = Uri.tryParse(url);
    if (uri == null) return const SizedBox();

    final r2Key = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;

    final fileName = _fileNameFromUrl(url);
    final mimeType = _guessMimeType(fileName);

    return MediaPreviewCard(
      key: ValueKey('legacy-$r2Key'),
      r2Key: r2Key,
      fileName: fileName,
      mimeType: mimeType,
      fileSize: 0, // Unknown for legacy
      isMe: isMe,
      selectionMode: selectionMode,
    );
  }

  String _guessMimeType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.m4a') || lower.endsWith('.aac')) return 'audio/aac';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    return 'application/octet-stream';
  }

  String _fileNameFromMetadata(MediaMetadata metadata) {
    // Prefer exact original file name if available
    final orig = metadata.originalFileName;
    if (orig != null && orig.isNotEmpty) {
      return orig;
    }
    final parts = metadata.r2Key.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isNotEmpty) return parts.last;
    return _fileNameFromUrl(metadata.publicUrl);
  }

  String _fileNameFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.last;
    }
    return 'file';
  }

  String _formatTime(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateFormat('h:mm a').format(date);
  }
}

// Group Message Search Screen
class GroupMessageSearchScreen extends StatefulWidget {
  final String classId;
  final String subjectId;
  final GroupMessagingService messagingService;
  final String currentUserId;

  const GroupMessageSearchScreen({
    super.key,
    required this.classId,
    required this.subjectId,
    required this.messagingService,
    required this.currentUserId,
  });

  @override
  State<GroupMessageSearchScreen> createState() =>
      _GroupMessageSearchScreenState();
}

class _GroupMessageSearchScreenState extends State<GroupMessageSearchScreen> {
  final TextEditingController _queryController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<GroupChatMessage> _results = [];

  bool _loading = false;
  bool _hasMore = true;
  String _lastQuery = '';
  // ignore: unused_field
  String? _cursor;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _queryController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_loading &&
        _hasMore) {
      _runSearch();
    }
  }

  Future<void> _runSearch({bool reset = false}) async {
    final q = _queryController.text.trim();

    if (q.length < 2) {
      setState(() {
        _results = [];
        _cursor = null;
        _hasMore = true;
        _lastQuery = q;
      });
      return;
    }

    if (reset || q != _lastQuery) {
      setState(() {
        _loading = true;
        _hasMore = true;
        _cursor = null;
        _results = [];
        _lastQuery = q;
      });
    } else if (!_hasMore || _loading) {
      return;
    } else {
      setState(() => _loading = true);
    }

    try {
      final messages = await widget.messagingService.searchGroupMessages(
        classId: widget.classId,
        subjectId: widget.subjectId,
        query: q,
        limit: 25,
      );

      setState(() {
        _results.addAll(messages);
        _hasMore = messages.length >= 25;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  String _formatTimestamp(DateTime dt) {
    return DateFormat('MMM d, h:mm a').format(dt);
  }

  IconData _iconFor(GroupChatMessage m) {
    final mime = m.mediaMetadata?.mimeType ?? '';
    if (mime.startsWith('image/')) return Icons.image_outlined;
    if (mime == 'application/pdf') return Icons.picture_as_pdf_outlined;
    if (mime.startsWith('audio/')) return Icons.audiotrack;
    if (mime.isNotEmpty) return Icons.insert_drive_file_outlined;
    return Icons.chat_bubble_outline;
  }

  String _primaryText(GroupChatMessage m) {
    if (m.message.isNotEmpty) return m.message;
    if (m.mediaMetadata?.originalFileName?.isNotEmpty == true) {
      return m.mediaMetadata!.originalFileName!;
    }
    return 'Media message';
  }

  String _secondaryText(GroupChatMessage m) {
    final sender = m.senderName.isNotEmpty ? m.senderName : 'Unknown';
    final dt = DateTime.fromMillisecondsSinceEpoch(m.timestamp);
    return '${_formatTimestamp(dt)} • $sender';
  }

  void _openMedia(GroupChatMessage message) {
    if (message.mediaMetadata == null) {
      if (message.message.isNotEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message.message)));
      }
      return;
    }

    final meta = message.mediaMetadata!;
    final mime = meta.mimeType ?? '';
    final publicUrl = meta.publicUrl;

    if (mime.startsWith('image/')) {
      _showImagePreview(publicUrl, meta);
      return;
    }

    if (mime == 'application/pdf') {
      _openPDFWithExternalApp(
        publicUrl,
        meta.originalFileName ?? 'Document.pdf',
      );
      return;
    }

    if (mime.startsWith('audio/')) {
      _showAudioPlayer(publicUrl, meta);
      return;
    }

    _handleFileDownload(publicUrl, meta.originalFileName ?? 'File');
  }

  void _handleFileDownload(String url, String fileName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Opening $fileName...'),
        action: SnackBarAction(
          label: 'Copy URL',
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('URL copied to clipboard')),
            );
          },
        ),
      ),
    );
  }

  Future<void> _showImagePreview(String publicUrl, dynamic meta) async {
    try {
      String? localPath;
      try {
        final mediaId = meta.mediaId ?? '';
        if (mediaId.isNotEmpty) {
          final cachedMedia = LocalCacheService().getCachedMediaMetadata(
            mediaId,
          );
          if (cachedMedia != null && cachedMedia['localPath'] != null) {
            final localFile = File(cachedMedia['localPath']);
            if (await localFile.exists()) {
              localPath = cachedMedia['localPath'];
            }
          }
        }
      } catch (e) {}

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: InteractiveViewer(
                  child: localPath != null
                      ? Image.file(
                          File(localPath),
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) =>
                              Image.network(publicUrl, fit: BoxFit.contain),
                        )
                      : Image.network(
                          publicUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Text(
                              'Failed to load image',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => Dialog(
            backgroundColor: Colors.transparent,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: InteractiveViewer(
                    child: Image.network(publicUrl, fit: BoxFit.contain),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      }
    }
  }

  Future<void> _showAudioPlayer(String publicUrl, dynamic meta) async {
    try {
      String audioUrl = publicUrl;
      try {
        final mediaId = meta.mediaId ?? '';
        if (mediaId.isNotEmpty) {
          final cachedMedia = LocalCacheService().getCachedMediaMetadata(
            mediaId,
          );
          if (cachedMedia != null && cachedMedia['localPath'] != null) {
            final localFile = File(cachedMedia['localPath']);
            if (await localFile.exists()) {
              audioUrl = cachedMedia['localPath'];
            }
          }
        }
      } catch (e) {}

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        builder: (ctx) => AudioPlayerModal(
          audioUrl: audioUrl,
          fileName: meta.originalFileName ?? 'Audio',
        ),
      );
    } catch (e) {
      print('Error showing audio player: $e');
    }
  }

  Future<void> _openPDFWithExternalApp(String url, String fileName) async {
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 12),
                Text('Preparing PDF...'),
              ],
            ),
            duration: Duration(seconds: 30),
          ),
        );
      }

      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final cleanFileName = fileName.replaceAll(RegExp(r'[^\w\s\-\.]'), '_');
      final finalFileName = cleanFileName.endsWith('.pdf')
          ? cleanFileName
          : '$cleanFileName.pdf';
      final filePath = '${tempDir.path}/${timestamp}_$finalFileName';

      final dio = Dio();
      await dio.download(url, filePath);

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }

      final result = await OpenFilex.open(filePath, type: 'application/pdf');

      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status: ${result.message}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new,
            size: 20,
            color: theme.iconTheme.color,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Search',
            style: TextStyle(
              color: theme.textTheme.bodyLarge?.color,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
            ),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(72),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF0F1419)
                    : theme.colorScheme.surfaceContainerHighest.withOpacity(
                        0.8,
                      ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: theme.primaryColor.withOpacity(0.15),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: theme.primaryColor.withOpacity(0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _queryController,
                      autofocus: true,
                      style: TextStyle(
                        color: theme.textTheme.bodyLarge?.color,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Messages, files, audio...',
                        hintStyle: TextStyle(
                          color: theme.textTheme.bodySmall?.color?.withOpacity(
                            0.4,
                          ),
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        suffixIcon: _queryController.text.isNotEmpty
                            ? Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: IconButton(
                                  icon: Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                    color: theme.textTheme.bodySmall?.color
                                        ?.withOpacity(0.6),
                                  ),
                                  padding: const EdgeInsets.all(4),
                                  splashRadius: 16,
                                  onPressed: () {
                                    _queryController.clear();
                                    _runSearch(reset: true);
                                  },
                                ),
                              )
                            : null,
                      ),
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _runSearch(reset: true),
                      onChanged: (_) => _runSearch(reset: true),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (_queryController.text.trim().length < 2)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.primaryColor.withOpacity(0.1),
                      ),
                      child: Icon(
                        Icons.search_rounded,
                        size: 50,
                        color: theme.primaryColor.withOpacity(0.3),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Search Messages',
                      style: TextStyle(
                        color: theme.textTheme.bodyLarge?.color,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        'Find messages, PDFs, images, or audio files',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: theme.textTheme.bodyMedium?.color?.withOpacity(
                            0.6,
                          ),
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: theme.primaryColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.primaryColor.withOpacity(0.1),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        'Type at least 2 characters',
                        style: TextStyle(
                          color: theme.primaryColor.withOpacity(0.7),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _results.length + (_loading ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= _results.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final message = _results[index];
                  final isMe = message.senderId == widget.currentUserId;

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.pop(context, message),
                        onLongPress: () => _openMedia(message),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withOpacity(0.05)
                                  : theme.dividerColor.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: theme.primaryColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  _iconFor(message),
                                  color: theme.primaryColor,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _primaryText(message),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: theme.textTheme.bodyLarge?.color,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _secondaryText(message),
                                      style: TextStyle(
                                        color: theme.textTheme.bodySmall?.color
                                            ?.withOpacity(0.6),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (isMe)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.primaryColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Icon(
                                    Icons.person,
                                    size: 14,
                                    color: theme.primaryColor.withOpacity(0.7),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          if (_results.isEmpty &&
              !_loading &&
              _queryController.text.trim().length >= 2)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.red.withOpacity(0.1),
                      ),
                      child: Icon(
                        Icons.search_off_rounded,
                        size: 40,
                        color: Colors.red.withOpacity(0.3),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No matches found',
                      style: TextStyle(
                        color: theme.textTheme.bodyLarge?.color,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Try searching with different keywords',
                      style: TextStyle(
                        color: theme.textTheme.bodyMedium?.color?.withOpacity(
                          0.6,
                        ),
                        fontSize: 13,
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

// Audio Player Modal (Bottom Sheet)
class AudioPlayerModal extends StatefulWidget {
  final String audioUrl;
  final String fileName;

  const AudioPlayerModal({
    super.key,
    required this.audioUrl,
    required this.fileName,
  });

  @override
  State<AudioPlayerModal> createState() => _AudioPlayerModalState();
}

class _AudioPlayerModalState extends State<AudioPlayerModal> {
  bool _isPlaying = false;
  final Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[900],
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.audiotrack, size: 80, color: Colors.blue),
          const SizedBox(height: 24),
          Text(
            widget.fileName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                iconSize: 48,
                icon: Icon(
                  _isPlaying ? Icons.pause_circle : Icons.play_circle,
                  color: Colors.blue,
                ),
                onPressed: () {
                  setState(() => _isPlaying = !_isPlaying);
                },
              ),
            ],
          ),
          const SizedBox(height: 32),
          Slider(
            value: _position.inSeconds.toDouble(),
            max: _duration.inSeconds.toDouble() + 1,
            onChanged: (value) {
              setState(() => _position = Duration(seconds: value.toInt()));
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(_position),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                _formatDuration(_duration),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}

// Image Gallery Viewer - Vertical scrollable viewer for grid images
class _ImageGalleryViewer extends StatefulWidget {
  final List<MediaMetadata> mediaList;
  final int initialIndex;
  final Map<String, String> localSenderMediaPaths;
  final bool isMe;

  const _ImageGalleryViewer({
    required this.mediaList,
    required this.initialIndex,
    required this.localSenderMediaPaths,
    required this.isMe,
  });

  @override
  State<_ImageGalleryViewer> createState() => _ImageGalleryViewerState();
}

class _ImageGalleryViewerState extends State<_ImageGalleryViewer> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '${_currentIndex + 1} / ${widget.mediaList.length}',
          style: const TextStyle(color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        itemCount: widget.mediaList.length,
        itemBuilder: (context, index) {
          final metadata = widget.mediaList[index];
          final localPath =
              metadata.localPath ??
              widget.localSenderMediaPaths[metadata.messageId];

          return _buildImageViewer(metadata, localPath);
        },
      ),
    );
  }

  Widget _buildImageViewer(MediaMetadata metadata, String? localPath) {
    // Priority: local file (if it exists) → full network URL → thumbnail → fallback
    Widget imageWidget;

    final file = (localPath != null && localPath.isNotEmpty)
        ? File(localPath)
        : null;
    final hasLocalFile = file != null && file.existsSync();
    final hasNetwork = metadata.publicUrl.isNotEmpty;

    if (hasLocalFile) {
      imageWidget = Image.file(
        file,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => _buildFallbackImage(metadata),
      );
    } else if (hasNetwork) {
      imageWidget = Image.network(
        metadata.publicUrl,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const Center(
            child: SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          );
        },
        errorBuilder: (_, __, ___) => _buildFallbackImage(metadata),
      );
    } else if (metadata.thumbnail.isNotEmpty) {
      // Use thumbnail if available
      if (metadata.thumbnail.startsWith('/')) {
        // Local file path
        imageWidget = Image.file(
          File(metadata.thumbnail),
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => _buildFallbackImage(metadata),
        );
      } else {
        // Base64 thumbnail
        try {
          final bytes = base64Decode(metadata.thumbnail);
          imageWidget = Image.memory(
            bytes,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) => _buildFallbackImage(metadata),
          );
        } catch (e) {
          imageWidget = _buildFallbackImage(metadata);
        }
      }
    } else {
      // Fallback: show download button or URL
      imageWidget = _buildFallbackImage(metadata);
    }

    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 4.0,
      child: Center(child: imageWidget),
    );
  }

  Widget _buildFallbackImage(MediaMetadata metadata) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.image, size: 64, color: Colors.white54),
          const SizedBox(height: 16),
          const Text(
            'Image not available locally',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Text(
            metadata.originalFileName ?? 'image.jpg',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
