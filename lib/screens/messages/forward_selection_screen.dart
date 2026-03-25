import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/forward_message_data.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/forward_message_service.dart';
import '../../services/community_service.dart';
import '../../services/group_messaging_service.dart';
import '../../services/teacher_groups_service.dart';
import 'teacher_group_chat_page.dart';

/// Screen for selecting forward destinations.
/// Accepts a list of [ForwardMessageData] (the messages to forward),
/// shows a multi-select list of accessible chat destinations,
/// and calls [ForwardMessageService] on confirmation.
class ForwardSelectionScreen extends StatefulWidget {
  final List<ForwardMessageData> messages;
  final List<ForwardDestination>? availableDestinations;
  final String? customSectionTitle;

  const ForwardSelectionScreen({
    super.key,
    required this.messages,
    this.availableDestinations,
    this.customSectionTitle,
  });

  @override
  State<ForwardSelectionScreen> createState() => _ForwardSelectionScreenState();
}

class _ForwardSelectionScreenState extends State<ForwardSelectionScreen> {
  final _forwardService = ForwardMessageService();
  final _communityService = CommunityService();
  final _groupService = GroupMessagingService();
  final _teacherGroupsService = TeacherGroupsService();

  final Set<String> _selectedDestinationIds = {};
  final List<ForwardDestination> _destinations = [];
  bool _isLoading = true;
  bool _isForwarding = false;
  String? _error;

  bool get _restrictToClassGroupsForMindmap =>
      widget.messages.any(_isMindmapForwardMessage);

  bool _isMindmapForwardMessage(ForwardMessageData msg) {
    if (msg.messageType.toLowerCase() == 'mindmap') return true;
    final text = (msg.text ?? '').trim().toLowerCase();
    return text.startsWith('mindmap:') || text.startsWith('mind map:');
  }

  bool _isDestinationEnabled(ForwardDestination dest) {
    if (_restrictToClassGroupsForMindmap) {
      return dest.type == 'group';
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    // Use caller-provided destinations when present (parent forward flow).
    if (widget.availableDestinations != null) {
      _destinations
        ..clear()
        ..addAll(widget.availableDestinations!);
      _isLoading = false;
      return;
    }

    // Use post-frame so Provider is accessible.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDestinations());
  }

  // ─── Destination loading ────────────────────────────────────────────────────

  Future<void> _loadDestinations() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final user = auth.currentUser;
      if (user == null) {
        setState(() {
          _isLoading = false;
          _error = 'Not signed in';
        });
        return;
      }

      final destinations = <ForwardDestination>[];

      // ── 1. Communities (all roles) ───────────────────────────────────────
      try {
        final comms = await _communityService.getMyComm(user.uid);
        for (final c in comms) {
          destinations.add(
            ForwardDestination(
              id: c.id,
              name: c.name,
              type: 'community',
              subtitle: c.category.isNotEmpty ? c.category : 'Community',
              iconEmoji: _communityEmoji(c.category),
              metadata: null,
            ),
          );
        }
      } catch (_) {}

      // ── 2. Staff room (teacher / institute) ──────────────────────────────
      if (user.role == UserRole.teacher || user.role == UserRole.institute) {
        final instituteId = user.instituteId;
        if (instituteId != null && instituteId.isNotEmpty) {
          destinations.add(
            ForwardDestination(
              id: instituteId,
              name: 'Staff Room',
              type: 'staff_room',
              subtitle: 'Teachers & Principals',
              iconEmoji: '👩‍🏫',
              metadata: null,
            ),
          );
        }
      }

      // ── 3. Class groups (teacher) ─────────────────────────────────────────
      if (user.role == UserRole.teacher || user.role == UserRole.institute) {
        try {
          final data = await _teacherGroupsService.getTeacherGroups(user.uid);
          if (data != null) {
            final groups = _teacherGroupsService.parseGroups(data);
            for (final g in groups) {
              final classId = g['classId'] as String? ?? '';
              final subjectId = g['subjectId'] as String? ?? '';
              final className = g['className'] as String? ?? 'Class';
              final subject = g['subject'] as String? ?? 'Subject';
              if (classId.isEmpty || subjectId.isEmpty) continue;
              final destId = '$classId|$subjectId';
              destinations.add(
                ForwardDestination(
                  id: destId,
                  name: '$className – $subject',
                  type: 'group',
                  subtitle: className,
                  iconEmoji: '📚',
                  metadata: {
                    'classId': classId,
                    'subjectId': subjectId,
                    'subjectName': subject,
                    'className': className,
                    'icon': '📚',
                  },
                ),
              );
            }
          }
        } catch (_) {}
      }

      // ── 4. Class groups (student) ─────────────────────────────────────────
      if (user.role == UserRole.student) {
        try {
          final classId = await _groupService.getStudentClassId(user.uid);
          if (classId != null) {
            final subjects = await _groupService.getClassSubjects(classId);
            for (final s in subjects) {
              destinations.add(
                ForwardDestination(
                  id: '$classId|${s.id}',
                  name: s.name,
                  type: 'group',
                  subtitle: 'Class Group',
                  iconEmoji: s.icon.isNotEmpty ? s.icon : '📚',
                  metadata: {
                    'classId': classId,
                    'subjectId': s.id,
                    'subjectName': s.name,
                    'className': '',
                    'icon': s.icon.isNotEmpty ? s.icon : '📚',
                  },
                ),
              );
            }
          }
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _destinations
          ..clear()
          ..addAll(destinations);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Failed to load destinations: $e';
      });
    }
  }

  // ─── Forwarding ──────────────────────────────────────────────────────────────

  Future<void> _doForward() async {
    if (_selectedDestinationIds.isEmpty) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.currentUser;
    if (user == null) return;

    setState(() => _isForwarding = true);

    final selected = _destinations
        .where(
          (d) =>
              _selectedDestinationIds.contains(d.id) &&
              _isDestinationEnabled(d),
        )
        .toList();

    if (selected.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mindmap can only be forwarded to class groups'),
        ),
      );
      return;
    }

    try {
      final results = await _forwardService.forwardMessages(
        messages: widget.messages,
        destinations: selected,
        senderId: user.uid,
        senderName: user.name,
        senderRole: user.role.toString().split('.').last,
      );

      if (!mounted) return;

      final failed = results.entries.where((e) => e.value != null).toList();

      if (failed.isEmpty) {
        // All succeeded
        final count = selected.length;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              count == 1
                  ? 'Forwarded to ${selected.first.name}'
                  : 'Forwarded to $count chats',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
        // Navigate to the destination if a single group was selected
        final dest = selected.first;
        if (selected.length == 1 &&
            dest.type == 'group' &&
            dest.metadata != null) {
          final classId = dest.metadata!['classId'] as String? ?? '';
          final subjectId = dest.metadata!['subjectId'] as String? ?? '';
          final subjectName =
              dest.metadata!['subjectName'] as String? ?? dest.name;
          final className = dest.metadata!['className'] as String? ?? '';
          final icon = dest.metadata!['icon'] as String? ?? '📚';
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => TeacherGroupChatPage(
                classId: classId,
                subjectId: subjectId,
                subjectName: subjectName,
                teacherName: 'Teacher',
                icon: icon,
                className: className.isNotEmpty ? className : null,
              ),
            ),
          );
        } else {
          Navigator.of(context).pop(true); // pop with success flag
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${failed.length} destination(s) failed. '
              'Please try again.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isForwarding = false);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Forward failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => _isForwarding = false);
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────────

  String _communityEmoji(String category) {
    final c = category.toLowerCase();
    if (c.contains('sports') || c.contains('cricket')) return '⚽';
    if (c.contains('science')) return '🔬';
    if (c.contains('art')) return '🎨';
    if (c.contains('music')) return '🎵';
    if (c.contains('tech') || c.contains('computer')) return '💻';
    if (c.contains('book') || c.contains('read')) return '📖';
    return '💬';
  }

  String _messagePreview(ForwardMessageData msg) {
    switch (msg.messageType) {
      case 'text':
        final t = msg.text ?? '';
        return t.length > 60 ? '${t.substring(0, 60)}…' : t;
      case 'link':
        return '🔗 ${msg.text ?? 'Link'}';
      case 'image':
        return '📷 Photo';
      case 'multi_image':
        final cnt = msg.multipleImageUrls?.length ?? 2;
        return '📷 $cnt Photos';
      case 'audio':
        return '🎤 Voice message';
      case 'file':
        return '📄 ${msg.fileName ?? 'Document'}';
      default:
        return '📨 Message';
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0D0E10) : Colors.white;
    final cardBg = isDark ? const Color(0xFF1A1C22) : const Color(0xFFF7F8FA);
    final textPrimary = isDark
        ? const Color(0xFFE8E8E8)
        : const Color(0xFF0F172A);
    final textSecondary = isDark
        ? const Color(0xFF9AA5B4)
        : const Color(0xFF64748B);
    final accentColor = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        title: Text(
          'Forward to…',
          style: TextStyle(
            color: textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.close, color: textPrimary),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: Column(
        children: [
          // ── Message preview strip ──────────────────────────────────────────
          _buildPreviewStrip(cardBg, textPrimary, textSecondary),

          // ── Destination list ───────────────────────────────────────────────
          Expanded(
            child: _buildDestinationList(
              theme,
              isDark,
              textPrimary,
              textSecondary,
              accentColor,
              cardBg,
            ),
          ),

          // ── Forward button ─────────────────────────────────────────────────
          _buildForwardButton(accentColor),
        ],
      ),
    );
  }

  Widget _buildPreviewStrip(Color bg, Color textPrimary, Color textSecondary) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          const Icon(Icons.reply_all_rounded, size: 18, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: widget.messages.length == 1
                ? Text(
                    _messagePreview(widget.messages.first),
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  )
                : Text(
                    '${widget.messages.length} messages selected',
                    style: TextStyle(
                      color: textSecondary,
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDestinationList(
    ThemeData theme,
    bool isDark,
    Color textPrimary,
    Color textSecondary,
    Color accentColor,
    Color cardBg,
  ) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: textSecondary)),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _loadDestinations,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_destinations.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, color: Colors.grey, size: 48),
            const SizedBox(height: 12),
            Text(
              'No chats available to forward to.',
              style: TextStyle(color: textSecondary),
            ),
          ],
        ),
      );
    }

    // Group destinations by type
    final communities = _destinations
        .where((d) => d.type == 'community')
        .toList();
    final groups = _destinations.where((d) => d.type == 'group').toList();
    final staffRooms = _destinations
        .where((d) => d.type == 'staff_room')
        .toList();
    final parentTeacherGroups = _destinations
        .where((d) => d.type == 'parent_teacher_group')
        .toList();

    final sections = <_Section>[
      if (communities.isNotEmpty)
        _Section(title: 'Communities', items: communities),
      if (staffRooms.isNotEmpty)
        _Section(title: 'Staff Room', items: staffRooms),
      if (groups.isNotEmpty) _Section(title: 'Class Groups', items: groups),
      if (parentTeacherGroups.isNotEmpty)
        _Section(
          title: widget.customSectionTitle ?? 'Parent-Teacher Groups',
          items: parentTeacherGroups,
        ),
    ];

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: sections.fold<int>(
        0,
        (sum, s) => sum + 1 + s.items.length,
      ), // headers + items
      itemBuilder: (context, index) {
        // Figure out which section / item this index maps to
        int running = 0;
        for (final section in sections) {
          if (index == running) {
            // Section header
            return _buildSectionHeader(section.title, textSecondary);
          }
          running++;
          if (index < running + section.items.length) {
            final item = section.items[index - running];
            return _buildDestinationTile(
              item,
              textPrimary,
              textSecondary,
              accentColor,
              cardBg,
              isDark,
            );
          }
          running += section.items.length;
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildSectionHeader(String title, Color textSecondary) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildDestinationTile(
    ForwardDestination dest,
    Color textPrimary,
    Color textSecondary,
    Color accentColor,
    Color cardBg,
    bool isDark,
  ) {
    final isSelected = _selectedDestinationIds.contains(dest.id);
    final isEnabled = _isDestinationEnabled(dest);

    return InkWell(
      onTap: () {
        if (!isEnabled) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Mindmap can only be forwarded to class groups'),
              duration: Duration(milliseconds: 1200),
            ),
          );
          return;
        }
        setState(() {
          if (isSelected) {
            _selectedDestinationIds.remove(dest.id);
          } else {
            _selectedDestinationIds.add(dest.id);
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected && isEnabled
              ? accentColor.withOpacity(isDark ? 0.15 : 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF2A2D35)
                      : const Color(0xFFEEF2FF),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    dest.iconEmoji ?? '💬',
                    style: TextStyle(
                      fontSize: 22,
                      color: isEnabled ? null : Colors.grey,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Text info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dest.name,
                      style: TextStyle(
                        color: isEnabled ? textPrimary : textSecondary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (dest.subtitle != null)
                      Text(
                        dest.subtitle!,
                        style: TextStyle(color: textSecondary, fontSize: 12),
                      ),
                  ],
                ),
              ),

              // Checkbox-style indicator
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isSelected && isEnabled
                      ? accentColor
                      : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected && isEnabled ? accentColor : Colors.grey,
                    width: 2,
                  ),
                ),
                child: isSelected && isEnabled
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForwardButton(Color accentColor) {
    final count = _selectedDestinationIds.length;
    final enabled = count > 0 && !_isForwarding;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: enabled ? accentColor : Colors.grey,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: _isForwarding
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.reply_all_rounded, color: Colors.white),
            label: Text(
              _isForwarding
                  ? 'Forwarding…'
                  : (count == 0
                        ? (_restrictToClassGroupsForMindmap
                              ? 'Select a class group to forward'
                              : 'Select a chat to forward')
                        : 'Forward to $count chat${count == 1 ? '' : 's'}'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            onPressed: enabled ? _doForward : null,
          ),
        ),
      ),
    );
  }
}

// Helper struct for grouped sections
class _Section {
  final String title;
  final List<ForwardDestination> items;
  const _Section({required this.title, required this.items});
}
