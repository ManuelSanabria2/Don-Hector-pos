import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../pos_asistente_provider.dart';

void showAssistantDialog(BuildContext context) {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Asistente',
    barrierColor: Colors.black87,
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, anim1, anim2) {
      return const AssistantAuraDialog();
    },
    transitionBuilder: (context, anim1, anim2, child) {
      return FadeTransition(
        opacity: anim1,
        child: child,
      );
    },
  );
}

class AssistantAuraDialog extends ConsumerStatefulWidget {
  const AssistantAuraDialog({super.key});

  @override
  ConsumerState<AssistantAuraDialog> createState() => _AssistantAuraDialogState();
}

class _AssistantAuraDialogState extends ConsumerState<AssistantAuraDialog> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    // Iniciar con un saludo programado para el frame siguiente
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notifier = ref.read(posAsistenteProvider.notifier);
      notifier.resetState();
      notifier.speakText('Hola Don Héctor, ¿qué necesitas alistar?');
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(posAsistenteProvider);
    final notifier = ref.read(posAsistenteProvider.notifier);

    // Determine colors and animation speed based on state
    Color mainColor = AppColors.ambar;
    if (state.isListening) {
      mainColor = Colors.redAccent;
      _controller.duration = const Duration(seconds: 2);
    } else if (state.isProcessing) {
      mainColor = AppColors.ambar;
      _controller.duration = const Duration(seconds: 1);
    } else if (state.aiResponse.isNotEmpty) {
      mainColor = AppColors.verde;
      _controller.duration = const Duration(seconds: 3);
    } else {
      _controller.duration = const Duration(seconds: 4);
    }
    
    if (!_controller.isAnimating) {
      _controller.repeat();
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () {
                if (state.isListening) {
                  notifier.stopListening();
                } else {
                  notifier.startListening();
                }
              },
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return CustomPaint(
                    painter: _AuraPainter(
                      progress: _controller.value,
                      color: mainColor,
                      isListening: state.isListening,
                      soundLevel: state.soundLevel,
                    ),
                    child: SizedBox(
                      width: 250,
                      height: 250,
                      child: Center(
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: mainColor,
                            boxShadow: [
                              BoxShadow(
                                color: mainColor.withOpacity(0.5),
                                blurRadius: 20,
                                spreadRadius: 5,
                              )
                            ],
                          ),
                          child: Icon(
                            state.isListening ? Icons.mic : Icons.graphic_eq,
                            color: Colors.white,
                            size: 40,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 40),
            Text(
              state.isListening
                  ? 'Escuchando...'
                  : state.isProcessing
                      ? 'Procesando...'
                      : 'Toca para hablar',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            if (state.textSpoken.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16.0, left: 32, right: 32),
                child: Text(
                  '"${state.textSpoken}"',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.blancoD,
                    fontStyle: FontStyle.italic,
                    fontSize: 16,
                  ),
                ),
              ),
            if (state.aiResponse.isNotEmpty && !state.isListening && !state.isProcessing)
              Padding(
                padding: const EdgeInsets.only(top: 16.0, left: 32, right: 32),
                child: Text(
                  state.aiResponse,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.verde,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            if (state.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 16.0, left: 32, right: 32),
                child: Text(
                  state.errorMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 14,
                  ),
                ),
              ),
            const SizedBox(height: 40),
            IconButton(
              onPressed: () {
                notifier.stopListening();
                notifier.stopSpeaking();
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.close, color: Colors.white70, size: 32),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuraPainter extends CustomPainter {
  final double progress;
  final Color color;
  final bool isListening;
  final double soundLevel;

  _AuraPainter({
    required this.progress,
    required this.color,
    required this.isListening,
    required this.soundLevel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    // Draw pulsating rings
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    for (int i = 0; i < 3; i++) {
      final ringProgress = (progress + (i * 0.33)) % 1.0;
      final audioExpansion = isListening ? (math.max(0.0, soundLevel) * 2.5) : 0.0;
      final currentRadius = 40.0 + (maxRadius - 40.0 + audioExpansion) * ringProgress;
      final opacity = (1.0 - ringProgress).clamp(0.0, 1.0);

      ringPaint.color = color.withOpacity(opacity * 0.5);
      canvas.drawCircle(center, currentRadius, ringPaint);
    }

    // Draw little dots (partículas)
    final dotPaint = Paint()..style = PaintingStyle.fill;
    final int dotCount = isListening ? 20 : 12;

    for (int i = 0; i < dotCount; i++) {
      // Create offset for each dot based on time (progress)
      final angle = (i * (math.pi * 2) / dotCount) + (progress * math.pi * 2);
      
      // Some dots move outward, others orbit
      final isOrbiting = i % 2 == 0;
      final dotProgress = (progress + (i * 0.1)) % 1.0;
      
      final radiusDist = isOrbiting 
          ? 60.0 + (20.0 * math.sin(progress * math.pi * 2 + i))
          : 40.0 + (maxRadius - 40.0) * dotProgress;
      
      final dx = center.dx + math.cos(angle) * radiusDist;
      final dy = center.dy + math.sin(angle) * radiusDist;

      final dotOpacity = isOrbiting ? 0.6 : (1.0 - dotProgress).clamp(0.0, 1.0);
      dotPaint.color = color.withOpacity(dotOpacity);
      
      canvas.drawCircle(Offset(dx, dy), isOrbiting ? 3.0 : 2.0, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _AuraPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.isListening != isListening ||
        oldDelegate.soundLevel != soundLevel;
  }
}
