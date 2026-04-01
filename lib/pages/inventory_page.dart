import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/tag_repository.dart';
import '../features/inventory/inventory_tag_sorter.dart';
import '../models/edit_tag_request.dart';
import '../models/tag_record.dart';
import '../utils/qr_logo_loader.dart';
import '../utils/share_file_namer.dart';
import '../utils/sales_notifier.dart';

enum _InventoryListMode { inventory, newlyCreated }

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key, required this.onEditTag, this.tagRepository});

  final ValueChanged<EditTagRequest> onEditTag;
  final TagRepository? tagRepository;

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  static const int _pageSize = 50;

  late final TagRepository _tagRepository;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<TagRecord> _loadedTags = [];
  final Set<String> _selectedIds = <String>{};
  final List<TagRecord> _newTags = [];
  final Set<String> _selectedNewIds = <String>{};
  final List<TagRecord> _recentlyAddedTags = [];

  Set<String> _salesIds = <String>{};
  String _debouncedSearch = '';
  Timer? _searchDebounce;
  late final VoidCallback _salesListener;
  bool _appendRecentToInventory = false;
  bool _isLoadingRecent = false;
  bool _isTransferringRecent = false;

  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _isInitialLoading = true;
  bool _isLoadingMore = false;
  bool _isLoadingAllAction = false;
  bool _isLoadingAllNewAction = false;
  bool _isLoadingNewList = true;
  bool _hasMore = true;
  bool _selectionMode = false;
  bool _newSelectionMode = false;
  String? _loadError;
  String? _newLoadError;
  DocumentSnapshot<Map<String, dynamic>>? _lastNewDoc;
  bool _isLoadingMoreNew = false;
  bool _hasMoreNew = true;
  int _totalCount = 0;
  int _pendingNewCount = 0;
  _InventoryListMode _listMode = _InventoryListMode.inventory;
  DateTime? _lastTotalCountFetchAt;
  DateTime? _lastNewSyncAt;
  bool _isRefreshingTotalCount = false;
  bool _isRefreshingPendingCount = false;
  bool _inventoryListDirty = false;

  @override
  void initState() {
    super.initState();
    _tagRepository = widget.tagRepository ?? TagRepository();
    _salesListener = _loadSalesIds;
    SalesNotifier.version.addListener(_salesListener);
    _searchController.addListener(_handleSearchChanged);
    _scrollController.addListener(_handleScroll);
    _loadSalesIds();
    _refreshTotalCount(force: true);
    _refreshInventory();
    _refreshNewlyCreated();
    _refreshRecentlyAdded();
  }

  @override
  void dispose() {
    SalesNotifier.version.removeListener(_salesListener);
    _searchDebounce?.cancel();
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _loadSalesIds() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList('sales_item_ids') ?? <String>[];
    if (!mounted) {
      return;
    }
    setState(() {
      _salesIds = ids.toSet();
    });
  }

  Future<void> _refreshTotalCount({bool force = false}) async {
    final now = DateTime.now();
    if (!force && _lastTotalCountFetchAt != null) {
      final elapsed = now.difference(_lastTotalCountFetchAt!);
      if (elapsed < const Duration(minutes: 2)) {
        return;
      }
    }
    if (_isRefreshingTotalCount) {
      return;
    }
    _isRefreshingTotalCount = true;
    try {
      final snapshot = await _tagRepository.countTags();
      if (!mounted) {
        return;
      }
      setState(() {
        _totalCount = snapshot.count ?? 0;
      });
      _lastTotalCountFetchAt = DateTime.now();
    } catch (_) {
      // ignore count failures
    } finally {
      _isRefreshingTotalCount = false;
    }
  }

  Future<void> _refreshPendingCount({bool force = false}) async {
    if (!force && _isRefreshingPendingCount) {
      return;
    }
    _isRefreshingPendingCount = true;
    try {
      final snapshot = await _tagRepository.countPendingTags();
      if (!mounted) {
        return;
      }
      setState(() {
        _pendingNewCount = snapshot.count ?? 0;
      });
    } catch (_) {
      // ignore count failures
    } finally {
      _isRefreshingPendingCount = false;
    }
  }

  void _handleSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      final normalized = _searchController.text.trim().toLowerCase();
      if (normalized == _debouncedSearch) {
        return;
      }
      setState(() {
        _debouncedSearch = normalized;
      });
      _refreshVisibleList();
    });
  }

  Future<void> _refreshVisibleList() async {
    if (_listMode == _InventoryListMode.inventory) {
      await _refreshInventory();
      if (_appendRecentToInventory) {
        await _refreshRecentlyAdded();
      }
      return;
    }
    await _refreshNewlyCreated();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    final threshold = _scrollController.position.maxScrollExtent - 280;
    if (_scrollController.position.pixels >= threshold) {
      _loadNextPage();
    }
  }

  bool _matchesInventoryFilters(TagRecord tag) {
    if (tag.inventoryPending) {
      return false;
    }
    if (tag.inventoryQueued) {
      return false;
    }
    return tag.matchesSearch(_debouncedSearch);
  }

  bool _matchesNewFilters(TagRecord tag) {
    if (!tag.inventoryPending) {
      return false;
    }
    return tag.matchesSearch(_debouncedSearch);
  }

  bool _matchesRecentFilters(TagRecord tag) {
    if (!tag.inventoryQueued) {
      return false;
    }
    return tag.matchesSearch(_debouncedSearch);
  }

  bool _matchesSavedFilters(TagRecord tag) {
    return tag.matchesSearch(_debouncedSearch);
  }

  Query<Map<String, dynamic>> _buildPagedQuery({
    required int limit,
    DocumentSnapshot<Map<String, dynamic>>? cursor,
  }) {
    Query<Map<String, dynamic>> query = _tagRepository.queryTags().orderBy(
      'createdAt',
      descending: true,
    );

    if (cursor != null) {
      query = query.startAfterDocument(cursor);
    }
    return query.limit(limit);
  }

  Future<void> _refreshInventory() async {
    setState(() {
      _isInitialLoading = true;
      _isLoadingMore = false;
      _hasMore = true;
      _loadError = null;
      _lastDoc = null;
      _loadedTags.clear();
      _selectedIds.clear();
    });
    await _loadNextPage();
  }

  Future<void> _refreshNewlyCreated() async {
    setState(() {
      _isLoadingNewList = true;
      _isLoadingMoreNew = false;
      _hasMoreNew = true;
      _newLoadError = null;
      _lastNewDoc = null;
      _newTags.clear();
      _selectedNewIds.clear();
    });
    await _loadNextNewPage();
    await _refreshPendingCount(force: true);
  }

  Future<void> _loadNextNewPage() async {
    if (_isLoadingMoreNew || !_hasMoreNew) {
      return;
    }
    setState(() {
      _isLoadingMoreNew = true;
      _newLoadError = null;
    });
    try {
      final snapshot = await _tagRepository
          .queryPendingTags(limit: _pageSize, cursor: _lastNewDoc)
          .get();
      final rawDocs = snapshot.docs;
      final pageTags = rawDocs
          .map(_tagRepository.toTagRecord)
          .where(_matchesNewFilters)
          .toList();
      if (!mounted) {
        return;
      }
      final existingIds = _newTags.map((d) => d.id).toSet();
      setState(() {
        for (final tag in pageTags) {
          if (!existingIds.contains(tag.id)) {
            _newTags.add(tag);
          }
        }
        _newTags.sort(InventoryTagSorter.compareByCategoryItemAndWeight);
        _lastNewDoc = rawDocs.isNotEmpty ? rawDocs.last : _lastNewDoc;
        _hasMoreNew = rawDocs.length == _pageSize;
        _isLoadingNewList = false;
        _isLoadingMoreNew = false;
        _lastNewSyncAt = DateTime.now();
      });
    } on FirebaseException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _newLoadError = e.message ?? 'Failed to load new tags';
        _isLoadingNewList = false;
        _hasMoreNew = false;
        _isLoadingMoreNew = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _newLoadError = 'Failed to load new tags';
        _isLoadingNewList = false;
        _hasMoreNew = false;
        _isLoadingMoreNew = false;
      });
    }
  }

  Future<void> _loadNextPage() async {
    if (_isLoadingMore || !_hasMore) {
      return;
    }
    setState(() {
      _isLoadingMore = true;
      _loadError = null;
    });
    try {
      final effectiveLimit = _debouncedSearch.isNotEmpty
          ? _pageSize * 4
          : _pageSize;
      final snapshot = await _buildPagedQuery(
        limit: effectiveLimit,
        cursor: _lastDoc,
      ).get();

      final rawDocs = snapshot.docs;
      final pageTags = rawDocs
          .map(_tagRepository.toTagRecord)
          .where(_matchesInventoryFilters)
          .toList();

      if (!mounted) {
        return;
      }
      final existingIds = _loadedTags.map((d) => d.id).toSet();
      setState(() {
        for (final tag in pageTags) {
          if (!existingIds.contains(tag.id)) {
            _loadedTags.add(tag);
          }
        }
        _loadedTags.sort(InventoryTagSorter.compareByCategoryItemAndWeight);
        _lastDoc = rawDocs.isNotEmpty ? rawDocs.last : _lastDoc;
        _hasMore = rawDocs.length == effectiveLimit;
        _isInitialLoading = false;
      });
    } on FirebaseException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = e.message ?? 'Failed to load inventory';
        _isInitialLoading = false;
        _hasMore = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = 'Failed to load inventory';
        _isInitialLoading = false;
        _hasMore = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _refreshRecentlyAdded() async {
    if (_isLoadingRecent) {
      return;
    }
    setState(() {
      _isLoadingRecent = true;
    });
    try {
      final snapshot = await _tagRepository.queryRecentlyAddedTags().get();
      final tags = snapshot.docs
          .map(_tagRepository.toTagRecord)
          .where(_matchesRecentFilters)
          .toList();
      int sortMillis(TagRecord tag) {
        final queuedAt = tag.rawData['inventoryQueuedAt'];
        if (queuedAt is Timestamp) {
          return queuedAt.millisecondsSinceEpoch;
        }
        return tag.createdAtMillis;
      }

      tags.sort((a, b) => sortMillis(b).compareTo(sortMillis(a)));
      if (!mounted) {
        return;
      }
      setState(() {
        _recentlyAddedTags
          ..clear()
          ..addAll(tags);
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load recently added items')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingRecent = false;
        });
      }
    }
  }

  Future<List<TagRecord>> _fetchAllSavedTags() async {
    const batchSize = 200;
    final tags = <TagRecord>[];
    DocumentSnapshot<Map<String, dynamic>>? cursor;
    bool hasMore = true;
    while (hasMore) {
      final snapshot = await _buildPagedQuery(
        limit: batchSize,
        cursor: cursor,
      ).get();
      final rawDocs = snapshot.docs;
      if (rawDocs.isEmpty) {
        break;
      }
      final pageTags = rawDocs
          .map(_tagRepository.toTagRecord)
          .where(_matchesSavedFilters)
          .toList();
      tags.addAll(pageTags);
      cursor = rawDocs.last;
      hasMore = rawDocs.length == batchSize;
    }
    tags.sort(InventoryTagSorter.compareByCategoryItemAndWeight);
    return tags;
  }

  Future<List<TagRecord>> _fetchAllMatchingNewTags() async {
    const batchSize = 200;
    final tags = <TagRecord>[];
    DocumentSnapshot<Map<String, dynamic>>? cursor;
    bool hasMore = true;
    while (hasMore) {
      final snapshot = await _tagRepository
          .queryPendingTags(limit: batchSize, cursor: cursor)
          .get();
      final rawDocs = snapshot.docs;
      if (rawDocs.isEmpty) {
        break;
      }
      final pageTags = rawDocs
          .map(_tagRepository.toTagRecord)
          .where(_matchesNewFilters)
          .toList();
      tags.addAll(pageTags);
      cursor = rawDocs.last;
      hasMore = rawDocs.length == batchSize;
    }
    tags.sort(InventoryTagSorter.compareByCategoryItemAndWeight);
    return tags;
  }

  List<TagRecord> _selectedInventoryDocs() {
    final selected = <String, TagRecord>{};
    for (final doc in _loadedTags) {
      if (_selectedIds.contains(doc.id)) {
        selected[doc.id] = doc;
      }
    }
    for (final doc in _recentlyAddedTags) {
      if (_selectedIds.contains(doc.id)) {
        selected[doc.id] = doc;
      }
    }
    return selected.values.toList();
  }

  List<TagRecord> _filteredNewTags() {
    return _newTags.where(_matchesNewFilters).toList();
  }

  List<TagRecord> _selectedNewDocs() {
    return _filteredNewTags()
        .where((doc) => _selectedNewIds.contains(doc.id))
        .toList();
  }

  List<TagRecord> _visibleSummaryTags(List<TagRecord> filteredNewDocs) {
    if (_listMode != _InventoryListMode.inventory) {
      return filteredNewDocs;
    }
    if (!_appendRecentToInventory) {
      return List<TagRecord>.from(_loadedTags);
    }
    return <TagRecord>[..._recentlyAddedTags, ..._loadedTags];
  }

  String _normalizeSummaryCategoryKey(String category) {
    return category
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('-', '');
  }

  double _parseWeightValue(String value) {
    final cleaned = value.trim().replaceAll(',', '');
    final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(cleaned);
    return double.tryParse(match?.group(0) ?? '') ?? 0.0;
  }

  Map<String, _InventoryWeightTotals> _buildVisibleWeightTotals(
    List<TagRecord> tags,
  ) {
    final totals = <String, _InventoryWeightTotals>{
      'gold22kt': _InventoryWeightTotals(),
      'gold18kt': _InventoryWeightTotals(),
      'silver': _InventoryWeightTotals(),
    };
    for (final tag in tags) {
      final key = _normalizeSummaryCategoryKey(tag.category);
      final bucket = totals[key];
      if (bucket == null) {
        continue;
      }
      bucket.gross += _parseWeightValue(tag.grossWeight);
      bucket.less += _parseWeightValue(tag.lessWeight);
      bucket.nett += _parseWeightValue(tag.netWeight);
    }
    return totals;
  }

  String _summaryCategoryLabel(String categoryKey) {
    switch (categoryKey) {
      case 'gold22kt':
        return 'Gold22K';
      case 'gold18kt':
        return 'Gold18K';
      case 'silver':
        return 'Silver';
      default:
        return categoryKey;
    }
  }

  String _summaryCategoryColorName(String categoryKey) {
    switch (categoryKey) {
      case 'gold22kt':
        return 'Gold22kt';
      case 'gold18kt':
        return 'Gold18kt';
      case 'silver':
        return 'Silver';
      default:
        return categoryKey;
    }
  }

  String _formatWeightTotal(double value) => value.toStringAsFixed(3);

  Widget _buildSummaryCountChip(String label, String value) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopFilterButton({
    required Widget child,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: selected ? colorScheme.primaryContainer : colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(
          color: selected ? colorScheme.primary : colorScheme.outlineVariant,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: 40,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Center(
              child: DefaultTextStyle(
                style: theme.textTheme.labelLarge!.copyWith(
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurface,
                ),
                child: IconTheme(
                  data: IconThemeData(
                    color: selected
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurface,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNetSummaryTile(
    String categoryKey,
    _InventoryWeightTotals totals,
  ) {
    final theme = Theme.of(context);
    final categoryName = _summaryCategoryColorName(categoryKey);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _categoryBackgroundColor(categoryName, theme.colorScheme),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _categoryBorderColor(
            categoryName,
            theme.colorScheme,
          ).withValues(alpha: 0.32),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _summaryCategoryLabel(categoryKey),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _formatWeightTotal(totals.nett),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runAllItemsAction(
    Future<void> Function(List<TagRecord>) action,
  ) async {
    if (_isLoadingAllAction) {
      return;
    }
    setState(() {
      _isLoadingAllAction = true;
    });
    try {
      final tags = _appendRecentToInventory
          ? List<TagRecord>.from(_recentlyAddedTags)
          : await _fetchAllSavedTags();
      await action(tags);
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingAllAction = false;
        });
      }
    }
  }

  Future<void> _runAllNewItemsAction(
    Future<void> Function(List<TagRecord>) action,
  ) async {
    if (_isLoadingAllNewAction) {
      return;
    }
    setState(() {
      _isLoadingAllNewAction = true;
    });
    try {
      final tags = await _fetchAllMatchingNewTags();
      await action(tags);
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingAllNewAction = false;
        });
      }
    }
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
    canvas.drawRect(
      Rect.fromLTWH(0, 0, totalSize.toDouble(), totalSize.toDouble()),
      Paint()..color = Colors.white,
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
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  }

  Future<Uint8List> _buildQrPdfBytes(List<TagRecord> tags) async {
    const columns = 13;
    // 1.4 cm = 39.6851 PDF points
    const qrPt = 39.6851;
    const gapPt = 0.8;
    final qrImages = <pw.MemoryImage?>[];

    for (final tag in tags) {
      final qr = await _buildQrPng('QR1:${tag.id}', 360, borderPx: 24);
      qrImages.add(qr == null ? null : pw.MemoryImage(qr));
    }

    final rows = <pw.Widget>[];
    for (int i = 0; i < qrImages.length; i += columns) {
      final end = math.min(i + columns, qrImages.length);
      final cells = <pw.Widget>[];
      for (int j = i; j < end; j++) {
        final image = qrImages[j];
        cells.add(
          pw.Container(
            width: qrPt,
            height: qrPt,
            decoration: image == null
                ? pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey500, width: 0.6),
                  )
                : null,
            child: image == null ? null : pw.Image(image, fit: pw.BoxFit.fill),
          ),
        );
        if (j < end - 1) {
          cells.add(pw.SizedBox(width: gapPt));
        }
      }
      rows.add(pw.Row(children: cells));
      if (end < qrImages.length) {
        rows.add(pw.SizedBox(height: gapPt));
      }
    }

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(18),
        build: (_) => rows,
      ),
    );
    return doc.save();
  }

  Future<void> _exportQrPdf(
    List<TagRecord> tags, {
    required String prefix,
    Future<void> Function()? onSuccess,
  }) async {
    if (tags.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No items to export')));
      }
      return;
    }
    try {
      final bytes = await _buildQrPdfBytes(tags);
      final fileName = ShareFileNamer.startBatch(
        prefix: prefix,
        extension: 'pdf',
      ).nextName();
      await Share.shareXFiles(
        [XFile.fromData(bytes, name: fileName, mimeType: 'application/pdf')],
        fileNameOverrides: [fileName],
      );
      if (onSuccess != null) {
        await onSuccess();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to export PDF file')),
        );
      }
    }
  }

  Future<void> _moveNewItemsToRecentlyAdded(List<TagRecord> tags) async {
    if (tags.isEmpty) {
      return;
    }
    final uniqueIds = tags.map((d) => d.id).toSet().toList();
    const chunkSize = 400;
    try {
      await _tagRepository.markTagsAsRecentlyAdded(
        uniqueIds,
        chunkSize: chunkSize,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Moved ${uniqueIds.length} item(s) to Recently Added',
            ),
          ),
        );
      }
      _inventoryListDirty = true;
      await _refreshNewlyCreated();
      await _refreshInventory();
      await _refreshRecentlyAdded();
      await _refreshPendingCount(force: true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Printed, but failed to move items to recent'),
          ),
        );
      }
    }
  }

  Future<void> _transferRecentToInventory() async {
    if (_isTransferringRecent) {
      return;
    }
    final ids = _recentlyAddedTags.map((tag) => tag.id).toSet().toList();
    if (ids.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No recently added items to transfer')),
        );
      }
      return;
    }
    setState(() {
      _isTransferringRecent = true;
    });
    try {
      await _tagRepository.transferRecentlyAddedToInventory(ids);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Transferred ${ids.length} item(s) to inventory'),
        ),
      );
      setState(() {
        _listMode = _InventoryListMode.inventory;
      });
      await _refreshInventory();
      await _refreshRecentlyAdded();
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to transfer recently added items'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isTransferringRecent = false;
        });
      }
    }
  }

  Future<void> _exportNewQrPdf(
    List<TagRecord> tags, {
    required String prefix,
  }) async {
    await _exportQrPdf(
      tags,
      prefix: prefix,
      onSuccess: () => _moveNewItemsToRecentlyAdded(tags),
    );
  }

  Future<void> _deleteTag(String id, {required bool fromNewList}) async {
    await _tagRepository.deleteTag(id);
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedIds.remove(id);
      _selectedNewIds.remove(id);
    });
    await _refreshTotalCount(force: true);
    if (fromNewList) {
      await _refreshNewlyCreated();
      await _refreshPendingCount(force: true);
    } else {
      await _refreshInventory();
      await _refreshRecentlyAdded();
    }
  }

  String _formatLastSynced() {
    final synced = _lastNewSyncAt;
    if (synced == null) {
      return 'Never';
    }
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${twoDigits(synced.hour)}:${twoDigits(synced.minute)}:${twoDigits(synced.second)}';
  }

  Color _categoryBackgroundColor(String category, ColorScheme colorScheme) {
    final normalized = category
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('-', '');
    final isDark = colorScheme.brightness == Brightness.dark;
    if (normalized == 'gold22kt') {
      return isDark ? const Color(0xFF3A3217) : const Color(0xFFF0F0DB);
    }
    if (normalized == 'gold18kt') {
      return isDark ? const Color(0xFF3A301A) : const Color(0xFFE1D9BC);
    }
    if (normalized == 'silver') {
      return isDark ? const Color(0xFF2F343B) : const Color(0xFFE1E2E4);
    }
    return isDark
        ? colorScheme.surfaceContainerHigh
        : colorScheme.surfaceContainerHighest;
  }

  Color _categoryBorderColor(String category, ColorScheme colorScheme) {
    final normalized = category
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('-', '');
    final isDark = colorScheme.brightness == Brightness.dark;
    if (normalized == 'gold22kt') {
      return isDark ? const Color(0xFFE7CB68) : const Color(0xFFB38F00);
    }
    if (normalized == 'gold18kt') {
      return isDark ? const Color(0xFFD6B777) : const Color(0xFF9E8130);
    }
    if (normalized == 'silver') {
      return isDark ? const Color(0xFFB8C0CB) : const Color(0xFF8C8C8C);
    }
    return isDark ? colorScheme.outline : colorScheme.primary;
  }

  Widget _buildInventoryTile(
    TagRecord tag, {
    bool isNewList = false,
    bool isRecentList = false,
  }) {
    final theme = Theme.of(context);
    final category = tag.category.isEmpty ? '-' : tag.category;
    final itemName = tag.itemName.isEmpty ? '-' : tag.itemName;
    final netWeight = tag.netWeight.isEmpty ? '-' : tag.netWeight;
    final isSold = _salesIds.contains(tag.id);
    final selectionMode = isNewList ? _newSelectionMode : _selectionMode;
    final selectedIds = isNewList ? _selectedNewIds : _selectedIds;
    final backgroundColor = _categoryBackgroundColor(
      tag.category,
      theme.colorScheme,
    );
    final borderColor = _categoryBorderColor(
      tag.category,
      theme.colorScheme,
    ).withValues(alpha: 0.32);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (selectionMode)
              Checkbox(
                value: selectedIds.contains(tag.id),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      selectedIds.add(tag.id);
                    } else {
                      selectedIds.remove(tag.id);
                    }
                  });
                },
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isSold
                          ? theme.colorScheme.error
                          : (isRecentList ? theme.colorScheme.primary : null),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    itemName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  RichText(
                    text: TextSpan(
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      children: [
                        const TextSpan(text: 'Net: '),
                        TextSpan(
                          text: netWeight,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit),
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    widget.onEditTag(EditTagRequest(id: tag.id, tag: tag));
                  },
                ),
                const SizedBox(width: 1),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete),
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Delete tag'),
                        content: const Text(
                          'Are you sure you want to delete this tag?',
                        ),
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
                      ),
                    );
                    if (confirmed == true) {
                      await _deleteTag(tag.id, fromNewList: isNewList);
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    final hasVisibleItems =
        _loadedTags.isNotEmpty ||
        (_appendRecentToInventory &&
            (_recentlyAddedTags.isNotEmpty || _isLoadingRecent));
    if (_isInitialLoading && _loadedTags.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null && _loadedTags.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_loadError!),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _refreshInventory,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (!hasVisibleItems) {
      if (_hasMore) {
        return Center(
          child: OutlinedButton(
            onPressed: _loadNextPage,
            child: const Text('Load More'),
          ),
        );
      }
      return const Center(child: Text('No matching tags'));
    }

    final inventoryTags = _loadedTags;

    return RefreshIndicator(
      onRefresh: () async {
        await _refreshInventory();
        await _refreshRecentlyAdded();
      },
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (_appendRecentToInventory) ...[
            Row(
              children: [
                Text(
                  'Recently Added (${_recentlyAddedTags.length})',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 8),
                if (_isLoadingRecent)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_recentlyAddedTags.isEmpty && !_isLoadingRecent)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text('No recently added items'),
              ),
            ..._recentlyAddedTags.map(
              (tag) => _buildInventoryTile(tag, isRecentList: true),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed:
                    !_isTransferringRecent && _recentlyAddedTags.isNotEmpty
                    ? _transferRecentToInventory
                    : null,
                icon: _isTransferringRecent
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.move_to_inbox),
                label: const Text('Transfer To Inventory'),
              ),
            ),
            if (_recentlyAddedTags.isNotEmpty) const SizedBox(height: 6),
            const Divider(height: 18),
            const SizedBox(height: 4),
            Text(
              'Inventory',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
          ],
          ...inventoryTags.map((tag) => _buildInventoryTile(tag)),
          if (_isLoadingMore)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_hasMore)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: OutlinedButton(
                  onPressed: _loadNextPage,
                  child: const Text('Load More'),
                ),
              ),
            )
          else
            const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildNewList() {
    final tags = _filteredNewTags();
    if (_isLoadingNewList && _newTags.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_newLoadError != null && _newTags.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_newLoadError!),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _refreshNewlyCreated,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (tags.isEmpty) {
      if (_hasMoreNew) {
        return Center(
          child: OutlinedButton(
            onPressed: _loadNextNewPage,
            child: const Text('Load More'),
          ),
        );
      }
      return const Center(child: Text('No newly created tags'));
    }

    return RefreshIndicator(
      onRefresh: _refreshNewlyCreated,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        itemCount: tags.length + 1,
        itemBuilder: (context, index) {
          if (index < tags.length) {
            return _buildInventoryTile(tags[index], isNewList: true);
          }
          if (_isLoadingMoreNew) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (_hasMoreNew) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: OutlinedButton(
                  onPressed: _loadNextNewPage,
                  child: const Text('Load More'),
                ),
              ),
            );
          }
          return const SizedBox(height: 8);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedInventoryDocs = _selectedInventoryDocs();
    final selectedNewDocs = _selectedNewDocs();
    final filteredNewDocs = _filteredNewTags();
    final isInventoryMode = _listMode == _InventoryListMode.inventory;
    final visibleSummaryTags = _visibleSummaryTags(filteredNewDocs);
    final visibleWeightTotals = _buildVisibleWeightTotals(visibleSummaryTags);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        labelText: 'Search by Item Name',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () => _searchController.clear(),
                              )
                            : null,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildTopFilterButton(
                      selected: isInventoryMode && !_appendRecentToInventory,
                      onTap: () {
                        setState(() {
                          _listMode = _InventoryListMode.inventory;
                          _appendRecentToInventory = false;
                          _selectionMode = false;
                          _newSelectionMode = false;
                          _selectedIds.clear();
                          _selectedNewIds.clear();
                        });
                        if (_inventoryListDirty || _loadedTags.isEmpty) {
                          _inventoryListDirty = false;
                          _refreshInventory();
                        }
                      },
                      child: const Text('Inventory'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildTopFilterButton(
                      selected: _appendRecentToInventory,
                      onTap: () {
                        final nextValue = !_appendRecentToInventory;
                        setState(() {
                          _appendRecentToInventory = nextValue;
                          _listMode = _InventoryListMode.inventory;
                          _selectionMode = false;
                          _newSelectionMode = false;
                          _selectedIds.clear();
                          _selectedNewIds.clear();
                        });
                        if (nextValue) {
                          _refreshRecentlyAdded();
                        }
                      },
                      child: const Text('Recent Added'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildTopFilterButton(
                      selected: !isInventoryMode,
                      onTap: () {
                        setState(() {
                          _listMode = _InventoryListMode.newlyCreated;
                          _appendRecentToInventory = false;
                          _selectionMode = false;
                          _newSelectionMode = false;
                          _selectedIds.clear();
                          _selectedNewIds.clear();
                        });
                        _refreshNewlyCreated();
                      },
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Newly Created'),
                            if (_pendingNewCount > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade600,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$_pendingNewCount',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (!isInventoryMode) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      'Last synced: ${_formatLastSynced()}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: (_isLoadingNewList || _isLoadingMoreNew)
                          ? null
                          : _refreshNewlyCreated,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  if (isInventoryMode) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isLoadingAllAction
                            ? null
                            : () => _runAllItemsAction(
                                (docs) => _exportQrPdf(docs, prefix: 'ia'),
                              ),
                        icon: const Icon(Icons.description),
                        label: Text(
                          _isLoadingAllAction ? 'Loading...' : 'PDF All',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: selectedInventoryDocs.isEmpty
                            ? null
                            : () => _exportQrPdf(
                                selectedInventoryDocs,
                                prefix: 'is',
                              ),
                        icon: const Icon(Icons.article),
                        label: const Text('PDF Selected'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: _selectionMode
                          ? 'Cancel selection'
                          : 'Select items',
                      onPressed: () {
                        setState(() {
                          _selectionMode = !_selectionMode;
                          if (!_selectionMode) {
                            _selectedIds.clear();
                          }
                        });
                      },
                      icon: Icon(
                        _selectionMode ? Icons.close : Icons.check_box_outlined,
                      ),
                    ),
                  ] else ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isLoadingAllNewAction
                            ? null
                            : () => _runAllNewItemsAction(
                                (docs) => _exportNewQrPdf(docs, prefix: 'na'),
                              ),
                        icon: const Icon(Icons.description),
                        label: Text(
                          _isLoadingAllNewAction ? 'Loading...' : 'PDF All',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: selectedNewDocs.isEmpty
                            ? null
                            : () => _exportNewQrPdf(
                                selectedNewDocs,
                                prefix: 'ns',
                              ),
                        icon: const Icon(Icons.article),
                        label: const Text('PDF Selected'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: _newSelectionMode
                          ? 'Cancel selection'
                          : 'Select items',
                      onPressed: () {
                        setState(() {
                          _newSelectionMode = !_newSelectionMode;
                          if (!_newSelectionMode) {
                            _selectedNewIds.clear();
                          }
                        });
                      },
                      icon: Icon(
                        _newSelectionMode
                            ? Icons.close
                            : Icons.check_box_outlined,
                      ),
                    ),
                  ],
                ],
              ),
              if (!isInventoryMode && _newSelectionMode) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: selectedNewDocs.isEmpty
                        ? null
                        : () => _moveNewItemsToRecentlyAdded(selectedNewDocs),
                    icon: const Icon(Icons.move_to_inbox),
                    label: Text(
                      selectedNewDocs.isEmpty
                          ? 'Move To Recent'
                          : 'Move To Recent (${selectedNewDocs.length})',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(child: isInventoryMode ? _buildList() : _buildNewList()),
        Material(
          elevation: 8,
          color: Theme.of(context).colorScheme.surface,
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildSummaryCountChip('Saved Tags', '$_totalCount'),
                    _buildSummaryCountChip(
                      'Inventory',
                      '${_loadedTags.length}',
                    ),
                    if (_appendRecentToInventory)
                      _buildSummaryCountChip(
                        'Recent',
                        '${_recentlyAddedTags.length}',
                      ),
                    _buildSummaryCountChip('New', '${filteredNewDocs.length}'),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  isInventoryMode
                      ? 'Total Stocks (Net Weight)'
                      : 'Newly Created Totals (Net Weight)',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildNetSummaryTile(
                        'gold22kt',
                        visibleWeightTotals['gold22kt']!,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildNetSummaryTile(
                        'gold18kt',
                        visibleWeightTotals['gold18kt']!,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildNetSummaryTile(
                        'silver',
                        visibleWeightTotals['silver']!,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _InventoryWeightTotals {
  double gross = 0;
  double less = 0;
  double nett = 0;
}
