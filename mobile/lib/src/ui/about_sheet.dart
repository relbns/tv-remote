import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';
import 'widgets/controls.dart';

const _repo = 'https://github.com/relbns/tv-remote';

/// Wrap a Latin run so the bidirectional algorithm treats it as one unit.
///
/// Without this, "GitHub" or "louis49/androidtv-remote" inside a Hebrew
/// sentence drags the neighbouring punctuation across the line and the text
/// reads scrambled. U+2068 opens a first-strong isolate, U+2069 closes it.
String _ltr(String text) => '\u2068$text\u2069';

/// Shows what this build is and where it came from.
///
/// The version is read from the installed package rather than a constant in the
/// source, so it can never disagree with the APK a person actually has.
Future<void> showAboutSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: Palette.surface,
  showDragHandle: true,
  // Without these the sheet runs under the navigation bar and its last button
  // cannot be reached, and tall content is clipped instead of scrolling.
  useSafeArea: true,
  isScrollControlled: true,
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
    child: SingleChildScrollView(
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
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) => _Row(
              label: 'מזהה חבילה',
              value: snapshot.data?.packageName ?? '—',
            ),
          ),
          const SizedBox(height: 4),
          Pill(label: 'קוד המקור', onTap: () => _open(_repo)),
          Pill(label: 'דיווח על תקלה', onTap: _reportIssue),
          const SizedBox(height: 6),
          Text(
            'הפרוטוקול של ${_ltr('Android TV Remote v2')} אינו מתועד רשמית. '
            'הסכמות שבשימוש פוענחו על ידי ${_ltr('louis49/androidtv-remote')}.',
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

  /// Opens a new issue with the details a bug report is useless without:
  /// which build, which phone, which Android. Typing those by hand is exactly
  /// what people skip.
  static Future<void> _reportIssue() async {
    final info = await PackageInfo.fromPlatform();
    final body =
        '\n\n---\n'
        '- אפליקציה: ${info.version} (${info.buildNumber})\n'
        '- מערכת: ${Platform.operatingSystemVersion}\n';
    final uri = Uri.parse('$_repo/issues/new')
        .replace(queryParameters: {'title': '', 'body': body});
    await _open(uri.toString());
  }

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
