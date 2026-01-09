import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/parent_provider.dart';
import '../../models/student_model.dart';
import 'student_select_bottom_sheet.dart';

/// Compact horizontal row of student avatars for parent pages
/// Shows up to 4 avatars + overflow, with active student highlighted
class StudentAvatarRow extends StatelessWidget {
  const StudentAvatarRow({super.key});

  // App theme colors - matching existing app palette
  static const Color accentPurple = Color(0xFF8B5CF6);
  static const Color accentOrange = Color(0xFFFF6B35);
  static const Color parentGreen = Color(0xFF14A670);
  static const Color bgDark = Color(0xFF151022);
  static const Color cardDark = Color(0xFF1E1E2D);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Consumer<ParentProvider>(
      builder: (context, parentProvider, child) {
        final children = parentProvider.children;
        final selectedIndex = parentProvider.selectedChildIndex;

        if (children.isEmpty) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? cardDark : Colors.white,
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? Colors.white.withOpacity(0.05)
                    : Colors.grey.withOpacity(0.1),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              // Children count badge
              _buildCountBadge(children.length, isDark),
              const SizedBox(width: 12),

              // Avatars row
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _buildAvatarList(
                      context,
                      children,
                      selectedIndex,
                      isDark,
                      parentProvider,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCountBadge(int count, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: parentGreen.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: parentGreen.withOpacity(0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people, size: 16, color: parentGreen),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildAvatarList(
    BuildContext context,
    List<StudentModel> children,
    int selectedIndex,
    bool isDark,
    ParentProvider parentProvider,
  ) {
    const int maxVisible = 4;
    final List<Widget> avatars = [];

    if (children.length <= maxVisible) {
      // Show all children
      for (int i = 0; i < children.length; i++) {
        avatars.add(
          _buildAvatar(
            context,
            children[i],
            i,
            selectedIndex,
            isDark,
            parentProvider,
          ),
        );
      }
    } else {
      // Show first 4 + overflow
      for (int i = 0; i < maxVisible; i++) {
        avatars.add(
          _buildAvatar(
            context,
            children[i],
            i,
            selectedIndex,
            isDark,
            parentProvider,
          ),
        );
      }

      // Add overflow avatar
      avatars.add(
        _buildOverflowAvatar(context, children.length - maxVisible, isDark),
      );
    }

    return avatars;
  }

  Widget _buildAvatar(
    BuildContext context,
    StudentModel student,
    int index,
    int selectedIndex,
    bool isDark,
    ParentProvider parentProvider,
  ) {
    final isActive = index == selectedIndex;
    final firstName = student.name.split(' ').first;
    final shortName = firstName.length > 8
        ? '${firstName.substring(0, 7)}.'
        : firstName;

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: InkWell(
        onTap: () {
          if (isActive) {
            // Tapping active avatar opens bottom sheet
            _showStudentSelector(context);
          } else {
            // Switching to different child
            parentProvider.selectChild(index);
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Semantics(
          label: '${student.name}, ${isActive ? "selected" : "tap to select"}',
          button: true,
          child: Container(
            width: 72,
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Avatar with ring
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutBack,
                  transform: Matrix4.identity()..scale(isActive ? 1.1 : 1.0),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isActive ? parentGreen : Colors.transparent,
                        width: 3,
                      ),
                      boxShadow: isActive
                          ? [
                              BoxShadow(
                                color: parentGreen.withOpacity(0.4),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ]
                          : [],
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [parentGreen.withOpacity(0.8), parentGreen],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          student.name.isNotEmpty
                              ? student.name[0].toUpperCase()
                              : 'S',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                // Name
                Text(
                  shortName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                    color: isDark
                        ? (isActive ? Colors.white : Colors.grey[400])
                        : (isActive ? Colors.black87 : Colors.grey[700]),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverflowAvatar(
    BuildContext context,
    int remainingCount,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: InkWell(
        onTap: () => _showStudentSelector(context),
        borderRadius: BorderRadius.circular(12),
        child: Semantics(
          label: '$remainingCount more students, tap to view all',
          button: true,
          child: Container(
            width: 72,
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark ? Colors.grey[800] : Colors.grey[200],
                    border: Border.all(
                      color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '+$remainingCount',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : Colors.grey[700],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'More',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.grey[400] : Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showStudentSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const StudentSelectBottomSheet(),
    );
  }
}
