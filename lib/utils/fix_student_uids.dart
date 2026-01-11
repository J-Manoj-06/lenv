import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Utility to fix all student UIDs in the users collection
///
/// This function:
/// 1. Reads all students from the 'students' collection
/// 2. For each student, tries to sign in to get their Auth UID
/// 3. Updates the 'users' collection with the correct UID
///
/// WARNING: This requires knowing student passwords OR creating new accounts
class StudentUIDFixer {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Fix UIDs for students in a specific school
  ///
  /// [schoolCode] - The school code to filter students
  /// [defaultPassword] - Default password used for student accounts (if known)
  /// [className] - Optional: Fix only students in this class
  /// [section] - Optional: Fix only students in this section
  Future<Map<String, dynamic>> fixStudentUIDs({
    required String schoolCode,
    required String defaultPassword,
    String? className,
    String? section,
  }) async {
    if (className != null) print('   ClassName: $className');
    if (section != null) print('   Section: $section');

    int successCount = 0;
    int errorCount = 0;
    final List<String> errors = [];
    final originalUser = _auth.currentUser;

    try {
      // Query students
      var query = _db
          .collection('students')
          .where('schoolCode', isEqualTo: schoolCode);

      if (className != null && className.isNotEmpty) {
        query = query.where('className', isEqualTo: className);
      }
      if (section != null && section.isNotEmpty) {
        query = query.where('section', isEqualTo: section);
      }

      final studentsSnapshot = await query.get();

      for (final studentDoc in studentsSnapshot.docs) {
        final studentData = studentDoc.data();
        final email = studentData['email'] as String?;

        if (email == null || email.isEmpty) {
          errorCount++;
          errors.add('No email for ${studentDoc.id}');
          continue;
        }

        try {
          // Try to sign in to get the Auth UID
          final userCredential = await _auth.signInWithEmailAndPassword(
            email: email,
            password: defaultPassword,
          );

          if (userCredential.user != null) {
            final authUID = userCredential.user!.uid;

            // Update users collection
            final userQuery = await _db
                .collection('users')
                .where('email', isEqualTo: email)
                .limit(1)
                .get();

            if (userQuery.docs.isNotEmpty) {
              await _db.collection('users').doc(userQuery.docs.first.id).update(
                {'uid': authUID},
              );
              successCount++;
            } else {
              errorCount++;
              errors.add('No users doc for $email');
            }

            // Sign out this student
            await _auth.signOut();
          }
        } catch (e) {
          errorCount++;
          errors.add('$email: ${e.toString()}');
        }
      }

      // Restore original user session if needed
      if (originalUser != null) {
        // You'll need to sign back in as the original user
        // This is tricky - might be better to do this as an admin script
      }

      return {
        'success': true,
        'successCount': successCount,
        'errorCount': errorCount,
        'errors': errors,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
}
