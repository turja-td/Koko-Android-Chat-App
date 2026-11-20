import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models.dart';

class UserService {
  UserService._();
  static final instance = UserService._();

  final _db = FirebaseFirestore.instance;

  Stream<AppUser?> watch(String uid) => _db.collection('users').doc(uid).snapshots().map(
        (s) => s.data() == null ? null : AppUser.fromMap(s.data()!),
      );

  /// Email is intentionally not editable.
  Future<void> updateProfile({required String name, required String about}) async {
    final user = FirebaseAuth.instance.currentUser!;
    await _db.collection('users').doc(user.uid).set(
      {'name': name.trim(), 'about': about.trim()},
      SetOptions(merge: true),
    );
    await user.updateDisplayName(name.trim());
  }

  Future<void> setHidePresence(bool hide) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await _db.collection('users').doc(uid).set({'hidePresence': hide}, SetOptions(merge: true));
  }

  Future<void> setPhoto(String url) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    await _db.collection('users').doc(uid).set({'photoUrl': url}, SetOptions(merge: true));
  }
}
