/// ЭКРАН ЧАТА ПО ЗАКАЗУ (зона Артёма).
///
/// Четыре состояния: loading / data / empty / error (+ «Повторить»).
/// Дизайн минимальный, без виджетов Коли: брендовые цвета из гайдлайна
/// (синий #1D5BA6, жёлтый #F5E326), перекраска — на ревью Коли.
/// Источник сообщений — [OrdersRepository.watchOrderChat] (realtime),
/// отправка — [OrdersRepository.sendOrderChatMessage].
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';
import '../../../data/orders_repository.dart';
import '../../order_flow/domain/models.dart';

class OrderChatScreen extends StatefulWidget {
  const OrderChatScreen({
    super.key,
    required this.repository,
    required this.orderId,
  });

  final OrdersRepository repository;
  final String orderId;

  @override
  State<OrderChatScreen> createState() => _OrderChatScreenState();
}

class _OrderChatScreenState extends State<OrderChatScreen> {
  StreamSubscription<List<ChatMessage>>? _sub;
  List<ChatMessage>? _messages;
  AppFailure? _error;
  bool _sending = false;
  Uint8List? _pendingBytes;
  String? _pendingName;
  final _input = TextEditingController();

  @override
  void initState() {
    super.initState();
    _messages = null;
    _error = null;
    _listen();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _input.dispose();
    super.dispose();
  }

  void _listen() {
    _sub?.cancel();
    _sub = widget.repository.watchOrderChat(orderId: widget.orderId).listen(
      (list) {
        if (mounted) setState(() => _messages = list);
      },
      onError: (Object e) {
        if (mounted) {
          setState(() => _error = e is AppFailure ? e : Failures.unknown(e));
        }
      },
    );
  }

  /// «Повторить» из error-состояния: сброс и новая подписка.
  void _subscribe() {
    setState(() {
      _messages = null;
      _error = null;
    });
    _listen();
  }

  Future<void> _pick() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      // XFile.fromData/некоторые платформы не несут name — генерируем сами.
      final name = file.name.isEmpty
          ? 'photo-${DateTime.now().millisecondsSinceEpoch}.jpg'
          : file.name;
      if (mounted) {
        setState(() {
          _pendingBytes = bytes;
          _pendingName = name;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Не удалось открыть галерею на этом устройстве.')));
      }
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    final bytes = _pendingBytes;
    if ((text.isEmpty && bytes == null) || _sending) return;
    setState(() => _sending = true);
    try {
      String? url;
      if (bytes != null) {
        url = await widget.repository.uploadOrderPhoto(
          orderId: widget.orderId,
          bytes: bytes,
          fileName: _pendingName ?? 'photo.jpg',
        );
      }
      await widget.repository.sendOrderChatMessage(
        orderId: widget.orderId,
        text: text.isEmpty ? '📷 Фото с заказа' : text,
        attachmentUrl: url,
      );
      _input.clear();
      setState(() {
        _pendingBytes = null;
        _pendingName = null;
      });
    } on AppFailure catch (f) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(f.message)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Чат по заказу')),
        body: Column(
          children: [
            Expanded(child: _body()),
            _inputRow(),
          ],
        ),
      );

  Widget _body() {
    if (_error != null) {
      return StateView(
        key: const Key('chat_error'),
        icon: Icons.wifi_off,
        color: AppColors.error,
        body: Text(_error!.message),
        action: FilledButton(
          key: const Key('chat_retry'),
          onPressed: _subscribe,
          child: const Text('Повторить'),
        ),
      );
    }
    final messages = _messages;
    if (messages == null) {
      return const Center(
        child: CircularProgressIndicator(key: Key('chat_loading')),
      );
    }
    if (messages.isEmpty) {
      return const StateView(
        key: Key('chat_empty'),
        icon: Icons.forum_outlined,
        body: Text(
          'Сообщений пока нет.\nНапишите первым — бригада и диспетчер увидят.',
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView.builder(
      key: const Key('chat_list'),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      itemCount: messages.length,
      itemBuilder: (context, i) => _bubble(messages[i]),
    );
  }

  Widget _bubble(ChatMessage m) {
    final mine = m.isMine;
    const r = Radius.circular(18);
    const tail = Radius.circular(4);
    final textStyle = TextStyle(
      fontSize: 15,
      height: 1.35,
      color: mine ? Colors.white : AppColors.ink,
    );
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine) ...[
            InitialAvatar(name: m.authorName ?? 'Участник', size: 30),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.fromLTRB(14, 9, 14, 8),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              decoration: BoxDecoration(
                color: mine ? AppColors.brandBlue : AppColors.surface,
                borderRadius: BorderRadius.only(
                  topLeft: r,
                  topRight: r,
                  bottomLeft: mine ? r : tail,
                  bottomRight: mine ? tail : r,
                ),
                border: mine ? null : Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment:
                    mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!mine)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        m.authorName ?? 'Участник',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brandBlue,
                        ),
                      ),
                    ),
                  if (m.attachmentUrl != null) ...[
                    _attachment(m.attachmentUrl!, mine),
                    const SizedBox(height: 6),
                  ],
                  Text(m.text, style: textStyle),
                  const SizedBox(height: 2),
                  Text(
                    AppFormat.hhmm(m.sentAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: mine
                          ? Colors.white.withValues(alpha: 0.7)
                          : AppColors.faint,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Фото в пузыре: mock:// не грузим (заглушка), live — Image.network.
  Widget _attachment(String url, bool mine) {
    if (url.startsWith('mock://')) {
      return Container(
        key: const Key('chat_attachment'),
        width: 180,
        height: 110,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: mine
              ? Colors.white.withValues(alpha: 0.18)
              : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Icon(Icons.image_outlined,
            size: 40, color: mine ? Colors.white : AppColors.faint),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Image.network(
        url,
        key: const Key('chat_attachment'),
        width: 200,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined),
      ),
    );
  }

  Widget _inputRow() => DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 10, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_pendingBytes != null)
                  Container(
                    key: const Key('chat_attach_chip'),
                    margin: const EdgeInsets.only(left: 6, bottom: 8),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.brandBlueSoft,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(_pendingBytes!,
                              width: 40, height: 40, fit: BoxFit.cover),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(_pendingName ?? 'photo.jpg',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        IconButton(
                          key: const Key('chat_attach_remove'),
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() {
                            _pendingBytes = null;
                            _pendingName = null;
                          }),
                        ),
                      ],
                    ),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      key: const Key('chat_attach'),
                      tooltip: 'Прикрепить фото',
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      color: AppColors.muted,
                      onPressed: _sending ? null : _pick,
                    ),
                    Expanded(
                      child: TextField(
                        key: const Key('chat_input'),
                        controller: _input,
                        maxLength: 2000,
                        minLines: 1,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: 'Сообщение бригаде…',
                          isDense: true,
                          counterText: '',
                          fillColor: AppColors.background,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: const BorderSide(
                                color: AppColors.brandBlue, width: 1.5),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      key: const Key('chat_send'),
                      onPressed: _sending ? null : _send,
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.brandBlue,
                        fixedSize: const Size(46, 46),
                        shape: const CircleBorder(),
                      ),
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.arrow_upward_rounded,
                              color: Colors.white),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}
