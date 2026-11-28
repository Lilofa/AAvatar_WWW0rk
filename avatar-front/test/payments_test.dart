/// Оплата заказа: способ выбирает заказчик, «оплачено» отмечает диспетчер
/// (миграция 20261126130000_order_payments).
library;

import 'package:avatar_app/data/mock_orders_repository.dart';
import 'package:avatar_app/data/supabase/mappers.dart';
import 'package:avatar_app/features/dispatcher/presentation/dispatcher_screen.dart';
import 'package:avatar_app/features/order_flow/domain/enums.dart';
import 'package:avatar_app/features/order_flow/domain/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CreateOrderRequest _req(PaymentMethod m) => CreateOrderRequest(
      address: 'г. Томск, пр. Ленина, 1',
      timeStart: DateTime.now().add(const Duration(hours: 3)),
      peopleCount: 2,
      plannedDurationMin: 120,
      taskTitle: 'Переезд',
      taskDescription: 'Диван и 10 коробок',
      urgency: OrderUrgency.current,
      tariff: '2000 RUB',
      paymentMethod: m,
    );

void main() {
  setUp(() {
    MockControls.instant = true;
    MockControls.mode = MockMode.normal;
    MockControls.randomErrorEveryN = 0;
    MockControls.simulateDispatcher = false;
  });

  tearDown(() {
    MockControls.instant = false;
    MockControls.simulateDispatcher = true;
  });

  test('способ оплаты уходит на сервер, статус оплаты — нет', () {
    final row = orderInsertFromRequest(_req(PaymentMethod.invoice), clientId: 'c1');
    expect(row['payment_method'], 'invoice');
    expect(row.containsKey('payment_status'), isFalse);
    expect(row.containsKey('paid_amount'), isFalse);
  });

  test('с сервера читаются способ, статус и сумма', () {
    final o = orderFromRow({
      'id': 'o1',
      'client_id': 'c1',
      'address_from': 'A',
      'scheduled_at': '2026-11-26T05:00:00Z',
      'status': 'created',
      'payment_method': 'transfer',
      'payment_status': 'paid',
      'paid_amount': '1500.00',
    });
    expect(o.paymentMethod, PaymentMethod.transfer);
    expect(o.paymentStatus, PaymentStatus.paid);
    expect(o.paidAmount, 1500);
  });

  test('новый заказ: выбранный способ, не оплачен', () async {
    final repo = MockOrdersRepository();
    final o = await repo.createOrder(_req(PaymentMethod.transfer));
    expect(o.paymentMethod, PaymentMethod.transfer);
    expect(o.paymentStatus, PaymentStatus.unpaid);
  });

  testWidgets('диспетчер отмечает оплату и снимает отметку', (tester) async {
    final repo = MockOrdersRepository();
    await tester.pumpWidget(MaterialApp(
      home: DispatcherOrderScreen(repository: repo, orderId: 'ord-1001'),
    ));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('disp_payment_card')), findsOneWidget);
    expect(find.textContaining('Не оплачен'), findsOneWidget);

    await tester.tap(find.byKey(const Key('disp_mark_paid')));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('disp_mark_unpaid')), findsOneWidget);
    expect((await repo.getOrder(orderId: 'ord-1001')).paymentStatus, PaymentStatus.paid);

    await tester.tap(find.byKey(const Key('disp_mark_unpaid')));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect((await repo.getOrder(orderId: 'ord-1001')).paymentStatus, PaymentStatus.unpaid);
  });
}
