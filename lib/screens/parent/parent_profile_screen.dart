import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/parent_provider.dart';
import '../../providers/theme_provider.dart';
import '../../models/student_model.dart';

class ParentProfileScreen extends StatelessWidget {
  const ParentProfileScreen({super.key});

  static const Color parentGreen = Color(0xFF14A670);
  static const Color backgroundLight = Color(0xFFF6F6F8);
  static const Color backgroundDark = Color(0xFF151022);
  static const Color cardBg = Colors.white;
  static const Color textPrimary = Color(0xFF110D1B);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Consumer2<AuthProvider, ParentProvider>(
      builder: (context, authProvider, parentProvider, child) {
        final user = authProvider.currentUser;

        return Scaffold(
          backgroundColor: isDark ? backgroundDark : backgroundLight,
          appBar: AppBar(
            backgroundColor: isDark ? backgroundDark : backgroundLight,
            elevation: 0,
            title: Text(
              'Profile',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : textPrimary,
              ),
            ),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Parent Info Card
                  _buildParentInfoCard(
                    isDark,
                    user?.name,
                    user?.email,
                    user?.profileImage,
                  ),

                  const SizedBox(height: 24),

                  // Notification Preferences
                  _buildNotificationsCard(context, isDark, parentProvider),

                  const SizedBox(height: 24),

                  // Linked Children
                  _buildChildrenList(context, isDark, parentProvider.children),

                  const SizedBox(height: 24),

                  // App Settings + Logout
                  _buildSettingsAndLogout(context, isDark, authProvider),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildParentInfoCard(
    bool isDark,
    String? name,
    String? email,
    String? photoUrl,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? backgroundDark.withOpacity(0.5) : cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.1) : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: parentGreen.withOpacity(0.2),
            ),
            child: photoUrl != null
                ? ClipOval(child: Image.network(photoUrl, fit: BoxFit.cover))
                : const Icon(Icons.person, color: parentGreen, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name ?? 'Parent',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  email ?? '-',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationsCard(
    BuildContext context,
    bool isDark,
    ParentProvider parentProvider,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? backgroundDark.withOpacity(0.5) : cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.1) : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Notifications',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Enable notifications',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                ),
              ),
              Switch(
                value: parentProvider.notificationsEnabled,
                activeThumbColor: parentGreen,
                onChanged: (value) {
                  parentProvider.setNotificationsEnabled(value);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChildrenList(
    BuildContext context,
    bool isDark,
    List<StudentModel> children,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Linked Children',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        if (children.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? backgroundDark.withOpacity(0.5) : cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.1)
                    : Colors.transparent,
              ),
            ),
            child: Center(
              child: Text(
                'No linked children',
                style: TextStyle(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
            ),
          )
        else
          Column(
            children: children.map((c) {
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? backgroundDark.withOpacity(0.5) : cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withOpacity(0.1)
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: parentGreen.withOpacity(0.2),
                      ),
                      child: c.photoUrl != null
                          ? ClipOval(
                              child: Image.network(
                                c.photoUrl!,
                                fit: BoxFit.cover,
                              ),
                            )
                          : const Icon(
                              Icons.person,
                              color: parentGreen,
                              size: 22,
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.name,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${c.className ?? "N/A"}${c.section != null ? " - ${c.section}" : ""}',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        // Select child and navigate to profile
                        final index = children.indexWhere(
                          (s) => s.uid == c.uid,
                        );
                        if (index != -1) {
                          Provider.of<ParentProvider>(
                            context,
                            listen: false,
                          ).selectChild(index);
                          Navigator.pushNamed(
                            context,
                            '/parent/child-profile',
                          ).then((_) {
                            // Return to parent profile
                          });
                        }
                      },
                      child: const Text(
                        'View',
                        style: TextStyle(color: parentGreen),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildSettingsAndLogout(
    BuildContext context,
    bool isDark,
    AuthProvider authProvider,
  ) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? backgroundDark.withOpacity(0.5) : cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.1)
                  : Colors.transparent,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'App Settings',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Theme',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Consumer<ThemeProvider>(
                builder: (context, themeProvider, _) {
                  return Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            themeProvider.setThemeMode(ThemeMode.light);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color:
                                    themeProvider.themeMode == ThemeMode.light
                                    ? parentGreen
                                    : Colors.grey[300]!,
                                width:
                                    themeProvider.themeMode == ThemeMode.light
                                    ? 2
                                    : 1,
                              ),
                              color: themeProvider.themeMode == ThemeMode.light
                                  ? parentGreen.withOpacity(0.1)
                                  : Colors.transparent,
                            ),
                            child: Center(
                              child: Text(
                                'Light',
                                style: TextStyle(
                                  color:
                                      themeProvider.themeMode == ThemeMode.light
                                      ? parentGreen
                                      : (isDark ? Colors.white : Colors.black),
                                  fontWeight:
                                      themeProvider.themeMode == ThemeMode.light
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            themeProvider.setThemeMode(ThemeMode.dark);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: themeProvider.themeMode == ThemeMode.dark
                                    ? parentGreen
                                    : Colors.grey[300]!,
                                width: themeProvider.themeMode == ThemeMode.dark
                                    ? 2
                                    : 1,
                              ),
                              color: themeProvider.themeMode == ThemeMode.dark
                                  ? parentGreen.withOpacity(0.1)
                                  : Colors.transparent,
                            ),
                            child: Center(
                              child: Text(
                                'Dark',
                                style: TextStyle(
                                  color:
                                      themeProvider.themeMode == ThemeMode.dark
                                      ? parentGreen
                                      : (isDark ? Colors.white : Colors.black),
                                  fontWeight:
                                      themeProvider.themeMode == ThemeMode.dark
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            themeProvider.setThemeMode(ThemeMode.system);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color:
                                    themeProvider.themeMode == ThemeMode.system
                                    ? parentGreen
                                    : Colors.grey[300]!,
                                width:
                                    themeProvider.themeMode == ThemeMode.system
                                    ? 2
                                    : 1,
                              ),
                              color: themeProvider.themeMode == ThemeMode.system
                                  ? parentGreen.withOpacity(0.1)
                                  : Colors.transparent,
                            ),
                            child: Center(
                              child: Text(
                                'System',
                                style: TextStyle(
                                  color:
                                      themeProvider.themeMode ==
                                          ThemeMode.system
                                      ? parentGreen
                                      : (isDark ? Colors.white : Colors.black),
                                  fontWeight:
                                      themeProvider.themeMode ==
                                          ThemeMode.system
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () async {
              final isDark = Theme.of(context).brightness == Brightness.dark;
              final confirmed = await showDialog<bool>(
                context: context,
                barrierDismissible: true,
                builder: (ctx) {
                  return AlertDialog(
                    backgroundColor: isDark
                        ? const Color(0xFF1E1A2F)
                        : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    title: Row(
                      children: const [
                        Icon(Icons.exit_to_app, color: parentGreen),
                        SizedBox(width: 8),
                        Text('Logout'),
                      ],
                    ),
                    content: Text(
                      'Are you sure you want to logout?',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black87,
                        height: 1.3,
                      ),
                    ),
                    actionsPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: isDark ? Colors.grey[300] : Colors.grey[700],
                          ),
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: parentGreen,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Logout'),
                      ),
                    ],
                  );
                },
              );

              if (confirmed != true) return;

              await authProvider.signOut();
              // ignore: use_build_context_synchronously
              Navigator.of(
                context,
              ).pushNamedAndRemoveUntil('/parent-login', (route) => false);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[400],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Logout'),
          ),
        ),
      ],
    );
  }
}
