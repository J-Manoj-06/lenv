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
    print('🔧 Starting Student UID Fix Process...');
    print('   SchoolCode: $schoolCode');
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
      print('📋 Found ${studentsSnapshot.docs.length} students to fix');

      for (final studentDoc in studentsSnapshot.docs) {
        final studentData = studentDoc.data();
        final email = studentData['email'] as String?;

        if (email == null || email.isEmpty) {
          print('   ⚠️ Student ${studentDoc.id} has no email, skipping');
          errorCount++;
          errors.add('No email for ${studentDoc.id}');
          continue;
        }

        try {
          // Try to sign in to get the Auth UID
          print('   🔐 Signing in as $email...');
          final userCredential = await _auth.signInWithEmailAndPassword(
            email: email,
            password: defaultPassword,
          );

          if (userCredential.user != null) {
            final authUID = userCredential.user!.uid;
            print('   ✅ Got Auth UID: $authUID');

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
              print('   ✅ Updated users collection for $email');
              successCount++;
            } else {
              print('   ⚠️ No users document found for $email');
              errorCount++;
              errors.add('No users doc for $email');
            }

            // Sign out this student
            await _auth.signOut();
          }
        } catch (e) {
          print('   ❌ Failed to process $email: $e');
          errorCount++;
          errors.add('$email: ${e.toString()}');
        }
      }

      // Restore original user session if needed
      if (originalUser != null) {
        print('🔄 Restoring original user session...');
        // You'll need to sign back in as the original user
        // This is tricky - might be better to do this as an admin script
      }

      print('✅ Fix process complete!');
      print('   Success: $successCount');
      print('   Errors: $errorCount');

      return {
        'success': true,
        'successCount': successCount,
        'errorCount': errorCount,
        'errors': errors,
      };
    } catch (e, stackTrace) {
      print('❌ Fix process failed: $e');
      print('Stack trace: $stackTrace');
      return {'success': false, 'error': e.toString()};
    }
  }
}
