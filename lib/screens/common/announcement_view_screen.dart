import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Role-based announcement viewer
/// Shows a themed announcement based on the poster's role
/// Roles supported: student, teacher, parent, principal, institute
class AnnouncementViewScreen extends StatefulWidget {
  final String
  role; // e.g. 'teacher', 'principal', 'student', 'parent', 'institute'
  final String title; // main announcement title
  final String subtitle; // sub text
  final String postedByLabel; // e.g. 'Posted by Principal'
  final String? avatarUrl; // optional poster avatar
  final DateTime? postedAt; // for relative time (e.g., 3h ago)
  final DateTime? expiresAt; // for expiry banner

  const AnnouncementViewScreen({
    super.key,
    required this.role,
    required this.title,
    required this.subtitle,
    required this.postedByLabel,
    this.avatarUrl,
    this.postedAt,
    this.expiresAt,
  });

  @override
  State<AnnouncementViewScreen> createState() => _AnnouncementViewScreenState();
}

class _AnnouncementViewScreenState extends State<AnnouncementViewScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;

  late _RoleTheme _theme;

  @override
  void initState() {
    super.initState();
    _theme = _RoleTheme.forRole(widget.role);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );
    _progress = CurvedAnimation(parent: _controller, curve: Curves.linear);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _relativeTime(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return DateFormat('MMM d').format(dt);
  }

  String _expiryText(DateTime? expiresAt) {
    if (expiresAt == null) return '';
    final now = DateTime.now();
    final diff = expiresAt.difference(now);
    if (diff.isNegative) return 'Expired';
    if (diff.inHours >= 24) {
      final days = (diff.inHours / 24).floor();
      return 'Expires in ${days}d';
    }
    return 'Expires in ${diff.inHours} hrs';
  }

  @override
  Widget build(BuildContext context) {
    final isLight = _theme.useLightBackground;
    final bgColor = isLight ? _theme.bgLight : _theme.bgDark;

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          // Background glow and vignette
          Positioned.fill(
            child: IgnorePointer(
              child: Stack(
                children: [
                  // Primary glow ellipse
                  Align(
                    alignment: const Alignment(0, 0),
                    child: Container(
                      width: MediaQuery.of(context).size.width * 1.6,
                      height: MediaQuery.of(context).size.height * 0.8,
                      decoration: BoxDecoration(
                        color: _theme.primary.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(9999),
                      ),
                    ),
                  ),
                  // Vignette overlay
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(isLight ? 0.2 : 0.5),
                            Colors.transparent,
                            Colors.black.withOpacity(isLight ? 0.4 : 0.8),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Foreground content
          SafeArea(
            child: Column(
              children: [
                // Header with progress bars + avatar/title
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                  child: Column(
                    children: [
                      // Progress bars
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(9999),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: AnimatedBuilder(
                                animation: _progress,
                                builder: (context, _) {
                                  return Align(
                                    alignment: Alignment.centerLeft,
                                    child: FractionallySizedBox(
                                      widthFactor: _progress.value,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: _theme.primary,
                                          boxShadow: [
                                            BoxShadow(
                                              color: _theme.primary.withOpacity(
                                                0.5,
                                              ),
                                              blurRadius: 10,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Container(
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(9999),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Container(
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(9999),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Top row: avatar + titles + close button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              // Avatar
                              Container(
                                height: 44,
                                width: 44,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _theme.primary.withOpacity(0.5),
                                    width: 2,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 8,
                                    ),
                                  ],
                                  image: widget.avatarUrl != null
                                      ? DecorationImage(
                                          image: NetworkImage(
                                            widget.avatarUrl!,
                                          ),
                                          fit: BoxFit.cover,
                                        )
                                      : null,
                                  color: widget.avatarUrl == null
                                      ? Colors.grey.shade400
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Title lines
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'School Status',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Text(
                                        widget.postedByLabel,
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.8),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        width: 4,
                                        height: 4,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.6),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _relativeTime(widget.postedAt),
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.6),
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                          // Close button
                          InkWell(
                            onTap: () => Navigator.pop(context),
                            borderRadius: BorderRadius.circular(9999),
                            child: Container(
                              height: 40,
                              width: 40,
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(9999),
                              ),
                              child: const Icon(
                                Icons.close,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Center content
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.school, size: 68, color: _theme.primary),
                          const SizedBox(height: 16),
                          Text(
                            widget.title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                            ),
                            maxLines: 10,
                            overflow: TextOverflow.visible,
                          ),
                          if (widget.subtitle.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              widget.subtitle,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 8,
                              overflow: TextOverflow.visible,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),

                // Footer
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(9999),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.08),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.schedule,
                              size: 16,
                              color: Colors.white70,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _expiryText(widget.expiresAt),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white70,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Icon(
                        Icons.keyboard_arrow_up,
                        color: Colors.white70,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleTheme {
  final Color primary;
  final Color bgLight;
  final Color bgDark;
  final bool useLightBackground;

  const _RoleTheme({
    required this.primary,
    required this.bgLight,
    required this.bgDark,
    required this.useLightBackground,
  });

  /// Map role to theme (from project conventions)
  static _RoleTheme forRole(String role) {
    final r = role.toLowerCase();
    switch (r) {
      case 'teacher':
        return const _RoleTheme(
          primary: Color(0xFF7E57C2), // Violet
          bgLight: Color(0xFFF3E5F5),
          bgDark: Color(0xFF120F23),
          useLightBackground: true,
        );
      case 'principal':
      case 'institute':
        return const _RoleTheme(
          primary: Color(0xFF1976D2), // Blue
          bgLight: Color(0xFFE3F2FD),
          bgDark: Color(0xFF101214),
          useLightBackground: true,
        );
      case 'parent':
        return const _RoleTheme(
          primary: Color(0xFF009688), // Teal
          bgLight: Color(0xFFE0F2F1),
          bgDark: Color(0xFF151022),
          useLightBackground: true,
        );
      case 'student':
      default:
        return const _RoleTheme(
          primary: Color(0xFFF27F0D), // Orange
          bgLight: Color(0xFFFFF5EB),
          bgDark: Color(0xFF221910),
          useLightBackground: false,
        );
    }
  }
}

/// Helper: quick open via Navigator
Future<void> openAnnouncementView(
  BuildContext context, {
  required String role,
  required String title,
  required String subtitle,
  required String postedByLabel,
  String? avatarUrl,
  DateTime? postedAt,
  DateTime? expiresAt,
}) async {
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => AnnouncementViewScreen(
        role: role,
        title: title,
        subtitle: subtitle,
        postedByLabel: postedByLabel,
        avatarUrl: avatarUrl,
        postedAt: postedAt,
        expiresAt: expiresAt,
      ),
    ),
  );
}
