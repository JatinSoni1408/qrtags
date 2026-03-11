import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import '../data/tag_repository.dart';
import '../features/generate/generate_tag_normalizer.dart';
import '../models/edit_tag_request.dart';
import '../models/tag_record.dart';
import '../utils/qr_logo_loader.dart';
import '../utils/share_file_namer.dart';
import '../widgets/shared_item_form_layout.dart';

class GeneratePage extends StatefulWidget {
  const GeneratePage({
    super.key,
    required this.editRequest,
    this.onUpdated,
    this.canManageMasterData = true,
    this.firestore,
  });

  final ValueListenable<EditTagRequest?> editRequest;
  final VoidCallback? onUpdated;
  final bool canManageMasterData;
  final FirebaseFirestore? firestore;

  @override
  State<GeneratePage> createState() => _GeneratePageState();
}

class _GeneratePageState extends State<GeneratePage> {
  static const String _lessCategoriesKey = 'less_categories';
  static const String _additionalTypesKey = 'additional_types';
  static const String _lessCategoryEntriesKey = 'less_category_entries';
  static const String _additionalEntriesKey = 'additional_entries';
  static const String _lastCategoryKey = 'last_required_category';
  static const String _lastItemNameKey = 'last_required_item_name';
  static const String _lastMakingTypeKey = 'last_required_making_type';
  static const String _lastMakingChargeKey = 'last_required_making_charge';
  static const String _recentItemNameKey = 'recent_item_name';
  static const String _huidCheckedKey = 'huid_checked';
  static const String _itemNamesKey = 'item_names';
  static const String _categoriesKey = 'categories';
  static const String _makingTypesGoldKey = 'making_types_gold';
  static const String _makingTypesSilverKey = 'making_types_silver';
  static const String _itemNamesCollection = 'item_names';
  static const String _lessCategoriesCollection = 'less_categories';
  static const String _additionalTypesCollection = 'additional_types';
  static const String _categoriesCollection = 'categories';
  static const String _makingTypesGoldCollection = 'making_types_gold';
  static const String _makingTypesSilverCollection = 'making_types_silver';
  String? _selectedCategory;
  String? _selectedMakingType;
  String? _selectedReturnPurity;
  String? _selectedItemName;
  String? _lastCategory;
  String? _lastItemName;
  String? _lastMakingType;
  String? _lastMakingCharge;
  String? _recentItemName;

  bool _searchable = false;
  bool _crud = false;
  bool _persistence = false;
  bool _isHuidChecked = false;

  final List<String> _defaultCategories = ['Gold22kt', 'Gold18kt', 'Silver'];
  final List<String> _categories = [];
  final List<String> _defaultItemNames = [
    'Chain',
    'Bracelets',
    'Mangal Sutra',
    'Pendals',
  ];
  final List<String> _itemNames = [];
  final List<String> _defaultMakingTypesGold = [
    'FixRate',
    'Percentage',
    'TotalMaking',
  ];
  final List<String> _defaultMakingTypesSilver = [
    'PerGram',
    'TotalMaking',
    'FixRate',
  ];
  final List<String> _makingTypesGold = [];
  final List<String> _makingTypesSilver = [];
  final List<String> _percentageOptions = List.generate(11, (i) => '${i + 8}%');
  final List<String> _returnPurityOptions = ['50%', '60%', '70%', '80%', '92%'];
  final List<String> _defaultLessCategories = ['Stones', 'Meena', 'Kundan'];
  final List<String> _lessCategories = [];
  final List<String> _defaultAdditionalTypes = [
    'Stone Settings',
    'Kundan Work',
    'Meenakari',
    'Frosting',
    'Gheru',
    'Sandblasting',
    'Polishing',
    'Brushing',
  ];
  final List<String> _additionalTypes = [];

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _itemNamesSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _lessCategoriesSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _additionalTypesSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _categoriesSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _makingTypesGoldSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _makingTypesSilverSub;
  bool _seedingItemNames = false;
  bool _seedingLessCategories = false;
  bool _seedingAdditionalTypes = false;
  bool _seedingCategories = false;
  bool _seedingMakingTypesGold = false;
  bool _seedingMakingTypesSilver = false;

  void _sortList(List<String> list) {
    list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  String _normalizeItemName(String value) => value.trim();

  String _itemNameDocId(String value) => value.trim().toLowerCase();

  CollectionReference<Map<String, dynamic>> get _itemNamesRef =>
      _firestore.collection(_itemNamesCollection);

  String _normalizeLessCategory(String value) => value.trim();

  String _lessCategoryDocId(String value) => value.trim().toLowerCase();

  CollectionReference<Map<String, dynamic>> get _lessCategoriesRef =>
      _firestore.collection(_lessCategoriesCollection);

  String _normalizeAdditionalType(String value) => value.trim();

  String _additionalTypeDocId(String value) => value.trim().toLowerCase();

  CollectionReference<Map<String, dynamic>> get _additionalTypesRef =>
      _firestore.collection(_additionalTypesCollection);

  String _normalizeCategory(String value) => value.trim();

  String _categoryDocId(String value) => value.trim().toLowerCase();

  CollectionReference<Map<String, dynamic>> get _categoriesRef =>
      _firestore.collection(_categoriesCollection);

  String _normalizeMakingType(String value) => value.trim();

  String _makingTypeDocId(String value) => value.trim().toLowerCase();

  CollectionReference<Map<String, dynamic>> get _makingTypesGoldRef =>
      _firestore.collection(_makingTypesGoldCollection);

  CollectionReference<Map<String, dynamic>> get _makingTypesSilverRef =>
      _firestore.collection(_makingTypesSilverCollection);

  List<String> _makingTypesForCategory(String? category) {
    if (category == 'Silver') {
      return _makingTypesSilver;
    }
    if (category == 'Gold22kt' || category == 'Gold18kt') {
      return _makingTypesGold;
    }
    return const [];
  }

  final TextEditingController _makingChargeController = TextEditingController();
  final TextEditingController _itemNameController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _grossWeightController = TextEditingController();
  final TextEditingController _lessWeightController = TextEditingController();
  final TextEditingController _netWeightController = TextEditingController();
  final List<_LessCategoryEntry> _lessCategoryEntries = [_LessCategoryEntry()];
  final List<_AdditionalEntry> _additionalEntries = [_AdditionalEntry()];

  late final FirebaseFirestore _firestore;
  late final TagRepository _tagRepository;

  String? _qrData;
  String? _editingTagId;
  Map<String, dynamic>? _editingOriginalData;

  @override
  void initState() {
    super.initState();
    _firestore = widget.firestore ?? FirebaseFirestore.instance;
    _tagRepository = TagRepository(firestore: _firestore);
    _grossWeightController.addListener(_updateWeights);
    for (final entry in _lessCategoryEntries) {
      entry.valueController.addListener(_updateWeights);
    }
    _loadPrefs().then((_) {
      _resetForm(restoreLastRequiredValues: true);
      _startItemNamesSync();
      _startLessCategoriesSync();
      _startAdditionalTypesSync();
      _startCategoriesSync();
      _startMakingTypesGoldSync();
      _startMakingTypesSilverSync();
    });
    widget.editRequest.addListener(_handleEditRequest);
    _handleEditRequest();
  }

  @override
  void dispose() {
    widget.editRequest.removeListener(_handleEditRequest);
    _itemNamesSub?.cancel();
    _lessCategoriesSub?.cancel();
    _additionalTypesSub?.cancel();
    _categoriesSub?.cancel();
    _makingTypesGoldSub?.cancel();
    _makingTypesSilverSub?.cancel();
    _makingChargeController.dispose();
    _itemNameController.dispose();
    _locationController.dispose();
    _grossWeightController.dispose();
    _lessWeightController.dispose();
    _netWeightController.dispose();
    for (final entry in _lessCategoryEntries) {
      entry.dispose();
    }
    for (final entry in _additionalEntries) {
      entry.dispose();
    }
    super.dispose();
  }

  void _startItemNamesSync() {
    _itemNamesSub?.cancel();
    _itemNamesSub = _itemNamesRef.orderBy('nameLower').snapshots().listen((
      snapshot,
    ) async {
      final names = snapshot.docs
          .map((doc) => doc.data()['name']?.toString().trim())
          .whereType<String>()
          .where((name) => name.isNotEmpty)
          .toList();

      if (names.isEmpty) {
        await _seedItemNamesIfEmpty();
        return;
      }

      _sortList(names);
      if (!mounted) {
        return;
      }
      setState(() {
        _itemNames
          ..clear()
          ..addAll(names);
      });
      await _saveItemNamesToPrefs();
    });
    _seedItemNamesIfEmpty();
  }

  Future<void> _seedItemNamesIfEmpty() async {
    if (_seedingItemNames) {
      return;
    }
    _seedingItemNames = true;
    try {
      final existing = await _itemNamesRef.limit(1).get();
      if (existing.docs.isNotEmpty) {
        return;
      }
      final fromTags = await _loadItemNamesFromTags();
      final seedSource = fromTags.isNotEmpty
          ? fromTags
          : (_itemNames.isNotEmpty ? _itemNames : _defaultItemNames);
      final unique = <String>{};
      final batch = _firestore.batch();
      for (final name in seedSource) {
        final normalized = _normalizeItemName(name);
        if (normalized.isEmpty) {
          continue;
        }
        final docId = _itemNameDocId(normalized);
        if (!unique.add(docId)) {
          continue;
        }
        batch.set(_itemNamesRef.doc(docId), {
          'name': normalized,
          'nameLower': docId,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      if (unique.isNotEmpty) {
        await batch.commit();
      }
    } catch (_) {
      // ignore seeding failures
    } finally {
      _seedingItemNames = false;
    }
  }

  Future<List<String>> _loadItemNamesFromTags() async {
    try {
      final snapshot = await _tagRepository.getAllTags();
      final tags = _tagRepository.toTagRecords(snapshot);
      final unique = <String>{};
      for (final tag in tags) {
        final name = tag.itemName.trim();
        if (name.isNotEmpty) {
          unique.add(name);
        }
      }
      return unique.toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveItemNamesToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_itemNamesKey, _itemNames);
  }

  Future<void> _upsertItemNameRemote(String name) async {
    final normalized = _normalizeItemName(name);
    if (normalized.isEmpty) {
      return;
    }
    final docId = _itemNameDocId(normalized);
    await _itemNamesRef.doc(docId).set({
      'name': normalized,
      'nameLower': docId,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _renameItemNameRemote(String oldName, String newName) async {
    final normalizedOld = _normalizeItemName(oldName);
    final normalizedNew = _normalizeItemName(newName);
    if (normalizedNew.isEmpty) {
      return;
    }
    final oldId = _itemNameDocId(normalizedOld);
    final newId = _itemNameDocId(normalizedNew);
    if (oldId == newId) {
      await _itemNamesRef.doc(oldId).set({
        'name': normalizedNew,
        'nameLower': newId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }
    final batch = _firestore.batch();
    batch.set(_itemNamesRef.doc(newId), {
      'name': normalizedNew,
      'nameLower': newId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.delete(_itemNamesRef.doc(oldId));
    await batch.commit();
  }

  Future<void> _deleteItemNameRemote(String name) async {
    final normalized = _normalizeItemName(name);
    if (normalized.isEmpty) {
      return;
    }
    final docId = _itemNameDocId(normalized);
    await _itemNamesRef.doc(docId).delete();
  }

  void _startLessCategoriesSync() {
    _lessCategoriesSub?.cancel();
    _lessCategoriesSub = _lessCategoriesRef
        .orderBy('nameLower')
        .snapshots()
        .listen((snapshot) async {
          final names = snapshot.docs
              .map((doc) => doc.data()['name']?.toString().trim())
              .whereType<String>()
              .where((name) => name.isNotEmpty)
              .toList();

          if (names.isEmpty) {
            await _seedLessCategoriesIfEmpty();
            return;
          }

          _sortList(names);
          if (!mounted) {
            return;
          }
          setState(() {
            _lessCategories
              ..clear()
              ..addAll(names);
          });
          await _saveLessCategoriesToPrefs();
        });
    _seedLessCategoriesIfEmpty();
  }

  Future<void> _seedLessCategoriesIfEmpty() async {
    if (_seedingLessCategories) {
      return;
    }
    _seedingLessCategories = true;
    try {
      final existing = await _lessCategoriesRef.limit(1).get();
      if (existing.docs.isNotEmpty) {
        return;
      }
      final seedSource = _lessCategories.isNotEmpty
          ? _lessCategories
          : _defaultLessCategories;
      final unique = <String>{};
      final batch = _firestore.batch();
      for (final name in seedSource) {
        final normalized = _normalizeLessCategory(name);
        if (normalized.isEmpty) {
          continue;
        }
        final docId = _lessCategoryDocId(normalized);
        if (!unique.add(docId)) {
          continue;
        }
        batch.set(_lessCategoriesRef.doc(docId), {
          'name': normalized,
          'nameLower': docId,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      if (unique.isNotEmpty) {
        await batch.commit();
      }
    } catch (_) {
      // ignore seeding failures
    } finally {
      _seedingLessCategories = false;
    }
  }

  Future<void> _saveLessCategoriesToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_lessCategoriesKey, _lessCategories);
  }

  Future<void> _upsertLessCategoryRemote(String name) async {
    final normalized = _normalizeLessCategory(name);
    if (normalized.isEmpty) {
      return;
    }
    final docId = _lessCategoryDocId(normalized);
    await _lessCategoriesRef.doc(docId).set({
      'name': normalized,
      'nameLower': docId,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _renameLessCategoryRemote(String oldName, String newName) async {
    final normalizedOld = _normalizeLessCategory(oldName);
    final normalizedNew = _normalizeLessCategory(newName);
    if (normalizedNew.isEmpty) {
      return;
    }
    final oldId = _lessCategoryDocId(normalizedOld);
    final newId = _lessCategoryDocId(normalizedNew);
    if (oldId == newId) {
      await _lessCategoriesRef.doc(oldId).set({
        'name': normalizedNew,
        'nameLower': newId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }
    final batch = _firestore.batch();
    batch.set(_lessCategoriesRef.doc(newId), {
      'name': normalizedNew,
      'nameLower': newId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.delete(_lessCategoriesRef.doc(oldId));
    await batch.commit();
  }

  Future<void> _deleteLessCategoryRemote(String name) async {
    final normalized = _normalizeLessCategory(name);
    if (normalized.isEmpty) {
      return;
    }
    final docId = _lessCategoryDocId(normalized);
    await _lessCategoriesRef.doc(docId).delete();
  }

  void _startAdditionalTypesSync() {
    _additionalTypesSub?.cancel();
    _additionalTypesSub = _additionalTypesRef
        .orderBy('nameLower')
        .snapshots()
        .listen((snapshot) async {
          final names = snapshot.docs
              .map((doc) => doc.data()['name']?.toString().trim())
              .whereType<String>()
              .where((name) => name.isNotEmpty)
              .toList();

          if (names.isEmpty) {
            await _seedAdditionalTypesIfEmpty();
            return;
          }

          _sortList(names);
          if (!mounted) {
            return;
          }
          setState(() {
            _additionalTypes
              ..clear()
              ..addAll(names);
          });
          await _saveAdditionalTypesToPrefs();
        });
    _seedAdditionalTypesIfEmpty();
  }

  Future<void> _seedAdditionalTypesIfEmpty() async {
    if (_seedingAdditionalTypes) {
      return;
    }
    _seedingAdditionalTypes = true;
    try {
      final existing = await _additionalTypesRef.limit(1).get();
      if (existing.docs.isNotEmpty) {
        return;
      }
      final seedSource = _additionalTypes.isNotEmpty
          ? _additionalTypes
          : _defaultAdditionalTypes;
      final unique = <String>{};
      final batch = _firestore.batch();
      for (final name in seedSource) {
        final normalized = _normalizeAdditionalType(name);
        if (normalized.isEmpty) {
          continue;
        }
        final docId = _additionalTypeDocId(normalized);
        if (!unique.add(docId)) {
          continue;
        }
        batch.set(_additionalTypesRef.doc(docId), {
          'name': normalized,
          'nameLower': docId,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      if (unique.isNotEmpty) {
        await batch.commit();
      }
    } catch (_) {
      // ignore seeding failures
    } finally {
      _seedingAdditionalTypes = false;
    }
  }

  Future<void> _saveAdditionalTypesToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_additionalTypesKey, _additionalTypes);
  }

  Future<void> _upsertAdditionalTypeRemote(String name) async {
    final normalized = _normalizeAdditionalType(name);
    if (normalized.isEmpty) {
      return;
    }
    final docId = _additionalTypeDocId(normalized);
    await _additionalTypesRef.doc(docId).set({
      'name': normalized,
      'nameLower': docId,
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _renameAdditionalTypeRemote(
    String oldName,
    String newName,
  ) async {
    final normalizedOld = _normalizeAdditionalType(oldName);
    final normalizedNew = _normalizeAdditionalType(newName);
    if (normalizedNew.isEmpty) {
      return;
    }
    final oldId = _additionalTypeDocId(normalizedOld);
    final newId = _additionalTypeDocId(normalizedNew);
    if (oldId == newId) {
      await _additionalTypesRef.doc(oldId).set({
        'name': normalizedNew,
        'nameLower': newId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }
    final batch = _firestore.batch();
    batch.set(_additionalTypesRef.doc(newId), {
      'name': normalizedNew,
      'nameLower': newId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.delete(_additionalTypesRef.doc(oldId));
    await batch.commit();
  }

  Future<void> _deleteAdditionalTypeRemote(String name) async {
    final normalized = _normalizeAdditionalType(name);
    if (normalized.isEmpty) {
      return;
    }
    final docId = _additionalTypeDocId(normalized);
    await _additionalTypesRef.doc(docId).delete();
  }

  void _startCategoriesSync() {
    _categoriesSub?.cancel();
    _categoriesSub = _categoriesRef.orderBy('nameLower').snapshots().listen((
      snapshot,
    ) async {
      final names = snapshot.docs
          .map((doc) => doc.data()['name']?.toString().trim())
          .whereType<String>()
          .where((name) => name.isNotEmpty)
          .toList();

      if (names.isEmpty) {
        await _seedCategoriesIfEmpty();
        return;
      }

      _sortList(names);
      if (!mounted) {
        return;
      }
      setState(() {
        _categories
          ..clear()
          ..addAll(names);
        if (_selectedCategory != null &&
            !_categories.contains(_selectedCategory)) {
          _selectedCategory = null;
          _selectedMakingType = null;
        }
      });
      await _saveCategoriesToPrefs();
    });
    _seedCategoriesIfEmpty();
  }

  Future<void> _seedCategoriesIfEmpty() async {
    if (_seedingCategories) {
      return;
    }
    _seedingCategories = true;
    try {
      final existing = await _categoriesRef.limit(1).get();
      if (existing.docs.isNotEmpty) {
        return;
      }
      final seedSource = _categories.isNotEmpty
          ? _categories
          : _defaultCategories;
      final unique = <String>{};
      final batch = _firestore.batch();
      for (final name in seedSource) {
        final normalized = _normalizeCategory(name);
        if (normalized.isEmpty) {
          continue;
        }
        final docId = _categoryDocId(normalized);
        if (!unique.add(docId)) {
          continue;
        }
        batch.set(_categoriesRef.doc(docId), {
          'name': normalized,
          'nameLower': docId,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      if (unique.isNotEmpty) {
        await batch.commit();
      }
    } catch (_) {
      // ignore seeding failures
    } finally {
      _seedingCategories = false;
    }
  }

  Future<void> _saveCategoriesToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_categoriesKey, _categories);
  }

  void _startMakingTypesGoldSync() {
    _makingTypesGoldSub?.cancel();
    _makingTypesGoldSub = _makingTypesGoldRef
        .orderBy('nameLower')
        .snapshots()
        .listen((snapshot) async {
          final names = snapshot.docs
              .map((doc) => doc.data()['name']?.toString().trim())
              .whereType<String>()
              .where((name) => name.isNotEmpty)
              .toList();

          if (names.isEmpty) {
            await _seedMakingTypesGoldIfEmpty();
            return;
          }

          _sortList(names);
          if (!mounted) {
            return;
          }
          setState(() {
            _makingTypesGold
              ..clear()
              ..addAll(names);
            if (_selectedCategory != null &&
                _selectedCategory!.startsWith('Gold') &&
                _selectedMakingType != null &&
                !_makingTypesGold.contains(_selectedMakingType)) {
              _selectedMakingType = null;
            }
          });
          await _saveMakingTypesGoldToPrefs();
        });
    _seedMakingTypesGoldIfEmpty();
  }

  Future<void> _seedMakingTypesGoldIfEmpty() async {
    if (_seedingMakingTypesGold) {
      return;
    }
    _seedingMakingTypesGold = true;
    try {
      final existing = await _makingTypesGoldRef.limit(1).get();
      if (existing.docs.isNotEmpty) {
        return;
      }
      final seedSource = _makingTypesGold.isNotEmpty
          ? _makingTypesGold
          : _defaultMakingTypesGold;
      final unique = <String>{};
      final batch = _firestore.batch();
      for (final name in seedSource) {
        final normalized = _normalizeMakingType(name);
        if (normalized.isEmpty) {
          continue;
        }
        final docId = _makingTypeDocId(normalized);
        if (!unique.add(docId)) {
          continue;
        }
        batch.set(_makingTypesGoldRef.doc(docId), {
          'name': normalized,
          'nameLower': docId,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      if (unique.isNotEmpty) {
        await batch.commit();
      }
    } catch (_) {
      // ignore seeding failures
    } finally {
      _seedingMakingTypesGold = false;
    }
  }

  Future<void> _saveMakingTypesGoldToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_makingTypesGoldKey, _makingTypesGold);
  }

  void _startMakingTypesSilverSync() {
    _makingTypesSilverSub?.cancel();
    _makingTypesSilverSub = _makingTypesSilverRef
        .orderBy('nameLower')
        .snapshots()
        .listen((snapshot) async {
          final names = snapshot.docs
              .map((doc) => doc.data()['name']?.toString().trim())
              .whereType<String>()
              .where((name) => name.isNotEmpty)
              .toList();

          if (names.isEmpty) {
            await _seedMakingTypesSilverIfEmpty();
            return;
          }

          _sortList(names);
          if (!mounted) {
            return;
          }
          setState(() {
            _makingTypesSilver
              ..clear()
              ..addAll(names);
            if (_selectedCategory == 'Silver' &&
                _selectedMakingType != null &&
                !_makingTypesSilver.contains(_selectedMakingType)) {
              _selectedMakingType = null;
            }
          });
          await _saveMakingTypesSilverToPrefs();
        });
    _seedMakingTypesSilverIfEmpty();
  }

  Future<void> _seedMakingTypesSilverIfEmpty() async {
    if (_seedingMakingTypesSilver) {
      return;
    }
    _seedingMakingTypesSilver = true;
    try {
      final existing = await _makingTypesSilverRef.limit(1).get();
      if (existing.docs.isNotEmpty) {
        return;
      }
      final seedSource = _makingTypesSilver.isNotEmpty
          ? _makingTypesSilver
          : _defaultMakingTypesSilver;
      final unique = <String>{};
      final batch = _firestore.batch();
      for (final name in seedSource) {
        final normalized = _normalizeMakingType(name);
        if (normalized.isEmpty) {
          continue;
        }
        final docId = _makingTypeDocId(normalized);
        if (!unique.add(docId)) {
          continue;
        }
        batch.set(_makingTypesSilverRef.doc(docId), {
          'name': normalized,
          'nameLower': docId,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      if (unique.isNotEmpty) {
        await batch.commit();
      }
    } catch (_) {
      // ignore seeding failures
    } finally {
      _seedingMakingTypesSilver = false;
    }
  }

  Future<void> _saveMakingTypesSilverToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_makingTypesSilverKey, _makingTypesSilver);
  }

  void _handleEditRequest() {
    final request = widget.editRequest.value;
    if (request == null) {
      return;
    }
    _applyTagData(request.tag);
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final persist = prefs.getBool('persistence') ?? false;
    setState(() {
      _itemNames
        ..clear()
        ..addAll(prefs.getStringList(_itemNamesKey) ?? _defaultItemNames);
      _sortList(_itemNames);
      _categories
        ..clear()
        ..addAll(prefs.getStringList(_categoriesKey) ?? _defaultCategories);
      _sortList(_categories);
      _makingTypesGold
        ..clear()
        ..addAll(
          prefs.getStringList(_makingTypesGoldKey) ?? _defaultMakingTypesGold,
        );
      _sortList(_makingTypesGold);
      _makingTypesSilver
        ..clear()
        ..addAll(
          prefs.getStringList(_makingTypesSilverKey) ??
              _defaultMakingTypesSilver,
        );
      _sortList(_makingTypesSilver);
      _lessCategories
        ..clear()
        ..addAll(
          prefs.getStringList(_lessCategoriesKey) ?? _defaultLessCategories,
        );
      _sortList(_lessCategories);
      _additionalTypes
        ..clear()
        ..addAll(
          prefs.getStringList(_additionalTypesKey) ?? _defaultAdditionalTypes,
        );
      _sortList(_additionalTypes);
      _restoreEntriesFromPrefs(prefs);
      _lastCategory = _trimOrNull(prefs.getString(_lastCategoryKey));
      _lastItemName = _trimOrNull(prefs.getString(_lastItemNameKey));
      _lastMakingType = _trimOrNull(prefs.getString(_lastMakingTypeKey));
      _lastMakingCharge = _trimOrNull(prefs.getString(_lastMakingChargeKey));
      _recentItemName = _trimOrNull(prefs.getString(_recentItemNameKey));
      if (persist) {
        _persistence = true;
        _selectedCategory = prefs.getString('category');
        _selectedItemName = prefs.getString('item_name');
        _itemNameController.text = _selectedItemName ?? '';
        _selectedMakingType = prefs.getString('making_type');
        if (!_makingTypesForCategory(
          _selectedCategory,
        ).contains(_selectedMakingType)) {
          _selectedMakingType = null;
        }
        _makingChargeController.text = prefs.getString('making_charge') ?? '';
        _searchable = prefs.getBool('searchable') ?? false;
        _crud = prefs.getBool('crud') ?? false;
        _isHuidChecked = prefs.getBool(_huidCheckedKey) ?? false;
      }
    });
  }

  bool _isHuidMandatoryValue(dynamic raw) {
    if (raw is bool) {
      return raw;
    }
    final text = raw?.toString().trim().toLowerCase() ?? '';
    if (text.isEmpty) {
      return false;
    }
    return text != 'false' && text != '0' && text != 'no' && text != 'off';
  }

  void _updateWeights() {
    double parse(String v) => double.tryParse(v.trim()) ?? 0.0;
    final gross = parse(_grossWeightController.text);
    double lessTotal = 0;
    for (final entry in _lessCategoryEntries) {
      lessTotal += parse(entry.valueController.text);
    }
    final net = gross - lessTotal;
    _lessWeightController.text = lessTotal.toStringAsFixed(3);
    _netWeightController.text = net.toStringAsFixed(3);
    _saveIfNeeded();
  }

  String? _trimOrNull(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  bool _containsIgnoreCase(List<String> list, String value) {
    final target = value.toLowerCase();
    return list.any((item) => item.toLowerCase() == target);
  }

  void _captureLastRequiredValues() {
    final category = _trimOrNull(_selectedCategory);
    final itemName = _trimOrNull(_selectedItemName);
    final makingType = _trimOrNull(_selectedMakingType);
    final makingCharge = _trimOrNull(_makingChargeController.text);
    if (category != null) {
      _lastCategory = category;
    }
    if (itemName != null) {
      _lastItemName = itemName;
      _recentItemName = itemName;
    }
    if (makingType != null) {
      _lastMakingType = makingType;
    }
    if (makingCharge != null) {
      _lastMakingCharge = makingCharge;
    }
  }

  void _applyLastRequiredValues() {
    final savedCategory = _trimOrNull(_lastCategory);
    if (savedCategory != null && _categories.contains(savedCategory)) {
      _selectedCategory = savedCategory;
    }

    final savedItemName = _trimOrNull(_lastItemName);
    if (savedItemName != null) {
      if (_containsIgnoreCase(_itemNames, savedItemName)) {
        _selectedItemName = _itemNames.firstWhere(
          (item) => item.toLowerCase() == savedItemName.toLowerCase(),
          orElse: () => savedItemName,
        );
      } else {
        _selectedItemName = savedItemName;
      }
      _itemNameController.text = _selectedItemName ?? '';
    }

    final savedMakingType = _trimOrNull(_lastMakingType);
    if (savedMakingType != null &&
        _makingTypesForCategory(_selectedCategory).contains(savedMakingType)) {
      _selectedMakingType = savedMakingType;
    }

    final savedMakingCharge = _trimOrNull(_lastMakingCharge);
    if (savedMakingCharge != null) {
      _makingChargeController.text = savedMakingCharge;
    }
  }

  List<String> _itemNamesWithRecentFirst(String query) {
    final normalizedQuery = query.toLowerCase();
    final filtered = _itemNames
        .where((v) => v.toLowerCase().contains(normalizedQuery))
        .toList();
    final recent = _trimOrNull(_recentItemName);
    if (recent == null || !recent.toLowerCase().contains(normalizedQuery)) {
      return filtered;
    }
    filtered.removeWhere((item) => item.toLowerCase() == recent.toLowerCase());
    filtered.insert(0, recent);
    return filtered;
  }

  void _markRecentItemName(String? value) {
    final normalized = _trimOrNull(value);
    if (normalized == null) {
      return;
    }
    _recentItemName = normalized;
  }

  bool _isUnchangedUpdate(Map<String, dynamic> newData) {
    final original = _editingOriginalData;
    if (original == null) {
      return false;
    }
    return GenerateTagNormalizer.isUnchanged(original, newData);
  }

  void _resetForm({bool restoreLastRequiredValues = false}) {
    setState(() {
      _selectedCategory = null;
      _selectedMakingType = null;
      _selectedItemName = null;
      _itemNameController.text = '';
      _locationController.text = '';
      _makingChargeController.text = '';
      _grossWeightController.text = '';
      _lessWeightController.text = '';
      _netWeightController.text = '';
      for (final entry in _lessCategoryEntries) {
        entry.dispose();
      }
      _lessCategoryEntries
        ..clear()
        ..add(_LessCategoryEntry());
      _lessCategoryEntries.first.valueController.addListener(_updateWeights);
      for (final entry in _additionalEntries) {
        entry.dispose();
      }
      _additionalEntries
        ..clear()
        ..add(_AdditionalEntry());
      _isHuidChecked = false;
      _qrData = null;
      _editingTagId = null;
      _editingOriginalData = null;
      if (restoreLastRequiredValues) {
        _applyLastRequiredValues();
      }
    });
    _saveIfNeeded();
  }

  Future<void> _createTag() async {
    final missingFields = <String>[];
    if ((_selectedCategory ?? '').trim().isEmpty) {
      missingFields.add('Category');
    }
    if ((_selectedItemName ?? '').trim().isEmpty) {
      missingFields.add('Item Name');
    }
    if ((_selectedMakingType ?? '').trim().isEmpty) {
      missingFields.add('Making Type');
    }
    if (_makingChargeController.text.trim().isEmpty) {
      missingFields.add('Making Charge');
    }
    if (_grossWeightController.text.trim().isEmpty) {
      missingFields.add('Gross Weight');
    }
    if (_selectedCategory == 'Silver' && (_selectedReturnPurity ?? '').isEmpty) {
      missingFields.add('Return Purity');
    }
    if (missingFields.isNotEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please fill: ${missingFields.join(', ')}')),
        );
      }
      return;
    }
    final lessEntries = _lessCategoryEntries
        .where(
          (e) =>
              (e.category ?? '').isNotEmpty ||
              e.valueController.text.isNotEmpty,
        )
        .map((e) => {'category': e.category, 'value': e.valueController.text})
        .toList();
    final additionalEntries = _additionalEntries
        .where(
          (e) => (e.type ?? '').isNotEmpty || e.valueController.text.isNotEmpty,
        )
        .map((e) => {'type': e.type, 'value': e.valueController.text})
        .toList();
    _captureLastRequiredValues();
    _markRecentItemName(_selectedItemName);
    await _saveIfNeeded();

    final locationText = _locationController.text.trim();
    final data = <String, dynamic>{
      'category': _selectedCategory,
      'itemName': _selectedItemName,
      'itemNameLower': (_selectedItemName ?? '').trim().toLowerCase(),
      'makingType': _selectedMakingType,
      'makingCharge': _makingChargeController.text,
      'grossWeight': _grossWeightController.text,
      'lessWeight': _lessWeightController.text,
      'netWeight': _netWeightController.text,
      'huid': _isHuidChecked,
      'returnPurity': _selectedReturnPurity,
      'lessCategories': lessEntries,
      'additionalTypes': additionalEntries,
    };
    if (locationText.isNotEmpty) {
      data['location'] = locationText;
    } else {
      data['location'] = FieldValue.delete();
    }
    final currentUser = FirebaseAuth.instance.currentUser;
    final actorUid = currentUser?.uid ?? '';
    final actorEmail = currentUser?.email ?? '';

    try {
      if (_editingTagId == null) {
        final doc = await _tagRepository.createTag({
          ...data,
          'inventoryPending': true,
          'inventoryAdded': false,
          'createdByUid': actorUid,
          'createdByEmail': actorEmail,
          'updatedByUid': actorUid,
          'updatedByEmail': actorEmail,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        setState(() {
          _qrData = 'QR1:${doc.id}';
          _editingTagId = doc.id;
          _editingOriginalData = Map<String, dynamic>.from(data);
        });
      } else {
        if (_isUnchangedUpdate(data)) {
          setState(() {
            _qrData = 'QR1:${_editingTagId!}';
          });
          widget.onUpdated?.call();
          _resetForm(restoreLastRequiredValues: true);
          return;
        }
        await _tagRepository.updateTag(_editingTagId!, {
          ...data,
          'updatedByUid': actorUid,
          'updatedByEmail': actorEmail,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        setState(() {
          _qrData = 'QR1:${_editingTagId!}';
        });
        widget.onUpdated?.call();
        _resetForm(restoreLastRequiredValues: true);
      }
    } catch (_) {
      // If save fails, keep QR empty.
      setState(() {
        _qrData = null;
      });
    }
    // No snackbar on create.
  }

  void _applyTagData(TagRecord tag) {
    final data = tag.rawData;
    setState(() {
      _editingTagId = tag.id;
      _editingOriginalData = Map<String, dynamic>.from(data);
      _qrData = 'QR1:${tag.id}';
      _selectedCategory = tag.category;
      _selectedItemName = tag.itemName;
      _itemNameController.text = _selectedItemName ?? '';
      _locationController.text = data['location']?.toString() ?? '';
      _selectedMakingType = tag.makingType;
      _selectedReturnPurity = tag.returnPurity;
      if (!_makingTypesForCategory(
        _selectedCategory,
      ).contains(_selectedMakingType)) {
        _selectedMakingType = null;
      }
      _makingChargeController.text = tag.makingCharge;
      _grossWeightController.text = tag.grossWeight;
      _lessWeightController.text = tag.lessWeight;
      _netWeightController.text = tag.netWeight;
      _isHuidChecked = _isHuidMandatoryValue(data['huid']);

      for (final entry in _lessCategoryEntries) {
        entry.dispose();
      }
      _lessCategoryEntries.clear();
      final lessRaw = tag.lessCategories;
      if (lessRaw.isNotEmpty) {
        for (final item in lessRaw) {
          final entry = _LessCategoryEntry();
          entry.category = item['category']?.toString();
          entry.categoryController.text = entry.category ?? '';
          entry.valueController.text = item['value']?.toString() ?? '';
          entry.valueController.addListener(_updateWeights);
          _lessCategoryEntries.add(entry);
        }
      }
      if (_lessCategoryEntries.isEmpty) {
        final entry = _LessCategoryEntry();
        entry.valueController.addListener(_updateWeights);
        _lessCategoryEntries.add(entry);
      }

      for (final entry in _additionalEntries) {
        entry.dispose();
      }
      _additionalEntries.clear();
      final additionalRaw = tag.additionalTypes;
      if (additionalRaw.isNotEmpty) {
        for (final item in additionalRaw) {
          final entry = _AdditionalEntry();
          entry.type = item['type']?.toString();
          entry.typeController.text = entry.type ?? '';
          entry.valueController.text = item['value']?.toString() ?? '';
          _additionalEntries.add(entry);
        }
      }
      if (_additionalEntries.isEmpty) {
        _additionalEntries.add(_AdditionalEntry());
      }
    });
  }

  Future<void> _shareQr() async {
    if (_qrData == null) {
      return;
    }
    final bytes = await _buildQrPng(_qrData!, 512, borderPx: 24);
    if (bytes == null) {
      Share.share(_qrData!);
      return;
    }
    final fileName = ShareFileNamer.startBatch(
      prefix: 'gq',
      extension: 'png',
    ).nextName();
    await Share.shareXFiles(
      [XFile.fromData(bytes, name: fileName, mimeType: 'image/png')],
      fileNameOverrides: [fileName],
      text: _qrData!,
    );
  }

  Future<Uint8List?> _buildQrPng(
    String data,
    int sizePx, {
    int borderPx = 0,
  }) async {
    final totalSize = sizePx + (borderPx * 2);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, totalSize.toDouble(), totalSize.toDouble()),
    );
    final paint = Paint()..color = Colors.white;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, totalSize.toDouble(), totalSize.toDouble()),
      paint,
    );

    final logoImage = await QrLogoLoader.loadLogoImage();
    final qrPainter = QrPainter(
      data: data,
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.H,
      gapless: true,
      embeddedImage: logoImage,
      embeddedImageStyle: logoImage == null
          ? null
          : QrEmbeddedImageStyle(size: Size(sizePx * 0.20, sizePx * 0.20)),
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: Colors.black,
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: Colors.black,
      ),
    );
    final qrByteData = await qrPainter.toImageData(sizePx.toDouble());
    if (qrByteData == null) {
      return null;
    }
    final codec = await ui.instantiateImageCodec(
      qrByteData.buffer.asUint8List(),
    );
    final frame = await codec.getNextFrame();
    canvas.drawImage(
      frame.image,
      Offset(borderPx.toDouble(), borderPx.toDouble()),
      Paint(),
    );

    final image = await recorder.endRecording().toImage(totalSize, totalSize);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Future<void> _saveIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    _captureLastRequiredValues();
    await prefs.setStringList(_itemNamesKey, _itemNames);
    await prefs.setStringList(_categoriesKey, _categories);
    await prefs.setStringList(_makingTypesGoldKey, _makingTypesGold);
    await prefs.setStringList(_makingTypesSilverKey, _makingTypesSilver);
    await prefs.setStringList(_lessCategoriesKey, _lessCategories);
    await prefs.setStringList(_additionalTypesKey, _additionalTypes);
    await prefs.setString(
      _lessCategoryEntriesKey,
      jsonEncode(
        _lessCategoryEntries
            .map(
              (e) => {'category': e.category, 'value': e.valueController.text},
            )
            .toList(),
      ),
    );
    await prefs.setString(
      _additionalEntriesKey,
      jsonEncode(
        _additionalEntries
            .map((e) => {'type': e.type, 'value': e.valueController.text})
            .toList(),
      ),
    );
    final lastCategory = _trimOrNull(_lastCategory);
    final lastItemName = _trimOrNull(_lastItemName);
    final lastMakingType = _trimOrNull(_lastMakingType);
    final lastMakingCharge = _trimOrNull(_lastMakingCharge);
    final recentItemName = _trimOrNull(_recentItemName);
    if (lastCategory != null) {
      await prefs.setString(_lastCategoryKey, lastCategory);
    }
    if (lastItemName != null) {
      await prefs.setString(_lastItemNameKey, lastItemName);
    }
    if (lastMakingType != null) {
      await prefs.setString(_lastMakingTypeKey, lastMakingType);
    }
    if (lastMakingCharge != null) {
      await prefs.setString(_lastMakingChargeKey, lastMakingCharge);
    }
    if (recentItemName != null) {
      await prefs.setString(_recentItemNameKey, recentItemName);
    } else {
      await prefs.remove(_recentItemNameKey);
    }
    if (_persistence) {
      if (_selectedCategory != null) {
        await prefs.setString('category', _selectedCategory!);
      } else {
        await prefs.remove('category');
      }
      if (_selectedItemName != null) {
        await prefs.setString('item_name', _selectedItemName!);
      } else {
        await prefs.remove('item_name');
      }
      if (_selectedMakingType != null) {
        await prefs.setString('making_type', _selectedMakingType!);
      } else {
        await prefs.remove('making_type');
      }
      await prefs.setString('making_charge', _makingChargeController.text);
      await prefs.setBool(_huidCheckedKey, _isHuidChecked);
      await prefs.setBool('searchable', _searchable);
      await prefs.setBool('crud', _crud);
      await prefs.setBool('persistence', _persistence);
    } else {
      await prefs.remove('category');
      await prefs.remove('item_name');
      await prefs.remove('making_type');
      await prefs.remove('making_charge');
      await prefs.remove(_huidCheckedKey);
      await prefs.remove('searchable');
      await prefs.remove('crud');
      await prefs.setBool('persistence', false);
    }
  }

  void _restoreEntriesFromPrefs(SharedPreferences prefs) {
    for (final entry in _lessCategoryEntries) {
      entry.dispose();
    }
    _lessCategoryEntries.clear();
    final lessRaw = prefs.getString(_lessCategoryEntriesKey);
    if (lessRaw != null && lessRaw.isNotEmpty) {
      final decoded = jsonDecode(lessRaw);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            final entry = _LessCategoryEntry();
            entry.category = item['category']?.toString();
            entry.categoryController.text = entry.category ?? '';
            entry.valueController.text = item['value']?.toString() ?? '';
            entry.valueController.addListener(_updateWeights);
            _lessCategoryEntries.add(entry);
          }
        }
      }
    }
    if (_lessCategoryEntries.isEmpty) {
      final entry = _LessCategoryEntry();
      entry.valueController.addListener(_updateWeights);
      _lessCategoryEntries.add(entry);
    }

    for (final entry in _additionalEntries) {
      entry.dispose();
    }
    _additionalEntries.clear();
    final additionalRaw = prefs.getString(_additionalEntriesKey);
    if (additionalRaw != null && additionalRaw.isNotEmpty) {
      final decoded = jsonDecode(additionalRaw);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            final entry = _AdditionalEntry();
            entry.type = item['type']?.toString();
            entry.typeController.text = entry.type ?? '';
            entry.valueController.text = item['value']?.toString() ?? '';
            _additionalEntries.add(entry);
          }
        }
      }
    }
    if (_additionalEntries.isEmpty) {
      _additionalEntries.add(_AdditionalEntry());
    }
  }

  Future<void> _openLessCategorySearch(int index) async {
    FocusScope.of(context).unfocus();
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        String query = '';
        final controller = TextEditingController();
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = _lessCategories
                .where((v) => v.toLowerCase().contains(query.toLowerCase()))
                .toList();
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => FocusScope.of(context).unfocus(),
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 12,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: controller,
                              decoration: InputDecoration(
                                labelText: 'Search less category',
                                prefixIcon: const Icon(Icons.search),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onChanged: (value) {
                                setModalState(() {
                                  query = value;
                                });
                              },
                            ),
                          ),
                          if (widget.canManageMasterData) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: 'Add category',
                              icon: const Icon(Icons.add),
                              onPressed: () => _addLessCategory(setModalState),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (filtered.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text('No matches'),
                        )
                      else
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 320),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final item = filtered[i];
                              final isSelected =
                                  item == _lessCategoryEntries[index].category;
                              return ListTile(
                                title: Text(item),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isSelected)
                                      const Padding(
                                        padding: EdgeInsets.only(right: 4),
                                        child: Icon(Icons.check),
                                      ),
                                    if (widget.canManageMasterData)
                                      PopupMenuButton<String>(
                                        onSelected: (value) {
                                          if (value == 'edit') {
                                            _editLessCategory(
                                              item,
                                              setModalState,
                                            );
                                          } else if (value == 'delete') {
                                            _deleteLessCategory(
                                              item,
                                              setModalState,
                                            );
                                          }
                                        },
                                        itemBuilder: (_) => const [
                                          PopupMenuItem(
                                            value: 'edit',
                                            child: Text('Edit'),
                                          ),
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: Text('Delete'),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                                onTap: () => Navigator.of(context).pop(item),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (selected != null) {
      setState(() {
        _lessCategoryEntries[index].category = selected;
        _lessCategoryEntries[index].categoryController.text = selected;
      });
    }
  }

  Future<void> _editLessCategory(
    String current,
    StateSetter setModalState,
  ) async {
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit category'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Category'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(controller.text);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (!mounted) {
      return;
    }

    final updated = result?.trim();
    if (updated == null || updated.isEmpty || updated == current) {
      return;
    }
    final duplicate = _lessCategories.any(
      (v) => v.toLowerCase() == updated.toLowerCase() && v != current,
    );
    if (duplicate) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Category already exists')));
      return;
    }

    setState(() {
      final index = _lessCategories.indexOf(current);
      if (index != -1) {
        _lessCategories[index] = updated;
      }
      _sortList(_lessCategories);
      for (final entry in _lessCategoryEntries) {
        if (entry.category == current) {
          entry.category = updated;
          entry.categoryController.text = updated;
        }
      }
    });
    try {
      await _renameLessCategoryRemote(current, updated);
    } catch (_) {
      // ignore remote update failures
    }
    setModalState(() {});
    _saveIfNeeded();
  }

  Future<void> _addLessCategory(StateSetter setModalState) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add category'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Category'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(controller.text);
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (!mounted) {
      return;
    }

    final updated = result?.trim();
    if (updated == null || updated.isEmpty) {
      return;
    }
    final duplicate = _lessCategories.any(
      (v) => v.toLowerCase() == updated.toLowerCase(),
    );
    if (duplicate) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Category already exists')));
      return;
    }

    setState(() {
      _lessCategories.add(updated);
      _sortList(_lessCategories);
    });
    try {
      await _upsertLessCategoryRemote(updated);
    } catch (_) {
      // ignore remote update failures
    }
    setModalState(() {});
    _saveIfNeeded();
  }

  Future<void> _deleteLessCategory(
    String item,
    StateSetter setModalState,
  ) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete category'),
          content: Text('Delete "$item"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (!mounted) {
      return;
    }

    if (shouldDelete != true) {
      return;
    }

    setState(() {
      _lessCategories.remove(item);
      for (final entry in _lessCategoryEntries) {
        if (entry.category == item) {
          entry.category = null;
          entry.categoryController.text = '';
        }
      }
    });
    try {
      await _deleteLessCategoryRemote(item);
    } catch (_) {
      // ignore remote update failures
    }
    setModalState(() {});
    _saveIfNeeded();
  }

  Future<void> _openItemNameSearch() async {
    FocusScope.of(context).unfocus();
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        String query = '';
        final controller = TextEditingController();
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = _itemNamesWithRecentFirst(query);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => FocusScope.of(context).unfocus(),
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 12,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: controller,
                              decoration: InputDecoration(
                                labelText: 'Search item',
                                prefixIcon: const Icon(Icons.search),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onChanged: (value) {
                                setModalState(() {
                                  query = value;
                                });
                              },
                            ),
                          ),
                          if (widget.canManageMasterData) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: 'Add item',
                              icon: const Icon(Icons.add),
                              onPressed: () => _addItemName(setModalState),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (filtered.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text('No matches'),
                        )
                      else
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 320),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final item = filtered[i];
                              final isSelected = item == _selectedItemName;
                              final isRecent =
                                  (_recentItemName ?? '').toLowerCase() ==
                                  item.toLowerCase();
                              return ListTile(
                                title: Text(item),
                                subtitle: isRecent
                                    ? const Text('Recent')
                                    : null,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isSelected)
                                      const Padding(
                                        padding: EdgeInsets.only(right: 4),
                                        child: Icon(Icons.check),
                                      ),
                                    if (widget.canManageMasterData)
                                      PopupMenuButton<String>(
                                        onSelected: (value) {
                                          if (value == 'edit') {
                                            _editItemName(item, setModalState);
                                          } else if (value == 'delete') {
                                            _deleteItemName(
                                              item,
                                              setModalState,
                                            );
                                          }
                                        },
                                        itemBuilder: (_) => const [
                                          PopupMenuItem(
                                            value: 'edit',
                                            child: Text('Edit'),
                                          ),
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: Text('Delete'),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                                onTap: () => Navigator.of(context).pop(item),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (selected != null) {
      setState(() {
        if (selected != _selectedItemName) {
          _selectedItemName = selected;
          _itemNameController.text = selected;
        }
        _markRecentItemName(selected);
      });
      _saveIfNeeded();
    }
  }

  Future<void> _editItemName(String current, StateSetter setModalState) async {
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit item'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Item'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(controller.text);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (!mounted) {
      return;
    }

    final updated = result?.trim();
    if (updated == null || updated.isEmpty || updated == current) {
      return;
    }
    final duplicate = _itemNames.any(
      (v) => v.toLowerCase() == updated.toLowerCase() && v != current,
    );
    if (duplicate) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Item already exists')));
      return;
    }

    setState(() {
      final index = _itemNames.indexOf(current);
      if (index != -1) {
        _itemNames[index] = updated;
      }
      _sortList(_itemNames);
      if (_selectedItemName == current) {
        _selectedItemName = updated;
        _itemNameController.text = updated;
      }
      if ((_recentItemName ?? '').toLowerCase() == current.toLowerCase()) {
        _recentItemName = updated;
      }
    });
    try {
      await _renameItemNameRemote(current, updated);
    } catch (_) {
      // ignore remote update failures
    }
    setModalState(() {});
    _saveIfNeeded();
  }

  Future<void> _addItemName(StateSetter setModalState) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add item'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Item'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(controller.text);
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (!mounted) {
      return;
    }

    final updated = result?.trim();
    if (updated == null || updated.isEmpty) {
      return;
    }
    final duplicate = _itemNames.any(
      (v) => v.toLowerCase() == updated.toLowerCase(),
    );
    if (duplicate) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Item already exists')));
      return;
    }

    setState(() {
      _itemNames.add(updated);
      _sortList(_itemNames);
      _selectedItemName = updated;
      _itemNameController.text = updated;
      _markRecentItemName(updated);
    });
    try {
      await _upsertItemNameRemote(updated);
    } catch (_) {
      // ignore remote update failures
    }
    setModalState(() {});
    _saveIfNeeded();
  }

  Future<void> _deleteItemName(String item, StateSetter setModalState) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete item'),
          content: Text('Delete "$item"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (!mounted) {
      return;
    }

    if (shouldDelete != true) {
      return;
    }

    setState(() {
      _itemNames.remove(item);
      if (_selectedItemName == item) {
        _selectedItemName = null;
        _itemNameController.text = '';
      }
      if ((_recentItemName ?? '').toLowerCase() == item.toLowerCase()) {
        _recentItemName = null;
      }
    });
    try {
      await _deleteItemNameRemote(item);
    } catch (_) {
      // ignore remote update failures
    }
    setModalState(() {});
    _saveIfNeeded();
  }

  Widget _buildSelectField({
    required BuildContext context,
    required String label,
    required String hint,
    required String? value,
    required VoidCallback onTap,
    required TextEditingController controller,
  }) {
    controller.text = value ?? '';
    return TextField(
      controller: controller,
      readOnly: true,
      onTap: onTap,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
        suffixIcon: const Icon(Icons.arrow_drop_down),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      maxLines: 1,
    );
  }

  Widget _buildLessCategoryField(int index) {
    return _buildSelectField(
      context: context,
      label: 'Less Category',
      hint: 'Select category',
      value: _lessCategoryEntries[index].category,
      onTap: () => _openLessCategorySearch(index),
      controller: _lessCategoryEntries[index].categoryController,
    );
  }

  Widget _buildItemNameField(BuildContext context) {
    return _buildSelectField(
      context: context,
      label: 'Item Name',
      hint: 'Select item',
      value: _selectedItemName,
      onTap: _openItemNameSearch,
      controller: _itemNameController,
    );
  }

  Widget _buildLessCategoryRow(int index) {
    final entry = _lessCategoryEntries[index];
    final canDelete = _lessCategoryEntries.length > 1;
    return Row(
      children: [
        Expanded(flex: 5, child: _buildLessCategoryField(index)),
        const SizedBox(width: 8),
        Expanded(
          flex: 4,
          child: TextField(
            controller: entry.valueController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Value',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (_) => _saveIfNeeded(),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Add row',
              icon: const Icon(Icons.add_circle),
              onPressed: () {
                setState(() {
                  final newEntry = _LessCategoryEntry();
                  newEntry.valueController.addListener(_updateWeights);
                  _lessCategoryEntries.add(newEntry);
                });
              },
            ),
            IconButton(
              tooltip: 'Delete row',
              icon: Icon(
                Icons.remove_circle,
                color: canDelete ? Colors.red : Colors.grey,
              ),
              onPressed: canDelete
                  ? () {
                      setState(() {
                        final removed = _lessCategoryEntries.removeAt(index);
                        removed.valueController.removeListener(_updateWeights);
                        removed.dispose();
                      });
                      _updateWeights();
                    }
                  : null,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openAdditionalTypeSearch(int index) async {
    FocusScope.of(context).unfocus();
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        String query = '';
        final controller = TextEditingController();
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = _additionalTypes
                .where((v) => v.toLowerCase().contains(query.toLowerCase()))
                .toList();
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => FocusScope.of(context).unfocus(),
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 12,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: controller,
                              decoration: InputDecoration(
                                labelText: 'Search additional type',
                                prefixIcon: const Icon(Icons.search),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onChanged: (value) {
                                setModalState(() {
                                  query = value;
                                });
                              },
                            ),
                          ),
                          if (widget.canManageMasterData) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: 'Add type',
                              icon: const Icon(Icons.add),
                              onPressed: () =>
                                  _addAdditionalType(setModalState),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (filtered.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Text('No matches'),
                        )
                      else
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 320),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final item = filtered[i];
                              final isSelected =
                                  item == _additionalEntries[index].type;
                              return ListTile(
                                title: Text(item),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isSelected)
                                      const Padding(
                                        padding: EdgeInsets.only(right: 4),
                                        child: Icon(Icons.check),
                                      ),
                                    if (widget.canManageMasterData)
                                      PopupMenuButton<String>(
                                        onSelected: (value) {
                                          if (value == 'edit') {
                                            _editAdditionalType(
                                              item,
                                              setModalState,
                                            );
                                          } else if (value == 'delete') {
                                            _deleteAdditionalType(
                                              item,
                                              setModalState,
                                            );
                                          }
                                        },
                                        itemBuilder: (_) => const [
                                          PopupMenuItem(
                                            value: 'edit',
                                            child: Text('Edit'),
                                          ),
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: Text('Delete'),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                                onTap: () => Navigator.of(context).pop(item),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (selected != null) {
      setState(() {
        _additionalEntries[index].type = selected;
        _additionalEntries[index].typeController.text = selected;
      });
    }
  }

  Future<void> _editAdditionalType(
    String current,
    StateSetter setModalState,
  ) async {
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit type'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Type'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(controller.text);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (!mounted) {
      return;
    }

    final updated = result?.trim();
    if (updated == null || updated.isEmpty || updated == current) {
      return;
    }
    final duplicate = _additionalTypes.any(
      (v) => v.toLowerCase() == updated.toLowerCase() && v != current,
    );
    if (duplicate) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Type already exists')));
      return;
    }

    setState(() {
      final index = _additionalTypes.indexOf(current);
      if (index != -1) {
        _additionalTypes[index] = updated;
      }
      _sortList(_additionalTypes);
      for (final entry in _additionalEntries) {
        if (entry.type == current) {
          entry.type = updated;
          entry.typeController.text = updated;
        }
      }
    });
    try {
      await _renameAdditionalTypeRemote(current, updated);
    } catch (_) {
      // ignore remote update failures
    }
    setModalState(() {});
    _saveIfNeeded();
  }

  Future<void> _addAdditionalType(StateSetter setModalState) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add type'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Type'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(controller.text);
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (!mounted) {
      return;
    }

    final updated = result?.trim();
    if (updated == null || updated.isEmpty) {
      return;
    }
    final duplicate = _additionalTypes.any(
      (v) => v.toLowerCase() == updated.toLowerCase(),
    );
    if (duplicate) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Type already exists')));
      return;
    }

    setState(() {
      _additionalTypes.add(updated);
      _sortList(_additionalTypes);
    });
    try {
      await _upsertAdditionalTypeRemote(updated);
    } catch (_) {
      // ignore remote update failures
    }
    setModalState(() {});
    _saveIfNeeded();
  }

  Future<void> _deleteAdditionalType(
    String item,
    StateSetter setModalState,
  ) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete type'),
          content: Text('Delete "$item"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (!mounted) {
      return;
    }

    if (shouldDelete != true) {
      return;
    }

    setState(() {
      _additionalTypes.remove(item);
      for (final entry in _additionalEntries) {
        if (entry.type == item) {
          entry.type = null;
          entry.typeController.text = '';
        }
      }
    });
    try {
      await _deleteAdditionalTypeRemote(item);
    } catch (_) {
      // ignore remote update failures
    }
    setModalState(() {});
    _saveIfNeeded();
  }

  Widget _buildAdditionalTypeField(int index) {
    return _buildSelectField(
      context: context,
      label: 'Additional Type',
      hint: 'Select type',
      value: _additionalEntries[index].type,
      onTap: () => _openAdditionalTypeSearch(index),
      controller: _additionalEntries[index].typeController,
    );
  }

  Widget _buildAdditionalRow(int index) {
    final entry = _additionalEntries[index];
    final canDelete = _additionalEntries.length > 1;
    return Row(
      children: [
        Expanded(flex: 5, child: _buildAdditionalTypeField(index)),
        const SizedBox(width: 8),
        Expanded(
          flex: 4,
          child: TextField(
            controller: entry.valueController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Value',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (_) => _saveIfNeeded(),
          ),
        ),
        const SizedBox(width: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Add row',
              icon: const Icon(Icons.add_circle),
              onPressed: () {
                setState(() {
                  _additionalEntries.add(_AdditionalEntry());
                });
              },
            ),
            IconButton(
              tooltip: 'Delete row',
              icon: Icon(
                Icons.remove_circle,
                color: canDelete ? Colors.red : Colors.grey,
              ),
              onPressed: canDelete
                  ? () {
                      setState(() {
                        final removed = _additionalEntries.removeAt(index);
                        removed.dispose();
                      });
                    }
                  : null,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final categoryValue = _categories.contains(_selectedCategory)
        ? _selectedCategory
        : null;
    final makingTypes = _makingTypesForCategory(_selectedCategory);
    final makingTypeValue = makingTypes.contains(_selectedMakingType)
        ? _selectedMakingType
        : null;
    final returnPurityValue = _returnPurityOptions.contains(_selectedReturnPurity)
        ? _selectedReturnPurity
        : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: _isHuidChecked,
                  onChanged: (value) {
                    setState(() {
                      _isHuidChecked = value ?? false;
                    });
                    _saveIfNeeded();
                  },
                ),
                const Text('HUID'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SharedItemFormLayout(
            primarySection: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(categoryValue),
                        initialValue: categoryValue,
                        hint: const Text('Category'),
                        items: _categories.map((String category) {
                          return DropdownMenuItem<String>(
                            value: category,
                            child: Text(category),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          setState(() {
                            _selectedCategory = newValue;
                            if (!_makingTypesForCategory(
                              _selectedCategory,
                            ).contains(_selectedMakingType)) {
                              _selectedMakingType = null;
                            }
                            if (_selectedCategory == 'Gold22kt') {
                              _selectedReturnPurity = '22kt';
                            } else if (_selectedCategory == 'Gold18kt') {
                              _selectedReturnPurity = '18kt';
                            } else {
                              _selectedReturnPurity = null;
                            }
                          });
                          _saveIfNeeded();
                        },
                        decoration: InputDecoration(
                          labelText: 'Category',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: _buildItemNameField(context)),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _locationController,
                  decoration: InputDecoration(
                    labelText: 'Location (optional)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: (_) => _saveIfNeeded(),
                ),
              ],
            ),
            makingSection: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('${categoryValue ?? ''}-${makingTypeValue ?? ''}'),
                    initialValue: makingTypeValue,
                    isExpanded: true,
                    items: makingTypes
                        .map(
                          (t) => DropdownMenuItem<String>(
                            value: t,
                            child: Text(
                              t,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: makingTypes.isEmpty
                        ? null
                        : (value) {
                            setState(() {
                              _selectedMakingType = value;
                            });
                            _saveIfNeeded();
                          },
                    decoration: InputDecoration(
                      labelText: 'Making Type',
                      isDense: true,
                      labelStyle: const TextStyle(fontSize: 12),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 4,
                  child: _selectedMakingType == 'Percentage'
                      ? DropdownButtonFormField<String>(
                          initialValue:
                              _percentageOptions.contains(
                                _makingChargeController.text,
                              )
                              ? _makingChargeController.text
                              : null,
                          isExpanded: true,
                          items: _percentageOptions
                              .map(
                                (p) => DropdownMenuItem<String>(
                                  value: p,
                                  child: Text(p),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              _makingChargeController.text = value ?? '';
                            });
                            _saveIfNeeded();
                          },
                          decoration: InputDecoration(
                            labelText: 'Making Charge %',
                            isDense: true,
                            labelStyle: const TextStyle(fontSize: 12),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        )
                      : TextField(
                          controller: _makingChargeController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Making Charge',
                            isDense: true,
                            labelStyle: const TextStyle(fontSize: 12),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onChanged: (_) => _saveIfNeeded(),
                        ),
                ),
              ],
            ),
            lessSection: Column(
              children: _lessCategoryEntries.asMap().entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildLessCategoryRow(entry.key),
                );
              }).toList(),
            ),
            weightSection: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _grossWeightController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Gross Weight',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _lessWeightController,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Less Weight',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _netWeightController,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Net Weight',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            returnPuritySection: _selectedCategory == 'Silver'
                ? Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('return-$returnPurityValue'),
                          initialValue: returnPurityValue,
                          hint: const Text('Return Purity'),
                          items: _returnPurityOptions.map((String purity) {
                            return DropdownMenuItem<String>(
                              value: purity,
                              child: Text(purity),
                            );
                          }).toList(),
                          onChanged: (String? newValue) {
                            setState(() {
                              _selectedReturnPurity = newValue;
                            });
                            _saveIfNeeded();
                          },
                          decoration: InputDecoration(
                            labelText: 'Return Purity',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          validator: (value) {
                            if (_selectedCategory == 'Silver' && (value == null || value.isEmpty)) {
                              return 'Required for Silver items';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  )
                : null,
            additionalSection: Column(
              children: _additionalEntries.asMap().entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildAdditionalRow(entry.key),
                );
              }).toList(),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _createTag,
                  child: Text(
                    _editingTagId == null ? 'Create Tag' : 'Update Tag',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: () => _resetForm(restoreLastRequiredValues: true),
                child: const Text('Reset'),
              ),
            ],
          ),
          if (_qrData != null) ...[
            const SizedBox(height: 16),
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(8),
              child: SizedBox(
                width: 180,
                height: 180,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    QrImageView(
                      data: _qrData!,
                      size: 180,
                      backgroundColor: Colors.white,
                      errorCorrectionLevel: QrErrorCorrectLevel.H,
                    ),
                    Container(
                      width: 40,
                      height: 40,
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFFE5E7EB),
                          width: 1.5,
                        ),
                      ),
                      child: Image.asset(
                        'assets/images/logo.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _shareQr,
              icon: const Icon(Icons.share),
              label: const Text('Share QR'),
            ),
          ],
        ],
      ),
    );
  }
}

class _LessCategoryEntry {
  _LessCategoryEntry();

  String? category;
  final TextEditingController categoryController = TextEditingController();
  final TextEditingController valueController = TextEditingController();

  void dispose() {
    categoryController.dispose();
    valueController.dispose();
  }
}

class _AdditionalEntry {
  _AdditionalEntry();

  String? type;
  final TextEditingController typeController = TextEditingController();
  final TextEditingController valueController = TextEditingController();

  void dispose() {
    typeController.dispose();
    valueController.dispose();
  }
}
