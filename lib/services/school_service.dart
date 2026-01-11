import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/school_model.dart';

class SchoolService {
  final _firestore = FirebaseFirestore.instance;

  Future<List<SchoolModel>> fetchSchools() async {
    try {
      final snap = await _firestore.collection('schools').orderBy('name').get();

      if (snap.docs.isEmpty) {
        return [];
      }

      final schools = snap.docs.map((d) {
        return SchoolModel.fromMap(d.id, d.data());
      }).toList();

      return schools;
    } catch (e) {
      rethrow;
    }
  }
}
