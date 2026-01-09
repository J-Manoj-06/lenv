import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import './institute_announcement_target_screen.dart';
import './principal_announcement_viewer.dart';
import '../../providers/auth_provider.dart';
import '../../models/institute_announcement_model.dart';
import '../../services/media_repository.dart';

const Color _backgroundDark = Color(0xFF0F172A); // slate-900
const Color _cardColor = Color(0xFF1E293B); // slate-800
const Color _teal = Color(0xFF146D7A); // custom teal
const Color _slate400 = Color(0xFF94A3B8);

class InstituteDashboardScreen extends StatefulWidget {
  const InstituteDashboardScreen({super.key});

  @override
  State<InstituteDashboardScreen> createState() =>
      _InstituteDashboardScreenState();
}

class _InstituteDashboardScreenState extends State<InstituteDashboardScreen> {
  final MediaRepository _mediaRepository = MediaRepository();

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundDark,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TopBar(teal: _teal),
              const _SectionHeader(title: 'Announcements'),
              _buildAnnouncementsSection(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: const [
                    Expanded(
                      child: _StatCard(
                        icon: Icons.school,
                        label: 'Total Students',
                        value: '1,240',
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: _StatCard(
                        icon: Icons.group,
                        label: 'Total Staff',
                        value: '85',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: _AttendanceCard(percentage: 0.92),
              ),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: _QuickActionCard(),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // Build announcements section with real Firestore data
  Widget _buildAnnouncementsSection() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;
    final currentUserId = currentUser?.uid;
    final instituteId = currentUser?.instituteId ?? '';

    if (instituteId.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(
          'Unable to load announcements. Please check your connection.',
          style: TextStyle(color: _slate400),
        ),
      );
    }

    return SizedBox(
      height: 110,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('institute_announcements')
            .where('instituteId', isEqualTo: instituteId)
            .snapshots(),
        builder: (context, snapshot) {
          // Loading state
          if (snapshot.connectionState == ConnectionState.waiting) {
            return ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              scrollDirection: Axis.horizontal,
              itemCount: 5,
              itemBuilder: (_, __) => _buildShimmerCircle(),
              separatorBuilder: (_, __) => const SizedBox(width: 12),
            );
          }

          // Error state
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Error loading announcements',
                  style: TextStyle(color: _slate400),
                ),
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          // Convert docs to InstituteAnnouncementModel and filter valid ones
          final allAnnouncements =
              docs
                  .map((d) => InstituteAnnouncementModel.fromFirestore(d))
                  .where((a) => a.instituteId == instituteId)
                  .toList()
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          // Segregate: My announcements vs Other Principals
          final myAnnouncements = allAnnouncements
              .where((a) => a.principalId == currentUserId)
              .toList();

          // Group other principals' announcements by principalId
          final otherPrincipalsMap =
              <String, List<InstituteAnnouncementModel>>{};
          for (final announcement in allAnnouncements) {
            if (announcement.principalId != currentUserId) {
              otherPrincipalsMap
                  .putIfAbsent(announcement.principalId, () => [])
                  .add(announcement);
            }
          }

          // Sort each principal's announcements by timestamp
          otherPrincipalsMap.forEach((key, value) {
            value.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          });

          // Create list of other principals (sorted by latest post)
          final otherPrincipals = otherPrincipalsMap.entries.toList()
            ..sort(
              (a, b) =>
                  b.value.first.createdAt.compareTo(a.value.first.createdAt),
            );

          // Build horizontal list: My Announcement + Other Principals
          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: 1 + otherPrincipals.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              if (index == 0) {
                // My Announcement (always first)
                return _buildMyAnnouncementAvatar(myAnnouncements, currentUser);
              } else {
                // Other Principals
                final principalEntry = otherPrincipals[index - 1];
                final announcements = principalEntry.value;
                final latestAnnouncement = announcements.first;
                return _buildOtherPrincipalAvatar(
                  latestAnnouncement,
                  announcements,
                );
              }
            },
          );
        },
      ),
    );
  }

  // Shimmer loading circle
  Widget _buildShimmerCircle() {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _cardColor.withOpacity(0.5),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: 40,
          height: 10,
          decoration: BoxDecoration(
            color: _cardColor.withOpacity(0.5),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }

  // My Announcement Avatar (First item with + button)
  Widget _buildMyAnnouncementAvatar(
    List<InstituteAnnouncementModel> myAnnouncements,
    dynamic currentUser,
  ) {
    final hasAnnouncement = myAnnouncements.isNotEmpty;
    final latestAnnouncement = hasAnnouncement ? myAnnouncements.first : null;

    return GestureDetector(
      onTap: () {
        if (hasAnnouncement) {
          // Open announcement viewer with delete option
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PrincipalAnnouncementViewer(
                announcements: myAnnouncements,
                initialIndex: 0,
                currentUserId: currentUser?.uid ?? '',
              ),
            ),
          ).then((_) {
            // Refresh dashboard after returning from viewer
            if (mounted) {
              setState(() {});
            }
          });
        } else {
          _openAnnouncementTargetSelection();
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              // Main Avatar Circle
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: hasAnnouncement
                      ? const LinearGradient(
                          colors: [Color(0xFF146D7A), Color(0xFF1E9BA8)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  border: !hasAnnouncement
                      ? Border.all(color: _teal, width: 2)
                      : null,
                  color: !hasAnnouncement ? _cardColor : null,
                ),
                padding: const EdgeInsets.all(3),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hasAnnouncement
                        ? (latestAnnouncement!.hasImage
                              ? Colors.transparent
                              : _teal)
                        : _cardColor,
                  ),
                  child: ClipOval(
                    child: hasAnnouncement && latestAnnouncement!.hasImage
                        ? _buildCachedAvatarImage(
                            latestAnnouncement.imageUrl!,
                            'announcement_${latestAnnouncement.id}.jpg',
                            currentUser?.name ?? 'Principal',
                          )
                        : _buildDefaultAvatar(currentUser?.name ?? 'Principal'),
                  ),
                ),
              ),

              // Add (+) Icon Overlay (Small, bottom-right)
              Positioned(
                right: -2,
                bottom: -2,
                child: GestureDetector(
                  onTap: _openAnnouncementTargetSelection,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF146D7A), Color(0xFF1E9BA8)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(color: _backgroundDark, width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          color: _teal.withOpacity(0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Label
          SizedBox(
            width: 70,
            child: Text(
              'Add',
              textAlign: TextAlign.center,
              maxLines: 1,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _slate400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultAvatar(String name) {
    return Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : 'P',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 24,
        ),
      ),
    );
  }

  // Other Principal Avatar
  Widget _buildOtherPrincipalAvatar(
    InstituteAnnouncementModel latestAnnouncement,
    List<InstituteAnnouncementModel> allAnnouncements,
  ) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = authProvider.currentUser?.uid ?? '';

    // Check if any of this principal's announcements are unviewed
    final hasUnviewed = allAnnouncements.any(
      (a) => !_hasBeenViewedSync(a.id, currentUserId),
    );

    return GestureDetector(
      onTap: () {
        // TODO: Open announcement viewer
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Avatar with gradient border
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: hasUnviewed
                  ? const LinearGradient(
                      colors: [Color(0xFFF27F0D), Color(0xFFFF9F40)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : LinearGradient(
                      colors: [
                        Colors.grey.withOpacity(0.4),
                        Colors.grey.withOpacity(0.3),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
              boxShadow: hasUnviewed
                  ? [
                      BoxShadow(
                        color: const Color(0xFFF27F0D).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            padding: const EdgeInsets.all(3),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: latestAnnouncement.hasImage ? Colors.transparent : _teal,
              ),
              child: ClipOval(
                child: latestAnnouncement.hasImage
                    ? ColorFiltered(
                        colorFilter: hasUnviewed
                            ? const ColorFilter.mode(
                                Colors.transparent,
                                BlendMode.multiply,
                              )
                            : ColorFilter.mode(
                                Colors.grey.withOpacity(0.5),
                                BlendMode.saturation,
                              ),
                        child: Image.network(
                          latestAnnouncement.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildPrincipalInitial(
                            latestAnnouncement.principalName,
                          ),
                        ),
                      )
                    : _buildPrincipalInitial(latestAnnouncement.principalName),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Principal Name
          SizedBox(
            width: 70,
            child: Text(
              latestAnnouncement.principalName.split(' ').first,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _slate400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrincipalInitial(String name) {
    return Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : 'P',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 24,
        ),
      ),
    );
  }

  // Synchronous check for viewed status (simplified for now)
  bool _hasBeenViewedSync(String announcementId, String userId) {
    // For simplicity, assume unviewed for now
    // In production, you'd cache this data or use a different approach
    return false;
  }

  void _openAnnouncementTargetSelection() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const InstituteAnnouncementTargetScreen(),
      ),
    );
  }

  /// Build cached avatar image - downloads and caches announcement images
  Widget _buildCachedAvatarImage(
    String imageUrl,
    String fileName,
    String fallbackName,
  ) {
    return FutureBuilder<String?>(
      future: _getAnnouncementImagePath(imageUrl, fileName),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Show loading shimmer while checking cache/downloading
          return Container(
            color: _teal.withOpacity(0.3),
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(_teal),
              ),
            ),
          );
        }

        if (snapshot.hasError || snapshot.data == null) {
          // Show fallback avatar if download failed
          return _buildDefaultAvatar(fallbackName);
        }

        // Show cached image
        return Image.file(
          File(snapshot.data!),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildDefaultAvatar(fallbackName);
          },
        );
      },
    );
  }

  /// Get announcement image path - from cache or download if needed
  Future<String?> _getAnnouncementImagePath(
    String imageUrl,
    String fileName,
  ) async {
    try {
      // Extract R2 key from URL
      String r2Key;
      if (imageUrl.contains('files.lenv1.tech')) {
        final uri = Uri.parse(imageUrl);
        r2Key = uri.path.substring(1); // Remove leading /
      } else {
        r2Key = 'announcements/${imageUrl.hashCode}_$fileName';
      }

      // Check if already cached
      final localPath = await _mediaRepository.getLocalFilePath(r2Key);
      if (localPath != null) {
        return localPath;
      }

      // Download and cache
      final result = await _mediaRepository.downloadMedia(
        r2Key: r2Key,
        fileName: fileName,
        mimeType: 'image/jpeg',
      );

      if (result.success && result.localPath != null) {
        return result.localPath;
      }

      return null;
    } catch (e) {
      debugPrint('❌ Error loading announcement avatar: $e');
      return null;
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.teal});

  final Color teal;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              image: const DecorationImage(
                image: NetworkImage(
                  'https://lh3.googleusercontent.com/aida-public/AB6AXuC4rLa-okXKewTcUXRfoGDRTz_zPBMuwI1SrwYIn89cU3YlQu5KQne8DGaF4rcKRVUOr-yBGxx6pEr30ZiC-a2D16o5r8svt6AFFJ5b9nAaZdR4CYbHVTbVCQEHD6G1nV8NnrRKY97DY-VuBfzWgJ5kpSR1-H9RNXvtMNT43Sr1_seTS53O9b4EfnIal8WIURyhqQpSu3uIL124NWamYDjuMknLmg3_HYhouqKgcLuwmU6KlxgMzkv8QmcS78Ckj9k-nIyon8gixkYi',
                ),
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Good Morning, Principal',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(
              Icons.account_circle,
              color: Colors.white,
              size: 32,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _teal),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: _slate400,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttendanceCard extends StatelessWidget {
  const _AttendanceCard({required this.percentage});

  final double percentage;

  @override
  Widget build(BuildContext context) {
    final percentText = '${(percentage * 100).round()}%';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Today's Attendance",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                percentText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Stack(
            children: [
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: const Color(0xFF334155),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              FractionallySizedBox(
                widthFactor: percentage.clamp(0, 1),
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: _teal,
                    borderRadius: BorderRadius.circular(999),
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

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF334155),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.campaign, color: _teal),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Broadcast Message',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Send a message to all staff',
                  style: TextStyle(color: _slate400, fontSize: 13),
                ),
              ],
            ),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: _teal,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_forward, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
