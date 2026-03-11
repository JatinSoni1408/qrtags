import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'l10n/app_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/edit_tag_request.dart';
import 'constants/storage_keys.dart';
import 'data/tag_migration_runner.dart';
import 'pages/generate_page.dart';
import 'pages/inventory_page.dart';
import 'pages/login_page.dart';
import 'pages/bhav_page.dart';
import 'pages/old_page.dart';
import 'pages/sales_page.dart';
import 'pages/scan_page.dart';
import 'pages/total_page.dart';
import 'widgets/settings_button.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _resetWorkingPagesStateOnColdStart();
  runApp(const MyApp());
}

Future<void> _resetWorkingPagesStateOnColdStart() async {
  final prefs = await SharedPreferences.getInstance();
  const keysToClear = <String>[
    // Scan page selection state
    StorageKeys.selectedItems,
    StorageKeys.selectedItemsGst,
    // Old page entries
    StorageKeys.oldItems,
    // Total page draft state
    StorageKeys.totalDraftCustomerName,
    StorageKeys.totalDraftCustomerMobile,
    StorageKeys.totalDraftDiscount,
    StorageKeys.totalDraftPaymentEntries,
    // Manual hallmark confirmation tied to current scan session
    StorageKeys.manualItemsHallmarked,
  ];
  for (final key in keysToClear) {
    await prefs.remove(key);
  }
}

class _AppTheme {
  static const _seedColor = Color(0xFF0F766E);
  static const _lightBackground = Color(0xFFF6FAFC);
  static const _darkBackground = Color(0xFF0B1115);
  static const _surfaceRadius = 18.0;
  static const _controlRadius = 14.0;

  static final ThemeData lightTheme = _buildTheme(Brightness.light);
  static final ThemeData darkTheme = _buildTheme(Brightness.dark);

  static ThemeData _buildTheme(Brightness brightness) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seedColor,
        brightness: brightness,
      ),
    );
    final scheme = base.colorScheme;
    final isLight = brightness == Brightness.light;
    final cardColor = isLight ? Colors.white : scheme.surfaceContainerHigh;
    final fieldFill = isLight
        ? const Color(0xFFF1F6F9)
        : scheme.surfaceContainerHighest;
    final textTheme = base.textTheme.copyWith(
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.35),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.35),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: isLight ? _lightBackground : _darkBackground,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: isLight ? 1 : 0,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_surfaceRadius),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fieldFill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_controlRadius),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_controlRadius),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_controlRadius),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_controlRadius),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.outlineVariant),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_controlRadius),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: textTheme.labelLarge,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: cardColor,
        elevation: 8,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: scheme.primary,
        unselectedItemColor: scheme.onSurfaceVariant,
        selectedLabelStyle: textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_surfaceRadius + 2),
        ),
        titleTextStyle: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_controlRadius),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.onPrimary;
          }
          return scheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primary;
          }
          return scheme.surfaceContainerHighest;
        }),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.45),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QRTags',
      debugShowCheckedModeBanner: false,
      theme: _AppTheme.lightTheme,
      darkTheme: _AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const _BootstrapGate(),
    );
  }
}

class _BootstrapGate extends StatefulWidget {
  const _BootstrapGate();

  @override
  State<_BootstrapGate> createState() => _BootstrapGateState();
}

class _BootstrapGateState extends State<_BootstrapGate> {
  late final Future<void> _bootstrapFuture;

  @override
  void initState() {
    super.initState();
    _bootstrapFuture = Firebase.initializeApp().timeout(
      const Duration(seconds: 20),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _bootstrapFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final errorDetails = snapshot.error?.toString() ?? 'Unknown error';
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Failed to initialize app services. Please restart the app.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      errorDetails,
                      textAlign: TextAlign.center,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.redAccent),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return const _ConnectivityGate(child: _AuthGate());
      },
    );
  }
}

class _ConnectivityGate extends StatefulWidget {
  const _ConnectivityGate({required this.child});

  final Widget child;

  @override
  State<_ConnectivityGate> createState() => _ConnectivityGateState();
}

class _ConnectivityGateState extends State<_ConnectivityGate> {
  bool _online = false;
  bool _checking = true;
  bool _inFlight = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_checkConnectivity());
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      unawaited(_checkConnectivity());
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkConnectivity() async {
    if (_inFlight) {
      return;
    }
    _inFlight = true;
    if (mounted) {
      setState(() {
        _checking = true;
      });
    }
    bool connected = false;
    try {
      await FirebaseFirestore.instance
          .collection('app_config')
          .doc('version')
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 6));
      connected = true;
    } catch (_) {
      connected = false;
    } finally {
      _inFlight = false;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _online = connected;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_online) {
      return widget.child;
    }
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off, size: 54),
                const SizedBox(height: 14),
                const Text(
                  'Enable Wi-Fi / Internet',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Please enable Wi-Fi or connect to the internet before logging in.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                ElevatedButton(
                  onPressed: _checking
                      ? null
                      : () => unawaited(_checkConnectivity()),
                  child: Text(_checking ? 'Checking...' : 'Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VersionGateResult {
  const _VersionGateResult({
    required this.blocked,
    required this.currentVersion,
    required this.currentBuildNumber,
    required this.minVersion,
    required this.minBuildNumber,
    required this.message,
  });

  final bool blocked;
  final String currentVersion;
  final int currentBuildNumber;
  final String minVersion;
  final int minBuildNumber;
  final String message;
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  static const String _configCollection = 'app_config';
  static const String _versionDocId = 'version';
  static const String _minAppVersionKey = 'min_app_version';
  static const String _minBuildNumberKey = 'min_build_number';
  static const String _updateMessageKey = 'update_message';

  late Future<_VersionGateResult> _versionGateFuture;
  bool _tagMigrationQueued = false;

  @override
  void initState() {
    super.initState();
    _versionGateFuture = _loadVersionGate();
  }

  int _toInt(dynamic value, {int fallback = 0}) {
    if (value == null) {
      return fallback;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value.toString()) ?? fallback;
  }

  int _compareVersions(String a, String b) {
    List<int> parseParts(String version) {
      return version
          .split('.')
          .map(
            (part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
          )
          .toList();
    }

    final left = parseParts(a);
    final right = parseParts(b);
    final maxLen = left.length > right.length ? left.length : right.length;
    for (int i = 0; i < maxLen; i++) {
      final l = i < left.length ? left[i] : 0;
      final r = i < right.length ? right[i] : 0;
      if (l != r) {
        return l.compareTo(r);
      }
    }
    return 0;
  }

  Future<_VersionGateResult> _loadVersionGate() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;
    final currentBuildNumber = _toInt(packageInfo.buildNumber, fallback: 0);

    try {
      final doc = await FirebaseFirestore.instance
          .collection(_configCollection)
          .doc(_versionDocId)
          .get()
          .timeout(const Duration(seconds: 12));
      if (!doc.exists || doc.data() == null) {
        return _VersionGateResult(
          blocked: false,
          currentVersion: currentVersion,
          currentBuildNumber: currentBuildNumber,
          minVersion: '',
          minBuildNumber: 0,
          message: '',
        );
      }

      final data = doc.data()!;
      final minVersion = data[_minAppVersionKey]?.toString().trim() ?? '';
      final minBuildNumber = _toInt(data[_minBuildNumberKey], fallback: 0);
      final message = data[_updateMessageKey]?.toString().trim() ?? '';
      bool blocked = false;

      if (minVersion.isNotEmpty &&
          _compareVersions(currentVersion, minVersion) < 0) {
        blocked = true;
      }
      if (minBuildNumber > 0 && currentBuildNumber < minBuildNumber) {
        blocked = true;
      }

      return _VersionGateResult(
        blocked: blocked,
        currentVersion: currentVersion,
        currentBuildNumber: currentBuildNumber,
        minVersion: minVersion,
        minBuildNumber: minBuildNumber,
        message: message,
      );
    } catch (_) {
      return _VersionGateResult(
        blocked: false,
        currentVersion: currentVersion,
        currentBuildNumber: currentBuildNumber,
        minVersion: '',
        minBuildNumber: 0,
        message: '',
      );
    }
  }

  Future<String> _loadRole(User user) async {
    final users = FirebaseFirestore.instance.collection('users');
    final docRef = users.doc(user.uid);
    try {
      final doc = await docRef.get().timeout(const Duration(seconds: 10));
      String role = 'staff';
      if (doc.exists) {
        role = doc.data()?['role']?.toString().toLowerCase() ?? 'staff';
        if (role != 'admin' && role != 'staff') {
          role = 'staff';
        }
        await docRef.set({
          'email': user.email ?? '',
          'updatedAt': FieldValue.serverTimestamp(),
          'lastLoginAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return role;
      }

      // Unknown users are staff by default; admin roles must be provisioned
      // explicitly in Firestore.
      await docRef.set({
        'uid': user.uid,
        'email': user.email ?? '',
        'role': 'staff',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastLoginAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return 'staff';
    } catch (_) {
      return 'staff';
    }
  }

  void _queueTagMigrationIfNeeded(String role) {
    if (role.toLowerCase() != 'admin' || _tagMigrationQueued) {
      return;
    }
    _tagMigrationQueued = true;
    unawaited(_runTagMigrationOnce());
  }

  Future<void> _runTagMigrationOnce() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await TagMigrationRunner.runIfNeeded(prefs: prefs);
    } catch (_) {
      // ignor e migration failures
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_VersionGateResult>(
      future: _versionGateFuture,
      builder: (context, versionSnapshot) {
        if (!versionSnapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final versionGate = versionSnapshot.data!;
        if (versionGate.blocked) {
          return _UpdateRequiredPage(
            versionGate: versionGate,
            onRetry: () {
              setState(() {
                _versionGateFuture = _loadVersionGate();
              });
            },
          );
        }

        return StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, authSnapshot) {
            if (authSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            final user = authSnapshot.data;
            if (user == null) {
              unawaited(SettingsButton.stopRatesSync());
              return const LoginPage();
            }
            return FutureBuilder<String>(
              future: _loadRole(user),
              builder: (context, roleSnapshot) {
                if (!roleSnapshot.hasData) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                final role = roleSnapshot.data!;
                _queueTagMigrationIfNeeded(role);
                SettingsButton.startRatesSync(
                  userId: user.uid,
                  userEmail: user.email ?? '',
                  canSeedRemote: role == 'admin',
                );
                return MyHomePage(
                  title: 'QRTags',
                  role: role,
                  userEmail: user.email ?? '',
                );
              },
            );
          },
        );
      },
    );
  }
}

class _UpdateRequiredPage extends StatelessWidget {
  const _UpdateRequiredPage({required this.versionGate, required this.onRetry});

  final _VersionGateResult versionGate;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final minVersionText = versionGate.minVersion.isNotEmpty
        ? versionGate.minVersion
        : 'build ${versionGate.minBuildNumber}';
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.system_update, size: 54),
                const SizedBox(height: 16),
                const Text(
                  'Update Required',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  'Current version: ${versionGate.currentVersion} (${versionGate.currentBuildNumber})',
                  textAlign: TextAlign.center,
                ),
                Text(
                  'Minimum required: $minVersionText',
                  textAlign: TextAlign.center,
                ),
                if (versionGate.message.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(versionGate.message, textAlign: TextAlign.center),
                ],
                const SizedBox(height: 20),
                ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _AppTab { bhav, inventory, tags, scan, old, sales, total }

class MyHomePage extends StatefulWidget {
  const MyHomePage({
    super.key,
    required this.title,
    required this.role,
    required this.userEmail,
  });

  final String title;
  final String role;
  final String userEmail;

  bool get isStaff => role.toLowerCase() == 'staff';

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _selectedIndex = 0;
  bool _openedRatesDialogOnLaunch = false;
  final ValueNotifier<EditTagRequest?> _editTagRequest =
      ValueNotifier<EditTagRequest?>(null);

  Future<bool> _confirmExit() async {
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Exit App'),
          content: const Text('Are you sure you want to exit?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Exit'),
            ),
          ],
        );
      },
    );
    return shouldExit ?? false;
  }

  List<_AppTab> get _tabOrder => widget.isStaff
      ? const [_AppTab.bhav, _AppTab.scan, _AppTab.old, _AppTab.total]
      : const [
          _AppTab.inventory,
          _AppTab.tags,
          _AppTab.scan,
          _AppTab.old,
          _AppTab.total,
          _AppTab.sales,
        ];

  int _indexOfTab(_AppTab tab) {
    final idx = _tabOrder.indexOf(tab);
    return idx < 0 ? 0 : idx;
  }

  bool _hasTab(_AppTab tab) => _tabOrder.contains(tab);

  void _setTab(_AppTab tab) {
    setState(() {
      _selectedIndex = _indexOfTab(tab);
    });
  }

  Future<void> _handleBackNavigation() async {
    final currentTab = _tabOrder[_selectedIndex];
    if (currentTab == _AppTab.total && _hasTab(_AppTab.old)) {
      _setTab(_AppTab.old);
      return;
    }
    if (currentTab == _AppTab.old && _hasTab(_AppTab.scan)) {
      _setTab(_AppTab.scan);
      return;
    }
    if (currentTab == _AppTab.scan && _hasTab(_AppTab.tags)) {
      _setTab(_AppTab.tags);
      return;
    }
    if (currentTab == _AppTab.scan && _hasTab(_AppTab.bhav)) {
      _setTab(_AppTab.bhav);
      return;
    }
    if (currentTab == _AppTab.tags && _hasTab(_AppTab.inventory)) {
      _setTab(_AppTab.inventory);
      return;
    }
    final shouldExit = await _confirmExit();
    if (shouldExit) {
      await SystemNavigator.pop();
    }
  }

  Future<bool> _scanSelectionHasManualItems() async {
    final prefs = await SharedPreferences.getInstance();
    final items =
        prefs.getStringList(StorageKeys.selectedItems) ?? const <String>[];
    for (final raw in items) {
      try {
        final parsed = jsonDecode(raw);
        if (parsed is Map<String, dynamic> &&
            parsed['entrySource']?.toString() == 'manual') {
          return true;
        }
      } catch (_) {
        // ignore malformed entries
      }
    }
    return false;
  }

  Future<bool> _confirmManualHallmarkIfNeeded() async {
    final hasManualItems = await _scanSelectionHasManualItems();
    if (!hasManualItems || !mounted) {
      return true;
    }

    final answer = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Manual Item Hallmark'),
          content: const Text(
            'Manual items are present in Scan list. '
            'Are these manual items hallmarked?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('No'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Yes'),
            ),
          ],
        );
      },
    );

    if (answer == null) {
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(StorageKeys.manualItemsHallmarked, answer);
    return true;
  }

  List<Widget> _buildPages() {
    return _tabOrder.map((tab) {
      switch (tab) {
        case _AppTab.bhav:
          return const BhavPage();
        case _AppTab.inventory:
          return InventoryPage(
            onEditTag: (request) {
              _editTagRequest.value = null;
              _editTagRequest.value = request;
              _setTab(_AppTab.tags);
            },
          );
        case _AppTab.tags:
          return GeneratePage(
            editRequest: _editTagRequest,
            canManageMasterData: !widget.isStaff,
            onUpdated: () {
              if (widget.isStaff) {
                _setTab(_AppTab.tags);
              } else {
                _setTab(_AppTab.inventory);
              }
            },
          );
        case _AppTab.scan:
          return ScanPage(
            onSelectedAdded: () {
              // no-op
            },
            onShowTotal: () {
              _setTab(_AppTab.total);
            },
          );
        case _AppTab.old:
          return const OldPage();
        case _AppTab.sales:
          return const SalesPage();
        case _AppTab.total:
          return TotalPage(
            canFinishTransaction: widget.role.toLowerCase() == 'admin',
          );
      }
    }).toList();
  }

  List<BottomNavigationBarItem> _buildItems() {
    return _tabOrder.map((tab) {
      switch (tab) {
        case _AppTab.bhav:
          return const BottomNavigationBarItem(
            icon: Icon(Icons.currency_rupee),
            label: 'Bhav',
          );
        case _AppTab.inventory:
          return const BottomNavigationBarItem(
            icon: Icon(Icons.inventory_2),
            label: 'Inventory',
          );
        case _AppTab.tags:
          return const BottomNavigationBarItem(
            icon: Icon(Icons.add),
            label: 'Tags',
          );
        case _AppTab.scan:
          return const BottomNavigationBarItem(
            icon: Icon(Icons.qr_code_scanner),
            label: 'Scan',
          );
        case _AppTab.old:
          return const BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'Old',
          );
        case _AppTab.sales:
          return const BottomNavigationBarItem(
            icon: Icon(Icons.point_of_sale),
            label: 'Sales',
          );
        case _AppTab.total:
          return const BottomNavigationBarItem(
            icon: Icon(Icons.trending_up),
            label: 'Total',
          );
      }
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _selectedIndex = _indexOfTab(_AppTab.scan);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openRatesOnLaunchIfNeeded();
    });
  }

  Future<void> _openRatesOnLaunchIfNeeded() async {
    if (!mounted || widget.isStaff || _openedRatesDialogOnLaunch) {
      return;
    }
    if (_selectedIndex != _indexOfTab(_AppTab.scan)) {
      return;
    }
    _openedRatesDialogOnLaunch = true;
    await SettingsButton.openRateSettings(context);
  }

  @override
  void didUpdateWidget(covariant MyHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedIndex >= _tabOrder.length) {
      _selectedIndex = _indexOfTab(_AppTab.scan);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openRatesOnLaunchIfNeeded();
    });
  }

  @override
  void dispose() {
    _editTagRequest.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = _buildPages();
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }
        await _handleBackNavigation();
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: _GstSettingsButton(
            onChanged: () {
              setState(() {});
            },
          ),
          title: Image.asset(
            'assets/images/logo.png',
            height: 56,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : const Color(0xFF1F2937),
            colorBlendMode: BlendMode.srcIn,
          ),
          centerTitle: true,
          actions: [
            if (!widget.isStaff) const _VibratingTitleSettingsButton(),
            SizedBox(
              width: 40,
              height: 40,
              child: IconButton(
                tooltip: 'Logout',
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                hoverColor: Colors.transparent,
                focusColor: Colors.transparent,
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                },
                icon: const Icon(Icons.logout, color: Colors.transparent),
              ),
            ),
          ],
        ),
        body: IndexedStack(index: _selectedIndex, children: pages),
        bottomNavigationBar: BottomNavigationBar(
          items: _buildItems(),
          currentIndex: _selectedIndex,
          selectedItemColor: Theme.of(context).colorScheme.primary,
          type: BottomNavigationBarType.fixed,
          onTap: (index) async {
            final targetTab = _tabOrder[index];
            if (targetTab == _AppTab.total) {
              final canOpen = await _confirmManualHallmarkIfNeeded();
              if (!canOpen || !mounted) {
                return;
              }
            }
            _setTab(targetTab);
          },
        ),
      ),
    );
  }
}

class _VibratingTitleSettingsButton extends StatelessWidget {
  const _VibratingTitleSettingsButton();

  @override
  Widget build(BuildContext context) {
    return const SettingsButton(
      tooltip: 'Settings',
      color: Colors.red,
      padding: EdgeInsets.zero,
    );
  }
}

class _GstSettingsButton extends StatelessWidget {
  const _GstSettingsButton({required this.onChanged});

  final VoidCallback onChanged;

  Future<void> _showGstToggle(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    bool gstEnabled = prefs.getBool(StorageKeys.gstEnabled) ?? false;
    bool makingEnabled = prefs.getBool(StorageKeys.makingEnabled) ?? false;
    bool discountEnabled = prefs.getBool(StorageKeys.discountEnabled) ?? false;
    if (!context.mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('GST'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Expanded(child: Text('GST Enabled')),
                      Switch(
                        value: gstEnabled,
                        onChanged: (value) {
                          setState(() {
                            gstEnabled = value;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Expanded(child: Text('Making Charge')),
                      Switch(
                        value: makingEnabled,
                        onChanged: (value) {
                          setState(() {
                            makingEnabled = value;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Expanded(child: Text('Discount')),
                      Switch(
                        value: discountEnabled,
                        onChanged: (value) {
                          setState(() {
                            discountEnabled = value;
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await prefs.setBool(StorageKeys.gstEnabled, gstEnabled);
                    await prefs.setBool(
                      StorageKeys.makingEnabled,
                      makingEnabled,
                    );
                    await prefs.setBool(
                      StorageKeys.discountEnabled,
                      discountEnabled,
                    );
                    SettingsButton.ratesVersion.value++;
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                    onChanged();
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () => _showGstToggle(context),
      behavior: HitTestBehavior.opaque,
      child: const SizedBox(width: 48, height: 48),
    );
  }
}
