import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/teacher_bottom_nav.dart';
import '../../services/teacher_service.dart';
import '../../services/firestore_service.dart';

class TeacherDashboardScreen extends StatefulWidget {
  const TeacherDashboardScreen({Key? key}) : super(key: key);

  @override
  State<TeacherDashboardScreen> createState() => _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState extends State<TeacherDashboardScreen> {
  String? selectedClass;
  int selectedNavIndex = 0;

  final TeacherService _teacherService = TeacherService();
  Map<String, dynamic>? _teacherData;
  List<Map<String, dynamic>> _students = [];
  List<String> _classes = [];
  Map<String, int> _classStudentCounts = {};
  bool _isLoading = true;
  String? _error;

  // Highlights: best-effort cleanup on load
  Future<void> _cleanupExpiredHighlights() async {
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final uid = auth.currentUser?.uid;
      if (uid == null) return;
      final now = DateTime.now();
      final qs = await FirebaseFirestore.instance
          .collection('class_highlights')
          .where('teacherId', isEqualTo: uid)
          .get();
      final expired = qs.docs.where((d) {
        final ts = (d.data()['expiresAt'] as Timestamp?)?.toDate();
        return ts != null && !ts.isAfter(now);
      }).toList();
      if (expired.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (final d in expired) {
          batch.delete(d.reference);
        }
        await batch.commit();
      }
    } catch (_) {
      // silent best-effort
    }
  }

  @override
  void initState() {
    super.initState();
    _loadTeacherData();
    // Sweep expired highlights for this teacher (best-effort; prefer Firestore TTL)
    _cleanupExpiredHighlights();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadTeacherData() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      // DEBUG: trace startup auth/session state
      // ignore: avoid_print
      print('[Dashboard] Starting _loadTeacherData');
      // Attempt to initialize auth in case app was cold-started
      await authProvider.initializeAuth();
      final currentUser = authProvider.currentUser;
      // ignore: avoid_print
      print(
        '[Dashboard] auth.currentUser: ${currentUser?.email} role=${currentUser?.role}',
      );

      if (currentUser == null) {
        setState(() {
          _error = 'No user logged in';
          _isLoading = false;
        });
        // ignore: avoid_print
        print('[Dashboard] No user after initializeAuth');
        return;
      }

      // Fetch teacher data
      final teacherData = await _teacherService.getTeacherByEmail(
        currentUser.email,
      );

      if (teacherData == null) {
        setState(() {
          _error = 'Teacher data not found';
          _isLoading = false;
        });
        return;
      }

      // Determine sections field (supports 'sections' array or 'section' string)
      final dynamic sections =
          teacherData['sections'] ?? teacherData['section'];

      // Format classes for dropdown using sections
      final classes = _teacherService.getTeacherClasses(
        teacherData['classesHandled'],
        sections,
        classAssignments: teacherData['classAssignments'], // Fallback
      );

      // Fetch students (supports both classesHandled and classAssignments)
      final students = await _teacherService.getStudentsByTeacher(
        currentUser.instituteId ?? teacherData['schoolCode'] ?? '',
        teacherData['classesHandled'],
        sections,
        classAssignments: teacherData['classAssignments'],
      );

      setState(() {
        _teacherData = teacherData;
        _classes = classes;
        _students = students;
        selectedClass = classes.isNotEmpty ? classes[0] : null;

        // Calculate student count per class
        _classStudentCounts = {};
        for (var className in classes) {
          final parts = className.split(' - ');
          if (parts.length == 2) {
            final selectedGrade = parts[0].trim();
            final selectedSection = parts[1].trim();

            final count = students.where((student) {
              final studentClassName = student['className']?.toString() ?? '';
              final studentGrade = studentClassName
                  .replaceAll('Grade ', '')
                  .replaceAll('grade ', '')
                  .trim();
              final studentSection = student['section']?.toString() ?? '';

              return studentGrade == selectedGrade &&
                  studentSection == selectedSection;
            }).length;

            _classStudentCounts[className] = count;
          }
        }

        _isLoading = false;
      });

      // After loading, run best-effort auto-publish sweep
      // (app-side scheduled check in case backend cron isn't available)
      try {
        await FirestoreService().autoPublishExpiredTests();
      } catch (_) {}
    } catch (e) {
      // ignore: avoid_print
      print('Error loading teacher data: $e');
      setState(() {
        _error = 'Failed to load data';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(_error!),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadTeacherData,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildGradientStatsBanner(),
                        const SizedBox(height: 24),
                        _buildClassroomHighlights(),
                        const SizedBox(height: 24),
                        _buildClassSummary(),
                        const SizedBox(height: 24),
                        _buildAlerts(),
                        const SizedBox(height: 24),
                        _buildRecentActivity(),
                        const SizedBox(height: 80),
                      ],
                    ),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  Widget _buildHeader() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.menu,
                        color: Theme.of(context).iconTheme.color,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Hello, ${_teacherData?['teacherName'] ?? currentUser?.name ?? 'Teacher'}',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                      ),
                    ],
                  ),
                  Stack(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.notifications_outlined),
                        color: Theme.of(context).iconTheme.color,
                        onPressed: () {},
                      ),
                      Positioned(
                        right: 8,
                        top: 8,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Color(0xFF6366F1),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: DropdownButtonFormField<String>(
                  value: selectedClass,
                  dropdownColor: Theme.of(context).cardColor,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  items: _classes.map((String className) {
                    final count = _classStudentCounts[className] ?? 0;
                    return DropdownMenuItem<String>(
                      value: className,
                      child: Text('$className ($count students)'),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      setState(() {
                        selectedClass = newValue;
                      });
                    }
                  },
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pushNamed(context, '/create-test');
                      },
                      icon: const Icon(Icons.add, size: 20),
                      label: const Text('Create Test'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pushNamed(context, '/ai-test-generator');
                      },
                      icon: const Icon(Icons.auto_awesome, size: 20),
                      label: const Text('Generate via DeepSeek'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF6366F1),
                        side: const BorderSide(color: Color(0xFF6366F1)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // (Announcements removed) — merged into Classroom Highlights as 24h status

  // ========== New: Gradient Stats Banner ==========
  Widget _buildGradientStatsBanner() {
    final theme = Theme.of(context);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final teacherId = authProvider.currentUser?.uid;

    Widget _stat(IconData icon, String label, String value) {
      return Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    final engagement = '82%'; // Placeholder until a real metric is defined
    final studentsCount = _students.length.toString();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFA78BFA), Color(0xFF7B61FF)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(
                theme.brightness == Brightness.dark ? 0.3 : 0.15,
              ),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            _stat(Icons.trending_up, 'Engagement', engagement),
            _stat(Icons.groups, 'Students', studentsCount),
            // Tests Assigned uses a lightweight stream count
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: teacherId == null
                    ? const Stream.empty()
                    : FirebaseFirestore.instance
                          .collection('tests')
                          .where('teacherId', isEqualTo: teacherId)
                          .snapshots(),
                builder: (context, snapshot) {
                  final count = snapshot.hasData
                      ? snapshot.data!.docs.length
                      : null;
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.assignment,
                        color: Colors.white,
                        size: 28,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Tests Assigned',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        count == null ? '—' : '$count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ========== New: Classroom Highlights ==========
  Widget _buildClassroomHighlights() {
    final theme = Theme.of(context);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;
    final instituteId =
        currentUser?.instituteId ?? _teacherData?['schoolCode'] ?? '';
    final titleStyle = TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.bold,
      color: theme.brightness == Brightness.dark
          ? theme.colorScheme.onSurface
          : theme.textTheme.bodyLarge?.color,
    );

    Widget gradientRingAvatar(String imageUrl, String caption) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFA78BFA), Color(0xFF7B61FF)],
              ),
            ),
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                image: DecorationImage(
                  image: NetworkImage(imageUrl),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 90,
            child: Text(
              caption,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.brightness == Brightness.dark
                    ? theme.colorScheme.onSurface.withOpacity(0.8)
                    : theme.textTheme.bodyMedium?.color?.withOpacity(0.8),
              ),
            ),
          ),
        ],
      );
    }

    Widget textOnlyAvatar(String text) {
      final bg = theme.brightness == Brightness.dark
          ? const Color(0xFF1F2937)
          : const Color(0xFFE8E9EB);
      final fg = theme.brightness == Brightness.dark
          ? theme.colorScheme.onSurface
          : const Color(0xFF111827);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bg,
              border: Border.all(color: const Color(0xFFA78BFA), width: 2),
            ),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(8),
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                color: fg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 90,
            child: Text(
              'Text',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.brightness == Brightness.dark
                    ? theme.colorScheme.onSurface.withOpacity(0.8)
                    : theme.textTheme.bodyMedium?.color?.withOpacity(0.8),
              ),
            ),
          ),
        ],
      );
    }

    Widget addHighlightButton() {
      final accent = const Color(0xFFF27F0D);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: accent, width: 2),
            ),
            child: IconButton(
              icon: Icon(Icons.add, color: accent, size: 28),
              onPressed: () => _showCreateHighlightSheet(),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Add',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.brightness == Brightness.dark
                  ? theme.colorScheme.onSurface.withOpacity(0.8)
                  : theme.textTheme.bodyMedium?.color?.withOpacity(0.8),
            ),
          ),
        ],
      );
    }

    if (selectedClass == null || selectedClass!.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Classroom Highlights', style: titleStyle),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Select a class to view and post highlights.',
              style: TextStyle(color: theme.textTheme.bodyMedium?.color),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('Classroom Highlights', style: titleStyle),
        ),
        SizedBox(
          height: 110,
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('class_highlights')
                .where('className', isEqualTo: selectedClass)
                .snapshots(),
            builder: (context, snapshot) {
              final docs = snapshot.data?.docs ?? [];
              final now = DateTime.now();
              // Filter by institute (client-side) and expiry, then sort by createdAt desc
              final items =
                  docs.where((d) {
                    final data = d.data();
                    final instituteOk =
                        (data['instituteId'] as String?) == instituteId;
                    final ts = (data['expiresAt'] as Timestamp?)?.toDate();
                    final notExpired = ts == null || ts.isAfter(now);
                    return instituteOk && notExpired;
                  }).toList()..sort((a, b) {
                    final ad = a.data();
                    final bd = b.data();
                    final at =
                        (ad['createdAt'] as Timestamp?)?.toDate() ??
                        DateTime.fromMillisecondsSinceEpoch(0);
                    final bt =
                        (bd['createdAt'] as Timestamp?)?.toDate() ??
                        DateTime.fromMillisecondsSinceEpoch(0);
                    return bt.compareTo(at);
                  });

              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemBuilder: (context, index) {
                  if (index == 0) return addHighlightButton();
                  final data = items[index - 1].data();
                  final img = (data['imageUrl'] as String?) ?? '';
                  final text = (data['text'] as String?)?.trim() ?? '';
                  final caption =
                      (data['caption'] as String?)?.trim() ??
                      (text.isNotEmpty ? text : 'Update');
                  final clipped = caption.length > 22
                      ? caption.substring(0, 22) + '…'
                      : caption;
                  if (img.isNotEmpty) {
                    return GestureDetector(
                      onTap: () => _openHighlightViewer(data),
                      child: gradientRingAvatar(img, clipped),
                    );
                  }
                  return GestureDetector(
                    onTap: () => _openHighlightViewer(data),
                    child: textOnlyAvatar(clipped),
                  );
                },
                separatorBuilder: (_, __) => const SizedBox(width: 16),
                itemCount: (items.length) + 1,
              );
            },
          ),
        ),
      ],
    );
  }

  void _openHighlightViewer(Map<String, dynamic> data) {
    final theme = Theme.of(context);
    final img = (data['imageUrl'] as String?) ?? '';
    final text = (data['text'] as String?) ?? '';
    final author = (data['teacherName'] as String?) ?? 'Teacher';
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
    final expiresAt = (data['expiresAt'] as Timestamp?)?.toDate();
    final timeLeft = expiresAt == null
        ? ''
        : _formatDuration(expiresAt.difference(DateTime.now()));
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: theme.dialogBackgroundColor,
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(16),
          width: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    child: Text(author.isNotEmpty ? author[0] : 'T'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          author,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (createdAt != null)
                          Text(
                            '${createdAt.toLocal()}' +
                                (timeLeft.isNotEmpty
                                    ? '  •  $timeLeft left'
                                    : ''),
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.textTheme.bodyMedium?.color,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (img.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 4 / 5,
                    child: Image.network(img, fit: BoxFit.cover),
                  ),
                ),
              if (text.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(text, style: const TextStyle(fontSize: 16)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d.isNegative) return 'expired';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  Future<void> _showCreateHighlightSheet() async {
    final theme = Theme.of(context);
    final textController = TextEditingController();
    XFile? pickedXFile;
    Uint8List? previewBytes;
    String? imageMime;
    bool posting = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            Future<void> pickImage() async {
              final picker = ImagePicker();
              final x = await picker.pickImage(
                source: ImageSource.gallery,
                imageQuality: 85,
              );
              if (x != null) {
                try {
                  final bytes = await x.readAsBytes();
                  String? mime;
                  final p = x.path.toLowerCase();
                  if (p.endsWith('.png')) mime = 'image/png';
                  if (p.endsWith('.jpg') || p.endsWith('.jpeg'))
                    mime = 'image/jpeg';
                  setSheetState(() {
                    pickedXFile = x;
                    previewBytes = bytes;
                    imageMime = mime ?? 'image/jpeg';
                  });
                } catch (_) {}
              }
            }

            Future<void> post() async {
              if (posting) return;
              setSheetState(() => posting = true);
              try {
                await _postHighlight(
                  text: textController.text.trim(),
                  imageBytes: previewBytes,
                  imageMime: imageMime,
                );
                if (mounted) Navigator.of(ctx).pop();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Highlight posted for 24 hours.'),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Failed to post: $e')));
                }
              } finally {
                if (mounted) setSheetState(() => posting = false);
              }
            }

            final kbInsets = MediaQuery.of(ctx).viewInsets.bottom;
            return Padding(
              padding: EdgeInsets.only(bottom: kbInsets),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.bolt, color: Color(0xFF6366F1)),
                          const SizedBox(width: 8),
                          Text(
                            'New Classroom Highlight',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: theme.textTheme.bodyLarge?.color,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: textController,
                        minLines: 1,
                        maxLines: 5,
                        decoration: InputDecoration(
                          hintText:
                              'Share a class achievement or note (optional)…',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: pickImage,
                            icon: const Icon(Icons.image_outlined),
                            label: const Text('Add Image'),
                          ),
                          const SizedBox(width: 12),
                          if (previewBytes != null)
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(
                                  previewBytes!,
                                  height: 80,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: posting ? null : post,
                          icon: posting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.send),
                          label: Text(posting ? 'Posting…' : 'Post (24h)'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _postHighlight({
    String? text,
    Uint8List? imageBytes,
    String? imageMime,
  }) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;
    if (currentUser == null) throw 'User not logged in';
    if ((text == null || text.isEmpty) && imageBytes == null) {
      throw 'Add text or image to post.';
    }
    if (selectedClass == null || selectedClass!.isEmpty) {
      throw 'Select a class first.';
    }

    String? imageUrl;
    if (imageBytes != null) {
      try {
        final fileName =
            'highlight_${currentUser.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        // Simplified path to avoid nested folder issues
        final ref = FirebaseStorage.instance.ref().child(
          'class_highlights/$fileName',
        );
        final metadata = SettableMetadata(
          contentType: imageMime ?? 'image/jpeg',
          customMetadata: {
            'teacherId': currentUser.uid,
            'className': selectedClass ?? '',
            'instituteId':
                currentUser.instituteId ?? _teacherData?['schoolCode'] ?? '',
          },
        );
        final task = await ref.putData(imageBytes, metadata);
        imageUrl = await task.ref.getDownloadURL();
      } catch (e) {
        // ignore: avoid_print
        print('❌ Storage upload error: $e');
        rethrow;
      }
    }

    final now = DateTime.now();
    final expiresAt = now.add(const Duration(hours: 24));
    final data = <String, dynamic>{
      'teacherId': currentUser.uid,
      'teacherName':
          _teacherData?['teacherName'] ?? currentUser.name ?? 'Teacher',
      'teacherEmail': currentUser.email,
      'instituteId':
          currentUser.instituteId ?? _teacherData?['schoolCode'] ?? '',
      'className': selectedClass,
      'text': text ?? '',
      'imageUrl': imageUrl ?? '',
      'createdAt': FieldValue.serverTimestamp(),
      // also store client timestamps for queries without server latency
      'createdAtClient': Timestamp.fromDate(now),
      'expiresAt': Timestamp.fromDate(expiresAt),
    };
    await FirebaseFirestore.instance.collection('class_highlights').add(data);
  }

  Widget _buildClassSummary() {
    List<Map<String, dynamic>> filteredStudents = _students;

    if (selectedClass != null && selectedClass!.isNotEmpty) {
      final parts = selectedClass!.split(' - ');
      if (parts.length == 2) {
        final selectedGrade = parts[0].trim();
        final selectedSection = parts[1].trim();

        filteredStudents = _students.where((student) {
          final studentClassName = student['className']?.toString() ?? '';
          final studentGrade = studentClassName
              .replaceAll('Grade ', '')
              .replaceAll('grade ', '')
              .trim();
          final studentSection = student['section']?.toString() ?? '';

          return studentGrade == selectedGrade &&
              studentSection == selectedSection;
        }).toList();
      }
    }

    final totalStudents = filteredStudents.length;
    final totalAllStudents = _students.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Class Summary',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                icon: Icons.people,
                iconColor: Colors.green,
                iconBgColor: Colors.green.withOpacity(0.1),
                value: '$totalStudents',
                label: 'Students in Class',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildSummaryCard(
                icon: Icons.school,
                iconColor: Colors.orange,
                iconBgColor: Colors.orange.withOpacity(0.1),
                value: '$totalAllStudents',
                label: 'Total Students',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconBgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.color?.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlerts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Alerts',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '0',
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyMedium?.color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Column(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 48,
                  color: Theme.of(context).iconTheme.color?.withOpacity(0.5),
                ),
                const SizedBox(height: 12),
                Text(
                  'No pending alerts',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentActivity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Activity',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Column(
              children: [
                Icon(
                  Icons.history,
                  size: 48,
                  color: Theme.of(context).iconTheme.color?.withOpacity(0.5),
                ),
                const SizedBox(height: 12),
                Text(
                  'No recent activity',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomNavigationBar() {
    return const TeacherBottomNav(selectedIndex: 0);
  }

  // _buildNavItem removed in favor of shared TeacherBottomNav
}
