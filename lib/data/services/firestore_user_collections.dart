// lib/data/services/firestore_user_collections.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class UserCollections {
  final String uid;
  final FirebaseFirestore _db;
  UserCollections(this.uid, {FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get invoices =>
      _db.collection('users').doc(uid).collection('invoices');

  CollectionReference<Map<String, dynamic>> get tenants =>
      _db.collection('users').doc(uid).collection('tenants');

  CollectionReference<Map<String, dynamic>> get properties =>
      _db.collection('users').doc(uid).collection('properties');

  CollectionReference<Map<String, dynamic>> get contracts =>
      _db.collection('users').doc(uid).collection('contracts');

  CollectionReference<Map<String, dynamic>> get maintenance =>
      _db.collection('users').doc(uid).collection('maintenance');

  // اختياري:
  CollectionReference<Map<String, dynamic>> get session =>
      _db.collection('users').doc(uid).collection('session');
}
