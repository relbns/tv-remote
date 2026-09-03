import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// The navigation ring.
///
/// One continuous surface rather than four keys: the shape invites a swipe as
/// readily as a tap, which is far more forgiving on a touch screen than aiming
/// at a small arrow. Both gestures produce the same commands.
class DPad extends StatelessWidget {
  const DPad({super.key, required this.onCommand, this.enabled = true});

  final void Function(String command) onCommand;
  final bool enabled;

  void _fire(String command) {
    if (!enabled) return;
    HapticFeedback.lightImpact();
    onCommand(command);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context).width.clamp(0.0, 420.0) * 0.72;

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: SizedBox(
        width: size,
        height: size,
        child: GestureDetector(
          // A flick anywhere on the ring navigates, so precise aim is optional.
          onHorizontalDragEnd: (details) {
            final v = details.velocity.pixelsPerSecond.dx;
            if (v.abs() < 200) return;
            // Physical direction, not reading direction: a flick right moves right.
            _fire(v > 0 ? 'right' : 'left');
          },
          onVerticalDragEnd: (details) {
            final v = details.velocity.pixelsPerSecond.dy;
            if (v.abs() < 200) return;
            _fire(v > 0 ? 'down' : 'up');
          },
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                center: Alignment(0, -0.55),
                radius: 0.9,
                colors: [Color(0xFF232A36), Color(0xFF141922)],
              ),
              boxShadow: raisedShadow,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // A hairline groove implies the swipe surface without drawing keys.
                Padding(
                  padding: EdgeInsets.all(size * 0.15),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                    ),
                  ),
                ),
                _Arrow(
                  Alignment.topCenter,
                  Icons.keyboard_arrow_up_rounded,
                  'למעלה',
                  () => _fire('up'),
                ),
                _Arrow(
                  Alignment.bottomCenter,
                  Icons.keyboard_arrow_down_rounded,
                  'למטה',
                  () => _fire('down'),
                ),
                _Arrow(
                  Alignment.centerLeft,
                  Icons.keyboard_arrow_left_rounded,
                  'שמאלה',
                  () => _fire('left'),
                ),
                _Arrow(
                  Alignment.centerRight,
                  Icons.keyboard_arrow_right_rounded,
                  'ימינה',
                  () => _fire('right'),
                ),
                _Ok(size: size * 0.38, onTap: () => _fire('ok')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow(this.alignment, this.icon, this.label, this.onTap);

  final Alignment alignment;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Align(
    alignment: alignment,
    child: Semantics(
      button: true,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 34,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Icon(icon, size: 30, color: Palette.inkMid),
        ),
      ),
    ),
  );
}

class _Ok extends StatefulWidget {
  const _Ok({required this.size, required this.onTap});
  final double size;
  final VoidCallback onTap;

  @override
  State<_Ok> createState() => _OkState();
}

class _OkState extends State<_Ok> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) => setState(() => _down = true),
    onTapUp: (_) => setState(() => _down = false),
    onTapCancel: () => setState(() => _down = false),
    onTap: widget.onTap,
    child: AnimatedScale(
      scale: _down ? 0.94 : 1,
      duration: const Duration(milliseconds: 110),
      child: Container(
        width: widget.size,
        height: widget.size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF2BC5C), Palette.amber, Palette.amberDeep],
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x47E9A93F),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: const Text(
          'OK',
          style: TextStyle(
            color: Color(0xFF2A1D08),
            fontWeight: FontWeight.w600,
            fontSize: 16,
            letterSpacing: 1,
          ),
        ),
      ),
    ),
  );
}
