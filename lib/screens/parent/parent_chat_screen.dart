import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/chat_service.dart';
import '../../providers/parent_provider.dart';
import '../../services/media_upload_service.dart';
import '../../services/media_repository.dart';
import '../../services/cloudflare_r2_service.dart';
import '../../services/local_cache_service.dart';
import '../../config/cloudflare_config.dart';
import '../../models/media_metadata.dart';
import '../../widgets/modern_attachment_sheet.dart';
import '../../services/connectivity_service.dart';
import '../../services/message_reaction_service.dart';
import '../../widgets/message_reaction_picker.dart';
import '../../widgets/message_reaction_summary.dart';

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
  final ScrollController _scrollController = ScrollController();
  String? _conversationId;
  // Track messages already scheduled for read marking to avoid re-scheduling.
  final Set<String> _scheduledReadIds = <String>{};

  // Media services
  final ImagePicker _imagePicker = ImagePicker();
  late final MediaUploadService _mediaUploadService;
  final MediaRepository _mediaRepository = MediaRepository();
  bool _isUploading = false;
  bool _isOnline = true;
  StreamSubscription<bool>? _connectivitySub;

  // Pending message tracking
  final List<Map<String, dynamic>> _pendingMessages = [];
  final Map<String, ValueNotifier<double>> _progressNotifiers = {};
  final Map<String, String> _localMediaPaths = {};
  final Map<String, int> _lastUploadPercent = {};
  bool _isReactionPickerOpen = false;
  Map<String, dynamic>? _replyTo;
  List<Map<String, dynamic>> _latestAllMessages = const [];

  // Audio recording
  final AudioRecorder _audioRecorder = AudioRecorder();
  final ValueNotifier<bool> _isRecording = ValueNotifier<bool>(false);
  final ValueNotifier<int> _recordingDuration = ValueNotifier<int>(0);
  Timer? _recordingTimer;
  String? _recordingPath;

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    _audioRecorder.dispose();
    _recordingTimer?.cancel();
    _isRecording.dispose();
    _recordingDuration.dispose();
    // Clean up progress notifiers
    for (final notifier in _progressNotifiers.values) {
      notifier.dispose();
    }
    super.dispose();
  }

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
    _isOnline = ConnectivityService().isOnline;
    _connectivitySub = ConnectivityService().onConnectivityChanged.listen((
      online,
    ) {
      if (mounted) setState(() => _isOnline = online);
    });

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

    final id = await _chat.ensureConversation(
      schoolCode: schoolCode,
      teacherId: teacherId,
      parentId: parentAuthUid,
      studentId: studentId,
      studentName: child.name,
      className: widget.className,
      section: widget.section,
    );

    setState(() => _conversationId = id);
  }

  Map<String, int> _reactionSummaryForMap(Map<String, dynamic> msg) {
    final summary = <String, int>{};
    final raw = msg['reactionSummary'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (key.isEmpty) continue;
        if (value is int && value > 0) {
          summary[key] = value;
        } else if (value is num && value > 0) {
          summary[key] = value.toInt();
        }
      }
    }
    return summary;
  }

  String _replyTypeForMap(Map<String, dynamic> msg) {
    final media = msg['mediaMetadata'];
    if (media is MediaMetadata) {
      final mime = (media.mimeType ?? '').toLowerCase();
      if (mime.startsWith('image/')) return 'image';
      if (mime.startsWith('audio/')) return 'audio';
      return 'document';
    }
    if (media is Map<String, dynamic>) {
      final mime = (media['mimeType'] as String? ?? '').toLowerCase();
      if (mime.startsWith('image/')) return 'image';
      if (mime.startsWith('audio/')) return 'audio';
      return 'document';
    }
    return 'text';
  }

  String _replyPreviewForMap(Map<String, dynamic> msg) {
    final type = _replyTypeForMap(msg);
    if (type == 'image') return '📷 Photo';
    if (type == 'audio') return '🎵 Audio';
    if (type == 'document') return '📄 Document';
    final text = (msg['text'] as String? ?? '').trim();
    if (text.isEmpty) return 'Message';
    return text.length > 64 ? '${text.substring(0, 64)}…' : text;
  }

  void _setReplyTarget(Map<String, dynamic> msg) {
    HapticFeedback.lightImpact();
    final isParent = msg['senderRole'] == 'parent';
    setState(() {
      _replyTo = {
        'messageId': (msg['_docId'] ?? msg['messageId'] ?? '').toString(),
        'senderName': isParent ? 'You' : widget.teacherName,
        'type': _replyTypeForMap(msg),
        'contentPreview': _replyPreviewForMap(msg),
      };
    });
  }

  void _clearReplyTarget() {
    if (_replyTo == null) return;
    setState(() => _replyTo = null);
  }

  Future<void> _jumpToOriginalMessage(String messageId) async {
    final idx = _latestAllMessages.indexWhere(
      (m) => ((m['_docId'] ?? m['messageId'] ?? '').toString()) == messageId,
    );
    if (idx < 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Message not available')));
      return;
    }
    if (!_scrollController.hasClients) return;
    final offset = (idx * 104).toDouble();
    await _scrollController.animateTo(
      offset.clamp(0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  Widget _buildReplyComposerPreview(bool isDark) {
    final reply = _replyTo;
    if (reply == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(10),
        border: const Border(
          left: BorderSide(color: Color(0xFF1362EB), width: 3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Replying to ${reply['senderName'] ?? 'User'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  (reply['contentPreview'] as String?) ?? 'Message',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _clearReplyTarget,
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Cancel reply',
          ),
        ],
      ),
    );
  }

  Widget _buildInlineReplyHeader(Map<String, dynamic> reply, bool isDark) {
    final previewType = (reply['type'] as String? ?? '').toLowerCase();
    final rawPreview = (reply['contentPreview'] as String?)?.trim() ?? '';
    final previewText = switch (previewType) {
      'image' => '📷 Photo',
      'document' => '📄 Document',
      'audio' => '🎵 Audio',
      _ =>
        rawPreview.isEmpty
            ? 'Message not available'
            : (rawPreview.length > 40
                  ? '${rawPreview.substring(0, 40)}...'
                  : rawPreview),
    };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () =>
            _jumpToOriginalMessage((reply['messageId'] as String?) ?? ''),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0x33222F3E) : const Color(0x14000000),
            borderRadius: BorderRadius.circular(8),
            border: const Border(
              left: BorderSide(color: Color(0xFF22C55E), width: 3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                (reply['senderName'] as String?) ?? 'User',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                previewText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _reactToConversationMessage({
    required String messageId,
    required Offset globalPosition,
  }) async {
    if (_isReactionPickerOpen) return;
    if (_conversationId == null) return;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null || currentUserId.isEmpty) return;

    _isReactionPickerOpen = true;
    try {
      final selectedEmoji = await MessageReactionService.instance
          .getUserReaction(
            target: ReactionTarget.conversationMessage(
              conversationId: _conversationId!,
              messageId: messageId,
            ),
            userId: currentUserId,
          );

      final emoji = await showMessageReactionPicker(
        context: context,
        globalPosition: globalPosition,
        selectedEmoji: selectedEmoji,
      );
      if (emoji == null || emoji.isEmpty) return;

      await MessageReactionService.instance.toggleReaction(
        target: ReactionTarget.conversationMessage(
          conversationId: _conversationId!,
          messageId: messageId,
        ),
        userId: currentUserId,
        emoji: emoji,
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

  Future<void> _startRecording() async {
    if (!await _audioRecorder.hasPermission()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission needed')),
      );
      return;
    }

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/ptc_${DateTime.now().millisecondsSinceEpoch}.m4a';
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

  Future<void> _stopAndDeleteRecording() async {
    _recordingTimer?.cancel();
    await _audioRecorder.stop();

    if (_recordingPath != null) {
      try {
        final file = File(_recordingPath!);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {}
    }

    setState(() {
      _isRecording.value = false;
      _recordingPath = null;
      _recordingDuration.value = 0;
    });
  }

  Future<void> _stopAndSendRecording() async {
    if (!_isRecording.value) return;
    _recordingTimer?.cancel();

    final path = await _audioRecorder.stop();
    setState(() => _isRecording.value = false);

    if (path == null || _conversationId == null) return;

    try {
      final file = File(path);
      final fileName = 'audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final fileSize = await file.length();
      final pendingId = 'pending:${DateTime.now().millisecondsSinceEpoch}';

      // Create pending message
      final pendingMsg = {
        'messageId': pendingId,
        'text': '',
        'senderRole': 'parent',
        'createdAt': Timestamp.now(),
        'mediaMetadata': MediaMetadata(
          messageId: pendingId,
          r2Key: 'pending/$fileName',
          publicUrl: '',
          thumbnail: '',
          expiresAt: DateTime.now().add(const Duration(days: 365)),
          uploadedAt: DateTime.now(),
          fileSize: fileSize,
          mimeType: 'audio/aac',
          originalFileName: fileName,
        ),
      };

      setState(() {
        _pendingMessages.insert(0, pendingMsg);
        _progressNotifiers[pendingId] = ValueNotifier<double>(0);
        _localMediaPaths[pendingId] = file.path;
        _lastUploadPercent[pendingId] = -1;
      });

      // Upload audio
      final mediaMessage = await _mediaUploadService.uploadMedia(
        file: file,
        conversationId: _conversationId!,
        senderId: FirebaseAuth.instance.currentUser?.uid ?? '',
        senderRole: 'parent',
        mediaType: 'audio',
        onProgress: (progress) {
          if (!mounted) return;
          final percent = progress.toInt().clamp(0, 100);
          final last = _lastUploadPercent[pendingId] ?? -1;
          final shouldUpdate =
              last < 0 || percent == 100 || (percent - last) >= 5;
          if (!shouldUpdate) return;
          _lastUploadPercent[pendingId] = percent;
          _progressNotifiers[pendingId]?.value = percent.toDouble();
        },
      );

      // Send message with media
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

      await _chat.sendMessage(
        conversationId: _conversationId!,
        text: '',
        senderRole: 'parent',
        replyTo: _replyTo,
        mediaMetadata: {
          'messageId': metadata.messageId,
          'r2Key': metadata.r2Key,
          'publicUrl': metadata.publicUrl,
          'thumbnail': metadata.thumbnail,
          'expiresAt': metadata.expiresAt.toIso8601String(),
          'uploadedAt': metadata.uploadedAt.toIso8601String(),
          'fileSize': metadata.fileSize,
          'mimeType': metadata.mimeType,
          'originalFileName': metadata.originalFileName,
        },
      );

      // Cache uploaded media
      await _mediaRepository.cacheUploadedMedia(
        r2Key: r2Key,
        localPath: file.path,
        fileName: fileName,
        mimeType: 'audio/aac',
        fileSize: fileSize,
      );

      if (mounted) {
        setState(() {
          _pendingMessages.removeWhere((m) => m['messageId'] == pendingId);
          _progressNotifiers.remove(pendingId)?.dispose();
          _localMediaPaths.remove(pendingId);
          _lastUploadPercent.remove(pendingId);
        });
        _clearReplyTarget();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send audio: $e')));
      }
    }
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return WillPopScope(
      onWillPop: () async {
        if (_isReactionPickerOpen) {
          _isReactionPickerOpen = false;
          dismissMessageReactionPicker();
          return false;
        }
        return true;
      },
      child: Scaffold(
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
                    ? (widget.teacherAvatarUrl!.isNotEmpty
                          ? NetworkImage(widget.teacherAvatarUrl!)
                          : null)
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
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                      ),
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
                        // Show pending messages immediately while loading
                        if (snapshot.connectionState ==
                                ConnectionState.waiting &&
                            _pendingMessages.isEmpty) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        final docs = snapshot.data?.docs ?? [];
                        // After receiving messages, mark delivered for incoming ones
                        if (_conversationId != null && docs.isNotEmpty) {
                          WidgetsBinding.instance.addPostFrameCallback(
                            (_) => _batchUpdateIncoming(docs),
                          );
                        }

                        // Combine pending and Firestore messages
                        final allMessages = [
                          ..._pendingMessages,
                          ...docs.map((d) => d.data()..['_docId'] = d.id),
                        ];
                        _latestAllMessages = allMessages;

                        // Remove pending messages that now exist in Firestore
                        final pendingIdsToRemove = <String>[];
                        for (final pending in _pendingMessages) {
                          final pendingId = (pending['messageId'] as String)
                              .replaceFirst('pending:', '');
                          final existsInFirestore = docs.any(
                            (d) => d.id == pendingId,
                          );
                          if (existsInFirestore) {
                            pendingIdsToRemove.add(
                              pending['messageId'] as String,
                            );
                          }
                        }

                        if (pendingIdsToRemove.isNotEmpty) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            setState(() {
                              _pendingMessages.removeWhere(
                                (m) =>
                                    pendingIdsToRemove.contains(m['messageId']),
                              );
                              for (final id in pendingIdsToRemove) {
                                _progressNotifiers.remove(id)?.dispose();
                                _localMediaPaths.remove(id);
                                _lastUploadPercent.remove(id);
                              }
                            });
                          });
                        }

                        return ListView.separated(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemBuilder: (context, index) {
                            final msg = allMessages[index];
                            final messageId =
                                (msg['_docId'] ?? msg['messageId'] ?? '')
                                    .toString();
                            final isPendingMessage = messageId.startsWith(
                              'pending:',
                            );
                            final isParent = msg['senderRole'] == 'parent';
                            final deliveredToTeacher =
                                (msg['deliveredToTeacher'] ?? false) as bool;
                            final readByTeacher =
                                (msg['readByTeacher'] ?? false) as bool;
                            final mediaMetadata =
                                msg['mediaMetadata'] as MediaMetadata?;
                            final hasMedia = mediaMetadata != null;

                            return Align(
                              alignment: isParent
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: GestureDetector(
                                onLongPressStart: isPendingMessage
                                    ? null
                                    : (details) {
                                        _reactToConversationMessage(
                                          messageId: messageId,
                                          globalPosition:
                                              details.globalPosition,
                                        );
                                      },
                                onHorizontalDragEnd: (details) {
                                  if (isPendingMessage) return;
                                  final velocity = details.primaryVelocity ?? 0;
                                  if (velocity > 240) {
                                    _setReplyTarget(msg);
                                  }
                                },
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 360,
                                  ),
                                  child: Column(
                                    crossAxisAlignment: isParent
                                        ? CrossAxisAlignment.end
                                        : CrossAxisAlignment.start,
                                    children: [
                                      DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: hasMedia
                                              ? (msg['replyTo'] is Map
                                                    ? (isParent
                                                          ? const Color(
                                                              0xFF1362EB,
                                                            )
                                                          : (isDark
                                                                ? const Color(
                                                                    0xFF2A2A2A,
                                                                  )
                                                                : Colors
                                                                      .grey
                                                                      .shade200))
                                                    : Colors.transparent)
                                              : (isParent
                                                    ? const Color(0xFF1362EB)
                                                    : (isDark
                                                          ? const Color(
                                                              0xFF2A2A2A,
                                                            )
                                                          : Colors
                                                                .grey
                                                                .shade200)),
                                          borderRadius:
                                              BorderRadius.circular(
                                                12,
                                              ).copyWith(
                                                bottomRight: isParent
                                                    ? const Radius.circular(4)
                                                    : null,
                                                bottomLeft: !isParent
                                                    ? const Radius.circular(4)
                                                    : null,
                                              ),
                                        ),
                                        child: Padding(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: hasMedia ? 4 : 16,
                                            vertical: hasMedia ? 4 : 12,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (msg['replyTo'] is Map) ...[
                                                _buildInlineReplyHeader(
                                                  Map<String, dynamic>.from(
                                                    msg['replyTo'] as Map,
                                                  ),
                                                  isDark,
                                                ),
                                                const SizedBox(height: 6),
                                              ],
                                              // Media preview
                                              if (hasMedia) ...[
                                                Text(
                                                  'Media attachment: ${mediaMetadata.originalFileName ?? "file"}',
                                                  style: TextStyle(
                                                    color: isParent
                                                        ? Colors.white
                                                        : (isDark
                                                              ? Colors.white
                                                              : Colors.black87),
                                                    fontStyle: FontStyle.italic,
                                                  ),
                                                ),
                                                if ((msg['text'] ?? '')
                                                    .isNotEmpty)
                                                  const SizedBox(height: 8),
                                              ],
                                              // Text content
                                              if ((msg['text'] ?? '')
                                                  .isNotEmpty)
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
                                                  mainAxisSize:
                                                      MainAxisSize.min,
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
                                                          ? Colors
                                                                .lightBlueAccent
                                                          : Colors.white70,
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                      MessageReactionSummary(
                                        summary: _reactionSummaryForMap(msg),
                                        isMe: isParent,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemCount: allMessages.length,
                        );
                      },
                    ),
            ),
            SafeArea(
              top: false,
              minimum: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: ValueListenableBuilder<bool>(
                  valueListenable: _isRecording,
                  builder: (context, isRecording, _) {
                    if (isRecording) {
                      // Show recording UI
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF2A2A2A)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Row(
                          children: [
                            // Delete button
                            Material(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(26),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(26),
                                onTap: _stopAndDeleteRecording,
                                child: const SizedBox(
                                  width: 52,
                                  height: 52,
                                  child: Icon(
                                    Icons.delete,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Timer
                            Expanded(
                              child: ValueListenableBuilder<int>(
                                valueListenable: _recordingDuration,
                                builder: (context, duration, _) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      borderRadius: BorderRadius.circular(25),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          width: 12,
                                          height: 12,
                                          decoration: const BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _formatDuration(duration),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Send button
                            Material(
                              color: const Color(0xFF1362EB),
                              borderRadius: BorderRadius.circular(26),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(26),
                                onTap: _stopAndSendRecording,
                                child: const SizedBox(
                                  width: 52,
                                  height: 52,
                                  child: Icon(
                                    Icons.send,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    // Normal input UI
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_replyTo != null)
                          _buildReplyComposerPreview(isDark),
                        Row(
                          children: [
                            IconButton(
                              onPressed: _isUploading
                                  ? null
                                  : _showAttachmentSheet,
                              icon: Icon(
                                Icons.add_circle_outline,
                                color: _isUploading
                                    ? Colors.grey.shade500
                                    : (isDark
                                          ? Colors.grey.shade400
                                          : Colors.grey.shade700),
                              ),
                            ),
                            Expanded(
                              child: TextField(
                                controller: _controller,
                                onChanged: (_) => setState(() {}),
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
                                onPressed: _controller.text.trim().isNotEmpty
                                    ? () async {
                                        if (!_isOnline) {
                                          _showOfflineSnackBar();
                                          return;
                                        }
                                        final text = _controller.text.trim();
                                        if (text.isEmpty ||
                                            _conversationId == null) {
                                          return;
                                        }
                                        await _chat.sendMessage(
                                          conversationId: _conversationId!,
                                          text: text,
                                          senderRole: 'parent',
                                          replyTo: _replyTo,
                                        );
                                        _controller.clear();
                                        _clearReplyTarget();
                                      }
                                    : _startRecording,
                                icon: Icon(
                                  _controller.text.trim().isNotEmpty
                                      ? Icons.send
                                      : Icons.mic,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
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

  void _showAttachmentSheet() {
    if (!_isOnline) {
      _showOfflineSnackBar(isMedia: true);
      return;
    }
    showModernAttachmentSheet(
      context,
      onCameraTap: _pickAndSendCamera,
      onImageTap: _pickAndSendImage,
      onDocumentTap: _pickAndSendDocument,
      onAudioTap: _pickAndSendAudioFile,
      color: const Color(0xFF1362EB),
    );
  }

  Future<void> _pickAndSendCamera() async {
    if (_conversationId == null) return;

    try {
      final picked = await _imagePicker.pickImage(source: ImageSource.camera);
      if (picked == null) return;

      await _sendMediaFile(File(picked.path), 'image', 'image/jpeg');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to capture photo: $e')));
      }
    }
  }

  Future<void> _pickAndSendImage() async {
    if (_conversationId == null) return;

    try {
      final picked = await _imagePicker.pickMultiImage(limit: 5);
      if (picked.isEmpty) return;

      for (final xFile in picked) {
        await _sendMediaFile(File(xFile.path), 'image', 'image/jpeg');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to select images: $e')));
      }
    }
  }

  Future<void> _pickAndSendDocument() async {
    if (_conversationId == null) return;

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
        ],
      );

      if (result == null || result.files.isEmpty) return;

      final file = File(result.files.single.path!);
      final extension = file.path.split('.').last.toLowerCase();

      String mimeType = 'application/pdf';
      if (extension == 'doc') {
        mimeType = 'application/msword';
      } else if (extension == 'docx')
        mimeType =
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      else if (extension == 'xls')
        mimeType = 'application/vnd.ms-excel';
      else if (extension == 'xlsx')
        mimeType =
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      else if (extension == 'ppt')
        mimeType = 'application/vnd.ms-powerpoint';
      else if (extension == 'pptx')
        mimeType =
            'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      else if (extension == 'txt')
        mimeType = 'text/plain';

      await _sendMediaFile(file, 'document', mimeType);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to select document: $e')),
        );
      }
    }
  }

  Future<void> _pickAndSendAudioFile() async {
    if (_conversationId == null) return;

    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.audio);

      if (result == null || result.files.isEmpty) return;

      final file = File(result.files.single.path!);
      await _sendMediaFile(file, 'audio', 'audio/mpeg');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to select audio: $e')));
      }
    }
  }

  Future<void> _sendMediaFile(
    File file,
    String mediaType,
    String mimeType,
  ) async {
    if (_conversationId == null) return;

    setState(() => _isUploading = true);

    try {
      final fileName = file.path.split('/').last;
      final fileSize = await file.length();
      final pendingId = 'pending:${DateTime.now().millisecondsSinceEpoch}';

      // Create pending message
      final pendingMsg = {
        'messageId': pendingId,
        'text': '',
        'senderRole': 'parent',
        'createdAt': Timestamp.now(),
        'mediaMetadata': MediaMetadata(
          messageId: pendingId,
          r2Key: 'pending/$fileName',
          publicUrl: '',
          thumbnail: '',
          expiresAt: DateTime.now().add(const Duration(days: 365)),
          uploadedAt: DateTime.now(),
          fileSize: fileSize,
          mimeType: mimeType,
          originalFileName: fileName,
        ),
      };

      setState(() {
        _pendingMessages.insert(0, pendingMsg);
        _progressNotifiers[pendingId] = ValueNotifier<double>(0);
        _localMediaPaths[pendingId] = file.path;
        _lastUploadPercent[pendingId] = -1;
      });

      // Upload media
      final mediaMessage = await _mediaUploadService.uploadMedia(
        file: file,
        conversationId: _conversationId!,
        senderId: FirebaseAuth.instance.currentUser?.uid ?? '',
        senderRole: 'parent',
        mediaType: mediaType,
        onProgress: (progress) {
          if (!mounted) return;
          final percent = progress.toInt().clamp(0, 100);
          final last = _lastUploadPercent[pendingId] ?? -1;
          final shouldUpdate =
              last < 0 || percent == 100 || (percent - last) >= 5;
          if (!shouldUpdate) return;
          _lastUploadPercent[pendingId] = percent;
          _progressNotifiers[pendingId]?.value = percent.toDouble();
        },
      );

      // Send message with media
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

      await _chat.sendMessage(
        conversationId: _conversationId!,
        text: '',
        senderRole: 'parent',
        replyTo: _replyTo,
        mediaMetadata: {
          'messageId': metadata.messageId,
          'r2Key': metadata.r2Key,
          'publicUrl': metadata.publicUrl,
          'thumbnail': metadata.thumbnail,
          'expiresAt': metadata.expiresAt.toIso8601String(),
          'uploadedAt': metadata.uploadedAt.toIso8601String(),
          'fileSize': metadata.fileSize,
          'mimeType': metadata.mimeType,
          'originalFileName': metadata.originalFileName,
        },
      );

      // Cache uploaded media
      await _mediaRepository.cacheUploadedMedia(
        r2Key: r2Key,
        localPath: file.path,
        fileName: fileName,
        mimeType: mimeType,
        fileSize: fileSize,
      );

      if (mounted) {
        setState(() {
          _pendingMessages.removeWhere((m) => m['messageId'] == pendingId);
          _progressNotifiers.remove(pendingId)?.dispose();
          _localMediaPaths.remove(pendingId);
          _lastUploadPercent.remove(pendingId);
        });
        _clearReplyTarget();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send $mediaType: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }
}
