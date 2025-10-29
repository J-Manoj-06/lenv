import 'package:flutter/foundation.dart';
import '../models/test_model.dart';
import '../services/firestore_service.dart';

class TestProvider with ChangeNotifier {
  final FirestoreService _firestoreService = FirestoreService();

  List<TestModel> _tests = [];
  TestModel? _selectedTest;
  bool _isLoading = false;
  String? _errorMessage;

  List<TestModel> get tests => _tests;
  TestModel? get selectedTest => _selectedTest;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // Create test
  Future<bool> createTest(TestModel test) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _firestoreService.createTestAndAssignToClass(test);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Load tests by teacher
  void loadTestsByTeacher(String teacherId) {
    _isLoading = true;
    notifyListeners();

    _firestoreService
        .getTestsByTeacher(teacherId)
        .listen(
          (tests) {
            _tests = tests;
            _isLoading = false;
            notifyListeners();
          },
          onError: (error) {
            _errorMessage = error.toString();
            _isLoading = false;
            notifyListeners();
          },
        );
  }

  // Load available tests for student
  void loadAvailableTests(String studentId, {String? studentEmail}) {
    _isLoading = true;
    notifyListeners();

    _firestoreService
        .getAvailableTestsForStudent(studentId, studentEmail: studentEmail)
        .listen(
          (tests) {
            _tests = tests;
            _isLoading = false;
            notifyListeners();
          },
          onError: (error) {
            _errorMessage = error.toString();
            _isLoading = false;
            notifyListeners();
          },
        );
  }

  // Select test
  void selectTest(TestModel test) {
    _selectedTest = test;
    notifyListeners();
  }

  // Update test
  Future<bool> updateTest(String testId, Map<String, dynamic> data) async {
    try {
      await _firestoreService.updateTest(testId, data);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
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
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  // Clear error
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
