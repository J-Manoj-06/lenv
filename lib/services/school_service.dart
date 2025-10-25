import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/school_model.dart';

class SchoolService {
  final _firestore = FirebaseFirestore.instance;

  Future<List<SchoolModel>> fetchSchools() async {
    try {
      print('🏫 Fetching schools from Firestore...');
      final snap = await _firestore.collection('schools').orderBy('name').get();
      print('📊 Found ${snap.docs.length} schools');

      if (snap.docs.isEmpty) {
        print('⚠️ No schools found in Firestore!');
        return [];
      }

      final schools = snap.docs.map((d) {
        print('  - School: ${d.id} => ${d.data()}');
        return SchoolModel.fromMap(d.id, d.data());
      }).toList();

      print('✅ Successfully loaded ${schools.length} schools');
      return schools;
    } catch (e, stackTrace) {
      print('❌ Error fetching schools: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }
}
