import 'package:avatar_app/data/supabase/supabase_orders_repository.dart';
import 'package:flutter_test/flutter_test.dart';

// Чек-лист п. 3: фото заказа в приватном бакете, показ — по подписанной ссылке.
void main() {
  const p = SupabaseOrdersRepository.attachmentPath;

  test('новая ссылка storage://orders/… → путь в бакете', () {
    expect(p('storage://orders/abc/1_photo.jpg'), 'abc/1_photo.jpg');
  });

  test('старая публичная ссылка → путь (для подписи)', () {
    expect(
      p('https://x.supabase.co/storage/v1/object/public/orders/abc/1.jpg'),
      'abc/1.jpg',
    );
  });

  test('чужие и опасные ссылки не подписываем', () {
    expect(p('https://evil.example/tracker.png'), isNull);
    expect(p('storage://orders/abc/../other/1.jpg'), isNull);
    expect(p('storage://orders/'), isNull);
    expect(p('storage://avatars/u/1.jpg'), isNull);
  });
}
