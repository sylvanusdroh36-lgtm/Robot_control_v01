// FILE: lib/widgets/joystick.dart (modifié)
import 'package:flutter/material.dart';

class Joystick extends StatefulWidget {
  final double size;
  final void Function(double dx, double dy) onChange;
  final VoidCallback? onRelease;

  const Joystick({
    super.key,
    this.size = 200,
    required this.onChange,
    this.onRelease,
  });

  @override
  State<Joystick> createState() => _JoystickState();
}

class _JoystickState extends State<Joystick> {
  Offset _thumb = Offset.zero;

  void _updateThumb(Offset globalPos) {
    final RenderBox box = context.findRenderObject() as RenderBox;
    final local = box.globalToLocal(globalPos);
    final center = Offset(widget.size / 2, widget.size / 2);
    var delta = local - center;
    final maxDist = widget.size / 2 - 20;
    
    if (delta.distance > maxDist) {
      delta = Offset.fromDirection(delta.direction, maxDist);
    }
    
    setState(() => _thumb = delta);

    final dx = (delta.dx / maxDist).clamp(-1.0, 1.0);
    final dy = (-delta.dy / maxDist).clamp(-1.0, 1.0);
    widget.onChange(dx, dy);
  }

  void _reset() {
    setState(() => _thumb = Offset.zero);
    widget.onRelease?.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanDown: (e) => _updateThumb(e.globalPosition),
      onPanUpdate: (e) => _updateThumb(e.globalPosition),
      onPanEnd: (_) => _reset(),
      onPanCancel: () => _reset(),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _JoystickPainter(thumbOffset: _thumb),
        ),
      ),
    );
  }
}

class _JoystickPainter extends CustomPainter {
  final Offset thumbOffset;
  
  _JoystickPainter({required this.thumbOffset});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width / 2;
    final paint = Paint()..style = PaintingStyle.fill;

    // Base circle
    paint.color = const Color(0xFF11141A);
    canvas.drawCircle(center, baseRadius, paint);

    // Inner ring
    paint.color = const Color(0xFF17212A);
    canvas.drawCircle(center, baseRadius * 0.7, paint);

    // Thumb pad
    final thumbCenter = center + thumbOffset;
    paint.color = const Color(0xFF2A5BFF).withAlpha(230); // 230 ≈ 0.9 * 255
    canvas.drawCircle(thumbCenter, size.width * 0.12, paint);

    // Border
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white.withAlpha(15)
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, baseRadius * 0.98, border);
  }

  @override
  bool shouldRepaint(covariant _JoystickPainter old) => old.thumbOffset != thumbOffset;
}