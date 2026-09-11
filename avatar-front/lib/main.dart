import 'package:avatar_app/data/mock_orders_repository.dart';
import 'package:avatar_app/features/order_feed/presentation/order_feed_screen.dart';
import 'package:flutter/material.dart';

void main() => runApp(
      MaterialApp(
        home: OrderFeedScreen(
          repository: MockOrdersRepository(),
          showMockSwitch: true,
        ),
      ),
    );