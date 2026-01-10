import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:new_reward/firebase_options.dart';

void main() async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final firestore = FirebaseFirestore.instance;

  try {
    print('🔧 Starting student document repair...');

    // Get all student documents
    final studentsSnap = await firestore.collection('students').get();
    print('📊 Found ${studentsSnap.docs.length} student documents');

    int repaired = 0;
    int skipped = 0;

    for (final studentDoc in studentsSnap.docs) {
      final data = studentDoc.data();
      final docId = studentDoc.id;

      // Check if this document has ONLY reward fields
      final keys = data.keys.toSet();
      final rewardOnlyFields = {
        'available_points',
        'locked_points',
        'deducted_points',
        'last_reward_request',
      };
      final hasProfileFields =
          keys.contains('className') ||
          keys.contains('section') ||
          keys.contains('schoolCode') ||
          keys.contains('email') ||
          keys.contains('studentName');

      if (!hasProfileFields) {
        print('⚠️  Document $docId has NO profile fields! Keys: $keys');

        // Try to restore from users collection
        try {
          final usersDoc = await firestore.collection('users').doc(docId).get();
          if (usersDoc.exists) {
            final userData = usersDoc.data() ?? {};
            print('   Found backup in users/$docId');

            // Merge profile fields from users back to students
            await firestore.collection('students').doc(docId).update({
              'className': userData['className'] ?? '',
              'section': userData['section'] ?? '',
              'schoolCode': userData['schoolCode'] ?? '',
              'email': userData['email'] ?? '',
              'studentName': userData['name'] ?? '',
              'name': userData['name'] ?? '',
              'schoolName': userData['schoolName'] ?? '',
            });

            print('   ✅ Repaired document $docId');
            repaired++;
          } else {
            print('   ❌ No backup found in users/$docId');
            skipped++;
          }
        } catch (e) {
          print('   ❌ Error repairing $docId: $e');
          skipped++;
        }
      }
    }

    print('\n✅ Repair complete!');
    print('   Repaired: $repaired documents');
    print('   Skipped: $skipped documents');
  } catch (e) {
    print('❌ Error: $e');
  }
}
