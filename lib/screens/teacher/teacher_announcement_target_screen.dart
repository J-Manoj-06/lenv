import 'package:flutter/material.dart';
import 'teacher_announcement_compose_screen.dart';

const _bg = Color(0xFF120F23);
const _surface = Color(0xFF1A1730);
const _muted = Color(0xFF8E8BA3);
const _primary = Color(0xFF355872);

class TeacherAnnouncementTargetScreen extends StatefulWidget {
  final List<String> teacherClasses; // Teacher's assigned classes
  final Map<String, dynamic>? teacherData; // Teacher data including sections

  const TeacherAnnouncementTargetScreen({
    super.key,
    required this.teacherClasses,
    this.teacherData,
  });

  @override
  State<TeacherAnnouncementTargetScreen> createState() =>
      _TeacherAnnouncementTargetScreenState();
}

class _TeacherAnnouncementTargetScreenState
    extends State<TeacherAnnouncementTargetScreen> {
  String _target = 'school';
  final Set<String> _selectedStandards = {};
  final Set<String> _selectedSections = {};
  List<String> _availableStandards = [];
  List<String> _availableSections = [];

  @override
  void initState() {
    super.initState();
    _extractStandardsAndSections();
  }

  void _extractStandardsAndSections() {
    final standards = <String>{};
    final sections = <String>{};

    // Parse classes like "Grade 10 - A", "Grade 10 - B"
    for (final className in widget.teacherClasses) {
      final parts = className.split(' - ');
      if (parts.length == 2) {
        final standard = parts[0].replaceAll('Grade ', '').trim();
        final section = parts[1].trim();

        standards.add(standard);
        sections.add('$standard$section'); // e.g., "10A"
      }
    }

    setState(() {
      _availableStandards = standards.toList()..sort();
      _availableSections = sections.toList()..sort();
    });
  }

  void _toggleStandard(String s) {
    setState(() {
      if (_selectedStandards.contains(s)) {
        _selectedStandards.remove(s);
      } else {
        _selectedStandards.add(s);
      }
    });
  }

  void _toggleSection(String s) {
    setState(() {
      if (_selectedSections.contains(s)) {
        _selectedSections.remove(s);
      } else {
        _selectedSections.add(s);
      }
    });
  }

  void _continue() {
    if (_target == 'standard' && _selectedStandards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one standard')),
      );
      return;
    }

    if (_target == 'section' && _selectedSections.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one section')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TeacherAnnouncementComposeScreen(
          audienceType: _target,
          standards: _selectedStandards.toList(),
          sections: _selectedSections.toList(),
          teacherData: widget.teacherData,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? _bg : Colors.white;
    final surfaceColor = isDark ? _surface : const Color(0xFFF5F5F5);
    final textColor = isDark ? Colors.white : Colors.black87;
    final mutedColor = isDark ? _muted : const Color(0xFF757575);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            _TargetTopBar(
              onClose: () => Navigator.pop(context),
              textColor: textColor,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Choose who should receive this announcement.',
                textAlign: TextAlign.center,
                style: TextStyle(color: mutedColor, fontSize: 14),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _TargetCard(
                    title: 'Whole School',
                    subtitle: 'Send announcement to all students and staff.',
                    icon: Icons.school_rounded,
                    selected: _target == 'school',
                    onTap: () => setState(() => _target = 'school'),
                    surfaceColor: surfaceColor,
                    textColor: textColor,
                    mutedColor: mutedColor,
                  ),
                  const SizedBox(height: 12),
                  _TargetCard(
                    title: 'Specific Standards',
                    subtitle: 'Choose individual standards to notify.',
                    icon: Icons.class_rounded,
                    selected: _target == 'standard',
                    onTap: () => setState(() => _target = 'standard'),
                    surfaceColor: surfaceColor,
                    textColor: textColor,
                    mutedColor: mutedColor,
                    child: _availableStandards.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              'No standards assigned to you',
                              style: TextStyle(color: mutedColor, fontSize: 13),
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: _availableStandards
                                  .map(
                                    (s) => _StandardChip(
                                      label: 'Grade $s',
                                      selected: _selectedStandards.contains(s),
                                      onTap: () => _toggleStandard(s),
                                      isDark: isDark,
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                  ),
                  const SizedBox(height: 12),
                  _TargetCard(
                    title: 'Specific Sections',
                    subtitle: 'Choose your sections to notify.',
                    icon: Icons.groups_rounded,
                    selected: _target == 'section',
                    onTap: () => setState(() => _target = 'section'),
                    surfaceColor: surfaceColor,
                    textColor: textColor,
                    mutedColor: mutedColor,
                    child: _availableSections.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              'No sections assigned to you',
                              style: TextStyle(color: mutedColor, fontSize: 13),
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: _availableSections
                                  .map(
                                    (s) => _StandardChip(
                                      label: s,
                                      selected: _selectedSections.contains(s),
                                      onTap: () => _toggleSection(s),
                                      isDark: isDark,
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: bgColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.5 : 0.1),
                    offset: const Offset(0, -2),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: mutedColor, fontSize: 15),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _continue,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Continue',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TargetTopBar extends StatelessWidget {
  const _TargetTopBar({required this.onClose, required this.textColor});

  final VoidCallback onClose;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.chevron_left, color: textColor, size: 28),
          ),
          Expanded(
            child: Text(
              'New Announcement',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: Icon(Icons.close, color: textColor, size: 24),
          ),
        ],
      ),
    );
  }
}

class _TargetCard extends StatelessWidget {
  const _TargetCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.surfaceColor,
    required this.textColor,
    required this.mutedColor,
    this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final Color surfaceColor;
  final Color textColor;
  final Color mutedColor;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? _primary.withOpacity(0.5) : Colors.transparent,
            width: 2,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: _primary.withOpacity(0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: _primary.withOpacity(0.16),
                    shape: BoxShape.circle,
                    border: Border.all(color: _primary.withOpacity(0.4)),
                  ),
                  child: Icon(icon, color: _primary, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(color: mutedColor, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: selected ? _primary : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? _primary : mutedColor.withOpacity(0.4),
                    ),
                  ),
                  child: const Icon(Icons.check, size: 16, color: Colors.white),
                ),
              ],
            ),
            if (child != null) child!,
          ],
        ),
      ),
    );
  }
}

class _StandardChip extends StatelessWidget {
  const _StandardChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.isDark,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? _primary
        : (isDark ? const Color(0xFF1A1730) : const Color(0xFFE8E8E8));
    final border = selected
        ? _primary
        : (isDark ? _muted.withOpacity(0.4) : const Color(0xFFD0D0D0));
    final textColor = selected
        ? Colors.white
        : (isDark ? Colors.white : Colors.black87);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? Icons.check : Icons.class_rounded,
              size: 16,
              color: textColor,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
