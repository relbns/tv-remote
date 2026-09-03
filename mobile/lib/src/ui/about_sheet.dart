import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';
import 'widgets/controls.dart';

const _repo = 'https://github.com/relbns/tv-remote';

/// Shows what this build is and where it came from.
///
/// The version is read from the installed package rather than a constant in the
/// source, so it can never disagree with the APK a person actually has.
Future<void> showAboutSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: Palette.surface,
  showDragHandle: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.lg)),
  ),
  builder: (_) => const _AboutSheet(),
);

class _AboutSheet extends StatelessWidget {
  const _AboutSheet();

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 14,
        children: [
          const _Ring(),
          const Center(
            child: Text(
              'שלט טלוויזיה',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
            ),
          ),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final info = snapshot.data;
              final version = info == null
                  ? '—'
                  : 'גרסה ${info.version} (${info.buildNumber})';
              return Center(
                child: Text(
                  version,
                  style: const TextStyle(fontSize: 13, color: Palette.inkDim),
                ),
              );
            },
          ),
          const SizedBox(height: 2),
          const _Row(label: 'פיתוח', value: 'relbns'),
          const _Row(label: 'רישיון', value: 'MIT'),
          const _Row(label: 'מזהה חבילה', value: 'co.singalong.tv_remote'),
          const SizedBox(height: 4),
          Pill(label: 'קוד המקור ב-GitHub', onTap: () => _open(_repo)),
          Pill(label: 'דיווח על תקלה', onTap: () => _open('$_repo/issues')),
          const SizedBox(height: 6),
          const Text(
            'הפרוטוקול של Android TV Remote v2 אינו מתועד רשמית. הסכמות '
            'שבשימוש פוענחו על ידי louis49/androidtv-remote.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              color: Palette.inkDim,
              height: 1.6,
            ),
          ),
        ],
      ),
    ),
  );

  static Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: const TextStyle(fontSize: 13, color: Palette.inkDim)),
      Text(
        value,
        // The value may be Latin in a right-to-left line; let it keep its own
        // direction so it does not read backwards.
        textDirection: TextDirection.ltr,
        style: const TextStyle(fontSize: 13, color: Palette.ink),
      ),
    ],
  );
}

/// The app's own mark, drawn rather than shipped as another image.
class _Ring extends StatelessWidget {
  const _Ring();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 62,
      height: 62,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Palette.amber, width: 7),
      ),
      child: Container(
        width: 22,
        height: 22,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Palette.amber,
        ),
      ),
    ),
  );
}
