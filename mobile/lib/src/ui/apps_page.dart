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
            'הממיר לא יכול לדווח אילו אפליקציות מותקנות עליו — לפרוטוקול של '
            'Android TV אין בקשה כזו. במקום זה הוא לומד: פתח אפליקציה עם השלט '
            'הרגיל והיא תופיע כאן לשמירה.',
            style: TextStyle(
              fontSize: 12.5,
              color: Palette.inkMid,
              height: 1.65,
            ),
          ),
        ),
        if (controller.learned.isNotEmpty) ...[
          const SizedBox(height: 20),
          const _Label('זוהו בממיר'),
          for (final package in controller.learned) ...[
            Raised(
              radius: Radii.md,
              onTap: () => controller.saveLearned(package),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                spacing: 12,
                children: [
                  const Lamp(color: Palette.amber),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          controller.labelFor(package),
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        Text(
                          package,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Palette.inkDim,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Text(
                    'שמור',
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
