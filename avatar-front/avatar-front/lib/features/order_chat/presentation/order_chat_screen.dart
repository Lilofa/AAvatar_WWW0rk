/// ЭКРАН ЧАТА ПО ЗАКАЗУ (зона Артёма).
///
/// Четыре состояния: loading / data / empty / error (+ «Повторить»).
/// Дизайн минимальный, без виджетов Коли: брендовые цвета из гайдлайна
/// (синий #1D5BA6, жёлтый #F5E326), перекраска — на ревью Коли.
/// Источник сообщений — [OrdersRepository.watchOrderChat] (realtime),
/// отправка — [OrdersRepository.sendOrderChatMessage].
library;

import 'dart:async';

import 'package:flutter/material.dart';

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

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.repository
          .sendOrderChatMessage(orderId: widget.orderId, text: text);
      _input.clear();
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

  Widget _inputRow() => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
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
        ),
      );
}
