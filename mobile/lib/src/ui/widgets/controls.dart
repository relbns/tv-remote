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
    this.enabled = true,
  });

  final String label;
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
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: Palette.inkDim),
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
    child: InkResponse(
      radius: 28,
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
      child: SizedBox(
        width: 52,
        height: 56,
        child: Center(
          child: Text(
            glyph,
            style: const TextStyle(fontSize: 22, color: Palette.inkMid),
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
