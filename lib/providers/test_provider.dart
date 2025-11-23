import 'dart:async';
import 'package:flutter/material.dart';
import '../models/test_model.dart';
import '../services/firestore_service.dart';

class TestProvider with ChangeNotifier {
  final FirestoreService _firestoreService = FirestoreService();

  // Per-context (teacher/student) state maps to avoid global leakage across users.
  final Map<String, List<TestModel>> _teacherTests = {}; // key: teacherId
  final Map<String, List<TestModel>> _studentTests = {}; // key: studentId
  final Map<String, TestModel?> _selectedTests =
      {}; // key: contextId (teacherId or studentId)
  final Map<String, bool> _loadingStates = {}; // key: contextId
  final Map<String, String?> _errorStates = {}; // key: contextId

  // Track current active contexts for backward-compatible getters.
  String? _currentTeacherId;
  String? _currentStudentId;

  // Separate subscriptions so listening for a teacher does not cancel student stream and vice versa.
  final Map<String, StreamSubscription<List<TestModel>>?>
  _teacherSubscriptions = {};
  final Map<String, StreamSubscription<List<TestModel>>?>
  _studentSubscriptions = {};

  // Backward compatible getters (return last active context data).
  List<TestModel> get tests {
    if (_currentTeacherId != null) {
      return _teacherTests[_currentTeacherId!] ?? [];
    }
    if (_currentStudentId != null) {
      return _studentTests[_currentStudentId!] ?? [];
    }
    return [];
  }

  TestModel? get selectedTest {
    if (_currentTeacherId != null) {
      return _selectedTests['teacher_${_currentTeacherId!}'];
    }
    if (_currentStudentId != null) {
      return _selectedTests['student_${_currentStudentId!}'];
    }
    return null;
  }

  bool get isLoading {
    if (_currentTeacherId != null) {
      return _loadingStates['teacher_${_currentTeacherId!}'] ?? false;
    }
    if (_currentStudentId != null) {
      return _loadingStates['student_${_currentStudentId!}'] ?? false;
    }
    return false;
  }

  String? get errorMessage {
    if (_currentTeacherId != null) {
      return _errorStates['teacher_${_currentTeacherId!}'];
    }
    if (_currentStudentId != null) {
      return _errorStates['student_${_currentStudentId!}'];
    }
    return null;
  }

  // Explicit per-context accessors (preferred going forward)
  List<TestModel> testsForTeacher(String teacherId) =>
      _teacherTests[teacherId] ?? [];
  List<TestModel> testsForStudent(String studentId) =>
      _studentTests[studentId] ?? [];
  bool isLoadingForTeacher(String teacherId) =>
      _loadingStates['teacher_$teacherId'] ?? false;
  bool isLoadingForStudent(String studentId) =>
      _loadingStates['student_$studentId'] ?? false;
  String? errorForTeacher(String teacherId) =>
      _errorStates['teacher_$teacherId'];
  String? errorForStudent(String studentId) =>
      _errorStates['student_$studentId'];

  // Create test
  Future<bool> createTest(TestModel test) async {
    final teacherId = test.teacherId;
    _currentTeacherId = teacherId.isNotEmpty ? teacherId : _currentTeacherId;
    final key = 'teacher_${_currentTeacherId ?? teacherId}';
    _loadingStates[key] = true;
    _errorStates[key] = null;
    notifyListeners();

    try {
      await _firestoreService.createTestAndAssignToClass(test);
      _loadingStates[key] = false;
      // Refresh teacher tests to include newly created test
      if (teacherId.isNotEmpty) {
        loadTestsByTeacher(teacherId);
      }
      notifyListeners();
      return true;
    } catch (e) {
      _errorStates[key] = e.toString();
      _loadingStates[key] = false;
      notifyListeners();
      return false;
    }
  }

  // Create scheduled test
  Future<bool> createScheduledTest(
    TestModel test, {
    required DateTime scheduledDate,
    required TimeOfDay scheduledTime,
  }) async {
    final teacherId = test.teacherId;
    _currentTeacherId = teacherId.isNotEmpty ? teacherId : _currentTeacherId;
    final key = 'teacher_${_currentTeacherId ?? teacherId}';
    _loadingStates[key] = true;
    _errorStates[key] = null;
    notifyListeners();

    try {
      await _firestoreService.createScheduledTest(
        test,
        scheduledDate: scheduledDate,
        scheduledTime: scheduledTime,
      );
      _loadingStates[key] = false;
      if (teacherId.isNotEmpty) {
        loadTestsByTeacher(teacherId);
      }
      notifyListeners();
      return true;
    } catch (e) {
      _errorStates[key] = e.toString();
      _loadingStates[key] = false;
      notifyListeners();
      return false;
    }
  }

  // Load tests by teacher (initial + any subsequent reloads)
  void loadTestsByTeacher(String teacherId) {
    final subKey = teacherId;
    _currentTeacherId = teacherId; // update active context
    _loadingStates['teacher_$teacherId'] = true;
    _errorStates['teacher_$teacherId'] = null;
    notifyListeners();

    // Cancel only this teacher's previous subscription
    _teacherSubscriptions[subKey]?.cancel();

    _teacherSubscriptions[subKey] = _firestoreService
        .getTestsByTeacher(teacherId)
        .listen(
          (tests) {
            _teacherTests[teacherId] = tests;
            _loadingStates['teacher_$teacherId'] = false;
            _errorStates['teacher_$teacherId'] = null;
            notifyListeners();
          },
          onError: (error) {
            _errorStates['teacher_$teacherId'] = error.toString();
            _loadingStates['teacher_$teacherId'] = false;
            notifyListeners();
          },
        );
  }

  // Load available tests for student
  void loadAvailableTests(String studentId, {String? studentEmail}) {
    final subKey = studentId;
    _currentStudentId = studentId; // update active context
    _loadingStates['student_$studentId'] = true;
    _errorStates['student_$studentId'] = null;
    notifyListeners();

    // Cancel only this student's previous subscription
    _studentSubscriptions[subKey]?.cancel();

    _studentSubscriptions[subKey] = _firestoreService
        .getAvailableTestsForStudent(studentId, studentEmail: studentEmail)
        .listen(
          (tests) {
            _studentTests[studentId] = tests;
            _loadingStates['student_$studentId'] = false;
            _errorStates['student_$studentId'] = null;
            notifyListeners();
          },
          onError: (error) {
            _errorStates['student_$studentId'] = error.toString();
            _loadingStates['student_$studentId'] = false;
            notifyListeners();
          },
        );
  }

  // Select test
  void selectTest(TestModel test) {
    if (_currentTeacherId != null) {
      _selectedTests['teacher_${_currentTeacherId!}'] = test;
    } else if (_currentStudentId != null) {
      _selectedTests['student_${_currentStudentId!}'] = test;
    }
    notifyListeners();
  }

  // Update test
  Future<bool> updateTest(String testId, Map<String, dynamic> data) async {
    try {
      await _firestoreService.updateTest(testId, data);
      return true;
    } catch (e) {
      // Assign error to current context
      if (_currentTeacherId != null) {
        _errorStates['teacher_${_currentTeacherId!}'] = e.toString();
      } else if (_currentStudentId != null) {
        _errorStates['student_${_currentStudentId!}'] = e.toString();
      }
      notifyListeners();
      return false;
    }
  }

  // Delete test
  Future<bool> deleteTest(String testId) async {
    try {
      await _firestoreService.deleteTestCascade(testId);
      return true;
    } catch (e) {
      if (_currentTeacherId != null) {
        _errorStates['teacher_${_currentTeacherId!}'] = e.toString();
      } else if (_currentStudentId != null) {
        _errorStates['student_${_currentStudentId!}'] = e.toString();
      }
      notifyListeners();
      return false;
    }
  }

  // Clear error
  void clearError() {
    if (_currentTeacherId != null) {
      _errorStates['teacher_${_currentTeacherId!}'] = null;
    }
    if (_currentStudentId != null) {
      _errorStates['student_${_currentStudentId!}'] = null;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    // Cancel all teacher subscriptions
    for (final sub in _teacherSubscriptions.values) {
      sub?.cancel();
    }
    // Cancel all student subscriptions
    for (final sub in _studentSubscriptions.values) {
      sub?.cancel();
    }
    super.dispose();
  }
}
