import 'dart:math';

class ShareFileNamer {
  const ShareFileNamer._();

  static ShareFileBatch startBatch({
    required String prefix,
    required String extension,
  }) {
    final normalizedPrefix = _normalizePrefix(prefix);
    final normalizedExtension = _normalizeExtension(extension);
    final token = _generateToken();
    return ShareFileBatch._(
      prefix: normalizedPrefix,
      extension: normalizedExtension,
      token: token,
    );
  }

  static String _normalizePrefix(String value) {
    final lettersOnly = value.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    if (lettersOnly.length >= 2) {
      return lettersOnly.substring(0, 2);
    }
    if (lettersOnly.length == 1) {
      return '${lettersOnly}x';
    }
    return 'xx';
  }

  static String _normalizeExtension(String value) {
    final noDot = value.trim().toLowerCase().replaceAll(RegExp(r'^\.+'), '');
    final cleaned = noDot.replaceAll(RegExp(r'[^a-z0-9]'), '');
    return cleaned.isEmpty ? 'bin' : cleaned;
  }

  static String _generateToken() {
    final random = Random.secure().nextInt(36 * 36 * 36);
    return random.toRadixString(36).padLeft(3, '0');
  }
}

class ShareFileBatch {
  ShareFileBatch._({
    required this.prefix,
    required this.extension,
    required this.token,
  });

  final String prefix;
  final String extension;
  final String token;
  int _counter = 0;

  String nextName() {
    _counter += 1;
    final serial = _counter <= 99
        ? _counter.toString().padLeft(2, '0')
        : _counter.toString();
    return '$prefix${token}_$serial.$extension';
  }
}
