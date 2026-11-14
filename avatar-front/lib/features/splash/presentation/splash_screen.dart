/// БРЕНДОВЫЙ СПЛЭШ (зона релиза): грузчик в кепке с коробкой = иконка-фургон,
/// синий фон, жёлтый акцент, слоган. Показывается ТОЛЬКО в release-сборках
/// (в debug/тестах приложение стартует сразу в AuthGate).
library;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_widgets.dart';

class SplashGate extends StatefulWidget {
  const SplashGate(
      {super.key,
      required this.child,
      this.duration = const Duration(milliseconds: 1400)});

  final Widget child;
  final Duration duration;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate>
    with SingleTickerProviderStateMixin {
  bool _done = false;
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.duration, () {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    final fade = CurvedAnimation(parent: _intro, curve: Curves.easeOut);
    final scale = Tween<double>(begin: 0.8, end: 1)
        .animate(CurvedAnimation(parent: _intro, curve: Curves.easeOutBack));
    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _done = true),
        child: BrandSurface(
          child: SizedBox.expand(
            child: FadeTransition(
              opacity: fade,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ScaleTransition(
                    scale: scale,
                    child: const BrandMark(size: 116, onDark: true),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'АВАТАР',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 6,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.brandYellow,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Используем силу с умом',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 15,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
