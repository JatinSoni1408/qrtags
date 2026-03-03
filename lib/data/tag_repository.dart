import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/tag_record.dart';

class TagRepository {
  TagRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static const String _tagsCollection = 'tags';

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _tagsRef =>
      _firestore.collection(_tagsCollection);

  Query<Map<String, dynamic>> queryTags() => _tagsRef;

  Future<AggregateQuerySnapshot> countTags() => _tagsRef.count().get();

  Future<AggregateQuerySnapshot> countPendingTags() {
    return _tagsRef.where('inventoryPending', isEqualTo: true).count().get();
  }

  Future<QuerySnapshot<Map<String, dynamic>>> getAllTags() => _tagsRef.get();

  Query<Map<String, dynamic>> queryPendingTags({
    required int limit,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
  }) {
    Query<Map<String, dynamic>> query = _tagsRef
        .where('inventoryPending', isEqualTo: true)
        .orderBy('createdAt', descending: true);
    if (cursor != null) {
      query = query.startAfterDocument(cursor);
    }
    return query.limit(limit);
  }

  Query<Map<String, dynamic>> queryRecentlyAddedTags({
    int limit = 60,
  }) {
    return _tagsRef.where('inventoryQueued', isEqualTo: true).limit(limit);
  }

  TagRecord toTagRecord(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    return TagRecord.fromSnapshot(doc);
  }

  List<TagRecord> toTagRecords(QuerySnapshot<Map<String, dynamic>> snapshot) {
    return snapshot.docs.map(toTagRecord).toList();
  }

  Future<DocumentReference<Map<String, dynamic>>> createTag(
    Map<String, dynamic> data,
  ) {
    return _tagsRef.add(data);
  }

  Future<void> updateTag(String id, Map<String, dynamic> data) {
    return _tagsRef.doc(id).update(data);
  }

  Future<void> deleteTag(String id) {
    return _tagsRef.doc(id).delete();
  }

  Future<void> markTagsAsAdded(
    List<String> ids, {
    int chunkSize = 400,
  }) async {
    if (ids.isEmpty) {
      return;
    }
    for (int i = 0; i < ids.length; i += chunkSize) {
      final end = (i + chunkSize > ids.length) ? ids.length : i + chunkSize;
      final chunk = ids.sublist(i, end);
      final batch = _firestore.batch();
      for (final id in chunk) {
        batch.set(_tagsRef.doc(id), {
          'inventoryPending': false,
          'inventoryAdded': true,
          'inventoryAddedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
    }
  }

  Future<void> markTagsAsRecentlyAdded(
    List<String> ids, {
    int chunkSize = 400,
  }) async {
    if (ids.isEmpty) {
      return;
    }
    for (int i = 0; i < ids.length; i += chunkSize) {
      final end = (i + chunkSize > ids.length) ? ids.length : i + chunkSize;
      final chunk = ids.sublist(i, end);
      final batch = _firestore.batch();
      for (final id in chunk) {
        batch.set(_tagsRef.doc(id), {
          'inventoryPending': false,
          'inventoryQueued': true,
          'inventoryQueuedAt': FieldValue.serverTimestamp(),
          'inventoryAdded': false,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
    }
  }

  Future<void> transferRecentlyAddedToInventory(
    List<String> ids, {
    int chunkSize = 400,
  }) async {
    if (ids.isEmpty) {
      return;
    }
    for (int i = 0; i < ids.length; i += chunkSize) {
      final end = (i + chunkSize > ids.length) ? ids.length : i + chunkSize;
      final chunk = ids.sublist(i, end);
      final batch = _firestore.batch();
      for (final id in chunk) {
        batch.set(_tagsRef.doc(id), {
          'inventoryQueued': false,
          'inventoryQueuedAt': FieldValue.delete(),
          'inventoryAdded': true,
          'inventoryAddedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
    }
  }
}
