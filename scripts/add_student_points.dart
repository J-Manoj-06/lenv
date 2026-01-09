import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

/// Quick script to add points to a student account for testing
///
/// Usage:
/// ```
/// dart scripts/add_student_points.dart STUDENT_ID POINTS_TO_ADD
/// ```
///
/// Example:
/// ```
/// dart scripts/add_student_points.dart 6z0NvaPo9xUMFmltnmwnkTRMUts1 500
/// ```

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    print('❌ Usage: dart scripts/add_student_points.dart <studentId> <points>');
    print(
      '   Example: dart scripts/add_student_points.dart 6z0NvaPo9xUMFmltnmwnkTRMUts1 500',
    );
    return;
  }

  final studentId = args[0];
  final pointsToAdd = int.tryParse(args[1]);

  if (pointsToAdd == null || pointsToAdd <= 0) {
    print('❌ Points must be a positive number');
    return;
  }

  print('🔧 Initializing Firebase...');
  await Firebase.initializeApp();

  final firestore = FirebaseFirestore.instance;

  try {
    print('📝 Adding $pointsToAdd points to student: $studentId');

    // Update students collection
    final studentRef = firestore.collection('students').doc(studentId);
    await studentRef.set({
      'available_points': FieldValue.increment(pointsToAdd),
    }, SetOptions(merge: true));

    print('✅ Successfully added $pointsToAdd points to students collection');

    // Also add to student_rewards for tracking
    final now = DateTime.now();
    final rewardRef = firestore.collection('student_rewards').doc();
    await rewardRef.set({
      'id': rewardRef.id,
      'studentId': studentId,
      'testId': 'manual_addition_${now.millisecondsSinceEpoch}',
      'marks': pointsToAdd.toDouble(),
      'totalMarks': pointsToAdd.toDouble(),
      'pointsEarned': pointsToAdd,
      'timestamp': FieldValue.serverTimestamp(),
      'source': 'manual_testing',
    });

    print('✅ Created student_rewards entry for tracking');

    // Verify the update
    final snapshot = await studentRef.get();
    final data = snapshot.data();
    final availablePoints = data?['available_points'] ?? 0;

    print('');
    print('✨ SUCCESS! Student now has:');
    print('   Available Points: $availablePoints');
    print('   Locked Points: ${data?['locked_points'] ?? 0}');
    print('');
    print('💡 You can now test the rewards request feature!');
  } catch (e) {
    print('❌ Error adding points: $e');
  }
}
