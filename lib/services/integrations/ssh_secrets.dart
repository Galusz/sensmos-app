import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Hasła SSH — jedno miejsce na format klucza, żeby ekran sesji i edytor celu nie
/// rozjechały się na dwa różne (wtedy „zapamiętane" hasło znika przy następnym wejściu).
///
/// Hasło NIGDY nie idzie do SharedPreferences: to zwykły plik XML w katalogu apki.
/// Ląduje w tym samym szyfrowanym magazynie co klucze parowania i tylko za zgodą usera.
class SshSecrets {
  static const _prefix = 'term_pass_';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static String keyFor(String deviceId, String slug) => '$_prefix${deviceId}_$slug';

  /// Hasło DOKŁADNIE tego celu. Bez żadnych podmian: czytanie starego, wspólnego dla całego
  /// noda hasła podstawiało je każdemu nowo dodanemu celowi, także takiemu, przy którym user
  /// świadomie nie zaznaczył „zapamiętaj".
  static Future<String?> read(String deviceId, String slug) =>
      _storage.read(key: keyFor(deviceId, slug));

  /// Hasło z czasów „jeden cel na node" (klucz bez sluga) — czytane wyłącznie przy
  /// przenoszeniu tamtego wpisu na listę, potem kasowane.
  static Future<String?> readLegacy(String deviceId) => _storage.read(key: '$_prefix$deviceId');
  static Future<void> dropLegacy(String deviceId) => _storage.delete(key: '$_prefix$deviceId');

  static Future<void> write(String deviceId, String slug, String pass) =>
      _storage.write(key: keyFor(deviceId, slug), value: pass);

  static Future<void> forget(String deviceId, String slug) =>
      _storage.delete(key: keyFor(deviceId, slug));
}
