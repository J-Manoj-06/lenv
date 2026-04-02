import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../services/student_usage_service.dart';

class AppUsageCard extends StatefulWidget {
  final String studentId;
  final int refreshTrigger;

  const AppUsageCard({
    super.key,
    required this.studentId,
    this.refreshTrigger = 0,
  });

  @override
  State<AppUsageCard> createState() => _AppUsageCardState();
}

class _AppUsageCardState extends State<AppUsageCard> {
  final StudentUsageService _usageService = StudentUsageService();
  late Future<StudentDailyUsage?> _usageFuture;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _loadUsage();
  }

  void _loadUsage({bool forceRefresh = false}) {
    _usageFuture = _usageService.getTodayUsageForStudent(
      studentId: widget.studentId,
      forceRefresh: forceRefresh,
    );
  }

  Future<void> _refresh() async {
    setState(() => _isRefreshing = true);
    await _usageService.collectAndSyncTodayUsage(studentId: widget.studentId);
    _loadUsage();
    // Wait for at least one second to show refresh indicator
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      setState(() => _isRefreshing = false);
    }
  }

  @override
  void didUpdateWidget(AppUsageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.studentId != widget.studentId ||
        oldWidget.refreshTrigger != widget.refreshTrigger) {
      _loadUsage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FutureBuilder<StudentDailyUsage?>(
      future: _usageFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildSkeletonCard(isDark);
        }

        if (snapshot.hasError) {
          debugPrint(
            '❌ [AppUsageCard] load error studentId=${widget.studentId} '
            'error=${snapshot.error}',
          );
          return _buildCardContainer(
            isDark,
            child: _buildSectionContent(
              context,
              title: 'Top 5 Used Apps Today',
              body: const Text('No usage data available'),
            ),
          );
        }

        final usage = snapshot.data;
        if (usage == null) {
          return _buildCardContainer(
            isDark,
            child: _buildSectionContent(
              context,
              title: 'Top 5 Used Apps Today',
              body: const Text('No usage data available'),
            ),
          );
        }

        if (!usage.permissionEnabled) {
          return _buildCardContainer(
            isDark,
            child: _buildSectionContent(
              context,
              title: 'Top 5 Used Apps Today',
              body: const Text('App usage permission not enabled'),
            ),
          );
        }

        final allApps = usage.allApps.isNotEmpty
            ? usage.allApps
            : usage.topApps;
        final apps = allApps;
        final isTodayData = _isUsageDateToday(usage.date);
        final usageDateLabel = _formatUsageDateLabel(usage.date);
        if (apps.isEmpty) {
          return _buildCardContainer(
            isDark,
            child: _buildSectionContent(
              context,
              title: 'Top 5 Used Apps Today',
              body: const Text('No usage data available'),
            ),
          );
        }

        final itemCount = apps.length > 5 ? 5 : apps.length;
        final consideredCount = usage.consideredAppCount;

        return _buildCardContainer(
          isDark,
          child: _buildSectionContent(
            context,
            title: isTodayData
                ? 'Top 5 Used Apps Today'
                : 'Top 5 Used Apps ($usageDateLabel)',
            body: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      isTodayData
                          ? 'Showing data for today ($usageDateLabel)'
                          : 'Showing data from $usageDateLabel',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isTodayData
                            ? (isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight)
                            : Colors.orangeAccent,
                        fontWeight: isTodayData
                            ? FontWeight.w400
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                if (consideredCount != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Based on $consideredCount installed apps',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondaryLight,
                        ),
                      ),
                    ),
                  ),
                ListView.builder(
                  itemCount: itemCount,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemBuilder: (context, index) {
                    final app = apps[index];
                    return _buildAppRow(
                      context,
                      app: app,
                      isDark: isDark,
                      showIcon: true,
                      isLast: index == itemCount - 1,
                    );
                  },
                ),
                if (apps.length > itemCount) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => _showAllAppsBottomSheet(
                        context,
                        apps,
                        isDark,
                        usageDateLabel,
                        isTodayData,
                      ),
                      child: Text(
                        'View More (${apps.length - itemCount} more)',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAppRow(
    BuildContext context, {
    required AppUsageItem app,
    required bool isDark,
    required bool isLast,
    required bool showIcon,
  }) {
    final iconBytes = showIcon
        ? _usageService.decodeIcon(app.appIconBase64)
        : null;

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.primary.withValues(alpha: 0.16),
            backgroundImage: iconBytes != null ? MemoryImage(iconBytes) : null,
            child: iconBytes == null
                ? const Icon(Icons.apps_rounded, color: AppColors.primary)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app.appName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  app.packageName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            StudentUsageService.formatMinutes(app.usageMinutes),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  void _showAllAppsBottomSheet(
    BuildContext context,
    List<AppUsageItem> apps,
    bool isDark,
    String usageDateLabel,
    bool isTodayData,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1F1F1F) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isTodayData
                          ? 'All App Usage Today'
                          : 'All App Usage ($usageDateLabel)',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${apps.length} apps',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: apps.length,
                    itemBuilder: (context, index) {
                      return _buildAppRow(
                        context,
                        app: apps[index],
                        isDark: isDark,
                        showIcon: true,
                        isLast: index == apps.length - 1,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _isUsageDateToday(String usageDate) {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final today = '${now.year}-$month-$day';
    return usageDate == today;
  }

  String _formatUsageDateLabel(String usageDate) {
    final parsed = DateTime.tryParse(usageDate);
    if (parsed == null) return usageDate;
    final month = parsed.month.toString().padLeft(2, '0');
    final day = parsed.day.toString().padLeft(2, '0');
    return '$day-$month-${parsed.year}';
  }

  Widget _buildSectionContent(
    BuildContext context, {
    required String title,
    required Widget body,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            if (_isRefreshing)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _refresh,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                padding: EdgeInsets.zero,
              ),
          ],
        ),
        const SizedBox(height: 12),
        body,
      ],
    );
  }

  Widget _buildCardContainer(bool isDark, {required Widget child}) {
    return Card(
      elevation: isDark ? 0 : 2,
      color: isDark ? const Color(0xFF1F1F1F) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }

  Widget _buildSkeletonCard(bool isDark) {
    return _buildCardContainer(
      isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 18,
            width: 190,
            decoration: BoxDecoration(
              color: (isDark ? Colors.white : Colors.black).withValues(
                alpha: 0.10,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(height: 14),
          for (int i = 0; i < 5; i++) ...[
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: (isDark ? Colors.white : Colors.black)
                      .withValues(alpha: 0.10),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 14,
                        width: 150,
                        decoration: BoxDecoration(
                          color: (isDark ? Colors.white : Colors.black)
                              .withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        height: 12,
                        width: 110,
                        decoration: BoxDecoration(
                          color: (isDark ? Colors.white : Colors.black)
                              .withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  height: 12,
                  width: 45,
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : Colors.black).withValues(
                      alpha: 0.10,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            ),
            if (i != 4) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}
