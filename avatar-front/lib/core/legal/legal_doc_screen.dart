/// Экран юридического документа внутри приложения (Политика, Соглашение).
///
/// App Store 5.1.1(i): политика должна быть доступна и в самом приложении.
/// Тексты — assets/legal/*.md (копии docs/legal, scripts/sync-legal.py).
/// Простой разбор markdown: заголовки, абзацы, списки, таблицы, **жирный**.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

enum LegalDoc {
  privacy('Политика конфиденциальности', 'assets/legal/privacy.md'),
  terms('Пользовательское соглашение', 'assets/legal/terms.md');

  const LegalDoc(this.title, this.asset);
  final String title;
  final String asset;
}

Future<void> openLegalDoc(BuildContext context, LegalDoc doc) =>
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LegalDocScreen(doc: doc),
    ));

class LegalDocScreen extends StatelessWidget {
  const LegalDocScreen({super.key, required this.doc, this.bundle});

  final LegalDoc doc;
  final AssetBundle? bundle;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(doc.title)),
        body: FutureBuilder<String>(
          future: (bundle ?? rootBundle).loadString(doc.asset),
          builder: (context, snap) {
            if (snap.hasError) {
              return const Center(child: Text('Не удалось открыть документ.'));
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return SelectionArea(
              child: ListView(
                key: Key('legal_doc_${doc.name}'),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: legalBlocks(snap.data!),
              ),
            );
          },
        ),
      );
}

/// Разбор нашего подмножества markdown в виджеты (публично — для тестов).
List<Widget> legalBlocks(String md) {
  final out = <Widget>[];
  final para = <String>[];
  final lines = md.split('\n');

  void flush() {
    if (para.isEmpty) return;
    out.add(Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text.rich(_inline(para.join(' '))),
    ));
    para.clear();
  }

  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    if (line.startsWith('# ')) {
      flush();
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(line.substring(2),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
      ));
    } else if (line.startsWith('## ')) {
      flush();
      out.add(Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(line.substring(3),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ));
    } else if (line.startsWith('|')) {
      flush();
      final rows = <List<String>>[];
      while (i < lines.length && lines[i].startsWith('|')) {
        rows.add(lines[i]
            .substring(1, lines[i].length - (lines[i].endsWith('|') ? 1 : 0))
            .split('|')
            .map((c) => c.trim())
            .toList());
        i++;
      }
      final head = rows.first;
      for (final r in rows.skip(2)) {
        out.add(Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var c = 0; c < r.length; c++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text.rich(c == 0
                      ? _inline('**${r[c].replaceAll('**', '')}**')
                      : TextSpan(children: [
                          TextSpan(
                            text: c < head.length ? '${head[c]}: ' : '',
                            style: const TextStyle(color: AppColors.muted),
                          ),
                          _inline(r[c]),
                        ])),
                ),
            ],
          ),
        ));
      }
      continue;
    } else if (line.startsWith('- ')) {
      flush();
      final items = <String>[];
      while (i < lines.length && (lines[i].startsWith('- ') || lines[i].startsWith('  '))) {
        if (lines[i].startsWith('- ')) {
          items.add(lines[i].substring(2));
        } else {
          items[items.length - 1] += ' ${lines[i].trim()}';
        }
        i++;
      }
      for (final it in items) {
        out.add(Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('•  '),
              Expanded(child: Text.rich(_inline(it))),
            ],
          ),
        ));
      }
      continue;
    } else if (line.trim().isEmpty) {
      flush();
    } else {
      para.add(line.trim());
    }
    i++;
  }
  flush();
  return out;
}

TextSpan _inline(String text) {
  final spans = <InlineSpan>[];
  final re = RegExp(r'\*\*(.+?)\*\*');
  var pos = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > pos) spans.add(TextSpan(text: text.substring(pos, m.start)));
    spans.add(TextSpan(
        text: m.group(1), style: const TextStyle(fontWeight: FontWeight.w700)));
    pos = m.end;
  }
  if (pos < text.length) spans.add(TextSpan(text: text.substring(pos)));
  return TextSpan(children: spans, style: const TextStyle(height: 1.4));
}
