import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class FirestoreCollections {
  const FirestoreCollections._();

  static const users = 'users';
  static const publicProfiles = 'publicProfiles';
  static const nicknames = 'nicknames';
  static const admins = 'admins';
  static const roles = 'roles';
  static const councils = 'councils';
  static const votes = 'votes';
  static const comments = 'comments';
  static const notifications = 'notifications';
  static const conversations = 'conversations';
  static const messages = 'messages';
  static const fcmTokens = 'fcmTokens';
  static const reports = 'reports';
  static const councilResults = 'councilResults';
  static const categories = 'categories';
  static const sponsorships = 'sponsorships';
  static const boosts = 'boosts';
  static const subscriptions = 'subscriptions';
  static const companyPolls = 'companyPolls';
  static const appSettings = 'appSettings';
  static const auditLogs = 'auditLogs';
  static const analyticsDaily = 'analyticsDaily';
  static const sponsorshipCampaigns = sponsorships;
  static const sponsorshipRequests = 'sponsorshipRequests';
  static const adProducts = 'adProducts';
  static const adPackages = 'adPackages';
  static const adRequests = sponsorshipRequests;
}

class FirestoreService {
  FirestoreService._();

  static final FirestoreService instance = FirestoreService._();

  final FirebaseFirestore db = FirebaseFirestore.instance;
  final FirebaseStorage storage = FirebaseStorage.instance;

  CollectionReference<Map<String, dynamic>> get users =>
      db.collection(FirestoreCollections.users);

  CollectionReference<Map<String, dynamic>> get publicProfiles =>
      db.collection(FirestoreCollections.publicProfiles);

  CollectionReference<Map<String, dynamic>> get nicknames =>
      db.collection(FirestoreCollections.nicknames);

  CollectionReference<Map<String, dynamic>> get councils =>
      db.collection(FirestoreCollections.councils);

  CollectionReference<Map<String, dynamic>> get comments =>
      db.collection(FirestoreCollections.comments);

  CollectionReference<Map<String, dynamic>> get reports =>
      db.collection(FirestoreCollections.reports);

  CollectionReference<Map<String, dynamic>> get conversations =>
      db.collection(FirestoreCollections.conversations);

  CollectionReference<Map<String, dynamic>> get councilResults =>
      db.collection(FirestoreCollections.councilResults);

  CollectionReference<Map<String, dynamic>> get categories =>
      db.collection(FirestoreCollections.categories);

  CollectionReference<Map<String, dynamic>> get sponsorshipCampaigns =>
      db.collection(FirestoreCollections.sponsorshipCampaigns);

  CollectionReference<Map<String, dynamic>> get adProducts =>
      db.collection(FirestoreCollections.adProducts);

  CollectionReference<Map<String, dynamic>> get adPackages =>
      db.collection(FirestoreCollections.adPackages);

  CollectionReference<Map<String, dynamic>> get adRequests =>
      db.collection(FirestoreCollections.adRequests);

  CollectionReference<Map<String, dynamic>> get sponsorships =>
      db.collection(FirestoreCollections.sponsorships);

  CollectionReference<Map<String, dynamic>> get boosts =>
      db.collection(FirestoreCollections.boosts);

  CollectionReference<Map<String, dynamic>> get subscriptions =>
      db.collection(FirestoreCollections.subscriptions);

  CollectionReference<Map<String, dynamic>> get companyPolls =>
      db.collection(FirestoreCollections.companyPolls);

  DocumentReference<Map<String, dynamic>> get appSettings =>
      db.collection(FirestoreCollections.appSettings).doc('main');

  CollectionReference<Map<String, dynamic>> get sponsorshipRequests =>
      db.collection(FirestoreCollections.sponsorshipRequests);

  DocumentReference<Map<String, dynamic>> user(String uid) => users.doc(uid);

  DocumentReference<Map<String, dynamic>> publicProfile(String uid) {
    return publicProfiles.doc(uid);
  }

  DocumentReference<Map<String, dynamic>> nickname(String nicknameKey) {
    return nicknames.doc(nicknameKey);
  }

  CollectionReference<Map<String, dynamic>> userNotifications(String uid) {
    return user(uid).collection(FirestoreCollections.notifications);
  }

  CollectionReference<Map<String, dynamic>> userFcmTokens(String uid) {
    return user(uid).collection(FirestoreCollections.fcmTokens);
  }

  DocumentReference<Map<String, dynamic>> council(String councilId) {
    return councils.doc(councilId);
  }

  DocumentReference<Map<String, dynamic>> conversation(String conversationId) {
    return conversations.doc(conversationId);
  }

  CollectionReference<Map<String, dynamic>> conversationMessages(
    String conversationId,
  ) {
    return conversation(conversationId)
        .collection(FirestoreCollections.messages);
  }

  CollectionReference<Map<String, dynamic>> councilVotes(String councilId) {
    return council(councilId).collection(FirestoreCollections.votes);
  }

  CollectionReference<Map<String, dynamic>> councilComments(String councilId) {
    return comments;
  }

  DocumentReference<Map<String, dynamic>> councilResult(String councilId) {
    return councilResults.doc(councilId);
  }

  Reference userAvatarRef(String uid, String fileName) {
    return storage.ref('users/$uid/avatar/$fileName');
  }

  Reference councilMediaRef(String councilId, String fileName) {
    return storage.ref('councils/$councilId/cover/$fileName');
  }

  Reference councilImageRef(String councilId, String uid, String fileName) {
    return storage.ref('councils/$councilId/images/$uid/$fileName');
  }

  Reference conversationImageRef(
    String conversationId,
    String uid,
    String fileName,
  ) {
    return storage.ref('conversations/$conversationId/images/$uid/$fileName');
  }

  String newCouncilId() => councils.doc().id;
  String newReportId() => reports.doc().id;

  WriteBatch batch() => db.batch();

  Future<T> runTransaction<T>(
    Future<T> Function(Transaction transaction) handler,
  ) {
    return db.runTransaction<T>(handler);
  }
}
