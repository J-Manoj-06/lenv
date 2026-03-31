import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/app_usage_service.dart';

class StudentUsageCard extends StatelessWidget {
  final String studentName;
  final String? profileImageUrl;
  final TeacherStudentUsageSummary? usage;
  final VoidCallback? onTap;

  const StudentUsageCard({
    super.key,
    required this.studentName,
    this.profileImageUrl,
    this.usage,
    this.onTap,
  });

  static const Color _mediumColor = Color(0xFFF2800D);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      elevation: isDark ? 0 : 1.5,
      color: isDark ? const Color(0xFF1E1E2D) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAvatar(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      studentName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: isDark ? Colors.white : const Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildUsagePreview(context, isDark),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _buildPriorityBadge(isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    if (profileImageUrl != null && profileImageUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 22,
        backgroundImage: NetworkImage(profileImageUrl!),
      );
    }

    final initials = _initials(studentName);
    return CircleAvatar(
      radius: 22,
      backgroundColor: const Color(0xFF355872).withValues(alpha: 0.16),
      child: Text(
        initials,
        style: const TextStyle(
          color: Color(0xFF355872),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildPriorityBadge(bool isDark) {
    final current = usage;
    if (current == null ||
        !current.hasData ||
        current.permissionEnabled != true) {
      return _badge('No Data', Colors.grey, isDark);
    }

    switch (current.priority) {
      case UsagePriority.high:
        return _badge('High Usage', Colors.red, isDark, showAlert: true);
      case UsagePriority.medium:
        return _badge('Medium Usage', _mediumColor, isDark);
      case UsagePriority.low:
        return _badge('Low Usage', Colors.green, isDark);
      case UsagePriority.unknown:
        return _badge('No Data', Colors.grey, isDark);
    }
  }

  Widget _badge(
    String label,
    Color color,
    bool isDark, {
    bool showAlert = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.22 : 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showAlert) ...[
            Icon(Icons.priority_high_rounded, size: 13, color: color),
            const SizedBox(width: 2),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsagePreview(BuildContext context, bool isDark) {
    final current = usage;
    if (current == null || !current.hasData) {
      return Text(
        'No usage data available',
        style: TextStyle(
          color: isDark ? Colors.grey[400] : Colors.grey[600],
          fontSize: 13,
        ),
      );
    }

    if (current.permissionEnabled != true) {
      return Text(
        'Usage permission not enabled',
        style: TextStyle(
          color: isDark ? Colors.grey[400] : Colors.grey[600],
          fontSize: 13,
        ),
      );
    }

    final apps = current.topApps.take(3).toList();
    if (apps.isEmpty) {
      return Text(
        'No usage data available',
        style: TextStyle(
          color: isDark ? Colors.grey[400] : Colors.grey[600],
          fontSize: 13,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: apps.map((app) {
        final icon = _decodeIcon(app.appIconBase64);
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              CircleAvatar(
                radius: 10,
                backgroundColor: const Color(
                  0xFFF2800D,
                ).withValues(alpha: 0.12),
                backgroundImage: icon != null ? MemoryImage(icon) : null,
                child: icon == null
                    ? const Icon(
                        Icons.apps_rounded,
                        size: 12,
                        color: Color(0xFFF2800D),
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  app.appName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDark ? Colors.white : const Color(0xFF111827),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                AppUsageService.formatMinutes(app.usageMinutes),
                style: TextStyle(
                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  Uint8List? _decodeIcon(String? base64Icon) {
    if (base64Icon == null || base64Icon.trim().isEmpty) return null;
    try {
      return base64Decode(base64Icon);
    } catch (_) {
      return null;
    }
  }
}
