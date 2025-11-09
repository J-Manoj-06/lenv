import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/test_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/test_provider.dart';
import '../../widgets/teacher_bottom_nav.dart';

class TestsScreen extends StatefulWidget {
  const TestsScreen({Key? key}) : super(key: key);

  @override
  State<TestsScreen> createState() => _TestsScreenState();
}

class _TestsScreenState extends State<TestsScreen> {
  final TextEditingController _searchController = TextEditingController();
  int _selectedTabIndex = 0;
  String _selectedClassFilter = 'All Classes';

  @override
  void initState() {
    super.initState();
    // Load tests for the current teacher after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final user = auth.currentUser;
      if (user != null) {
        Provider.of<TestProvider>(
          context,
          listen: false,
        ).loadTestsByTeacher(user.uid);
      }
    });
  }

  final List<String> _tabs = ['All', 'Live', 'Scheduled', 'Past'];
  List<String> _buildClassFilters(List<TestModel> tests) {
    final set = <String>{'All Classes'};
    for (final t in tests) {
      final label = (t.className ?? '').isNotEmpty
          ? (t.section != null && (t.section ?? '').isNotEmpty
                ? '${t.className} - ${t.section}'
                : t.className!)
          : (t.subject.isNotEmpty ? t.subject : '');
      if (label.isNotEmpty) set.add(label);
    }
    return set.toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final testProv = Provider.of<TestProvider>(context);
    final tests = testProv.tests;
    final filters = _buildClassFilters(tests);
    if (!filters.contains(_selectedClassFilter)) {
      _selectedClassFilter = 'All Classes';
    }

    final filtered = _applyFilters(tests);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Column(
            children: [
              _buildHeader(),
              _buildSearchBar(),
              _buildTabs(),
              _buildClassFiltersRow(filters),
              Expanded(
                child: testProv.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : filtered.isEmpty
                    ? const Center(child: Text('No tests found'))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                        itemCount: filtered.length,
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _buildTestCardFromModel(filtered[i]),
                        ),
                      ),
              ),
            ],
          ),
          _buildFAB(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(color: Theme.of(context).cardColor),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(width: 48),
              Text(
                'Tests',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                iconSize: 24,
                color: Theme.of(context).iconTheme.color,
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Notifications')),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Theme.of(context).cardColor,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search by test name...',
          hintStyle: TextStyle(color: Theme.of(context).hintColor),
          prefixIcon: Icon(
            Icons.search,
            color: Theme.of(context).iconTheme.color,
          ),
          filled: true,
          fillColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.grey[800]
              : const Color(0xFFF6F7F8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        onChanged: (value) {
          setState(() {});
        },
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      color: Theme.of(context).cardColor,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: List.generate(_tabs.length, (index) {
          final isSelected = _selectedTabIndex == index;
          return Expanded(
            child: InkWell(
              onTap: () {
                setState(() {
                  _selectedTabIndex = index;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isSelected
                          ? const Color(0xFF6366F1)
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
                child: Text(
                  _tabs[index],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isSelected
                        ? const Color(0xFF6366F1)
                        : Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildClassFiltersRow(List<String> classFilters) {
    return Container(
      color: Theme.of(context).cardColor,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // All Classes dropdown
            InkWell(
              onTap: () {
                _showClassFilterSheet();
              },
              child: Container(
                height: 32,
                padding: const EdgeInsets.only(left: 16, right: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _selectedClassFilter,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF6366F1),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.expand_more,
                      size: 18,
                      color: Color(0xFF6366F1),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Individual class filters
            ...(classFilters.skip(1).map((className) {
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _selectedClassFilter = className;
                    });
                  },
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.grey[800]
                          : const Color(0xFFF6F7F8),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      child: Text(
                        className,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList()),
          ],
        ),
      ),
    );
  }

  List<TestModel> _applyFilters(List<TestModel> tests) {
    final query = _searchController.text.trim().toLowerCase();
    DateTime now = DateTime.now();
    bool matchesTab(TestModel t) {
      final isLive = t.startDate.isBefore(now) && t.endDate.isAfter(now);
      final isScheduled = t.startDate.isAfter(now);
      final isPast = t.endDate.isBefore(now);
      switch (_selectedTabIndex) {
        case 1:
          return isLive;
        case 2:
          return isScheduled;
        case 3:
          return isPast;
        default:
          return true;
      }
    }

    bool matchesClass(TestModel t) {
      if (_selectedClassFilter == 'All Classes') return true;
      final label = (t.className ?? '').isNotEmpty
          ? (t.section != null && (t.section ?? '').isNotEmpty
                ? '${t.className} - ${t.section}'
                : t.className!)
          : (t.subject.isNotEmpty ? t.subject : '');
      return label == _selectedClassFilter;
    }

    bool matchesSearch(TestModel t) {
      if (query.isEmpty) return true;
      return t.title.toLowerCase().contains(query) ||
          t.subject.toLowerCase().contains(query);
    }

    final filtered = tests
        .where(matchesTab)
        .where(matchesClass)
        .where(matchesSearch)
        .toList();
    filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return filtered;
  }

  Widget _buildTestCardFromModel(TestModel t) {
    final now = DateTime.now();
    final isLive = t.startDate.isBefore(now) && t.endDate.isAfter(now);
    final isScheduled = t.startDate.isAfter(now);
    final statusText = isLive ? 'Live' : (isScheduled ? 'Scheduled' : 'Past');
    final statusColor = isLive
        ? const Color(0xFF10B981)
        : (isScheduled ? const Color(0xFF6366F1) : const Color(0xFF1F2937));
    final statusBg = isLive
        ? const Color(0xFFD1FAE5)
        : (isScheduled
              ? const Color(0xFF6366F1).withOpacity(0.2)
              : const Color(0xFFE5E7EB));

    final subtitle = (t.className ?? '').isNotEmpty
        ? (t.section != null && (t.section ?? '').isNotEmpty
              ? '${t.className} - ${t.section}'
              : t.className!)
        : t.subject;

    String footerText;
    IconData footerIcon;
    Color footerIconColor;
    if (isLive) {
      final remaining = t.endDate.difference(now);
      final hh = remaining.inHours.toString().padLeft(2, '0');
      final mm = (remaining.inMinutes % 60).toString().padLeft(2, '0');
      final ss = (remaining.inSeconds % 60).toString().padLeft(2, '0');
      footerText = 'Ends in: $hh:$mm:$ss';
      footerIcon = Icons.timer_outlined;
      footerIconColor = const Color(0xFF6366F1);
    } else if (isScheduled) {
      footerText = _formatDateTime(t.startDate);
      footerIcon = Icons.calendar_today_outlined;
      footerIconColor = const Color(0xFF6B7280);
    } else {
      footerText = 'Total: ${t.totalPoints} pts';
      footerIcon = Icons.leaderboard_outlined;
      footerIconColor = const Color(0xFF6366F1);
    }

    return _buildTestCard(
      testId: t.id,
      title: t.title,
      subtitle: subtitle,
      status: statusText,
      statusColor: statusColor,
      statusBgColor: statusBg,
      footerIcon: footerIcon,
      footerText: footerText,
      footerIconColor: footerIconColor,
      showEditButton: false,
      showDeleteButton: true,
      showStatsButton: !isScheduled,
      onDelete: () async {
        final prov = Provider.of<TestProvider>(context, listen: false);
        final ok = await prov.deleteTest(t.id);
        if (ok && mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Deleted ${t.title}')));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to delete: ${prov.errorMessage ?? 'Unknown error'}',
              ),
            ),
          );
        }
      },
    );
  }

  String _formatDateTime(DateTime dt) {
    final y = dt.year;
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/$y, $hh:$mm';
  }

  Widget _buildTestCard({
    String? testId,
    required String title,
    required String subtitle,
    required String status,
    required Color statusColor,
    required Color statusBgColor,
    required IconData footerIcon,
    required String footerText,
    required Color footerIconColor,
    bool showEditButton = false,
    bool showDeleteButton = false,
    bool showStatsButton = false,
    Future<void> Function()? onDelete,
  }) {
    return InkWell(
      onTap: () {
        Navigator.pushNamed(
          context,
          '/test-result',
          arguments: {
            'testId': testId ?? '',
            'name': title,
            'class': subtitle,
            'status': status,
            'endTime': footerText.contains('Ends in')
                ? footerText.replaceAll('Ends in: ', '')
                : footerText.replaceAll(
                    '28 Oct 2023, 10:00 AM',
                    '24 Oct 2023, 10:00 AM',
                  ),
          },
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusBgColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Footer
            Container(
              padding: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(footerIcon, size: 18, color: footerIconColor),
                      const SizedBox(width: 8),
                      Text(
                        footerText,
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      if (showStatsButton)
                        IconButton(
                          icon: const Icon(Icons.bar_chart_outlined),
                          iconSize: 20,
                          color: Theme.of(
                            context,
                          ).iconTheme.color?.withOpacity(0.6),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('View stats for $title')),
                            );
                          },
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(),
                        ),
                      if (showEditButton)
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          iconSize: 20,
                          color: Theme.of(
                            context,
                          ).iconTheme.color?.withOpacity(0.6),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Edit $title')),
                            );
                          },
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(),
                        ),
                      if (showDeleteButton)
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          iconSize: 20,
                          color: Theme.of(
                            context,
                          ).iconTheme.color?.withOpacity(0.6),
                          onPressed: () {
                            if (onDelete != null) {
                              _showDeleteDialogConfirm(title, onDelete);
                            }
                          },
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFAB() {
    return Positioned(
      bottom: 100,
      right: 24,
      child: FloatingActionButton(
        onPressed: () {
          Navigator.pushNamed(context, '/create-test');
        },
        backgroundColor: const Color(0xFF6366F1),
        child: const Icon(Icons.add, size: 30, color: Colors.white),
      ),
    );
  }

  Widget _buildBottomNav() {
    return const Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: TeacherBottomNav(selectedIndex: 2),
    );
  }

  void _showClassFilterSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: Theme.of(context).cardColor,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Filter by Class',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 16),
              ..._buildClassFilters(
                Provider.of<TestProvider>(context, listen: false).tests,
              ).map((className) {
                return ListTile(
                  title: Text(
                    className,
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  trailing: _selectedClassFilter == className
                      ? const Icon(Icons.check, color: Color(0xFF6366F1))
                      : null,
                  onTap: () {
                    setState(() {
                      _selectedClassFilter = className;
                    });
                    Navigator.pop(context);
                  },
                );
              }).toList(),
            ],
          ),
        );
      },
    );
  }

  void _showDeleteDialogConfirm(
    String testName,
    Future<void> Function() onConfirm,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Test'),
          content: Text('Are you sure you want to delete "$testName"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await onConfirm();
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }
}
