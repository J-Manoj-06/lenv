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
  late TextEditingController _schoolIdController;
  late TextEditingController _schoolNameController;
  bool _isLoading = false;
  final SchoolService _schoolService = SchoolService();
  List<SchoolModel> _schools = [];
  bool _isLoadingSchools = true;
  String? _schoolLoadError;
  bool _schoolLoadIsWarning = false;

  @override
  void initState() {
    super.initState();
    _schoolIdController = TextEditingController();
    _schoolNameController = TextEditingController();
    _loadSchools();
  }

  @override
  void dispose() {
    _schoolIdController.dispose();
    _schoolNameController.dispose();
    super.dispose();
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

  /// Show manual school entry dialog
  void _showManualSchoolDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter School Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _schoolIdController,
              decoration: InputDecoration(
                labelText: 'School ID',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _schoolNameController,
              decoration: InputDecoration(
                labelText: 'School Name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (_schoolIdController.text.isEmpty ||
                  _schoolNameController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please fill all fields')),
                );
                return;
              }

              _selectSchool(
                SchoolModel(
                  id: _schoolIdController.text,
                  name: _schoolNameController.text,
                ),
              );

              Navigator.of(context).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Your School'),
        centerTitle: true,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isLoadingSchools
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
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
                    const SizedBox(height: 24),

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
                    if (_schools.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
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
                              'No schools available',
                              style: TextStyle(
                                color: isDark
                                    ? AppColors.textLight
                                    : AppColors.textDark,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _loadSchools,
                              child: const Text('Refresh'),
                            ),
                          ],
                        ),
                      )
                    else
                      ...List.generate(
                        _schools.length,
                        (index) => _buildSchoolCard(_schools[index], isDark),
                      ),

                    const SizedBox(height: 24),

                    // Divider
                    Divider(
                      color: isDark ? AppColors.dividerDark : AppColors.divider,
                    ),

                    const SizedBox(height: 24),

                    // Manual entry section
                    Text(
                      'Can\'t find your school?',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 12),

                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: _showManualSchoolDialog,
                        icon: const Icon(Icons.add),
                        label: const Text('Enter School Details Manually'),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                            color: AppColors.primary,
                            width: 2,
                          ),
                          foregroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),
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
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
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
              width: 70,
              height: 70,
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
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.textLight : AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'School ID: ${school.id}',
                    style: TextStyle(
                      fontSize: 12,
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
