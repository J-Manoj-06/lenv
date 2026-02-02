import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../models/user_model.dart';
import '../share/incoming_share_data.dart';
import '../share/share_controller.dart';
import '../services/cloudflare_r2_service.dart';
import '../config/cloudflare_config.dart';
import '../services/media_upload_service.dart';
import '../services/local_cache_service.dart';
import '../services/community_service.dart';
import '../services/group_messaging_service.dart';
import '../models/community_model.dart';
import '../models/group_subject.dart';
import '../core/constants/app_colors.dart';

/// Comprehensive share target screen for all roles
/// Shows appropriate destinations based on user role:
/// - Student: Communities, Group Chats, Individual Chats
/// - Teacher: Communities, Group Chats (Classes), Staff Room, Announcements
/// - Parent: Individual Teacher Chats
/// - Institute: Staff Room, Announcements
class ShareTargetScreen extends StatefulWidget {
  final IncomingShareData shareData;

  const ShareTargetScreen({super.key, required this.shareData});

  @override
  State<ShareTargetScreen> createState() => _ShareTargetScreenState();
}

class _ShareTargetScreenState extends State<ShareTargetScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<ShareDestination> _allDestinations = [];
  List<ShareDestination> _filteredDestinations = [];
  bool _isLoading = true;
  String _searchQuery = '';
  late final MediaUploadService _mediaUploadService;
  UserRole? _userRole;
  Color _roleColor = AppColors.primary;

  @override
  void initState() {
    super.initState();
    _initMediaService();
    _loadDestinations();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
        _filterDestinations();
      });
    });
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
      firestore: FirebaseFirestore.instance,
      cacheService: LocalCacheService(),
    );
  }

  Future<void> _loadDestinations() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUser = authProvider.currentUser;
      if (currentUser == null) {
        print('ShareTargetScreen: No current user found');
        setState(() => _isLoading = false);
        return;
      }

      print('ShareTargetScreen: Loading destinations for ${currentUser.role}');
      _userRole = currentUser.role;
      _roleColor = _getRoleColor(currentUser.role);

      final List<ShareDestination> destinations = [];

      // Load destinations based on role
      switch (currentUser.role) {
        case UserRole.student:
          await _loadStudentDestinations(destinations, currentUser);
          break;
        case UserRole.teacher:
          await _loadTeacherDestinations(destinations, currentUser);
          break;
        case UserRole.parent:
          await _loadParentDestinations(destinations, currentUser);
          break;
        case UserRole.institute:
          await _loadInstituteDestinations(destinations, currentUser);
          break;
      }

      print('ShareTargetScreen: Loaded ${destinations.length} destinations');
      setState(() {
        _allDestinations = destinations;
        _filteredDestinations = destinations;
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      print('ShareTargetScreen: Error loading destinations: $e');
      print('Stack trace: $stackTrace');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading destinations: $e'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _loadStudentDestinations(
    List<ShareDestination> destinations,
    UserModel currentUser,
  ) async {
    print('Loading student destinations for user: ${currentUser.uid}');
    final communityService = CommunityService();
    final messagingService = GroupMessagingService();

    // Load communities
    try {
      final communities = await communityService.getMyCommunitiesForRole(
        userId: currentUser.uid,
        role: 'student',
      );
      print('Found ${communities.length} communities for student');

      for (final community in communities) {
        destinations.add(
          ShareDestination(
            id: community.id,
            name: community.name,
            type: DestinationType.community,
            icon: Icons.groups,
            subtitle: '${community.memberCount} members',
            data: community,
          ),
        );
      }
    } catch (e) {
      print('Error loading student communities: $e');
    }

    // Load group chats (class subjects)
    try {
      final classId = await messagingService.getStudentClassId(currentUser.uid);
      print('Student classId: $classId');
      if (classId != null) {
        final subjects = await messagingService.getClassSubjects(classId);
        print('Found ${subjects.length} subjects for student');
        for (final subject in subjects) {
          destinations.add(
            ShareDestination(
              id: '${classId}_${subject.id}',
              name: subject.name,
              type: DestinationType.groupChat,
              icon: Icons.school,
              subtitle: 'Class Group Chat',
              data: {
                'classId': classId,
                'subjectId': subject.id,
                'subject': subject,
              },
            ),
          );
        }
      }
    } catch (e) {
      print('Error loading student groups: $e');
    }

    print('Total student destinations: ${destinations.length}');
    // Note: Individual chats would require a list of contacts
    // This could be added by querying recent conversations or contacts list
  }

  Future<void> _loadTeacherDestinations(
    List<ShareDestination> destinations,
    UserModel currentUser,
  ) async {
    print('Loading teacher destinations for user: ${currentUser.uid}');
    final communityService = CommunityService();

    // Load communities
    try {
      final communities = await communityService.getMyCommunitiesForRole(
        userId: currentUser.uid,
        role: 'teacher',
      );
      print('Found ${communities.length} communities for teacher');

      for (final community in communities) {
        destinations.add(
          ShareDestination(
            id: community.id,
            name: community.name,
            type: DestinationType.community,
            icon: Icons.groups,
            subtitle: '${community.memberCount} members',
            data: community,
          ),
        );
      }
    } catch (e) {
      print('Error loading teacher communities: $e');
    }

    // Load teaching groups (classes and subjects)
    try {
      // Query teacher by email, not by UID
      final teacherQuery = await FirebaseFirestore.instance
          .collection('teachers')
          .where('email', isEqualTo: currentUser.email)
          .limit(1)
          .get();

      print('Teacher query found: ${teacherQuery.docs.length} docs');
      if (teacherQuery.docs.isNotEmpty) {
        final teacherData = teacherQuery.docs.first.data();
        final classesHandled =
            teacherData['classesHandled'] as List<dynamic>? ?? [];
        print('Found ${classesHandled.length} classesHandled for teacher');

        for (final classId in classesHandled) {
          if (classId is String) {
            // Fetch class details to get subjects
            try {
              final classDoc = await FirebaseFirestore.instance
                  .collection('classes')
                  .doc(classId)
                  .get();

              if (classDoc.exists) {
                final classData = classDoc.data();
                final className = classData?['className'] ?? '';
                final section = classData?['section'] ?? '';
                final subjects = classData?['subjects'] as List<dynamic>? ?? [];

                print(
                  'Class $className $section has ${subjects.length} subjects',
                );

                for (final subject in subjects) {
                  if (subject is String) {
                    destinations.add(
                      ShareDestination(
                        id: '${classId}_$subject',
                        name: '$subject - Class $className $section',
                        type: DestinationType.groupChat,
                        icon: Icons.class_,
                        subtitle: 'Class Group Chat',
                        data: {
                          'classId': classId,
                          'subjectId': subject,
                          'className': className,
                          'section': section,
                        },
                      ),
                    );
                  }
                }
              }
            } catch (e) {
              print('Error loading class $classId: $e');
            }
          }
        }
      }
    } catch (e) {
      print('Error loading teacher classes: $e');
    }

    // Staff Room
    if (currentUser.instituteId != null) {
      print('Adding staff room for institute: ${currentUser.instituteId}');
      destinations.add(
        ShareDestination(
          id: 'staff_room_${currentUser.instituteId}',
          name: 'Staff Room',
          type: DestinationType.staffRoom,
          icon: Icons.meeting_room,
          subtitle: 'Teacher communication',
          data: {'instituteId': currentUser.instituteId},
        ),
      );
    }

    // Announcement option
    print('Adding announcement option for teacher');
    destinations.add(
      ShareDestination(
        id: 'announcement_${currentUser.uid}',
        name: 'Create Announcement',
        type: DestinationType.announcement,
        icon: Icons.campaign,
        subtitle: 'Share as announcement',
        data: {'teacherId': currentUser.uid},
      ),
    );

    print('Total teacher destinations: ${destinations.length}');
  }

  Future<void> _loadParentDestinations(
    List<ShareDestination> destinations,
    UserModel currentUser,
  ) async {
    print('Loading parent destinations for user: ${currentUser.uid}');
    // Load linked students and their teachers
    try {
      final parentDoc = await FirebaseFirestore.instance
          .collection('parents')
          .doc(currentUser.uid)
          .get();

      print('Parent doc exists: ${parentDoc.exists}');
      if (parentDoc.exists) {
        final parentData = parentDoc.data();
        final linkedStudents =
            parentData?['linkedStudents'] as List<dynamic>? ?? [];
        print('Found ${linkedStudents.length} linked students');

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

              for (final teacherData in linkedTeachers) {
                if (teacherData is Map<String, dynamic>) {
                  final teacherId = teacherData['teacherId'] ?? '';
                  final teacherName = teacherData['teacherName'] ?? 'Teacher';
                  final subject = teacherData['subject'] ?? '';

                  destinations.add(
                    ShareDestination(
                      id: 'teacher_$teacherId',
                      name: teacherName,
                      type: DestinationType.individualChat,
                      icon: Icons.person,
                      subtitle: subject,
                      data: {
                        'teacherId': teacherId,
                        'teacherName': teacherName,
                        'studentId': studentId,
                      },
                    ),
                  );
                }
              }
            }
          }
        }
      }
    } catch (e) {
      print('Error loading parent destinations: $e');
    }

    // Remove duplicates based on teacher ID
    final uniqueDestinations = <String, ShareDestination>{};
    for (final dest in destinations) {
      if (dest.type == DestinationType.individualChat) {
        final teacherId = (dest.data as Map<String, dynamic>)['teacherId'];
        uniqueDestinations[teacherId] = dest;
      }
    }
    destinations.clear();
    destinations.addAll(uniqueDestinations.values);

    print(
      'Total parent destinations after deduplication: ${destinations.length}',
    );
  }

  Future<void> _loadInstituteDestinations(
    List<ShareDestination> destinations,
    UserModel currentUser,
  ) async {
    print('Loading institute destinations for user: ${currentUser.uid}');
    // Staff Room
    if (currentUser.instituteId != null) {
      print('Adding staff room for institute: ${currentUser.instituteId}');
      destinations.add(
        ShareDestination(
          id: 'staff_room_${currentUser.instituteId}',
          name: 'Staff Room',
          type: DestinationType.staffRoom,
          icon: Icons.business,
          subtitle: 'All staff members',
          data: {'instituteId': currentUser.instituteId},
        ),
      );
    }

    // Announcement option
    print('Adding institute announcement option');
    destinations.add(
      ShareDestination(
        id: 'announcement_${currentUser.uid}',
        name: 'Create Announcement',
        type: DestinationType.announcement,
        icon: Icons.campaign,
        subtitle: 'Share as institute announcement',
        data: {'principalId': currentUser.uid},
      ),
    );

    print('Total institute destinations: ${destinations.length}');
  }

  void _filterDestinations() {
    if (_searchQuery.isEmpty) {
      setState(() {
        _filteredDestinations = _allDestinations;
      });
    } else {
      setState(() {
        _filteredDestinations = _allDestinations
            .where(
              (dest) =>
                  dest.name.toLowerCase().contains(_searchQuery) ||
                  dest.subtitle.toLowerCase().contains(_searchQuery),
            )
            .toList();
      });
    }
  }

  void _showShareConfirmation(ShareDestination destination) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Share to ${destination.name}?',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _shareToDestination(destination);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _roleColor,
                    ),
                    child: const Text(
                      'Send',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _shareToDestination(ShareDestination destination) async {
    final shareController = Provider.of<ShareController>(
      context,
      listen: false,
    );
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;

    if (currentUser == null) return;

    shareController.setProcessing(true);

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Sharing...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final messageData = <String, dynamic>{
        'senderId': currentUser.uid,
        'senderName': currentUser.name,
        'senderRole': currentUser.role.toString().split('.').last,
        'timestamp': FieldValue.serverTimestamp(),
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'isForwarded': true,
        'forwardedFrom': 'External App',
      };

      // Handle different content types
      if (widget.shareData.hasText) {
        messageData['text'] = widget.shareData.text;
      } else {
        messageData['text'] = '';
      }

      // Handle files
      if (widget.shareData.hasFiles) {
        final file = File(widget.shareData.files.first);

        // Upload file
        final mediaMessage = await _mediaUploadService.uploadMedia(
          file: file,
          conversationId: destination.id,
          senderId: currentUser.uid,
          senderRole: currentUser.role.toString().split('.').last,
        );

        messageData['mediaType'] = 'media';
        messageData['mediaUrl'] = mediaMessage.r2Url;
        messageData['fileName'] = mediaMessage.fileName;
        messageData['fileType'] = mediaMessage.fileType;
        messageData['fileSize'] = mediaMessage.fileSize;
        messageData['thumbnailUrl'] = mediaMessage.thumbnailUrl;
        messageData['mediaId'] = mediaMessage.id;
            }

      // Send to appropriate destination based on type
      switch (destination.type) {
        case DestinationType.community:
          await _shareToCommunity(destination, messageData);
          break;
        case DestinationType.groupChat:
          await _shareToGroupChat(destination, messageData);
          break;
        case DestinationType.individualChat:
          await _shareToIndividualChat(destination, messageData);
          break;
        case DestinationType.staffRoom:
          await _shareToStaffRoom(destination, messageData);
          break;
        case DestinationType.announcement:
          await _shareAsAnnouncement(destination, messageData);
          break;
      }

      // Close dialogs and show success
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        Navigator.pop(context); // Close share screen
        shareController.clearShareData();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Shared to ${destination.name}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      // Close loading dialog
      if (mounted) Navigator.pop(context);

      shareController.setProcessing(false);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to share: $e')));
      }
    }
  }

  Future<void> _shareToCommunity(
    ShareDestination destination,
    Map<String, dynamic> messageData,
  ) async {
    await FirebaseFirestore.instance
        .collection('communities')
        .doc(destination.id)
        .collection('messages')
        .add(messageData);
  }

  Future<void> _shareToGroupChat(
    ShareDestination destination,
    Map<String, dynamic> messageData,
  ) async {
    final data = destination.data as Map<String, dynamic>;
    final classId = data['classId'];
    final subjectId = data['subjectId'];

    await FirebaseFirestore.instance
        .collection('classes')
        .doc(classId)
        .collection('subjects')
        .doc(subjectId)
        .collection('messages')
        .add(messageData);
  }

  Future<void> _shareToIndividualChat(
    ShareDestination destination,
    Map<String, dynamic> messageData,
  ) async {
    final data = destination.data as Map<String, dynamic>;
    final teacherId = data['teacherId'];
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final parentId = authProvider.currentUser?.uid;

    // Create or get conversation
    final conversationId = '${parentId}_$teacherId';

    await FirebaseFirestore.instance
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .add(messageData);

    // Update conversation metadata
    await FirebaseFirestore.instance
        .collection('conversations')
        .doc(conversationId)
        .set({
          'participants': [parentId, teacherId],
          'lastMessage': messageData['text'],
          'lastMessageTime': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Future<void> _shareToStaffRoom(
    ShareDestination destination,
    Map<String, dynamic> messageData,
  ) async {
    final data = destination.data as Map<String, dynamic>;
    final instituteId = data['instituteId'];

    await FirebaseFirestore.instance
        .collection('staff_rooms')
        .doc(instituteId)
        .collection('messages')
        .add(messageData);
  }

  Future<void> _shareAsAnnouncement(
    ShareDestination destination,
    Map<String, dynamic> messageData,
  ) async {
    // For announcements, we need to show a dialog to get more details
    // For now, we'll just show a message that this feature needs the full UI
    if (mounted) {
      Navigator.pop(context); // Close loading dialog if open
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'To create an announcement, please use the announcement composer in the app',
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return WillPopScope(
      onWillPop: () async {
        // Clear share data when user cancels
        final shareController = Provider.of<ShareController>(
          context,
          listen: false,
        );
        shareController.clearShareData();
        return true;
      },
      child: Scaffold(
        backgroundColor: isDark
            ? const Color(0xFF130F23)
            : const Color(0xFFF6F5F8),
        appBar: AppBar(
          backgroundColor: _roleColor,
          foregroundColor: Colors.white,
          title: const Text('Share to...'),
          elevation: 0,
        ),
        body: Column(
          children: [
            // Content preview card
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1A2F) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _roleColor.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    _getIconForType(widget.shareData.type),
                    color: _roleColor,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getTypeLabel(widget.shareData.type),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (widget.shareData.hasText)
                          Text(
                            widget.shareData.text!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        if (widget.shareData.hasFiles)
                          Text(
                            '${widget.shareData.files.length} file(s)',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search destinations...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1E1A2F) : Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Destinations list
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredDestinations.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.inbox_outlined,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No destinations found',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _filteredDestinations.length,
                      itemBuilder: (context, index) {
                        final destination = _filteredDestinations[index];
                        return _DestinationTile(
                          destination: destination,
                          isDark: isDark,
                          roleColor: _roleColor,
                          onTap: () => _showShareConfirmation(destination),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

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

  IconData _getIconForType(ShareContentType type) {
    switch (type) {
      case ShareContentType.text:
        return Icons.text_fields;
      case ShareContentType.image:
        return Icons.image;
      case ShareContentType.audio:
        return Icons.audiotrack;
      case ShareContentType.file:
        return Icons.insert_drive_file;
      case ShareContentType.mixed:
        return Icons.attach_file;
    }
  }

  String _getTypeLabel(ShareContentType type) {
    switch (type) {
      case ShareContentType.text:
        return 'Text Message';
      case ShareContentType.image:
        return 'Image';
      case ShareContentType.audio:
        return 'Audio';
      case ShareContentType.file:
        return 'File';
      case ShareContentType.mixed:
        return 'Multiple Items';
    }
  }
}

/// Tile widget for displaying a share destination
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
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: roleColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(destination.icon, color: roleColor),
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
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
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
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Model for share destinations
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
