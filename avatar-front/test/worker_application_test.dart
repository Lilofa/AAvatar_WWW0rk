/// Регистрация только заказчиком; грузчиком — по заявке из кабинета
/// (просьба Артёма 26.11.2026), одобряет диспетчер.
library;

import 'package:avatar_app/data/mock_orders_repository.dart';
import 'package:avatar_app/features/auth/presentation/login_screen.dart';
import 'package:avatar_app/features/client_orders/presentation/client_cabinet_screen.dart';
import 'package:avatar_app/features/dispatcher/presentation/dispatcher_screen.dart';
import 'package:avatar_app/features/order_flow/domain/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    MockControls.instant = true;
    MockControls.mode = MockMode.normal;
    MockControls.randomErrorEveryN = 0;
    MockControls.simulateOffline = false;
    MockControls.simulateDispatcher = false;
  });

  tearDown(() {
    MockControls.instant = false;
    MockControls.mode = MockMode.normal;
    MockControls.simulateDispatcher = true;
    MockControls.setDemoRoles(MockControls.allDemoRoles);
  });

  Future<void> settle(WidgetTester tester, [int frames = 4]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tapVisible(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.pump();
    await tester.tap(find.byKey(Key(key)));
    await settle(tester);
  }

  testWidgets('вход: выбора роли больше нет, есть подсказка про заявку',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LoginScreen(
          repository: MockOrdersRepository(), onAuthenticated: (_) {}),
    ));
    await settle(tester);
    expect(find.byKey(const Key('login_role_client')), findsNothing);
    expect(find.byKey(const Key('login_role_porter')), findsNothing);
    expect(find.byKey(const Key('login_worker_hint')), findsOneWidget);
  });

  testWidgets('заказчик подаёт заявку: проверка анкеты, затем «На рассмотрении»',
      (tester) async {
    MockControls.setDemoRoles({UserRole.client});
    final repo = MockOrdersRepository();
    await tester.pumpWidget(MaterialApp(home: ClientCabinetScreen(repository: repo)));
    await settle(tester);

    expect(find.byKey(const Key('cab_worker_card')), findsOneWidget);
    await tapVisible(tester, 'cab_worker_apply');

    // Без города и без 18+ — не отправляется.
    await tapVisible(tester, 'worker_app_submit');
    expect(find.byKey(const Key('worker_app_error')), findsOneWidget);
    expect(find.text('Выберите город.'), findsOneWidget);

    await tapVisible(tester, 'worker_app_city_Томск');
    await tapVisible(tester, 'worker_app_submit');
    expect(find.text('Работать грузчиком можно с 18 лет.'), findsOneWidget);

    await tapVisible(tester, 'worker_app_adult');
    await tapVisible(tester, 'worker_app_submit');
    await settle(tester, 4);

    // Вернулись в кабинет: заявка ждёт, кнопки «Подать» нет.
    await tester.ensureVisible(find.byKey(const Key('cab_worker_card'), skipOffstage: false));
    await tester.pump();
    expect(find.byKey(const Key('worker_app_pending')), findsOneWidget);
    expect(find.byKey(const Key('cab_worker_apply')), findsNothing);
    final mine = await repo.myWorkerApplication();
    expect(mine?.city, 'Томск');
  });

  testWidgets('грузчику карточка заявки не показывается', (tester) async {
    MockControls.setDemoRoles({UserRole.client, UserRole.porter});
    await tester.pumpWidget(MaterialApp(
      home: ClientCabinetScreen(repository: MockOrdersRepository()),
    ));
    await settle(tester);
    expect(find.byKey(const Key('cab_profile')), findsOneWidget);
    expect(find.byKey(const Key('cab_worker_card')), findsNothing);
  });

  testWidgets('новый пользователь без заказов тоже видит кнопку заявки',
      (tester) async {
    MockControls.setDemoRoles({UserRole.client});
    MockControls.mode = MockMode.empty;
    await tester.pumpWidget(MaterialApp(
      home: ClientCabinetScreen(repository: MockOrdersRepository()),
    ));
    await settle(tester);
    expect(find.byKey(const Key('cab_empty')), findsOneWidget);
    expect(find.byKey(const Key('cab_worker_apply')), findsOneWidget);
  });

  testWidgets('диспетчер одобряет свою заявку — у человека появляется роль грузчика',
      (tester) async {
    MockControls.setDemoRoles({UserRole.client});
    final repo = MockOrdersRepository();
    await repo.submitWorkerApplication(fullName: 'Артём Иванов', city: 'Новосибирск');

    await tester.pumpWidget(MaterialApp(home: DispatcherScreen(repository: repo)));
    await settle(tester);
    expect(find.byKey(const Key('disp_worker_apps')), findsOneWidget);
    expect(find.text('Артём Иванов'), findsOneWidget);

    final mine = await repo.myWorkerApplication();
    await tapVisible(tester, 'disp_worker_approve_${mine!.id}');
    expect(MockControls.demoRoles.contains(UserRole.porter), isTrue);
    expect(find.text('Артём Иванов'), findsNothing);
  });

  testWidgets('отклонение с причиной: человек видит причину и может подать снова',
      (tester) async {
    MockControls.setDemoRoles({UserRole.client});
    final repo = MockOrdersRepository();
    await tester.pumpWidget(MaterialApp(home: DispatcherScreen(repository: repo)));
    await settle(tester);

    await tapVisible(tester, 'disp_worker_reject_wa-demo-1');
    await tester.enterText(
        find.byKey(const Key('disp_worker_reject_reason')), 'Не дозвонились');
    await tester.tap(find.byKey(const Key('disp_worker_reject_confirm')));
    await settle(tester);
    expect(find.byKey(const Key('disp_worker_app_wa-demo-1')), findsNothing);

    final pending = await repo.pendingWorkerApplications();
    expect(pending.where((a) => a.id == 'wa-demo-1'), isEmpty);
  });
}
