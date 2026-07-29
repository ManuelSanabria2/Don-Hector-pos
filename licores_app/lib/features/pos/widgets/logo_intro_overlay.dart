import 'package:flutter/material.dart';

class LogoIntroOverlay extends StatefulWidget {
  const LogoIntroOverlay({required this.onFinished, super.key});

  final VoidCallback onFinished;

  @override
  State<LogoIntroOverlay> createState() => _LogoIntroOverlayState();
}

class _LogoIntroOverlayState extends State<LogoIntroOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _opacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0).chain(
          CurveTween(curve: Curves.easeIn),
        ),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0).chain(
          CurveTween(curve: Curves.easeOut),
        ),
        weight: 35,
      ),
    ]).animate(_controller);

    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.85, end: 1.05).chain(
          CurveTween(curve: Curves.easeOutCubic),
        ),
        weight: 65,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.05, end: 1.15).chain(
          CurveTween(curve: Curves.easeInCubic),
        ),
        weight: 35,
      ),
    ]).animate(_controller);

    _controller.forward().then((_) {
      widget.onFinished();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: const Color(0xFF0A0A08),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Center(
              child: Opacity(
                opacity: _opacity.value,
                child: Transform.scale(
                  scale: _scale.value,
                  child: child,
                ),
              ),
            );
          },
          child: Hero(
            tag: 'turbo_logo',
            child: Image.asset(
              'assets/images/logov1_removebg.png',
              width: 250,
              height: 250,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                // Fallback in case of missing asset
                return const Icon(
                  Icons.bolt,
                  color: Color(0xFF64B5F6),
                  size: 150,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
