import 'package:flutter/material.dart';

class ParentTestsScreen extends StatelessWidget {
  const ParentTestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF151022)
          : const Color(0xFFF6F6F8),
      appBar: AppBar(
        title: const Text('Tests'),
        backgroundColor: isDark ? const Color(0xFF151022) : Colors.white,
        foregroundColor: isDark ? Colors.white : const Color(0xFF110D1B),
        elevation: 0.5,
      ),
      body: Center(
        child: Text(
          'Test performance overview coming soon',
          style: TextStyle(
            color: isDark ? Colors.grey[300] : Colors.grey[700],
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
