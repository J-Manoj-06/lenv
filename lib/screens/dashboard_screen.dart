import 'package:flutter/material.dart';

import 'student/student_dashboard_screen.dart';

/// Generic dashboard entry that currently maps to the student dashboard.
/// Keeps UI structure extensible without changing business logic.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const StudentDashboardScreen();
  }
}
