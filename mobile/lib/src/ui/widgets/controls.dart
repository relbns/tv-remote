import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// A raised surface: the shared look for every control that is meant to be
/// pressed. Elevation and radius do the separating, so nothing needs a border.
class Raised extends StatelessWidget {
  const Raised({
    super.key,
    required this.child,
    this.onTap,
    this.radius = Radii.md,
    this.padding = EdgeInsets.zero,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final EdgeInsets padding;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: enabled ? 1 : 0.4,
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: raisedGradient,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: raisedShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: enabled && onTap != null
              ? () {
                  HapticFeedback.lightImpact();
                  onTap!();
                }
              : null,
          child: Padding(padding: padding, child: child),
        ),
      ),
    ),
  );
}

/// A minus / label / plus control shaped like the rockers on a physical remote.
///
/// Laid out left-to-right even in this right-to-left interface: plus and minus
/// map to a physical direction, not to reading order.
class Rocker extends StatelessWidget {
  const Rocker({
    super.key,
    required this.label,
    required this.onDown,
    required this.onUp,
    this.value,
    this.enabled = true,
  });

  final String label;

  /// Shown under the label when the device reports a reading.
  final String? value;
  final VoidCallback onDown;
  final VoidCallback onUp;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Raised(
      radius: 28,
      enabled: enabled,
      child: SizedBox(
        height: 56,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: [
              _Step('−', enabled ? onDown : null, 'הפחת $label'),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      // The two step buttons take most of the width; without
                      // this the label wraps and the rocker grows.
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: Palette.inkDim,
                      ),
                    ),
                    if (value != null)
                      Text(
                        value!,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.visible,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.2,
                          fontFeatures: [FontFeature.tabularFigures()],
                          color: Palette.ink,
                        ),
                      ),
                  ],
                ),
              ),
              _Step('+', enabled ? onUp : null, 'הגבר $label'),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Step extends StatelessWidget {
  const _Step(this.glyph, this.onTap, this.semantics);
  final String glyph;
  final VoidCallback? onTap;
  final String semantics;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semantics,
    child: RepeatDetector(
      enabled: onTap != null,
      onFire: () {
        HapticFeedback.selectionClick();
        onTap?.call();
      },
      child: InkResponse(
        radius: 28,
        onTap: onTap == null ? null : () {},
        child: SizedBox(
          width: 42,
          height: 56,
          child: Center(
            child: Text(
              glyph,
              style: const TextStyle(fontSize: 22, color: Palette.inkMid),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A short label chip, used for the quick keys and the app shelf.
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Raised(
    enabled: enabled,
    onTap: onTap,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: Text(
      label,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 13, color: Palette.ink),
    ),
  );
}

/// Connection indicator: green live, red unreachable, amber mid-handshake.
class Lamp extends StatelessWidget {
  const Lamp({super.key, required this.color, this.tooltip});
  final Color color;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8),
        ],
      ),
    );
    return tooltip == null ? dot : Tooltip(message: tooltip!, child: dot);
  }
}

/// A round icon key.
///
/// An icon is read faster than a word and needs no translation, which matters
/// on a control that is glanced at in the dark. The label survives as the
/// accessibility name and the tooltip.
class IconKey extends StatelessWidget {
  const IconKey({
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
      child: Tooltip(
        message: label,
        child: Raised(
          enabled: enabled,
          onTap: onTap,
          radius: Radii.md,
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Icon(
            icon,
            size: 22,
            color: accent ? Palette.amber : Palette.inkMid,
          ),
        ),
      ),
    ),
  );
}

/// Fires once on tap, then repeats while held.
///
/// Stepping through twenty volume levels or a long menu one press at a time is
/// what makes a phone feel worse than the plastic remote it replaces. The first
/// repeat waits, so a normal tap is never mistaken for a hold.
class RepeatDetector extends StatefulWidget {
  const RepeatDetector({
    super.key,
    required this.onFire,
    required this.child,
    this.enabled = true,
    this.delay = const Duration(milliseconds: 450),
    this.interval = const Duration(milliseconds: 110),
  });

  final VoidCallback onFire;
  final Widget child;
  final bool enabled;

  /// How long to hold before repeating begins.
  final Duration delay;

  /// Gap between repeats once they start.
  final Duration interval;

  @override
  State<RepeatDetector> createState() => _RepeatDetectorState();
}

class _RepeatDetectorState extends State<RepeatDetector> {
  Timer? _delayTimer;
  Timer? _repeatTimer;

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _start() {
    if (!widget.enabled) return;
    widget.onFire();
    _delayTimer = Timer(widget.delay, () {
      _repeatTimer = Timer.periodic(widget.interval, (_) => widget.onFire());
    });
  }

  void _stop() {
    _delayTimer?.cancel();
    _repeatTimer?.cancel();
    _delayTimer = null;
    _repeatTimer = null;
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _start(),
    onPointerUp: (_) => _stop(),
    onPointerCancel: (_) => _stop(),
    child: widget.child,
  );
}
