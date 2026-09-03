import 'package:flutter/material.dart';

import '../data/controller.dart';
import 'about_sheet.dart';
import 'transfer_page.dart';
import 'theme.dart';
import 'widgets/controls.dart';

const tabNames = ['שלט', 'אפליקציות', 'מכשירים'];

Future<void> showSettingsSheet(
  BuildContext context,
  RemoteController controller,
) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: Palette.surface,
  showDragHandle: true,
  useSafeArea: true,
  isScrollControlled: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.lg)),
  ),
  builder: (_) => _SettingsSheet(controller: controller),
);

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.controller});
  final RemoteController controller;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  @override
  Widget build(BuildContext context) {
    final selected = widget.controller.defaultTab;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 14,
          children: [
            const Center(
              child: Text(
                'הגדרות',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'מסך פתיחה',
              textAlign: TextAlign.start,
              style: TextStyle(fontSize: 12, color: Palette.inkDim),
            ),
            const Text(
              // No trailing period: at the end of a right-to-left line it lands
              // on the far left and reads as if it opened the sentence.
              'הלשונית שהאפליקציה נפתחת בה',
              textAlign: TextAlign.start,
              style: TextStyle(
                fontSize: 12,
                color: Palette.inkDim,
                height: 1.5,
              ),
            ),
            for (var i = 0; i < tabNames.length; i++)
              Raised(
                radius: Radii.md,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                onTap: () async {
                  await widget.controller.setDefaultTab(i);
                  if (mounted) setState(() {});
                },
                child: Row(
                  children: [
                    Expanded(child: Text(tabNames[i])),
                    if (i == selected)
                      const Icon(
                        Icons.check_rounded,
                        size: 19,
                        color: Palette.amber,
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Pill(
              label: 'העברה למכשיר אחר',
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => TransferPage(controller: widget.controller),
                  ),
                );
              },
            ),
            Pill(
              label: 'אודות',
              onTap: () {
                Navigator.pop(context);
                showAboutSheet(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}
