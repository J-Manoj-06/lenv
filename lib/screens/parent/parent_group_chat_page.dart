import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:open_filex/open_filex.dart';
import 'package:dio/dio.dart';
import 'package:characters/characters.dart';
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
import '../../services/connectivity_service.dart';
import '../../services/media_availability_service.dart';
import '../../services/media_storage_helper.dart';
import '../create_poll_screen.dart';
import '../../widgets/poll_message_widget.dart';
import '../../models/poll_model.dart';
import '../common/announcement_view_screen.dart';
import '../../utils/message_scroll_highlight_mixin.dart';
// OFFLINE-FIRST IMPORTS
import '../../repositories/local_message_repository.dart';
import '../../services/firebase_message_sync_service.dart';
import '../../services/image_viewer_action_service.dart';
import '../messages/offline_message_search_page.dart';
import '../messages/forward_selection_screen.dart';
import '../../models/forward_message_data.dart';
import '../../models/local_message.dart';
import '../../core/constants/app_colors.dart';
import '../../services/active_chat_service.dart';
import '../../utils/session_manager.dart';
import '../../services/message_reaction_service.dart';
import '../../widgets/message_reaction_picker.dart';
import '../../widgets/message_reaction_summary.dart';
import '../../widgets/whatsapp_emoji_picker.dart';

class ParentGroupChatPage extends StatefulWidget {
  final String groupId;
  final String groupName;
  final String? className;
  final String? section;
  final String childName;
  final String childId;
  final String? schoolCode;
  final String senderRole;

  const ParentGroupChatPage({
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
  State<ParentGroupChatPage> createState() => _ParentGroupChatPageState();
}

class _ParentGroupChatPageState extends State<ParentGroupChatPage>
    with AutomaticKeepAliveClientMixin, MessageScrollAndHighlightMixin {
  static const bool _debugMultiImageGrid = true;
  static const bool _debugPendingUploadTrace = true;
  static const int _pendingUploadStaleTimeoutMs = 180000;
  static const int _initialRealtimeMessageLimit = 500;
  static const int _initialOfflineSyncLimit = 300;

  // ✅ NEW THEME COLORS - Modern dark design
  static const Color primaryBackground = Color(0xFF0F1113);
  static const Color secondaryBackground = Color(0xFF16181A);
  static const Color userMessageBubble = Color(0xFF6C5CE7);
  static const Color otherMessageBubble = Color(0xFF2B2F31);
  static const Color primaryText = Color(0xFFFFFFFF);
  static const Color mutedText = Color(0xFF9AA0A6);
  static const Color dividerColor = Color(0xFF1E2123);
  static const Color parentGreen = Color(0xFF14A670);

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
  final MediaAvailabilityService _mediaAvailabilityService =
      MediaAvailabilityService();
  final MediaStorageHelper _mediaStorageHelper = MediaStorageHelper();

  // OFFLINE-FIRST SERVICES
  late final LocalMessageRepository _localRepo;
  late final FirebaseMessageSyncService _syncService;

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();
  late final MediaUploadService _mediaUploadService;
  bool _isUploading = false;
  bool _isOnline = true;
  StreamSubscription<bool>? _connectivitySub;
  StreamSubscription<List<CommunityMessageModel>>? _firestoreMirrorSub;
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
  // ── Failed-upload state (for retry button) ────────────────────────────
  final Map<String, String> _failedUploadLocalPaths = {};
  final Map<String, String> _failedUploadMimeTypes = {};
  int _pendingTextSequence = 0;
  final Set<String> _sendingTextMessageIds = <String>{};
  final Set<String> _failedPendingTextMessageIds = <String>{};

  // Poll cached progress while uploads continue in background
  Timer? _progressPollTimer;
  bool _offlineReady = false;

  // Selection mode for multi-delete (using ValueNotifier to avoid full-page rebuilds)
  bool _selectionMode = false;
  final ValueNotifier<Set<String>> _selectedMessages =
      ValueNotifier<Set<String>>({});
  final Set<String> _optimisticallyDeletedMessageIds = <String>{};
  final Map<String, Map<String, dynamic>> _messageDataCache = {};
  String? _shareEligibilitySelectionKey;
  Future<bool>? _shareEligibilityFuture;
  String? _forwardEligibilitySelectionKey;
  Future<bool>? _forwardEligibilityFuture;
  String? _deleteEligibilitySelectionKey;
  Future<bool>? _deleteEligibilityFuture;
  bool _isReactionPickerOpen = false;
  bool _showEmojiPicker = false;
  final ValueNotifier<bool> _hasText = ValueNotifier<bool>(false);

  // ✅ NEW: Use ValueNotifier for loading state to avoid full rebuilds
  final ValueNotifier<bool> _isLoadingMoreNotifier = ValueNotifier<bool>(false);
  final int _messageLoadCount = 0; // Debug counter

  // ✅ CRITICAL: Message cache to maintain stable Map instances (prevents widget recreation)
  // This cache ensures Flutter recognizes the same message object and doesn't rebuild widgets
  // when StreamBuilder rebuilds. Same technique used in staff room.
  final Map<String, CommunityMessageModel> _messageCache = {};
  final Map<String, Map<String, dynamic>> _localPollDataCache =
      <String, Map<String, dynamic>>{};

  // ✅ Cache stream like staff room to avoid rebuilding new streams
  Stream<List<CommunityMessageModel>>? _messagesStream;
  Timestamp? _lastReadAt;
  StreamSubscription<Timestamp?>? _lastReadAtSub;
  final bool _showUnreadDivider = true;
  bool _hasScrolledToUnread = false;
  final Completer<void> _offlineInitCompleter = Completer<void>();

  String _cacheMessageIdFromPendingId(String messageId) {
    return messageId.startsWith('pending:')
        ? messageId.substring('pending:'.length)
        : messageId;
  }

  Future<LocalMessage?> _getCachedPendingMessageByPendingId(
    String pendingId,
  ) async {
    final baseId = _cacheMessageIdFromPendingId(pendingId);
    // Prefer normalized ID, but support legacy entries written with pending: prefix.
    return await _localRepo.getMessageById(baseId) ??
        await _localRepo.getMessageById(pendingId);
  }

  String _buildSelectionKey(Set<String> selectedIds) {
    if (selectedIds.isEmpty) return '';
    final sorted = selectedIds.toList()..sort();
    return sorted.join('|');
  }

  void _invalidateSelectionEligibilityCache() {
    _shareEligibilitySelectionKey = null;
    _shareEligibilityFuture = null;
    _forwardEligibilitySelectionKey = null;
    _forwardEligibilityFuture = null;
    _deleteEligibilitySelectionKey = null;
    _deleteEligibilityFuture = null;
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

  Future<bool> _getDeleteEligibilityFuture(Set<String> selectedIds) {
    final nextKey = _buildSelectionKey(selectedIds);
    if (_deleteEligibilityFuture != null &&
        _deleteEligibilitySelectionKey == nextKey) {
      return _deleteEligibilityFuture!;
    }
    _deleteEligibilitySelectionKey = nextKey;
    _deleteEligibilityFuture = _canDeleteSelectedMessages(
      Set<String>.from(selectedIds),
    );
    return _deleteEligibilityFuture!;
  }

  Future<void> _showReactionPickerForMessage({
    required CommunityMessageModel msg,
    required Offset globalPosition,
  }) async {
    if (_isReactionPickerOpen) return;

    final userId = fb_auth.FirebaseAuth.instance.currentUser?.uid;
    if (userId == null || userId.isEmpty) return;

    _isReactionPickerOpen = true;
    try {
      final providerUserId = Provider.of<AuthProvider>(
        context,
        listen: false,
      ).currentUser?.uid;
      final resolvedUserId = await _resolveCurrentUserId();
      final userAliases = <String>[
        if (providerUserId != null && providerUserId.isNotEmpty) providerUserId,
        if (resolvedUserId != null && resolvedUserId.isNotEmpty) resolvedUserId,
      ];

      final selectedEmoji = await MessageReactionService.instance
          .getUserReaction(
            target: ReactionTarget.parentTeacherGroupMessage(
              groupId: widget.groupId,
              messageId: msg.messageId,
            ),
            userId: userId,
            userAliases: userAliases,
          );

      final emoji = await showMessageReactionPicker(
        context: context,
        globalPosition: globalPosition,
        selectedEmoji: selectedEmoji,
      );
      if (emoji == null || emoji.isEmpty) return;

      if (mounted && _selectionMode) {
        setState(() => _selectionMode = false);
      }
      _selectedMessages.value = {};
      _invalidateSelectionEligibilityCache();

      await MessageReactionService.instance.toggleReaction(
        target: ReactionTarget.parentTeacherGroupMessage(
          groupId: widget.groupId,
          messageId: msg.messageId,
        ),
        userId: userId,
        emoji: emoji,
        userAliases: userAliases,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update reaction right now')),
      );
    } finally {
      _isReactionPickerOpen = false;
    }
  }

  Future<void> _showReactionViewerForMessage(CommunityMessageModel msg) async {
    if (msg.reactionSummary.isEmpty) return;

    final userId = fb_auth.FirebaseAuth.instance.currentUser?.uid;
    if (userId == null || userId.isEmpty) return;

    final providerUserId = Provider.of<AuthProvider>(
      context,
      listen: false,
    ).currentUser?.uid;
    final resolvedUserId = await _resolveCurrentUserId();
    final userAliases = <String>[
      if (providerUserId != null && providerUserId.isNotEmpty) providerUserId,
      if (resolvedUserId != null && resolvedUserId.isNotEmpty) resolvedUserId,
    ];

    String? myReaction;
    try {
      myReaction = await MessageReactionService.instance.getUserReaction(
        target: ReactionTarget.parentTeacherGroupMessage(
          groupId: widget.groupId,
          messageId: msg.messageId,
        ),
        userId: userId,
        userAliases: userAliases,
      );
    } catch (_) {
      myReaction = null;
    }

    if (!mounted) return;

    final entries = msg.reactionSummary.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<int>(0, (sum, e) => sum + e.value);
    final selectedReaction = myReaction;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outline.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '$total reaction${total == 1 ? '' : 's'}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: entries.map((entry) {
                    final selected = selectedReaction == entry.key;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? theme.colorScheme.primary.withValues(alpha: 0.18)
                            : theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${entry.key} ${entry.value}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                if (selectedReaction != null &&
                    selectedReaction.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 18,
                      backgroundColor: theme.colorScheme.primary.withValues(
                        alpha: 0.14,
                      ),
                      child: Text(
                        selectedReaction,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                    title: const Text('You'),
                    subtitle: const Text('Tap to remove'),
                    onTap: () async {
                      Navigator.of(ctx).pop();

                      try {
                        await MessageReactionService.instance.toggleReaction(
                          target: ReactionTarget.parentTeacherGroupMessage(
                            groupId: widget.groupId,
                            messageId: msg.messageId,
                          ),
                          userId: userId,
                          emoji: selectedReaction,
                          userAliases: userAliases,
                        );
                      } catch (_) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Could not remove reaction right now',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  bool _isImageMime(String? mimeType) {
    final mt = (mimeType ?? '').toLowerCase();
    return mt.startsWith('image/');
  }

  String _mediaTypeFromMime(String? mimeType) {
    final mt = (mimeType ?? '').toLowerCase();
    if (mt.startsWith('audio/')) return 'audio';
    if (mt.startsWith('image/')) return 'image';
    if (mt.contains('pdf')) return 'pdf';
    return 'file';
  }

  bool _isPendingUploadInProgress(CommunityMessageModel pendingMsg) {
    final notifiers = <ValueNotifier<double>>[];

    final pendingNotifier = _pendingUploadNotifiers[pendingMsg.messageId];
    if (pendingNotifier != null) {
      notifiers.add(pendingNotifier);
    }

    final mediaIds = <String>{};
    if (pendingMsg.mediaMetadata != null &&
        pendingMsg.mediaMetadata!.messageId.isNotEmpty) {
      mediaIds.add(pendingMsg.mediaMetadata!.messageId);
    }
    if (pendingMsg.multipleMedia != null) {
      for (final media in pendingMsg.multipleMedia!) {
        if (media.messageId.isNotEmpty) {
          mediaIds.add(media.messageId);
        }
      }
    }

    for (final mediaId in mediaIds) {
      final notifier = _pendingUploadNotifiers[mediaId];
      if (notifier != null) {
        notifiers.add(notifier);
      }
    }

    if (notifiers.isEmpty) return false;
    return notifiers.any((n) => n.value >= 0 && n.value < 100);
  }

  Set<String> _pendingTrackingKeys(CommunityMessageModel pendingMsg) {
    final keys = <String>{};
    final pendingId = pendingMsg.messageId;
    final baseId = pendingId.replaceFirst('pending:', '');

    keys.add(pendingId);
    keys.add(baseId);

    final singleMediaId = pendingMsg.mediaMetadata?.messageId;
    if (singleMediaId != null && singleMediaId.isNotEmpty) {
      keys.add(singleMediaId);
    }

    if (pendingMsg.multipleMedia != null) {
      for (final media in pendingMsg.multipleMedia!) {
        if (media.messageId.isNotEmpty) {
          keys.add(media.messageId);
        }
      }
    }

    return keys;
  }

  void _disposePendingTracking(CommunityMessageModel pendingMsg) {
    final keys = _pendingTrackingKeys(pendingMsg);
    final baseId = pendingMsg.messageId.replaceFirst('pending:', '');
    final legacyPrefix = 'pending_${baseId}_';

    _pendingUploadNotifiers.removeWhere((key, notifier) {
      final shouldRemove =
          keys.contains(key) ||
          (baseId.isNotEmpty && key.startsWith(legacyPrefix));
      if (shouldRemove) {
        notifier.dispose();
      }
      return shouldRemove;
    });

    _lastUploadPercent.removeWhere(
      (key, _) =>
          keys.contains(key) ||
          (baseId.isNotEmpty && key.startsWith(legacyPrefix)),
    );
    _sendingTextMessageIds.remove(pendingMsg.messageId);
    _failedPendingTextMessageIds.remove(pendingMsg.messageId);
  }

  bool _isPendingTextMessage(CommunityMessageModel msg) {
    return msg.messageId.startsWith('pending:') &&
        msg.content.trim().isNotEmpty &&
        msg.mediaMetadata == null &&
        (msg.multipleMedia == null || msg.multipleMedia!.isEmpty) &&
        msg.imageUrl.isEmpty &&
        msg.fileUrl.isEmpty;
  }

  Future<void> _retryPendingTextMessage(String pendingMessageId) async {
    final pendingMessage = _pendingMessages.firstWhere(
      (m) => m.messageId == pendingMessageId,
      orElse: () => CommunityMessageModel(
        messageId: '',
        communityId: '',
        senderId: '',
        senderName: '',
        senderRole: '',
        senderAvatar: '',
        type: 'text',
        content: '',
        imageUrl: '',
        fileUrl: '',
        fileName: '',
        createdAt: DateTime.now(),
        isEdited: false,
        isDeleted: false,
        isPinned: false,
        reactions: const {},
        replyTo: '',
        replyCount: 0,
        isReported: false,
        reportCount: 0,
      ),
    );

    if (pendingMessage.messageId.isEmpty) return;
    await _sendPendingTextMessage(pendingMessage);
  }

  Future<void> _sendPendingTextMessage(CommunityMessageModel pendingMsg) async {
    final pendingId = pendingMsg.messageId;
    if (_sendingTextMessageIds.contains(pendingId)) return;
    _sendingTextMessageIds.add(pendingId);

    if (mounted) {
      setState(() {
        _failedPendingTextMessageIds.remove(pendingId);
      });
    }

    try {
      await _service.sendMessage(
        groupId: widget.groupId,
        senderId: pendingMsg.senderId,
        senderName: pendingMsg.senderName,
        senderRole: pendingMsg.senderRole,
        content: pendingMsg.content,
      );

      if (_offlineInitCompleter.isCompleted) {
        try {
          await _localRepo.deletePendingMessage(
            _cacheMessageIdFromPendingId(pendingId),
          );
          await _localRepo.deletePendingMessage(pendingId);
        } catch (_) {
          // Local cleanup is best-effort after successful send.
        }
      }

      if (mounted) {
        setState(() {
          _failedPendingTextMessageIds.remove(pendingId);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _failedPendingTextMessageIds.add(pendingId);
        });
      }
    } finally {
      _sendingTextMessageIds.remove(pendingId);
    }
  }

  Future<void> _resumePendingTextMessages() async {
    if (!_isOnline || !mounted) return;

    final pendingTextMessages = _pendingMessages.where((msg) {
      return _isPendingTextMessage(msg) &&
          !_failedPendingTextMessageIds.contains(msg.messageId);
    }).toList();

    for (final msg in pendingTextMessages) {
      unawaited(_sendPendingTextMessage(msg));
    }
  }

  void _logPendingUploadTrace(
    String event, [
    Map<String, Object?> extra = const {},
  ]) {
    if (!_debugPendingUploadTrace) return;
    final parts = <String>['[PTG-UPLOAD-TRACE][$event]'];
    extra.forEach((key, value) {
      parts.add('$key=$value');
    });
    debugPrint(parts.join(' '));
  }

  void _toggleSelectedMessage({
    required String messageId,
    required bool isPending,
    required bool isSelected,
  }) {
    if (isPending) return;

    final selectedSet = _selectedMessages.value;
    if (isSelected) {
      if (selectedSet.length > 1) {
        final updated = {...selectedSet};
        updated.remove(messageId);
        _selectedMessages.value = updated;
      } else {
        setState(() => _selectionMode = false);
        _selectedMessages.value = {};
        _invalidateSelectionEligibilityCache();
      }
    } else {
      _selectedMessages.value = {...selectedSet, messageId};
    }
  }

  Future<T?> _runWithoutInputFocus<T>(Future<T?> Function() action) async {
    // Prevent keyboard re-opening when launching overlays/routes from chat.
    FocusManager.instance.primaryFocus?.unfocus();
    _focusNode.unfocus();
    final previousCanRequestFocus = _focusNode.canRequestFocus;
    _focusNode.canRequestFocus = false;
    try {
      return await action();
    } finally {
      if (mounted) {
        _focusNode.canRequestFocus = previousCanRequestFocus;
      }
    }
  }

  Color _chatAccentColor(BuildContext context) {
    // Match teacher dashboard accent exactly.
    if (widget.senderRole.toLowerCase() == 'teacher') {
      return AppColors.teacherColor;
    }
    return parentGreen;
  }

  @override
  bool get wantKeepAlive => true; // ✅ Prevent rebuild when switching tabs

  @override
  void dispose() {
    ActiveChatService().clearActiveChat(
      targetType: 'parent_teacher_group',
      targetId: widget.groupId,
    );
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
    _connectivitySub?.cancel();
    _firestoreMirrorSub?.cancel();
    _lastReadAtSub?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    ActiveChatService().setActiveChat(
      targetType: 'parent_teacher_group',
      targetId: widget.groupId,
    );
    _isOnline = ConnectivityService().isOnline;
    _connectivitySub = ConnectivityService().onConnectivityChanged.listen((
      online,
    ) {
      if (mounted) setState(() => _isOnline = online);
      if (online) {
        _startFirestoreMirror();
        _syncOnReconnect();
        unawaited(_resumePendingTextMessages());
      } else {
        _firestoreMirrorSub?.cancel();
        _firestoreMirrorSub = null;
      }
    });

    // ✅ OPTIMIZATION: Setup scroll listener for pagination
    scrollController.addListener(_onScroll);

    // ✅ OPTIMIZATION: Listen to text changes without rebuilding
    _controller.addListener(() {
      _hasText.value = _controller.text.trim().isNotEmpty;
    });
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && _showEmojiPicker) {
        setState(() => _showEmojiPicker = false);
      }
    });

    _initOfflineFirst();
    _startFirestoreMirror();

    // Start polling cached progress (keeps UI updated after navigation)
    _startProgressPolling();

    // ✅ Cache stream once (same as staff room) to prevent re-creation
    _messagesStream = _buildOfflineFirstMessagesStream();

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
    _setupLastReadStream();
  }

  void _initOfflineFirst() async {
    try {
      _localRepo = LocalMessageRepository();
      _syncService = FirebaseMessageSyncService(_localRepo);

      await _localRepo.initialize();
      if (!_offlineInitCompleter.isCompleted) {
        _offlineInitCompleter.complete();
      }

      final chatId = widget.groupId;

      // Load from cache first
      final cachedMessages = await _localRepo.getMessagesForChat(
        chatId,
        limit: _initialOfflineSyncLimit,
      );

      if (cachedMessages.isEmpty) {
        await _syncService.initialSyncForChat(
          chatId: chatId,
          chatType: 'parent_group',
          limit: _initialOfflineSyncLimit,
        );
      } else {
        // Debug: Check what senders are in the cache
        final senders = cachedMessages.map((m) => m.senderId).toSet();
        for (final senderId in senders) {
          final count = cachedMessages
              .where((m) => m.senderId == senderId)
              .length;
        }

        _syncService.syncNewMessages(
          chatId: chatId,
          chatType: 'parent_group',
          lastTimestamp: cachedMessages.first.timestamp,
        );
      }

      // Start real-time sync
      if (!mounted) return;
      final currentUserId = await _resolveCurrentUserId();
      if (currentUserId != null && currentUserId.isNotEmpty) {
        await _syncService.startSyncForChat(
          chatId: chatId,
          chatType: 'parent_group',
          userId: currentUserId,
        );

        // ✅ CRITICAL: Load pending messages after sync starts
        await _loadPendingMessages();
        unawaited(_resumePendingTextMessages());

        // Mark offline services ready for progress polling
        _offlineReady = true;
      } else {}
    } catch (e) {}
  }

  Stream<List<CommunityMessageModel>>
  _buildOfflineFirstMessagesStream() async* {
    try {
      await _offlineInitCompleter.future;
    } catch (_) {
      // No-op; stream will yield empty state below.
    }

    if (!_offlineInitCompleter.isCompleted) {
      yield const <CommunityMessageModel>[];
      return;
    }

    await for (final localMessages in _localRepo.watchMessagesForChat(
      widget.groupId,
    )) {
      final mapped = localMessages
          .where((m) => !m.isDeleted && m.isPending != true)
          .map(_localToCommunityMessage)
          .toList();

      yield mapped;
    }
  }

  Future<String?> _resolveCurrentUserId() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;
    if (currentUser != null && currentUser.uid.isNotEmpty) {
      return currentUser.uid;
    }

    final session = await SessionManager.getLoginSession();
    final userId = session['userId'] as String?;
    if (userId != null && userId.isNotEmpty) {
      return userId;
    }
    return null;
  }

  Future<void> _syncOnReconnect() async {
    if (!_offlineInitCompleter.isCompleted) return;

    try {
      final userId = await _resolveCurrentUserId();
      if (userId != null && userId.isNotEmpty) {
        await _syncService.startSyncForChat(
          chatId: widget.groupId,
          chatType: 'parent_group',
          userId: userId,
        );
      }

      final cachedMessages = await _localRepo.getMessagesForChat(
        widget.groupId,
        limit: 1,
      );
      if (cachedMessages.isEmpty) {
        await _syncService.initialSyncForChat(
          chatId: widget.groupId,
          chatType: 'parent_group',
          limit: _initialOfflineSyncLimit,
        );
      } else {
        await _syncService.syncNewMessages(
          chatId: widget.groupId,
          chatType: 'parent_group',
          lastTimestamp: cachedMessages.first.timestamp,
        );
      }

      unawaited(_resumePendingTextMessages());
    } catch (_) {
      // Ignore transient reconnect sync errors.
    }
  }

  void _startFirestoreMirror() {
    if (!_isOnline) return;

    _firestoreMirrorSub?.cancel();
    _firestoreMirrorSub = _service
        .getMessagesStream(widget.groupId, limit: _initialRealtimeMessageLimit)
        .listen((messages) async {
          if (!_offlineInitCompleter.isCompleted) {
            try {
              await _offlineInitCompleter.future;
            } catch (_) {
              return;
            }
          }

          final localMessages = messages
              .where((m) => (m.isDeleted == false))
              .map(_communityToLocalMessage)
              .toList();

          if (localMessages.isNotEmpty) {
            await _localRepo.saveMessages(localMessages);
          }
        });
  }

  LocalMessage _communityToLocalMessage(CommunityMessageModel msg) {
    final attachment = msg.mediaMetadata;
    final rawMultipleMedia = (msg.multipleMedia?.isNotEmpty == true)
        ? msg.multipleMedia!.map((m) => m.toFirestore()).toList()
        : (attachment != null
              ? <Map<String, dynamic>>[attachment.toFirestore()]
              : null);
    final multipleMedia =
        _sanitizeForLocalHive(rawMultipleMedia) as List<dynamic>?;

    final rawDocData = _asStringDynamicMap(msg.documentSnapshot?.data());
    final pollData =
        _sanitizeForLocalHive(_extractPollDataFromMessage(rawDocData, msg))
            as Map<String, dynamic>?;

    String? attachmentType;
    if (attachment != null) {
      final mime = (attachment.mimeType ?? '').toLowerCase();
      if (mime.startsWith('image/')) {
        attachmentType = 'image';
      } else if (mime.startsWith('audio/')) {
        attachmentType = 'audio';
      } else if (mime.contains('pdf')) {
        attachmentType = 'pdf';
      } else {
        attachmentType = msg.type;
      }
    } else {
      attachmentType = msg.type == 'text' ? null : msg.type;
    }

    return LocalMessage(
      messageId: msg.messageId,
      chatId: widget.groupId,
      chatType: 'parent_group',
      senderId: msg.senderId,
      senderName: msg.senderName,
      messageText: msg.content,
      timestamp: msg.createdAt.millisecondsSinceEpoch,
      attachmentUrl: attachment?.publicUrl,
      attachmentType: attachmentType,
      isDeleted: msg.isDeleted,
      replyToMessageId: msg.replyTo.isNotEmpty ? msg.replyTo : null,
      multipleMedia: multipleMedia,
      pollData: pollData,
      isPending: false,
      reactionSummary: msg.reactionSummary,
      reactionCount: msg.reactionCount,
    );
  }

  Map<String, dynamic>? _extractPollDataFromMessage(
    Map<String, dynamic>? raw,
    CommunityMessageModel msg,
  ) {
    if ((msg.type).toLowerCase() != 'poll') return null;

    if (raw != null) {
      if (raw['poll'] is Map) {
        return Map<String, dynamic>.from(raw['poll'] as Map);
      }
      if (raw['question'] != null && raw['options'] is List) {
        return Map<String, dynamic>.from(raw);
      }
    }

    // Fallback for cached local reconstruction when snapshot isn't present.
    return <String, dynamic>{
      'type': 'poll',
      'question': msg.content.replaceFirst(RegExp(r'^Poll:\s*'), ''),
      'options': const <dynamic>[],
      'allowMultiple': false,
      'createdBy': msg.senderId,
      'createdByName': msg.senderName,
      'createdByRole': msg.senderRole,
      'timestamp': msg.createdAt.millisecondsSinceEpoch,
      'createdAt': msg.createdAt.millisecondsSinceEpoch,
      'voters': const <String, dynamic>{},
    };
  }

  CommunityMessageModel _localToCommunityMessage(LocalMessage msg) {
    final multipleMedia = _extractRawMultipleMedia(msg.multipleMedia);

    MediaMetadata? mediaMetadata;
    if (msg.attachmentUrl != null && msg.attachmentUrl!.isNotEmpty) {
      final first = multipleMedia.isNotEmpty ? multipleMedia.first : null;
      final resolvedPublicUrl = first?.publicUrl.isNotEmpty == true
          ? first!.publicUrl
          : msg.attachmentUrl!;
      mediaMetadata = MediaMetadata(
        messageId: msg.messageId,
        r2Key: _extractR2KeyFromMediaUrl(resolvedPublicUrl),
        publicUrl: resolvedPublicUrl,
        thumbnail: '',
        expiresAt: DateTime.now().add(const Duration(days: 30)),
        uploadedAt: DateTime.fromMillisecondsSinceEpoch(msg.timestamp),
        originalFileName:
            first?.originalFileName ?? msg.attachmentUrl!.split('/').last,
        fileSize: (first?.fileSize != null && first!.fileSize! > 0)
            ? first.fileSize
            : null,
        mimeType:
            first?.mimeType ?? _mimeFromAttachmentType(msg.attachmentType),
      );
    }

    if (multipleMedia.isNotEmpty && mediaMetadata == null) {
      mediaMetadata = multipleMedia.first;
    }

    if (msg.pollData != null) {
      _localPollDataCache[msg.messageId] = Map<String, dynamic>.from(
        msg.pollData!,
      );
    }

    final resolvedType = _messageTypeFromLocal(msg, multipleMedia);
    final pollQuestion = msg.pollData?['question']?.toString();

    return CommunityMessageModel(
      messageId: msg.messageId,
      communityId: widget.groupId,
      senderId: msg.senderId,
      senderName: msg.senderName,
      senderRole: widget.senderRole,
      senderAvatar: '',
      type: resolvedType,
      content: resolvedType == 'poll'
          ? 'Poll: ${pollQuestion ?? (msg.messageText ?? '').trim()}'
          : (msg.messageText ?? ''),
      imageUrl: mediaMetadata != null && _isImageMime(mediaMetadata.mimeType)
          ? mediaMetadata.publicUrl
          : '',
      fileUrl: mediaMetadata != null && !_isImageMime(mediaMetadata.mimeType)
          ? mediaMetadata.publicUrl
          : '',
      fileName: mediaMetadata?.originalFileName ?? '',
      mediaMetadata: mediaMetadata,
      multipleMedia: multipleMedia.isNotEmpty ? multipleMedia : null,
      createdAt: DateTime.fromMillisecondsSinceEpoch(msg.timestamp),
      updatedAt: null,
      isEdited: false,
      isDeleted: msg.isDeleted,
      isPinned: false,
      reactions: const <String, List<String>>{},
      replyTo: msg.replyToMessageId ?? '',
      replyCount: 0,
      isReported: false,
      reportCount: 0,
      documentSnapshot: null,
      reactionSummary: msg.reactionSummary,
      reactionCount: msg.reactionCount,
    );
  }

  String _mimeFromAttachmentType(String? type) {
    final normalized = (type ?? '').toLowerCase();
    if (normalized == 'image') return 'image/jpeg';
    if (normalized == 'audio') return 'audio/mpeg';
    if (normalized == 'pdf' || normalized == 'document') {
      return 'application/pdf';
    }
    return 'application/octet-stream';
  }

  String _messageTypeFromLocal(LocalMessage msg, List<MediaMetadata> multi) {
    if (msg.pollData != null ||
        (msg.attachmentType ?? '').toLowerCase() == 'poll') {
      return 'poll';
    }
    if (multi.isNotEmpty) {
      final firstMime = (multi.first.mimeType ?? '').toLowerCase();
      if (_isImageMime(firstMime)) return 'image';
      if (firstMime.startsWith('audio/')) return 'audio';
      return 'pdf';
    }
    final t = (msg.attachmentType ?? '').toLowerCase();
    if (t == 'image') return 'image';
    if (t == 'audio') return 'audio';
    if (t == 'pdf' || t == 'document') return 'pdf';
    return 'text';
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
        return;
      }

      final localMessage = LocalMessage(
        messageId: _cacheMessageIdFromPendingId(messageId),
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
    } catch (e) {}
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

      _logPendingUploadTrace('loadPendingMessages', {
        'chatId': widget.groupId,
        'count': pendingMessages.length,
      });

      if (pendingMessages.isEmpty) {
        return;
      }

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

        // Remove only completed/stale messages, keep active uploads.
        final removed = _pendingMessages
            .where((msg) => !activeUploadIds.contains(msg.messageId))
            .toList();
        for (final msg in removed) {
          _disposePendingTracking(msg);
        }
        _pendingMessages.removeWhere(
          (msg) => !activeUploadIds.contains(msg.messageId),
        );

        // Convert LocalMessage to CommunityMessageModel format
        for (final msg in pendingMessages) {
          if (msg.multipleMedia != null && msg.multipleMedia!.isNotEmpty) {
            final firstRaw = msg.multipleMedia!.first;
            final firstMime = (firstRaw['mimeType'] as String?) ?? '';
            final isSingleNonImageAttachment =
                msg.multipleMedia!.length == 1 && !_isImageMime(firstMime);

            if (isSingleNonImageAttachment) {
              final pendingMessageId = msg.messageId.startsWith('pending:')
                  ? msg.messageId
                  : 'pending:${msg.messageId}';
              final mediaId =
                  (firstRaw['messageId'] as String?) ?? pendingMessageId;
              final localPath = firstRaw['localPath'] as String?;
              final uploadProgress =
                  (firstRaw['uploadProgress'] as num?)?.toDouble() ?? 0.0;

              final pendingMetadata = MediaMetadata(
                messageId: mediaId,
                r2Key: firstRaw['r2Key'] ?? '',
                publicUrl: firstRaw['publicUrl'] ?? '',
                thumbnail: firstRaw['thumbnail'] ?? '',
                localPath: localPath ?? '',
                expiresAt: firstRaw['expiresAt'] != null
                    ? DateTime.parse(firstRaw['expiresAt'])
                    : DateTime.now().add(const Duration(days: 30)),
                uploadedAt: firstRaw['uploadedAt'] != null
                    ? DateTime.parse(firstRaw['uploadedAt'])
                    : DateTime.now(),
                originalFileName: firstRaw['originalFileName'] ?? '',
                fileSize: firstRaw['fileSize'] ?? 0,
                mimeType: firstRaw['mimeType'] ?? 'application/octet-stream',
              );

              if (_pendingMessages.any(
                (m) => m.messageId == pendingMessageId,
              )) {
                continue;
              }

              final pendingMessage = CommunityMessageModel(
                messageId: pendingMessageId,
                communityId: widget.groupId,
                senderId: msg.senderId,
                senderName: msg.senderName,
                senderRole: widget.senderRole,
                senderAvatar: '',
                type: _mediaTypeFromMime(firstMime),
                content: msg.messageText ?? '',
                imageUrl: '',
                fileUrl: '',
                fileName: pendingMetadata.originalFileName ?? '',
                mediaMetadata: pendingMetadata,
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
              _messageCache[pendingMessage.messageId] = pendingMessage;

              if (localPath != null && localPath.isNotEmpty) {
                _localSenderMediaPaths[pendingMessageId] = localPath;
                _localSenderMediaPaths[mediaId] = localPath;
              }

              if (uploadProgress < 1.0) {
                _pendingUploadNotifiers[pendingMessageId] =
                    ValueNotifier<double>(uploadProgress * 100);
                _lastUploadPercent[pendingMessageId] = (uploadProgress * 100)
                    .toInt();

                _logPendingUploadTrace('restoreSinglePending', {
                  'pendingId': pendingMessageId,
                  'mediaId': mediaId,
                  'progress': (uploadProgress * 100).toStringAsFixed(1),
                  'file': pendingMetadata.originalFileName ?? '',
                });
              }

              continue;
            }

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
              } catch (e) {}
            }

            if (mediaList.isEmpty) continue;

            // ✅ Ensure consistent pending: prefix for deduplication
            String messageId = msg.messageId.startsWith('pending:')
                ? msg.messageId
                : 'pending:${msg.messageId}';

            // ✅ CRITICAL: Skip if this message is already in _pendingMessages
            // This prevents duplication when an upload is still in progress
            // (activeUploadIds logic keeps it alive, then restore loop would add it again)
            if (_pendingMessages.any((m) => m.messageId == messageId)) {
              continue;
            }

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
                // ✅ FIX: Map by BOTH messageId AND r2Key so URL lookup always finds it
                _localSenderMediaPaths[media.messageId] = media.localPath!;
                if (media.r2Key.isNotEmpty) {
                  _localSenderMediaPaths[media.r2Key] = media.localPath!;
                }
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
              } else {}
            }
          } else if ((msg.messageText ?? '').trim().isNotEmpty) {
            final pendingMessageId = msg.messageId.startsWith('pending:')
                ? msg.messageId
                : 'pending:${msg.messageId}';

            if (_pendingMessages.any((m) => m.messageId == pendingMessageId)) {
              continue;
            }

            final pendingMessage = CommunityMessageModel(
              messageId: pendingMessageId,
              communityId: widget.groupId,
              senderId: msg.senderId,
              senderName: msg.senderName,
              senderRole: widget.senderRole,
              senderAvatar: '',
              type: 'text',
              content: msg.messageText ?? '',
              imageUrl: '',
              fileUrl: '',
              fileName: '',
              createdAt: DateTime.fromMillisecondsSinceEpoch(msg.timestamp),
              isEdited: false,
              isDeleted: false,
              isPinned: false,
              reactions: const {},
              replyTo: '',
              replyCount: 0,
              isReported: false,
              reportCount: 0,
            );

            _pendingMessages.insert(0, pendingMessage);
            _messageCache[pendingMessage.messageId] = pendingMessage;
          }
        }
      });

      unawaited(_resumePendingTextMessages());
    } catch (e) {}
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

      try {
        final cachedMsg = await _getCachedPendingMessageByPendingId(pendingId);

        if (cachedMsg == null || cachedMsg.isPending == false) {
          final uploadInProgress = _isPendingUploadInProgress(pendingMsg);
          final pendingAgeMs =
              DateTime.now().millisecondsSinceEpoch -
              pendingMsg.createdAt.millisecondsSinceEpoch;
          final isStale = pendingAgeMs > _pendingUploadStaleTimeoutMs;

          if (uploadInProgress && !isStale) {
            _logPendingUploadTrace('pollSkipRemoveActive', {
              'pendingId': pendingId,
              'progress':
                  _pendingUploadNotifiers[pendingId]?.value.toStringAsFixed(
                    1,
                  ) ??
                  'na',
              'ageMs': pendingAgeMs,
            });
            continue; // Still uploading, don't remove yet
          }

          if (uploadInProgress && isStale) {
            _logPendingUploadTrace('pollRemoveStaleUploading', {
              'pendingId': pendingId,
              'progress':
                  _pendingUploadNotifiers[pendingId]?.value.toStringAsFixed(
                    1,
                  ) ??
                  'na',
              'ageMs': pendingAgeMs,
            });
          }

          _logPendingUploadTrace('pollRemoveNoCache', {'pendingId': pendingId});
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

              // Keep parent pending card progress in sync for single-media uploads.
              final pendingCurrent =
                  _pendingUploadNotifiers[pendingId]?.value ?? 0.0;
              if ((nextValue - pendingCurrent).abs() > 0.5) {
                _pendingUploadNotifiers[pendingId] ??= ValueNotifier<double>(
                  nextValue,
                );
                _pendingUploadNotifiers[pendingId]!.value = nextValue;
                _lastUploadPercent[pendingId] = nextValue.toInt();
              }
              _logPendingUploadTrace('pollProgressUpdate', {
                'pendingId': pendingId,
                'mediaId': mediaId,
                'progress': nextValue.toStringAsFixed(1),
              });
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
        final removed = _pendingMessages
            .where((m) => toRemove.contains(m.messageId))
            .toList();
        for (final msg in removed) {
          _disposePendingTracking(msg);
        }
        _pendingMessages.removeWhere((m) => toRemove.contains(m.messageId));
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

  void _setupLastReadStream() {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;
      if (currentUser == null) return;
      final stream = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('chatReads')
          .doc(widget.groupId)
          .snapshots()
          .map((doc) {
            if (doc.exists && doc.data() != null && doc['lastReadAt'] != null) {
              return doc['lastReadAt'] as Timestamp;
            }
            return Timestamp.fromDate(
              DateTime.now().subtract(const Duration(days: 30)),
            );
          });
      _lastReadAtSub?.cancel();
      _lastReadAtSub = stream.listen((ts) {
        if (mounted) setState(() => _lastReadAt = ts);
      });
    } catch (e) {
      // Fail silently — unread divider is non-critical
    }
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

  Widget _buildUnreadDivider({int count = 0}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = _chatAccentColor(context);
    final label = count <= 1 ? '1 unread message' : '$count unread messages';
    final dividerColor = isDark
        ? const Color(0x339E9E9E)
        : Colors.grey.shade300;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: dividerColor, thickness: 1)),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: accentColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Divider(color: dividerColor, thickness: 1)),
        ],
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

  ForwardMessageData _buildForwardDataForMessage(CommunityMessageModel msg) {
    return ForwardMessageData.fromRaw(
      messageId: msg.messageId,
      senderId: msg.senderId,
      senderName: msg.senderName,
      rawData: _asStringDynamicMap(msg.documentSnapshot?.data()),
      imageUrl: msg.imageUrl,
      message: msg.content,
      mediaMetadata: msg.mediaMetadata,
      multipleMedia: msg.multipleMedia,
    );
  }

  Map<String, dynamic>? _asStringDynamicMap(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      final mapped = <String, dynamic>{};
      raw.forEach((key, value) {
        mapped[key.toString()] = value;
      });
      return mapped;
    }
    return null;
  }

  dynamic _sanitizeForLocalHive(dynamic value) {
    if (value == null) return null;

    // Avoid direct Timestamp dependency while still handling Firestore values.
    if (value.runtimeType.toString() == 'Timestamp') {
      final dynamic ts = value;
      return ts.millisecondsSinceEpoch as int;
    }

    if (value is DateTime) {
      return value.millisecondsSinceEpoch;
    }

    if (value is Map) {
      final mapped = <String, dynamic>{};
      value.forEach((key, val) {
        mapped[key.toString()] = _sanitizeForLocalHive(val);
      });
      return mapped;
    }

    if (value is List) {
      return value.map(_sanitizeForLocalHive).toList();
    }

    return value;
  }

  MediaMetadata _normalizeMediaMetadata(MediaMetadata media) {
    final normalizedR2Key = media.r2Key.isNotEmpty
        ? media.r2Key
        : _extractR2KeyFromMediaUrl(media.publicUrl);
    final normalizedPublicUrl = media.publicUrl.isNotEmpty
        ? media.publicUrl
        : (normalizedR2Key.isNotEmpty
              ? '${CloudflareConfig.r2Domain}/$normalizedR2Key'
              : '');

    return MediaMetadata(
      messageId: media.messageId,
      r2Key: normalizedR2Key,
      publicUrl: normalizedPublicUrl,
      localPath: media.localPath,
      thumbnail: media.thumbnail,
      deletedLocally: media.deletedLocally,
      serverStatus: media.serverStatus,
      expiresAt: media.expiresAt,
      uploadedAt: media.uploadedAt,
      fileSize: media.fileSize,
      mimeType: media.mimeType,
      originalFileName: media.originalFileName,
    );
  }

  String _extractR2KeyFromMediaUrl(String url) {
    if (url.trim().isEmpty) return '';

    final parsed = Uri.tryParse(url.trim());
    if (parsed == null) return '';

    var path = parsed.path;
    while (path.startsWith('/')) {
      path = path.substring(1);
    }
    if (path.isEmpty) return '';

    final mediaIndex = path.indexOf('media/');
    if (mediaIndex >= 0) {
      path = path.substring(mediaIndex);
    } else {
      path = 'media/$path';
    }

    return Uri.decodeFull(path);
  }

  String _resolvedMediaDisplaySource(
    MediaMetadata media, {
    required bool isPending,
  }) {
    final localByKey = media.r2Key.isNotEmpty
        ? _localSenderMediaPaths[media.r2Key]
        : null;
    final localByMessageId = media.messageId.isNotEmpty
        ? _localSenderMediaPaths[media.messageId]
        : null;

    final candidates = <String?>[
      if (isPending) localByKey,
      if (isPending) localByMessageId,
      media.localPath,
      media.publicUrl,
      if (media.r2Key.isNotEmpty) '${CloudflareConfig.r2Domain}/${media.r2Key}',
      media.thumbnail,
    ];

    for (final candidate in candidates) {
      final value = (candidate ?? '').trim();
      if (value.isEmpty) continue;
      if (value.startsWith('/')) return value;
      if (value.startsWith('http://') || value.startsWith('https://')) {
        return value;
      }
      if (value.startsWith('data:image/')) return value;
    }

    return '';
  }

  String _messageMediaFingerprint(CommunityMessageModel msg) {
    final parts = <String>[
      msg.type,
      msg.content,
      msg.imageUrl,
      msg.fileUrl,
      msg.fileName,
      '${msg.createdAt.millisecondsSinceEpoch}',
      '${msg.updatedAt?.millisecondsSinceEpoch ?? -1}',
    ];

    if (msg.mediaMetadata != null) {
      final media = _normalizeMediaMetadata(msg.mediaMetadata!);
      parts.addAll([
        media.messageId,
        media.r2Key,
        media.publicUrl,
        media.localPath ?? '',
        media.thumbnail,
        media.mimeType ?? '',
        media.originalFileName ?? '',
        '${media.fileSize ?? -1}',
      ]);
    }

    for (final media in _effectiveMultipleMedia(msg)) {
      final normalized = _normalizeMediaMetadata(media);
      parts.addAll([
        normalized.messageId,
        normalized.r2Key,
        normalized.publicUrl,
        normalized.localPath ?? '',
        normalized.thumbnail,
        normalized.mimeType ?? '',
        normalized.originalFileName ?? '',
        '${normalized.fileSize ?? -1}',
      ]);
    }

    return parts.join('|');
  }

  bool _sameReactionSummary(Map<String, int> a, Map<String, int> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  String? _legacyMultiImageGroupKey(CommunityMessageModel msg) {
    if (msg.multipleMedia != null && msg.multipleMedia!.length > 1) {
      return null;
    }

    final media = msg.mediaMetadata;
    if (media == null || !_isImageMime(media.mimeType)) return null;

    final rawId = media.messageId.trim();
    if (rawId.isEmpty) return null;

    final match = RegExp(r'^(.+)_\d+$').firstMatch(rawId);
    if (match == null) return null;

    final prefix = match.group(1)?.trim();
    if (prefix == null || prefix.isEmpty) return null;
    if (!(prefix.startsWith('upload_') || prefix.startsWith('pending_'))) {
      return null;
    }

    return '${msg.senderId}|$prefix';
  }

  bool _isStandaloneImageMessage(CommunityMessageModel msg) {
    final media = msg.mediaMetadata;
    if (media == null || !_isImageMime(media.mimeType)) return false;
    if (msg.multipleMedia != null && msg.multipleMedia!.length > 1) {
      return false;
    }
    if (msg.content.trim().isNotEmpty) return false;
    if (msg.replyTo.trim().isNotEmpty) return false;
    return true;
  }

  bool _canBurstGroupImages(
    CommunityMessageModel anchor,
    CommunityMessageModel candidate,
  ) {
    if (!_isStandaloneImageMessage(anchor) ||
        !_isStandaloneImageMessage(candidate)) {
      return false;
    }
    if (anchor.senderId != candidate.senderId) return false;

    final timeDiff =
        (anchor.createdAt.millisecondsSinceEpoch -
                candidate.createdAt.millisecondsSinceEpoch)
            .abs();

    return timeDiff <= 45 * 1000;
  }

  List<CommunityMessageModel> _collapseLegacyMultiImageMessages(
    List<CommunityMessageModel> messages,
  ) {
    if (messages.length < 2) return messages;

    final collapsed = <CommunityMessageModel>[];
    int index = 0;

    while (index < messages.length) {
      final current = messages[index];
      final groupKey = _legacyMultiImageGroupKey(current);

      if (groupKey == null && !_isStandaloneImageMessage(current)) {
        collapsed.add(current);
        index++;
        continue;
      }

      final grouped = <CommunityMessageModel>[current];
      int probe = index + 1;

      while (probe < messages.length) {
        final candidate = messages[probe];
        final candidateKey = _legacyMultiImageGroupKey(candidate);
        final sameExplicitGroup =
            groupKey != null &&
            candidateKey != null &&
            candidateKey == groupKey;
        final sameBurst = _canBurstGroupImages(current, candidate);

        if (!sameExplicitGroup && !sameBurst) {
          break;
        }

        grouped.add(candidate);
        probe++;
      }

      if (grouped.length == 1) {
        collapsed.add(current);
        index++;
        continue;
      }

      final mediaList = grouped
          .map((msg) => msg.mediaMetadata)
          .whereType<MediaMetadata>()
          .map(_normalizeMediaMetadata)
          .toList();

      _debugLogMultiImage(
        'legacyCollapse',
        messageId: current.messageId,
        parsedCount: grouped.length,
        effectiveCount: mediaList.length,
        resolvedSources: mediaList
            .map((m) => _resolvedMediaDisplaySource(m, isPending: false))
            .toList(),
      );

      collapsed.add(
        CommunityMessageModel(
          messageId:
              'legacy-group:${groupKey ?? 'burst_${current.senderId}_${current.createdAt.millisecondsSinceEpoch}'}:${current.messageId}',
          communityId: current.communityId,
          senderId: current.senderId,
          senderName: current.senderName,
          senderRole: current.senderRole,
          senderAvatar: current.senderAvatar,
          type: 'image',
          content: grouped
              .map((m) => m.content.trim())
              .firstWhere((text) => text.isNotEmpty, orElse: () => ''),
          imageUrl: '',
          fileUrl: '',
          fileName: '',
          mediaMetadata: mediaList.isNotEmpty ? mediaList.first : null,
          multipleMedia: mediaList,
          createdAt: current.createdAt,
          updatedAt: current.updatedAt,
          isEdited: grouped.any((m) => m.isEdited),
          isDeleted: false,
          isPinned: grouped.any((m) => m.isPinned),
          reactions: current.reactions,
          reactionSummary: current.reactionSummary,
          reactionCount: current.reactionCount,
          replyTo: current.replyTo,
          replyCount: grouped.fold<int>(0, (sum, m) => sum + m.replyCount),
          isReported: grouped.any((m) => m.isReported),
          reportCount: grouped.fold<int>(0, (sum, m) => sum + m.reportCount),
          deletedFor: current.deletedFor,
          documentSnapshot: current.documentSnapshot,
        ),
      );

      index = probe;
    }

    return collapsed;
  }

  void _debugLogMultiImage(
    String stage, {
    required String messageId,
    int? parsedCount,
    int? rawCount,
    int? effectiveCount,
    List<String>? resolvedSources,
  }) {
    if (!_debugMultiImageGrid) return;
    debugPrint(
      '[ParentGroupMultiImage][$stage] '
      'messageId=$messageId '
      'parsed=${parsedCount ?? '-'} '
      'raw=${rawCount ?? '-'} '
      'effective=${effectiveCount ?? '-'} '
      'sources=${resolvedSources ?? const <String>[]}',
    );
  }

  void _debugLogDisplayImageSummary(List<CommunityMessageModel> messages) {
    if (!_debugMultiImageGrid) return;

    final imageMessages = messages
        .where(
          (msg) =>
              (msg.mediaMetadata != null &&
                  _isImageMime(msg.mediaMetadata!.mimeType)) ||
              (msg.multipleMedia != null && msg.multipleMedia!.isNotEmpty),
        )
        .take(20)
        .toList();

    if (imageMessages.isEmpty) {
      debugPrint('[ParentGroupMultiImage][summary] no image candidates');
      return;
    }

    for (final msg in imageMessages) {
      final media = msg.mediaMetadata;
      debugPrint(
        '[ParentGroupMultiImage][summary] '
        'id=${msg.messageId} '
        'sender=${msg.senderId} '
        'type=${msg.type} '
        'created=${msg.createdAt.millisecondsSinceEpoch} '
        'singleImage=${media != null && _isImageMime(media.mimeType)} '
        'multiple=${msg.multipleMedia?.length ?? 0} '
        'mediaId=${media?.messageId ?? '-'} '
        'r2Key=${media?.r2Key ?? '-'} '
        'contentEmpty=${msg.content.trim().isEmpty}',
      );
    }
  }

  List<MediaMetadata> _extractRawMultipleMedia(dynamic rawList) {
    if (rawList is! List) return const <MediaMetadata>[];

    final extracted = <MediaMetadata>[];
    for (final item in rawList) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      try {
        extracted.add(
          _normalizeMediaMetadata(MediaMetadata.fromFirestore(map)),
        );
        continue;
      } catch (_) {
        // Fall back to lenient parsing below.
      }

      final publicUrl = (map['publicUrl'] ?? map['url'] ?? '').toString();
      final r2Key = (map['r2Key'] ?? '').toString();
      final localPath = (map['localPath'] ?? '').toString();
      final thumbnail = (map['thumbnail'] ?? '').toString();

      if (publicUrl.isEmpty &&
          r2Key.isEmpty &&
          localPath.isEmpty &&
          thumbnail.isEmpty) {
        continue;
      }

      final nameRaw = (map['originalFileName'] ?? '').toString();
      final sizeRaw = map['fileSize'];

      extracted.add(
        _normalizeMediaMetadata(
          MediaMetadata(
            messageId: (map['messageId'] ?? '').toString(),
            r2Key: r2Key,
            publicUrl: publicUrl,
            localPath: localPath.isEmpty ? null : localPath,
            thumbnail: thumbnail,
            expiresAt: DateTime.now().add(const Duration(days: 30)),
            uploadedAt: DateTime.now(),
            fileSize: sizeRaw is num
                ? sizeRaw.toInt()
                : int.tryParse('$sizeRaw'),
            mimeType: (map['mimeType'] ?? map['type'] ?? 'image/jpeg')
                .toString(),
            originalFileName: nameRaw.isEmpty ? null : nameRaw,
          ),
        ),
      );
    }

    return extracted;
  }

  List<MediaMetadata> _effectiveMultipleMedia(CommunityMessageModel msg) {
    final raw = msg.documentSnapshot?.data();
    final parsed =
        msg.multipleMedia?.map(_normalizeMediaMetadata).toList() ??
        const <MediaMetadata>[];
    final rawExtracted = raw is Map
        ? _extractRawMultipleMedia(raw['multipleMedia'])
        : const <MediaMetadata>[];

    final merged = <String, MediaMetadata>{};
    for (final media in [...rawExtracted, ...parsed]) {
      final key = media.messageId.isNotEmpty
          ? media.messageId
          : (media.r2Key.isNotEmpty ? media.r2Key : media.publicUrl);
      if (key.isEmpty) continue;
      merged[key] = media;
    }

    final effective = merged.values.toList();
    if (parsed.length != rawExtracted.length ||
        effective.length != parsed.length) {
      _debugLogMultiImage(
        'effectiveMultipleMedia',
        messageId: msg.messageId,
        parsedCount: parsed.length,
        rawCount: rawExtracted.length,
        effectiveCount: effective.length,
      );
    }

    return effective;
  }

  void _onEmojiSelected(String emoji) {
    final value = _controller.value;
    final start = value.selection.start;
    final end = value.selection.end;

    if (start < 0 || end < 0) {
      _controller.text = '${_controller.text}$emoji';
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
      return;
    }

    final text = value.text;
    final selectedStart = start < end ? start : end;
    final selectedEnd = start < end ? end : start;
    final nextText =
        '${text.substring(0, selectedStart)}$emoji${text.substring(selectedEnd)}';
    final nextOffset = selectedStart + emoji.length;
    _controller.value = value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
      composing: TextRange.empty,
    );
  }

  void _onBackspacePressed() {
    final value = _controller.value;
    final text = value.text;
    if (text.isEmpty) return;

    final start = value.selection.start;
    final end = value.selection.end;

    if (start < 0 || end < 0) {
      final chars = text.characters;
      if (chars.isEmpty) return;
      final nextText = chars.skipLast(1).toString();
      _controller.value = TextEditingValue(
        text: nextText,
        selection: TextSelection.collapsed(offset: nextText.length),
      );
      return;
    }

    if (start != end) {
      final selectedStart = start < end ? start : end;
      final selectedEnd = start < end ? end : start;
      final nextText =
          '${text.substring(0, selectedStart)}${text.substring(selectedEnd)}';
      _controller.value = value.copyWith(
        text: nextText,
        selection: TextSelection.collapsed(offset: selectedStart),
        composing: TextRange.empty,
      );
      return;
    }

    if (start == 0) return;
    final prefix = text.substring(0, start).characters;
    if (prefix.isEmpty) return;
    final truncatedPrefix = prefix.skipLast(1).toString();
    final nextText = '$truncatedPrefix${text.substring(start)}';
    _controller.value = value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: truncatedPrefix.length),
      composing: TextRange.empty,
    );
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
      _loadMoreMessages();
    }
  }

  /// ✅ OPTIMIZATION: Load older messages with pagination - NO STATE CHANGES
  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMoreMessages) {
      return;
    }

    _isLoadingMore = true;
    _isLoadingMoreNotifier.value = true;

    // Save current scroll position before loading
    final savedPosition = scrollController.hasClients
        ? scrollController.position.pixels
        : 0.0;

    try {
      final newMessages = await _service.getMessagesPaginated(
        groupId: widget.groupId,
        limit: _messagesPerPage,
        startAfter: _lastDocument,
      );

      if (newMessages.length < _messagesPerPage) {
        _hasMoreMessages = false;
      }

      if (newMessages.isNotEmpty && mounted) {
        // Disable scroll listener before adding messages
        _isRestoringScroll = true;

        // ✅ KEY FIX: Add messages directly WITHOUT calling setState
        // This prevents triggering the StreamBuilder rebuild
        _olderMessages.addAll(newMessages);
        _lastDocument = newMessages.last.documentSnapshot;

        // ✅ KEY FIX: Update loading notifier AFTER messages are added
        // This updates only the loading indicator, not the entire list
        _isLoadingMoreNotifier.value = false;

        // Restore scroll position after the next frame
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            _isRestoringScroll = false;
            return;
          }

          if (!scrollController.hasClients) {
            _isRestoringScroll = false;
            return;
          }

          try {
            scrollController.jumpTo(savedPosition);
          } catch (e) {
            // If position is out of bounds, jump to safe position
            try {
              final safePosition =
                  scrollController.position.maxScrollExtent * 0.5;
              scrollController.jumpTo(safePosition);
            } catch (_) {}
          }

          // Re-enable scroll listener after restoration is complete
          if (mounted) {
            Future.delayed(const Duration(milliseconds: 50), () {
              if (mounted) {
                _isRestoringScroll = false;
              }
            });
          }
        });
      } else {
        _hasMoreMessages = false;
        _isLoadingMoreNotifier.value = false;
      }
    } catch (e) {
      _isLoadingMoreNotifier.value = false;
    } finally {
      _isLoadingMore = false;
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

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.currentUser;
    final senderId = user?.uid ?? '';
    final senderName = user?.name ?? 'Parent';

    final now = DateTime.now();
    final pendingBaseId =
        'text_${now.millisecondsSinceEpoch}_${senderId.hashCode}_${_pendingTextSequence++}';
    final pendingMessageId = 'pending:$pendingBaseId';

    final pendingMessage = CommunityMessageModel(
      messageId: pendingMessageId,
      communityId: widget.groupId,
      senderId: senderId,
      senderName: senderName,
      senderRole: widget.senderRole,
      senderAvatar: user?.profileImage ?? '',
      type: 'text',
      content: text,
      imageUrl: '',
      fileUrl: '',
      fileName: '',
      createdAt: now,
      isEdited: false,
      isDeleted: false,
      isPinned: false,
      reactions: const {},
      replyTo: '',
      replyCount: 0,
      isReported: false,
      reportCount: 0,
    );

    setState(() {
      _pendingMessages.insert(0, pendingMessage);
      _messageCache[pendingMessage.messageId] = pendingMessage;
      _failedPendingTextMessageIds.remove(pendingMessage.messageId);
    });

    try {
      final localMessage = LocalMessage(
        messageId: pendingBaseId,
        chatId: widget.groupId,
        chatType: 'parent_group',
        senderId: senderId,
        senderName: senderName,
        messageText: text,
        timestamp: now.millisecondsSinceEpoch,
        isPending: true,
      );
      await _localRepo.saveMessage(localMessage);
    } catch (_) {
      // Local persistence is best-effort; optimistic UI still proceeds.
    }

    // Clear immediately like WhatsApp (no loading state)
    _controller.clear();
    _scrollToBottom();

    unawaited(_sendPendingTextMessage(pendingMessage));

    if (!_isOnline) {
      _showOfflineSnackBar();
    }
  }

  /// ✅ NEW: Instant scroll to bottom to show latest message
  void _scrollToBottom() {
    if (!scrollController.hasClients) return;

    // Schedule after frame to ensure ListView has laid out
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scrollController.hasClients) {
        return;
      }

      try {
        // Instant jump to bottom (0 in reverse list) - no animation
        scrollController.jumpTo(0.0);
      } catch (e) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // ✅ Required for AutomaticKeepAliveClientMixin
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentUserId =
        Provider.of<AuthProvider>(context, listen: false).currentUser?.uid ??
        '';
    final primaryColor = _chatAccentColor(context);
    // Compute last-read threshold for unread divider
    final lastReadMs =
        _lastReadAt?.toDate().millisecondsSinceEpoch ??
        DateTime.now()
            .subtract(const Duration(days: 30))
            .millisecondsSinceEpoch;

    return WillPopScope(
      onWillPop: () async {
        if (_selectionMode) {
          setState(() => _selectionMode = false);
          _selectedMessages.value = {};
          _invalidateSelectionEligibilityCache();
          return false;
        }
        return true;
      },
      child: Scaffold(
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
                _invalidateSelectionEligibilityCache();
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
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FutureBuilder<bool>(
                            future: _getForwardEligibilityFuture(selectedSet),
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
                                onPressed: selectedSet.isEmpty
                                    ? null
                                    : _forwardSelectedMessages,
                              );
                            },
                          ),
                          FutureBuilder<bool>(
                            future: _getShareEligibilityFuture(selectedSet),
                            builder: (context, snapshot) {
                              final canShare = snapshot.data == true;
                              if (!canShare) return const SizedBox.shrink();
                              return IconButton(
                                icon: Icon(
                                  Icons.share_rounded,
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black87,
                                  size: 24,
                                ),
                                tooltip: 'Share',
                                onPressed: _shareSelectedMessages,
                              );
                            },
                          ),
                          FutureBuilder<bool>(
                            future: _getDeleteEligibilityFuture(selectedSet),
                            builder: (context, snapshot) {
                              final canDelete = snapshot.data == true;
                              if (!canDelete) return const SizedBox.shrink();
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
                        ],
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
                      child: CircularProgressIndicator(color: primaryColor),
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
                      final hasChange =
                          cached.type != msg.type ||
                          cached.updatedAt != msg.updatedAt ||
                          cached.createdAt != msg.createdAt ||
                          cached.reactionCount != msg.reactionCount ||
                          !_sameReactionSummary(
                            cached.reactionSummary,
                            msg.reactionSummary,
                          ) ||
                          _messageMediaFingerprint(cached) !=
                              _messageMediaFingerprint(msg);

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

                  // ✅ SMART MERGE: Remove pending messages that now exist in Firestore
                  final pendingIdsToRemove = <String>[];
                  final pendingById = {
                    for (final pending in _pendingMessages)
                      pending.messageId: pending,
                  };
                  final filteredPendingMessages = <CommunityMessageModel>[];

                  for (final pendingMsg in _pendingMessages) {
                    final pendingId = pendingMsg.messageId.replaceFirst(
                      'pending:',
                      '',
                    );

                    // 1️⃣ FIRST: exact server-id match should always win,
                    // even if local progress notifier is stale after navigation.
                    final hasExactServerMatch = cachedFirestoreMessages.any(
                      (serverMsg) => serverMsg.messageId == pendingId,
                    );
                    if (hasExactServerMatch) {
                      _logPendingUploadTrace('dedupeExactServerMatch', {
                        'pendingId': pendingMsg.messageId,
                        'serverId': pendingId,
                      });
                      pendingIdsToRemove.add(pendingMsg.messageId);
                      continue;
                    }

                    // 2️⃣ FALLBACK: Content-based matching
                    final pendingSenderId = pendingMsg.senderId;
                    final pendingTimestamp =
                        pendingMsg.createdAt.millisecondsSinceEpoch;
                    final pendingAgeMs =
                        DateTime.now().millisecondsSinceEpoch -
                        pendingTimestamp;
                    final isStalePending =
                        pendingAgeMs > _pendingUploadStaleTimeoutMs;
                    final pendingHasMultipleMedia =
                        pendingMsg.multipleMedia != null &&
                        pendingMsg.multipleMedia!.isNotEmpty;
                    final pendingHasAttachment =
                        pendingHasMultipleMedia ||
                        pendingMsg.mediaMetadata != null;

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
                    if (pendingMsg.mediaMetadata?.originalFileName != null &&
                        pendingMsg.mediaMetadata?.fileSize != null) {
                      pendingFileKeys.add(
                        '${pendingMsg.mediaMetadata!.originalFileName!.toLowerCase()}|${pendingMsg.mediaMetadata!.fileSize}',
                      );
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
                      final timeDiff = (serverTimestamp - pendingTimestamp)
                          .abs();
                      // ✅ Extended time window for media uploads (5 minutes)
                      final timeWindow = pendingHasAttachment ? 300000 : 30000;
                      final timeMatch = timeDiff < timeWindow;

                      // ✅ Check file name matching (case-insensitive)
                      bool fileMatch = false;
                      if (pendingFileKeys.isNotEmpty) {
                        final serverFileKeys = <String>{};
                        if (msg.multipleMedia != null) {
                          for (final media in msg.multipleMedia!) {
                            if (media.originalFileName != null &&
                                media.fileSize != null) {
                              serverFileKeys.add(
                                '${media.originalFileName!.toLowerCase()}|${media.fileSize}',
                              );
                            }
                          }
                        }
                        if (msg.mediaMetadata?.originalFileName != null &&
                            msg.mediaMetadata?.fileSize != null) {
                          serverFileKeys.add(
                            '${msg.mediaMetadata!.originalFileName!.toLowerCase()}|${msg.mediaMetadata!.fileSize}',
                          );
                        }
                        fileMatch = serverFileKeys.any(
                          pendingFileKeys.contains,
                        );
                      }

                      final serverHasAttachment =
                          (msg.multipleMedia != null &&
                              msg.multipleMedia!.isNotEmpty) ||
                          msg.mediaMetadata != null ||
                          msg.fileUrl.isNotEmpty ||
                          msg.imageUrl.isNotEmpty;

                      // For multi-media messages, ONLY match if server has multipleMedia too
                      if (pendingHasMultipleMedia) {
                        final serverHasMultipleMedia =
                            msg.multipleMedia != null &&
                            msg.multipleMedia!.isNotEmpty;

                        return senderMatch &&
                            timeMatch &&
                            (serverHasMultipleMedia || fileMatch);
                      }

                      if (pendingHasAttachment) {
                        if (pendingFileKeys.isNotEmpty) {
                          return senderMatch && timeMatch && fileMatch;
                        }
                        return senderMatch && timeMatch && serverHasAttachment;
                      }

                      final pendingText = pendingMsg.content.trim();
                      final sameText = msg.content.trim() == pendingText;
                      return senderMatch && timeMatch && sameText;
                    }).firstOrNull;

                    if (matchingServerMsg != null) {
                      // Server message exists; remove pending duplicate.
                      _logPendingUploadTrace('dedupeFallbackServerMatch', {
                        'pendingId': pendingMsg.messageId,
                        'serverId': matchingServerMsg.messageId,
                      });
                      pendingIdsToRemove.add(pendingMsg.messageId);
                    } else {
                      // Check upload state only after all server-match paths.
                      final uploadInProgress = _isPendingUploadInProgress(
                        pendingMsg,
                      );

                      if (uploadInProgress && !isStalePending) {
                        _logPendingUploadTrace('dedupeKeepUploading', {
                          'pendingId': pendingMsg.messageId,
                          'progressPending':
                              _pendingUploadNotifiers[pendingMsg.messageId]
                                  ?.value
                                  .toStringAsFixed(1) ??
                              'na',
                          'ageMs': pendingAgeMs,
                        });
                        final cachedPending =
                            _messageCache[pendingMsg.messageId] ??= pendingMsg;
                        filteredPendingMessages.add(cachedPending);
                      } else if (uploadInProgress && isStalePending) {
                        _logPendingUploadTrace('dedupeDropStaleUploading', {
                          'pendingId': pendingMsg.messageId,
                          'progressPending':
                              _pendingUploadNotifiers[pendingMsg.messageId]
                                  ?.value
                                  .toStringAsFixed(1) ??
                              'na',
                          'ageMs': pendingAgeMs,
                        });
                        pendingIdsToRemove.add(pendingMsg.messageId);
                      } else if (isStalePending) {
                        _logPendingUploadTrace('dedupeDropStaleNoServer', {
                          'pendingId': pendingMsg.messageId,
                          'ageMs': pendingAgeMs,
                        });
                        pendingIdsToRemove.add(pendingMsg.messageId);
                      } else {
                        _logPendingUploadTrace('dedupeKeepNoServerMatch', {
                          'pendingId': pendingMsg.messageId,
                        });
                        final cachedPending =
                            _messageCache[pendingMsg.messageId] ??= pendingMsg;
                        filteredPendingMessages.add(cachedPending);
                      }
                    }
                  }

                  // Remove completed pending messages (after frame to avoid flicker)
                  if (pendingIdsToRemove.isNotEmpty) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      setState(() {
                        _pendingMessages.removeWhere(
                          (m) => pendingIdsToRemove.contains(m.messageId),
                        );
                        // Clean up notifiers and cache for removed pending messages
                        for (final pendingId in pendingIdsToRemove) {
                          final pendingMsg = pendingById[pendingId];
                          if (pendingMsg != null) {
                            _disposePendingTracking(pendingMsg);
                          }
                          // Remove pending message from cache (but keep Firestore messages)
                          _messageCache.remove(pendingId);
                          if (_offlineInitCompleter.isCompleted) {
                            unawaited(
                              _localRepo.deletePendingMessage(
                                _cacheMessageIdFromPendingId(pendingId),
                              ),
                            );
                            unawaited(
                              _localRepo.deletePendingMessage(pendingId),
                            );
                          }
                        }
                      });
                    });
                  }

                  // ✅ COMBINE: pending + Firestore + preserved cache + older paginated messages
                  // Deduplicate by messageId to prevent any source of duplication
                  final seenIds = <String>{};
                  final allMessages = <CommunityMessageModel>[];
                  for (final msg in [
                    ...filteredPendingMessages,
                    ...cachedFirestoreMessages,
                    ...olderCachedMessages,
                    ..._olderMessages,
                  ]) {
                    if (_optimisticallyDeletedMessageIds.contains(
                      msg.messageId,
                    )) {
                      continue;
                    }
                    if (seenIds.add(msg.messageId)) {
                      allMessages.add(msg);
                    }
                  }
                  allMessages.sort(
                    (a, b) => b.createdAt.compareTo(a.createdAt),
                  );
                  final displayMessages = _collapseLegacyMultiImageMessages(
                    allMessages,
                  );
                  _debugLogDisplayImageSummary(allMessages);

                  // Update last document from stream if available
                  if (cachedFirestoreMessages.isNotEmpty &&
                      _lastDocument == null) {
                    _lastDocument =
                        cachedFirestoreMessages.last.documentSnapshot;
                  }

                  if (displayMessages.isEmpty) {
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

                  // ── WhatsApp-style unread divider ──────────────────────────
                  int? unreadDividerIndex;
                  bool hasUnreadFromOthers = false;
                  bool hasUnread = false;
                  bool hasRead = false;
                  for (int i = 0; i < displayMessages.length; i++) {
                    final msEpoch =
                        displayMessages[i].createdAt.millisecondsSinceEpoch;
                    final isUnread = msEpoch > lastReadMs;
                    final isFromOthers =
                        displayMessages[i].senderId != currentUserId;
                    hasUnread = hasUnread || isUnread;
                    hasRead = hasRead || !isUnread;
                    if (isUnread && isFromOthers) hasUnreadFromOthers = true;
                    if (i > 0) {
                      final prevMs = displayMessages[i - 1]
                          .createdAt
                          .millisecondsSinceEpoch;
                      if (prevMs > lastReadMs &&
                          !isUnread &&
                          unreadDividerIndex == null) {
                        unreadDividerIndex = i;
                      }
                    }
                  }
                  if (unreadDividerIndex == null && hasUnread && hasRead) {
                    unreadDividerIndex = displayMessages.length - 1;
                  }
                  if (!hasUnreadFromOthers) unreadDividerIndex = null;
                  final unreadCount = displayMessages
                      .where(
                        (m) =>
                            m.createdAt.millisecondsSinceEpoch > lastReadMs &&
                            m.senderId != currentUserId,
                      )
                      .length;
                  // Scroll to first unread on initial open
                  if (_showUnreadDivider &&
                      _lastReadAt != null &&
                      unreadDividerIndex != null &&
                      !_hasScrolledToUnread) {
                    _hasScrolledToUnread = true;
                    final targetIdx = unreadDividerIndex;
                    final totalItems = displayMessages.length;
                    WidgetsBinding.instance.addPostFrameCallback((_) async {
                      await Future.delayed(const Duration(milliseconds: 300));
                      if (!mounted || !scrollController.hasClients) return;
                      final maxExtent =
                          scrollController.position.maxScrollExtent;
                      if (maxExtent <= 0) return;
                      final target = (targetIdx / totalItems) * maxExtent;
                      scrollController.animateTo(
                        target.clamp(0.0, maxExtent),
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOut,
                      );
                    });
                  }
                  // ──────────────────────────────────────────────────────────

                  return Stack(
                    children: [
                      // Main message list
                      ListView.builder(
                        key: const PageStorageKey('parent_group_chat_list'),
                        controller: scrollController,
                        reverse: true,
                        padding: const EdgeInsets.all(16),
                        itemCount: displayMessages.length,
                        itemBuilder: (context, index) {
                          final msg = displayMessages[index];
                          final isCurrentUser = msg.senderId == currentUserId;

                          // Day separator logic
                          final isOldest = index == displayMessages.length - 1;
                          final currentDate = msg.createdAt;
                          final nextDate = isOldest
                              ? null
                              : displayMessages[index + 1].createdAt;
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
                          final isPending = msg.messageId.startsWith(
                            'pending:',
                          );
                          final isPendingTextOnly =
                              isPending && _isPendingTextMessage(msg);
                          final isTextSendFailed =
                              isPendingTextOnly &&
                              _failedPendingTextMessageIds.contains(
                                msg.messageId,
                              );
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
                          final displayMultipleMedia = _effectiveMultipleMedia(
                            msg,
                          ).where((m) => _isImageMime(m.mimeType)).toList();

                          if (msg.type == 'announcement') {
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_showUnreadDivider &&
                                    unreadDividerIndex == index)
                                  _buildUnreadDivider(count: unreadCount),
                                if (showDayDivider)
                                  _buildDayDivider(currentDate),
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
                                _asStringDynamicMap(
                                  msg.documentSnapshot?.data(),
                                ) ??
                                _localPollDataCache[msg.messageId];
                            if (data != null) {
                              final poll = PollModel.fromMap(
                                data,
                                msg.messageId,
                              );
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_showUnreadDivider &&
                                      unreadDividerIndex == index)
                                    _buildUnreadDivider(count: unreadCount),
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
                              if (_showUnreadDivider &&
                                  unreadDividerIndex == index)
                                _buildUnreadDivider(count: unreadCount),
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
                                        Expanded(
                                          child: GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onLongPressStart: (details) {
                                              if (isPending) return;

                                              if (isCurrentUser) {
                                                setState(() {
                                                  _selectionMode = true;
                                                });
                                                _selectedMessages.value = {
                                                  ..._selectedMessages.value,
                                                  msg.messageId,
                                                };
                                                _invalidateSelectionEligibilityCache();
                                              }

                                              _showReactionPickerForMessage(
                                                msg: msg,
                                                globalPosition:
                                                    details.globalPosition,
                                              );
                                            },
                                            onTap:
                                                _selectionMode && isCurrentUser
                                                ? () {
                                                    _toggleSelectedMessage(
                                                      messageId: msg.messageId,
                                                      isPending: isPending,
                                                      isSelected: isSelected,
                                                    );
                                                  }
                                                : null,
                                            onDoubleTap:
                                                (!_selectionMode &&
                                                    !isPending &&
                                                    isCurrentUser)
                                                ? () {
                                                    _selectionMode = true;
                                                    setState(() {
                                                      _selectedMessages.value =
                                                          {msg.messageId};
                                                    });
                                                  }
                                                : null,
                                            child: Align(
                                              alignment: isCurrentUser
                                                  ? Alignment.centerRight
                                                  : Alignment.centerLeft,
                                              child: Column(
                                                crossAxisAlignment:
                                                    isCurrentUser
                                                    ? CrossAxisAlignment.end
                                                    : CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  // Show sender name outside the bubble
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
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
                                                        fontWeight:
                                                            FontWeight.w600,
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
                                                            (displayMultipleMedia
                                                                .isNotEmpty)
                                                            ? Colors.transparent
                                                            : (isSelected
                                                                  ? primaryColor
                                                                        .withOpacity(
                                                                          0.2,
                                                                        )
                                                                  : bubbleColor),
                                                        // No border on media bubbles — media cards have their own shape.
                                                        // Only show a subtle selection indicator for text-only bubbles.
                                                        border:
                                                            isSelected &&
                                                                !hasMedia &&
                                                                displayMultipleMedia
                                                                    .isEmpty
                                                            ? Border.all(
                                                                color:
                                                                    primaryColor,
                                                                width: 2.5,
                                                              )
                                                            : null,
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
                                                          // Zero padding for media — let the card fill naturally.
                                                          horizontal:
                                                              hasMedia ||
                                                                  displayMultipleMedia
                                                                      .isNotEmpty
                                                              ? 0
                                                              : 12,
                                                          vertical:
                                                              hasMedia ||
                                                                  displayMultipleMedia
                                                                      .isNotEmpty
                                                              ? 0
                                                              : 8,
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
                                                            if (displayMultipleMedia
                                                                .isNotEmpty) ...[
                                                              Builder(
                                                                builder: (context) {
                                                                  final resolvedImageUrls = displayMultipleMedia
                                                                      .map(
                                                                        (
                                                                          m,
                                                                        ) => _resolvedMediaDisplaySource(
                                                                          m,
                                                                          isPending:
                                                                              isPending,
                                                                        ),
                                                                      )
                                                                      .where(
                                                                        (
                                                                          url,
                                                                        ) => url
                                                                            .isNotEmpty,
                                                                      )
                                                                      .toList();

                                                                  if (resolvedImageUrls
                                                                              .length !=
                                                                          displayMultipleMedia
                                                                              .length ||
                                                                      displayMultipleMedia
                                                                              .length >
                                                                          1) {
                                                                    final rawMessageData =
                                                                        _asStringDynamicMap(
                                                                          msg.documentSnapshot
                                                                              ?.data(),
                                                                        );
                                                                    final rawMultipleMedia =
                                                                        rawMessageData?['multipleMedia'];
                                                                    _debugLogMultiImage(
                                                                      'render',
                                                                      messageId:
                                                                          msg.messageId,
                                                                      parsedCount: msg
                                                                          .multipleMedia
                                                                          ?.length,
                                                                      rawCount:
                                                                          rawMultipleMedia
                                                                              is List
                                                                          ? rawMultipleMedia.length
                                                                          : 0,
                                                                      effectiveCount:
                                                                          displayMultipleMedia
                                                                              .length,
                                                                      resolvedSources:
                                                                          resolvedImageUrls,
                                                                    );
                                                                  }

                                                                  return Container(
                                                                    decoration: BoxDecoration(
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                            12,
                                                                          ),
                                                                    ),
                                                                    clipBehavior:
                                                                        Clip.antiAlias,
                                                                    child: MultiImageMessageBubble(
                                                                      imageUrls:
                                                                          resolvedImageUrls,
                                                                      isMe:
                                                                          isCurrentUser,
                                                                      selectionMode:
                                                                          _selectionMode &&
                                                                          isCurrentUser,
                                                                      onSelectionTap:
                                                                          _selectionMode &&
                                                                              isCurrentUser
                                                                          ? () {
                                                                              _toggleSelectedMessage(
                                                                                messageId: msg.messageId,
                                                                                isPending: isPending,
                                                                                isSelected: isSelected,
                                                                              );
                                                                            }
                                                                          : null,
                                                                      userRole:
                                                                          Provider.of<
                                                                                AuthProvider
                                                                              >(
                                                                                context,
                                                                                listen: false,
                                                                              )
                                                                              .currentUser
                                                                              ?.role
                                                                              .toString()
                                                                              .split(
                                                                                '.',
                                                                              )
                                                                              .last,
                                                                      // ✅ Show upload progress for pending images
                                                                      uploadProgress:
                                                                          isPending
                                                                          ? displayMultipleMedia.map((
                                                                              m,
                                                                            ) {
                                                                              final notifier = _pendingUploadNotifiers[m.messageId];
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
                                                                          ) async {
                                                                            // Update media list with cached paths
                                                                            final updatedMediaList =
                                                                                <
                                                                                  MediaMetadata
                                                                                >[];
                                                                            for (
                                                                              int
                                                                              i = 0;
                                                                              i <
                                                                                  displayMultipleMedia.length;
                                                                              i++
                                                                            ) {
                                                                              final media = displayMultipleMedia[i];
                                                                              updatedMediaList.add(
                                                                                MediaMetadata(
                                                                                  localPath:
                                                                                      cachedPaths[i] ??
                                                                                      media.localPath,
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
                                                                            // ✅ Open full-screen viewer with zoom, pinch, and swipe
                                                                            await _runWithoutInputFocus(
                                                                              () =>
                                                                                  Navigator.of(
                                                                                    context,
                                                                                  ).push(
                                                                                    MaterialPageRoute(
                                                                                      builder:
                                                                                          (
                                                                                            _,
                                                                                          ) => _ImageGalleryViewer(
                                                                                            mediaList: updatedMediaList,
                                                                                            initialIndex: index,
                                                                                            localFilePaths: _localSenderMediaPaths,
                                                                                            forwardMessage: ForwardMessageData.fromRaw(
                                                                                              messageId: msg.messageId,
                                                                                              senderId: msg.senderId,
                                                                                              senderName: msg.senderName,
                                                                                              rawData: _asStringDynamicMap(
                                                                                                msg.documentSnapshot?.data(),
                                                                                              ),
                                                                                              imageUrl: msg.imageUrl,
                                                                                              message: msg.content,
                                                                                              mediaMetadata: msg.mediaMetadata,
                                                                                              multipleMedia: displayMultipleMedia,
                                                                                            ),
                                                                                          ),
                                                                                    ),
                                                                                  ),
                                                                            );
                                                                          },
                                                                    ),
                                                                  );
                                                                },
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
                                                                        builder:
                                                                            (
                                                                              _,
                                                                              value,
                                                                              _,
                                                                            ) {
                                                                              // ── Failed upload: show retry overlay ──
                                                                              if (value ==
                                                                                  -1.0) {
                                                                                return Stack(
                                                                                  children: [
                                                                                    MediaPreviewCard(
                                                                                      r2Key: msg.mediaMetadata!.r2Key,
                                                                                      fileName: _getFileName(
                                                                                        msg,
                                                                                      ),
                                                                                      mimeType:
                                                                                          msg.mediaMetadata!.mimeType ??
                                                                                          'application/octet-stream',
                                                                                      fileSize:
                                                                                          msg.mediaMetadata!.fileSize ??
                                                                                          0,
                                                                                      thumbnailBase64: msg.mediaMetadata!.thumbnail,
                                                                                      localPath: localPath,
                                                                                      isMe: isCurrentUser,
                                                                                      uploading: false,
                                                                                      uploadProgress: null,
                                                                                      selectionMode: _selectionMode,
                                                                                      forwardMessage: _buildForwardDataForMessage(
                                                                                        msg,
                                                                                      ),
                                                                                    ),
                                                                                    Positioned.fill(
                                                                                      child: Container(
                                                                                        decoration: BoxDecoration(
                                                                                          color: Colors.black.withOpacity(
                                                                                            0.65,
                                                                                          ),
                                                                                          borderRadius: BorderRadius.circular(
                                                                                            12,
                                                                                          ),
                                                                                        ),
                                                                                        child: Column(
                                                                                          mainAxisAlignment: MainAxisAlignment.center,
                                                                                          mainAxisSize: MainAxisSize.min,
                                                                                          children: [
                                                                                            const Icon(
                                                                                              Icons.cloud_off_rounded,
                                                                                              color: Colors.white70,
                                                                                              size: 26,
                                                                                            ),
                                                                                            const SizedBox(
                                                                                              height: 6,
                                                                                            ),
                                                                                            const Text(
                                                                                              'Upload failed',
                                                                                              style: TextStyle(
                                                                                                color: Colors.white70,
                                                                                                fontSize: 12,
                                                                                                fontWeight: FontWeight.w500,
                                                                                              ),
                                                                                            ),
                                                                                            const SizedBox(
                                                                                              height: 10,
                                                                                            ),
                                                                                            ElevatedButton.icon(
                                                                                              onPressed: () => _retryPendingUpload(
                                                                                                msg.messageId,
                                                                                              ),
                                                                                              icon: const Icon(
                                                                                                Icons.refresh_rounded,
                                                                                                size: 15,
                                                                                              ),
                                                                                              label: const Text(
                                                                                                'Retry',
                                                                                                style: TextStyle(
                                                                                                  fontSize: 12,
                                                                                                  fontWeight: FontWeight.w600,
                                                                                                ),
                                                                                              ),
                                                                                              style: ElevatedButton.styleFrom(
                                                                                                backgroundColor: const Color(
                                                                                                  0xFFE53935,
                                                                                                ),
                                                                                                foregroundColor: Colors.white,
                                                                                                padding: const EdgeInsets.symmetric(
                                                                                                  horizontal: 14,
                                                                                                  vertical: 6,
                                                                                                ),
                                                                                                minimumSize: Size.zero,
                                                                                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                                                                shape: RoundedRectangleBorder(
                                                                                                  borderRadius: BorderRadius.circular(
                                                                                                    8,
                                                                                                  ),
                                                                                                ),
                                                                                              ),
                                                                                            ),
                                                                                          ],
                                                                                        ),
                                                                                      ),
                                                                                    ),
                                                                                  ],
                                                                                );
                                                                              }
                                                                              // ── Normal upload in progress ──
                                                                              final progress =
                                                                                  ((value /
                                                                                              100)
                                                                                          .clamp(
                                                                                            0.0,
                                                                                            1.0,
                                                                                          ))
                                                                                      .toDouble();
                                                                              return MediaPreviewCard(
                                                                                r2Key: msg.mediaMetadata!.r2Key,
                                                                                fileName: _getFileName(
                                                                                  msg,
                                                                                ),
                                                                                mimeType:
                                                                                    msg.mediaMetadata!.mimeType ??
                                                                                    'application/octet-stream',
                                                                                fileSize:
                                                                                    msg.mediaMetadata!.fileSize ??
                                                                                    0,
                                                                                thumbnailBase64: msg.mediaMetadata!.thumbnail,
                                                                                localPath: localPath,
                                                                                isMe: isCurrentUser,
                                                                                uploading: true,
                                                                                uploadProgress: progress,
                                                                                selectionMode: _selectionMode,
                                                                                forwardMessage: _buildForwardDataForMessage(
                                                                                  msg,
                                                                                ),
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
                                                                            isPending,
                                                                        uploadProgress:
                                                                            null,
                                                                        selectionMode:
                                                                            _selectionMode,
                                                                        forwardMessage:
                                                                            _buildForwardDataForMessage(
                                                                              msg,
                                                                            ),
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
                                                                text: LinkUtils.addProtocolToBareUrls(
                                                                  msg.content,
                                                                ),
                                                                options:
                                                                    const LinkifyOptions(
                                                                      defaultToHttps:
                                                                          true,
                                                                    ),
                                                                style: TextStyle(
                                                                  color:
                                                                      textColor,
                                                                  fontSize: 15,
                                                                ),
                                                                linkStyle: TextStyle(
                                                                  color:
                                                                      isCurrentUser
                                                                      ? Colors
                                                                            .white
                                                                            .withOpacity(
                                                                              0.95,
                                                                            )
                                                                      : primaryColor,
                                                                  fontSize: 15,
                                                                  decoration:
                                                                      TextDecoration
                                                                          .underline,
                                                                ),
                                                              ),
                                                            if (isPendingTextOnly) ...[
                                                              const SizedBox(
                                                                height: 4,
                                                              ),
                                                              GestureDetector(
                                                                onTap:
                                                                    isTextSendFailed
                                                                    ? () => _retryPendingTextMessage(
                                                                        msg.messageId,
                                                                      )
                                                                    : null,
                                                                child: Row(
                                                                  mainAxisSize:
                                                                      MainAxisSize
                                                                          .min,
                                                                  children: [
                                                                    Icon(
                                                                      isTextSendFailed
                                                                          ? Icons.error_outline_rounded
                                                                          : Icons.schedule_rounded,
                                                                      size: 12,
                                                                      color:
                                                                          isTextSendFailed
                                                                          ? Colors.redAccent
                                                                          : (isCurrentUser
                                                                                ? Colors.white.withOpacity(
                                                                                    0.72,
                                                                                  )
                                                                                : (isDark
                                                                                      ? Colors.white70
                                                                                      : Colors.black54)),
                                                                    ),
                                                                    const SizedBox(
                                                                      width: 4,
                                                                    ),
                                                                    Text(
                                                                      isTextSendFailed
                                                                          ? 'Tap to retry'
                                                                          : 'Sending...',
                                                                      style: TextStyle(
                                                                        color:
                                                                            isTextSendFailed
                                                                            ? Colors.redAccent
                                                                            : (isCurrentUser
                                                                                  ? Colors.white.withOpacity(
                                                                                      0.72,
                                                                                    )
                                                                                  : (isDark
                                                                                        ? Colors.white70
                                                                                        : Colors.black54)),
                                                                        fontSize:
                                                                            11,
                                                                        fontWeight:
                                                                            FontWeight.w500,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                            ],
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  MessageReactionSummary(
                                                    summary:
                                                        msg.reactionSummary,
                                                    isMe: isCurrentUser,
                                                    onTap: _selectionMode
                                                        ? null
                                                        : () =>
                                                              _showReactionViewerForMessage(
                                                                msg,
                                                              ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Padding(
                                                    padding: EdgeInsets.only(
                                                      left: isCurrentUser
                                                          ? 0
                                                          : 8,
                                                      right: isCurrentUser
                                                          ? 8
                                                          : 0,
                                                    ),
                                                    child: Text(
                                                      _formatTime(
                                                        msg.createdAt,
                                                      ),
                                                      style: TextStyle(
                                                        color:
                                                            (isDark
                                                                    ? Colors
                                                                          .white
                                                                    : Colors
                                                                          .black)
                                                                .withOpacity(
                                                                  0.5,
                                                                ),
                                                        fontSize: 10,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
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
                                              behavior:
                                                  HitTestBehavior.translucent,
                                              onTap: () =>
                                                  _toggleSelectedMessage(
                                                    messageId: msg.messageId,
                                                    isPending: isPending,
                                                    isSelected: isSelected,
                                                  ),
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
            if (_showEmojiPicker)
              WhatsAppEmojiPicker(
                accentColor: primaryColor,
                backgroundColor: isDark
                    ? secondaryBackground
                    : Colors.grey.shade100,
                onEmojiSelected: _onEmojiSelected,
                onBackspacePressed: _onBackspacePressed,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput(bool isDark) {
    final primaryColor = _chatAccentColor(context);

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
                    border: Border.all(
                      color: primaryColor.withOpacity(isDark ? 0.45 : 0.25),
                      width: 1.1,
                    ),
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
                      border: Border.all(
                        color: widget.senderRole.toLowerCase() == 'teacher'
                            ? AppColors.teacherColor
                            : primaryColor.withOpacity(isDark ? 0.55 : 0.35),
                        width: widget.senderRole.toLowerCase() == 'teacher'
                            ? 1.6
                            : 1.2,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        IconButton(
                          icon: Icon(
                            _showEmojiPicker
                                ? Icons.keyboard_outlined
                                : Icons.emoji_emotions_outlined,
                            color: mutedText,
                            size: 22,
                          ),
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            setState(() {
                              _showEmojiPicker = !_showEmojiPicker;
                            });
                            if (_showEmojiPicker) {
                              _focusNode.unfocus();
                            } else {
                              _focusNode.requestFocus();
                            }
                          },
                        ),
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
                              filled: false,
                              fillColor: Colors.transparent,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              focusedErrorBorder: InputBorder.none,
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
    if (!_isOnline) {
      _showOfflineSnackBar(isMedia: true);
      return;
    }
    final primaryColor = _chatAccentColor(context);
    unawaited(
      _runWithoutInputFocus(
        () => showModernAttachmentSheet(
          context,
          onCameraTap: _pickAndSendCamera,
          onImageTap: _pickAndSendImage,
          onDocumentTap: _pickAndSendPDF,
          onAudioTap: _pickAndSendAudioFile,
          onPollTap: _navigateToPollScreen,
          mindmapEnabled: false, // ✅ Disable mindmap in parent-teacher groups
          color: primaryColor,
        ),
      ),
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

  /// Retry a failed media upload using the stored local file path.
  Future<void> _retryPendingUpload(String pendingId) async {
    if (!_isOnline) {
      _showOfflineSnackBar(isMedia: true);
      return;
    }
    final localPath = _failedUploadLocalPaths[pendingId];
    final mimeType =
        _failedUploadMimeTypes[pendingId] ?? 'application/octet-stream';

    if (localPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File path unavailable for retry.')),
      );
      return;
    }

    final file = File(localPath);
    if (!await file.exists()) {
      if (mounted) {
        setState(() {
          _pendingMessages.removeWhere((m) => m.messageId == pendingId);
          _pendingUploadNotifiers.remove(pendingId)?.dispose();
          _failedUploadLocalPaths.remove(pendingId);
          _failedUploadMimeTypes.remove(pendingId);
          _lastUploadPercent.remove(pendingId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('File no longer exists. Please re-attach it.'),
          ),
        );
      }
      return;
    }

    final pendingMsg = _pendingMessages
        .cast<CommunityMessageModel?>()
        .firstWhere((m) => m?.messageId == pendingId, orElse: () => null);
    if (pendingMsg == null) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.currentUser;
    if (user == null) return;

    // Reset progress notifier to "in-progress"
    if (mounted) {
      setState(() {
        _pendingUploadNotifiers[pendingId]?.value = 0.0;
        _failedUploadLocalPaths.remove(pendingId);
        _failedUploadMimeTypes.remove(pendingId);
        _lastUploadPercent[pendingId] = -1;
      });
    }

    try {
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
          if (last < 0 || percent == 100 || (percent - last) >= 5) {
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
        mediaType: pendingMsg.type,
        mediaMetadata: metadata,
      );

      await _mediaRepository.cacheUploadedMedia(
        r2Key: r2Key,
        localPath: localPath,
        fileName: localPath.split('/').last,
        mimeType: mimeType,
        fileSize: await file.length(),
      );

      if (mounted) {
        setState(() {
          _pendingMessages.removeWhere((m) => m.messageId == pendingId);
          _pendingUploadNotifiers.remove(pendingId)?.dispose();
          _lastUploadPercent.remove(pendingId);
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _pendingUploadNotifiers[pendingId]?.value = -1.0;
          _failedUploadLocalPaths[pendingId] = localPath;
          _failedUploadMimeTypes[pendingId] = mimeType;
        });
      }
    }
  }

  Future<void> _pickAndSendCamera() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.currentUser;
    if (user == null) return;

    // Captured for catch-block access (try-scope variables not visible there)
    String? capPendingId;
    String? capFilePath;

    try {
      final picked = await _imagePicker.pickImage(source: ImageSource.camera);
      if (picked == null) return;

      final file = File(picked.path);
      final pendingId = 'pending:${DateTime.now().millisecondsSinceEpoch}';
      capPendingId = pendingId;
      capFilePath = file.path;

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

      _logPendingUploadTrace('imageUploadStarted', {
        'pendingId': pendingId,
        'file': file.path.split('/').last,
        'size': file.lengthSync(),
        'mime': 'image/jpeg',
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

      _logPendingUploadTrace('cameraUploadCompleted', {
        'pendingId': pendingId,
        'serverMediaId': mediaMessage.id,
      });

      if (mounted) {
        setState(() {
          _pendingMessages.removeWhere((m) => m.messageId == pendingId);
          _pendingUploadNotifiers.remove(pendingId)?.dispose();
          _localSenderMediaPaths.remove(pendingId);
          _lastUploadPercent.remove(pendingId);
        });
      }
    } catch (e) {
      if (mounted && capPendingId != null && capFilePath != null) {
        final id = capPendingId;
        final path = capFilePath;
        setState(() {
          _pendingUploadNotifiers[id]?.value = -1.0;
          _failedUploadLocalPaths[id] = path;
          _failedUploadMimeTypes[id] = 'image/jpeg';
        });
      }
    }
  }

  Future<void> _pickAndSendImage() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.currentUser;
    if (user == null) return;

    // Captured for catch-block access
    String? capPendingId;
    String? capFilePath;

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
      capPendingId = pendingId;
      capFilePath = file.path;

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

          _logPendingUploadTrace('pdfUploadProgress', {
            'pendingId': pendingId,
            'percent': percent,
          });

          _logPendingUploadTrace('imageUploadProgress', {
            'pendingId': pendingId,
            'percent': percent,
          });
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

      _logPendingUploadTrace('pdfUploadServerSent', {
        'pendingId': pendingId,
        'serverMediaId': mediaMessage.id,
        'r2Key': r2Key,
      });

      _logPendingUploadTrace('imageUploadServerSent', {
        'pendingId': pendingId,
        'serverMediaId': mediaMessage.id,
        'r2Key': r2Key,
      });

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
      if (mounted && capPendingId != null && capFilePath != null) {
        final id = capPendingId;
        final path = capFilePath;
        setState(() {
          _pendingUploadNotifiers[id]?.value = -1.0;
          _failedUploadLocalPaths[id] = path;
          _failedUploadMimeTypes[id] = 'image/jpeg';
        });
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
    } catch (e) {}

    setState(() {
      _pendingMessages.insert(0, pendingMessage);

      // Track local paths and upload progress for each media item
      for (int i = 0; i < localPaths.length; i++) {
        final messageId = '${groupMessageId}_$i';
        _localSenderMediaPaths[messageId] = localPaths[i];
        _pendingUploadNotifiers[messageId] = ValueNotifier<double>(0);
        _lastUploadPercent[messageId] = -1;
      }
    });

    // Upload all images
    try {
      final uploadedMetadata = <MediaMetadata>[];

      for (int i = 0; i < files.length; i++) {
        final file = files[i];
        final messageId = '${groupMessageId}_$i';

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
                    // ✅ FIX: Include thumbnail (local file path) so it survives cache restore
                    final localPath =
                        _localSenderMediaPaths[mId] ?? m.thumbnail;
                    return {
                      'messageId': mId,
                      'localPath': localPath,
                      'thumbnail':
                          localPath, // ✅ Preserve local path as thumbnail
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

        // Cache the uploaded file
        await _mediaRepository.cacheUploadedMedia(
          r2Key: r2Key,
          localPath: file.path,
          fileName: file.path.split('/').last,
          mimeType: 'image/jpeg',
          fileSize: await file.length(),
        );
      }

      // ✅ Create Firestore message with auto-generated ID (like staff room)
      // ✅ CRITICAL: Use correct collection - parent_teacher_groups, not communities!
      final messageTimestamp = DateTime.now().millisecondsSinceEpoch;
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
      } catch (e) {}

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
        } catch (e) {}
      }
    }
  }

  Future<void> _pickAndSendPDF() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.currentUser;
    if (user == null) return;

    // Captured for catch-block access
    String? capPendingId;
    String? capFilePath;
    String capMime = 'application/pdf';

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

      // Capture for retry in catch-block
      capPendingId = pendingId;
      capFilePath = file.path;
      capMime = mimeType;

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
        _localSenderMediaPaths[pendingId] = file.path;
        _lastUploadPercent[pendingId] = -1;
      });

      // ✅ Save pending PDF to cache immediately for persistence
      try {
        final pendingLocalMsg = LocalMessage(
          messageId: _cacheMessageIdFromPendingId(pendingId),
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
      } catch (e) {}

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
          _localSenderMediaPaths[r2Key] = file.path;
          _localSenderMediaPaths.remove(pendingId);
          _lastUploadPercent.remove(pendingId);
        });

        // Remove pending cache entries now that server message is sent.
        try {
          await _localRepo.deletePendingMessage(
            _cacheMessageIdFromPendingId(pendingId),
          );
          await _localRepo.deletePendingMessage(pendingId);
          _logPendingUploadTrace('pdfUploadPendingCacheDeleted', {
            'pendingId': pendingId,
          });
        } catch (_) {}

        // ✅ Scroll to bottom to show newly sent PDF
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted && capPendingId != null && capFilePath != null) {
        final id = capPendingId;
        final path = capFilePath;
        final mime = capMime;
        _logPendingUploadTrace('pdfUploadFailed', {
          'pendingId': id,
          'path': path,
          'mime': mime,
          'error': '$e',
        });
        setState(() {
          _pendingUploadNotifiers[id]?.value = -1.0;
          _failedUploadLocalPaths[id] = path;
          _failedUploadMimeTypes[id] = mime;
        });
      }
    }
  }

  Future<void> _pickAndSendAudioFile() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.currentUser;
    if (user == null) return;

    // Captured for catch-block access
    String? capPendingId;
    String? capFilePath;
    String capMime = 'audio/mpeg';

    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.audio);
      if (result == null || result.files.single.path == null) return;

      final file = File(result.files.single.path!);
      final pendingId = 'pending:${DateTime.now().millisecondsSinceEpoch}';
      final fileName = file.path.split('/').last;
      final fileSize = await file.length();
      final ext = result.files.single.extension?.toLowerCase();
      final mime = _inferAudioMime(ext);

      // Capture for retry in catch-block
      capPendingId = pendingId;
      capFilePath = file.path;
      capMime = mime;

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
        _localSenderMediaPaths[pendingId] = file.path;
        _lastUploadPercent[pendingId] = -1;
      });

      // Save pending audio to cache for restore-after-navigation support.
      try {
        final pendingLocalMsg = LocalMessage(
          messageId: _cacheMessageIdFromPendingId(pendingId),
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
              'mimeType': mime,
            },
          ],
          isPending: true,
        );
        await _localRepo.saveMessage(pendingLocalMsg);
      } catch (_) {}

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

          if (percent % 20 == 0 || percent == 100) {
            _updatePendingMessageCache(pendingId, [
              {
                'messageId': pendingId,
                'localPath': file.path,
                'uploadProgress': percent / 100.0,
                'originalFileName': fileName,
                'fileSize': fileSize,
                'mimeType': mime,
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
          _localSenderMediaPaths[r2Key] = file.path;
          _localSenderMediaPaths.remove(pendingId);
          _lastUploadPercent.remove(pendingId);
        });

        try {
          await _localRepo.deletePendingMessage(
            _cacheMessageIdFromPendingId(pendingId),
          );
          await _localRepo.deletePendingMessage(pendingId);
        } catch (_) {}

        // ✅ Scroll to bottom to show newly sent audio
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted && capPendingId != null && capFilePath != null) {
        final id = capPendingId;
        final path = capFilePath;
        final mime = capMime;
        setState(() {
          _pendingUploadNotifiers[id]?.value = -1.0;
          _failedUploadLocalPaths[id] = path;
          _failedUploadMimeTypes[id] = mime;
        });
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
    var persistedRecordingPath = file.path;

    try {
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final voiceDir = Directory('${appDir.path}/recordings');
        if (!await voiceDir.exists()) {
          await voiceDir.create(recursive: true);
        }
        final persistedFile = File('${voiceDir.path}/$fileName');
        final copied = await file.copy(persistedFile.path);
        persistedRecordingPath = copied.path;
      } catch (_) {}

      final sourceFilePath = persistedRecordingPath;
      final sourceFile = File(sourceFilePath);

      // Create optimistic pending message
      final pendingMetadata = MediaMetadata(
        messageId: pendingId,
        r2Key: 'pending/$fileName',
        publicUrl: '',
        thumbnail: '',
        expiresAt: DateTime.now().add(const Duration(days: 365)),
        uploadedAt: DateTime.now(),
        fileSize: await sourceFile.length(),
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
        _localSenderMediaPaths[pendingId] = sourceFilePath;
        _lastUploadPercent[pendingId] = -1;
      });

      try {
        final pendingLocalMsg = LocalMessage(
          messageId: _cacheMessageIdFromPendingId(pendingId),
          chatId: widget.groupId,
          chatType: 'ptGroup',
          senderId: user.uid,
          senderName: user.name,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          messageText: '',
          multipleMedia: [
            {
              'messageId': pendingId,
              'localPath': sourceFilePath,
              'uploadProgress': 0.0,
              'originalFileName': fileName,
              'fileSize': await sourceFile.length(),
              'mimeType': 'audio/mp4',
            },
          ],
          isPending: true,
        );
        await _localRepo.saveMessage(pendingLocalMsg);
      } catch (_) {}

      // Scroll to bottom to show new message
      Future.delayed(const Duration(milliseconds: 100), () {
        if (scrollController.hasClients) {
          scrollController.jumpTo(0);
        }
      });

      // Upload in background
      final mediaMessage = await _mediaUploadService.uploadMedia(
        file: sourceFile,
        conversationId: widget.groupId,
        senderId: user.uid,
        senderRole: widget.senderRole,
        mediaType: 'community',
        onProgress: (progress) {
          final percent = (progress * 100).toInt();
          if (_lastUploadPercent[pendingId] != percent) {
            _lastUploadPercent[pendingId] = percent;
            _pendingUploadNotifiers[pendingId]?.value = percent.toDouble();

            if (percent % 20 == 0 || percent == 100) {
              _updatePendingMessageCache(pendingId, [
                {
                  'messageId': pendingId,
                  'localPath': sourceFilePath,
                  'uploadProgress': percent / 100.0,
                  'originalFileName': fileName,
                  'fileSize': sourceFile.lengthSync(),
                  'mimeType': 'audio/mp4',
                },
              ]);
            }
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
        localPath: sourceFilePath,
        fileName: fileName,
        mimeType: mediaMessage.fileType,
        fileSize: mediaMessage.fileSize,
      );

      // Remove pending message after successful upload
      if (mounted) {
        setState(() {
          _pendingMessages.removeWhere((m) => m.messageId == pendingId);
          _pendingUploadNotifiers.remove(pendingId)?.dispose();
          _localSenderMediaPaths[r2Key] = sourceFilePath;
          _localSenderMediaPaths.remove(pendingId);
          _lastUploadPercent.remove(pendingId);
        });

        try {
          await _localRepo.deletePendingMessage(
            _cacheMessageIdFromPendingId(pendingId),
          );
          await _localRepo.deletePendingMessage(pendingId);
        } catch (_) {}
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
        if (_recordingPath != null &&
            _recordingPath != persistedRecordingPath) {
          File(_recordingPath!).deleteSync();
        }
      } catch (_) {}
      _recordingPath = null;
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

    final messageIdsToDelete = _selectedMessages.value.toList();

    if (mounted) {
      setState(() {
        _selectionMode = false;
        _optimisticallyDeletedMessageIds.addAll(messageIdsToDelete);
        _olderMessages.removeWhere(
          (message) => messageIdsToDelete.contains(message.messageId),
        );
        for (final messageId in messageIdsToDelete) {
          _messageCache.remove(messageId);
          _messageDataCache.remove(messageId);
        }
      });
      _selectedMessages.value = {};
      _invalidateSelectionEligibilityCache();
    }

    try {
      await _service.deleteMessagesForEveryone(
        groupId: widget.groupId,
        messageIds: messageIdsToDelete,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Messages deleted for everyone'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _optimisticallyDeletedMessageIds.removeAll(messageIdsToDelete);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete messages: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<Map<String, dynamic>?> _getMessageDataById(String id) async {
    final cached = _messageDataCache[id];
    if (cached != null) return cached;

    final doc = await FirebaseFirestore.instance
        .collection('parent_teacher_groups')
        .doc(widget.groupId)
        .collection('messages')
        .doc(id)
        .get();
    if (!doc.exists) return null;

    final data = <String, dynamic>{...?(doc.data()), 'id': doc.id};
    _messageDataCache[id] = data;
    return data;
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

    return null;
  }

  Future<List<ShareMediaItem>> _buildShareItemsFromSelection(
    Set<String> selectedIds,
  ) async {
    final items = <ShareMediaItem>[];

    for (final id in selectedIds) {
      final data = await _getMessageDataById(id);
      if (data == null) return [];

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
        if (localPath == null) return [];

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
          if (localPath == null) return [];

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
        if (localPath == null) return [];
        items.add(
          ShareMediaItem(
            localPath: localPath,
            fileName: legacyMedia['originalFileName'] as String?,
            mimeType: legacyMedia['mimeType'] as String?,
          ),
        );
      }
    }

    return items;
  }

  Future<bool> _canShareSelectedMessages(Set<String> selectedIds) async {
    if (selectedIds.isEmpty) return false;
    final items = await _buildShareItemsFromSelection(selectedIds);
    return items.isNotEmpty;
  }

  Future<bool> _canForwardSelectedMessages(Set<String> selectedIds) async {
    if (selectedIds.isEmpty) return false;

    for (final id in selectedIds) {
      final data = await _getMessageDataById(id);
      if (data == null) return false;

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

  Future<bool> _canDeleteSelectedMessages(Set<String> selectedIds) async {
    if (selectedIds.isEmpty) return false;
    final currentUserId = Provider.of<AuthProvider>(
      context,
      listen: false,
    ).currentUser?.uid;
    if (currentUserId == null || currentUserId.isEmpty) return false;

    for (final id in selectedIds) {
      final data = await _getMessageDataById(id);
      if (data == null) return false;
      final senderId = data['senderId'] as String?;
      if (senderId == null || senderId != currentUserId) {
        return false;
      }
    }

    return true;
  }

  Future<void> _forwardSelectedMessages() async {
    final ids = _selectedMessages.value.toList();
    if (ids.isEmpty) return;

    final canForward = await _canForwardSelectedMessages(Set<String>.from(ids));
    if (!canForward) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Download selected media first to enable forwarding'),
        ),
      );
      return;
    }

    final forwardData = <ForwardMessageData>[];
    for (final id in ids) {
      final data = await _getMessageDataById(id);
      if (data == null) continue;

      final mediaMetaRaw = data['mediaMetadata'];
      final multipleMediaRaw = data['multipleMedia'];

      forwardData.add(
        ForwardMessageData.fromRaw(
          messageId: id,
          senderId: data['senderId'] as String? ?? '',
          senderName: data['senderName'] as String? ?? '',
          rawData: data,
          imageUrl: data['imageUrl'] as String?,
          message: data['text'] as String? ?? '',
          mediaMetadata: mediaMetaRaw is Map
              ? MediaMetadata.fromFirestore(
                  Map<String, dynamic>.from(mediaMetaRaw),
                )
              : null,
          multipleMedia: multipleMediaRaw is List
              ? multipleMediaRaw
                    .whereType<Map>()
                    .map(
                      (media) => MediaMetadata.fromFirestore(
                        Map<String, dynamic>.from(media),
                      ),
                    )
                    .toList()
              : null,
        ),
      );
    }

    setState(() => _selectionMode = false);
    _selectedMessages.value = {};
    _invalidateSelectionEligibilityCache();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ForwardSelectionScreen(messages: forwardData),
      ),
    );
  }

  Future<void> _shareSelectedMessages() async {
    final selectedIds = _selectedMessages.value;
    if (selectedIds.isEmpty) return;

    final items = await _buildShareItemsFromSelection(selectedIds);
    if (items.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Download selected media first to enable sharing'),
        ),
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

    setState(() => _selectionMode = false);
    _selectedMessages.value = {};
    _invalidateSelectionEligibilityCache();
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
  final ForwardMessageData? forwardMessage;

  const _ImageGalleryViewer({
    required this.mediaList,
    required this.initialIndex,
    required this.localFilePaths,
    this.forwardMessage,
  });

  @override
  State<_ImageGalleryViewer> createState() => _ImageGalleryViewerState();
}

class _ImageGalleryViewerState extends State<_ImageGalleryViewer> {
  late PageController _pageController;
  late int _currentIndex;
  late Map<int, TransformationController> _transformationControllers;
  late Map<int, bool> _zoomStates;
  final Map<int, Offset> _doubleTapPositions =
      {}; // Per-image double-tap position
  bool _isInteracting = false; // Track if user is zooming
  int _pointerCount = 0; // Track number of fingers on screen
  bool _isActionBusy = false;

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

  MediaMetadata get _currentMetadata => widget.mediaList[_currentIndex];

  String? get _currentLocalPath {
    final metadata = _currentMetadata;
    return widget.localFilePaths[metadata.r2Key] ?? metadata.thumbnail;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _downloadCurrentImage() async {
    if (_isActionBusy) return;
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
    if (_isActionBusy) return;
    setState(() => _isActionBusy = true);
    try {
      final metadata = _currentMetadata;
      final ok = await ImageViewerActionService.shareImage(
        localPath: _currentLocalPath,
        publicUrl: metadata.publicUrl,
        fileNameHint: metadata.originalFileName,
      );
      if (!ok) _showMessage('Android share failed');
    } catch (_) {
      _showMessage('Android share failed');
    } finally {
      if (mounted) setState(() => _isActionBusy = false);
    }
  }

  Future<void> _forwardCurrentImage() async {
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
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded, color: Colors.white),
            tooltip: 'Download',
            onPressed: _isActionBusy ? null : _downloadCurrentImage,
          ),
          IconButton(
            icon: const Icon(Icons.forward_rounded, color: Colors.white),
            tooltip: 'Forward',
            onPressed: _isActionBusy ? null : _forwardCurrentImage,
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded, color: Colors.white),
            tooltip: 'Share',
            onPressed: _isActionBusy ? null : _shareCurrentImage,
          ),
        ],
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
          errorBuilder: (_, _, _) => _buildFallbackImage(),
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
        onDoubleTapDown: (details) {
          // Capture the exact tap position for position-aware zoom
          _doubleTapPositions[index] = details.localPosition;
        },
        onDoubleTap: () {
          // ✅ Double-tap toggle: 1x ↔ 2.5x zoom at the tapped location
          final controller = _transformationControllers[index]!;
          final scale = controller.value.getMaxScaleOnAxis();

          if (scale > 1.1) {
            // Zoom out to 1x
            controller.value = Matrix4.identity();
          } else {
            // Zoom in to 2.5x at the exact tapped position
            const double zoomLevel = 2.5;
            final tapPos = _doubleTapPositions[index] ?? Offset.zero;
            final matrix = Matrix4.identity()
              ..translate(
                -tapPos.dx * (zoomLevel - 1),
                -tapPos.dy * (zoomLevel - 1),
              )
              ..scale(zoomLevel);
            controller.value = matrix;
          }
          setState(() {});
        },
        child: InteractiveViewer(
          transformationController: _transformationControllers[index],
          minScale: 1.0, // No zoom out below original size
          maxScale: 5.0, // Max 5x zoom
          panEnabled:
              (_zoomStates[index] ?? false) ||
              _pointerCount >=
                  2, // Pan with 1 finger when zoomed, or 2+ fingers
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
