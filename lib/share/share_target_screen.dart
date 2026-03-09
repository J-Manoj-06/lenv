import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../models/user_model.dart';
import '../models/group_chat_message.dart';
import '../models/community_model.dart';
import '../share/incoming_share_data.dart';
import '../share/share_controller.dart';
import '../services/community_service.dart';
import '../services/group_messaging_service.dart';
import '../services/background_upload_service.dart';
import '../screens/messages/teacher_group_chat_page.dart';
import '../screens/messages/community_chat_page.dart';
import '../core/constants/app_colors.dart';

// ---------------------------------------------------------------------------
// Section model
// ---------------------------------------------------------------------------

class _Section {
  final String title;
  final List<ShareDestination> destinations;
  _Section({required this.title, required this.destinations});
}

// ---------------------------------------------------------------------------
// Main screen
// ---------------------------------------------------------------------------

/// Comprehensive share target screen for all roles.
/// - Teacher  : Announcement (top, image-only) => Communities => Groups => Staff Room
/// - Student  : Communities => Groups
/// - Parent   : Teacher Chats
/// - Institute: Staff Room => Announcement
class ShareTargetScreen extends StatefulWidget {
  final IncomingShareData shareData;

  const ShareTargetScreen({super.key, required this.shareData});

  @override
  State<ShareTargetScreen> createState() => _ShareTargetScreenState();
}

class _ShareTargetScreenState extends State<ShareTargetScreen> {
  final TextEditingController _searchController = TextEditingController();

  List<_Section> _allSections = [];
  List<_Section> _filteredSections = [];
  bool _isLoading = true;
  String _searchQuery = '';

  Color _roleColor = AppColors.primary;

  /// Whether the shared content is an image (enables Announcement).
  bool get _isImageContent => widget.shareData.type == ShareContentType.image;

  @override
  void initState() {
    super.initState();
    _loadDestinations();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
      _applySearch();
    });
  }

  // -------------------------------------------------------------------------
  // Destination loading
  // -------------------------------------------------------------------------

  Future<void> _loadDestinations() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;
      if (currentUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      _roleColor = _getRoleColor(currentUser.role);

      List<_Section> sections = [];

      switch (currentUser.role) {
        case UserRole.student:
          sections = await _buildStudentSections(currentUser);
          break;
        case UserRole.teacher:
          sections = await _buildTeacherSections(currentUser);
          break;
        case UserRole.parent:
          sections = await _buildParentSections(currentUser);
          break;
        case UserRole.institute:
          sections = await _buildInstituteSections(currentUser);
          break;
      }

      if (mounted) {
        setState(() {
          _allSections = sections;
          _filteredSections = sections;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('ShareTargetScreen: Error loading destinations: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---- Teacher ----

  Future<List<_Section>> _buildTeacherSections(UserModel currentUser) async {
    final List<_Section> sections = [];

    // 1. Announcement always at top
    sections.add(
      _Section(
        title: 'Announcement',
        destinations: [
          ShareDestination(
            id: 'announcement_${currentUser.uid}',
            name: 'Create Announcement',
            type: DestinationType.announcement,
            icon: Icons.campaign_rounded,
            subtitle: 'Broadcast to all members',
            data: {'teacherId': currentUser.uid},
          ),
        ],
      ),
    );

    // 2. Communities
    try {
      final communityService = CommunityService();
      final communities = await communityService.getMyCommunitiesForRole(
        userId: currentUser.uid,
        role: 'teacher',
      );
      if (communities.isNotEmpty) {
        sections.add(
          _Section(
            title: 'Communities',
            destinations: communities
                .map(
                  (c) => ShareDestination(
                    id: c.id,
                    name: c.name,
                    type: DestinationType.community,
                    icon: Icons.groups_rounded,
                    subtitle: '${c.memberCount} members',
                    data: c,
                  ),
                )
                .toList(),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error loading teacher communities: $e');
    }

    // 3. Groups  –  query all classes and match via subjectTeachers map
    final List<ShareDestination> groups = [];
    try {
      final classesSnapshot = await FirebaseFirestore.instance
          .collection('classes')
          .get();

      for (final classDoc in classesSnapshot.docs) {
        final classData = classDoc.data();
        final className = classData['className'] as String? ?? '';
        final section = classData['section'] as String? ?? '';
        final subjectTeachers =
            classData['subjectTeachers'] as Map<String, dynamic>?;

        if (subjectTeachers == null) continue;

        subjectTeachers.forEach((subject, teacherData) {
          if (teacherData is Map<String, dynamic>) {
            final assignedId = teacherData['teacherId'] as String?;
            if (assignedId == currentUser.uid) {
              // subjectId must match the Firestore doc ID convention:
              // subject.toLowerCase().replaceAll(' ', '_')
              final subjectDocId = subject.toLowerCase().replaceAll(' ', '_');
              groups.add(
                ShareDestination(
                  id: '${classDoc.id}_$subjectDocId',
                  name: '$subject - Class $className $section',
                  type: DestinationType.groupChat,
                  icon: Icons.class_rounded,
                  subtitle: 'Class Group Chat',
                  data: {
                    'classId': classDoc.id,
                    'subjectId': subjectDocId,
                    'subjectName': subject, // original-case for navigation
                    'className': className,
                    'section': section,
                  },
                ),
              );
            }
          }
        });
      }

      // Sort by class then subject
      groups.sort((a, b) {
        final aName = a.name;
        final bName = b.name;
        return aName.compareTo(bName);
      });
    } catch (e) {
      debugPrint('Error loading teacher groups: $e');
    }
    if (groups.isNotEmpty) {
      sections.add(_Section(title: 'Groups', destinations: groups));
    }

    // 4. Staff Room
    if (currentUser.instituteId != null) {
      sections.add(
        _Section(
          title: 'Staff Room',
          destinations: [
            ShareDestination(
              id: 'staff_room_${currentUser.instituteId}',
              name: 'Staff Room',
              type: DestinationType.staffRoom,
              icon: Icons.meeting_room_rounded,
              subtitle: 'Teacher communication',
              data: {'instituteId': currentUser.instituteId},
            ),
          ],
        ),
      );
    }

    return sections;
  }

  // ---- Student ----

  Future<List<_Section>> _buildStudentSections(UserModel currentUser) async {
    final List<_Section> sections = [];

    // Communities
    try {
      final communityService = CommunityService();
      final communities = await communityService.getMyCommunitiesForRole(
        userId: currentUser.uid,
        role: 'student',
      );
      if (communities.isNotEmpty) {
        sections.add(
          _Section(
            title: 'Communities',
            destinations: communities
                .map(
                  (c) => ShareDestination(
                    id: c.id,
                    name: c.name,
                    type: DestinationType.community,
                    icon: Icons.groups_rounded,
                    subtitle: '${c.memberCount} members',
                    data: c,
                  ),
                )
                .toList(),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error loading student communities: $e');
    }

    // Class Groups
    final List<ShareDestination> groups = [];
    try {
      final messagingService = GroupMessagingService();
      final classId = await messagingService.getStudentClassId(currentUser.uid);
      if (classId != null) {
        final subjects = await messagingService.getClassSubjects(classId);
        for (final subject in subjects) {
          // Keep same doc ID convention as TeacherGroupChatPage
          final subjectDocId = subject.id.toLowerCase().replaceAll(' ', '_');
          groups.add(
            ShareDestination(
              id: '${classId}_$subjectDocId',
              name: subject.name,
              type: DestinationType.groupChat,
              icon: Icons.school_rounded,
              subtitle: 'Class Group Chat',
              data: {
                'classId': classId,
                'subjectId': subjectDocId,
                'subjectName': subject.name, // for navigation
                'subject': subject,
              },
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error loading student groups: $e');
    }
    if (groups.isNotEmpty) {
      sections.add(_Section(title: 'Groups', destinations: groups));
    }

    return sections;
  }

  // ---- Parent ----

  Future<List<_Section>> _buildParentSections(UserModel currentUser) async {
    final List<ShareDestination> chats = [];
    try {
      final parentDoc = await FirebaseFirestore.instance
          .collection('parents')
          .doc(currentUser.uid)
          .get();

      if (parentDoc.exists) {
        final parentData = parentDoc.data();
        final linkedStudents =
            parentData?['linkedStudents'] as List<dynamic>? ?? [];
        final Map<String, ShareDestination> unique = {};

        for (final studentId in linkedStudents) {
          if (studentId is String) {
            final studentDoc = await FirebaseFirestore.instance
                .collection('students')
                .doc(studentId)
                .get();
            if (studentDoc.exists) {
              final studentData = studentDoc.data();
              final linkedTeachers =
                  studentData?['linkedTeachers'] as List<dynamic>? ?? [];
              for (final td in linkedTeachers) {
                if (td is Map<String, dynamic>) {
                  final teacherId = td['teacherId'] ?? '';
                  final teacherName = td['teacherName'] ?? 'Teacher';
                  final subject = td['subject'] ?? '';
                  unique[teacherId] = ShareDestination(
                    id: 'teacher_$teacherId',
                    name: teacherName,
                    type: DestinationType.individualChat,
                    icon: Icons.person_rounded,
                    subtitle: subject,
                    data: {
                      'teacherId': teacherId,
                      'teacherName': teacherName,
                      'studentId': studentId,
                    },
                  );
                }
              }
            }
          }
        }
        chats.addAll(unique.values);
      }
    } catch (e) {
      debugPrint('Error loading parent destinations: $e');
    }

    if (chats.isNotEmpty) {
      return [_Section(title: 'Teacher Chats', destinations: chats)];
    }
    return [];
  }

  // ---- Institute ----

  Future<List<_Section>> _buildInstituteSections(UserModel currentUser) async {
    final List<_Section> sections = [];

    if (currentUser.instituteId != null) {
      sections.add(
        _Section(
          title: 'Staff Room',
          destinations: [
            ShareDestination(
              id: 'staff_room_${currentUser.instituteId}',
              name: 'Staff Room',
              type: DestinationType.staffRoom,
              icon: Icons.business_rounded,
              subtitle: 'All staff members',
              data: {'instituteId': currentUser.instituteId},
            ),
          ],
        ),
      );
    }

    sections.add(
      _Section(
        title: 'Announcement',
        destinations: [
          ShareDestination(
            id: 'announcement_${currentUser.uid}',
            name: 'Create Announcement',
            type: DestinationType.announcement,
            icon: Icons.campaign_rounded,
            subtitle: 'Share as institute announcement',
            data: {'principalId': currentUser.uid},
          ),
        ],
      ),
    );

    return sections;
  }

  // -------------------------------------------------------------------------
  // Search
  // -------------------------------------------------------------------------

  void _applySearch() {
    if (_searchQuery.isEmpty) {
      _filteredSections = _allSections;
      return;
    }
    _filteredSections = _allSections
        .map((section) {
          final matched = section.destinations
              .where(
                (d) =>
                    d.name.toLowerCase().contains(_searchQuery) ||
                    d.subtitle.toLowerCase().contains(_searchQuery),
              )
              .toList();
          return matched.isEmpty
              ? null
              : _Section(title: section.title, destinations: matched);
        })
        .whereType<_Section>()
        .toList();
  }

  // -------------------------------------------------------------------------
  // Posting logic
  // -------------------------------------------------------------------------

  void _onDestinationTap(ShareDestination destination) {
    if (destination.type == DestinationType.announcement && !_isImageContent) {
      // Announcement is disabled for non-image content
      return;
    }
    _showShareConfirmation(destination);
  }

  void _showShareConfirmation(ShareDestination destination) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _ConfirmBottomSheet(
        destination: destination,
        isDark: Theme.of(context).brightness == Brightness.dark,
        roleColor: _roleColor,
        onConfirm: () => _shareToDestination(destination),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Share dispatch — background, non-blocking
  // ---------------------------------------------------------------------------

  /// Entry point called when user confirms sending to a destination.
  /// No blocking dialog; upload is queued in background, UI navigates immediately.
  Future<void> _shareToDestination(ShareDestination destination) async {
    final shareController = Provider.of<ShareController>(
      context,
      listen: false,
    );
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;
    if (currentUser == null) return;

    shareController.setProcessing(true);

    try {
      final senderId = currentUser.uid;
      final senderName = currentUser.name;
      final senderRole = currentUser.role.toString().split('.').last;
      final hasFiles = widget.shareData.hasFiles;
      final text = widget.shareData.hasText
          ? (widget.shareData.text ?? '')
          : '';

      switch (destination.type) {
        case DestinationType.groupChat:
          await _sendToGroupChat(
            destination: destination,
            hasFiles: hasFiles,
            text: text,
            senderId: senderId,
            senderName: senderName,
            senderRole: senderRole,
          );
          break;
        case DestinationType.community:
          await _sendToCommunity(
            destination: destination,
            hasFiles: hasFiles,
            text: text,
            senderId: senderId,
            senderName: senderName,
            senderRole: senderRole,
          );
          break;
        case DestinationType.staffRoom:
          await _sendToStaffRoom(
            destination: destination,
            hasFiles: hasFiles,
            text: text,
            senderId: senderId,
            senderName: senderName,
            senderRole: senderRole,
          );
          break;
        case DestinationType.individualChat:
          await _sendToIndividualChat(
            destination: destination,
            hasFiles: hasFiles,
            text: text,
            senderId: senderId,
            senderName: senderName,
            senderRole: senderRole,
            currentUser: currentUser,
          );
          break;
        case DestinationType.announcement:
          await _sendAsAnnouncement(
            destination: destination,
            senderId: senderId,
            senderName: senderName,
            senderRole: senderRole,
          );
          break;
      }

      if (!mounted) return;
      shareController.clearShareData();
      _navigateAfterSend(destination);
    } catch (e) {
      shareController.setProcessing(false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to share: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ---- group chat ----

  Future<void> _sendToGroupChat({
    required ShareDestination destination,
    required bool hasFiles,
    required String text,
    required String senderId,
    required String senderName,
    required String senderRole,
  }) async {
    final data = destination.data as Map<String, dynamic>;
    final classId = data['classId'] as String;
    final subjectId = data['subjectId'] as String;

    if (hasFiles) {
      // Background upload — returns immediately, upload runs in background
      await BackgroundUploadService().queueUpload(
        file: File(widget.shareData.files.first),
        conversationId: '${classId}_$subjectId',
        senderId: senderId,
        senderRole: senderRole,
        mediaType: 'image',
        chatType: 'group',
        senderName: senderName,
      );
    } else {
      // Text-only: use correct GroupChatMessage schema
      final message = GroupChatMessage(
        id: '',
        senderId: senderId,
        senderName: senderName,
        message: text, // Note: field is 'message', NOT 'text'
        imageUrl: null,
        mediaMetadata: null,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      await GroupMessagingService().sendGroupMessage(
        classId,
        subjectId,
        message,
      );
    }
  }

  // ---- community ----

  Future<void> _sendToCommunity({
    required ShareDestination destination,
    required bool hasFiles,
    required String text,
    required String senderId,
    required String senderName,
    required String senderRole,
  }) async {
    final communityId = destination.id;

    if (hasFiles) {
      // Background upload for community
      await BackgroundUploadService().queueUpload(
        file: File(widget.shareData.files.first),
        conversationId: communityId,
        senderId: senderId,
        senderRole: senderRole,
        mediaType: 'image',
        chatType: 'community',
        senderName: senderName,
      );
    } else {
      // Text-only via CommunityService
      await CommunityService().sendMessage(
        communityId: communityId,
        senderId: senderId,
        senderName: senderName,
        senderRole: senderRole,
        content: text,
        mediaType: 'text',
      );
    }
  }

  // ---- staff room ----

  Future<void> _sendToStaffRoom({
    required ShareDestination destination,
    required bool hasFiles,
    required String text,
    required String senderId,
    required String senderName,
    required String senderRole,
  }) async {
    final data = destination.data as Map<String, dynamic>;
    final instituteId = data['instituteId'] as String;

    if (hasFiles) {
      // Background upload for staff room
      await BackgroundUploadService().queueUpload(
        file: File(widget.shareData.files.first),
        conversationId: instituteId,
        senderId: senderId,
        senderRole: senderRole,
        mediaType: 'image',
        chatType: 'staff_room',
        senderName: senderName,
      );
    } else {
      // Text-only: write directly to staff_rooms collection
      await FirebaseFirestore.instance
          .collection('staff_rooms')
          .doc(instituteId)
          .collection('messages')
          .add({
            'text': text,
            'senderId': senderId,
            'senderName': senderName,
            'senderRole': senderRole,
            'timestamp': FieldValue.serverTimestamp(),
            'createdAt': DateTime.now().millisecondsSinceEpoch,
          });
    }
  }

  // ---- individual (parent ↔ teacher) ----

  Future<void> _sendToIndividualChat({
    required ShareDestination destination,
    required bool hasFiles,
    required String text,
    required String senderId,
    required String senderName,
    required String senderRole,
    required UserModel currentUser,
  }) async {
    final data = destination.data as Map<String, dynamic>;
    final teacherId = data['teacherId'] as String;
    final conversationId = '${currentUser.uid}_$teacherId';

    if (hasFiles) {
      await BackgroundUploadService().queueUpload(
        file: File(widget.shareData.files.first),
        conversationId: conversationId,
        senderId: senderId,
        senderRole: senderRole,
        mediaType: 'image',
        chatType: 'direct',
        senderName: senderName,
      );
    } else {
      await FirebaseFirestore.instance
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .add({
            'text': text,
            'senderId': senderId,
            'senderName': senderName,
            'senderRole': senderRole,
            'timestamp': FieldValue.serverTimestamp(),
            'createdAt': DateTime.now().millisecondsSinceEpoch,
          });

      await FirebaseFirestore.instance
          .collection('conversations')
          .doc(conversationId)
          .set({
            'participants': [currentUser.uid, teacherId],
            'lastMessage': text,
            'lastMessageTime': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    }
  }

  // ---- announcement ----

  Future<void> _sendAsAnnouncement({
    required ShareDestination destination,
    required String senderId,
    required String senderName,
    required String senderRole,
  }) async {
    if (!widget.shareData.hasFiles) return;

    // Upload image first, then create announcement document
    await BackgroundUploadService().queueUpload(
      file: File(widget.shareData.files.first),
      conversationId: 'announcements_$senderId',
      senderId: senderId,
      senderRole: senderRole,
      mediaType: 'image',
      chatType: 'announcement',
      senderName: senderName,
    );
  }

  // ---------------------------------------------------------------------------
  // Smart navigation after send
  // ---------------------------------------------------------------------------

  /// Navigates to the destination chat after queuing the send, or pops to dashboard.
  /// For group/community chats, replaces the share screen with the destination chat
  /// so the back button returns to the dashboard.
  void _navigateAfterSend(ShareDestination destination) {
    if (!mounted) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;

    // Show "sending" snackbar BEFORE navigating — ScaffoldMessenger persists
    // above the Navigator so the snackbar appears on the next screen automatically
    final isMediaMessage = widget.shareData.hasFiles;
    final label = isMediaMessage ? 'Sending image' : 'Sending message';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label to ${destination.name}...'),
        backgroundColor: Colors.green.shade600,
        duration: const Duration(seconds: 3),
      ),
    );

    switch (destination.type) {
      case DestinationType.groupChat:
        final data = destination.data as Map<String, dynamic>;
        final classId = data['classId'] as String;
        final subjectId = data['subjectId'] as String;
        final subjectName =
            (data['subjectName'] as String?) ??
            destination.name.split(' - ').first;
        final className = data['className'] as String?;
        final section = data['section'] as String?;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => TeacherGroupChatPage(
              classId: classId,
              subjectId: subjectId,
              subjectName: subjectName,
              teacherName: currentUser?.name ?? '',
              icon: '📚',
              className: className,
              section: section,
            ),
          ),
        );
        break;

      case DestinationType.community:
        final communityData = destination.data;
        final communityIcon = communityData is CommunityModel
            ? communityData.getCategoryIcon()
            : '👥';

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => CommunityChatPage(
              communityId: destination.id,
              communityName: destination.name,
              icon: communityIcon,
            ),
          ),
        );
        break;

      default:
        // Staff room, individual chats, announcements → return to dashboard
        Navigator.pop(context);
        break;
    }
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  Color _getRoleColor(UserRole role) {
    switch (role) {
      case UserRole.student:
        return AppColors.studentColor;
      case UserRole.teacher:
        return AppColors.teacherColor;
      case UserRole.parent:
        return AppColors.parentColor;
      case UserRole.institute:
        return AppColors.instituteColor;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF130F23) : const Color(0xFFF0EFF5);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          Provider.of<ShareController>(context, listen: false).clearShareData();
        }
      },
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: _roleColor,
          foregroundColor: Colors.white,
          title: const Text(
            'Share to...',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          elevation: 0,
          leading: BackButton(
            onPressed: () {
              Provider.of<ShareController>(
                context,
                listen: false,
              ).clearShareData();
              Navigator.pop(context);
            },
          ),
        ),
        body: Column(
          children: [
            // Content preview
            _SharePreviewCard(
              shareData: widget.shareData,
              isDark: isDark,
              roleColor: _roleColor,
            ),

            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: _SearchBar(controller: _searchController, isDark: isDark),
            ),

            const SizedBox(height: 4),

            // Sections list
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredSections.isEmpty
                  ? _EmptyState(isDark: isDark)
                  : ListView.builder(
                      padding: const EdgeInsets.only(
                        left: 16,
                        right: 16,
                        bottom: 32,
                      ),
                      itemCount: _filteredSections.length,
                      itemBuilder: (context, sectionIndex) {
                        final section = _filteredSections[sectionIndex];
                        return _SectionWidget(
                          section: section,
                          isDark: isDark,
                          roleColor: _roleColor,
                          isImageContent: _isImageContent,
                          onTap: _onDestinationTap,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Share Preview Card
// ===========================================================================

class _SharePreviewCard extends StatelessWidget {
  final IncomingShareData shareData;
  final bool isDark;
  final Color roleColor;

  const _SharePreviewCard({
    required this.shareData,
    required this.isDark,
    required this.roleColor,
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF1E1A2F) : Colors.white;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.35 : 0.08),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(color: roleColor.withOpacity(0.25), width: 1),
      ),
      child: shareData.type == ShareContentType.image && shareData.hasFiles
          ? _ImagePreview(files: shareData.files, cardBg: cardBg)
          : _GenericPreview(
              shareData: shareData,
              isDark: isDark,
              roleColor: roleColor,
            ),
    );
  }
}

class _ImagePreview extends StatelessWidget {
  final List<String> files;
  final Color cardBg;

  const _ImagePreview({required this.files, required this.cardBg});

  @override
  Widget build(BuildContext context) {
    if (files.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.file(
          File(files.first),
          height: 200,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _fallbackTile(),
        ),
      );
    }
    // Multiple images – horizontal scroll
    return SizedBox(
      height: 140,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        scrollDirection: Axis.horizontal,
        itemCount: files.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(
            File(files[i]),
            width: 120,
            height: 120,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _fallbackTile(),
          ),
        ),
      ),
    );
  }

  Widget _fallbackTile() => Container(
    width: 120,
    height: 120,
    color: cardBg,
    child: const Icon(Icons.image_not_supported_outlined, size: 40),
  );
}

class _GenericPreview extends StatelessWidget {
  final IncomingShareData shareData;
  final bool isDark;
  final Color roleColor;

  const _GenericPreview({
    required this.shareData,
    required this.isDark,
    required this.roleColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: roleColor.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _iconForType(shareData.type),
              color: roleColor,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _labelForType(shareData.type),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                if (shareData.hasText)
                  Text(
                    shareData.text!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                if (shareData.hasFiles &&
                    shareData.type != ShareContentType.text)
                  Text(
                    '${shareData.files.length} file(s)',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForType(ShareContentType t) {
    switch (t) {
      case ShareContentType.text:
        return Icons.text_fields_rounded;
      case ShareContentType.image:
        return Icons.image_rounded;
      case ShareContentType.audio:
        return Icons.audiotrack_rounded;
      case ShareContentType.file:
        return Icons.insert_drive_file_rounded;
      case ShareContentType.mixed:
        return Icons.attach_file_rounded;
    }
  }

  String _labelForType(ShareContentType t) {
    switch (t) {
      case ShareContentType.text:
        return 'Text';
      case ShareContentType.image:
        return 'Image \u00b7 ${shareData.files.length} file(s)';
      case ShareContentType.audio:
        return 'Audio';
      case ShareContentType.file:
        return 'File';
      case ShareContentType.mixed:
        return 'Multiple Items \u00b7 ${shareData.files.length} file(s)';
    }
  }
}

// ===========================================================================
// Search bar
// ===========================================================================

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isDark;

  const _SearchBar({required this.controller, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: 'Search destinations...',
        hintStyle: TextStyle(
          color: isDark ? Colors.white38 : Colors.black38,
          fontSize: 14,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          color: isDark ? Colors.white54 : Colors.black45,
        ),
        filled: true,
        fillColor: isDark ? const Color(0xFF1E1A2F) : Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          vertical: 12,
          horizontal: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

// ===========================================================================
// Section widget
// ===========================================================================

class _SectionWidget extends StatelessWidget {
  final _Section section;
  final bool isDark;
  final Color roleColor;
  final bool isImageContent;
  final void Function(ShareDestination) onTap;

  const _SectionWidget({
    required this.section,
    required this.isDark,
    required this.roleColor,
    required this.isImageContent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isAnnouncement = section.title == 'Announcement';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header (skip for Announcement – has its own header style)
        if (!isAnnouncement) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 14, 0, 8),
            child: Text(
              section.title.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ),
        ] else ...[
          const SizedBox(height: 12),
        ],
        ...section.destinations.map(
          (dest) => dest.type == DestinationType.announcement
              ? _AnnouncementCard(
                  destination: dest,
                  isDark: isDark,
                  roleColor: roleColor,
                  enabled: isImageContent,
                  onTap: () => onTap(dest),
                )
              : _DestinationTile(
                  destination: dest,
                  isDark: isDark,
                  roleColor: roleColor,
                  onTap: () => onTap(dest),
                ),
        ),
      ],
    );
  }
}

// ===========================================================================
// Announcement card (special – image-only rule enforced here)
// ===========================================================================

class _AnnouncementCard extends StatelessWidget {
  final ShareDestination destination;
  final bool isDark;
  final Color roleColor;
  final bool enabled;
  final VoidCallback onTap;

  const _AnnouncementCard({
    required this.destination,
    required this.isDark,
    required this.roleColor,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = enabled
        ? (isDark ? roleColor.withOpacity(0.18) : roleColor.withOpacity(0.08))
        : (isDark ? const Color(0xFF232030) : const Color(0xFFF0EFF5));

    final iconColor = enabled ? roleColor : Colors.grey;
    final titleColor = enabled
        ? (isDark ? Colors.white : Colors.black87)
        : Colors.grey;
    final subtitleColor = enabled
        ? (isDark ? Colors.white60 : Colors.black54)
        : Colors.grey.shade500;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: enabled
                  ? roleColor.withOpacity(0.4)
                  : Colors.grey.withOpacity(0.25),
              width: 1.5,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: enabled ? onTap : null,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: iconColor.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.campaign_rounded,
                        color: iconColor,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            destination.name,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: titleColor,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            destination.subtitle,
                            style: TextStyle(
                              fontSize: 12,
                              color: subtitleColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (enabled)
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 15,
                        color: isDark ? Colors.white38 : Colors.black38,
                      )
                    else
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 18,
                        color: Colors.grey.shade500,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Helper text shown when announcement is disabled
        if (!enabled)
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 10),
            child: Text(
              'Announcements support image posts only.',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade500,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }
}

// ===========================================================================
// Regular destination tile
// ===========================================================================

class _DestinationTile extends StatelessWidget {
  final ShareDestination destination;
  final bool isDark;
  final Color roleColor;
  final VoidCallback onTap;

  const _DestinationTile({
    required this.destination,
    required this.isDark,
    required this.roleColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1A2F) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.25 : 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: roleColor.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(destination.icon, color: roleColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        destination.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        destination.subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 15,
                  color: isDark ? Colors.white30 : Colors.black26,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Confirm bottom sheet
// ===========================================================================

class _ConfirmBottomSheet extends StatelessWidget {
  final ShareDestination destination;
  final bool isDark;
  final Color roleColor;
  final VoidCallback onConfirm;

  const _ConfirmBottomSheet({
    required this.destination,
    required this.isDark,
    required this.roleColor,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1A2F) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Share to ${destination.name}?',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    onConfirm();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: roleColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Post',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Empty state
// ===========================================================================

class _EmptyState extends StatelessWidget {
  final bool isDark;
  const _EmptyState({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 64,
            color: (isDark ? Colors.white : Colors.black).withOpacity(0.2),
          ),
          const SizedBox(height: 14),
          Text(
            'No destinations found',
            style: TextStyle(
              fontSize: 16,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Data models
// ===========================================================================

class ShareDestination {
  final String id;
  final String name;
  final DestinationType type;
  final IconData icon;
  final String subtitle;
  final dynamic data;

  ShareDestination({
    required this.id,
    required this.name,
    required this.type,
    required this.icon,
    required this.subtitle,
    this.data,
  });
}

enum DestinationType {
  community,
  groupChat,
  individualChat,
  staffRoom,
  announcement,
}
