import 'package:flutter/material.dart';
import '/models/durationstate.dart';

class MiniPlayerProgressBar extends StatelessWidget {
  const MiniPlayerProgressBar(
      {super.key,
      required this.progressBarStatus,
      required this.progressBarColor});
  final ProgressBarState progressBarStatus;
  final Color progressBarColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final progress = progressBarStatus.total.inSeconds == 0
            ? 0.0
            : progressBarStatus.current.inSeconds /
                progressBarStatus.total.inSeconds;

        return SizedBox(
          height: 3,
          child: CustomPaint(
            size: Size(width, 3),
            painter: _ProgressBarPainter(
              progress: progress,
              activeColor: progressBarColor,
            ),
          ),
        );
      },
    );
  }
}

class _ProgressBarPainter extends CustomPainter {
  _ProgressBarPainter({
    required this.progress,
    required this.activeColor,
  });

  final double progress;
  final Color activeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;

    final bgPaint = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      bgPaint,
    );

    if (progress > 0) {
      final activePaint = Paint()
        ..color = activeColor
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(0, centerY),
        Offset(size.width * progress, centerY),
        activePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
