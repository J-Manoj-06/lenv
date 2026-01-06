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
import '../../config/cloudflare_config.dart';
import '../../models/community_message_model.dart';
import '../../models/media_metadata.dart';
import '../../providers/auth_provider.dart';
import '../../services/cloudflare_r2_service.dart';
import '../../services/local_cache_service.dart';
import '../../services/media_upload_service.dart';
import '../../services/parent_teacher_group_service.dart';
import '../../services/whatsapp_media_upload_service.dart';
import '../../widgets/media_preview_card.dart';
import '../../widgets/modern_attachment_sheet.dart';
import '../common/announcement_view_screen.dart';

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
    with AutomaticKeepAliveClientMixin {
  static const Color parentGreen = Color(0xFF14A670);
  static const Color teacherViolet = Color(0xFF6366F1);
  static const Color backgroundDark = Color(0xFF101214);
  static const Color bubbleDark = Color(0xFF1A1C20);

  // ✅ OPTIMIZATION: Pagination state
  static const int _messagesPerPage = 50;
  bool _hasMoreMessages = true;
  bool _isLoadingMore = false;
  bool _isRestoringScroll = false;
  DocumentSnapshot? _lastDocument;
  final List<CommunityMessageModel> _olderMessages = [];

  final ParentTeacherGroupService _service = ParentTeacherGroupService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();
  late final MediaUploadService _mediaUploadService;
  bool _isUploading = false;
  bool _isRecording = false;
  String? _recordingPath;
  final ValueNotifier<int> _recordingDuration = ValueNotifier<int>(0);
  Timer? _recordingTimer;
  final List<CommunityMessageModel> _pendingMessages = [];
  final Map<String, ValueNotifier<double>> _pendingUploadNotifiers = {};
  // Tracks local file paths for sent media (by messageId or r2Key) so we can display without re-downloading.
  final Map<String, String> _localSenderMediaPaths = {};
  // Throttle progress updates to avoid rebuilding the entire list too frequently
  final Map<String, int> _lastUploadPercent = {};

  // Selection mode for multi-delete (using ValueNotifier to avoid full-page rebuilds)
  bool _selectionMode = false;
  final ValueNotifier<Set<String>> _selectedMessages =
      ValueNotifier<Set<String>>({});

  @override
  bool get wantKeepAlive => true; // ✅ Prevent rebuild when switching tabs

  @override
  void dispose() {
    for (final notifier in _pendingUploadNotifiers.values) {
      notifier.dispose();
    }
    _selectedMessages.dispose();
    _controller.dispose();
    _scrollController.dispose();
    _recordingTimer?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    // ✅ OPTIMIZATION: Setup scroll listener for pagination
    _scrollController.addListener(_onScroll);

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
  }

  String _formatTime(DateTime dateTime) {
    return DateFormat('h:mm a').format(dateTime);
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
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

  /// ✅ OPTIMIZATION: Scroll listener for pagination
  void _onScroll() {
    if (!_scrollController.hasClients || _isLoadingMore || !_hasMoreMessages || _isRestoringScroll) {
      return;
    }

    // Load more when user scrolls to 95% from the top (bottom in reverse list)
    // Higher threshold prevents premature loading when just scrolling up a bit
    final scrollPosition = _scrollController.position;
    if (scrollPosition.pixels >= scrollPosition.maxScrollExtent * 0.95) {
      _loadMoreMessages();
    }
  }

  /// ✅ OPTIMIZATION: Load older messages with pagination
  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMoreMessages) return;

    _isLoadingMore = true;

    // Save current scroll position before loading
    final savedPosition = _scrollController.hasClients 
        ? _scrollController.position.pixels 
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
        _olderMessages.addAll(newMessages);
        _lastDocument = newMessages.last.documentSnapshot;
        
        // Single setState after all data is ready
        setState(() {});
        
        // Restore scroll position after rebuild, prevent scroll listener from interfering
        _isRestoringScroll = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients && savedPosition > 0) {
            _scrollController.jumpTo(savedPosition);
          }
          // Re-enable scroll listener after a short delay
          Future.delayed(const Duration(milliseconds: 150), () {
            _isRestoringScroll = false;
          });
        });
      } else {
        _hasMoreMessages = false;
      }
    } catch (e) {
      print('❌ Error loading more messages: $e');
    } finally {
      _isLoadingMore = false;
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
      backgroundColor: isDark ? backgroundDark : const Color(0xFFF6F7F8),
      appBar: AppBar(
        backgroundColor: isDark ? bubbleDark : Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: Icon(
            _selectionMode ? Icons.close : Icons.arrow_back_ios_new_rounded,
          ),
          color: isDark ? Colors.white : Colors.black,
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
                      color: isDark ? Colors.white : Colors.black,
                      fontWeight: FontWeight.w600,
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
                      color: isDark ? Colors.white : Colors.black,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${widget.className ?? ''}${widget.section != null ? ' - ${widget.section}' : ''} · ${widget.childName}',
                    style: TextStyle(
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      fontSize: 12,
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
                      onPressed: selectedSet.length < 2
                          ? null
                          : _deleteSelectedMessages,
                      tooltip: selectedSet.length < 2
                          ? 'Select at least 2 messages'
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
              stream: _service.getMessagesStream(widget.groupId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(color: primaryColor),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error loading messages',
                      style: TextStyle(
                        color: isDark ? Colors.red[200] : Colors.red[600],
                      ),
                    ),
                  );
                }

                final firestoreMessages = snapshot.data ?? [];
                // ✅ OPTIMIZATION: Combine recent stream messages + older paginated messages
                final allMessages = [
                  ..._pendingMessages,
                  ...firestoreMessages,
                  ..._olderMessages,
                ];

                // Update last document from stream if available
                if (firestoreMessages.isNotEmpty && _lastDocument == null) {
                  _lastDocument = firestoreMessages.last.documentSnapshot;
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

                return ListView.builder(
                  key: const PageStorageKey('parent_group_chat_list'),
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: allMessages.length,
                  itemBuilder: (context, index) {
                    final msg = allMessages[index];
                    final isCurrentUser = msg.senderId == currentUserId;
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
                            ? _localSenderMediaPaths[msg.mediaMetadata!.r2Key]
                            : null);

                    if (msg.type == 'announcement') {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Center(
                          child: InkWell(
                            onTap: () {
                              final role = (msg.senderRole).toLowerCase();
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
                                color: isDark ? Colors.white70 : Colors.black54,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      );
                    }

                    // Skip deleted messages
                    if (msg.isDeleted) {
                      return const SizedBox.shrink();
                    }

                    return ValueListenableBuilder<Set<String>>(
                      valueListenable: _selectedMessages,
                      builder: (context, selectedSet, _) {
                        final isSelected = selectedSet.contains(msg.messageId);

                        return Padding(
                          key: ValueKey(msg.messageId),
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            mainAxisAlignment: isCurrentUser
                                ? MainAxisAlignment.end
                                : MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Flexible(
                                child: GestureDetector(
                                  onLongPress: () {
                                    if (!_selectionMode &&
                                        !isPending &&
                                        isCurrentUser) {
                                      _selectionMode = true;
                                      _selectedMessages.value = {msg.messageId};
                                    }
                                  },
                                  onTap: _selectionMode && isCurrentUser
                                      ? () {
                                          if (!isPending) {
                                            final selectedSet =
                                                _selectedMessages.value;
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
                                          }
                                        }
                                      : null,
                                  child: Column(
                                    crossAxisAlignment: isCurrentUser
                                        ? CrossAxisAlignment.end
                                        : CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
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
                                            color: isSelected
                                                ? primaryColor.withOpacity(0.2)
                                                : bubbleColor,
                                            border: hasMedia
                                                ? Border.all(
                                                    color: isSelected
                                                        ? primaryColor
                                                              .withOpacity(0.8)
                                                        : primaryColor,
                                                    width: isSelected
                                                        ? 2.5
                                                        : 1.5,
                                                  )
                                                : (isSelected
                                                      ? Border.all(
                                                          color: primaryColor,
                                                          width: 2.5,
                                                        )
                                                      : null),
                                            borderRadius:
                                                BorderRadius.circular(
                                                  12,
                                                ).copyWith(
                                                  bottomRight: isCurrentUser
                                                      ? const Radius.circular(4)
                                                      : null,
                                                  bottomLeft: !isCurrentUser
                                                      ? const Radius.circular(4)
                                                      : null,
                                                ),
                                          ),
                                          child: Padding(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: hasMedia ? 4 : 12,
                                              vertical: hasMedia ? 4 : 8,
                                            ),
                                            child: Column(
                                              crossAxisAlignment: isCurrentUser
                                                  ? CrossAxisAlignment.end
                                                  : CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (!isCurrentUser)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          bottom: 3,
                                                        ),
                                                    child: Text(
                                                      msg.senderName,
                                                      style: TextStyle(
                                                        color: isDark
                                                            ? primaryColor
                                                            : primaryColor
                                                                  .withOpacity(
                                                                    0.8,
                                                                  ),
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ),
                                                if (msg.mediaMetadata !=
                                                    null) ...[
                                                  RepaintBoundary(
                                                    child:
                                                        progressNotifier != null
                                                        ? ValueListenableBuilder<
                                                            double
                                                          >(
                                                            valueListenable:
                                                                progressNotifier,
                                                            builder: (_, value, __) {
                                                              final progress =
                                                                  ((value / 100)
                                                                          .clamp(
                                                                            0.0,
                                                                            1.0,
                                                                          ))
                                                                      .toDouble();
                                                              return MediaPreviewCard(
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
                                                                uploading: true,
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
                                                            isMe: isCurrentUser,
                                                            uploading:
                                                                isPending,
                                                            uploadProgress:
                                                                null,
                                                            selectionMode:
                                                                _selectionMode,
                                                          ),
                                                  ),
                                                  if (msg.content.isNotEmpty)
                                                    const SizedBox(height: 8),
                                                ],
                                                if (msg.content.isNotEmpty)
                                                  Text(
                                                    msg.content,
                                                    style: TextStyle(
                                                      color: textColor,
                                                      fontSize: 15,
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
                                          final updated = {...selectedSet};
                                          updated.remove(msg.messageId);
                                          _selectedMessages.value = updated;
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
                    );
                  },
                );
              },
            ),
          ),
          _buildMessageInput(isDark),
        ],
      ),
    );
  }

  Widget _buildMessageInput(bool isDark) {
    final primaryColor = widget.senderRole == 'teacher'
        ? teacherViolet
        : parentGreen;
    final hasText = _controller.text.trim().isNotEmpty;

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
    final iconColor = isDark
        ? const Color(0xFF9A95CC) // Soft muted violet
        : const Color(0xFF6C63FF);
    final iconDisabledColor = isDark
        ? const Color(0xFF3A3A3C)
        : const Color(0xFFBBBBBB);

    return SafeArea(
      top: false,
      child: Container(
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
                    // Attachment - inside input, left side
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: GestureDetector(
                        onTap: _isUploading ? null : _showAttachmentSheet,
                        child: Icon(
                          Icons.attach_file_rounded,
                          color: _isUploading ? iconDisabledColor : iconColor,
                          size: 23,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Text input - primary focus
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        child: _isRecording
                            ? _buildRecordingBar(isDark, primaryColor)
                            : TextField(
                                key: const ValueKey('input'),
                                controller: _controller,
                                minLines: 1,
                                maxLines: 4,
                                cursorColor: primaryColor,
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
                                keyboardType: TextInputType.multiline,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                onChanged: (_) => setState(() {}),
                                readOnly: _isRecording,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Mic/Send button - balanced size, outside input
            GestureDetector(
              onTap: _isRecording
                  ? _stopAndSendRecording
                  : (hasText ? _sendMessage : _startRecording),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _isRecording
                      ? primaryColor
                      : (hasText
                            ? primaryColor
                            : primaryColor.withOpacity(0.85)),
                  shape: BoxShape.circle,
                  boxShadow: isDark
                      ? [
                          BoxShadow(
                            color: primaryColor.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: primaryColor.withOpacity(0.25),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                ),
                child: Icon(
                  _isRecording
                      ? Icons.send_rounded
                      : (hasText ? Icons.send_rounded : Icons.mic),
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingBar(bool isDark, Color primaryColor) {
    return Container(
      key: const ValueKey('recording'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: primaryColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: primaryColor.withOpacity(isDark ? 0.4 : 0.6),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              color: Colors.redAccent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.redAccent.withOpacity(0.5),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          ValueListenableBuilder<int>(
            valueListenable: _recordingDuration,
            builder: (context, duration, _) {
              return Text(
                _formatDuration(duration),
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              );
            },
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: _deleteRecording,
            splashRadius: 22,
          ),
        ],
      ),
    );
  }

  void _showAttachmentSheet() {
    showModernAttachmentSheet(
      context,
      onImageTap: _pickAndSendImage,
      onPdfTap: _pickAndSendPDF,
      onAudioTap: _pickAndSendAudioFile,
    );
  }

  Future<void> _pickAndSendImage() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.currentUser;
    if (user == null) return;

    try {
      final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
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
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
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
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send image: $e')));
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
        allowedExtensions: ['pdf'],
      );
      if (result == null || result.files.single.path == null) return;

      final file = File(result.files.single.path!);
      final pendingId = 'pending:${DateTime.now().millisecondsSinceEpoch}';
      final fileName = file.path.split('/').last;
      final fileSize = await file.length();
      final pendingMetadata = MediaMetadata(
        messageId: pendingId,
        r2Key: 'pending/$fileName',
        publicUrl: '',
        thumbnail: '',
        expiresAt: DateTime.now().add(const Duration(days: 365)),
        uploadedAt: DateTime.now(),
        fileSize: fileSize,
        mimeType: 'application/pdf',
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

      if (mounted) {
        setState(() {
          _pendingMessages.removeWhere((m) => m.messageId == pendingId);
          _pendingUploadNotifiers.remove(pendingId)?.dispose();
          _lastUploadPercent.remove(pendingId);
        });
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
        _pendingUploadNotifiers[pendingId] = ValueNotifier<double>(0);
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

      if (mounted) {
        setState(() {
          _pendingMessages.removeWhere((m) => m.messageId == pendingId);
          _pendingUploadNotifiers.remove(pendingId)?.dispose();
          _lastUploadPercent.remove(pendingId);
        });
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
      _isRecording = true;
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
    if (!_isRecording) return;
    _recordingTimer?.cancel();

    final path = await _audioRecorder.stop();
    setState(() => _isRecording = false);

    if (path == null) return;
    final file = File(path);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.currentUser;
    if (user == null) return;

    try {
      setState(() => _isUploading = true);
      final mediaMessage = await _mediaUploadService.uploadMedia(
        file: file,
        conversationId: widget.groupId,
        senderId: user.uid,
        senderRole: widget.senderRole,
        mediaType: 'community',
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
    } catch (e) {
      if (mounted) {
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
    if (_isRecording) {
      try {
        await _audioRecorder.stop();
      } catch (_) {}
    }
    setState(() {
      _isRecording = false;
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
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ParentGroupMessageSearchScreen(
          groupId: widget.groupId,
          messagingService: _service,
          currentUserId: currentUser.uid,
        ),
      ),
    );
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
      print('Search error: $e');
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
    if (m.type == 'pdf' || m.type == 'file')
      return Icons.insert_drive_file_outlined;
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
          final cachedMedia = await LocalCacheService().getCachedMediaMetadata(
            mediaId,
          );
          if (cachedMedia != null && cachedMedia['localPath'] != null) {
            final localFile = File(cachedMedia['localPath']);
            if (await localFile.exists()) {
              localPath = cachedMedia['localPath'];
            }
          }
        }
      } catch (e) {
        print('Cache check failed: $e');
      }

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
      print('Error showing image: $e');
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
          final cachedMedia = await LocalCacheService().getCachedMediaMetadata(
            mediaId,
          );
          if (cachedMedia != null && cachedMedia['localPath'] != null) {
            final localFile = File(cachedMedia['localPath']);
            if (await localFile.exists()) {
              audioUrl = cachedMedia['localPath'];
            }
          }
        }
      } catch (e) {
        print('Cache check failed: $e');
      }

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
      final filePath = '${tempDir.path}/$timestamp\_$finalFileName';

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
  Duration _duration = Duration.zero;
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
