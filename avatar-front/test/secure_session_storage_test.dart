import 'package:avatar_app/core/security/secure_session_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('сессия пишется, читается и стирается через защищённое хранилище',
      () async {
    FlutterSecureStorage.setMockInitialValues({});
    final s = SecureSessionStorage();
    await s.initialize();

    expect(await s.hasAccessToken(), isFalse);
    expect(await s.accessToken(), isNull);

    await s.persistSession('{"access_token":"a","refresh_token":"r"}');
    expect(await s.hasAccessToken(), isTrue);
    expect(await s.accessToken(), contains('refresh_token'));

    await s.removePersistedSession();
    expect(await s.hasAccessToken(), isFalse);
  });
}
