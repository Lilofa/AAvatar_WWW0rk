/// Политика и Соглашение внутри приложения (App Store 5.1.1(i)).
library;

import 'dart:io';

import 'package:avatar_app/core/legal/consent_text.dart';
import 'package:avatar_app/core/legal/legal_doc_screen.dart';
import 'package:avatar_app/data/mock_orders_repository.dart';
import 'package:avatar_app/features/auth/presentation/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _public(String path) => File(path)
    .readAsStringSync()
    .replaceAll(RegExp(r'<!--.*?-->\s*', dotAll: true), '')
    .trim();

void main() {
  for (final doc in LegalDoc.values) {
    final src = doc == LegalDoc.privacy
        ? '../docs/legal/privacy-policy.md'
        : '../docs/legal/terms-of-use.md';

    test('${doc.name}: копия в приложении совпадает с docs/legal '
        '(иначе: python3 scripts/sync-legal.py)', () {
      expect(File(doc.asset).readAsStringSync().trim(), _public(src));
    });

    test('${doc.name}: без незаполненных [полей] и с оператором', () {
      final text = _public(src);
      expect(RegExp(r'\[[^\]]*\]').hasMatch(text), isFalse);
      expect(text, contains('ИНН 701739286703'));
      expect(text, contains('22-8070@mail.ru'));
    });

    testWidgets('${doc.name}: экран показывает документ', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(children: legalBlocks(_public(src))),
        ),
      ));
      expect(find.textContaining('Грищук', findRichText: true), findsWidgets);
    });
  }

  test('согласие при входе называет оператора, версия обновлена', () {
    expect(consentText, contains('Грищуку Александру Сергеевичу'));
    expect(consentText, isNot(contains('[')));
    expect(consentVersion, '2026-11-26');
  });

  testWidgets('на экране входа есть ссылки на Соглашение и Политику', (tester) async {
    MockControls.instant = true;
    addTearDown(() => MockControls.instant = false);
    await tester.pumpWidget(MaterialApp(
      home: LoginScreen(repository: MockOrdersRepository(), onAuthenticated: (_) {}),
    ));
    await tester.pump();
    expect(find.byKey(const Key('login_terms_link')), findsOneWidget);
    expect(find.byKey(const Key('login_privacy_link')), findsOneWidget);
  });
}
