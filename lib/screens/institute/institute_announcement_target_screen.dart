import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import 'institute_announcement_compose_screen.dart';

const _bg = Color(0xFF0F1416);
const _surface = Color(0xFF1D1F24);
const _muted = Color(0xFF9AA0A6);
const _teal = Color(0xFF146D7A);

class InstituteAnnouncementTargetScreen extends StatefulWidget {
  const InstituteAnnouncementTargetScreen({super.key});

  @override
  State<InstituteAnnouncementTargetScreen> createState() =>
      _InstituteAnnouncementTargetScreenState();
}

class _InstituteAnnouncementTargetScreenState
    extends State<InstituteAnnouncementTargetScreen> {
  String _target = 'specific';
  final Set<String> _selectedStandards = {};
  List<String> _availableStandards = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchAvailableStandards();
  }

  Future<void> _fetchAvailableStandards() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final schoolCode = authProvider.currentUser?.instituteId ?? '';

    if (schoolCode.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('schoolCode', isEqualTo: schoolCode)
          .get();

      // Extract unique standards from students
      final standards = <String>{};
      for (final doc in snapshot.docs) {
        final className = doc.data()['className'] as String?;
        if (className != null && className.isNotEmpty) {
          standards.add(className);
        }
      }

      // Sort standards
      final sortedStandards = standards.toList()..sort();

      setState(() {
        _availableStandards = sortedStandards;
        _isLoading = false;
      });
    } catch (e) {
      print('Error fetching standards: $e');
      setState(() => _isLoading = false);
    }
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

  void _continue() {
    if (_target == 'specific' && _selectedStandards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one standard')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InstituteAnnouncementComposeScreen(
          audienceType: _target == 'whole' ? 'school' : 'standard',
          standards: _target == 'whole' ? [] : _selectedStandards.toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _TargetTopBar(onClose: () => Navigator.pop(context)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Choose who should receive this announcement.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted, fontSize: 14),
              ),
            ),
            const SizedBox(height: 16),
            _isLoading
                ? const Expanded(
                    child: Center(
                      child: CircularProgressIndicator(color: _teal),
                    ),
                  )
                : Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        _TargetCard(
                          title: 'Whole School',
                          subtitle:
                              'Send announcement to all standards and staff.',
                          icon: Icons.school,
                          selected: _target == 'whole',
                          onTap: () => setState(() => _target = 'whole'),
                        ),
                        const SizedBox(height: 12),
                        _TargetCard(
                          title: 'Specific Standards',
                          subtitle: 'Choose individual standards to notify.',
                          icon: Icons.class_,
                          selected: _target == 'specific',
                          onTap: () => setState(() => _target = 'specific'),
                          child: _availableStandards.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Text(
                                    'No standards found in school',
                                    style: TextStyle(
                                      color: _muted,
                                      fontSize: 13,
                                    ),
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
                                            label: s,
                                            selected: _selectedStandards
                                                .contains(s),
                                            onTap: () => _toggleStandard(s),
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
              decoration: const BoxDecoration(
                color: _bg,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black54,
                    offset: Offset(0, -2),
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
                      style: TextStyle(color: _muted, fontSize: 15),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _continue,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _teal,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Continue',
                        style: TextStyle(
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
  const _TargetTopBar({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
          ),
          const Expanded(
            child: Text(
              'New Announcement',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close, color: Colors.white, size: 24),
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
    this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? _teal.withOpacity(0.5) : Colors.transparent,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: _teal.withOpacity(0.25),
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
                    color: _teal.withOpacity(0.16),
                    shape: BoxShape.circle,
                    border: Border.all(color: _teal.withOpacity(0.4)),
                  ),
                  child: Icon(icon, color: _teal, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(color: _muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: selected ? _teal : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? _teal : _muted.withOpacity(0.4),
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
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? _teal : const Color(0xFF111417);
    final border = selected ? _teal : _muted.withOpacity(0.4);
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
              selected ? Icons.check : Icons.class_,
              size: 16,
              color: Colors.white,
            ),
            const SizedBox(width: 6),
            Text(
              '$label Standard',
              style: const TextStyle(
                color: Colors.white,
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
