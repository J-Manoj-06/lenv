import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:open_filex/open_filex.dart';
import 'package:dio/dio.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../utils/link_utils.dart';
import '../../config/cloudflare_config.dart';
import '../../models/community_message_model.dart';
import '../../models/media_metadata.dart';
import '../../providers/auth_provider.dart';
import '../../services/cloudflare_r2_service.dart';
import '../../services/local_cache_service.dart';
import '../../services/media_upload_service.dart';
import '../../services/media_repository.dart';
import '../../services/parent_teacher_group_service.dart';
import '../../services/unread_count_service.dart';
import '../../widgets/media_preview_card.dart';
import '../../widgets/multi_image_message_bubble.dart';
import '../../widgets/modern_attachment_sheet.dart';
import '../create_poll_screen.dart';
import '../../widgets/poll_message_widget.dart';
import '../../models/poll_model.dart';
import '../common/announcement_view_screen.dart';
import '../../utils/message_scroll_highlight_mixin.dart';
// OFFLINE-FIRST IMPORTS
import '../../repositories/local_message_repository.dart';
import '../../services/firebase_message_sync_service.dart';
import '../messages/offline_message_search_page.dart';
import '../../models/local_message.dart';

class ParentSectionGroupChatScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  final String? className;
  final String? section;
  final String childName;
  final String childId;
  final String? schoolCode;
  final String senderRole;

  const ParentSectionGroupChatScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.childName,
    required this.childId,
    this.className,
    this.section,
    this.schoolCode,
    this.senderRole = 'parent',
  });

  @override
  State<ParentSectionGroupChatScreen> createState() =>
      _ParentSectionGroupChatScreenState();
}

class _ParentSectionGroupChatScreenState
    extends State<ParentSectionGroupChatScreen>
    with AutomaticKeepAliveClientMixin, MessageScrollAndHighlightMixin {
  // ✅ NEW THEME COLORS - Modern dark design
  static const Color primaryBackground = Color(0xFF0F1113);
  static const Color secondaryBackground = Color(0xFF16181A);
  static const Color userMessageBubble = Color(0xFF6C5CE7);
  static const Color otherMessageBubble = Color(0xFF2B2F31);
  static const Color primaryText = Color(0xFFFFFFFF);
  static const Color mutedText = Color(0xFF9AA0A6);
  static const Color dividerColor = Color(0xFF1E2123);
  static const Color parentGreen = Color(0xFF14A670);
  static const Color teacherViolet = Color(0xFF6366F1);

  // Legacy color constants for compatibility
  static const Color backgroundDark = primaryBackground;
  static const Color bubbleDark = secondaryBackground;

  // ✅ OPTIMIZATION: Pagination state
  static const int _messagesPerPage = 50;
  bool _hasMoreMessages = true;
  bool _isLoadingMore = false;
  bool _isRestoringScroll = false;
  DocumentSnapshot? _lastDocument;
  final List<CommunityMessageModel> _olderMessages = [];

  final ParentTeacherGroupService _service = ParentTeacherGroupService();
  final MediaRepository _mediaRepository = MediaRepository();
  final UnreadCountService _unreadService = UnreadCountService();

  // OFFLINE-FIRST SERVICES
  late final LocalMessageRepository _localRepo;
  late final FirebaseMessageSyncService _syncService;

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();
  late final MediaUploadService _mediaUploadService;
  bool _isUploading = false;
  final ValueNotifier<bool> _isRecording = ValueNotifier<bool>(false);
  String? _recordingPath;
  final ValueNotifier<int> _recordingDuration = ValueNotifier<int>(0);
  Timer? _recordingTimer;
  final List<CommunityMessageModel> _pendingMessages = [];
  final Map<String, ValueNotifier<double>> _pendingUploadNotifiers = {};
  // ✅ Additional map for progress tracking (for compatibility)
  final Map<String, ValueNotifier<double>> _progressNotifiers = {};
  // Tracks local file paths for sent media (by messageId or r2Key) so we can display without re-downloading.
  final Map<String, String> _localSenderMediaPaths = {};
  // Throttle progress updates to avoid rebuilding the entire list too frequently
  final Map<String, int> _lastUploadPercent = {};
  // Ensure unique IDs for rapid uploads
  int _lastUploadTimestamp = 0;

  // Poll cached progress while uploads continue in background
  Timer? _progressPollTimer;
  bool _offlineReady = false;

  // Selection mode for multi-delete (using ValueNotifier to avoid full-page rebuilds)
  bool _selectionMode = false;
  final ValueNotifier<Set<String>> _selectedMessages =
      ValueNotifier<Set<String>>({});
  final ValueNotifier<bool> _hasText = ValueNotifier<bool>(false);

  // ✅ NEW: Use ValueNotifier for loading state to avoid full rebuilds
  final ValueNotifier<bool> _isLoadingMoreNotifier = ValueNotifier<bool>(false);
  int _messageLoadCount = 0; // Debug counter

  // ✅ CRITICAL: Message cache to maintain stable Map instances (prevents widget recreation)
  // This cache ensures Flutter recognizes the same message object and doesn't rebuild widgets
  // when StreamBuilder rebuilds. Same technique used in staff room.
  final Map<String, CommunityMessageModel> _messageCache = {};

  // ✅ Cache stream like staff room to avoid rebuilding new streams
  Stream<List<CommunityMessageModel>>? _messagesStream;

  @override
  bool get wantKeepAlive => true; // ✅ Prevent rebuild when switching tabs

  @override
  void dispose() {
    for (final notifier in _pendingUploadNotifiers.values) {
      notifier.dispose();
    }
    // ✅ Dispose _progressNotifiers
    for (final notifier in _progressNotifiers.values) {
      notifier.dispose();
    }
    _selectedMessages.dispose();
    _hasText.dispose();
    _isRecording.dispose();
    _isLoadingMoreNotifier.dispose();
    _controller.dispose();
    scrollController.dispose();
    _focusNode.dispose();
    _recordingTimer?.cancel();
    _progressPollTimer?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    // ✅ OPTIMIZATION: Setup scroll listener for pagination
    scrollController.addListener(_onScroll);

    // ✅ OPTIMIZATION: Listen to text changes without rebuilding
    _controller.addListener(() {
      _hasText.value = _controller.text.trim().isNotEmpty;
    });

    _initOfflineFirst();

    // Start polling cached progress (keeps UI updated after navigation)
    _startProgressPolling();

    // ✅ Cache stream once (same as staff room) to prevent re-creation
    _messagesStream = _service.getMessagesStream(widget.groupId);

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

    // Mark chat as read when screen opens
    _markChatAsRead();
  }

  void _initOfflineFirst() async {
    try {
      _localRepo = LocalMessageRepository();
      _syncService = FirebaseMessageSyncService(_localRepo);

      await _localRepo.initialize();

      final chatId = widget.groupId;
      print('👨‍👩‍👧 Parent Group Chat - Initializing offline-first');
      print('   Group ID: $chatId');
      print('   Group Name: ${widget.groupName}');

      // Load from cache first
      final cachedMessages = await _localRepo.getMessagesForChat(
        chatId,
        limit: 50,
      );

      if (cachedMessages.isEmpty) {
        print('📥 No cache - fetching initial messages from Firebase...');
        await _syncService.initialSyncForChat(
          chatId: chatId,
          chatType: 'parent_group',
          limit: 50,
        );
        print('✅ Initial sync completed');
      } else {
        print('✅ Loaded ${cachedMessages.length} messages from cache');

        // Debug: Check what senders are in the cache
        final senders = cachedMessages.map((m) => m.senderId).toSet();
        print('   👥 Unique senders in cache: ${senders.length}');
        for (final senderId in senders) {
          final count = cachedMessages
              .where((m) => m.senderId == senderId)
              .length;
          print('      - $senderId: $count messages');
        }

        _syncService.syncNewMessages(
          chatId: chatId,
          chatType: 'parent_group',
          lastTimestamp: cachedMessages.first.timestamp,
        );
      }

      // Start real-time sync
      if (!mounted) return;
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;
      if (currentUser != null) {
        print('🔄 Starting real-time sync for parent group chat');
        await _syncService.startSyncForChat(
          chatId: chatId,
          chatType: 'parent_group',
          userId: currentUser.uid,
        );
        print('✅ Real-time sync started successfully');

        // ✅ CRITICAL: Load pending messages after sync starts
        await _loadPendingMessages();

        // Mark offline services ready for progress polling
        _offlineReady = true;
      } else {
        print('⚠️ No current user found, skipping real-time sync');
      }
    } catch (e, stackTrace) {
      print('❌ Error initializing offline-first for parent group: $e');
      print('Stack trace: $stackTrace');
    }
  }

  /// Save pending message with current upload progress to cache
  Future<void> _updatePendingMessageCache(
    String messageId,
    List<Map<String, dynamic>> mediaWithProgress,
  ) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;
      if (currentUser == null) return;

      // ✅ Find the pending message safely
      final pendingMsg = _pendingMessages
          .cast<CommunityMessageModel?>()
          .firstWhere((m) => m?.messageId == messageId, orElse: () => null);

      if (pendingMsg == null) {
        print(
          '⚠️ Pending message $messageId not found in list, skipping cache update',
        );
        return;
      }

      final localMessage = LocalMessage(
        messageId: messageId,
        chatId: widget.groupId,
        chatType: 'ptGroup',
        senderId: currentUser.uid,
        senderName: currentUser.name,
        timestamp: pendingMsg.createdAt.millisecondsSinceEpoch,
        messageText: pendingMsg.content,
        multipleMedia: mediaWithProgress,
        isPending: true,
      );

      await _localRepo.saveMessage(localMessage);
      print('💾 Updated cache for $messageId with progress');
    } catch (e) {
      print('⚠️ Failed to update pending message cache: $e');
    }
  }

  /// Load pending messages from local cache (survives navigation)
  /// WHY: When user uploads images and navigates away, the pending messages are saved to LocalMessageRepository
  ///      This function restores them when returning to the chat
  Future<void> _loadPendingMessages() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;
      if (currentUser == null) return;

      // Load pending messages for this chat from cache
      final pendingMessages = await _localRepo.getPendingMessages(
        chatId: widget.groupId,
        senderId: currentUser.uid,
      );

      if (pendingMessages.isEmpty) {
        print('📭 No pending messages to restore');
        return;
      }

      print('📥 Loading ${pendingMessages.length} pending messages from cache');

      if (!mounted) return;

      setState(() {
        // ✅ IMPROVED: Keep actively uploading messages, only replace completed/missing ones
        final activeUploadIds = _pendingMessages
            .where((msg) {
              // Check if any media in this message is actively uploading
              if (msg.multipleMedia != null) {
                return msg.multipleMedia!.any((media) {
                  final notifier = _pendingUploadNotifiers[media.messageId];
                  return notifier != null && notifier.value < 100;
                });
              }
              // Check single media uploads
              final notifier = _pendingUploadNotifiers[msg.messageId];
              return notifier != null && notifier.value < 100;
            })
            .map((msg) => msg.messageId)
            .toSet();

        print(
          '🔄 Preserving ${activeUploadIds.length} actively uploading messages',
        );

        // Remove only completed/stale messages, keep active uploads
        _pendingMessages.removeWhere(
          (msg) => !activeUploadIds.contains(msg.messageId),
        );

        // Clean up notifiers for removed messages only
        final messagesToKeep = _pendingMessages.map((m) => m.messageId).toSet();
        _pendingUploadNotifiers.removeWhere((key, notifier) {
          final shouldRemove = !messagesToKeep.any(
            (msgId) => key.startsWith(msgId.replaceFirst('pending:', '')),
          );
          if (shouldRemove) notifier.dispose();
          return shouldRemove;
        });
        _lastUploadPercent.removeWhere(
          (key, _) => !messagesToKeep.any(
            (msgId) => key.startsWith(msgId.replaceFirst('pending:', '')),
          ),
        );

        // Convert LocalMessage to CommunityMessageModel format
        for (final msg in pendingMessages) {
          if (msg.multipleMedia != null && msg.multipleMedia!.isNotEmpty) {
            print(
              '   📤 Restoring pending: ${msg.messageId} (${msg.multipleMedia!.length} media items)',
            );

            // Convert multipleMedia from List<dynamic> to List<MediaMetadata>
            final mediaList = <MediaMetadata>[];
            for (final mediaMap in msg.multipleMedia!) {
              try {
                mediaList.add(
                  MediaMetadata(
                    messageId: mediaMap['messageId'] ?? '',
                    r2Key: mediaMap['r2Key'] ?? '',
                    publicUrl: mediaMap['publicUrl'] ?? '',
                    thumbnail: mediaMap['thumbnail'] ?? '',
                    localPath: mediaMap['localPath'],
                    expiresAt: mediaMap['expiresAt'] != null
                        ? DateTime.parse(mediaMap['expiresAt'])
                        : DateTime.now().add(const Duration(days: 30)),
                    uploadedAt: mediaMap['uploadedAt'] != null
                        ? DateTime.parse(mediaMap['uploadedAt'])
                        : DateTime.now(),
                    originalFileName: mediaMap['originalFileName'] ?? '',
                    fileSize: mediaMap['fileSize'] ?? 0,
                    mimeType: mediaMap['mimeType'] ?? 'image/jpeg',
                  ),
                );
              } catch (e) {
                print('⚠️ Failed to parse media item: $e');
              }
            }

            if (mediaList.isEmpty) continue;

            // ✅ Ensure consistent pending: prefix for deduplication
            String messageId = msg.messageId.startsWith('pending:')
                ? msg.messageId
                : 'pending:${msg.messageId}';

            final pendingMessage = CommunityMessageModel(
              messageId: messageId,
              communityId: widget.groupId,
              senderId: msg.senderId,
              senderName: msg.senderName,
              senderRole: widget.senderRole,
              senderAvatar: '',
              type: 'image',
              content: msg.messageText ?? '',
              imageUrl: '',
              fileUrl: '',
              fileName: '',
              multipleMedia: mediaList,
              createdAt: DateTime.fromMillisecondsSinceEpoch(msg.timestamp),
              isEdited: false,
              isDeleted: false,
              isPinned: false,
              reactions: {},
              replyTo: '',
              replyCount: 0,
              isReported: false,
              reportCount: 0,
            );

            _pendingMessages.insert(0, pendingMessage);

            // Cache this pending message in the message cache too
            _messageCache[pendingMessage.messageId] = pendingMessage;

            // Restore upload progress trackers and local paths
            for (int i = 0; i < mediaList.length; i++) {
              final media = mediaList[i];
              if (media.localPath != null && media.localPath!.isNotEmpty) {
                _localSenderMediaPaths[media.messageId] = media.localPath!;
              }
              // Check if progress was saved in the cached multipleMedia
              final cachedMedia = msg.multipleMedia?[i];
              final progressValue =
                  cachedMedia != null && cachedMedia['uploadProgress'] != null
                  ? (cachedMedia['uploadProgress'] as num).toDouble()
                  : 0.0;

              // ✅ Only restore if not completed (progress < 1.0)
              if (progressValue < 1.0) {
                _pendingUploadNotifiers[media.messageId] =
                    ValueNotifier<double>(
                      progressValue * 100, // Convert 0.0-1.0 to 0-100
                    );
                _lastUploadPercent[media.messageId] = (progressValue * 100)
                    .toInt();
                print(
                  '   📊 Restored progress: ${media.messageId} at ${(progressValue * 100).toInt()}%',
                );
              } else {
                print('   ✅ Skipped completed upload: ${media.messageId}');
              }
            }
          }
        }
      });

      print('✅ Restored ${_pendingMessages.length} pending messages');
    } catch (e, stackTrace) {
      print('❌ Error loading pending messages: $e');
      print('Stack trace: $stackTrace');
    }
  }

  void _startProgressPolling() {
    _progressPollTimer?.cancel();
    _progressPollTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_pendingMessages.isNotEmpty) {
        _checkCacheForProgressUpdates();
      }
    });
  }

  Future<void> _checkCacheForProgressUpdates() async {
    if (!_offlineReady || _pendingMessages.isEmpty || !mounted) return;

    final toRemove = <String>[];
    bool hasChanges = false;

    for (final pendingMsg in _pendingMessages) {
      final pendingId = pendingMsg.messageId;
      final baseId = pendingId.replaceFirst('pending:', '');

      try {
        final cachedMsg = await _localRepo.getMessageById(baseId);

        if (cachedMsg == null || cachedMsg.isPending == false) {
          // ✅ CRITICAL: Check if upload is still in progress before removing
          final notifier = _pendingUploadNotifiers[pendingId];
          if (notifier != null && notifier.value < 100) {
            print(
              '⏳ [CLEANUP] Keep pending:$pendingId - upload at ${notifier.value}%',
            );
            continue; // Still uploading, don't remove yet
          }
          toRemove.add(pendingId);
          continue;
        }

        if (cachedMsg.multipleMedia == null) continue;

        for (final media in cachedMsg.multipleMedia!) {
          final mediaId = media['messageId'] as String?;
          if (mediaId == null) continue;

          final cachedProgress = media['uploadProgress'] as double?;
          if (cachedProgress != null) {
            final current = _pendingUploadNotifiers[mediaId]?.value ?? 0.0;
            final nextValue = (cachedProgress * 100).clamp(0.0, 100.0);
            if ((nextValue - current).abs() > 0.5) {
              _pendingUploadNotifiers[mediaId] ??= ValueNotifier<double>(
                nextValue,
              );
              _pendingUploadNotifiers[mediaId]!.value = nextValue;
              _lastUploadPercent[mediaId] = nextValue.toInt();
              hasChanges = true;
            }
          }
        }
      } catch (_) {
        // Ignore cache read errors while uploads update
      }
    }

    if (toRemove.isNotEmpty && mounted) {
      setState(() {
        _pendingMessages.removeWhere((m) => toRemove.contains(m.messageId));
        for (final pendingId in toRemove) {
          final baseId = pendingId.replaceFirst('pending:', '');
          _pendingUploadNotifiers.removeWhere((k, _) => k.startsWith(baseId));
          _lastUploadPercent.removeWhere((k, _) => k.startsWith(baseId));
        }
      });
      return;
    }

    if (hasChanges && mounted) {
      setState(() {});
    }
  }

  /// Mark this chat as read for the current user
  Future<void> _markChatAsRead() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final userId = authProvider.currentUser?.uid;
      if (userId != null) {
        await _unreadService.markChatAsRead(
          userId: userId,
          chatId: widget.groupId,
        );
      }
    } catch (e) {}
  }

  String _formatTime(DateTime dateTime) {
    return DateFormat('h:mm a').format(dateTime);
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
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

  String _getFileName(CommunityMessageModel msg) {
    final meta = msg.mediaMetadata;
    if (meta?.originalFileName != null && meta!.originalFileName!.isNotEmpty) {
      return meta.originalFileName!;
    }
    if (meta != null && meta.r2Key.isNotEmpty) {
      final parts = meta.r2Key.split('/').where((p) => p.isNotEmpty).toList();
      if (parts.isNotEmpty) return parts.last;
    }
    if (meta != null && meta.publicUrl.isNotEmpty) {
      final uri = Uri.tryParse(meta.publicUrl);
      if (uri != null && uri.pathSegments.isNotEmpty) {
        return uri.pathSegments.last;
      }
    }
    return 'file';
  }

  void _onEmojiSelected(Emoji emoji) {
    _controller.text += emoji.emoji;
  }

  void _onBackspacePressed() {
    final text = _controller.text;
    if (text.isNotEmpty) {
      _controller.text = text.substring(0, text.length - 1);
    }
  }

  /// ✅ OPTIMIZATION: Scroll listener for pagination
  void _onScroll() {
    if (!scrollController.hasClients ||
        _isLoadingMore ||
        !_hasMoreMessages ||
        _isRestoringScroll) {
      return;
    }

    // Load more when user scrolls to 95% from the top (bottom in reverse list)
    // Higher threshold prevents premature loading when just scrolling up a bit
    final scrollPosition = scrollController.position;
    if (scrollPosition.pixels >= scrollPosition.maxScrollExtent * 0.95) {
      print(
        '[CHAT_DEBUG] Scroll threshold reached - loading more messages. Current: ${scrollPosition.pixels}, Max: ${scrollPosition.maxScrollExtent}',
      );
      _loadMoreMessages();
    }
  }

  /// ✅ OPTIMIZATION: Load older messages with pagination - NO STATE CHANGES
  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMoreMessages) {
      print(
        '[CHAT_DEBUG] Load skipped - isLoadingMore: $_isLoadingMore, hasMoreMessages: $_hasMoreMessages',
      );
      return;
    }

    _isLoadingMore = true;
    _isLoadingMoreNotifier.value = true;
    print(
      '[CHAT_DEBUG] [LOAD #${++_messageLoadCount}] Starting message load. Current older messages: ${_olderMessages.length}',
    );

    // Save current scroll position before loading
    final savedPosition = scrollController.hasClients
        ? scrollController.position.pixels
        : 0.0;
    print(
      '[CHAT_DEBUG] [LOAD #$_messageLoadCount] Saved scroll position: $savedPosition',
    );

    try {
      final newMessages = await _service.getMessagesPaginated(
        groupId: widget.groupId,
        limit: _messagesPerPage,
        startAfter: _lastDocument,
      );

      print(
        '[CHAT_DEBUG] [LOAD #$_messageLoadCount] Fetched ${newMessages.length} messages from Firestore',
      );

      if (newMessages.length < _messagesPerPage) {
        _hasMoreMessages = false;
        print(
          '[CHAT_DEBUG] [LOAD #$_messageLoadCount] No more messages - reached end',
        );
      }

      if (newMessages.isNotEmpty && mounted) {
        // Disable scroll listener before adding messages
        _isRestoringScroll = true;

        // ✅ KEY FIX: Add messages directly WITHOUT calling setState
        // This prevents triggering the StreamBuilder rebuild
        _olderMessages.addAll(newMessages);
        _lastDocument = newMessages.last.documentSnapshot;

        print(
          '[CHAT_DEBUG] [LOAD #$_messageLoadCount] Added messages to _olderMessages. Total older messages now: ${_olderMessages.length}',
        );

        // ✅ KEY FIX: Update loading notifier AFTER messages are added
        // This updates only the loading indicator, not the entire list
        _isLoadingMoreNotifier.value = false;
        print(
          '[CHAT_DEBUG] [LOAD #$_messageLoadCount] Loading indicator updated to false',
        );

        // Restore scroll position after the next frame
        print(
          '[CHAT_DEBUG] [LOAD #$_messageLoadCount] Scheduling scroll restoration via addPostFrameCallback',
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            print(
              '[CHAT_DEBUG] [LOAD #$_messageLoadCount] Widget not mounted, skipping scroll restoration',
            );
            _isRestoringScroll = false;
            return;
          }

          if (!scrollController.hasClients) {
            print(
              '[CHAT_DEBUG] [LOAD #$_messageLoadCount] ScrollController has no clients',
            );
            _isRestoringScroll = false;
            return;
          }

          try {
            print(
              '[CHAT_DEBUG] [LOAD #$_messageLoadCount] Restoring scroll to position: $savedPosition',
            );
            scrollController.jumpTo(savedPosition);
            print(
              '[CHAT_DEBUG] [LOAD #$_messageLoadCount] Scroll restoration completed',
            );
          } catch (e) {
            print(
              '[CHAT_DEBUG] [LOAD #$_messageLoadCount] Scroll restoration failed: $e',
            );
            // If position is out of bounds, jump to safe position
            try {
              final safePosition =
                  scrollController.position.maxScrollExtent * 0.5;
              print(
                '[CHAT_DEBUG] [LOAD #$_messageLoadCount] Attempting safe scroll to: $safePosition',
              );
              scrollController.jumpTo(safePosition);
            } catch (_) {
              print(
                '[CHAT_DEBUG] [LOAD #$_messageLoadCount] Safe scroll also failed',
              );
            }
          }

          // Re-enable scroll listener after restoration is complete
          if (mounted) {
            Future.delayed(const Duration(milliseconds: 50), () {
              if (mounted) {
                _isRestoringScroll = false;
                print(
                  '[CHAT_DEBUG] [LOAD #$_messageLoadCount] Scroll listener re-enabled',
                );
              }
            });
          }
        });
      } else {
        _hasMoreMessages = false;
        print(
          '[CHAT_DEBUG] [LOAD #$_messageLoadCount] No new messages or widget not mounted',
        );
        _isLoadingMoreNotifier.value = false;
      }
    } catch (e) {
      print('[CHAT_DEBUG] [LOAD #$_messageLoadCount] ERROR: $e');
      _isLoadingMoreNotifier.value = false;
    } finally {
      _isLoadingMore = false;
      print('[CHAT_DEBUG] [LOAD #$_messageLoadCount] Load operation completed');
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.currentUser;
    final senderId = user?.uid ?? '';
    final senderName = user?.name ?? 'Parent';

    // Clear immediately like WhatsApp (no loading state)
    _controller.clear();

    try {
      await _service.sendMessage(
        groupId: widget.groupId,
        senderId: senderId,
        senderName: senderName,
        senderRole: widget.senderRole,
        content: text,
      );

      // ✅ Auto-scroll to bottom to show latest message
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send message: $e'),
          backgroundColor: Colors.red[400],
        ),
      );
    }
  }

  /// ✅ NEW: Instant scroll to bottom to show latest message
  void _scrollToBottom() {
    if (!scrollController.hasClients) return;

    print('[CHAT_DEBUG] Instant scrolling to bottom to show latest message');

    // Schedule after frame to ensure ListView has laid out
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scrollController.hasClients) {
        print('[CHAT_DEBUG] ScrollController not ready for bottom scroll');
        return;
      }

      try {
        // Instant jump to bottom (0 in reverse list) - no animation
        scrollController.jumpTo(0.0);
        print('[CHAT_DEBUG] Successfully jumped to bottom instantly');
      } catch (e) {
        print('[CHAT_DEBUG] Exception during instant scroll: $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // ✅ Required for AutomaticKeepAliveClientMixin
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUserId =
        Provider.of<AuthProvider>(context, listen: false).currentUser?.uid ??
        '';
    final primaryColor = widget.senderRole == 'teacher'
        ? teacherViolet
        : parentGreen;

    return Scaffold(
      backgroundColor: isDark ? primaryBackground : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? secondaryBackground : Colors.grey.shade50,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(
            _selectionMode ? Icons.close : Icons.arrow_back_ios_new_rounded,
          ),
          color: isDark ? primaryText : Colors.black87,
          onPressed: () {
            if (_selectionMode) {
              setState(() => _selectionMode = false);
              _selectedMessages.value = {};
            } else {
              Navigator.of(context).maybePop();
            }
          },
          tooltip: _selectionMode ? 'Cancel' : 'Back',
        ),
        titleSpacing: 0,
        title: _selectionMode
            ? ValueListenableBuilder<Set<String>>(
                valueListenable: _selectedMessages,
                builder: (context, selectedSet, _) {
                  return Text(
                    '${selectedSet.length} selected',
                    style: TextStyle(
                      color: isDark ? primaryText : Colors.black87,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  );
                },
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.groupName,
                    style: TextStyle(
                      color: isDark ? primaryText : Colors.black87,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.className ?? ''}${widget.section != null ? ' - ${widget.section}' : ''}',
                    style: TextStyle(
                      color: isDark ? mutedText : Colors.grey.shade600,
                      fontSize: 13,
                      fontWeight: FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
        actions: _selectionMode
            ? [
                ValueListenableBuilder<Set<String>>(
                  valueListenable: _selectedMessages,
                  builder: (context, selectedSet, _) {
                    return IconButton(
                      icon: const Icon(Icons.delete_outline),
                      color: Colors.redAccent,
                      onPressed: selectedSet.isEmpty
                          ? null
                          : _deleteSelectedMessages,
                      tooltip: selectedSet.isEmpty
                          ? 'Select messages to delete'
                          : 'Delete for everyone',
                    );
                  },
                ),
              ]
            : [
                IconButton(
                  icon: Icon(
                    Icons.search,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                  onPressed: _openSearch,
                ),
              ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<CommunityMessageModel>>(
              stream: _messagesStream,
              builder: (context, snapshot) {
                // ✅ CRITICAL: Show pending messages immediately while Firestore loads
                if (snapshot.connectionState == ConnectionState.waiting &&
                    _pendingMessages.isEmpty) {
                  return Center(
                    child: CircularProgressIndicator(color: parentGreen),
                  );
                }

                if (snapshot.hasError) {
                  // ✅ Show pending messages even if Firestore has error
                  if (_pendingMessages.isEmpty) {
                    return Center(
                      child: Text(
                        'Error loading messages',
                        style: TextStyle(
                          color: isDark ? Colors.red[200] : Colors.red[600],
                        ),
                      ),
                    );
                  }
                  // Continue building with pending messages
                }

                final firestoreMessages = snapshot.data ?? [];

                // StreamBuilder rebuild - combining pending + Firestore messages

                // ✅ CRITICAL: Use message cache to maintain stable instances
                // Create or retrieve cached versions of Firestore messages
                final cachedFirestoreMessages = <CommunityMessageModel>[];
                final firestoreMessageIds = <String>{};

                for (final msg in firestoreMessages) {
                  firestoreMessageIds.add(msg.messageId);
                  final cached = _messageCache[msg.messageId];
                  if (cached == null) {
                    // First time seeing this message - cache it
                    _messageCache[msg.messageId] = msg;
                  } else {
                    final cachedMulti = cached.multipleMedia?.length ?? 0;
                    final freshMulti = msg.multipleMedia?.length ?? 0;
                    final hasChange =
                        cached.type != msg.type ||
                        cachedMulti != freshMulti ||
                        cached.updatedAt != msg.updatedAt ||
                        cached.createdAt != msg.createdAt;

                    if (hasChange) {
                      _messageCache[msg.messageId] = msg;
                    }
                  }

                  // Always use the cached instance to maintain widget identity
                  cachedFirestoreMessages.add(_messageCache[msg.messageId]!);
                }

                // ✅ PRESERVE older cached messages that are not in the current Firestore snapshot
                // This prevents messages from disappearing when new ones arrive (due to stream limit)
                final olderCachedMessages = <CommunityMessageModel>[];
                for (final entry in _messageCache.entries) {
                  final msgId = entry.key;
                  // Skip if it's a pending message or already in the Firestore snapshot
                  if (msgId.startsWith('pending:') ||
                      firestoreMessageIds.contains(msgId)) {
                    continue;
                  }
                  // Add to older cached messages to preserve them
                  olderCachedMessages.add(entry.value);
                }
                print(
                  '🔍 [CACHE_DEBUG] Firestore=${firestoreMessages.length} PreservedCache=${olderCachedMessages.length}',
                );

                // ✅ SMART MERGE: Remove pending messages that now exist in Firestore
                final pendingIdsToRemove = <String>[];
                final filteredPendingMessages = <CommunityMessageModel>[];
                print(
                  '🔍 [PENDING_MERGE] Pending=${_pendingMessages.length} Firestore=${cachedFirestoreMessages.length}',
                );

                for (final pendingMsg in _pendingMessages) {
                  final pendingId = pendingMsg.messageId.replaceFirst(
                    'pending:',
                    '',
                  );

                  // ✅ Check if upload is still in progress FIRST
                  bool uploadInProgress = false;
                  final notifier =
                      _pendingUploadNotifiers[pendingMsg.messageId];
                  if (notifier != null && notifier.value < 100) {
                    uploadInProgress = true;
                  }

                  print(
                    '🔍 [PENDING_MERGE] Check ${pendingMsg.messageId} base=$pendingId media=${pendingMsg.multipleMedia?.length ?? 0} uploading=$uploadInProgress progress=${notifier?.value ?? -1}%',
                  );

                  // ✅ If upload in progress, keep the message visible
                  if (uploadInProgress) {
                    final cachedPending =
                        _messageCache[pendingMsg.messageId] ??= pendingMsg;
                    filteredPendingMessages.add(cachedPending);
                    print(
                      '⏳ [PENDING_MERGE] Keep ${pendingMsg.messageId} - upload at ${notifier?.value ?? 0}%',
                    );
                    continue;
                  }

                  // 1️⃣ FIRST: Try exact ID matching (highest priority)
                  bool foundExactMatch = false;
                  for (final serverMsg in cachedFirestoreMessages) {
                    if (serverMsg.messageId == pendingId) {
                      // ✅ CRITICAL: Only remove pending if upload is complete (100%)
                      bool uploadComplete = true;
                      if (pendingMsg.multipleMedia != null) {
                        for (final media in pendingMsg.multipleMedia!) {
                          final notifier =
                              _pendingUploadNotifiers[media.messageId];
                          if (notifier != null && notifier.value < 100) {
                            uploadComplete = false;
                            print(
                              '📤 [EXACT_MATCH] ${media.messageId} still uploading: ${notifier.value}%',
                            );
                            break;
                          }
                        }
                      } else {
                        // Check single upload
                        final notifier =
                            _pendingUploadNotifiers[pendingMsg.messageId];
                        if (notifier != null && notifier.value < 100) {
                          uploadComplete = false;
                          print(
                            '📤 [EXACT_MATCH] ${pendingMsg.messageId} still uploading: ${notifier.value}%',
                          );
                        }
                      }

                      if (uploadComplete) {
                        foundExactMatch = true;
                        print(
                          '✅ [EXACT_ID_MATCH] Firestore ID matches pending ID: $pendingId - removing',
                        );
                        pendingIdsToRemove.add(pendingMsg.messageId);
                      } else {
                        // Still uploading - keep pending visible
                        print(
                          '⏳ [EXACT_ID_MATCH] Firestore ID matches but upload incomplete: $pendingId - keeping',
                        );
                      }
                      break;
                    }
                  }

                  if (foundExactMatch) continue;

                  // 2️⃣ FALLBACK: Content-based matching
                  final pendingSenderId = pendingMsg.senderId;
                  final pendingTimestamp =
                      pendingMsg.createdAt.millisecondsSinceEpoch;
                  final pendingHasMultipleMedia =
                      pendingMsg.multipleMedia != null &&
                      pendingMsg.multipleMedia!.isNotEmpty;

                  // ✅ Add file name matching with case-insensitive comparison
                  final pendingFileKeys = <String>{};
                  if (pendingMsg.multipleMedia != null) {
                    for (final media in pendingMsg.multipleMedia!) {
                      if (media.originalFileName != null &&
                          media.fileSize != null) {
                        pendingFileKeys.add(
                          '${media.originalFileName!.toLowerCase()}|${media.fileSize}',
                        );
                      }
                    }
                  }

                  // Check if this pending message now exists in Firestore
                  final matchingServerMsg = cachedFirestoreMessages.where((
                    msg,
                  ) {
                    final serverSenderId = msg.senderId;
                    final serverTimestamp =
                        msg.createdAt.millisecondsSinceEpoch;

                    // Match by sender and timestamp
                    final senderMatch = serverSenderId == pendingSenderId;
                    final timeDiff = (serverTimestamp - pendingTimestamp).abs();
                    // ✅ Extended time window for media uploads (5 minutes)
                    final timeWindow = pendingHasMultipleMedia ? 300000 : 30000;
                    final timeMatch = timeDiff < timeWindow;

                    // ✅ Check file name matching (case-insensitive)
                    bool fileMatch = false;
                    if (pendingFileKeys.isNotEmpty &&
                        msg.multipleMedia != null) {
                      final serverFileKeys = <String>{};
                      for (final media in msg.multipleMedia!) {
                        if (media.originalFileName != null &&
                            media.fileSize != null) {
                          serverFileKeys.add(
                            '${media.originalFileName!.toLowerCase()}|${media.fileSize}',
                          );
                        }
                      }
                      fileMatch = serverFileKeys.any(pendingFileKeys.contains);
                    }

                    // For multi-media messages, ONLY match if server has multipleMedia too
                    if (pendingHasMultipleMedia) {
                      final serverHasMultipleMedia =
                          msg.multipleMedia != null &&
                          msg.multipleMedia!.isNotEmpty;

                      return senderMatch &&
                          timeMatch &&
                          (serverHasMultipleMedia || fileMatch);
                    }

                    return senderMatch && timeMatch;
                  }).firstOrNull;

                  if (matchingServerMsg != null) {
                    // ✅ CRITICAL: Only remove pending if upload is complete (100%)
                    bool uploadComplete = true;
                    if (pendingMsg.multipleMedia != null) {
                      for (final media in pendingMsg.multipleMedia!) {
                        final notifier =
                            _pendingUploadNotifiers[media.messageId];
                        if (notifier != null && notifier.value < 100) {
                          uploadComplete = false;
                          print(
                            '📤 [PENDING_MERGE] ${media.messageId} still uploading: ${notifier.value}%',
                          );
                          break;
                        }
                      }
                    } else {
                      // Check single upload
                      final notifier =
                          _pendingUploadNotifiers[pendingMsg.messageId];
                      if (notifier != null && notifier.value < 100) {
                        uploadComplete = false;
                        print(
                          '📤 [PENDING_MERGE] ${pendingMsg.messageId} still uploading: ${notifier.value}%',
                        );
                      }
                    }

                    if (uploadComplete) {
                      // Upload complete - safe to remove pending and show server version
                      print(
                        '🗑️ [PENDING_MERGE] Remove ${pendingMsg.messageId} matched ${matchingServerMsg.messageId}',
                      );
                      pendingIdsToRemove.add(pendingMsg.messageId);
                    } else {
                      // Still uploading - keep pending message visible
                      final cachedPending =
                          _messageCache[pendingMsg.messageId] ??= pendingMsg;
                      filteredPendingMessages.add(cachedPending);
                      print(
                        '⏳ [PENDING_MERGE] Keep ${pendingMsg.messageId} - upload in progress',
                      );
                    }
                  } else {
                    // Still uploading - keep in list
                    // Cache pending to keep stable instance
                    final cachedPending =
                        _messageCache[pendingMsg.messageId] ??= pendingMsg;
                    filteredPendingMessages.add(cachedPending);
                    print('✅ [PENDING_MERGE] Keep ${pendingMsg.messageId}');
                  }
                }

                // Remove completed pending messages (after frame to avoid flicker)
                if (pendingIdsToRemove.isNotEmpty) {
                  print(
                    '🧹 [PENDING_MERGE] Removing pending: $pendingIdsToRemove',
                  );
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    setState(() {
                      _pendingMessages.removeWhere(
                        (m) => pendingIdsToRemove.contains(m.messageId),
                      );
                      // Clean up notifiers and cache for removed pending messages
                      for (final pendingId in pendingIdsToRemove) {
                        final baseId = pendingId.replaceFirst('pending:', '');
                        // Remove all notifiers for this message's media
                        _pendingUploadNotifiers.forEach((key, notifier) {
                          if (key.startsWith(baseId)) {
                            notifier.dispose();
                          }
                        });
                        _pendingUploadNotifiers.removeWhere(
                          (key, _) => key.startsWith(baseId),
                        );
                        _lastUploadPercent.removeWhere(
                          (key, _) => key.startsWith(baseId),
                        );
                        // Remove pending message from cache (but keep Firestore messages)
                        _messageCache.remove(pendingId);
                      }
                    });
                  });
                }

                // ✅ COMBINE: pending + Firestore + preserved cache + older paginated messages
                // IMPORTANT: Sort by timestamp DESC for proper display order
                final allMessages = [
                  ...filteredPendingMessages,
                  ...cachedFirestoreMessages,
                  ...olderCachedMessages,
                  ..._olderMessages,
                ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

                // Update last document from stream if available
                if (cachedFirestoreMessages.isNotEmpty &&
                    _lastDocument == null) {
                  _lastDocument = cachedFirestoreMessages.last.documentSnapshot;
                }

                if (allMessages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.forum_outlined,
                          size: 64,
                          color: isDark
                              ? Colors.white.withOpacity(0.2)
                              : Colors.grey[500],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No messages yet',
                          style: TextStyle(
                            color: isDark
                                ? Colors.white.withOpacity(0.7)
                                : Colors.grey[700],
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Say hello to the teachers and parents of this section',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isDark
                                ? Colors.white.withOpacity(0.6)
                                : Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Stack(
                  children: [
                    // Main message list
                    ListView.builder(
                      key: const PageStorageKey('parent_group_chat_list'),
                      controller: scrollController,
                      reverse: true,
                      padding: const EdgeInsets.all(16),
                      itemCount: allMessages.length,
                      itemBuilder: (context, index) {
                        final msg = allMessages[index];
                        final isCurrentUser = msg.senderId == currentUserId;

                        // Day separator logic
                        final isOldest = index == allMessages.length - 1;
                        final currentDate = msg.createdAt;
                        final nextDate = isOldest
                            ? null
                            : allMessages[index + 1].createdAt;
                        final showDayDivider =
                            isOldest ||
                            _formatDayLabel(currentDate) !=
                                _formatDayLabel(nextDate!);

                        final hasMedia = msg.mediaMetadata != null;
                        final bubbleColor = hasMedia
                            ? Colors.transparent
                            : (isCurrentUser
                                  ? primaryColor
                                  : (isDark ? bubbleDark : Colors.grey[200]));
                        final textColor = isCurrentUser
                            ? Colors.white
                            : (isDark ? Colors.white : Colors.black87);
                        final isPending = msg.messageId.startsWith('pending:');
                        final progressNotifier = isPending
                            ? _pendingUploadNotifiers[msg.messageId]
                            : null;
                        final localPath =
                            _localSenderMediaPaths[msg.messageId] ??
                            (msg.mediaMetadata != null
                                ? _localSenderMediaPaths[msg
                                      .mediaMetadata!
                                      .r2Key]
                                : null);

                        if (msg.type == 'announcement') {
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (showDayDivider) _buildDayDivider(currentDate),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Center(
                                  child: InkWell(
                                    onTap: () {
                                      final role = (msg.senderRole)
                                          .toLowerCase();
                                      final postedByLabel =
                                          'Posted by ${msg.senderRole}';
                                      openAnnouncementView(
                                        context,
                                        role: role,
                                        title: msg.content.isNotEmpty
                                            ? msg.content
                                            : 'Announcement',
                                        subtitle: '',
                                        postedByLabel: postedByLabel,
                                        avatarUrl: null,
                                        postedAt: msg.createdAt,
                                        expiresAt: msg.createdAt.add(
                                          const Duration(hours: 24),
                                        ),
                                      );
                                    },
                                    child: Text(
                                      msg.content,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.white70
                                            : Colors.black54,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }

                        if (msg.type == 'poll') {
                          final data =
                              msg.documentSnapshot?.data()
                                  as Map<String, dynamic>?;
                          if (data != null) {
                            final poll = PollModel.fromMap(data, msg.messageId);
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (showDayDivider)
                                  _buildDayDivider(currentDate),
                                SizedBox(
                                  width: double.infinity,
                                  child: Align(
                                    alignment: isCurrentUser
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                    child: PollMessageWidget(
                                      poll: poll,
                                      chatId: widget.groupId,
                                      chatType: 'ptGroup',
                                      isOwnMessage: isCurrentUser,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }
                        }

                        // Skip deleted messages
                        if (msg.isDeleted) {
                          return const SizedBox.shrink();
                        }

                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (showDayDivider) _buildDayDivider(currentDate),
                            ValueListenableBuilder<Set<String>>(
                              valueListenable: _selectedMessages,
                              builder: (context, selectedSet, _) {
                                final isSelected = selectedSet.contains(
                                  msg.messageId,
                                );

                                return Padding(
                                  key: ValueKey(msg.messageId),
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    mainAxisAlignment: isCurrentUser
                                        ? MainAxisAlignment.end
                                        : MainAxisAlignment.start,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Flexible(
                                        child: GestureDetector(
                                          onLongPress: () {
                                            if (!_selectionMode &&
                                                !isPending &&
                                                isCurrentUser) {
                                              // Batch state updates to prevent flickering
                                              _selectionMode = true;
                                              setState(() {
                                                _selectedMessages.value = {
                                                  msg.messageId,
                                                };
                                              });
                                            }
                                          },
                                          onTap: _selectionMode && isCurrentUser
                                              ? () {
                                                  if (!isPending) {
                                                    final selectedSet =
                                                        _selectedMessages.value;
                                                    if (isSelected) {
                                                      if (selectedSet.length >
                                                          1) {
                                                        final updated = {
                                                          ...selectedSet,
                                                        };
                                                        updated.remove(
                                                          msg.messageId,
                                                        );
                                                        _selectedMessages
                                                                .value =
                                                            updated;
                                                      } else {
                                                        // Deselecting the last message exits selection mode
                                                        setState(() {
                                                          _selectionMode =
                                                              false;
                                                          _selectedMessages
                                                                  .value =
                                                              {};
                                                        });
                                                      }
                                                    } else {
                                                      _selectedMessages.value =
                                                          {
                                                            ...selectedSet,
                                                            msg.messageId,
                                                          };
                                                    }
                                                  }
                                                }
                                              : null,
                                          child: Column(
                                            crossAxisAlignment: isCurrentUser
                                                ? CrossAxisAlignment.end
                                                : CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // Show sender name outside the bubble
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  left: 12,
                                                  right: 12,
                                                  bottom: 4,
                                                ),
                                                child: Text(
                                                  isCurrentUser
                                                      ? 'You'
                                                      : msg.senderName,
                                                  style: TextStyle(
                                                    color: isDark
                                                        ? Colors.grey[400]
                                                        : Colors.grey[700],
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                              ConstrainedBox(
                                                constraints: BoxConstraints(
                                                  maxWidth:
                                                      MediaQuery.of(
                                                        context,
                                                      ).size.width *
                                                      0.7,
                                                ),
                                                child: DecoratedBox(
                                                  decoration: BoxDecoration(
                                                    color:
                                                        (msg.multipleMedia !=
                                                                null &&
                                                            msg
                                                                .multipleMedia!
                                                                .isNotEmpty)
                                                        ? Colors.transparent
                                                        : (isSelected
                                                              ? primaryColor
                                                                    .withOpacity(
                                                                      0.2,
                                                                    )
                                                              : bubbleColor),
                                                    border:
                                                        (msg.multipleMedia !=
                                                                null &&
                                                            msg
                                                                .multipleMedia!
                                                                .isNotEmpty)
                                                        ? Border.all(
                                                            color: primaryColor
                                                                .withOpacity(
                                                                  0.8,
                                                                ),
                                                            width: 2.5,
                                                          )
                                                        : (hasMedia
                                                              ? Border.all(
                                                                  color:
                                                                      isSelected
                                                                      ? primaryColor
                                                                            .withOpacity(
                                                                              0.8,
                                                                            )
                                                                      : primaryColor,
                                                                  width:
                                                                      isSelected
                                                                      ? 1.0
                                                                      : 1.5,
                                                                )
                                                              : (isSelected
                                                                    ? Border.all(
                                                                        color:
                                                                            primaryColor,
                                                                        width:
                                                                            2.5,
                                                                      )
                                                                    : null)),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ).copyWith(
                                                          bottomRight:
                                                              isCurrentUser
                                                              ? const Radius.circular(
                                                                  4,
                                                                )
                                                              : null,
                                                          bottomLeft:
                                                              !isCurrentUser
                                                              ? const Radius.circular(
                                                                  4,
                                                                )
                                                              : null,
                                                        ),
                                                  ),
                                                  child: Padding(
                                                    padding: EdgeInsets.symmetric(
                                                      horizontal:
                                                          (msg.multipleMedia !=
                                                                  null &&
                                                              msg
                                                                  .multipleMedia!
                                                                  .isNotEmpty)
                                                          ? 2
                                                          : (hasMedia ? 4 : 12),
                                                      vertical:
                                                          (msg.multipleMedia !=
                                                                  null &&
                                                              msg
                                                                  .multipleMedia!
                                                                  .isNotEmpty)
                                                          ? 2
                                                          : (hasMedia ? 4 : 8),
                                                    ),
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          isCurrentUser
                                                          ? CrossAxisAlignment
                                                                .end
                                                          : CrossAxisAlignment
                                                                .start,
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        // ✅ MULTI-IMAGE GRID: Display multiple images in WhatsApp-style grid
                                                        // FIX 1: Properly map URLs - use publicUrl for uploaded, localPath for pending
                                                        // FIX 2: Fallback to thumbnail if path not found (prevents empty grid)
                                                        // FIX 3: Filter empty URLs to avoid blank tiles
                                                        if (msg.multipleMedia !=
                                                                null &&
                                                            msg
                                                                .multipleMedia!
                                                                .isNotEmpty) ...[
                                                          Container(
                                                            decoration:
                                                                BoxDecoration(
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        12,
                                                                      ),
                                                                ),
                                                            clipBehavior:
                                                                Clip.antiAlias,
                                                            child: MultiImageMessageBubble(
                                                              imageUrls: msg
                                                                  .multipleMedia!
                                                                  .map((m) {
                                                                    // Priority: publicUrl > localPath > thumbnail
                                                                    if (m
                                                                        .publicUrl
                                                                        .isNotEmpty) {
                                                                      return m
                                                                          .publicUrl; // Uploaded image
                                                                    }
                                                                    final localPath =
                                                                        _localSenderMediaPaths[m
                                                                            .r2Key];
                                                                    if (localPath !=
                                                                            null &&
                                                                        localPath
                                                                            .isNotEmpty) {
                                                                      return localPath; // Pending upload
                                                                    }
                                                                    // Fallback to thumbnail (local path stored during pending)
                                                                    return m
                                                                            .thumbnail
                                                                            .isNotEmpty
                                                                        ? m.thumbnail
                                                                        : '';
                                                                  })
                                                                  .where(
                                                                    (url) => url
                                                                        .isNotEmpty,
                                                                  ) // Filter empty URLs
                                                                  .toList(),
                                                              isMe:
                                                                  isCurrentUser,
                                                              // ✅ Show upload progress for pending images
                                                              uploadProgress:
                                                                  isPending
                                                                  ? msg.multipleMedia!.map((
                                                                      m,
                                                                    ) {
                                                                      final notifier =
                                                                          _pendingUploadNotifiers[m
                                                                              .messageId];
                                                                      return notifier !=
                                                                              null
                                                                          ? notifier.value /
                                                                                100.0
                                                                          : null;
                                                                    }).toList()
                                                                  : null,
                                                              onImageTap:
                                                                  (
                                                                    index,
                                                                    cachedPaths,
                                                                  ) {
                                                                    // Update media list with cached paths
                                                                    final updatedMediaList =
                                                                        <
                                                                          MediaMetadata
                                                                        >[];
                                                                    for (
                                                                      int i = 0;
                                                                      i <
                                                                          msg
                                                                              .multipleMedia!
                                                                              .length;
                                                                      i++
                                                                    ) {
                                                                      final media =
                                                                          msg.multipleMedia![i];
                                                                      updatedMediaList.add(
                                                                        MediaMetadata(
                                                                          localPath:
                                                                              cachedPaths[i] ??
                                                                              media.localPath,
                                                                          publicUrl:
                                                                              media.publicUrl,
                                                                          messageId:
                                                                              media.messageId,
                                                                          mimeType:
                                                                              media.mimeType,
                                                                          fileSize:
                                                                              media.fileSize,
                                                                          r2Key:
                                                                              media.r2Key,
                                                                          thumbnail:
                                                                              media.thumbnail,
                                                                          expiresAt:
                                                                              media.expiresAt,
                                                                          uploadedAt:
                                                                              media.uploadedAt,
                                                                        ),
                                                                      );
                                                                    }
                                                                    // ✅ Open full-screen viewer with zoom, pinch, and swipe
                                                                    Navigator.of(
                                                                      context,
                                                                    ).push(
                                                                      MaterialPageRoute(
                                                                        builder: (_) => _ImageGalleryViewer(
                                                                          mediaList:
                                                                              updatedMediaList,
                                                                          initialIndex:
                                                                              index,
                                                                          localFilePaths:
                                                                              _localSenderMediaPaths,
                                                                        ),
                                                                      ),
                                                                    );
                                                                  },
                                                            ),
                                                          ),
                                                          if (msg
                                                              .content
                                                              .isNotEmpty)
                                                            const SizedBox(
                                                              height: 8,
                                                            ),
                                                        ] else if (msg
                                                                .mediaMetadata !=
                                                            null) ...[
                                                          RepaintBoundary(
                                                            child:
                                                                progressNotifier !=
                                                                    null
                                                                ? ValueListenableBuilder<
                                                                    double
                                                                  >(
                                                                    valueListenable:
                                                                        progressNotifier,
                                                                    builder: (_, value, __) {
                                                                      final progress =
                                                                          ((value / 100).clamp(
                                                                            0.0,
                                                                            1.0,
                                                                          )).toDouble();
                                                                      return MediaPreviewCard(
                                                                        r2Key: msg
                                                                            .mediaMetadata!
                                                                            .r2Key,
                                                                        fileName:
                                                                            _getFileName(
                                                                              msg,
                                                                            ),
                                                                        mimeType:
                                                                            msg.mediaMetadata!.mimeType ??
                                                                            'application/octet-stream',
                                                                        fileSize:
                                                                            msg.mediaMetadata!.fileSize ??
                                                                            0,
                                                                        thumbnailBase64: msg
                                                                            .mediaMetadata!
                                                                            .thumbnail,
                                                                        localPath:
                                                                            localPath,
                                                                        isMe:
                                                                            isCurrentUser,
                                                                        uploading:
                                                                            true,
                                                                        uploadProgress:
                                                                            progress,
                                                                        selectionMode:
                                                                            _selectionMode,
                                                                      );
                                                                    },
                                                                  )
                                                                : MediaPreviewCard(
                                                                    r2Key: msg
                                                                        .mediaMetadata!
                                                                        .r2Key,
                                                                    fileName:
                                                                        _getFileName(
                                                                          msg,
                                                                        ),
                                                                    mimeType:
                                                                        msg
                                                                            .mediaMetadata!
                                                                            .mimeType ??
                                                                        'application/octet-stream',
                                                                    fileSize:
                                                                        msg
                                                                            .mediaMetadata!
                                                                            .fileSize ??
                                                                        0,
                                                                    thumbnailBase64: msg
                                                                        .mediaMetadata!
                                                                        .thumbnail,
                                                                    localPath:
                                                                        localPath,
                                                                    isMe:
                                                                        isCurrentUser,
                                                                    uploading:
                                                                        isPending,
                                                                    uploadProgress:
                                                                        null,
                                                                    selectionMode:
                                                                        _selectionMode,
                                                                  ),
                                                          ),
                                                          if (msg
                                                              .content
                                                              .isNotEmpty)
                                                            const SizedBox(
                                                              height: 8,
                                                            ),
                                                        ],
                                                        if (msg
                                                            .content
                                                            .isNotEmpty)
                                                          Linkify(
                                                            onOpen: (link) async {
                                                              final uri =
                                                                  Uri.parse(
                                                                    link.url,
                                                                  );
                                                              if (await canLaunchUrl(
                                                                uri,
                                                              )) {
                                                                await launchUrl(
                                                                  uri,
                                                                  mode: LaunchMode
                                                                      .externalApplication,
                                                                );
                                                              }
                                                            },
                                                            text:
                                                                LinkUtils.addProtocolToBareUrls(
                                                                  msg.content,
                                                                ),
                                                            options:
                                                                const LinkifyOptions(
                                                                  defaultToHttps:
                                                                      true,
                                                                ),
                                                            style: TextStyle(
                                                              color: textColor,
                                                              fontSize: 15,
                                                            ),
                                                            linkStyle: TextStyle(
                                                              color:
                                                                  isCurrentUser
                                                                  ? const Color(
                                                                      0xFF0066CC,
                                                                    )
                                                                  : (widget.senderRole ==
                                                                            'parent'
                                                                        ? const Color(
                                                                            0xFF14A670,
                                                                          )
                                                                        : const Color(
                                                                            0xFF6366F1,
                                                                          )),
                                                              fontSize: 15,
                                                              decoration:
                                                                  TextDecoration
                                                                      .underline,
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Padding(
                                                padding: EdgeInsets.only(
                                                  left: isCurrentUser ? 0 : 8,
                                                  right: isCurrentUser ? 8 : 0,
                                                ),
                                                child: Text(
                                                  _formatTime(msg.createdAt),
                                                  style: TextStyle(
                                                    color:
                                                        (isDark
                                                                ? Colors.white
                                                                : Colors.black)
                                                            .withOpacity(0.5),
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      if (_selectionMode && isCurrentUser)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            left: 8,
                                            top: 8,
                                          ),
                                          child: GestureDetector(
                                            onTap: () {
                                              if (isSelected) {
                                                if (selectedSet.length > 2) {
                                                  final updated = {
                                                    ...selectedSet,
                                                  };
                                                  updated.remove(msg.messageId);
                                                  _selectedMessages.value =
                                                      updated;
                                                }
                                              } else {
                                                _selectedMessages.value = {
                                                  ...selectedSet,
                                                  msg.messageId,
                                                };
                                              }
                                            },
                                            child: Container(
                                              width: 24,
                                              height: 24,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: isSelected
                                                      ? primaryColor
                                                      : Colors.grey[400]!,
                                                  width: isSelected ? 2 : 1.5,
                                                ),
                                                color: isSelected
                                                    ? primaryColor
                                                    : Colors.transparent,
                                              ),
                                              child: isSelected
                                                  ? Center(
                                                      child: Icon(
                                                        Icons.check,
                                                        size: 16,
                                                        color: Colors.white,
                                                      ),
                                                    )
                                                  : null,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        );
                      },
                    ),
                    // Loading indicator overlay using ValueListenableBuilder
                    ValueListenableBuilder<bool>(
                      valueListenable: _isLoadingMoreNotifier,
                      builder: (context, isLoading, _) {
                        if (!isLoading) {
                          return const SizedBox.shrink();
                        }
                        return Positioned(
                          top: 16,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.grey[800]
                                    : Colors.grey[200],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: SizedBox(
                                width: 30,
                                height: 30,
                                child: CircularProgressIndicator(
                                  color: primaryColor,
                                  strokeWidth: 2.5,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ),
          _buildMessageInput(isDark),
          // ✅ EMOJI PANEL - WhatsApp-style with custom search
        ],
      ),
    );
  }

  Widget _buildMessageInput(bool isDark) {
    final primaryColor = widget.senderRole == 'teacher'
        ? teacherViolet
        : parentGreen;

    return ValueListenableBuilder<bool>(
      valueListenable: _isRecording,
      builder: (context, isRecording, _) {
        if (isRecording) {
          return _buildRecordingBar(isDark, primaryColor);
        }

        return Container(
          color: isDark ? primaryBackground : Colors.grey.shade50,
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: SafeArea(
            top: false,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Attachment button - outside input
                Container(
                  width: 42,
                  height: 42,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: isDark ? secondaryBackground : Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _isUploading ? null : _showAttachmentSheet,
                      borderRadius: BorderRadius.circular(21),
                      child: Icon(
                        Icons.add_rounded,
                        color: _isUploading ? mutedText : primaryColor,
                        size: 24,
                      ),
                    ),
                  ),
                ),
                // Main input field - compact pill shape
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(
                      minHeight: 42,
                      maxHeight: 100,
                    ),
                    decoration: BoxDecoration(
                      color: secondaryBackground,
                      borderRadius: BorderRadius.circular(21),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            minLines: 1,
                            maxLines: 4,
                            cursorColor: primaryColor,
                            style: const TextStyle(
                              color: primaryText,
                              fontSize: 15,
                              height: 1.4,
                            ),
                            decoration: const InputDecoration(
                              hintText: 'Message',
                              hintStyle: TextStyle(
                                color: mutedText,
                                fontSize: 15,
                              ),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.fromLTRB(
                                16,
                                11,
                                8,
                                11,
                              ),
                              isDense: true,
                            ),
                            keyboardType: TextInputType.multiline,
                            textCapitalization: TextCapitalization.sentences,
                            readOnly: _isRecording.value,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Send/Mic button - circular FAB
                ValueListenableBuilder<bool>(
                  valueListenable: _hasText,
                  builder: (context, hasText, _) {
                    return Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: primaryColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: primaryColor.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _isRecording.value
                              ? _stopAndSendRecording
                              : (hasText ? _sendMessage : _startRecording),
                          borderRadius: BorderRadius.circular(21),
                          child: Icon(
                            _isRecording.value
                                ? Icons.send_rounded
                                : (hasText
                                      ? Icons.send_rounded
                                      : Icons.mic_rounded),
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecordingBar(bool isDark, Color primaryColor) {
    return ValueListenableBuilder<int>(
      valueListenable: _recordingDuration,
      builder: (context, duration, _) {
        final minutes = duration ~/ 60;
        final seconds = duration % 60;
        final timeStr =
            '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          color: isDark ? primaryBackground : Colors.grey.shade50,
          child: SafeArea(
            top: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Delete button
                GestureDetector(
                  onTap: _deleteRecording,
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.delete,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                // Recording indicator dot
                Container(
                  width: 14,
                  height: 14,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),

                const SizedBox(width: 16),

                // Timer
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.all(Radius.circular(18)),
                  ),
                  child: Text(
                    timeStr,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),

                const Spacer(),

                // Send button
                GestureDetector(
                  onTap: _stopAndSendRecording,
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: primaryColor,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.send,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAttachmentSheet() {
    final primaryColor = widget.senderRole == 'teacher'
        ? teacherViolet
        : parentGreen;
    showModernAttachmentSheet(
      context,
      onCameraTap: _pickAndSendCamera,
      onImageTap: _pickAndSendImage,
      onDocumentTap: _pickAndSendPDF,
      onAudioTap: _pickAndSendAudioFile,
      onPollTap: _navigateToPollScreen,
      mindmapEnabled: false, // ✅ Disable mindmap in parent-teacher groups
      color: primaryColor,
    );
  }

  void _navigateToPollScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/create_poll'),
        builder: (context) =>
            CreatePollScreen(chatId: widget.groupId, chatType: 'ptGroup'),
      ),
    );
  }

  Future<void> _pickAndSendCamera() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.currentUser;
    if (user == null) return;

    try {
      final picked = await _imagePicker.pickImage(source: ImageSource.camera);
      if (picked == null) return;

      final file = File(picked.path);
      final pendingId = 'pending:${DateTime.now().millisecondsSinceEpoch}';

      // Create optimistic pending message
      final pendingMetadata = MediaMetadata(
        messageId: pendingId,
        r2Key: 'pending/${file.path.split('/').last}',
        publicUrl: '',
        thumbnail: '',
        expiresAt: DateTime.now().add(const Duration(days: 365)),
        uploadedAt: DateTime.now(),
        fileSize: await file.length(),
        mimeType: 'image/jpeg',
        originalFileName: file.path.split('/').last,
      );

      final pendingMessage = CommunityMessageModel(
        messageId: pendingId,
        communityId: widget.groupId,
        senderId: user.uid,
        senderName: user.name,
        senderRole: widget.senderRole,
        senderAvatar: user.profileImage ?? '',
        type: 'image',
        content: '',
        imageUrl: '',
        fileUrl: '',
        fileName: file.path.split('/').last,
        mediaMetadata: pendingMetadata,
        createdAt: DateTime.now(),
        isEdited: false,
        isDeleted: false,
        isPinned: false,
        reactions: {},
        replyTo: '',
        replyCount: 0,
        isReported: false,
        reportCount: 0,
      );

      setState(() {
        _pendingMessages.insert(0, pendingMessage);
        _pendingUploadNotifiers[pendingId] = ValueNotifier<double>(0);
        _localSenderMediaPaths[pendingId] = file.path;
        _lastUploadPercent[pendingId] = -1;
      });

      // Scroll to bottom to show new message
      Future.delayed(const Duration(milliseconds: 100), () {
        if (scrollController.hasClients) {
          scrollController.jumpTo(0);
        }
      });

      // Upload in background
      final mediaMessage = await _mediaUploadService.uploadMedia(
        file: file,
        conversationId: widget.groupId,
        senderId: user.uid,
        senderRole: widget.senderRole,
        mediaType: 'community',
        onProgress: (progress) {
          if (!mounted) return;
          final percent = progress.toInt().clamp(0, 100);
          final last = _lastUploadPercent[pendingId] ?? -1;
          final shouldUpdate =
              (last == -1) || (percent == 100) || (percent - last >= 5);
          if (shouldUpdate) {
            _lastUploadPercent[pendingId] = percent;
            _pendingUploadNotifiers[pendingId]?.value = progress.toDouble();
          }
        },
      );

      if (mounted) {
        setState(() {
          _pendingMessages.removeWhere((m) => m.messageId == pendingId);
          _pendingUploadNotifiers.remove(pendingId)?.dispose();
          _localSenderMediaPaths.remove(pendingId);
          _lastUploadPercent.remove(pendingId);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send image: $e')));
      }
    }
  }

  Future<void> _pickAndSendImage() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.currentUser;
    if (user == null) return;

    try {
      // Try pickMultiImage for multiple image selection (up to 5)
      final picked = await _imagePicker.pickMultiImage(limit: 5);

      if (picked.isEmpty) return;

      // If multiple images selected, handle as multi-image message
      if (picked.length > 1) {
        await _uploadMultipleImages(picked.map((xf) => File(xf.path)).toList());
        return;
      }

      // Single image - use existing logic
      final file = File(picked.first.path);
      final pendingId = 'pending:${DateTime.now().millisecondsSinceEpoch}';

      // Create optimistic pending message
      final pendingMetadata = MediaMetadata(
        messageId: pendingId,
        r2Key: 'pending/${file.path.split('/').last}',
        publicUrl: '',
        thumbnail: '',
        expiresAt: DateTime.now().add(const Duration(days: 365)),
        uploadedAt: DateTime.now(),
        fileSize: await file.length(),
        mimeType: 'image/jpeg',
        originalFileName: file.path.split('/').last,
      );

      final pendingMessage = CommunityMessageModel(
        messageId: pendingId,
        communityId: widget.groupId,
        senderId: user.uid,
        senderName: user.name,
        senderRole: widget.senderRole,
        senderAvatar: user.profileImage ?? '',
        type: 'image',
        content: '',
        imageUrl: '',
        fileUrl: '',
        fileName: file.path.split('/').last,
        mediaMetadata: pendingMetadata,
        createdAt: DateTime.now(),
        isEdited: false,
        isDeleted: false,
        isPinned: false,
        reactions: {},
        replyTo: '',
        replyCount: 0,
        isReported: false,
        reportCount: 0,
      );

      setState(() {
        _pendingMessages.insert(0, pendingMessage);
        _pendingUploadNotifiers[pendingId] = ValueNotifier<double>(0);
        _localSenderMediaPaths[pendingId] = file.path;
        _lastUploadPercent[pendingId] = -1;
      });

      // Scroll to bottom to show new message
      Future.delayed(const Duration(milliseconds: 100), () {
        if (scrollController.hasClients) {
          scrollController.jumpTo(0);
        }
      });

      // Upload in background
      final mediaMessage = await _mediaUploadService.uploadMedia(
        file: file,
        conversationId: widget.groupId,
        senderId: user.uid,
        senderRole: widget.senderRole,
        mediaType: 'community',
        onProgress: (progress) {
          if (!mounted) return;

          // Convert to integer percent and throttle updates to reduce list rebuilds
          final percent = progress.toInt().clamp(0, 100);
          final last = _lastUploadPercent[pendingId] ?? -1;

          // Always allow first update and 100%; otherwise update on >= 5% change
          final shouldUpdate =
              last < 0 || percent == 100 || (percent - last) >= 5;
          if (!shouldUpdate) return;

          _lastUploadPercent[pendingId] = percent;
          _pendingUploadNotifiers[pendingId]?.value = percent.toDouble();
        },
      );

      final r2Key = mediaMessage.r2Url.split('/').skip(3).join('/');
      final metadata = MediaMetadata(
        messageId: mediaMessage.id,
        r2Key: r2Key,
        publicUrl: mediaMessage.r2Url,
        thumbnail: '',
        expiresAt: DateTime.now().add(const Duration(days: 365)),
        uploadedAt: DateTime.now(),
        fileSize: mediaMessage.fileSize,
        mimeType: mediaMessage.fileType,
        originalFileName: mediaMessage.fileName,
      );

      await _service.sendMessage(
        groupId: widget.groupId,
        senderId: user.uid,
        senderName: user.name,
        senderRole: widget.senderRole,
        content: '',
        mediaType: 'image',
        mediaMetadata: metadata,
      );

      // Cache the uploaded file so we don't re-download it
      await _mediaRepository.cacheUploadedMedia(
        r2Key: r2Key,
        localPath: file.path,
        fileName: file.path.split('/').last,
        mimeType: 'image/jpeg',
        fileSize: await file.length(),
      );

      // Remove pending message after successful upload
      if (mounted) {
        setState(() {
          _pendingMessages.removeWhere((m) => m.messageId == pendingId);
          _pendingUploadNotifiers.remove(pendingId)?.dispose();
          // Keep local file mapped to the cloud key so we don't re-download our own upload
          _localSenderMediaPaths[r2Key] = file.path;
          _localSenderMediaPaths.remove(pendingId);
          _lastUploadPercent.remove(pendingId);
        });

        // ✅ Scroll to bottom to show newly sent image
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send image: $e')));
      }
    }
  }

  /// Upload multiple images as a single message
  Future<void> _uploadMultipleImages(List<File> files) async {
    if (files.isEmpty) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.currentUser;
    if (user == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final baseTimestamp = now > _lastUploadTimestamp
        ? now
        : _lastUploadTimestamp + 1;
    _lastUploadTimestamp = baseTimestamp;
    final groupMessageId = 'pending_${baseTimestamp}_${user.uid.hashCode}';
    final List<MediaMetadata> mediaList = [];
    final List<String> localPaths = [];
    final List<Map<String, dynamic>> mediaListForCache = [];

    // Create metadata for each image with local path
    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      if (!file.existsSync()) continue;

      final messageId = '${groupMessageId}_$i';
      final fileSize = await file.length();
      final fileName = file.path.split('/').last;
      localPaths.add(file.path);

      final metadata = MediaMetadata(
        messageId: messageId,
        r2Key: 'pending/$messageId',
        publicUrl: '',
        thumbnail: file.path,
        expiresAt: DateTime.now().add(const Duration(days: 365)),
        uploadedAt: DateTime.now(),
        fileSize: fileSize,
        mimeType: 'image/jpeg',
        originalFileName: fileName,
      );
      mediaList.add(metadata);

      // Format for LocalMessageRepository
      mediaListForCache.add({
        'messageId': messageId,
        'r2Key': 'pending/$messageId',
        'publicUrl': '',
        'thumbnail': file.path,
        'localPath': file.path,
        'originalFileName': fileName,
        'fileSize': fileSize,
        'mimeType': 'image/jpeg',
        'uploadProgress': 0.0,
      });
    }

    if (mediaList.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No valid images found')));
      }
      return;
    }

    // Create pending message with multiple media
    final pendingMessage = CommunityMessageModel(
      messageId: 'pending:$groupMessageId',
      communityId: widget.groupId,
      senderId: user.uid,
      senderName: user.name,
      senderRole: widget.senderRole,
      senderAvatar: user.profileImage ?? '',
      type: 'image',
      content: '',
      imageUrl: '',
      fileUrl: '',
      fileName: '',
      multipleMedia: mediaList,
      createdAt: DateTime.now(),
      isEdited: false,
      isDeleted: false,
      isPinned: false,
      reactions: {},
      replyTo: '',
      replyCount: 0,
      isReported: false,
      reportCount: 0,
    );

    // ✅ CRITICAL: Save pending message to LocalMessageRepository (persists across navigation)
    try {
      final pendingLocalMsg = LocalMessage(
        messageId: groupMessageId,
        chatId: widget.groupId,
        chatType: 'ptGroup',
        senderId: user.uid,
        senderName: user.name,
        timestamp: baseTimestamp,
        messageText: '',
        multipleMedia: mediaListForCache,
        isPending: true,
      );
      await _localRepo.saveMessage(pendingLocalMsg);
      print('💾 Pending message saved to cache (survives navigation)');
    } catch (e) {
      print('⚠️ Failed to cache pending message: $e');
    }

    setState(() {
      _pendingMessages.insert(0, pendingMessage);
      print(
        '✅ [PENDING_DEBUG] Added pending message to list: ${pendingMessage.messageId}',
      );
      print('   - Sender: ${user.uid}');
      print('   - Timestamp: $baseTimestamp');
      print('   - MultipleMedia count: ${mediaList.length}');
      print('   - Total pending messages now: ${_pendingMessages.length}');

      // Track local paths and upload progress for each media item
      for (int i = 0; i < localPaths.length; i++) {
        final messageId = '${groupMessageId}_$i';
        _localSenderMediaPaths[messageId] = localPaths[i];
        _pendingUploadNotifiers[messageId] = ValueNotifier<double>(0);
        _lastUploadPercent[messageId] = -1;
        print(
          '   - Media $i: messageId=$messageId, localPath=${localPaths[i]}',
        );
      }
    });

    // Upload all images
    try {
      print('🚀 [UPLOAD_DEBUG] Starting upload for ${files.length} files');
      final uploadedMetadata = <MediaMetadata>[];

      for (int i = 0; i < files.length; i++) {
        final file = files[i];
        final messageId = '${groupMessageId}_$i';
        print('📤 [UPLOAD_DEBUG] Uploading file $i: ${file.path}');

        // Upload to R2 with progress tracking
        final mediaMessage = await _mediaUploadService.uploadMedia(
          file: file,
          conversationId: widget.groupId,
          senderId: user.uid,
          senderRole: widget.senderRole,
          mediaType: 'community',
          onProgress: (progress) async {
            // Smooth progress updates (only update on percentage change)
            final percent = (progress / 100.0 * 100).round();
            final last = _lastUploadPercent[messageId] ?? -1;
            if (percent != last) {
              _lastUploadPercent[messageId] = percent;

              if (mounted) {
                // Update UI progress
                _pendingUploadNotifiers[messageId]?.value = percent.toDouble();

                // ✅ Trigger rebuild to show live progress for multi-image messages
                setState(() {});

                // ✅ Save progress to cache every 10% to persist across navigation
                if (percent % 10 == 0 || percent == 100) {
                  final mediaWithProgress = mediaList.map((m) {
                    final mId = m.messageId;
                    final progress = _pendingUploadNotifiers[mId]?.value ?? 0.0;
                    return {
                      'messageId': mId,
                      'localPath': _localSenderMediaPaths[mId],
                      'uploadProgress': progress / 100.0,
                      'r2Key': m.r2Key,
                      'publicUrl': m.publicUrl,
                      'fileSize': m.fileSize,
                      'mimeType': m.mimeType,
                      'originalFileName': m.originalFileName,
                    };
                  }).toList();
                  _updatePendingMessageCache(
                    'pending:$groupMessageId',
                    mediaWithProgress,
                  );
                }
              }

              // Save to cache at 10% intervals (even if not mounted)
              if (percent % 10 == 0 || percent == 100) {
                try {
                  final cachedMsg = await _localRepo.getMessageById(
                    groupMessageId,
                  );
                  if (cachedMsg != null && cachedMsg.multipleMedia != null) {
                    final updatedMedia = cachedMsg.multipleMedia!.map((media) {
                      if (media['messageId'] == messageId) {
                        return {...media, 'uploadProgress': progress / 100.0};
                      }
                      return media;
                    }).toList();

                    final updatedMsg = LocalMessage(
                      messageId: cachedMsg.messageId,
                      chatId: cachedMsg.chatId,
                      chatType: cachedMsg.chatType,
                      senderId: cachedMsg.senderId,
                      senderName: cachedMsg.senderName,
                      timestamp: cachedMsg.timestamp,
                      messageText: cachedMsg.messageText,
                      multipleMedia: updatedMedia,
                      isPending: true,
                    );
                    await _localRepo.saveMessage(updatedMsg);
                  }
                } catch (e) {
                  // Silent fail - progress still works in current session
                }
              }
            }
          },
        );

        print('✅ [UPLOAD_DEBUG] File $i uploaded: ${mediaMessage.r2Url}');
        final r2Key = mediaMessage.r2Url.split('/').skip(3).join('/');
        final publicUrl = mediaMessage.r2Url;

        final metadata = MediaMetadata(
          messageId: messageId,
          r2Key: r2Key,
          publicUrl: publicUrl,
          thumbnail: '',
          expiresAt: DateTime.now().add(const Duration(days: 365)),
          uploadedAt: DateTime.now(),
          fileSize: mediaMessage.fileSize,
          mimeType: mediaMessage.fileType,
          originalFileName: mediaMessage.fileName,
        );

        uploadedMetadata.add(metadata);

        print('💾 [UPLOAD_DEBUG] Cached media file $i');
        // Cache the uploaded file
        await _mediaRepository.cacheUploadedMedia(
          r2Key: r2Key,
          localPath: file.path,
          fileName: file.path.split('/').last,
          mimeType: 'image/jpeg',
          fileSize: await file.length(),
        );
      }

      print('🔥 [UPLOAD_DEBUG] All files uploaded, writing to Firestore');
      // ✅ Create Firestore message with auto-generated ID (like staff room)
      // ✅ CRITICAL: Use correct collection - parent_teacher_groups, not communities!
      final messageTimestamp = DateTime.now().millisecondsSinceEpoch;
      print(
        '🔥 [UPLOAD_DEBUG] Writing to parent_teacher_groups/${widget.groupId}/messages',
      );
      final messageRef = await FirebaseFirestore.instance
          .collection('parent_teacher_groups')
          .doc(widget.groupId)
          .collection('messages')
          .add({
            'senderId': user.uid,
            'senderName': user.name,
            'senderRole': widget.senderRole,
            'senderAvatar': user.profileImage ?? '',
            'type': 'image',
            'content': '',
            'imageUrl': '',
            'fileUrl': '',
            'fileName': '',
            'multipleMedia': uploadedMetadata
                .map((m) => m.toFirestore())
                .toList(),
            'timestamp': FieldValue.serverTimestamp(),
            'createdAt': messageTimestamp,
            'isEdited': false,
            'isDeleted': false,
            'isPinned': false,
            'reactions': {},
            'replyTo': '',
            'replyCount': 0,
            'isReported': false,
            'reportCount': 0,
          });

      print('✅ [UPLOAD_DEBUG] Firestore message created: ${messageRef.id}');
      // ✅ CRITICAL: Save final message to LocalMessageRepository with Firestore ID
      final uploadedMediaForCache = uploadedMetadata
          .map(
            (m) => {
              'messageId': m.messageId,
              'publicUrl': m.publicUrl,
              'thumbnail': m.thumbnail,
              'originalFileName': m.originalFileName,
              'fileSize': m.fileSize,
              'mimeType': m.mimeType,
              'r2Key': m.r2Key,
            },
          )
          .toList();

      try {
        final localMessage = LocalMessage(
          messageId: messageRef.id, // Use Firestore auto-generated ID
          chatId: widget.groupId,
          chatType: 'ptGroup',
          senderId: user.uid,
          senderName: user.name,
          timestamp: messageTimestamp,
          multipleMedia: uploadedMediaForCache,
        );
        await _localRepo.saveMessage(localMessage);

        // ✅ Keep pending cache until Firestore message is visible
        print(
          '✅ Final message saved to cache (ID: ${messageRef.id}); pending retained until sync',
        );
      } catch (e) {
        print('⚠️ Failed to save final message to cache: $e');
      }

      // ✅ Keep pending message in UI until Firestore sync replaces it
      if (mounted) {
        setState(() {
          // Keep local files mapped to the cloud keys for offline access
          for (int i = 0; i < uploadedMetadata.length; i++) {
            final r2Key = uploadedMetadata[i].r2Key;
            final messageId = '${groupMessageId}_$i';
            _localSenderMediaPaths[r2Key] = localPaths[i];
            _localSenderMediaPaths.remove(messageId);
          }
        });
      }

      // ✅ Scroll to bottom after cleanup
      if (mounted) {
        _scrollToBottom();
      }
    } catch (e) {
      print('❌ [UPLOAD_DEBUG] Upload failed: $e');
      print('❌ [UPLOAD_DEBUG] Stack trace: ${StackTrace.current}');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to upload images: $e')));
        // Remove pending message on error
        setState(() {
          _pendingMessages.removeWhere(
            (m) => m.messageId == 'pending:$groupMessageId',
          );
          // Clean up progress notifiers
          for (int i = 0; i < files.length; i++) {
            final messageId = '${groupMessageId}_$i';
            _pendingUploadNotifiers[messageId]?.dispose();
            _pendingUploadNotifiers.remove(messageId);
            _lastUploadPercent.remove(messageId);
          }
        });

        // Delete pending message from cache on error
        try {
          await _localRepo.deletePendingMessage(groupMessageId);
        } catch (e) {
          print('⚠️ Failed to delete pending message from cache: $e');
        }
      }
    }
  }

  Future<void> _pickAndSendPDF() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.currentUser;
    if (user == null) return;

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
      );
      if (result == null || result.files.single.path == null) return;

      final file = File(result.files.single.path!);
      final pendingId = 'pending:${DateTime.now().millisecondsSinceEpoch}';
      final fileName = file.path.split('/').last;
      final fileSize = await file.length();
      final fileExtension = fileName.split('.').last.toLowerCase();

      // Determine MIME type based on extension
      String mimeType = 'application/pdf';
      if (fileExtension == 'doc') {
        mimeType = 'application/msword';
      } else if (fileExtension == 'docx') {
        mimeType =
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      } else if (fileExtension == 'xls') {
        mimeType = 'application/vnd.ms-excel';
      } else if (fileExtension == 'xlsx') {
        mimeType =
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      } else if (fileExtension == 'ppt') {
        mimeType = 'application/vnd.ms-powerpoint';
      } else if (fileExtension == 'pptx') {
        mimeType =
            'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      } else if (fileExtension == 'txt') {
        mimeType = 'text/plain';
      } else if (fileExtension == 'csv') {
        mimeType = 'text/csv';
      } else if (fileExtension == 'rtf') {
        mimeType = 'application/rtf';
      } else if (fileExtension == 'odt') {
        mimeType = 'application/vnd.oasis.opendocument.text';
      } else if (fileExtension == 'ods') {
        mimeType = 'application/vnd.oasis.opendocument.spreadsheet';
      } else if (fileExtension == 'odp') {
        mimeType = 'application/vnd.oasis.opendocument.presentation';
      }

      final pendingMetadata = MediaMetadata(
        messageId: pendingId,
        r2Key: 'pending/$fileName',
        publicUrl: '',
        thumbnail: '',
        expiresAt: DateTime.now().add(const Duration(days: 365)),
        uploadedAt: DateTime.now(),
        fileSize: fileSize,
        mimeType: mimeType,
        originalFileName: fileName,
      );

      final pendingMessage = CommunityMessageModel(
        messageId: pendingId,
        communityId: widget.groupId,
        senderId: user.uid,
        senderName: user.name,
        senderRole: widget.senderRole,
        senderAvatar: user.profileImage ?? '',
        type: 'pdf',
        content: '',
        imageUrl: '',
        fileUrl: '',
        fileName: fileName,
        mediaMetadata: pendingMetadata,
        createdAt: DateTime.now(),
        isEdited: false,
        isDeleted: false,
        isPinned: false,
        reactions: {},
        replyTo: '',
        replyCount: 0,
        isReported: false,
        reportCount: 0,
      );

      setState(() {
        _pendingMessages.insert(0, pendingMessage);
        _pendingUploadNotifiers[pendingId] = ValueNotifier<double>(0);
        _lastUploadPercent[pendingId] = -1;
      });

      // ✅ Save pending PDF to cache immediately for persistence
      try {
        final pendingLocalMsg = LocalMessage(
          messageId: pendingId,
          chatId: widget.groupId,
          chatType: 'ptGroup',
          senderId: user.uid,
          senderName: user.name,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          messageText: '',
          multipleMedia: [
            {
              'messageId': pendingId,
              'localPath': file.path,
              'uploadProgress': 0.0,
              'originalFileName': fileName,
              'fileSize': fileSize,
              'mimeType': mimeType,
            },
          ],
          isPending: true,
        );
        await _localRepo.saveMessage(pendingLocalMsg);
        print('💾 PDF pending message saved to cache');
      } catch (e) {
        print('⚠️ Failed to cache pending PDF: $e');
      }

      // Upload in background with optimistic UI
      final mediaMessage = await _mediaUploadService.uploadMedia(
        file: file,
        conversationId: widget.groupId,
        senderId: user.uid,
        senderRole: widget.senderRole,
        mediaType: 'community',
        onProgress: (progress) {
          if (!mounted) return;
          final percent = progress.toInt().clamp(0, 100);
          final last = _lastUploadPercent[pendingId] ?? -1;
          final shouldUpdate =
              last < 0 || percent == 100 || (percent - last) >= 5;
          if (!shouldUpdate) return;
          _lastUploadPercent[pendingId] = percent;
          _pendingUploadNotifiers[pendingId]?.value = percent.toDouble();

          // ✅ Update cache with progress every 20% for persistence
          if (percent % 20 == 0 || percent == 100) {
            _updatePendingMessageCache(pendingId, [
              {
                'messageId': pendingId,
                'localPath': file.path,
                'uploadProgress': percent / 100.0,
                'originalFileName': fileName,
                'fileSize': fileSize,
                'mimeType': mimeType,
              },
            ]);
          }
        },
      );

      final r2Key = mediaMessage.r2Url.split('/').skip(3).join('/');
      final metadata = MediaMetadata(
        messageId: mediaMessage.id,
        r2Key: r2Key,
        publicUrl: mediaMessage.r2Url,
        thumbnail: '',
        expiresAt: DateTime.now().add(const Duration(days: 365)),
        uploadedAt: DateTime.now(),
        fileSize: mediaMessage.fileSize,
        mimeType: mediaMessage.fileType,
        originalFileName: mediaMessage.fileName,
      );

      await _service.sendMessage(
        groupId: widget.groupId,
        senderId: user.uid,
        senderName: user.name,
        senderRole: widget.senderRole,
        content: '',
        mediaType: 'pdf',
        mediaMetadata: metadata,
      );

      // Cache the uploaded file so we don't re-download it
      await _mediaRepository.cacheUploadedMedia(
        r2Key: r2Key,
        localPath: file.path,
        fileName: file.path.split('/').last,
        mimeType: 'application/pdf',
        fileSize: await file.length(),
      );

      // ✅ Scroll to bottom to show newly sent PDF
      _scrollToBottom();

      if (mounted) {
        setState(() {
          _pendingMessages.removeWhere((m) => m.messageId == pendingId);
          _pendingUploadNotifiers.remove(pendingId)?.dispose();
          _lastUploadPercent.remove(pendingId);
        });

        // ✅ Scroll to bottom to show newly sent PDF
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send PDF: $e')));
      }
    }
  }

  Future<void> _pickAndSendAudioFile() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.currentUser;
    if (user == null) return;

    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.audio);
      if (result == null || result.files.single.path == null) return;

      final file = File(result.files.single.path!);
      final pendingId = 'pending:${DateTime.now().millisecondsSinceEpoch}';
      final fileName = file.path.split('/').last;
      final fileSize = await file.length();
      final ext = result.files.single.extension?.toLowerCase();
      final mime = _inferAudioMime(ext);

      final pendingMetadata = MediaMetadata(
        messageId: pendingId,
        r2Key: 'pending/$fileName',
        publicUrl: '',
        thumbnail: '',
        expiresAt: DateTime.now().add(const Duration(days: 365)),
        uploadedAt: DateTime.now(),
        fileSize: fileSize,
        mimeType: mime,
        originalFileName: fileName,
      );

      final pendingMessage = CommunityMessageModel(
        messageId: pendingId,
        communityId: widget.groupId,
        senderId: user.uid,
        senderName: user.name,
        senderRole: widget.senderRole,
        senderAvatar: user.profileImage ?? '',
        type: 'audio',
        content: '',
        imageUrl: '',
        fileUrl: '',
        fileName: fileName,
        mediaMetadata: pendingMetadata,
        createdAt: DateTime.now(),
        isEdited: false,
        isDeleted: false,
        isPinned: false,
        reactions: {},
        replyTo: '',
        replyCount: 0,
        isReported: false,
        reportCount: 0,
      );

      setState(() {
        _pendingMessages.insert(0, pendingMessage);
        _pendingUploadNotifiers[pendingId] = ValueNotifier<double>(0.01);
        _lastUploadPercent[pendingId] = -1;
      });

      final mediaMessage = await _mediaUploadService.uploadMedia(
        file: file,
        conversationId: widget.groupId,
        senderId: user.uid,
        senderRole: widget.senderRole,
        mediaType: 'community',
        onProgress: (progress) {
          if (!mounted) return;
          final percent = progress.toInt().clamp(0, 100);
          final last = _lastUploadPercent[pendingId] ?? -1;
          final shouldUpdate =
              last < 0 || percent == 100 || (percent - last) >= 5;
          if (!shouldUpdate) return;
          _lastUploadPercent[pendingId] = percent;
          _pendingUploadNotifiers[pendingId]?.value = percent.toDouble();
        },
      );

      final r2Key = mediaMessage.r2Url.split('/').skip(3).join('/');
      final metadata = MediaMetadata(
        messageId: mediaMessage.id,
        r2Key: r2Key,
        publicUrl: mediaMessage.r2Url,
        thumbnail: '',
        expiresAt: DateTime.now().add(const Duration(days: 365)),
        uploadedAt: DateTime.now(),
        fileSize: mediaMessage.fileSize,
        mimeType: mediaMessage.fileType,
        originalFileName: mediaMessage.fileName,
      );

      await _service.sendMessage(
        groupId: widget.groupId,
        senderId: user.uid,
        senderName: user.name,
        senderRole: widget.senderRole,
        content: '',
        mediaType: 'audio',
        mediaMetadata: metadata,
      );

      // Cache the uploaded file so we don't re-download it
      await _mediaRepository.cacheUploadedMedia(
        r2Key: r2Key,
        localPath: file.path,
        fileName: fileName,
        mimeType: mime,
        fileSize: fileSize,
      );

      // ✅ Scroll to bottom to show newly sent audio
      _scrollToBottom();

      if (mounted) {
        setState(() {
          _pendingMessages.removeWhere((m) => m.messageId == pendingId);
          _pendingUploadNotifiers.remove(pendingId)?.dispose();
          _lastUploadPercent.remove(pendingId);
        });

        // ✅ Scroll to bottom to show newly sent audio
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send audio: $e')));
      }
    }
  }

  Future<void> _startRecording() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.currentUser;
    if (user == null) return;

    if (!await _audioRecorder.hasPermission()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission needed')),
      );
      return;
    }

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/ptg_${DateTime.now().millisecondsSinceEpoch}.m4a';
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

  Future<void> _stopAndSendRecording() async {
    if (!_isRecording.value) return;
    _recordingTimer?.cancel();

    final path = await _audioRecorder.stop();
    setState(() => _isRecording.value = false);

    if (path == null) return;
    final file = File(path);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.currentUser;
    if (user == null) return;

    final pendingId = 'pending:${DateTime.now().millisecondsSinceEpoch}';
    final fileName = file.path.split('/').last;

    try {
      // Create optimistic pending message
      final pendingMetadata = MediaMetadata(
        messageId: pendingId,
        r2Key: 'pending/$fileName',
        publicUrl: '',
        thumbnail: '',
        expiresAt: DateTime.now().add(const Duration(days: 365)),
        uploadedAt: DateTime.now(),
        fileSize: await file.length(),
        mimeType: 'audio/mp4',
        originalFileName: fileName,
      );

      final pendingMessage = CommunityMessageModel(
        messageId: pendingId,
        communityId: widget.groupId,
        senderId: user.uid,
        senderName: user.name,
        senderRole: widget.senderRole,
        senderAvatar: user.profileImage ?? '',
        type: 'audio',
        content: '',
        imageUrl: '',
        fileUrl: '',
        fileName: fileName,
        mediaMetadata: pendingMetadata,
        createdAt: DateTime.now(),
        isEdited: false,
        isDeleted: false,
        isPinned: false,
        reactions: {},
        replyTo: '',
        replyCount: 0,
        isReported: false,
        reportCount: 0,
      );

      setState(() {
        _pendingMessages.insert(0, pendingMessage);
        _pendingUploadNotifiers[pendingId] = ValueNotifier<double>(0.01);
        _localSenderMediaPaths[pendingId] = file.path;
        _lastUploadPercent[pendingId] = -1;
      });

      // Scroll to bottom to show new message
      Future.delayed(const Duration(milliseconds: 100), () {
        if (scrollController.hasClients) {
          scrollController.jumpTo(0);
        }
      });

      // Upload in background
      final mediaMessage = await _mediaUploadService.uploadMedia(
        file: file,
        conversationId: widget.groupId,
        senderId: user.uid,
        senderRole: widget.senderRole,
        mediaType: 'community',
        onProgress: (progress) {
          final percent = (progress * 100).toInt();
          if (_lastUploadPercent[pendingId] != percent) {
            _lastUploadPercent[pendingId] = percent;
            _pendingUploadNotifiers[pendingId]?.value = percent.toDouble();
          }
        },
      );

      final r2Key = mediaMessage.r2Url.split('/').skip(3).join('/');
      final metadata = MediaMetadata(
        messageId: mediaMessage.id,
        r2Key: r2Key,
        publicUrl: mediaMessage.r2Url,
        thumbnail: '',
        expiresAt: DateTime.now().add(const Duration(days: 365)),
        uploadedAt: DateTime.now(),
        fileSize: mediaMessage.fileSize,
        mimeType: mediaMessage.fileType,
        originalFileName: mediaMessage.fileName,
      );

      await _service.sendMessage(
        groupId: widget.groupId,
        senderId: user.uid,
        senderName: user.name,
        senderRole: widget.senderRole,
        content: '',
        mediaType: 'audio',
        mediaMetadata: metadata,
      );

      // Cache the uploaded recording so we don't re-download it
      await _mediaRepository.cacheUploadedMedia(
        r2Key: r2Key,
        localPath: file.path,
        fileName: fileName,
        mimeType: mediaMessage.fileType,
        fileSize: mediaMessage.fileSize,
      );

      // Remove pending message after successful upload
      if (mounted) {
        setState(() {
          _pendingMessages.removeWhere((m) => m.messageId == pendingId);
          _pendingUploadNotifiers.remove(pendingId)?.dispose();
          _lastUploadPercent.remove(pendingId);
        });
      }

      // ✅ Scroll to bottom to show newly sent voice message
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        // Remove pending message on error
        setState(() {
          _pendingMessages.removeWhere((m) => m.messageId == pendingId);
          _pendingUploadNotifiers.remove(pendingId)?.dispose();
          _lastUploadPercent.remove(pendingId);
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send recording: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
      try {
        if (_recordingPath != null) File(_recordingPath!).deleteSync();
      } catch (_) {}
    }
  }

  Future<void> _deleteRecording() async {
    _recordingTimer?.cancel();
    if (_isRecording.value) {
      try {
        await _audioRecorder.stop();
      } catch (_) {}
    }
    setState(() {
      _isRecording.value = false;
      _recordingDuration.value = 0;
    });
    try {
      if (_recordingPath != null) File(_recordingPath!).deleteSync();
    } catch (_) {}
    _recordingPath = null;
  }

  String _inferAudioMime(String? ext) {
    switch (ext) {
      case 'm4a':
      case 'mp4':
        return 'audio/mp4';
      case 'aac':
        return 'audio/aac';
      case 'wav':
        return 'audio/wav';
      case 'ogg':
      case 'oga':
        return 'audio/ogg';
      case 'opus':
        return 'audio/opus';
      case 'flac':
        return 'audio/flac';
      default:
        return 'audio/mpeg';
    }
  }

  Future<void> _deleteSelectedMessages() async {
    if (_selectedMessages.value.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF2A2A2A)
            : Colors.white,
        title: Text(
          'Delete for everyone?',
          style: TextStyle(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : Colors.black,
          ),
        ),
        content: Text(
          'Delete ${_selectedMessages.value.length} message(s)? This cannot be undone.',
          style: TextStyle(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white70
                : Colors.black87,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _service.deleteMessagesForEveryone(
        groupId: widget.groupId,
        messageIds: _selectedMessages.value.toList(),
      );

      if (mounted) {
        setState(() => _selectionMode = false);
        _selectedMessages.value = {};
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Messages deleted for everyone'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete messages: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _openSearch() {
    Navigator.of(context)
        .push<String?>(
          MaterialPageRoute(
            builder: (_) => OfflineMessageSearchPage(
              chatId: widget.groupId,
              chatType: 'parent_group',
            ),
          ),
        )
        .then((messageId) async {
          if (messageId != null) {
            // Scroll to the message
            final localMsg = await _localRepo.getMessageById(messageId);
            if (localMsg != null) {
              await scrollToMessage(messageId, [
                {'id': messageId},
              ]);
            }
          }
        });
  }
}

// Parent Group Message Search Screen
class ParentGroupMessageSearchScreen extends StatefulWidget {
  final String groupId;
  final ParentTeacherGroupService messagingService;
  final String currentUserId;

  const ParentGroupMessageSearchScreen({
    super.key,
    required this.groupId,
    required this.messagingService,
    required this.currentUserId,
  });

  @override
  State<ParentGroupMessageSearchScreen> createState() =>
      _ParentGroupMessageSearchScreenState();
}

class _ParentGroupMessageSearchScreenState
    extends State<ParentGroupMessageSearchScreen> {
  final TextEditingController _queryController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<CommunityMessageModel> _results = [];
  DocumentSnapshot? _cursor;
  bool _loading = false;
  bool _hasMore = true;
  String _lastQuery = '';

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
      final messages = await widget.messagingService.searchParentGroupMessages(
        groupId: widget.groupId,
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

  IconData _iconFor(CommunityMessageModel m) {
    final mime = m.mediaMetadata?.mimeType ?? '';
    if (mime.startsWith('image/')) return Icons.image_outlined;
    if (mime == 'application/pdf') return Icons.picture_as_pdf_outlined;
    if (mime.startsWith('audio/')) return Icons.audiotrack;
    if (mime.isNotEmpty) return Icons.insert_drive_file_outlined;
    if (m.type == 'audio') return Icons.audiotrack;
    if (m.type == 'image') return Icons.image_outlined;
    if (m.type == 'pdf' || m.type == 'file') {
      return Icons.insert_drive_file_outlined;
    }
    return Icons.chat_bubble_outline;
  }

  String _primaryText(CommunityMessageModel m) {
    if (m.content.isNotEmpty) return m.content;
    if (m.mediaMetadata?.originalFileName?.isNotEmpty == true) {
      return m.mediaMetadata!.originalFileName!;
    }
    if (m.fileName.isNotEmpty) return m.fileName;
    return 'Media message';
  }

  String _secondaryText(CommunityMessageModel m) {
    final sender = m.senderName.isNotEmpty ? m.senderName : 'Unknown';
    return '${_formatTimestamp(m.createdAt)} • $sender';
  }

  void _openMedia(CommunityMessageModel message) {
    if (message.mediaMetadata == null) {
      if (message.content.isNotEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message.content)));
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
      if (mounted) {
        showModalBottomSheet(
          context: context,
          builder: (ctx) => AudioPlayerModal(
            audioUrl: publicUrl,
            fileName: meta.originalFileName ?? 'Audio',
          ),
        );
      }
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
                        onTap: () => _openMedia(message),
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

/// ✅ FULL-SCREEN IMAGE GALLERY VIEWER with zoom, pinch, and swipe
/// Features:
/// 1. Horizontal swipe between images (PageView)
/// 2. Pinch-to-zoom (InteractiveViewer with 2-finger detection)
/// 3. Double-tap toggle zoom (1x ↔ 2.5x)
/// 4. Smart scroll lock (disables PageView when zoomed)
/// 5. CachedNetworkImage with aggressive caching
/// 6. Loading indicators and error fallbacks
class _ImageGalleryViewer extends StatefulWidget {
  final List<MediaMetadata> mediaList;
  final int initialIndex;
  final Map<String, String> localFilePaths;

  const _ImageGalleryViewer({
    required this.mediaList,
    required this.initialIndex,
    required this.localFilePaths,
  });

  @override
  State<_ImageGalleryViewer> createState() => _ImageGalleryViewerState();
}

class _ImageGalleryViewerState extends State<_ImageGalleryViewer> {
  late PageController _pageController;
  late int _currentIndex;
  late Map<int, TransformationController> _transformationControllers;
  late Map<int, bool> _zoomStates;
  bool _isInteracting = false; // Track if user is zooming
  int _pointerCount = 0; // Track number of fingers on screen

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

      // Listen to transformation changes to track zoom state
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

  // Disable horizontal scroll when zoomed or interacting
  bool get _shouldDisableScroll =>
      _isInteracting || (_zoomStates[_currentIndex] ?? false);

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
        scrollDirection: Axis.horizontal,
        physics: _shouldDisableScroll
            ? const NeverScrollableScrollPhysics() // Lock scroll when zoomed
            : const AlwaysScrollableScrollPhysics(),
        onPageChanged: (index) {
          // Reset zoom of previous image when switching pages
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
          final media = widget.mediaList[index];
          final publicUrl = media.publicUrl;
          final localPath =
              widget.localFilePaths[media.r2Key] ?? media.thumbnail;

          return _buildImageViewer(index, localPath, publicUrl);
        },
      ),
    );
  }

  Widget _buildImageViewer(int index, String? localPath, String? publicUrl) {
    // Priority: Local file > Network image
    final file = (localPath != null && localPath.isNotEmpty)
        ? File(localPath)
        : null;
    final hasLocalFile = file != null && file.existsSync();
    final hasNetwork = publicUrl != null && publicUrl.isNotEmpty;

    Widget imageWidget;

    if (hasLocalFile) {
      // ✅ Local image with high-quality rendering
      imageWidget = RepaintBoundary(
        child: Image.file(
          file,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          cacheWidth: 1200, // Cache optimization
          errorBuilder: (_, __, ___) => _buildFallbackImage(),
        ),
      );
    } else if (hasNetwork) {
      // ✅ Network image with aggressive caching and loading indicator
      imageWidget = RepaintBoundary(
        child: CachedNetworkImage(
          imageUrl: publicUrl,
          key: ValueKey(publicUrl), // Widget identity
          cacheKey: publicUrl, // Explicit cache key
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          memCacheWidth: 1200, // Memory cache optimization
          maxWidthDiskCache: 1200, // Disk cache optimization
          fadeInDuration: const Duration(milliseconds: 0), // No fade for cached
          fadeOutDuration: const Duration(milliseconds: 0),
          useOldImageOnUrlChange: true, // Keep showing old while loading new
          imageBuilder: (context, imageProvider) => Image(
            image: imageProvider,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            gaplessPlayback: true, // Seamless transition
          ),
          placeholder: (context, url) => const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  color: Color(0xFFFFA929),
                  strokeWidth: 3,
                ),
                SizedBox(height: 16),
                Text(
                  'Loading image...',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
          errorWidget: (context, url, error) => _buildFallbackImage(),
        ),
      );
    } else {
      imageWidget = _buildFallbackImage();
    }

    // ✅ Wrap with gesture detection for zoom control
    return Listener(
      onPointerDown: (event) {
        setState(() {
          _pointerCount++;
          // Enable interaction mode when 2+ fingers detected
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
            // Small delay to prevent accidental swipe during zoom release
            Future.delayed(const Duration(milliseconds: 100), () {
              if (mounted && _pointerCount < 2) {
                setState(() {
                  _isInteracting = false;
                });
              }
            });
          }
        });
      },
      onPointerCancel: (event) {
        setState(() {
          _pointerCount--;
          if (_pointerCount < 2) {
            Future.delayed(const Duration(milliseconds: 100), () {
              if (mounted && _pointerCount < 2) {
                setState(() {
                  _isInteracting = false;
                });
              }
            });
          }
        });
      },
      child: GestureDetector(
        onDoubleTap: () {
          // ✅ Double-tap toggle: 1x ↔ 2.5x zoom
          final controller = _transformationControllers[index]!;
          final scale = controller.value.getMaxScaleOnAxis();

          if (scale > 1.1) {
            // Zoom out to 1x
            controller.value = Matrix4.identity();
          } else {
            // Zoom in to 2.5x at center
            final matrix = Matrix4.identity()..scale(2.5);
            controller.value = matrix;
          }
          setState(() {});
        },
        child: InteractiveViewer(
          transformationController: _transformationControllers[index],
          minScale: 1.0, // No zoom out below original size
          maxScale: 5.0, // Max 5x zoom
          panEnabled: _pointerCount >= 2, // Only pan with 2+ fingers
          scaleEnabled: true, // Enable pinch zoom
          boundaryMargin: const EdgeInsets.all(double.infinity),
          clipBehavior: Clip.none,
          child: Center(child: imageWidget),
        ),
      ),
    );
  }

  Widget _buildFallbackImage() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image, size: 64, color: Colors.white54),
          SizedBox(height: 16),
          Text('Image not available', style: TextStyle(color: Colors.white70)),
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
