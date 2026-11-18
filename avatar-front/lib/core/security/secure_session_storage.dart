/// ХРАНИЛИЩЕ СЕССИИ SUPABASE В KEYCHAIN / KEYSTORE.
///
/// По умолчанию supabase_flutter кладёт сессию (access + refresh токен) в
/// SharedPreferences — это открытый файл, который читается из бэкапа и на
/// рутованном устройстве. Здесь токены лежат в защищённом хранилище ОС:
///  * iOS — Keychain, доступ после первой разблокировки, без переноса на
///    другое устройство и без iCloud-синхронизации;
///  * Android — шифрование AES-GCM, ключ в Android Keystore.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              // По умолчанию: AES-GCM, ключ в Android Keystore (API 23+).
              aOptions: AndroidOptions(),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  static const sessionKey = 'avatar.supabase.session';

  final FlutterSecureStorage _storage;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() => _storage.containsKey(key: sessionKey);

  @override
  Future<String?> accessToken() => _storage.read(key: sessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: sessionKey, value: persistSessionString);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: sessionKey);
}
