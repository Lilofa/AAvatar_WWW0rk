/// БРЕНДОВЫЙ СПЛЭШ (зона релиза): грузчик в кепке с коробкой = иконка-фургон,
/// синий фон, жёлтый акцент, слоган. Показывается ТОЛЬКО в release-сборках
/// (в debug/тестах приложение стартует сразу в AuthGate).
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.child, this.duration = const Duration(milliseconds: 1400)});

  final Widget child;
  final Duration duration;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool _done = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.duration, () {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    return Scaffold(
      backgroundColor: AppColors.brandBlue,
      body: GestureDetector(
        onTap: () => setState(() => _done = true),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 108,
                height: 108,
                decoration: BoxDecoration(
                  color: AppColors.brandBlue,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: AppColors.brandYellow, width: 3),
                ),
                child: const Icon(Icons.local_shipping,
                    size: 56, color: AppColors.brandYellow),
              ),
              const SizedBox(height: 20),
              const Text(
                'АВАТАР',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Используем силу с умом',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
