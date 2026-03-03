import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;

class QrCrypto {
  //Replace with your own secret (32 chars for AES-256).
  static const String _keyString = '11111111111111111111111111111111';

  static enc.Key _key() {
    final key = _keyString.padRight(32, '0').substring(0, 32);
    return enc.Key.fromUtf8(key);
  }

  static String encrypt(String plaintext) {
    final iv = enc.IV(_randomBytes(16));
    final encrypter = enc.Encrypter(enc.AES(_key(), mode: enc.AESMode.cbc));
    final encrypted = encrypter.encrypt(plaintext, iv: iv);
    final payload = {
      'iv': base64UrlEncode(iv.bytes),
      'data': encrypted.base64,
    };
    return base64UrlEncode(utf8.encode(jsonEncode(payload)));
  }

  static String decrypt(String payload) {
    final decoded = utf8.decode(base64Url.decode(payload));
    final map = jsonDecode(decoded) as Map<String, dynamic>;
    final iv = enc.IV(base64Url.decode(map['iv'] as String));
    final encrypted = enc.Encrypted.fromBase64(map['data'] as String);
    final encrypter = enc.Encrypter(enc.AES(_key(), mode: enc.AESMode.cbc));
    return encrypter.decrypt(encrypted, iv: iv);
  }

  static Uint8List _randomBytes(int length) {
    final rnd = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => rnd.nextInt(256)),
    );
  }
}
