import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../services/student_usage_service.dart';

class AppUsageCard extends StatefulWidget {
  final String studentId;

  const AppUsageCard({super.key, required this.studentId});

  @override
  State<AppUsageCard> createState() => _AppUsageCardState();
}

class _AppUsageCardState extends State<AppUsageCard> {
  final StudentUsageService _usageService = StudentUsageService();
  late Future<StudentDailyUsage?> _usageFuture;

  @override
  void initState() {
    super.initState();
    _usageFuture = _usageService.getTodayUsageForStudent(
      studentId: widget.studentId,
    );
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

        final apps = usage.topApps;
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

        return _buildCardContainer(
          isDark,
          child: _buildSectionContent(
            context,
            title: 'Top 5 Used Apps Today',
            body: ListView.builder(
              itemCount: itemCount,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (context, index) {
                final app = apps[index];
                final iconBytes = _usageService.decodeIcon(app.appIconBase64);

                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index == itemCount - 1 ? 0 : 10,
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: AppColors.primary.withValues(
                          alpha: 0.16,
                        ),
                        backgroundImage: iconBytes != null
                            ? MemoryImage(iconBytes)
                            : null,
                        child: iconBytes == null
                            ? const Icon(
                                Icons.apps_rounded,
                                color: AppColors.primary,
                              )
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
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              app.packageName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
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
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionContent(
    BuildContext context, {
    required String title,
    required Widget body,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
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
