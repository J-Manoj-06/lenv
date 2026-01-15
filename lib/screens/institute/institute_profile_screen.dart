import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart' as auth;
import '../../providers/theme_provider.dart';
import '../../utils/session_manager.dart';

class InstituteProfileScreen extends StatefulWidget {
  const InstituteProfileScreen({super.key});

  @override
  State<InstituteProfileScreen> createState() => _InstituteProfileScreenState();
}

class _InstituteProfileScreenState extends State<InstituteProfileScreen> {
  bool _isLoading = false;
  String? _principalName;

  @override
  void initState() {
    super.initState();
    _loadPrincipalName();
  }

  Future<void> _loadPrincipalName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Try principals collection first
      var doc = await FirebaseFirestore.instance
          .collection('principals')
          .doc(user.uid)
          .get();

      if (doc.exists) {
        final data = doc.data();
        final name = data?['principalName']?.toString() ?? 
                     data?['name']?.toString() ?? 
                     data?['fullName']?.toString();
        if (name != null && name.isNotEmpty) {
          setState(() => _principalName = name);
          return;
        }
      }

      // If not found, try users collection
      doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (doc.exists) {
        final data = doc.data();
        final name = data?['principalName']?.toString() ?? 
                     data?['name']?.toString() ?? 
                     data?['displayName']?.toString() ?? 
                     data?['fullName']?.toString();
        if (name != null && name.isNotEmpty) {
          setState(() => _principalName = name);
          return;
        }
      }

      // Last fallback: query by email in users collection
      if (user.email != null) {
        final querySnapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: user.email)
            .where('role', isEqualTo: 'principal')
            .limit(1)
            .get();

        if (querySnapshot.docs.isNotEmpty) {
          final data = querySnapshot.docs.first.data();
          final name = data['principalName']?.toString() ?? 
                       data['name']?.toString() ?? 
                       data['displayName']?.toString() ?? 
                       data['fullName']?.toString();
          if (name != null && name.isNotEmpty) {
            setState(() => _principalName = name);
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading principal name: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF111F21) : const Color(0xFFF8FAFC);
    final cardColor = isDark ? const Color(0xFF1A2A2D) : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    _ProfileHeader(user: user, isDark: isDark, principalName: _principalName),
                    const SizedBox(height: 24),
                    _AppSettingsCard(isDark: isDark, cardColor: cardColor),
                    const SizedBox(height: 24),
                    _QuickStats(isDark: isDark, cardColor: cardColor),
                    const SizedBox(height: 24),
                    _InfoCards(user: user, isDark: isDark, cardColor: cardColor),
                    const SizedBox(height: 32),
                    _LogoutButton(
                      isLoading: _isLoading,
                      onLogout: _handleLogout,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _TopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Principal Profile',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogout() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF1A2A2D) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark ? Colors.white70 : const Color(0xFF64748B);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cardColor,
        title: Text('Logout', style: TextStyle(color: textColor)),
        content: Text(
          'Are you sure you want to logout?',
          style: TextStyle(color: subtitleColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: subtitleColor),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      final authProvider = Provider.of<auth.AuthProvider>(
        context,
        listen: false,
      );
      await authProvider.signOut();
      await SessionManager.clearLoginSession();

      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/role-selection',
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logout failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user, required this.isDark, this.principalName});

  final User? user;
  final bool isDark;
  final String? principalName;

  @override
  Widget build(BuildContext context) {
    final displayName = principalName ?? user?.displayName ?? 'Principal';
    final initials = _getInitials(displayName);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark ? Colors.white54 : const Color(0xFF64748B);

    return Column(
      children: [
        Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF0D9488), Color(0xFF5EEAD4)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Center(
            child: Text(
              initials,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          displayName,
          style: TextStyle(
            color: textColor,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Principal',
          style: TextStyle(color: subtitleColor, fontSize: 14),
        ),
      ],
    );
  }

  String _getInitials(String name) {
    if (name.trim().isEmpty) return 'P';

    final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
      return parts[0].substring(0, parts[0].length >= 2 ? 2 : 1).toUpperCase();
    }
    return 'P';
  }
}

class _AppSettingsCard extends StatelessWidget {
  const _AppSettingsCard({required this.isDark, required this.cardColor});

  final bool isDark;
  final Color cardColor;

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark ? Colors.white54 : const Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'App Settings',
            style: TextStyle(
              color: textColor,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose your preferred theme',
            style: TextStyle(color: subtitleColor, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _ThemeButton(
                  label: 'Light',
                  icon: Icons.light_mode_outlined,
                  isSelected: themeProvider.themeMode == ThemeMode.light,
                  isDark: isDark,
                  onTap: () => themeProvider.setThemeMode(ThemeMode.light),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ThemeButton(
                  label: 'Dark',
                  icon: Icons.dark_mode_outlined,
                  isSelected: themeProvider.themeMode == ThemeMode.dark,
                  isDark: isDark,
                  onTap: () => themeProvider.setThemeMode(ThemeMode.dark),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ThemeButton(
                  label: 'System',
                  icon: Icons.brightness_auto_outlined,
                  isSelected: themeProvider.themeMode == ThemeMode.system,
                  isDark: isDark,
                  onTap: () => themeProvider.setThemeMode(ThemeMode.system),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ThemeButton extends StatelessWidget {
  const _ThemeButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bgColor = isSelected
        ? const Color(0xFF146D7A)
        : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9));
    final textColor = isSelected
        ? Colors.white
        : (isDark ? Colors.white70 : const Color(0xFF475569));

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? null
              : Border.all(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
        ),
        child: Column(
          children: [
            Icon(icon, color: textColor, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickStats extends StatelessWidget {
  const _QuickStats({required this.isDark, required this.cardColor});

  final bool isDark;
  final Color cardColor;

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark ? Colors.white54 : const Color(0xFF64748B);
    final dividerColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  Text(
                    '25 years',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Experience',
                    style: TextStyle(color: subtitleColor, fontSize: 13),
                  ),
                ],
              ),
            ),
            VerticalDivider(
              color: dividerColor,
              thickness: 1,
              width: 1,
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    'Ph.D, M.Sc',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Qualification',
                    style: TextStyle(color: subtitleColor, fontSize: 13),
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

class _InfoCards extends StatelessWidget {
  const _InfoCards({required this.user, required this.isDark, required this.cardColor});

  final User? user;
  final bool isDark;
  final Color cardColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _InfoCard(
          label: 'Date of Joining',
          value: user?.metadata.creationTime != null
              ? '${user!.metadata.creationTime!.year}-${user!.metadata.creationTime!.month.toString().padLeft(2, '0')}-${user!.metadata.creationTime!.day.toString().padLeft(2, '0')}'
              : '2018-06-01',
          isDark: isDark,
          cardColor: cardColor,
        ),
        const SizedBox(height: 12),
        _InfoCard(
          label: 'Contact Number',
          value: user?.phoneNumber ?? '+91-98765-11112',
          isDark: isDark,
          cardColor: cardColor,
        ),
        const SizedBox(height: 12),
        _InfoCard(
          label: 'Email',
          value: user?.email ?? 'principal@school.edu',
          isDark: isDark,
          cardColor: cardColor,
        ),
        const SizedBox(height: 12),
        _InfoCard(
          label: 'Employee ID',
          value: user?.uid.substring(0, 8).toUpperCase() ?? 'PRN-1001',
          isDark: isDark,
          cardColor: cardColor,
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.label,
    required this.value,
    required this.isDark,
    required this.cardColor,
  });

  final String label;
  final String value;
  final bool isDark;
  final Color cardColor;

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark ? Colors.white54 : const Color(0xFF64748B);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: subtitleColor, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: textColor,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  const _LogoutButton({
    required this.isLoading,
    required this.onLogout,
    required this.isDark,
  });

  final bool isLoading;
  final VoidCallback onLogout;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final buttonColor = isDark ? Colors.red.shade400 : Colors.red.shade600;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: isLoading ? null : onLogout,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: BorderSide(color: buttonColor, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(buttonColor),
                ),
              )
            : Text(
                'Logout',
                style: TextStyle(
                  color: buttonColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}
