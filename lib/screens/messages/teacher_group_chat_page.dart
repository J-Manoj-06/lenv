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
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart' as fcm;
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
import '../../providers/profile_dp_provider.dart';
import '../../providers/unread_count_provider.dart';
import '../../core/constants/app_colors.dart';
import '../../models/user_model.dart';
import '../../widgets/group_avatar_widget.dart';
import '../../widgets/profile_avatar_widget.dart';
import '../../widgets/media_preview_card.dart';
import '../../widgets/modern_attachment_sheet.dart';
import '../../services/connectivity_service.dart';
import '../../services/image_viewer_action_service.dart';
import '../../services/media_availability_service.dart';
import '../../services/media_storage_helper.dart';
import '../../widgets/multi_image_message_bubble.dart';
import '../create_poll_screen.dart';
import '../../widgets/poll_message_widget.dart';
import '../../models/poll_model.dart';
import '../../utils/message_scroll_highlight_mixin.dart';
// OFFLINE-FIRST IMPORTS
import '../../repositories/local_message_repository.dart';
import '../../services/firebase_message_sync_service.dart';
import '../messages/offline_message_search_page.dart';
import 'mindmap_viewer_page.dart';
import 'mindmap_create_page.dart';
import '../../models/forward_message_data.dart';
import 'forward_selection_screen.dart';
import '../../services/active_chat_service.dart';

class TeacherGroupChatPage extends StatefulWidget {
  final String classId;
  final String subjectId;
  final String subjectName;
  final String teacherName;
  final String icon;
  final String? className;
  final String? section;
  final bool isParentGroup; // Flag to indicate if this group includes parents

  const TeacherGroupChatPage({
    super.key,
    required this.classId,
    required this.subjectId,
    required this.subjectName,
    required this.teacherName,
    required this.icon,
    this.className,
    this.section,
    this.isParentGroup = false, // Default to false for teacher-student groups
  });

  @override
  State<TeacherGroupChatPage> createState() => _TeacherGroupChatPageState();
}

class _TeacherGroupChatPageState extends State<TeacherGroupChatPage>
    with MessageScrollAndHighlightMixin {
  Color _getAccentColor(UserRole? role) {
    switch (role) {
      case UserRole.teacher:
        return AppColors.teacherColor;
      case UserRole.student:
        return AppColors.studentColor;
      case UserRole.parent:
        return AppColors.parentColor;
      case UserRole.institute:
      default:
        return AppColors.insightsTeal;
    }
  }

  final GroupMessagingService _messagingService = GroupMessagingService();
  final MediaAvailabilityService _mediaAvailabilityService =
      MediaAvailabilityService();
  final MediaStorageHelper _mediaStorageHelper = MediaStorageHelper();
  final TextEditingController _messageController = TextEditingController();
  String? _lastTopMessageId;
  final FocusNode _messageFocusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();
  late final MediaUploadService _mediaUploadService;

  // OFFLINE-FIRST SERVICES
  late final LocalMessageRepository _localRepo;
  late final FirebaseMessageSyncService _syncService;

  final bool _isUploading = false;
  bool _isRecording = false;
  bool _isOnline = true;
  StreamSubscription<bool>? _connectivitySub;
  final String _uploadingMediaType =
      ''; // Track what type of media is uploading: 'image', 'pdf', 'audio'
  bool _showEmojiPicker = false;
  String? _recordingPath;
  final ValueNotifier<int> _recordingDuration = ValueNotifier<int>(0);
  Timer? _recordingTimer;
  double _slideOffsetX = 0;
  bool _isCancelled = false;
  final Set<String> _selectedMessages = {};
  bool _isSelectionMode = false;
  String? _shareEligibilitySelectionKey;
  Future<bool>? _shareEligibilityFuture;
  String? _forwardEligibilitySelectionKey;
  Future<bool>? _forwardEligibilityFuture;

  // Optimistic UI: pending messages added locally before Firestore confirms
  final List<GroupChatMessage> _pendingMessages = [];
  // Track upload progress per pending messageId
  final Map<String, double> _pendingUploadProgress = {};
  // Track which messages are currently uploading
  final Set<String> _uploadingMessageIds = {};
  // Hide deleted messages immediately while backend deletion completes.
  final Set<String> _optimisticallyDeletedMessageIds = {};
  // Local media paths for the sender (so they view from disk, no re-download)
  final Map<String, String> _localSenderMediaPaths = {};
  // Track upload failures for retry UI
  final Set<String> _failedMessageIds = {};

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

  // ✅ ValueNotifiers for smooth progress updates without full rebuilds
  final Map<String, ValueNotifier<double>> _progressNotifiers = {};

  // ✅ Cached stream to prevent reloading on every rebuild
  late final Stream<List<GroupChatMessage>> _messagesStream;

  // ✅ Message cache for stable instances (reserved for future use)
  // ignore: unused_field
  final Map<String, GroupChatMessage> _messageCache = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cache provider reference to avoid context lookup in dispose
    _unreadRef ??= Provider.of<UnreadCountProvider>(context, listen: false);
  }

  String _buildSelectionKey(Set<String> selectedIds) {
    if (selectedIds.isEmpty) return '';
    final sorted = selectedIds.toList()..sort();
    return sorted.join('|');
  }

  void _invalidateShareEligibilityCache() {
    _shareEligibilitySelectionKey = null;
    _shareEligibilityFuture = null;
    _forwardEligibilitySelectionKey = null;
    _forwardEligibilityFuture = null;
  }

  Future<bool> _getShareEligibilityFuture(Set<String> selectedIds) {
    final nextKey = _buildSelectionKey(selectedIds);
    if (_shareEligibilityFuture != null &&
        _shareEligibilitySelectionKey == nextKey) {
      return _shareEligibilityFuture!;
    }
    _shareEligibilitySelectionKey = nextKey;
    _shareEligibilityFuture = _canShareSelectedMessages(
      Set<String>.from(selectedIds),
    );
    return _shareEligibilityFuture!;
  }

  Future<bool> _getForwardEligibilityFuture(Set<String> selectedIds) {
    final nextKey = _buildSelectionKey(selectedIds);
    if (_forwardEligibilityFuture != null &&
        _forwardEligibilitySelectionKey == nextKey) {
      return _forwardEligibilityFuture!;
    }
    _forwardEligibilitySelectionKey = nextKey;
    _forwardEligibilityFuture = _canForwardSelectedMessages(
      Set<String>.from(selectedIds),
    );
    return _forwardEligibilityFuture!;
  }

  // ===== Pending messages persistence =====
  void _restorePendingMessagesFromCacheSync() {
    try {
      final cacheService = LocalCacheService();
      final cachedMessages = cacheService.getCachedMessages(
        _pendingMessagesCacheKey,
      );

      if (cachedMessages != null && cachedMessages.isNotEmpty) {
        // ✅ CRITICAL: Clear stale state before reload
        _pendingMessages.clear();
        _uploadingMessageIds.clear();
        _pendingUploadProgress.clear();
        _localSenderMediaPaths.clear();

        for (final msgMap in cachedMessages) {
          try {
            // Cast to Map<String, dynamic> safely (Hive returns Map<dynamic, dynamic>)
            final Map<String, dynamic> msgData = Map.from(msgMap);
            // ✅ Ensure consistent pending: prefix
            String msgId = msgData['id'] as String? ?? 'pending:unknown';
            if (!msgId.startsWith('pending:')) {
              msgId = 'pending:$msgId';
            }
            final msg = GroupChatMessage.fromFirestore(msgData, msgId);

            _pendingMessages.add(msg);

            // Restore upload progress for each media item
            if (msg.multipleMedia != null) {
              for (final media in msg.multipleMedia!) {
                // ✅ Only add if not completed (progress < 1.0)
                final progress =
                    0.0; // Default since we don't have stored progress in this cache format
                if (progress < 1.0) {
                  _uploadingMessageIds.add(media.messageId);
                  _pendingUploadProgress[media.messageId] = progress;
                  if (media.localPath != null && media.localPath!.isNotEmpty) {
                    _localSenderMediaPaths[media.messageId] = media.localPath!;
                  }
                  // ✅ Create ValueNotifier for smooth progress
                  _progressNotifiers[media.messageId] = ValueNotifier<double>(
                    progress,
                  );
                }
              }
            }
            if (msg.mediaMetadata != null) {
              // ✅ Only add if not completed
              final progress = 0.0;
              if (progress < 1.0) {
                _uploadingMessageIds.add(msg.mediaMetadata!.messageId);
                _pendingUploadProgress[msg.mediaMetadata!.messageId] = progress;
                if (msg.mediaMetadata!.localPath != null &&
                    msg.mediaMetadata!.localPath!.isNotEmpty) {
                  _localSenderMediaPaths[msg.mediaMetadata!.messageId] =
                      msg.mediaMetadata!.localPath!;
                }
                // ✅ Create ValueNotifier for smooth progress
                _progressNotifiers[msg.mediaMetadata!.messageId] =
                    ValueNotifier<double>(progress);
              }
            }
          } catch (e) {
            // Silently skip individual message restoration errors
          }
        }
      }
    } catch (e) {
      // Silently skip cache restoration errors
    }
  }

  /// Cache pending messages SYNCHRONOUSLY to ensure data persists even on immediate navigation
  void _cachePendingMessages() {
    try {
      final cacheService = LocalCacheService();

      if (_pendingMessages.isNotEmpty) {
        final List<Map<String, dynamic>> messages = _pendingMessages.map((m) {
          final firestore = m.toFirestore();
          firestore['id'] = m.id;
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
          return _stripTimestamps(firestore) as Map<String, dynamic>;
        }).toList();
        cacheService.cacheMessagesSync(
          conversationId: _pendingMessagesCacheKey,
          messages: messages,
        );
      } else {
        cacheService.clearCacheSync(_pendingMessagesCacheKey);
      }
    } catch (e) {
      // Silently ignore cache write errors
    }
  }

  /// Recursively convert Firestore Timestamp to millis (int) to make Hive safe.
  dynamic _stripTimestamps(dynamic value) {
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is DateTime) return value.millisecondsSinceEpoch;
    if (value is List) return value.map(_stripTimestamps).toList();
    if (value is Map) {
      return value.map((k, v) => MapEntry(k, _stripTimestamps(v)));
    }
    return value;
  }

  /// Retry a failed upload: clears the failed flag and re-queues via BackgroundUploadService.
  void _retryUpload(String mediaId) {
    if (!mounted) return;
    setState(() {
      _failedMessageIds.remove(mediaId);
      _uploadingMessageIds.add(mediaId);
      _pendingUploadProgress[mediaId] = 0.0;
      _progressNotifiers[mediaId] = ValueNotifier<double>(0.0);
    });
    BackgroundUploadService().retryUpload(mediaId).catchError((e) {
      if (mounted) {
        setState(() {
          _failedMessageIds.add(mediaId);
          _uploadingMessageIds.remove(mediaId);
          _pendingUploadProgress.remove(mediaId);
        });
      }
    });
  }

  /// Rehydrate any in-flight background uploads into visible pending bubbles.
  Future<void> _hydrateInFlightUploads() async {
    try {
      final uploadService = BackgroundUploadService();
      await uploadService.initialize();

      final conversationId = '${widget.classId}_${widget.subjectId}';
      final uploads = uploadService.uploads
          .where(
            (u) =>
                u.conversationId == conversationId &&
                (u.status == UploadStatus.pending ||
                    u.status == UploadStatus.uploading),
          )
          .toList();

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
    cleanupMessageKeys(currentIds.toList()); // Use mixin's cleanup method

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
      controller: scrollController,
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

        final msgKey = getMessageKey(message.id);
        final isHighlighted = highlightedMessageId == message.id;
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
                onLongPress: () {
                  setState(() {
                    _isSelectionMode = true;
                    _selectedMessages.add(message.id);
                    _invalidateShareEligibilityCache();
                  });
                },
                onTap: _isSelectionMode
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
                          _invalidateShareEligibilityCache();
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
                        classId: widget.classId,
                        subjectId: widget.subjectId,
                        failedMessageIds: _failedMessageIds,
                        onRetry: _retryUpload,
                        key: ValueKey('bubble-${message.id}'),
                      ),
                    ),
                    if (_isSelectionMode)
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

  void _initOfflineFirst() async {
    _localRepo = LocalMessageRepository();
    _syncService = FirebaseMessageSyncService(_localRepo);

    await _localRepo.initialize();

    final chatId = '${widget.classId}_${widget.subjectId}';

    // Load from cache first
    final cachedMessages = await _localRepo.getMessagesForChat(
      chatId,
      limit: 50,
    );

    if (cachedMessages.isEmpty) {
      await _syncService.initialSyncForChat(
        chatId: chatId,
        chatType: 'group',
        limit: 50,
      );
    } else {
      _syncService.syncNewMessages(
        chatId: chatId,
        chatType: 'group',
        lastTimestamp: cachedMessages.first.timestamp,
      );
    }

    // Start real-time sync
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;
    if (currentUser != null) {
      await _syncService.startSyncForChat(
        chatId: chatId,
        chatType: 'group',
        userId: currentUser.uid,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    ActiveChatService().setActiveChat(
      targetType: 'teacher_student_group',
      targetId: '${widget.classId}|${widget.subjectId}',
    );
    _isOnline = ConnectivityService().isOnline;
    _connectivitySub = ConnectivityService().onConnectivityChanged.listen((
      online,
    ) {
      if (mounted) setState(() => _isOnline = online);
    });

    // ✅ Initialize cached messages stream (prevents reloading on rebuild)
    _messagesStream = _messagingService.getGroupMessages(
      widget.classId,
      widget.subjectId,
    );

    // Initialize offline-first services
    _initOfflineFirst();

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
        // ✅ Update ValueNotifier for smooth progress (milestone-based)
        final milestones = [0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0];
        if (_progressNotifiers[messageId] != null) {
          final currentValue = _progressNotifiers[messageId]!.value;
          // Only update on significant changes to prevent excessive redraws
          if ((progress - currentValue).abs() > 0.05 ||
              milestones.any((m) => (progress - m).abs() < 0.01)) {
            _progressNotifiers[messageId]!.value = progress;
          }
        } else if (isUploading) {
          // Create notifier if it doesn't exist
          _progressNotifiers[messageId] = ValueNotifier<double>(progress);
        }

        setState(() {
          if (isUploading) {
            _uploadingMessageIds.add(messageId);
            _pendingUploadProgress[messageId] = progress;
          } else {
            // Upload complete - only remove uploading state, keep pending visible
            // Dedup logic will remove pending when server message arrives
            _uploadingMessageIds.remove(messageId);
            _pendingUploadProgress.remove(messageId);
            // ✅ Dispose ValueNotifier when upload complete
            _progressNotifiers[messageId]?.dispose();
            _progressNotifiers.remove(messageId);
          }
        });
        // Cache progress updates
        _cachePendingMessages();
      }
    };
    uploadService.onUploadProgress = (messageId, isUploading, progress) {
      if (mounted) {
        // ✅ Update ValueNotifier for smooth progress (milestone-based)
        final milestones = [0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0];
        if (_progressNotifiers[messageId] != null) {
          final currentValue = _progressNotifiers[messageId]!.value;
          // Only update on significant changes to prevent excessive redraws
          if ((progress - currentValue).abs() > 0.05 ||
              milestones.any((m) => (progress - m).abs() < 0.01)) {
            _progressNotifiers[messageId]!.value = progress;
          }
        } else if (isUploading) {
          // Create notifier if it doesn't exist
          _progressNotifiers[messageId] = ValueNotifier<double>(progress);
        }

        setState(() {
          if (isUploading) {
            _uploadingMessageIds.add(messageId);
            _pendingUploadProgress[messageId] = progress;
            // Clear failure flag when retrying
            _failedMessageIds.remove(messageId);
          } else {
            _uploadingMessageIds.remove(messageId);
            _pendingUploadProgress.remove(messageId);
            _progressNotifiers[messageId]?.dispose();
            _progressNotifiers.remove(messageId);
            // Detect failure: backend signals failure with progress == 0.0
            if (progress == 0.0) {
              _failedMessageIds.add(messageId);
            } else {
              // Successful upload — clear any previous failure flag
              _failedMessageIds.remove(messageId);
            }
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
      if (currentUser == null) {
        // ✅ OFFLINE FALLBACK: assign a static stream so the late field is always initialized
        _lastReadAtStream = Stream.value(
          Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 30))),
        );
        return;
      }
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

        // Update legacy group doc for backward compatibility.
        // Only teachers have write permission on the subjects document;
        // calling this as a student causes PERMISSION_DENIED.
        if (currentUser.role == UserRole.teacher) {
          await _messagingService.markGroupAsRead(
            widget.classId,
            widget.subjectId,
            currentUser.uid,
          );
        }
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
    ActiveChatService().clearActiveChat(
      targetType: 'teacher_student_group',
      targetId: '${widget.classId}|${widget.subjectId}',
    );
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

    _connectivitySub?.cancel();
    _messageController.dispose();
    disposeScrollController(); // Use mixin's disposal method
    _messageFocusNode.dispose();
    _audioRecorder.dispose();
    _recordingTimer?.cancel();

    // ✅ Dispose all ValueNotifiers
    for (final notifier in _progressNotifiers.values) {
      notifier.dispose();
    }
    _progressNotifiers.clear();

    cleanupMessageKeys([]); // Clear message keys from mixin
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
      if (scrollController.hasClients) {
        // Only auto-scroll if user is at bottom (within 100 pixels) or force is true
        if (force || scrollController.offset < 100) {
          scrollController.jumpTo(0);
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

  void _showOfflineSnackBar({bool isMedia = false}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        padding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        elevation: 0,
        duration: const Duration(seconds: 3),
        content: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2E),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.orange.withOpacity(0.45),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.wifi_off_rounded,
                  color: Colors.orange,
                  size: 19,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'No internet connection',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isMedia
                          ? 'Connect to send media files'
                          : 'Connect to send messages',
                      style: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 12,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.signal_wifi_connected_no_internet_4_rounded,
                color: Colors.orange.withOpacity(0.7),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendMessage({
    String? imageUrl,
    MediaMetadata? mediaMetadata,
  }) async {
    final text = _messageController.text.trim();
    if (text.isEmpty && imageUrl == null && mediaMetadata == null) return;
    if (!_isOnline && imageUrl == null && mediaMetadata == null) {
      _showOfflineSnackBar();
      return;
    }

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
    if (!scrollController.hasClients) return;
    scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  // Remove old scroll/highlight methods - now using mixin

  void _openSearch() {
    final chatId = '${widget.classId}_${widget.subjectId}';

    Navigator.of(context)
        .push<String?>(
          MaterialPageRoute(
            builder: (_) =>
                OfflineMessageSearchPage(chatId: chatId, chatType: 'group'),
          ),
        )
        .then((selectedMessageId) async {
          if (selectedMessageId != null) {
            // Get current messages to pass to scrollToMessage
            final messages = await _messagingService
                .getGroupMessages(widget.classId, widget.subjectId)
                .first;
            if (mounted) {
              await scrollToMessage(
                selectedMessageId,
                messages.map((m) => {'id': m.id}).toList(),
              );
            }
          }
        });
  }

  Future<void> _pickAndSendCamera() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image == null) return;

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
      final file = File(image.path);
      if (!file.existsSync()) return;

      final baseTimestamp = DateTime.now().millisecondsSinceEpoch;
      final groupMessageId =
          'upload_${baseTimestamp}_${currentUserId.hashCode}';
      final messageId = '${groupMessageId}_0';

      // Create pending MediaMetadata with local path for instant preview
      final pendingMetadata = MediaMetadata(
        messageId: messageId,
        r2Key: 'pending/$messageId',
        publicUrl: '',
        thumbnail: file.path,
        localPath: file.path,
        expiresAt: DateTime.now().add(const Duration(days: 30)),
        uploadedAt: DateTime.now(),
        originalFileName: file.path.split('/').last,
        fileSize: await file.length(),
        mimeType: 'image/jpeg',
      );

      // Pending message — appears immediately in chat
      final pendingMessage = GroupChatMessage(
        id: 'pending:$groupMessageId',
        senderId: currentUserId,
        senderName: currentUserName,
        message: '',
        timestamp: baseTimestamp,
        mediaMetadata: pendingMetadata,
      );

      await _bumpLastActivity(baseTimestamp);

      setState(() {
        _pendingMessages.insert(0, pendingMessage);
        _uploadingMessageIds.add(messageId);
        _pendingUploadProgress[messageId] = 0.0;
        _localSenderMediaPaths[messageId] = file.path;
        _progressNotifiers[messageId] = ValueNotifier<double>(0.0);
      });
      _cachePendingMessages();

      // Queue background upload
      await BackgroundUploadService().queueUpload(
        file: file,
        conversationId: conversationId,
        senderId: currentUserId,
        senderRole: 'group',
        mediaType: 'message',
        chatType: 'group',
        senderName: currentUserName,
        messageId: messageId,
        groupId: groupMessageId,
      );

      _scrollToBottom(force: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to capture image: $e')));
      }
    }
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
        allowedExtensions: [
          'pdf',
          'doc',
          'docx',
          'xls',
          'xlsx',
          'ppt',
          'pptx',
          'txt',
          'csv',
          'rtf',
          'odt',
          'ods',
          'odp',
        ],
        withReadStream: true,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;
      final platformFile = result.files.single;
      final file = await _ensureLocalPickedFile(platformFile);

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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Document file not found')),
          );
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
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        withReadStream: true,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;
      final platformFile = result.files.single;
      final file = await _ensureLocalPickedFile(platformFile);

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

  /// Ensure we have a readable local File for a picked PlatformFile.
  Future<File> _ensureLocalPickedFile(PlatformFile platformFile) async {
    if (platformFile.path != null) {
      final f = File(platformFile.path!);
      if (f.existsSync()) return f;
    }
    if (platformFile.readStream == null) {
      throw Exception('Selected file is not accessible');
    }
    final tmpDir = await Directory.systemTemp.createTemp('lenv_attach_');
    final dest = File('${tmpDir.path}/${platformFile.name}');
    final sink = dest.openWrite();
    await platformFile.readStream!.pipe(sink);
    await sink.close();
    return dest;
  }

  Future<void> _recordAndSendAudio() async {
    try {
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

      // Stop recording FIRST
      if (_isRecording) {
        try {
          await _audioRecorder.stop();
        } catch (e) {}
        _recordingTimer?.cancel();
      }

      final recordingPath = _recordingPath;
      if (recordingPath == null) return;

      final file = File(recordingPath);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Recording file not found')),
          );
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
        imageUrl: null,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        mediaMetadata: MediaMetadata(
          messageId: messageId,
          r2Key: 'pending/$messageId',
          publicUrl: '',
          localPath: recordingPath,
          thumbnail: '',
          expiresAt: DateTime.now().add(const Duration(days: 30)),
          uploadedAt: DateTime.now(),
          originalFileName: recordingPath.split('/').last,
          fileSize: await file.length(),
          mimeType: 'audio/aac',
        ),
      );

      await _bumpLastActivity(pendingMessage.timestamp);

      setState(() {
        _isRecording = false;
        _recordingPath = null;
        _recordingDuration.value = 0;
        _slideOffsetX = 0;
        _isCancelled = false;
        _pendingMessages.insert(0, pendingMessage);
        _uploadingMessageIds.add(messageId);
        _pendingUploadProgress[messageId] = 0.0;
        _localSenderMediaPaths[messageId] = recordingPath;
        _progressNotifiers[messageId] = ValueNotifier<double>(0.0);
      });
      _cachePendingMessages();

      // Queue background upload – non-blocking
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

      _scrollToBottom(force: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to queue audio: $e'),
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
                    _invalidateShareEligibilityCache();
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
                : GestureDetector(
                    onTap: () {
                      final authProv = Provider.of<AuthProvider>(
                        context,
                        listen: false,
                      );
                      final isTeacher =
                          authProv.currentUser?.role == UserRole.teacher;
                      final groupId = '${widget.classId}_${widget.subjectId}';
                      // Start watching group DP
                      context.read<ProfileDPProvider>().watchGroupDP(groupId);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GroupInfoScreen(
                            groupId: groupId,
                            groupName: widget.subjectName,
                            subjectName: widget.subjectName,
                            className: widget.className ?? '',
                            section: widget.section,
                            isTeacher: isTeacher,
                            icon: widget.icon,
                          ),
                        ),
                      );
                    },
                    child: Row(
                      children: [
                        GroupAvatarWidget(
                          groupId: '${widget.classId}_${widget.subjectId}',
                          groupName: widget.subjectName,
                          size: 38,
                          icon: widget.icon,
                        ),
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
                                widget.className != null &&
                                        widget.section != null
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
                  ),
            actions: _isSelectionMode
                ? [
                    FutureBuilder<bool>(
                      future: _getForwardEligibilityFuture(_selectedMessages),
                      builder: (context, snapshot) {
                        final canForward = snapshot.data == true;
                        if (!canForward) return const SizedBox.shrink();
                        return IconButton(
                          icon: const Icon(
                            Icons.reply_all_rounded,
                            color: Colors.blueAccent,
                            size: 24,
                          ),
                          tooltip: 'Forward',
                          onPressed: _selectedMessages.isEmpty
                              ? null
                              : _forwardSelectedMessages,
                        );
                      },
                    ),
                    FutureBuilder<bool>(
                      future: _getShareEligibilityFuture(_selectedMessages),
                      builder: (context, snapshot) {
                        final canShare = snapshot.data == true;
                        if (!canShare) return const SizedBox.shrink();
                        return IconButton(
                          icon: const Icon(
                            Icons.share_rounded,
                            color: Colors.white70,
                            size: 24,
                          ),
                          tooltip: 'Share',
                          onPressed: _shareSelectedMessages,
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.redAccent,
                        size: 24,
                      ),
                      tooltip: 'Delete',
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
                  stream: _messagesStream, // ✅ Use cached stream
                  builder: (context, snapshot) {
                    // ✅ CRITICAL: Show pending messages immediately while Firestore loads
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        _pendingMessages.isEmpty) {
                      return Center(
                        child: CircularProgressIndicator(
                          color: AppColors.insightsTeal,
                        ),
                      );
                    }

                    if (snapshot.hasError) {
                      // ✅ Show pending messages even if Firestore has error
                      debugPrint(
                        '❌ Firestore stream error for '
                        '${widget.classId}/${widget.subjectId}: ${snapshot.error}',
                      );
                      if (_pendingMessages.isEmpty) {
                        return Center(
                          child: Text(
                            'Error loading messages',
                            style: TextStyle(color: Colors.white70),
                          ),
                        );
                      }
                      // Continue building with pending messages
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
                        final allMessages = <GroupChatMessage>[
                          ..._pendingMessages,
                          ...messages,
                        ];

                        // SAFETY CHECK: Snapshot uploading IDs before dedup
                        final uploadingMessageIds = <String>{
                          ..._uploadingMessageIds,
                        };

                        // Track which pending messages to remove from state
                        final pendingIdsToRemove = <String>[];

                        // Remove pending messages that now have a corresponding Firestore message
                        allMessages.removeWhere((pendingMsg) {
                          // Only process pending messages
                          if (!pendingMsg.id.startsWith('pending:')) {
                            return false;
                          }

                          // ✅ CRITICAL: Extract actual ID from "pending:upload_..." format
                          final pendingId = pendingMsg.id.replaceFirst(
                            'pending:',
                            '',
                          );

                          // 1️⃣ FIRST: Try exact ID matching (highest priority)
                          bool foundExactMatch = false;
                          for (final fsMsg in messages) {
                            if (fsMsg.id.startsWith('pending:')) continue;

                            // Check if Firestore doc ID matches our pending ID
                            if (fsMsg.id == pendingId) {
                              foundExactMatch = true;
                              break;
                            }
                          }

                          if (foundExactMatch) {
                            // Cleanup pending state
                            if (pendingMsg.multipleMedia != null) {
                              for (final pm in pendingMsg.multipleMedia!) {
                                if (pm.localPath != null &&
                                    pm.localPath!.isNotEmpty) {
                                  _localSenderMediaPaths[pm.messageId] =
                                      pm.localPath!;
                                }
                                _uploadingMessageIds.remove(pm.messageId);
                                _pendingUploadProgress.remove(pm.messageId);
                                _progressNotifiers[pm.messageId]?.dispose();
                                _progressNotifiers.remove(pm.messageId);
                              }
                            }
                            if (pendingMsg.mediaMetadata != null) {
                              final mediaId =
                                  pendingMsg.mediaMetadata!.messageId;
                              if (pendingMsg.mediaMetadata!.localPath != null) {
                                _localSenderMediaPaths[mediaId] =
                                    pendingMsg.mediaMetadata!.localPath!;
                              }
                              _uploadingMessageIds.remove(mediaId);
                              _pendingUploadProgress.remove(mediaId);
                              _progressNotifiers[mediaId]?.dispose();
                              _progressNotifiers.remove(mediaId);
                            }
                            pendingIdsToRemove.add(pendingMsg.id);
                            return true; // Remove pending message
                          }

                          // 2️⃣ FALLBACK: Build a set of media IDs for reliable matching
                          final pendingMediaIds = <String>{};
                          if (pendingMsg.multipleMedia != null) {
                            pendingMediaIds.addAll(
                              pendingMsg.multipleMedia!.map((m) => m.messageId),
                            );
                          }
                          if (pendingMsg.mediaMetadata != null) {
                            pendingMediaIds.add(
                              pendingMsg.mediaMetadata!.messageId,
                            );
                          }

                          // ✅ Add file name matching with case-insensitive comparison
                          final pendingAttachmentKeys = <String>{};
                          if (pendingMsg.mediaMetadata?.originalFileName !=
                                  null &&
                              pendingMsg.mediaMetadata?.fileSize != null) {
                            pendingAttachmentKeys.add(
                              '${pendingMsg.mediaMetadata!.originalFileName!.toLowerCase()}|${pendingMsg.mediaMetadata!.fileSize}',
                            );
                          }
                          if (pendingMsg.multipleMedia != null) {
                            for (final m in pendingMsg.multipleMedia!) {
                              if (m.originalFileName != null &&
                                  m.fileSize != null) {
                                pendingAttachmentKeys.add(
                                  '${m.originalFileName!.toLowerCase()}|${m.fileSize}',
                                );
                              }
                            }
                          }

                          // 3️⃣ Media ID matching
                          final hasMatchingMedia =
                              pendingMediaIds.isNotEmpty &&
                              messages.any((fsMsg) {
                                if (fsMsg.id.startsWith('pending:')) {
                                  return false;
                                }
                                final fsMediaIds = <String>{};
                                if (fsMsg.multipleMedia != null) {
                                  fsMediaIds.addAll(
                                    fsMsg.multipleMedia!.map(
                                      (m) => m.messageId,
                                    ),
                                  );
                                }
                                if (fsMsg.mediaMetadata != null) {
                                  fsMediaIds.add(
                                    fsMsg.mediaMetadata!.messageId,
                                  );
                                }
                                if (fsMediaIds.isEmpty) return false;
                                return fsMediaIds.any(pendingMediaIds.contains);
                              });

                          // 4️⃣ File name matching (case-insensitive)
                          final hasMatchingAttachment =
                              pendingAttachmentKeys.isNotEmpty &&
                              messages.any((fsMsg) {
                                if (fsMsg.id.startsWith('pending:')) {
                                  return false;
                                }
                                final fsAttachmentKeys = <String>{};
                                if (fsMsg.mediaMetadata?.originalFileName !=
                                        null &&
                                    fsMsg.mediaMetadata?.fileSize != null) {
                                  fsAttachmentKeys.add(
                                    '${fsMsg.mediaMetadata!.originalFileName!.toLowerCase()}|${fsMsg.mediaMetadata!.fileSize}',
                                  );
                                }
                                if (fsMsg.multipleMedia != null) {
                                  for (final m in fsMsg.multipleMedia!) {
                                    if (m.originalFileName != null &&
                                        m.fileSize != null) {
                                      fsAttachmentKeys.add(
                                        '${m.originalFileName!.toLowerCase()}|${m.fileSize}',
                                      );
                                    }
                                  }
                                }
                                if (fsAttachmentKeys.isEmpty) return false;
                                return fsAttachmentKeys.any(
                                  pendingAttachmentKeys.contains,
                                );
                              });

                          // 5️⃣ Fallback: match sender + wider time window
                          final hasServerVersion =
                              hasMatchingMedia ||
                              hasMatchingAttachment ||
                              messages.any((fsMsg) {
                                final senderMatch =
                                    fsMsg.senderId == pendingMsg.senderId;
                                final diff =
                                    (fsMsg.timestamp - pendingMsg.timestamp)
                                        .abs();
                                // ✅ Extended time window for single attachments (5 minutes)
                                final timeWindow =
                                    pendingMsg.mediaMetadata != null
                                    ? 300000
                                    : 30000;
                                final timeMatch = diff < timeWindow;
                                final isNotPending = !fsMsg.id.startsWith(
                                  'pending:',
                                );
                                return senderMatch && timeMatch && isNotPending;
                              });

                          if (hasServerVersion) {
                            // Preserve local paths before removing
                            if (pendingMsg.multipleMedia != null) {
                              for (final pm in pendingMsg.multipleMedia!) {
                                if (pm.localPath != null &&
                                    pm.localPath!.isNotEmpty) {
                                  _localSenderMediaPaths[pm.messageId] =
                                      pm.localPath!;
                                }
                                _uploadingMessageIds.remove(pm.messageId);
                                _pendingUploadProgress.remove(pm.messageId);
                                // ✅ Dispose ValueNotifiers
                                _progressNotifiers[pm.messageId]?.dispose();
                                _progressNotifiers.remove(pm.messageId);
                              }
                            }
                            if (pendingMsg.mediaMetadata?.localPath != null) {
                              _localSenderMediaPaths[pendingMsg
                                      .mediaMetadata!
                                      .messageId] =
                                  pendingMsg.mediaMetadata!.localPath!;
                            }
                            if (pendingMsg.mediaMetadata != null) {
                              final mediaId =
                                  pendingMsg.mediaMetadata!.messageId;
                              _uploadingMessageIds.remove(mediaId);
                              _pendingUploadProgress.remove(mediaId);
                              // ✅ Dispose ValueNotifiers
                              _progressNotifiers[mediaId]?.dispose();
                              _progressNotifiers.remove(mediaId);
                            }

                            // Track for state removal
                            pendingIdsToRemove.add(pendingMsg.id);
                            return true; // Remove from merged list
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
                              return false; // Keep it
                            }
                          } else if (pendingMsg.mediaMetadata != null) {
                            if (uploadingMessageIds.contains(
                              pendingMsg.mediaMetadata!.messageId,
                            )) {
                              return false; // Keep it
                            }
                          }

                          return false; // Keep in merged list
                        });

                        // Remove confirmed messages from _pendingMessages state
                        if (pendingIdsToRemove.isNotEmpty) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            setState(() {
                              _pendingMessages.removeWhere(
                                (m) => pendingIdsToRemove.contains(m.id),
                              );
                            });
                            // Persist updated pending list
                            _cachePendingMessages();
                          });
                        }

                        // Immediately hide messages queued for deletion.
                        allMessages.removeWhere(
                          (msg) =>
                              _optimisticallyDeletedMessageIds.contains(msg.id),
                        );

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
    final isTeacher = currentUser?.role == UserRole.teacher;

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
              ? const Color(0xFF355872) // Teacher color
              : const Color(0xFFFFB380)) // Soft muted orange for students
        : (isTeacher
              ? const Color(0xFF355872) // Teacher color
              : const Color(0xFFFF8F00)); // Orange for students

    final iconDisabledColor = isDark
        ? const Color(0xFF3A3A3C)
        : const Color(0xFFBBBBBB);

    final accentColor = isTeacher
        ? const Color(0xFF355872) // Teacher color
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
    if (!_isOnline) {
      _showOfflineSnackBar(isMedia: true);
      return;
    }
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final isTeacher = authProvider.currentUser?.role == UserRole.teacher;

    // ✅ Only enable mindmap for teachers in student groups (not parent groups)
    final mindmapEnabled = isTeacher && !widget.isParentGroup;

    final accentColor = _getAccentColor(authProvider.currentUser?.role);
    showModernAttachmentSheet(
      context,
      onCameraTap: _pickAndSendCamera,
      onImageTap: _pickAndSendImage,
      onDocumentTap: _pickAndSendPDF,
      onAudioTap: _pickAndSendAudio,
      onPollTap: _navigateToPollScreen,
      onMindmapTap: mindmapEnabled ? _openMindmapGenerator : null,
      mindmapEnabled: mindmapEnabled,
      color: accentColor,
    );
  }

  Future<void> _openMindmapGenerator() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;
    if (currentUser == null || currentUser.role != UserRole.teacher) {
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: '/teacher/group/mindmap/create'),
        builder: (_) => MindmapCreatePage(
          classId: widget.classId,
          subjectId: widget.subjectId,
          teacherId: currentUser.uid,
          teacherName: currentUser.name,
          subjectName: widget.subjectName,
          className: widget.className ?? '',
          section: widget.section ?? '',
          onMindmapSent: () {
            if (mounted) {
              _scrollToLatest();
            }
          },
        ),
      ),
    );
  }

  void _navigateToPollScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/create_poll'),
        builder: (context) => CreatePollScreen(
          chatId: '${widget.classId}_${widget.subjectId}',
          chatType: 'group',
        ),
      ),
    );
  }

  Future<void> _deleteMessages(bool deleteForEveryone) async {
    final messagesToDelete = _selectedMessages.toList();
    if (messagesToDelete.isEmpty) return;

    final selectedSnapshot = Set<String>.from(messagesToDelete);
    setState(() {
      _optimisticallyDeletedMessageIds.addAll(selectedSnapshot);
      _selectedMessages.clear();
      _isSelectionMode = false;
      _invalidateShareEligibilityCache();
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUserId = authProvider.currentUser?.uid;
      if (currentUserId == null) {
        throw Exception('User not found');
      }

      // Collect all R2 keys to delete (deduplication)
      final mediaToDelete = <String>{};
      final validMessages = <String>[];
      final invalidMessages = <String>[];

      // First pass: Verify ownership and collect media keys
      for (final messageId in messagesToDelete) {
        final messageRef = FirebaseFirestore.instance
            .collection('classes')
            .doc(widget.classId)
            .collection('subjects')
            .doc(widget.subjectId)
            .collection('messages')
            .doc(messageId);

        final docSnapshot = await messageRef.get();
        if (!docSnapshot.exists) continue;

        final data = docSnapshot.data();
        final senderId = data?['senderId'] as String?;

        if (senderId == null || senderId != currentUserId) {
          invalidMessages.add(messageId);
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

        validMessages.add(messageId);

        // Extract R2 keys from mediaMetadata (primary source)
        final mediaMetadata = data?['mediaMetadata'] as Map<String, dynamic>?;
        if (mediaMetadata != null) {
          final r2Key = mediaMetadata['r2Key'] as String?;
          if (r2Key != null && r2Key.isNotEmpty) {
            mediaToDelete.add(r2Key);
          }

          final thumbnailKey = mediaMetadata['thumbnailR2Key'] as String?;
          if (thumbnailKey != null && thumbnailKey.isNotEmpty) {
            mediaToDelete.add(thumbnailKey);
          }
        }

        // Extract from multipleMedia array
        final multipleMedia = data?['multipleMedia'] as List<dynamic>?;
        if (multipleMedia != null) {
          for (final media in multipleMedia) {
            if (media is Map<String, dynamic>) {
              final r2Key = media['r2Key'] as String?;
              if (r2Key != null && r2Key.isNotEmpty) {
                mediaToDelete.add(r2Key);
              }

              final thumbnailKey = media['thumbnailR2Key'] as String?;
              if (thumbnailKey != null && thumbnailKey.isNotEmpty) {
                mediaToDelete.add(thumbnailKey);
              }
            }
          }
        }

        // Extract from legacy imageUrl field
        final imageUrl = data?['imageUrl'] as String?;
        if (imageUrl != null && imageUrl.isNotEmpty) {
          try {
            final uri = Uri.parse(imageUrl);
            final path = uri.path;
            final key = path.startsWith('/') ? path.substring(1) : path;
            if (key.isNotEmpty && !mediaToDelete.contains(key)) {
              mediaToDelete.add(key);
            }
          } catch (e) {
            // Invalid URL, skip
          }
        }
      }

      if (invalidMessages.isNotEmpty && mounted) {
        setState(() {
          _optimisticallyDeletedMessageIds.removeAll(invalidMessages);
        });
      }

      if (validMessages.isEmpty) {
        return;
      }

      // Update messages first so they disappear from all clients quickly.
      final batch = FirebaseFirestore.instance.batch();
      for (final messageId in validMessages) {
        final messageRef = FirebaseFirestore.instance
            .collection('classes')
            .doc(widget.classId)
            .collection('subjects')
            .doc(widget.subjectId)
            .collection('messages')
            .doc(messageId);

        batch.update(messageRef, {
          'isDeleted': true,
          'message': '',
          'mediaMetadata': FieldValue.delete(),
          'multipleMedia': FieldValue.delete(),
          'imageUrl': FieldValue.delete(),
        });
      }

      await batch.commit();

      // Delete media files from R2 in background so UI is not blocked.
      if (mediaToDelete.isNotEmpty) {
        unawaited(_deleteMediaFiles(mediaToDelete.toList()));
      }

      Future.delayed(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() {
          _optimisticallyDeletedMessageIds.removeAll(validMessages);
        });
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
        setState(() {
          _optimisticallyDeletedMessageIds.removeAll(selectedSnapshot);
        });
      }
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

  /// Delete media files from R2 storage with detailed logging
  Future<void> _deleteMediaFiles(List<String> keys) async {
    if (keys.isEmpty) return;

    try {
      final r2Service = CloudflareR2Service(
        accountId: CloudflareConfig.accountId,
        bucketName: CloudflareConfig.bucketName,
        accessKeyId: CloudflareConfig.accessKeyId,
        secretAccessKey: CloudflareConfig.secretAccessKey,
        r2Domain: CloudflareConfig.r2Domain,
      );

      int successCount = 0;
      for (final key in keys) {
        try {
          await r2Service.deleteFile(key: key);
          successCount++;
        } catch (e) {
          // Continue with next file
        }
      }
    } catch (e) {}
  }

  // ─── Forward selected messages ────────────────────────────────────────────
  Future<void> _forwardSelectedMessages() async {
    final ids = _selectedMessages.toList();
    if (ids.isEmpty) return;

    setState(() {
      _isSelectionMode = false;
      _selectedMessages.clear();
      _invalidateShareEligibilityCache();
    });

    final forwardData = <ForwardMessageData>[];
    for (final id in ids) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('classes')
            .doc(widget.classId)
            .collection('subjects')
            .doc(widget.subjectId)
            .collection('messages')
            .doc(id)
            .get();
        if (!doc.exists) continue;
        final data = doc.data()!;
        final msg = GroupChatMessage.fromFirestore(data, id);
        forwardData.add(
          ForwardMessageData.fromRaw(
            messageId: id,
            senderId: data['senderId'] as String? ?? '',
            senderName: data['senderName'] as String? ?? '',
            rawData: data,
            imageUrl: msg.imageUrl,
            message: msg.message,
            mediaMetadata: msg.mediaMetadata,
            multipleMedia: msg.multipleMedia,
          ),
        );
      } catch (_) {}
    }

    if (forwardData.isEmpty || !mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ForwardSelectionScreen(messages: forwardData),
      ),
    );
  }

  Future<String?> _resolveDownloadedLocalPath(
    Map<String, dynamic> media,
  ) async {
    final directPath = media['localPath'] as String?;
    if (directPath != null && directPath.isNotEmpty) {
      final file = File(directPath);
      if (await file.exists()) return directPath;
    }

    final urlCandidates = <String?>[
      media['publicUrl'] as String?,
      media['url'] as String?,
      media['imageUrl'] as String?,
      media['attachmentUrl'] as String?,
      media['downloadUrl'] as String?,
      media['fileUrl'] as String?,
    ];

    final keyCandidates = <String?>[
      media['r2Key'] as String?,
      media['key'] as String?,
      media['mediaKey'] as String?,
      media['path'] as String?,
    ];

    final normalizedKeys = <String>{};

    void addKeyCandidate(String? raw) {
      if (raw == null || raw.trim().isEmpty) return;
      final trimmed = raw.trim();
      normalizedKeys.add(trimmed);

      var noLeadingSlash = trimmed;
      while (noLeadingSlash.startsWith('/')) {
        noLeadingSlash = noLeadingSlash.substring(1);
      }
      if (noLeadingSlash.isNotEmpty) normalizedKeys.add(noLeadingSlash);

      final uri = Uri.tryParse(trimmed);
      if (uri != null && uri.path.isNotEmpty) {
        var path = uri.path;
        while (path.startsWith('/')) {
          path = path.substring(1);
        }
        if (path.isNotEmpty) {
          normalizedKeys.add(path);
          final decoded = Uri.decodeFull(path);
          if (decoded.isNotEmpty) normalizedKeys.add(decoded);
          final slashIndex = path.indexOf('/');
          if (slashIndex > 0 && slashIndex < path.length - 1) {
            normalizedKeys.add(path.substring(slashIndex + 1));
          }
        }
      }
    }

    for (final key in keyCandidates) {
      addKeyCandidate(key);
    }
    for (final url in urlCandidates) {
      addKeyCandidate(url);
    }

    for (final key in normalizedKeys) {
      final path = await _mediaAvailabilityService.getCachedFilePath(key);
      if (path != null && path.isNotEmpty) return path;
    }

    final fileName = media['originalFileName'] as String?;
    if (fileName != null && fileName.isNotEmpty) {
      final all = await _mediaStorageHelper.getAllMediaMetadata();
      for (final entry in all.values) {
        if (entry.fileName == fileName) {
          final file = File(entry.localPath);
          if (await file.exists()) return entry.localPath;
        }
      }
    }

    for (final url in urlCandidates) {
      if (url == null || url.isEmpty) continue;
      final cached = await fcm.DefaultCacheManager().getFileFromCache(url);
      final file = cached?.file;
      if (file != null && await file.exists()) {
        return file.path;
      }
    }

    return null;
  }

  Future<bool> _canShareSelectedMessages(Set<String> selectedIds) async {
    if (selectedIds.isEmpty) return false;

    final items = <ShareMediaItem>[];

    for (final id in selectedIds) {
      final doc = await FirebaseFirestore.instance
          .collection('classes')
          .doc(widget.classId)
          .collection('subjects')
          .doc(widget.subjectId)
          .collection('messages')
          .doc(id)
          .get();
      if (!doc.exists) return false;

      final data = doc.data()!;
      final mediaMetaRaw = data['mediaMetadata'];
      final imageUrl = data['imageUrl'] as String?;
      final attachmentUrl = data['attachmentUrl'] as String?;
      final fileUrl = data['fileUrl'] as String?;
      final hasLegacyMediaUrl =
          (imageUrl != null && imageUrl.isNotEmpty) ||
          (attachmentUrl != null && attachmentUrl.isNotEmpty) ||
          (fileUrl != null && fileUrl.isNotEmpty);
      if (mediaMetaRaw is Map) {
        final media = Map<String, dynamic>.from(mediaMetaRaw);
        String? localPath = await _resolveDownloadedLocalPath(media);
        if (localPath == null && hasLegacyMediaUrl) {
          final fallbackMedia = <String, dynamic>{
            ...media,
            'localPath': data['localPath'] ?? media['localPath'],
            'publicUrl': imageUrl ?? attachmentUrl ?? fileUrl,
            'imageUrl': imageUrl,
            'attachmentUrl': attachmentUrl,
            'fileUrl': fileUrl,
            'originalFileName':
                media['originalFileName'] ??
                data['attachmentName'] ??
                data['fileName'],
            'mimeType':
                media['mimeType'] ?? data['attachmentType'] ?? data['mimeType'],
          };
          localPath = await _resolveDownloadedLocalPath(fallbackMedia);
        }
        if (localPath == null) return false;
        items.add(
          ShareMediaItem(
            localPath: localPath,
            fileName: media['originalFileName'] as String?,
            mimeType: media['mimeType'] as String?,
          ),
        );
      }

      final multipleMediaRaw = data['multipleMedia'];
      if (multipleMediaRaw is List && multipleMediaRaw.isNotEmpty) {
        for (final m in multipleMediaRaw) {
          if (m is! Map) continue;
          final media = Map<String, dynamic>.from(m);
          final localPath = await _resolveDownloadedLocalPath(media);
          if (localPath == null) return false;
          items.add(
            ShareMediaItem(
              localPath: localPath,
              fileName: media['originalFileName'] as String?,
              mimeType: media['mimeType'] as String?,
            ),
          );
        }
      }

      if (mediaMetaRaw is! Map &&
          !((multipleMediaRaw is List) && multipleMediaRaw.isNotEmpty) &&
          hasLegacyMediaUrl) {
        final legacyMedia = <String, dynamic>{
          'localPath': data['localPath'],
          'publicUrl': imageUrl ?? attachmentUrl ?? fileUrl,
          'originalFileName': data['attachmentName'] ?? data['fileName'],
          'mimeType': data['attachmentType'] ?? data['mimeType'],
          'imageUrl': imageUrl,
          'attachmentUrl': attachmentUrl,
          'fileUrl': fileUrl,
        };
        final localPath = await _resolveDownloadedLocalPath(legacyMedia);
        if (localPath == null) return false;
        items.add(
          ShareMediaItem(
            localPath: localPath,
            fileName: legacyMedia['originalFileName'] as String?,
            mimeType: legacyMedia['mimeType'] as String?,
          ),
        );
      }
    }

    return items.isNotEmpty;
  }

  Future<bool> _canForwardSelectedMessages(Set<String> selectedIds) async {
    if (selectedIds.isEmpty) return false;

    for (final id in selectedIds) {
      final doc = await FirebaseFirestore.instance
          .collection('classes')
          .doc(widget.classId)
          .collection('subjects')
          .doc(widget.subjectId)
          .collection('messages')
          .doc(id)
          .get();
      if (!doc.exists) return false;

      final data = doc.data()!;
      final mediaMetaRaw = data['mediaMetadata'];
      final multipleMediaRaw = data['multipleMedia'];
      final imageUrl = data['imageUrl'] as String?;
      final attachmentUrl = data['attachmentUrl'] as String?;
      final fileUrl = data['fileUrl'] as String?;
      final hasLegacyMediaUrl =
          (imageUrl != null && imageUrl.isNotEmpty) ||
          (attachmentUrl != null && attachmentUrl.isNotEmpty) ||
          (fileUrl != null && fileUrl.isNotEmpty);

      if (mediaMetaRaw is Map) {
        final media = Map<String, dynamic>.from(mediaMetaRaw);
        String? localPath = await _resolveDownloadedLocalPath(media);
        if (localPath == null && hasLegacyMediaUrl) {
          final fallbackMedia = <String, dynamic>{
            ...media,
            'localPath': data['localPath'] ?? media['localPath'],
            'publicUrl': imageUrl ?? attachmentUrl ?? fileUrl,
            'imageUrl': imageUrl,
            'attachmentUrl': attachmentUrl,
            'fileUrl': fileUrl,
            'originalFileName':
                media['originalFileName'] ??
                data['attachmentName'] ??
                data['fileName'],
            'mimeType':
                media['mimeType'] ?? data['attachmentType'] ?? data['mimeType'],
          };
          localPath = await _resolveDownloadedLocalPath(fallbackMedia);
        }
        if (localPath == null) return false;
      }

      if (multipleMediaRaw is List && multipleMediaRaw.isNotEmpty) {
        for (final m in multipleMediaRaw) {
          if (m is! Map) continue;
          final media = Map<String, dynamic>.from(m);
          final localPath = await _resolveDownloadedLocalPath(media);
          if (localPath == null) return false;
        }
      }

      if (mediaMetaRaw is! Map &&
          !((multipleMediaRaw is List) && multipleMediaRaw.isNotEmpty) &&
          hasLegacyMediaUrl) {
        final legacyMedia = <String, dynamic>{
          'localPath': data['localPath'],
          'publicUrl': imageUrl ?? attachmentUrl ?? fileUrl,
          'originalFileName': data['attachmentName'] ?? data['fileName'],
          'mimeType': data['attachmentType'] ?? data['mimeType'],
          'imageUrl': imageUrl,
          'attachmentUrl': attachmentUrl,
          'fileUrl': fileUrl,
        };
        final localPath = await _resolveDownloadedLocalPath(legacyMedia);
        if (localPath == null) return false;
      }
    }

    return true;
  }

  Future<void> _shareSelectedMessages() async {
    final ids = _selectedMessages.toList();
    if (ids.isEmpty) return;

    final items = <ShareMediaItem>[];

    for (final id in ids) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('classes')
            .doc(widget.classId)
            .collection('subjects')
            .doc(widget.subjectId)
            .collection('messages')
            .doc(id)
            .get();
        if (!doc.exists) continue;
        final data = doc.data()!;

        final mediaMetaRaw = data['mediaMetadata'];
        final imageUrl = data['imageUrl'] as String?;
        final attachmentUrl = data['attachmentUrl'] as String?;
        final fileUrl = data['fileUrl'] as String?;
        final hasLegacyMediaUrl =
            (imageUrl != null && imageUrl.isNotEmpty) ||
            (attachmentUrl != null && attachmentUrl.isNotEmpty) ||
            (fileUrl != null && fileUrl.isNotEmpty);
        if (mediaMetaRaw is Map) {
          final media = Map<String, dynamic>.from(mediaMetaRaw);
          String? localPath = await _resolveDownloadedLocalPath(media);
          if (localPath == null && hasLegacyMediaUrl) {
            final fallbackMedia = <String, dynamic>{
              ...media,
              'localPath': data['localPath'] ?? media['localPath'],
              'publicUrl': imageUrl ?? attachmentUrl ?? fileUrl,
              'imageUrl': imageUrl,
              'attachmentUrl': attachmentUrl,
              'fileUrl': fileUrl,
              'originalFileName':
                  media['originalFileName'] ??
                  data['attachmentName'] ??
                  data['fileName'],
              'mimeType':
                  media['mimeType'] ??
                  data['attachmentType'] ??
                  data['mimeType'],
            };
            localPath = await _resolveDownloadedLocalPath(fallbackMedia);
          }
          if (localPath == null) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Download selected media first to share'),
              ),
            );
            return;
          }

          items.add(
            ShareMediaItem(
              localPath: localPath,
              fileName: media['originalFileName'] as String?,
              mimeType: media['mimeType'] as String?,
            ),
          );
        }

        final multipleMediaRaw = data['multipleMedia'];
        if (multipleMediaRaw is List && multipleMediaRaw.isNotEmpty) {
          for (final m in multipleMediaRaw) {
            if (m is! Map) continue;
            final media = Map<String, dynamic>.from(m);
            final localPath = await _resolveDownloadedLocalPath(media);
            if (localPath == null) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Download selected media first to share'),
                ),
              );
              return;
            }

            items.add(
              ShareMediaItem(
                localPath: localPath,
                fileName: media['originalFileName'] as String?,
                mimeType: media['mimeType'] as String?,
              ),
            );
          }
        }

        if (mediaMetaRaw is! Map &&
            !((multipleMediaRaw is List) && multipleMediaRaw.isNotEmpty) &&
            hasLegacyMediaUrl) {
          final legacyMedia = <String, dynamic>{
            'localPath': data['localPath'],
            'publicUrl': imageUrl ?? attachmentUrl ?? fileUrl,
            'originalFileName': data['attachmentName'] ?? data['fileName'],
            'mimeType': data['attachmentType'] ?? data['mimeType'],
            'imageUrl': imageUrl,
            'attachmentUrl': attachmentUrl,
            'fileUrl': fileUrl,
          };
          final localPath = await _resolveDownloadedLocalPath(legacyMedia);
          if (localPath == null) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Download selected media first to share'),
              ),
            );
            return;
          }
          items.add(
            ShareMediaItem(
              localPath: localPath,
              fileName: legacyMedia['originalFileName'] as String?,
              mimeType: legacyMedia['mimeType'] as String?,
            ),
          );
        }
      } catch (_) {}
    }

    if (items.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select media messages to share')),
      );
      return;
    }

    final ok = await ImageViewerActionService.shareMediaFiles(
      items: items,
      text: items.length > 1 ? 'Shared from New Reward' : null,
      requireLocalOnly: true,
    );

    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Android share failed')));
      return;
    }

    setState(() {
      _isSelectionMode = false;
      _selectedMessages.clear();
      _invalidateShareEligibilityCache();
    });
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
  final String classId;
  final String subjectId;
  final Set<String> failedMessageIds;
  final void Function(String)? onRetry;

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
    required this.classId,
    required this.subjectId,
    required this.failedMessageIds,
    this.onRetry,
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
          // Sender avatar for received messages
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 6),
              child: ChatSenderAvatarWidget(
                senderId: message.senderId,
                senderName: message.senderName,
                size: 32,
              ),
            ),
          // Message Content
          Flexible(
            child: Container(
              margin: EdgeInsets.only(
                left: isMe ? 32 : 0,
                right: isMe ? 0 : 32,
              ),
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
                  // ── Forwarded label ───────────────────────────────────────
                  if (message.rawData?['forwarded'] == true)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.reply_all_rounded,
                            size: 12,
                            color: const Color(0xFFFFA929).withOpacity(0.8),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Forwarded',
                            style: TextStyle(
                              fontSize: 11,
                              color: const Color(0xFFFFA929).withOpacity(0.8),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Check if this is a poll message - render it outside the bubble
                  if (message.type == 'poll')
                    SizedBox(
                      width: double.infinity,
                      child: Align(
                        alignment: isMe
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: PollMessageWidget(
                          poll: PollModel.fromMap(message.toMap(), message.id),
                          chatId: '${classId}_$subjectId',
                          chatType: 'group',
                          isOwnMessage: isMe,
                        ),
                      ),
                    )
                  else if (message.type == 'mindmap')
                    _MindmapMessageCard(
                      isMe: isMe,
                      mindmapId: (message.rawData?['mindmapId'] ?? '')
                          .toString(),
                      topic:
                          (message.rawData?['mindmapTopic'] ??
                                  message.message.replaceFirst('Mindmap: ', ''))
                              .toString(),
                      previewNodes:
                          (message.rawData?['previewNodes'] as List?)
                              ?.map((e) => e.toString())
                              .toList() ??
                          const [],
                    )
                  // Multiple media handling (WhatsApp-style grid) - NO outer bubble
                  else if (message.multipleMedia != null &&
                      message.multipleMedia!.isNotEmpty)
                    Column(
                      crossAxisAlignment: isMe
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_hasOnlyImageMedia(message.multipleMedia!))
                          MultiImageMessageBubble(
                            imageUrls: message.multipleMedia!
                                .map((m) => m.localPath ?? m.publicUrl)
                                .toList(),
                            isMe: isMe,
                            uploadProgress: message.multipleMedia!
                                .map((m) => pendingUploadProgress[m.messageId])
                                .toList(),
                            userRole: Provider.of<AuthProvider>(
                              context,
                              listen: false,
                            ).currentUser?.role.toString().split('.').last,
                            onImageTap: (index, cachedPaths) async {
                              final updatedMediaList = <MediaMetadata>[];
                              for (
                                int i = 0;
                                i < message.multipleMedia!.length;
                                i++
                              ) {
                                final media = message.multipleMedia![i];
                                updatedMediaList.add(
                                  MediaMetadata(
                                    localPath:
                                        cachedPaths[i] ?? media.localPath,
                                    publicUrl: media.publicUrl,
                                    messageId: media.messageId,
                                    mimeType: media.mimeType,
                                    fileSize: media.fileSize,
                                    r2Key: media.r2Key,
                                    thumbnail: media.thumbnail,
                                    expiresAt: media.expiresAt,
                                    uploadedAt: media.uploadedAt,
                                  ),
                                );
                              }

                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => _ImageGalleryViewer(
                                    mediaList: updatedMediaList,
                                    initialIndex: index,
                                    localSenderMediaPaths:
                                        localSenderMediaPaths,
                                    isMe: isMe,
                                    forwardMessage: _buildForwardData(),
                                  ),
                                ),
                              );
                            },
                          )
                        else
                          _buildMixedMediaAttachments(
                            context,
                            message.multipleMedia!,
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
                          // Zero padding for media-only bubbles — let the card fill naturally
                          horizontal:
                              (message.mediaMetadata != null ||
                                      message.imageUrl != null) &&
                                  message.message.isEmpty
                              ? 0
                              : 14,
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
                              _buildLegacyAttachment(
                                context,
                                message.imageUrl!,
                              ),
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

    final isFailed = failedMessageIds.contains(metadata.messageId);
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
      failed: isFailed,
      onRetry: isFailed ? () => onRetry?.call(metadata.messageId) : null,
      forwardMessage: _buildForwardData(),
    );
  }

  bool _hasOnlyImageMedia(List<MediaMetadata> mediaList) {
    if (mediaList.isEmpty) return false;
    return mediaList.every(
      (media) => (media.mimeType ?? '').toLowerCase().startsWith('image/'),
    );
  }

  Widget _buildMixedMediaAttachments(
    BuildContext context,
    List<MediaMetadata> mediaList,
  ) {
    return Column(
      crossAxisAlignment: isMe
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < mediaList.length; i++) ...[
          _buildMetadataAttachment(context, mediaList[i]),
          if (i != mediaList.length - 1) const SizedBox(height: 6),
        ],
      ],
    );
  }

  ForwardMessageData _buildForwardData() {
    return ForwardMessageData.fromRaw(
      messageId: message.id,
      senderId: message.senderId,
      senderName: message.senderName,
      rawData: message.rawData,
      imageUrl: message.imageUrl,
      message: message.message,
      mediaMetadata: message.mediaMetadata,
      multipleMedia: message.multipleMedia,
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
                              forwardMessage: _buildForwardData(),
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
                    forwardMessage: _buildForwardData(),
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
      forwardMessage: _buildForwardData(),
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

class _MindmapMessageCard extends StatelessWidget {
  final bool isMe;
  final String mindmapId;
  final String topic;
  final List<String> previewNodes;

  const _MindmapMessageCard({
    required this.isMe,
    required this.mindmapId,
    required this.topic,
    required this.previewNodes,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: mindmapId.isEmpty
          ? null
          : () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MindmapViewerPage(
                    mindmapId: mindmapId,
                    fallbackTopic: topic,
                  ),
                ),
              );
            },
      child: Container(
        width: 260,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
          boxShadow: const [
            BoxShadow(
              color: Color(0x4D000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with icon
            Row(
              children: [
                Icon(
                  Icons.account_tree_rounded,
                  color: const Color(0xFF355872),
                  size: 18,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Mindmap',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Mindmap preview canvas
            Container(
              height: 120,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF000000),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withOpacity(0.06),
                  width: 1,
                ),
              ),
              child: _MindmapPreview(topic: topic, previewNodes: previewNodes),
            ),
            const SizedBox(height: 12),
            // Bottom action indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Tap to explore',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 13,
                  ),
                ),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 16,
                  color: Colors.white.withOpacity(0.6),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Mindmap preview visualization widget
class _MindmapPreview extends StatelessWidget {
  final String topic;
  final List<String> previewNodes;

  const _MindmapPreview({required this.topic, required this.previewNodes});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Connection lines (drawn first, behind nodes)
        Positioned.fill(child: CustomPaint(painter: _MindmapPreviewPainter())),
        // Central root node (purple)
        Positioned(
          left: 5,
          top: 44,
          child: _buildPreviewNode(color: const Color(0xFF8B7CFF), size: 10),
        ),
        // Branch nodes (blue)
        Positioned(
          left: 30,
          top: 20,
          child: _buildPreviewNode(color: const Color(0xFF5B9BFF), size: 8),
        ),
        Positioned(
          left: 30,
          top: 68,
          child: _buildPreviewNode(color: const Color(0xFF5B9BFF), size: 8),
        ),
        // Leaf nodes (green)
        Positioned(
          left: 52,
          top: 10,
          child: _buildPreviewNode(color: const Color(0xFF4CAF50), size: 8),
        ),
        Positioned(
          left: 52,
          top: 30,
          child: _buildPreviewNode(color: const Color(0xFF4CAF50), size: 8),
        ),
        Positioned(
          left: 52,
          top: 58,
          child: _buildPreviewNode(color: const Color(0xFF4CAF50), size: 8),
        ),
        Positioned(
          left: 52,
          top: 78,
          child: _buildPreviewNode(color: const Color(0xFF4CAF50), size: 8),
        ),
      ],
    );
  }

  Widget _buildPreviewNode({required Color color, required double size}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

// Custom painter for mindmap preview connections
class _MindmapPreviewPainter extends CustomPainter {
  const _MindmapPreviewPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // Root node position
    const Offset root = Offset(10, 49);

    // Draw lines from root to branch nodes
    canvas.drawLine(root, const Offset(35, 25), paint);
    canvas.drawLine(root, const Offset(35, 73), paint);

    // Draw lines from branch to leaf nodes
    // Top branch to leaves
    canvas.drawLine(const Offset(35, 25), const Offset(57, 15), paint);
    canvas.drawLine(const Offset(35, 25), const Offset(57, 35), paint);

    // Bottom branch to leaves
    canvas.drawLine(const Offset(35, 73), const Offset(57, 63), paint);
    canvas.drawLine(const Offset(35, 73), const Offset(57, 83), paint);
  }

  @override
  bool shouldRepaint(covariant _MindmapPreviewPainter oldDelegate) {
    return false;
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
                          errorBuilder: (_, _, _) =>
                              Image.network(publicUrl, fit: BoxFit.contain),
                        )
                      : Image.network(
                          publicUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const Center(
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
    } catch (e) {}
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

// Image Gallery Viewer - Full-featured viewer with advanced zoom controls
class _ImageGalleryViewer extends StatefulWidget {
  final List<MediaMetadata> mediaList;
  final int initialIndex;
  final Map<String, String> localSenderMediaPaths;
  final bool isMe;
  final ForwardMessageData? forwardMessage;

  const _ImageGalleryViewer({
    required this.mediaList,
    required this.initialIndex,
    required this.localSenderMediaPaths,
    required this.isMe,
    this.forwardMessage,
  });

  @override
  State<_ImageGalleryViewer> createState() => _ImageGalleryViewerState();
}

class _ImageGalleryViewerState extends State<_ImageGalleryViewer>
    with TickerProviderStateMixin {
  late PageController _pageController;
  late int _currentIndex;
  late Map<int, TransformationController> _transformationControllers;
  late Map<int, bool> _zoomStates;
  bool _isInteracting =
      false; // Track if user is currently interacting with zoom
  int _pointerCount = 0; // Track number of fingers on screen
  bool _showTopBar = true;
  bool _isActionBusy = false;
  final Map<int, bool> _imageReady = {};
  final Map<int, int> _retryToken = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _transformationControllers = {};
    _zoomStates = {};

    // Initialize transformation controllers and zoom states for all images
    for (int i = 0; i < widget.mediaList.length; i++) {
      final controller = TransformationController();
      _transformationControllers[i] = controller;
      _zoomStates[i] = false;
      _imageReady[i] = false;
      _retryToken[i] = 0;

      // Listen to transformation changes
      controller.addListener(() {
        final scale = controller.value.getMaxScaleOnAxis();
        final isZoomed = scale > 1.01;
        if (_zoomStates[i] != isZoomed) {
          setState(() {
            _zoomStates[i] = isZoomed;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (var controller in _transformationControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _shouldDisableScroll =>
      _isInteracting || (_zoomStates[_currentIndex] ?? false);

  bool get _isCurrentImageReady => _imageReady[_currentIndex] == true;

  MediaMetadata get _currentMetadata => widget.mediaList[_currentIndex];

  String? get _currentLocalPath {
    final metadata = _currentMetadata;
    return metadata.localPath ??
        widget.localSenderMediaPaths[metadata.messageId];
  }

  void _setImageReady(int index, bool ready) {
    if (_imageReady[index] == ready || !mounted) return;
    setState(() {
      _imageReady[index] = ready;
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _downloadCurrentImage() async {
    if (_isActionBusy || !_isCurrentImageReady) return;
    setState(() => _isActionBusy = true);
    try {
      final metadata = _currentMetadata;
      final saved = await ImageViewerActionService.saveImageToGallery(
        localPath: _currentLocalPath,
        publicUrl: metadata.publicUrl,
        sourceKey: metadata.r2Key.isNotEmpty
            ? metadata.r2Key
            : metadata.publicUrl,
        fileNameHint: metadata.originalFileName,
      );
      _showMessage(
        saved != null
            ? 'Image saved to gallery'
            : 'Storage permission denied or save failed',
      );
    } catch (_) {
      _showMessage('Download interrupted. Please retry.');
    } finally {
      if (mounted) setState(() => _isActionBusy = false);
    }
  }

  Future<void> _shareCurrentImage() async {
    if (_isActionBusy || !_isCurrentImageReady) return;
    setState(() => _isActionBusy = true);
    try {
      final metadata = _currentMetadata;
      final ok = await ImageViewerActionService.shareImage(
        localPath: _currentLocalPath,
        publicUrl: metadata.publicUrl,
        fileNameHint: metadata.originalFileName,
      );
      if (!ok) {
        _showMessage('Android share failed');
      }
    } catch (_) {
      _showMessage('Android share failed');
    } finally {
      if (mounted) setState(() => _isActionBusy = false);
    }
  }

  Future<void> _forwardCurrentImageGroup() async {
    if (_isActionBusy) return;
    final forwardMessage = widget.forwardMessage;
    if (forwardMessage == null) {
      _showMessage('Forward unavailable for this image');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForwardSelectionScreen(messages: [forwardMessage]),
      ),
    );
  }

  void _animateZoom(TransformationController controller, Matrix4 targetMatrix) {
    final begin = controller.value;
    final end = targetMatrix;

    final animationController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );

    final animation = Matrix4Tween(begin: begin, end: end).animate(
      CurvedAnimation(parent: animationController, curve: Curves.easeInOut),
    );

    animation.addListener(() {
      controller.value = animation.value;
    });

    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        animationController.dispose();
      }
    });

    animationController.forward();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.horizontal,
            physics: _shouldDisableScroll
                ? const NeverScrollableScrollPhysics()
                : const AlwaysScrollableScrollPhysics(),
            onPageChanged: (index) {
              if (_transformationControllers[_currentIndex] != null) {
                _transformationControllers[_currentIndex]!.value =
                    Matrix4.identity();
              }
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

              return _buildImageViewer(index, metadata, localPath);
            },
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 180),
            top: _showTopBar ? 0 : -120,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Container(
                color: Colors.black54,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Row(
                  children: [
                    _circleIcon(
                      icon: Icons.close,
                      onTap: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${_currentIndex + 1} / ${widget.mediaList.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    _circleIcon(
                      icon: Icons.download_rounded,
                      onTap: (_isCurrentImageReady && !_isActionBusy)
                          ? _downloadCurrentImage
                          : null,
                    ),
                    _circleIcon(
                      icon: Icons.forward_rounded,
                      onTap: _isActionBusy ? null : _forwardCurrentImageGroup,
                    ),
                    _circleIcon(
                      icon: Icons.share_rounded,
                      onTap: (_isCurrentImageReady && !_isActionBusy)
                          ? _shareCurrentImage
                          : null,
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

  Widget _buildImageViewer(
    int index,
    MediaMetadata metadata,
    String? localPath,
  ) {
    // Priority: local file (if it exists) → full network URL → thumbnail → fallback
    Widget imageWidget;

    final file = (localPath != null && localPath.isNotEmpty)
        ? File(localPath)
        : null;
    final hasLocalFile = file != null && file.existsSync();
    final hasNetwork = metadata.publicUrl.isNotEmpty;

    if (hasLocalFile) {
      _setImageReady(index, true);
      imageWidget = RepaintBoundary(
        child: Image.file(
          file,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          cacheWidth: 1200,
          errorBuilder: (_, _, _) => _buildFallbackImage(metadata),
        ),
      );
    } else if (hasNetwork) {
      imageWidget = RepaintBoundary(
        child: CachedNetworkImage(
          imageUrl: metadata.publicUrl,
          key: ValueKey('${metadata.publicUrl}_${_retryToken[index]}'),
          cacheKey: metadata.publicUrl,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          memCacheWidth: 1200,
          maxWidthDiskCache: 1200,
          fadeInDuration: const Duration(milliseconds: 0),
          fadeOutDuration: const Duration(milliseconds: 0),
          useOldImageOnUrlChange: true,
          imageBuilder: (context, imageProvider) {
            _setImageReady(index, true);
            return Image(
              image: imageProvider,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              gaplessPlayback: true,
            );
          },
          placeholder: (context, url) {
            _setImageReady(index, false);
            return const Center(
              child: SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            );
          },
          errorWidget: (context, url, error) {
            _setImageReady(index, false);
            return _buildFallbackImage(
              metadata,
              onRetry: () {
                setState(() {
                  _retryToken[index] = (_retryToken[index] ?? 0) + 1;
                });
              },
            );
          },
        ),
      );
    } else if (metadata.thumbnail.isNotEmpty) {
      // Use thumbnail if available
      if (metadata.thumbnail.startsWith('/')) {
        // Local file path
        imageWidget = RepaintBoundary(
          child: Image.file(
            File(metadata.thumbnail),
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            cacheWidth: 1200,
            errorBuilder: (_, _, _) => _buildFallbackImage(metadata),
          ),
        );
        _setImageReady(index, true);
      } else {
        // Base64 thumbnail
        try {
          final bytes = base64Decode(metadata.thumbnail);
          imageWidget = RepaintBoundary(
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, _, _) => _buildFallbackImage(metadata),
            ),
          );
          _setImageReady(index, true);
        } catch (e) {
          _setImageReady(index, false);
          imageWidget = _buildFallbackImage(metadata);
        }
      }
    } else {
      // Fallback: show download button or URL
      _setImageReady(index, false);
      imageWidget = _buildFallbackImage(metadata);
    }

    return Listener(
      onPointerDown: (event) {
        setState(() {
          _pointerCount++;
          // Only enable interaction when 2+ fingers detected
          if (_pointerCount >= 2) {
            _isInteracting = true;
          }
        });
      },
      onPointerUp: (event) {
        setState(() {
          _pointerCount--;
          // Re-enable PageView when less than 2 fingers
          if (_pointerCount < 2) {
            _isInteracting = false;
            // Snap back to center if at original scale
            final controller = _transformationControllers[index]!;
            final scale = controller.value.getMaxScaleOnAxis();
            if (scale <= 1.01) {
              // Reset to centered position
              controller.value = Matrix4.identity();
            }
          }
        });
      },
      onPointerCancel: (event) {
        setState(() {
          _pointerCount--;
          if (_pointerCount < 2) {
            _isInteracting = false;
            // Snap back to center if at original scale
            final controller = _transformationControllers[index]!;
            final scale = controller.value.getMaxScaleOnAxis();
            if (scale <= 1.01) {
              controller.value = Matrix4.identity();
            }
          }
        });
      },
      child: GestureDetector(
        onTap: () => setState(() => _showTopBar = !_showTopBar),
        onDoubleTapDown: (details) {
          // Store tap position for zoom target
          final controller = _transformationControllers[index]!;
          final scale = controller.value.getMaxScaleOnAxis();

          if (scale > 1.1) {
            // Zoom out to original with animation
            _animateZoom(controller, Matrix4.identity());
          } else {
            // Zoom in to 2.5x at tap position with animation
            final targetScale = 2.5;
            final position = details.localPosition;

            // Calculate offset to center the tap position
            final x = -position.dx * (targetScale - 1);
            final y = -position.dy * (targetScale - 1);

            final matrix = Matrix4.identity()
              ..translate(x, y)
              ..scale(targetScale);

            _animateZoom(controller, matrix);
          }
        },
        onDoubleTap: () {
          // Required for onDoubleTapDown to work
        },
        onVerticalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) > 700) {
            Navigator.of(context).pop();
          }
        },
        child: InteractiveViewer(
          transformationController: _transformationControllers[index],
          minScale: 1.0,
          maxScale: 5.0,
          panEnabled: true, // Enable single-finger pan when zoomed
          scaleEnabled: true,
          boundaryMargin: const EdgeInsets.all(double.infinity),
          clipBehavior: Clip.none,
          child: Center(child: imageWidget),
        ),
      ),
    );
  }

  Widget _buildFallbackImage(MediaMetadata metadata, {VoidCallback? onRetry}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.image, size: 64, color: Colors.white54),
          const SizedBox(height: 16),
          const Text(
            'Image not available',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Text(
            metadata.originalFileName ?? 'image.jpg',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _circleIcon({required IconData icon, required VoidCallback? onTap}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.16),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}
