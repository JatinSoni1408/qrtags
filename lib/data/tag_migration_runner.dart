import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TagMigrationRunner {
  static const String _migrationKey = 'tags_migration_v1_done';
  static const int _pageSize = 300;

  static Future<void> runIfNeeded({
    required SharedPreferences prefs,
    FirebaseFirestore? firestore,
  }) async {
    if (prefs.getBool(_migrationKey) ?? false) {
      return;
    }

    final db = firestore ?? FirebaseFirestore.instance;
    DocumentSnapshot<Map<String, dynamic>>? cursor;
    bool hasMore = true;

    while (hasMore) {
      Query<Map<String, dynamic>> query = db
          .collection('tags')
          .orderBy(FieldPath.documentId)
          .limit(_pageSize);
      if (cursor != null) {
        query = query.startAfterDocument(cursor);
      }

      final snapshot = await query.get();
      final docs = snapshot.docs;
      if (docs.isEmpty) {
        break;
      }

      final batch = db.batch();
      bool hasWrites = false;

      for (final doc in docs) {
        final data = doc.data();
        final patch = <String, dynamic>{};

        if (!data.containsKey('inventoryPending')) {
          patch['inventoryPending'] = false;
        }
        if (!data.containsKey('inventoryAdded')) {
          patch['inventoryAdded'] = false;
        }

        final itemName = data['itemName']?.toString().trim() ?? '';
        final itemNameLower = data['itemNameLower']?.toString().trim() ?? '';
        if (itemName.isNotEmpty && itemNameLower.isEmpty) {
          patch['itemNameLower'] = itemName.toLowerCase();
        }

        if (patch.isNotEmpty) {
          batch.set(
            db.collection('tags').doc(doc.id),
            patch,
            SetOptions(merge: true),
          );
          hasWrites = true;
        }
      }

      if (hasWrites) {
        await batch.commit();
      }

      cursor = docs.last;
      hasMore = docs.length == _pageSize;
    }

    await prefs.setBool(_migrationKey, true);
  }
}
