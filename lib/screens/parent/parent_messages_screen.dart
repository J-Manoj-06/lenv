import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/parent_provider.dart';
import '../../widgets/student_selection/student_avatar_row.dart';
import '../../services/offline_data_service.dart';
import 'parent_profile_screen.dart';
import '../../services/whatsapp_chat_service.dart';

class ParentMessagesScreen extends StatefulWidget {
  const ParentMessagesScreen({super.key});

  @override
  State<ParentMessagesScreen> createState() => _ParentMessagesScreenState();
}

class _ParentMessagesScreenState extends State<ParentMessagesScreen> {
  static const Color parentGreen = Color(0xFF14A670);
  static const Color backgroundLight = Color(0xFFF6F6F8);
  static const Color backgroundDark = Color(0xFF151022);
  static const Color cardBg = Colors.white;
  static const Color textPrimary = Color(0xFF110D1B);

  final OfflineDataService _offlineService = OfflineDataService();
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _teachers = [];
  List<Map<String, dynamic>> _filteredTeachers = [];
  final Map<String, List<Map<String, dynamic>>> _teachersCache = {};
  bool _isLoading = true;
  bool _queuedReload = false;
  String? _lastLoadedChildId; // Track which child we loaded teachers for

  double _contentBottomInset(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    return 24 + 64 + safeBottom;
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTeachers(force: true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload teachers if selected child has changed
    final parentProvider = Provider.of<ParentProvider>(context, listen: false);
    final currentChildId = parentProvider.selectedChild?.uid;

    if (currentChildId != _lastLoadedChildId && currentChildId != null) {
      _lastLoadedChildId = currentChildId;
      if (!_isLoading) {
        _loadTeachers();
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredTeachers = _teachers;
      } else {
        _filteredTeachers = _teachers.where((teacher) {
          final name = (teacher['name'] as String? ?? '').toLowerCase();
          final subject = (teacher['subject'] as String? ?? '').toLowerCase();
          return name.contains(query) || subject.contains(query);
        }).toList();
      }
    });
  }

  Future<void> _loadTeachers({bool force = false}) async {
    final parentProvider = Provider.of<ParentProvider>(context, listen: false);

    final child = parentProvider.selectedChild;

    // If we have cached teachers for this child and not forcing, show immediately
    if (!force && child != null && _teachersCache.containsKey(child.uid)) {
      setState(() {
        _teachers = _teachersCache[child.uid]!;
        _filteredTeachers = _teachers;
        _isLoading = false;
        _lastLoadedChildId = child.uid;
      });
      return;
    }

    // ✅ Try loading from offline cache first for instant display
    if (child != null) {
      final cachedTeachers = _offlineService.getCachedParentTeachers(child.uid);
      if (cachedTeachers != null && cachedTeachers.isNotEmpty) {
        setState(() {
          _teachers = cachedTeachers;
          _filteredTeachers = _teachers;
          _teachersCache[child.uid] = _teachers;
          _isLoading = false;
          _lastLoadedChildId = child.uid;
        });
      }
    }

    setState(() => _isLoading = true);

    try {
      if (!parentProvider.hasChildren) {
        setState(() {
          _isLoading = false;
          _teachers = [];
          _filteredTeachers = [];
        });
        return;
      }

      // Get only the SELECTED child's teachers
      final child = parentProvider.selectedChild;
      if (child == null) {
        setState(() {
          _isLoading = false;
          _teachers = [];
          _filteredTeachers = [];
        });
        return;
      }

      // Track which child we are loading for (handles mid-load switches)
      _lastLoadedChildId = child.uid;

      final Set<String> teacherIds = {};
      final List<Map<String, dynamic>> teachersList = [];

      // Get selected child's class info
      if (child.className != null && child.schoolCode != null) {
        final studentClass = child.className!;
        final studentSection = child.section ?? '';

        // Build efficient token for arrayContains query
        // Token format: "Grade 10|A" or "Grade 10|" if no section
        final token = studentSection.isEmpty
            ? '$studentClass|'
            : '$studentClass|$studentSection';

        // OPTIMIZED: Single query with arrayContains on indexed field
        final teachersSnapshot = await FirebaseFirestore.instance
            .collection('teachers')
            .where('schoolCode', isEqualTo: child.schoolCode)
            .where('classAssignmentTokens', arrayContains: token)
            .get();

        // Fallback: if tokens are not populated, use legacy parsing
        final docsToScan = teachersSnapshot.docs.isNotEmpty
            ? teachersSnapshot.docs
            : (await FirebaseFirestore.instance
                      .collection('teachers')
                      .where('schoolCode', isEqualTo: child.schoolCode)
                      .get())
                  .docs;

        if (teachersSnapshot.docs.isEmpty) {
        } else {}

        for (final doc in docsToScan) {
          final data = doc.data();
          final teacherId = doc.id;

          // If using token query, any doc here is a match.
          // If falling back, we need to check classAssignments.
          bool matches = teachersSnapshot.docs.isNotEmpty;
          String? subject;

          if (!matches) {
            final assignments = (data['classAssignments'] as List?) ?? [];
            for (final a in assignments) {
              final str = a.toString();
              // Expect format: "Grade 10: A, math"
              if (str.contains(':')) {
                final parts = str.split(':');
                final className = parts[0].trim();
                final second = parts.length > 1 ? parts[1].trim() : '';
                final subParts = second.split(',');
                final section = subParts.isNotEmpty ? subParts[0].trim() : '';
                final subj = subParts.length > 1 ? subParts[1].trim() : '';
                if (className == studentClass &&
                    (studentSection.isEmpty || section == studentSection)) {
                  matches = true;
                  subject = subj.isNotEmpty ? subj : null;
                  break;
                }
              }
            }
          } else {
            // We can still try to extract subject for display
            final assignments = data['classAssignments'] as List?;
            if (assignments != null) {
              for (final a in assignments) {
                final str = a.toString();
                if (str.contains(studentClass) &&
                    (studentSection.isEmpty || str.contains(studentSection))) {
                  final parts = str.split(',');
                  if (parts.length > 1) {
                    subject = parts.last.trim();
                    break;
                  }
                }
              }
            }
          }

          if (matches && !teacherIds.contains(teacherId)) {
            teacherIds.add(teacherId);
            final teacherName =
                data['teacherName'] ?? data['name'] ?? 'Unknown Teacher';

            final teacherUid = (data['uid'] as String?) ?? teacherId;
            teachersList.add({
              'docId': teacherId, // Document ID for Firestore lookups
              'id': teacherUid, // Teacher UID
              'name': teacherName,
              'email': data['email'] ?? '',
              'subject': subject ?? 'General',
              'className': studentClass,
              'profileImage': data['profileImage'],
              'phoneNumber':
                  data['phoneNumber'] ??
                  data['phone'], // Include phone if available
            });
          }
        }
      }

      // Sort by name
      teachersList.sort(
        (a, b) => (a['name'] as String).compareTo(b['name'] as String),
      );

      // ✅ Cache teachers for offline access
      if (teachersList.isNotEmpty) {
        await _offlineService.cacheParentTeachers(
          childId: child.uid,
          teachers: teachersList,
        );
      }

      setState(() {
        _teachers = teachersList;
        _filteredTeachers = teachersList;
        _teachersCache[child.uid] = teachersList;
        _isLoading = false;
        _lastLoadedChildId = child.uid; // Track which child we loaded for
      });
    } catch (e) {
      // ✅ If network fails but we have cached data, keep showing it
      if (_teachers.isEmpty && child != null) {
        final cachedTeachers = _offlineService.getCachedParentTeachers(
          child.uid,
        );
        if (cachedTeachers != null && cachedTeachers.isNotEmpty) {
          setState(() {
            _teachers = cachedTeachers;
            _filteredTeachers = cachedTeachers;
            _teachersCache[child.uid] = cachedTeachers;
          });
        }
      }
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Auto-reload teachers immediately when selected child changes
    final parentProvider = Provider.of<ParentProvider>(context);
    final currentChildId = parentProvider.selectedChild?.uid;
    if (currentChildId != null &&
        currentChildId != _lastLoadedChildId &&
        !_isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadTeachers(force: true);
      });
    }

    return Scaffold(
      backgroundColor: isDark ? backgroundDark : backgroundLight,
      appBar: AppBar(
        title: const Text(
          'Messages',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: isDark ? backgroundDark : Colors.white,
        foregroundColor: isDark ? Colors.white : textPrimary,
        elevation: 0.5,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.person, size: 28),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ParentProfileScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: Consumer<ParentProvider>(
        builder: (context, parentProvider, child) {
          // If children just finished loading, auto-load teachers once
          if (parentProvider.hasChildren &&
              _teachers.isEmpty &&
              !_isLoading &&
              !_queuedReload) {
            _queuedReload = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _queuedReload = false;
              _loadTeachers();
            });
          }

          if (!parentProvider.hasChildren) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.message_outlined,
                    size: 64,
                    color: isDark ? Colors.grey[600] : Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No children found',
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              // Student Selection Row
              const StudentAvatarRow(),

              // Search Bar
              _buildSearchBar(isDark),

              // Teachers List
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            parentGreen,
                          ),
                        ),
                      )
                    : _filteredTeachers.isEmpty
                    ? _buildEmptyState(isDark)
                    : RefreshIndicator(
                        onRefresh: _loadTeachers,
                        color: parentGreen,
                        child: ListView.builder(
                          padding: EdgeInsets.fromLTRB(
                            16,
                            8,
                            16,
                            _contentBottomInset(context),
                          ),
                          itemCount: _filteredTeachers.length,
                          itemBuilder: (context, index) {
                            final teacher = _filteredTeachers[index];
                            return _buildTeacherCard(isDark, teacher);
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? backgroundDark : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white10 : Colors.grey.shade200,
          ),
        ),
      ),
      child: TextField(
        controller: _searchController,
        style: TextStyle(color: isDark ? Colors.white : textPrimary),
        decoration: InputDecoration(
          hintText: 'Search teachers...',
          hintStyle: TextStyle(
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
          prefixIcon: Icon(
            Icons.search,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  onPressed: () {
                    _searchController.clear();
                  },
                )
              : null,
          filled: true,
          fillColor: isDark ? const Color(0xFF1E1A2F) : backgroundLight,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildTeacherCard(bool isDark, Map<String, dynamic> teacher) {
    final name = teacher['name'] as String;
    final subject = teacher['subject'] as String;
    final className = teacher['className'] as String?;
    final profileImage = teacher['profileImage'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isDark ? const Color(0xFF1E1A2F) : cardBg,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isDark ? Colors.white10 : Colors.transparent),
      ),
      child: InkWell(
        onTap: () async {
          // Get selected child info
          final parentProvider = Provider.of<ParentProvider>(
            context,
            listen: false,
          );
          final child = parentProvider.selectedChild;

          if (child == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Please select a child first'),
                duration: Duration(seconds: 2),
              ),
            );
            return;
          }

          // Check if phone number is already available in cached data
          String? teacherPhone = teacher['phoneNumber'] as String?;

          // If phone not available, fetch from Firestore
          if (teacherPhone == null || teacherPhone.isEmpty) {
            // Show loading
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(parentGreen),
                ),
              ),
            );

            try {
              // Use docId for Firestore lookup
              final docId =
                  teacher['docId'] as String? ?? teacher['id'] as String;
              final teacherDoc = await FirebaseFirestore.instance
                  .collection('teachers')
                  .doc(docId)
                  .get();

              if (!mounted) return;
              Navigator.of(context).pop(); // Dismiss loading

              if (!teacherDoc.exists) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Teacher information not found'),
                    duration: Duration(seconds: 2),
                  ),
                );
                return;
              }

              final teacherData = teacherDoc.data();
              teacherPhone =
                  teacherData?['phoneNumber'] as String? ??
                  teacherData?['phone'] as String?;
            } catch (e) {
              if (mounted) {
                Navigator.of(context).pop(); // Dismiss loading
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Error fetching teacher info: ${e.toString()}',
                    ),
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
              return;
            }
          }

          if (teacherPhone == null || teacherPhone.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Teacher phone number not available'),
                duration: Duration(seconds: 3),
              ),
            );
            return;
          }

          // Format contact name: "StudentName's Subject Teacher TeacherName"
          final studentName = child.name;
          final teacherName = name.split(' ').last; // Get last name
          final contactName = "$studentName's $subject Teacher $teacherName";

          // Show opening WhatsApp message
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Opening WhatsApp...'),
              duration: Duration(seconds: 1),
            ),
          );

          // Open WhatsApp with custom contact name
          final whatsappService = WhatsAppChatService();
          final success = await whatsappService.startParentWhatsAppChat(
            studentName: contactName,
            parentPhoneNumber: teacherPhone,
          );

          if (!success && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Could not open WhatsApp. Please make sure WhatsApp is installed.',
                ),
                duration: Duration(seconds: 3),
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Profile Picture
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      parentGreen.withOpacity(0.8),
                      parentGreen.withOpacity(0.4),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: parentGreen.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: profileImage != null && profileImage.isNotEmpty
                    ? ClipOval(
                        child: Image.network(
                          profileImage,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              Icon(Icons.person, color: Colors.white, size: 28),
                        ),
                      )
                    : const Icon(Icons.person, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),

              // Teacher Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: parentGreen.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            subject,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: parentGreen,
                            ),
                          ),
                        ),
                        if (className != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            className,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Message Icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: parentGreen.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.message_outlined,
                  color: parentGreen,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: parentGreen.withOpacity(0.1),
            ),
            child: Icon(
              Icons.search_off,
              size: 60,
              color: isDark ? Colors.grey[600] : Colors.grey[400],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _searchController.text.isEmpty
                ? 'No teachers found'
                : 'No teachers match your search',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              _searchController.text.isEmpty
                  ? 'Teachers will appear here when your children are assigned to classes'
                  : 'Try searching with a different keyword',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
