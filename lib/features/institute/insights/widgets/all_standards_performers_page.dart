import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import './class_sections_performers_page.dart';

class AllStandardsPerformersPage extends StatefulWidget {
  const AllStandardsPerformersPage({super.key, required this.schoolCode});

  final String schoolCode;

  @override
  State<AllStandardsPerformersPage> createState() =>
      _AllStandardsPerformersPageState();
}

class _AllStandardsPerformersPageState
    extends State<AllStandardsPerformersPage> {
  bool _isLoading = true;
  List<String> _standards = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Get all unique classes from students collection
      final snapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('schoolCode', isEqualTo: widget.schoolCode)
          .get();

      final Set<String> uniqueClasses = {};
      for (var doc in snapshot.docs) {
        final className = doc.data()['className'] as String?;
        if (className != null && className.isNotEmpty) {
          uniqueClasses.add(className);
        }
      }

      // Sort classes numerically
      final sortedClasses = uniqueClasses.toList()
        ..sort((a, b) {
          final numA = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
          final numB = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
          return numA.compareTo(numB);
        });

      if (mounted) {
        setState(() {
          _standards = sortedClasses;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading standards: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final cardColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('Top Performers'),
        backgroundColor: cardColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _standards.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox_outlined, size: 64, color: subtitleColor),
                  const SizedBox(height: 16),
                  Text(
                    'No classes found',
                    style: TextStyle(color: subtitleColor, fontSize: 16),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _standards.length,
              itemBuilder: (context, index) {
                final standard = _standards[index];
                return Card(
                  color: cardColor,
                  margin: const EdgeInsets.only(bottom: 16),
                  elevation: 2,
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ClassSectionsPerformersPage(
                            className: standard,
                            schoolCode: widget.schoolCode,
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF146D7A).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.class_,
                              color: Color(0xFF146D7A),
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Class $standard',
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'View all sections',
                                  style: TextStyle(
                                    color: subtitleColor,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: subtitleColor,
                            size: 28,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
