import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart' as app;
import '../messages/messages_home_page.dart';

class StudentMessagesScreen extends StatelessWidget {
  const StudentMessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<app.AuthProvider>(context, listen: false);
    final studentId =
        authProvider.currentUser?.uid ??
        FirebaseAuth.instance.currentUser?.uid ??
        '';

    if (studentId.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFF1A1A1A),
        body: const Center(
          child: Text(
            'Please login to view messages',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return MessagesHomePage(studentId: studentId);
  }
}
