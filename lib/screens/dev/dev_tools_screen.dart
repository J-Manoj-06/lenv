import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/seed_data.dart';

/// Developer tools screen for seeding test data and debugging
/// Access this by navigating to /dev-tools
class DevToolsScreen extends StatefulWidget {
  const DevToolsScreen({super.key});

  @override
  State<DevToolsScreen> createState() => _DevToolsScreenState();
}

class _DevToolsScreenState extends State<DevToolsScreen> {
  bool _isLoading = false;
  String _statusMessage = '';
  final _studentUidController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
  }

  void _loadCurrentUser() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _studentUidController.text = user.uid;
    }
  }

  Future<void> _seedData() async {
    if (_studentUidController.text.isEmpty) {
      setState(() {
        _statusMessage = '❌ Please enter a student UID';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = '🌱 Seeding data...';
    });

    try {
      await FirestoreSeedData.seedStudentData(_studentUidController.text);
      setState(() {
        _statusMessage = '✅ Data seeded successfully!';
      });
    } catch (e) {
      setState(() {
        _statusMessage = '❌ Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _clearData() async {
    if (_studentUidController.text.isEmpty) {
      setState(() {
        _statusMessage = '❌ Please enter a student UID';
      });
      return;
    }

    // Confirm deletion
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Clear Data'),
        content: const Text(
          'Are you sure you want to delete all test data? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isLoading = true;
      _statusMessage = '🗑️ Clearing data...';
    });

    try {
      await FirestoreSeedData.clearTestData(_studentUidController.text);
      setState(() {
        _statusMessage = '✅ Data cleared successfully!';
      });
    } catch (e) {
      setState(() {
        _statusMessage = '❌ Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _seedSchools() async {
    setState(() {
      _isLoading = true;
      _statusMessage = '🏫 Seeding schools...';
    });

    try {
      await FirestoreSeedData.seedSchools();
      setState(() {
        _statusMessage = '✅ Schools seeded successfully!';
      });
    } catch (e) {
      setState(() {
        _statusMessage = '❌ Error seeding schools: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _openLatestResult() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _statusMessage = '❌ Sign in a student first';
      });
      return;
    }
    try {
      setState(() {
        _isLoading = true;
        _statusMessage = '🔎 Loading latest result...';
      });
      final snap = await FirebaseFirestore.instance
          .collection('testResults')
          .where('studentId', isEqualTo: user.uid)
          .orderBy('completedAt', descending: true)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) {
        setState(() {
          _statusMessage = 'ℹ️ No results found for this user';
        });
        return;
      }
      final id = snap.docs.first.id;
      if (mounted) {
        Navigator.of(
          context,
        ).pushNamed('/student-test-result', arguments: {'resultId': id});
      }
    } catch (e) {
      setState(() {
        _statusMessage = '❌ Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('🛠️ Developer Tools'),
        backgroundColor: const Color(0xFFF59E0B),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Current User Info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Current User',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (user != null) ...[
                      Text('UID: ${user.uid}'),
                      Text('Email: ${user.email}'),
                    ] else
                      const Text('No user signed in'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Student UID Input
            TextField(
              controller: _studentUidController,
              decoration: const InputDecoration(
                labelText: 'Student UID',
                hintText: 'Enter student UID to seed/clear data',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),

            const SizedBox(height: 16),

            // Seed Schools Button (Run this FIRST)
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _seedSchools,
              icon: const Icon(Icons.school),
              label: const Text('Seed Schools (Run First!)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),

            const SizedBox(height: 12),

            // Seed Data Button
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _seedData,
              icon: const Icon(Icons.upload),
              label: const Text('Seed Test Data'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),

            const SizedBox(height: 12),

            // Clear Data Button
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _clearData,
              icon: const Icon(Icons.delete_forever),
              label: const Text('Clear Test Data'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),

            const SizedBox(height: 12),

            // Open Latest Result
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _openLatestResult,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open Latest Test Result'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),

            const SizedBox(height: 24),

            // Status Message
            if (_statusMessage.isNotEmpty)
              Card(
                color: _statusMessage.contains('✅')
                    ? Colors.green.shade50
                    : _statusMessage.contains('❌')
                    ? Colors.red.shade50
                    : Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    _statusMessage,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),

            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(child: CircularProgressIndicator()),
              ),

            const Spacer(),

            // Info Card
            Card(
              color: Colors.amber.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'ℹ️ What this does:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text('• Creates a student document with initial stats'),
                    Text('• Creates today\'s daily challenge'),
                    Text('• Creates 4 sample notifications'),
                    Text('• Creates 3 pending tests'),
                    Text('• Creates 3 completed test results'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _studentUidController.dispose();
    super.dispose();
  }
}
