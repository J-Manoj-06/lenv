import 'package:flutter/material.dart';

class StudentListScreen extends StatefulWidget {
  final String className;

  const StudentListScreen({
    Key? key,
    required this.className,
  }) : super(key: key);

  @override
  State<StudentListScreen> createState() => _StudentListScreenState();
}

class _StudentListScreenState extends State<StudentListScreen> {
  final _searchController = TextEditingController();
  String selectedFilter = 'All';

  final List<String> filters = [
    'All',
    'Top Performer',
    'On Track',
    'Needs Help',
    'Needs Attention',
  ];

  final List<Student> students = [
    Student(
      name: 'Amelia Chen',
      status: 'Top Performer',
      score: 95,
      imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuBNNwdeelqVWPSumDjluySpYCZNgCwTpg9N7C_QxTdZ85vN5Hyx0szIlrfuNhk69qKtqhjviB3CX03WkIp_FtyysSsT_y5oDbxo5JN_ZEz34Eg0iQBtg8xp8D2UWAsSIaKuYTlIazZjMfdq8ECFGS8KwSvbYH4nMfy_MB5dY2oCKZAjMrXI65Dr6wM88xXAILaibwI6gsyEZzM7glJEpo8otKL6L0UJaHWUuRtuSSZjt7_k-LnmfMnfWkQ8MVBKB6BProqnC05GKCg',
    ),
    Student(
      name: 'Ben Carter',
      status: 'On Track',
      score: 88,
      imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuArzYjI0rZnh0sXu-ekZZPYNWgTHvFb_Tl230Q6mmN8A16WDebC5Gzqm8Z7ipPnaPz5IZ6rLza4xd4FGSyi5wHoDBr2EEvjRpR2sNiWp6N0HTZx3YQxQ6CGlCY0VqVFpTdga-0A8epgKoOg3cXUz7v7p9fM4pQqPirE1K7Rli9Eeo-xnYGbUrPrklfPJjAXJ9P3yVm3siWotbzulR2EoUJKvFpJBBAM-0OehjUfU4hBqaAl6y3zt66-jWb1bxEAAFDu23M9TIpApNc',
    ),
    Student(
      name: 'Chloe Davis',
      status: 'Needs Attention',
      score: 72,
      imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuBepAZ1dNAQdbtYeWQq4IQemSmjHTWP_QG9NrWQuiDfVD3bbuRAtOzCk8Y9gizbNG4PbvsEX9jW1fjhXbDySdr5xxegyexGc1Sqtf30tJG6AE9w7po09VtI5g4OX8DX7eydfHpTIqOkWGZYXarpWJUZUAFPmgJgcyjtgXePe0mygM2dwpgUc84Iay5keAI75foshZ08eYvvFIoWejuXnp_Z7Kx8TRZx1ptScIIdcLZCs4KFbrVY86rGeebaonzoqmxCj7MttsSsXN8',
    ),
    Student(
      name: 'David Evans',
      status: 'Needs Help',
      score: 58,
      imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuD4NPkptAr_0FzuHWP96K9ReqSh3o66JrfebpANQbtwXdC4cdX9hEiPqkBYVyClMh_5vB8W9J3wpf2g2KV8ILyszB9mFnEBeKaMPPsY1O4of2GZ7MjBNvY3tjvIAe_Y-4SCkSxv1ZJeT4ppxzQEoJB7P0uIa2d4vT7l39Dc7j5W8U5lZuOL_SmTb9Np_GpoZ0oX3Uvys4RD_5wGcXdFbnEhR7CBzz5ErPZMFvS1rqsF4sm9lPOxdqp0MyKMXbiWdc0QHDokQ6j-vd4',
    ),
    Student(
      name: 'Fatima Khan',
      status: 'On Track',
      score: 85,
      imageUrl: 'https://lh3.googleusercontent.com/aida-public/AB6AXuDBvrUYr0Ezy8Vk88SN4ZRcdRWrqI6RpuKanO-HLd0JLWdVEAFpHewAcn6jU_ent8j5rlMy4zbH7CVGSbywIVrXtzPWtptjS-xyazPEjYfrK-Ts5W81JjwiRz0zRXY7Fd2aVNSYPnFxdcVBk_aMIRHDy3U_otB_gbwNUrUIdU8G0QCTJi6yGhq2vtLdUn29jHHtI9aStsl-WGzyGOpywzTMW0blDTZ9Da7ufmtcaM1YSq_7Qf3J08XZYucdkJO4zTn9_xfd-TQ9Yao',
    ),
  ];

  List<Student> get filteredStudents {
    List<Student> filtered = students;

    // Apply filter
    if (selectedFilter != 'All') {
      filtered = filtered.where((s) => s.status == selectedFilter).toList();
    }

    // Apply search
    if (_searchController.text.isNotEmpty) {
      filtered = filtered
          .where((s) => s.name
              .toLowerCase()
              .contains(_searchController.text.toLowerCase()))
          .toList();
    }

    return filtered;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F8),
      body: Column(
        children: [
          _buildHeader(),
          _buildSearchBar(),
          _buildFilterChips(),
          Expanded(
            child: _buildStudentList(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7F8).withOpacity(0.85),
        border: const Border(
          bottom: BorderSide(color: Color(0xFFE5E7EB)),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 24),
                onPressed: () => Navigator.pop(context),
                color: const Color(0xFF1F2937),
              ),
              Expanded(
                child: Text(
                  widget.className,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ),
              const SizedBox(width: 40), // Spacer to balance the back button
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchController,
        onChanged: (value) {
          setState(() {});
        },
        decoration: InputDecoration(
          hintText: 'Search for a student',
          hintStyle: const TextStyle(color: Color(0xFF6B7280)),
          prefixIcon: const Icon(Icons.search, color: Color(0xFF6B7280)),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isSelected = selectedFilter == filter;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(filter),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  selectedFilter = filter;
                });
              },
              backgroundColor: Colors.white,
              selectedColor: const Color(0xFF6366F1),
              labelStyle: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isSelected ? Colors.white : const Color(0xFF374151),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              side: BorderSide.none,
            ),
          );
        },
      ),
    );
  }

  Widget _buildStudentList() {
    final students = filteredStudents;

    if (students.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No students found',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: students.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildStudentCard(students[index]),
        );
      },
    );
  }

  Widget _buildStudentCard(Student student) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () {
          _viewStudentDetails(student);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Student avatar
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.network(
                  student.imageUrl,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.person, color: Colors.grey[600]),
                    );
                  },
                ),
              ),
              const SizedBox(width: 16),
              // Student info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      student.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _buildStatusBadge(student.status),
                        const SizedBox(width: 8),
                        Text(
                          '${student.score}%',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Chevron icon
              Icon(
                Icons.chevron_right,
                color: Colors.grey[400],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bgColor;
    Color textColor;

    switch (status) {
      case 'Top Performer':
        bgColor = const Color(0xFFD1FAE5);
        textColor = const Color(0xFF065F46);
        break;
      case 'On Track':
        bgColor = const Color(0xFFDBEAFE);
        textColor = const Color(0xFF1E40AF);
        break;
      case 'Needs Attention':
        bgColor = const Color(0xFFFEF3C7);
        textColor = const Color(0xFF92400E);
        break;
      case 'Needs Help':
        bgColor = const Color(0xFFFEE2E2);
        textColor = const Color(0xFF991B1B);
        break;
      default:
        bgColor = Colors.grey[200]!;
        textColor = Colors.grey[800]!;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: textColor,
        ),
      ),
    );
  }

  void _viewStudentDetails(Student student) {
    Navigator.pushNamed(
      context,
      '/student-performance',
      arguments: {
        'name': student.name,
        'class': 'Grade 8 - Science',
        'imageUrl': student.imageUrl,
        'score': student.score,
      },
    );
  }
}

// Student model
class Student {
  final String name;
  final String status;
  final int score;
  final String imageUrl;

  Student({
    required this.name,
    required this.status,
    required this.score,
    required this.imageUrl,
  });
}
