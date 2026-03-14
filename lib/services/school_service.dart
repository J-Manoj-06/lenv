import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/school_model.dart';

class SchoolFetchException implements Exception {
  final String message;
  final bool isNetworkIssue;

  const SchoolFetchException(this.message, {this.isNetworkIssue = false});

  @override
  String toString() => message;
}

class SchoolService {
  final _firestore = FirebaseFirestore.instance;
  static const String _schoolsCacheBox = 'schools_cache_offline';
  static const String _schoolsCacheKey = 'schools';
  bool _lastFetchUsedCache = false;

  bool get lastFetchUsedCache => _lastFetchUsedCache;

  bool _isNetworkOrDnsError(Object e) {
    if (e is FirebaseException) {
      final code = e.code.toLowerCase();
      if (code == 'unavailable' ||
          code == 'network-request-failed' ||
          code == 'deadline-exceeded') {
        return true;
      }
    }

    final msg = e.toString().toLowerCase();
    return msg.contains('unknownhostexception') ||
        msg.contains('unable to resolve host') ||
        msg.contains('failed to resolve name') ||
        msg.contains('eai_nodata') ||
        msg.contains('service is unavailable') ||
        msg.contains('unavailable');
  }

  Future<void> _cacheSchools(List<SchoolModel> schools) async {
    final box = await Hive.openBox<Map>(_schoolsCacheBox);
    await box.put(_schoolsCacheKey, {
      'cachedAt': DateTime.now().toIso8601String(),
      'schools': schools
          .map((s) => {'id': s.id, 'name': s.name, 'address': s.address})
          .toList(),
    });
  }

  Future<List<SchoolModel>> _getCachedSchools() async {
    final box = await Hive.openBox<Map>(_schoolsCacheBox);
    final cached = box.get(_schoolsCacheKey);
    if (cached == null) return [];

    final raw = cached['schools'] as List?;
    if (raw == null || raw.isEmpty) return [];

    return raw
        .whereType<Map>()
        .map((item) {
          final data = Map<String, dynamic>.from(item);
          return SchoolModel(
            id: (data['id'] ?? '').toString(),
            name: (data['name'] ?? '').toString(),
            address: data['address']?.toString(),
          );
        })
        .where((s) => s.id.isNotEmpty && s.name.isNotEmpty)
        .toList();
  }

  Future<List<SchoolModel>> fetchSchools() async {
    _lastFetchUsedCache = false;

    try {
      final snap = await _firestore
          .collection('schools')
          .orderBy('name')
          .get()
          .timeout(const Duration(seconds: 10));

      if (snap.docs.isEmpty) {
        return [];
      }

      final schools = snap.docs.map((d) {
        return SchoolModel.fromMap(d.id, d.data());
      }).toList();

      await _cacheSchools(schools);

      return schools;
    } catch (e) {
      final cachedSchools = await _getCachedSchools();
      if (cachedSchools.isNotEmpty) {
        _lastFetchUsedCache = true;
        return cachedSchools;
      }

      throw SchoolFetchException(
        _isNetworkOrDnsError(e)
            ? 'Unable to connect. Check internet and try again.'
            : 'Failed to load schools. Please try again.',
        isNetworkIssue: _isNetworkOrDnsError(e),
      );
    }
  }
}
