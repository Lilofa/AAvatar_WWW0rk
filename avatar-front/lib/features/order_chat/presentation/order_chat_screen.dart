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

  static const Color brandBlue = Color(0xFF1D5BA6);
  static const Color brandYellow = Color(0xFFF5E326);

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
    _sub = widget.repository
        .watchOrderChat(orderId: widget.orderId)
        .listen(
          (list) {
            if (mounted) setState(() => _messages = list);
          },
          onError: (Object e) {
            if (mounted) {
              setState(() =>
                  _error = e is AppFailure ? e : Failures.unknown(e));
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
        appBar: AppBar(
          title: const Text('Чат по заказу'),
          backgroundColor: OrderChatScreen.brandBlue,
          foregroundColor: Colors.white,
        ),
        body: Column(
          children: [
            Expanded(child: _body()),
            _inputRow(),
          ],
        ),
      );

  Widget _body() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            key: const Key('chat_error'),
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(_error!.message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('chat_retry'),
                onPressed: _subscribe,
                child: const Text('Повторить'),
              ),
            ],
          ),
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
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            key: Key('chat_empty'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 48, color: Colors.grey),
              SizedBox(height: 12),
              Text(
                'Сообщений пока нет.\nНапишите первым — бригада и диспетчер увидят.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      key: const Key('chat_list'),
      padding: const EdgeInsets.all(12),
      itemCount: messages.length,
      itemBuilder: (context, i) => _bubble(messages[i]),
    );
  }

  Widget _bubble(ChatMessage m) {
    final mine = m.isMine;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: mine
              ? OrderChatScreen.brandBlue
              : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!mine)
              Text(
                m.authorName ?? 'Участник',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: mine ? Colors.white70 : OrderChatScreen.brandBlue,
                ),
              ),
            if (m.attachmentUrl != null)
              _attachment(m.attachmentUrl!, mine)
            else
              Text(
                m.text,
                style: TextStyle(color: mine ? Colors.white : Colors.black87),
              ),
            if (m.attachmentUrl != null)
              Text(
                m.text,
                style: TextStyle(color: mine ? Colors.white : Colors.black87),
              ),
            Text(
              '${m.sentAt.hour.toString().padLeft(2, '0')}:${m.sentAt.minute.toString().padLeft(2, '0')}',
              style: TextStyle(fontSize: 10, color: mine ? Colors.white60 : Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  /// Фото в пузыре: mock:// не грузим (заглушка), live — Image.network.
  Widget _attachment(String url, bool mine) {
    if (url.startsWith('mock://')) {
      return Container(
        key: const Key('chat_attachment'),
        width: 160,
        height: 100,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: mine ? Colors.white24 : Colors.grey.shade300,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.image, size: 40),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        key: const Key('chat_attachment'),
        width: 180,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined),
      ),
    );
  }

  Widget _inputRow() => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_pendingBytes != null)
                Container(
                  key: const Key('chat_attach_chip'),
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.memory(_pendingBytes!,
                          width: 36, height: 36, fit: BoxFit.cover),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_pendingName ?? 'photo.jpg',
                            maxLines: 1, overflow: TextOverflow.ellipsis),
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
            children: [
              IconButton(
                key: const Key('chat_attach'),
                tooltip: 'Прикрепить фото',
                icon: const Icon(Icons.attach_file),
                onPressed: _sending ? null : _pick,
              ),
              Expanded(
                child: TextField(
                  key: const Key('chat_input'),
                  controller: _input,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    hintText: 'Сообщение бригаде…',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                key: const Key('chat_send'),
                onPressed: _sending ? null : _send,
                style: IconButton.styleFrom(
                  backgroundColor: OrderChatScreen.brandBlue,
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
                    : const Icon(Icons.send, color: Colors.white),
              ),
            ],
              ),
            ],
          ),
        ),
      );
}
