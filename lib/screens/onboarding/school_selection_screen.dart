import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../models/school_model.dart';
import '../../services/school_service.dart';
import '../../services/school_storage_service.dart';

/// School selection screen - users select their school here
class SchoolSelectionScreen extends StatefulWidget {
  const SchoolSelectionScreen({super.key});

  @override
  State<SchoolSelectionScreen> createState() => _SchoolSelectionScreenState();
}

class _SchoolSelectionScreenState extends State<SchoolSelectionScreen> {
  late TextEditingController _searchController;
  bool _isLoading = false;
  final SchoolService _schoolService = SchoolService();
  List<SchoolModel> _schools = [];
  bool _isLoadingSchools = true;
  String? _schoolLoadError;
  bool _schoolLoadIsWarning = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _loadSchools();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<SchoolModel> get _filteredSchools {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return _schools;
    }

    return _schools.where((school) {
      return school.name.toLowerCase().contains(query) ||
          school.id.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _loadSchools() async {
    setState(() {
      _isLoadingSchools = true;
      _schoolLoadError = null;
      _schoolLoadIsWarning = false;
    });

    try {
      final schools = await _schoolService.fetchSchools();
      if (!mounted) return;

      setState(() {
        _schools = schools;
        _isLoadingSchools = false;

        if (_schoolService.lastFetchUsedCache && schools.isNotEmpty) {
          _schoolLoadError = 'Offline mode: showing previously loaded schools.';
          _schoolLoadIsWarning = true;
        }
      });

      if (schools.isEmpty) {
        setState(() {
          _schoolLoadError = 'No schools found. Please contact admin.';
          _schoolLoadIsWarning = false;
        });
      }
    } catch (e) {
      if (!mounted) return;

      final bool isNetworkIssue = e is SchoolFetchException && e.isNetworkIssue;
      setState(() {
        _isLoadingSchools = false;
        _schoolLoadError = e is SchoolFetchException
            ? e.message
            : 'Failed to load schools.';
        _schoolLoadIsWarning = isNetworkIssue;
      });
    }
  }

  /// Select a school from the list
  Future<void> _selectSchool(SchoolModel school) async {
    setState(() => _isLoading = true);

    try {
      await schoolStorageService.initialize();
      await schoolStorageService.saveSchoolData(
        schoolId: school.id,
        schoolName: school.name,
        schoolLogo: '',
      );

      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/role-selection');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Select Your School',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: isDark ? AppColors.textLight : AppColors.textDark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isLoadingSchools
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header text
                    Text(
                      'Choose your school from the list below',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Search schools by name or ID',
                        prefixIcon: const Icon(Icons.search_rounded),
                        isDense: true,
                        filled: true,
                        fillColor: isDark
                            ? AppColors.cardBackgroundDark
                            : AppColors.cardBackground,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isDark
                                ? AppColors.dividerDark
                                : AppColors.divider,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isDark
                                ? AppColors.dividerDark
                                : AppColors.divider,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    if (_schoolLoadError != null) ...[
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: _schoolLoadIsWarning
                              ? AppColors.primary.withValues(alpha: 0.1)
                              : Colors.red.withValues(alpha: 0.12),
                          border: Border.all(
                            color: _schoolLoadIsWarning
                                ? AppColors.primary.withValues(alpha: 0.35)
                                : Colors.red.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _schoolLoadIsWarning
                                  ? Icons.wifi_off_rounded
                                  : Icons.error_outline_rounded,
                              color: _schoolLoadIsWarning
                                  ? AppColors.primary
                                  : Colors.redAccent,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _schoolLoadError!,
                                style: TextStyle(
                                  color: isDark
                                      ? AppColors.textLight
                                      : AppColors.textDark,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            if (!_schoolLoadIsWarning)
                              TextButton(
                                onPressed: _loadSchools,
                                child: const Text('Retry'),
                              ),
                          ],
                        ),
                      ),
                    ],

                    // School list
                    if (_filteredSchools.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.cardBackgroundDark
                              : AppColors.cardBackground,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? AppColors.dividerDark
                                : AppColors.divider,
                          ),
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.school_rounded, size: 40),
                            const SizedBox(height: 8),
                            Text(
                              _schools.isEmpty
                                  ? 'No schools available'
                                  : 'No schools match your search',
                              style: TextStyle(
                                color: isDark
                                    ? AppColors.textLight
                                    : AppColors.textDark,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _schools.isEmpty
                                  ? _loadSchools
                                  : () {
                                      _searchController.clear();
                                      setState(() {});
                                    },
                              child: Text(
                                _schools.isEmpty ? 'Refresh' : 'Clear Search',
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ...List.generate(
                        _filteredSchools.length,
                        (index) =>
                            _buildSchoolCard(_filteredSchools[index], isDark),
                      ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
    );
  }

  /// Build school card widget
  Widget _buildSchoolCard(SchoolModel school, bool isDark) {
    return GestureDetector(
      onTap: () => _selectSchool(school),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.cardBackgroundDark
              : AppColors.cardBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? AppColors.dividerDark : AppColors.divider,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // School Logo
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: AppColors.primary.withValues(alpha: 0.1),
              ),
              child: Icon(
                Icons.school_rounded,
                color: AppColors.primary,
                size: 40,
              ),
            ),

            const SizedBox(width: 16),

            // School Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    school.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.textLight : AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'School ID: ${school.id}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                    ),
                  ),
                ],
              ),
            ),

            // Chevron icon
            Icon(
              Icons.chevron_right_rounded,
              color: AppColors.primary,
              size: 28,
            ),
          ],
        ),
      ),
    );
  }
}
