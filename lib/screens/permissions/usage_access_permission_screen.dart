import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../../services/student_usage_service.dart';

class UsageAccessPermissionScreen extends StatefulWidget {
  const UsageAccessPermissionScreen({super.key});

  @override
  State<UsageAccessPermissionScreen> createState() =>
      _UsageAccessPermissionScreenState();
}

class _UsageAccessPermissionScreenState
    extends State<UsageAccessPermissionScreen>
    with WidgetsBindingObserver {
  final StudentUsageService _usageService = StudentUsageService();

  bool _isOpeningSettings = false;
  bool _isCheckingOnResume = false;
  bool _openedSettings = false;

  static const Color _brandOrange = Color(0xFFF2800D);
  static const Color _brandOrangeLight = Color(0xFFFFB978);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _openedSettings) {
      _checkPermissionAfterReturn();
    }
  }

  Future<void> _openSettings() async {
    setState(() => _isOpeningSettings = true);
    try {
      _openedSettings = true;
      await _usageService.openUsagePermissionSettings();
    } finally {
      if (mounted) {
        setState(() => _isOpeningSettings = false);
      }
    }
  }

  Future<void> _checkPermissionAfterReturn() async {
    if (_isCheckingOnResume || !mounted) return;

    setState(() => _isCheckingOnResume = true);
    try {
      final granted = await _usageService.isUsagePermissionGranted();
      if (!mounted) return;

      if (granted) {
        Navigator.of(context).pop(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permission not enabled yet')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCheckingOnResume = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final isBusy = _isOpeningSettings || _isCheckingOnResume;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: colorScheme.onSurface),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Enable App Usage Access',
          style: textTheme.titleLarge?.copyWith(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [_brandOrangeLight, _brandOrange],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _brandOrange.withValues(alpha: 0.28),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.query_stats_rounded,
                        color: Colors.white,
                        size: 54,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'To help parents and teachers monitor app usage, please allow access in the next step.',
                    style: textTheme.bodyLarge?.copyWith(
                      fontSize: 16,
                      height: 1.4,
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.45,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _brandOrange.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Instructions',
                          style: textTheme.titleMedium?.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '1. Find "Lenv"',
                          style: textTheme.bodyMedium?.copyWith(
                            fontSize: 15,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '2. Tap on it',
                          style: textTheme.bodyMedium?.copyWith(
                            fontSize: 15,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '3. Enable "Allow usage access"',
                          style: textTheme.bodyMedium?.copyWith(
                            fontSize: 15,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isBusy ? null : _openSettings,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _brandOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Enable Permission'),
                    ),
                  ),
                ],
              ),
            ),
            if (_isCheckingOnResume)
              Container(
                color: Colors.black.withValues(alpha: 0.18),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: _brandOrange),
                      const SizedBox(height: 12),
                      Text(
                        'Checking permission...',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
