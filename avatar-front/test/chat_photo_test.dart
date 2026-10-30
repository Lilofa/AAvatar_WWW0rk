/// ТЕСТЫ ФОТО В ЧАТЕ ЗАКАЗА (v2): скрепка → чип → отправка с вложением.
library;

import 'dart:convert';

import 'package:avatar_app/data/mock_orders_repository.dart';
import 'package:avatar_app/features/order_chat/presentation/order_chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

class _FakePicker extends ImagePickerPlatform {
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async =>
      XFile.fromData(
        // валидный PNG 1x1: Image.memory в чипе должен декодироваться
        base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='),
        name: 'photo.jpg',
        mimeType: 'image/png',
      );
}

void main() {
  setUp(() {
    MockControls.instant = true;
    MockControls.mode = MockMode.normal;
    MockControls.randomErrorEveryN = 0;
    MockControls.simulateOffline = false;
    ImagePickerPlatform.instance = _FakePicker();
  });

  tearDown(() {
    MockControls.instant = false;
    MockControls.mode = MockMode.normal;
    MockControls.simulateOffline = false;
  });

  Future<void> settle(WidgetTester tester, [int frames = 4]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('скрепка → чип вложения → отправка → пузырь с фото',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: OrderChatScreen(
        repository: MockOrdersRepository(),
        orderId: 'ord-2001',
      ),
    ));
    await settle(tester);

    await tester.tap(find.byKey(const Key('chat_attach')));
    await settle(tester, 2);
    expect(find.byKey(const Key('chat_attach_chip')), findsOneWidget);
    expect(find.textContaining('.jpg'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('chat_input')), 'Фото груза');
    await tester.tap(find.byKey(const Key('chat_send')));
    await settle(tester);
    // чип ушёл, в ленте чата появился пузырь с вложением
    expect(find.byKey(const Key('chat_attach_chip')), findsNothing);
    expect(find.byKey(const Key('chat_attachment')), findsWidgets);
    expect(find.text('Фото груза'), findsOneWidget);
  });

  testWidgets('кнопка удаления снимает вложение', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: OrderChatScreen(
        repository: MockOrdersRepository(),
        orderId: 'ord-2001',
      ),
    ));
    await settle(tester);
    await tester.tap(find.byKey(const Key('chat_attach')));
    await settle(tester, 2);
    await tester.tap(find.byKey(const Key('chat_attach_remove')));
    await settle(tester, 2);
    expect(find.byKey(const Key('chat_attach_chip')), findsNothing);
  });

  test('mock хранит attachmentUrl в сообщении', () async {
    final repo = MockOrdersRepository();
    await repo.sendOrderChatMessage(
      orderId: 'ord-2001',
      text: 'с фото',
      attachmentUrl: 'mock://orders/ord-2001/x.jpg',
    );
    final list = await repo.watchOrderChat(orderId: 'ord-2001').first;
    expect(list.last.attachmentUrl, 'mock://orders/ord-2001/x.jpg');
  });
}
