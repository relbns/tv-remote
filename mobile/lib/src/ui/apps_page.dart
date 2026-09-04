import 'package:flutter/material.dart';

import '../data/controller.dart';
import 'theme.dart';
import 'widgets/controls.dart';

class AppsPage extends StatelessWidget {
  const AppsPage({super.key, required this.controller});
  final RemoteController controller;

  @override
  Widget build(BuildContext context) {
    final shortcuts = controller.shortcuts();

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      children: [
        Raised(
          radius: Radii.lg,
          padding: const EdgeInsets.all(16),
          child: const Text(
            'הרשימה נבנית ממה שבאמת רץ על הממיר. הפרוטוקול אינו יודע למנות '
            'אפליקציות מותקנות, אבל הוא מדווח מה פועל בכל רגע — אז כל אפליקציה '
            'שתפתח נוספת לכאן מעצמה.',
            style: TextStyle(
              fontSize: 12.5,
              color: Palette.inkMid,
              height: 1.65,
            ),
          ),
        ),
        if (controller.catalogSuggestions().isNotEmpty) ...[
          const SizedBox(height: 20),
          const _Label('הוסף מהקטלוג'),
          for (final app in controller.catalogSuggestions()) ...[
            Raised(
              radius: Radii.md,
              onTap: () => controller.addShortcut(app),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                spacing: 12,
                children: [
                  _Tile(label: app.label, color: app.color),
                  Expanded(
                    child: Text(
                      app.label,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  const Text(
                    'הוסף',
                    style: TextStyle(color: Palette.amber, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
        const SizedBox(height: 20),
        const _Label('קיצורים שמורים'),
        for (final entry in shortcuts) ...[
          Raised(
            radius: Radii.md,
            onTap: controller.isConnected
                ? () => controller.launch(entry.launch)
                : null,
            enabled: controller.isConnected,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              spacing: 12,
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.label,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      Text(
                        entry.launch,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Palette.inkDim,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => controller.removeShortcut(entry),
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: Palette.inkDim,
                  ),
                  tooltip: 'הסר',
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 4, bottom: 10),
    child: Text(
      text,
      style: const TextStyle(fontSize: 12, color: Palette.inkDim),
    ),
  );
}

/// A brand-coloured tile carrying the app's initial.
///
/// The logos themselves are trademarks and are not bundled; a tile in the
/// brand's colour is recognisable without redistributing anyone's mark.
class _Tile extends StatelessWidget {
  const _Tile({required this.label, this.color});
  final String label;
  final String? color;

  @override
  Widget build(BuildContext context) {
    final value = color == null
        ? Palette.surfaceHigh
        : Color(int.parse(color!.replaceFirst('#', 'ff'), radix: 16));
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: value,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label.characters.first.toUpperCase(),
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 16,
          color: color == null ? Palette.inkMid : const Color(0xFF0B0E14),
        ),
      ),
    );
  }
}
