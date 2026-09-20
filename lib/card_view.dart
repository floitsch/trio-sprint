import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'game.dart';

const ink = Color(0xFF202B38);
const paper = Color(0xFFF5F3ED);
const accent = Color(0xFFDB572E);

class CardView extends StatelessWidget {
  const CardView({
    super.key,
    required this.card,
    this.selected = false,
    this.onTap,
  });

  final SetCard card;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Align(
    child: AspectRatio(
      aspectRatio: 2 / 3,
      child: Semantics(
        label: card.description,
        button: onTap != null,
        selected: selected,
        onTap: onTap,
        child: _ForgivingTap(
          onTap: onTap,
          child: Material(
            color: selected ? const Color(0xFFFFEADF) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: selected ? accent : const Color(0xFFE0DED7),
                width: selected ? 3 : 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: CustomPaint(painter: SymbolsPainter(card)),
                ),
                if (selected)
                  const Positioned(
                    top: 5,
                    right: 5,
                    child: Icon(Icons.check_circle, size: 18, color: accent),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _ForgivingTap extends StatefulWidget {
  const _ForgivingTap({required this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  State<_ForgivingTap> createState() => _ForgivingTapState();
}

class _ForgivingTapState extends State<_ForgivingTap> {
  static const maxTapTravel = 40.0;
  final Map<int, _PointerTrack> pointers = {};

  void pointerDown(PointerDownEvent event) {
    if (widget.onTap == null || event.buttons & kPrimaryButton == 0) return;
    setState(
      () => pointers[event.pointer] = _PointerTrack(event.localPosition),
    );
  }

  void pointerMove(PointerMoveEvent event) {
    final pointer = pointers[event.pointer];
    if (pointer == null) return;
    pointer.furthestDistance = math.max(
      pointer.furthestDistance,
      (event.localPosition - pointer.start).distance,
    );
  }

  void pointerUp(PointerUpEvent event) {
    final pointer = pointers.remove(event.pointer);
    if (pointer == null) return;
    setState(() {});
    if (pointer.furthestDistance <= maxTapTravel) widget.onTap?.call();
  }

  void pointerCancel(PointerCancelEvent event) {
    if (pointers.remove(event.pointer) != null) setState(() {});
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
    child: Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: pointerDown,
      onPointerMove: pointerMove,
      onPointerUp: pointerUp,
      onPointerCancel: pointerCancel,
      child: AnimatedScale(
        scale: pointers.isEmpty ? 1 : .985,
        duration: const Duration(milliseconds: 70),
        child: widget.child,
      ),
    ),
  );
}

class _PointerTrack {
  _PointerTrack(this.start);

  final Offset start;
  double furthestDistance = 0;
}

class SymbolsPainter extends CustomPainter {
  SymbolsPainter(this.card);
  final SetCard card;
  static const colors = [
    Color(0xFFE21D2F),
    Color(0xFF009A44),
    Color(0xFF6F2C91),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // Draw in a landscape coordinate system, then rotate the whole layout:
    // horizontal symbols stacked down the portrait card.
    canvas.save();
    canvas.translate(size.width, 0);
    canvas.rotate(math.pi / 2);
    size = Size(size.height, size.width);
    final width = (size.width / 4.5).clamp(0.0, 25.0);
    final height = (size.height * .78).clamp(0.0, 55.0);
    final gap = width * .38;
    final total = card.count * width + (card.count - 1) * gap;
    final color = colors[card.color];
    for (var i = 0; i < card.count; i++) {
      final rect = Rect.fromLTWH(
        (size.width - total) / 2 + i * (width + gap),
        (size.height - height) / 2,
        width,
        height,
      );
      final path = _shape(rect);
      if (card.fill == 0) {
        canvas.drawPath(path, Paint()..color = color);
      } else if (card.fill == 1) {
        canvas.save();
        canvas.clipPath(path);
        for (double y = rect.top; y <= rect.bottom; y += 4) {
          canvas.drawLine(
            Offset(rect.left, y),
            Offset(rect.right, y),
            Paint()
              ..color = color
              ..strokeWidth = 1.3,
          );
        }
        canvas.restore();
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    canvas.restore();
  }

  Path _shape(Rect r) {
    switch (card.shape) {
      case 0:
        return Path()
          ..addRRect(RRect.fromRectAndRadius(r, Radius.circular(r.width / 2)));
      case 1:
        return Path()
          ..moveTo(r.center.dx, r.top)
          ..lineTo(r.right, r.center.dy)
          ..lineTo(r.center.dx, r.bottom)
          ..lineTo(r.left, r.center.dy)
          ..close();
      default:
        final x = r.left;
        final y = r.top;
        final w = r.width;
        final h = r.height;
        return Path()
          ..moveTo(x + w * .15, y + h * .04)
          ..cubicTo(
            x + w * .9,
            y - h * .18,
            x + w * 1.2,
            y + h * .3,
            x + w * .8,
            y + h * .5,
          )
          ..cubicTo(
            x + w * .45,
            y + h * .7,
            x + w * 1.25,
            y + h * .87,
            x + w * .85,
            y + h * .96,
          )
          ..cubicTo(
            x + w * .1,
            y + h * 1.18,
            x - w * .2,
            y + h * .7,
            x + w * .2,
            y + h * .5,
          )
          ..cubicTo(
            x + w * .55,
            y + h * .3,
            x - w * .25,
            y + h * .13,
            x + w * .15,
            y + h * .04,
          )
          ..close();
    }
  }

  @override
  bool shouldRepaint(SymbolsPainter oldDelegate) =>
      oldDelegate.card.id != card.id;
}
