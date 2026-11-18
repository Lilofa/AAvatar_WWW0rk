import 'package:avatar_app/data/mock_orders_repository.dart';
import 'package:avatar_app/data/orders_repository.dart';
import 'package:avatar_app/features/order_active/presentation/order_active_screen.dart';
import 'package:avatar_app/features/order_flow/domain/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Профиль только-грузчика, не состоящего в бригаде открытого заказа.
class _OutsiderRepo extends MockOrdersRepository {
  @override
  Stream<UserProfile?> watchCurrentUser() => Stream.value(const UserProfile(
        id: 'outsider',
        name: 'Чужой',
        phone: '+79990000000',
        roles: {UserRole.porter},
      ));
}

void main() {
  setUp(() {
    MockControls.instant = true;
    MockControls.mode = MockMode.normal;
    MockControls.randomErrorEveryN = 0;
  });

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 250));
    }
  }

  testWidgets('чат: не участник заказа видит объяснение, а не ошибку прав',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: OrderActiveScreen(repository: _OutsiderRepo(), orderId: 'ord-1001'),
    ));
    await settle(tester);
    await tester.tap(find.byKey(const Key('active_chat_btn')));
    await settle(tester);
    expect(find.byKey(const Key('active_chat_locked')), findsOneWidget);
    expect(find.text('Чат по заказу'), findsNothing,
        reason: 'экран чата не открывается');
  });
}
