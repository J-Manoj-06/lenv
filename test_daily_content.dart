import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

/// Quick test script to check if daily content exists in Firestore
void main() async {
  print('🔍 Checking daily content in Firebase...\n');
  
  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  final firestore = FirebaseFirestore.instance;
  
  // Check today and past 7 days
  final today = DateTime.now();
  
  for (int i = 0; i < 7; i++) {
    final checkDate = today.subtract(Duration(days: i));
    final dateKey = '${checkDate.year}-${checkDate.month.toString().padLeft(2, '0')}-${checkDate.day.toString().padLeft(2, '0')}';
    
    try {
      final doc = await firestore
          .collection('daily_content')
          .doc(dateKey)
          .get()
          .timeout(const Duration(seconds: 5));
      
      if (doc.exists) {
        final data = doc.data();
        print('✅ $dateKey - EXISTS');
        print('   Quote: ${data?['quote']?['text']?.toString().substring(0, 50) ?? 'N/A'}...');
        print('   Fact: ${data?['fact']?['text']?.toString().substring(0, 50) ?? 'N/A'}...');
        print('   History events: ${data?['history']?['events']?.length ?? 0}');
        print('   Fetched at: ${data?['fetchedAt'] ?? 'N/A'}');
        print('   Status: ${data?['status'] ?? 'N/A'}\n');
      } else {
        print('❌ $dateKey - NOT FOUND\n');
      }
    } catch (e) {
      print('⚠️  $dateKey - ERROR: $e\n');
    }
  }
  
  print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  print('📊 Summary:');
  print('   Collection: daily_content');
  print('   Document ID format: YYYY-MM-DD');
  print('   Expected cron: Daily at 2:00 AM IST');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
}
