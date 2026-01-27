import 'package:flutter/material.dart';

/// Entry screen letting teacher choose manual creation or AI generation.
class CreateTestEntryScreen extends StatelessWidget {
  const CreateTestEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Color cardBorder(bool primary) => primary
        ? const Color(0xFF5170FB).withOpacity(0.3)
        : Colors.white.withOpacity(isDark ? 0.08 : 0.15);
    Color cardBg(bool primary) => primary
        ? (isDark ? const Color(0xFF12162D) : theme.colorScheme.surface)
        : (isDark
              ? Colors.white.withOpacity(0.05)
              : Colors.black.withOpacity(0.05));
    final bgColor = isDark ? Colors.black : theme.scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            SizedBox(
              height: 56,
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  Center(
                    child: Text(
                      'Create a Test',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: theme.textTheme.bodyLarge?.color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  Text(
                    'Choose how you want to generate the test',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.textTheme.bodyMedium?.color?.withOpacity(
                        0.7,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                children: [
                  _OptionCard(
                    icon: Icons.edit_document,
                    iconBg: const Color(0xFF5170FB).withOpacity(0.2),
                    iconColor: const Color(0xFF5170FB),
                    title: 'Create Manually',
                    subtitle: 'Build your test by adding questions one by one.',
                    borderColor: cardBorder(true),
                    background: cardBg(true),
                    glowPrimary: true, // style parity with AI card
                    onTap: () =>
                        Navigator.pushReplacementNamed(context, '/create-test'),
                  ),
                  const SizedBox(height: 16),
                  _OptionCard(
                    icon: Icons.auto_awesome,
                    iconBg: const Color(0xFF5170FB).withOpacity(0.2),
                    iconColor: const Color(0xFF5170FB),
                    title: 'Generate with AI',
                    subtitle:
                        'Let AI create a complete test based on your topic.',
                    borderColor: cardBorder(true),
                    background: cardBg(true),
                    glowPrimary: true,
                    onTap: () => Navigator.pushReplacementNamed(
                      context,
                      '/ai-test-generator',
                    ),
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

class _OptionCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Color borderColor;
  final Color background;
  final VoidCallback onTap;
  final bool glowPrimary;

  const _OptionCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.borderColor,
    required this.background,
    required this.onTap,
    this.glowPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 1),
          boxShadow: glowPrimary
              ? [
                  BoxShadow(
                    color: const Color(0xFF5170FB).withOpacity(0.25),
                    blurRadius: 18,
                    spreadRadius: 2,
                    offset: const Offset(0, 6),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 48,
              width: 48,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 26),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(
                  context,
                ).textTheme.bodyMedium?.color?.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
