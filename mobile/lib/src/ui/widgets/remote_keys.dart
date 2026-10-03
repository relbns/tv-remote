import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'controls.dart';

/// A flat key in a grid: media, typing, mute.
///
/// Flat rather than raised so a cluster of them reads as one block next to
/// the raised navigation keys, the way the media pad on a physical remote is a
/// different texture from its arrows.
class PadKey extends StatelessWidget {
  const PadKey({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final bool accent;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Semantics(
      button: true,
      label: label,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: Material(
          color: accent
              ? Palette.amberWash
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: enabled
                ? () {
                    HapticFeedback.lightImpact();
                    onTap();
                  }
                : null,
            child: Center(
              child: Icon(
                icon,
                size: 24,
                color: accent ? Palette.amber : Palette.inkMid,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// An upright rocker: up on top, down below, like volume and channel on a
/// physical remote. Holding either end repeats.
class TallRocker extends StatelessWidget {
  const TallRocker({
    super.key,
    required this.label,
    required this.upIcon,
    required this.upLabel,
    required this.onUp,
    required this.downIcon,
    required this.downLabel,
    required this.onDown,
    this.value,
    this.enabled = true,
  });

  final String label;
  final IconData upIcon;
  final String upLabel;
  final VoidCallback onUp;
  final IconData downIcon;
  final String downLabel;
  final VoidCallback onDown;

  /// What the device reports, shown above the label.
  final String? value;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: enabled ? 1 : 0.4,
    child: Container(
      width: 68,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(34),
      ),
      child: Column(
        children: [
          Expanded(child: _Step(upIcon, upLabel, enabled ? onUp : null)),
          if (value != null)
            Text(
              value!,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          Text(
            label,
            style: const TextStyle(fontSize: 10.5, color: Palette.inkDim),
          ),
          Expanded(child: _Step(downIcon, downLabel, enabled ? onDown : null)),
        ],
      ),
    ),
  );
}

class _Step extends StatelessWidget {
  const _Step(this.icon, this.label, this.onTap);

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: RepeatDetector(
      enabled: onTap != null,
      onFire: () {
        HapticFeedback.selectionClick();
        onTap?.call();
      },
      child: InkResponse(
        radius: 30,
        onTap: onTap == null ? null : () {},
        child: Center(child: Icon(icon, size: 22, color: Palette.ink)),
      ),
    ),
  );
}

/// A round key with its name under it, for the corners around the ring.
class CornerKey extends StatelessWidget {
  const CornerKey({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 64,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 5,
      children: [
        Semantics(
          button: true,
          label: label,
          child: Raised(
            radius: 26,
            enabled: enabled,
            onTap: onTap,
            child: SizedBox(
              width: 52,
              height: 52,
              child: Icon(icon, size: 21, color: Palette.ink),
            ),
          ),
        ),
        ExcludeSemantics(
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: Palette.inkDim),
          ),
        ),
      ],
    ),
  );
}

/// A raised key with an icon and a word, for a row of equal keys.
class LabeledKey extends StatelessWidget {
  const LabeledKey({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Raised(
      radius: 18,
      enabled: enabled,
      onTap: onTap,
      child: SizedBox(
        height: 52,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 8,
          children: [
            Icon(icon, size: 18, color: Palette.ink),
            Text(label, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    ),
  );
}

/// One key of the number pad.
class DigitKey extends StatelessWidget {
  const DigitKey({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.enabled = true,
  });

  /// The digit, or the accessibility name when [icon] is shown instead.
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Semantics(
      button: true,
      label: label,
      child: Raised(
        radius: 20,
        enabled: enabled,
        onTap: onTap,
        child: SizedBox(
          height: 64,
          child: Center(
            child: icon == null
                ? Text(
                    label,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                    ),
                  )
                : Icon(icon, size: 22, color: Palette.inkMid),
          ),
        ),
      ),
    ),
  );
}

/// An app tile: a strip of the brand colour over the name.
class AppTile extends StatelessWidget {
  const AppTile({
    super.key,
    required this.label,
    required this.onTap,
    this.color,
    this.icon,
    this.enabled = true,
  });

  final String label;
  final Color? color;
  final IconData? icon;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            height: 56,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 6,
              children: [
                if (icon != null)
                  Icon(icon, size: 18, color: Palette.inkMid)
                else
                  Container(
                    width: 18,
                    height: 4,
                    decoration: BoxDecoration(
                      color: color ?? Palette.inkDim,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
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

/// A large surface to swipe on instead of aiming at arrows.
///
/// Every stretch of travel is one press, so a long drag walks a long menu the
/// way holding an arrow does. A tap is OK and a long press goes back.
class TouchSurface extends StatefulWidget {
  const TouchSurface({
    super.key,
    required this.onCommand,
    this.enabled = true,
    this.caption,
  });

  final void Function(String command) onCommand;
  final bool enabled;

  /// A short line in the corner, such as what is playing.
  final String? caption;

  @override
  State<TouchSurface> createState() => _TouchSurfaceState();
}

class _TouchSurfaceState extends State<TouchSurface> {
  /// Travel, in logical pixels, that counts as one press.
  static const _step = 36.0;

  Offset _travel = Offset.zero;
  Offset? _touch;

  void _fire(String command) {
    if (!widget.enabled) return;
    HapticFeedback.selectionClick();
    widget.onCommand(command);
  }

  void _onUpdate(DragUpdateDetails details) {
    var travel = _travel + details.delta;
    while (travel.dx.abs() >= _step || travel.dy.abs() >= _step) {
      if (travel.dx.abs() >= travel.dy.abs()) {
        // Physical direction, not reading direction: a drag right moves right.
        final right = travel.dx > 0;
        _fire(right ? 'right' : 'left');
        travel = Offset(travel.dx - (right ? _step : -_step), 0);
      } else {
        final down = travel.dy > 0;
        _fire(down ? 'down' : 'up');
        travel = Offset(0, travel.dy - (down ? _step : -_step));
      }
    }
    setState(() {
      _travel = travel;
      _touch = details.localPosition;
    });
  }

  void _release() => setState(() {
    _travel = Offset.zero;
    _touch = null;
  });

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'משטח מגע: החלקה לניווט, הקשה לאישור, לחיצה ארוכה לחזרה',
    child: Opacity(
      opacity: widget.enabled ? 1 : 0.45,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _fire('ok'),
        onLongPress: () => _fire('back'),
        onPanStart: (details) => setState(() {
          _travel = Offset.zero;
          _touch = details.localPosition;
        }),
        onPanUpdate: _onUpdate,
        onPanEnd: (_) => _release(),
        onPanCancel: _release,
        child: Container(
          height: 320,
          decoration: BoxDecoration(
            color: const Color(0xFF121620),
            borderRadius: BorderRadius.circular(32),
            boxShadow: raisedShadow,
          ),
          child: Stack(
            children: [
              if (widget.caption case final caption?)
                PositionedDirectional(
                  top: 16,
                  start: 18,
                  child: Text(
                    caption,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Palette.inkDim,
                    ),
                  ),
                ),
              if (_touch case final point?)
                Positioned(
                  left: point.dx - 32,
                  top: point.dy - 32,
                  child: IgnorePointer(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Palette.amberWash,
                        border: Border.all(
                          color: Palette.amber.withValues(alpha: 0.55),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              const Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.only(bottom: 18),
                  child: Text(
                    'החלקה · ניווט     הקשה · OK     לחיצה ארוכה · חזור',
                    style: TextStyle(fontSize: 11.5, color: Palette.inkDim),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The segmented switch at the top of the modes layout.
class ModeSwitch extends StatelessWidget {
  const ModeSwitch({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String value;

  /// Each option's id and name, in order.
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      spacing: 4,
      children: [
        for (final (id, label) in options)
          Expanded(
            child: Semantics(
              button: true,
              selected: id == value,
              child: Material(
                color: id == value ? Palette.surfaceHigh : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onChanged(id);
                  },
                  child: SizedBox(
                    height: 44,
                    child: Center(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: id == value ? Palette.amber : Palette.inkMid,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
