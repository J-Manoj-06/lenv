import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import 'firestore_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirestoreService _firestoreService = FirestoreService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Get current user stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Sign in with email and password - ROLE BASED
  Future<UserModel?> signInWithEmailPassword(
    String email,
    String password,
  ) async {
    try {
      final UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (result.user != null) {
        // Try to find user in role-based collections first
        final userFromRoleCollections = await _getUserFromRoleCollections(
          result.user!.uid,
          email,
        );
        if (userFromRoleCollections != null) {
          return userFromRoleCollections;
        }

        // Fallback to users collection
        return await _firestoreService.getUser(result.user!.uid);
      }
      return null;
    } catch (e) {
      throw Exception('Sign in failed: ${e.toString()}');
    }
  }

  // Search for user in role-based collections (teachers, students, principals, parents)
  Future<UserModel?> _getUserFromRoleCollections(
    String uid,
    String email,
  ) async {
    try {
      print('🔍 Searching for user with email: $email');

      // Define collection-role mapping
      final collections = {
        'teachers': UserRole.teacher,
        'students': UserRole.student,
        'principals':
            UserRole.institute, // Using 'institute' role for principals
        'parents': UserRole.parent,
      };

      // Search in each collection by email
      for (var entry in collections.entries) {
        final collectionName = entry.key;
        final role = entry.value;

        print('  Checking $collectionName collection...');

        // Try searching by 'email' field first
        var querySnapshot = await _firestore
            .collection(collectionName)
            .where('email', isEqualTo: email)
            .limit(1)
            .get();

        // If not found and it's students collection, try alternative field names
        if (querySnapshot.docs.isEmpty && collectionName == 'students') {
          print('    Not found by email, trying studentEmail field...');
          querySnapshot = await _firestore
              .collection(collectionName)
              .where('studentEmail', isEqualTo: email)
              .limit(1)
              .get();
        }

        if (querySnapshot.docs.isNotEmpty) {
          print('  ✅ Found user in $collectionName');
          final data = querySnapshot.docs.first.data();
          print('  📄 Document data: $data');

          // UPDATE: Ensure the user document in 'users' collection has the correct Auth UID
          try {
            final userDocQuery = await _firestore
                .collection('users')
                .where('email', isEqualTo: email)
                .limit(1)
                .get();

            if (userDocQuery.docs.isNotEmpty) {
              final userDoc = userDocQuery.docs.first;
              final userData = userDoc.data();
              final storedUid = (userData['uid'] as String?)?.trim();

              // If uid is empty or doesn't match, update it
              if (storedUid == null || storedUid.isEmpty || storedUid != uid) {
                print('  🔄 Updating users document with Auth UID: $uid');
                await _firestore.collection('users').doc(userDoc.id).update({
                  'uid': uid,
                });
                print('  ✅ Users document updated successfully');
              }
            }
          } catch (e) {
            print('  ⚠️ Failed to update users document: $e');
            // Continue anyway - not critical
          }

          // Convert Firestore document to UserModel
          return UserModel(
            uid: uid, // Use Firebase Auth UID
            email: email,
            name:
                data['teacherName'] ??
                data['studentName'] ??
                data['principalName'] ??
                data['parentName'] ??
                data['name'] ??
                'Unknown',
            role: role,
            phone: data['phone']?.toString(),
            profileImage:
                data['photoUrl']?.toString() ??
                data['profileImage']?.toString(),
            instituteId: data['schoolId'] ?? data['schoolCode'],
            createdAt:
                (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
            isActive: data['isActive'] ?? true,
          );
        }
      }

      print('  ⚠️ User not found in any role collection');
      return null;
    } catch (e, stackTrace) {
      print('❌ Error searching role collections: $e');
      print('Stack trace: $stackTrace');
      return null;
    }
  }

  // Register with email and password
  Future<UserModel?> registerWithEmailPassword({
    required String email,
    required String password,
    required String name,
    required UserRole role,
    String? phone,
    String? instituteId,
  }) async {
    try {
      final UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (result.user != null) {
        final user = UserModel(
          uid: result.user!.uid,
          email: email,
          name: name,
          role: role,
          phone: phone,
          instituteId: instituteId,
          createdAt: DateTime.now(),
          isActive: true,
        );

        await _firestoreService.createUser(user);
        return user;
      }
      return null;
    } catch (e) {
      throw Exception('Registration failed: ${e.toString()}');
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      throw Exception('Sign out failed: ${e.toString()}');
    }
  }

  // Reset password
  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } catch (e) {
      throw Exception('Password reset failed: ${e.toString()}');
    }
  }

  // Update user profile
  Future<void> updateProfile({String? displayName, String? photoURL}) async {
    try {
      await currentUser?.updateDisplayName(displayName);
      await currentUser?.updatePhotoURL(photoURL);
    } catch (e) {
      throw Exception('Profile update failed: ${e.toString()}');
    }
  }

  // Delete account
  Future<void> deleteAccount() async {
    try {
      await currentUser?.delete();
    } catch (e) {
      throw Exception('Account deletion failed: ${e.toString()}');
    }
  }
}
