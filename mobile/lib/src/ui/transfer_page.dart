import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../data/backup.dart';
import '../data/controller.dart';
import 'theme.dart';
import 'widgets/controls.dart';

/// Moving a setup between phones.
class TransferPage extends StatelessWidget {
  const TransferPage({super.key, required this.controller});
  final RemoteController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: Palette.ground,
      title: const Text('העברה למכשיר אחר', style: TextStyle(fontSize: 17)),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      children: [
        const _Note(
          'ההגדרות שלך — המכשירים, השמות שנתת והקיצורים — הן נתונים רגילים '
          'וקטנות מספיק לעבור כקוד \u2068QR\u2069. הצימוד עצמו הוא פריט '
          'אישור: מכשיר שמקבל אותו נכנס בלי ללכת לטלוויזיה, ולכן הוא עובר '
          'רק כקובץ.',
        ),
        const SizedBox(height: 20),
        const _Label('שליחה'),
        _Action(
          title: 'הגדרות בלבד',
          subtitle: 'קוד \u2068QR\u2069 או קובץ · יידרש צימוד אחד',
          icon: Icons.qr_code_2_rounded,
          onTap: () => _export(context, withCredentials: false),
        ),
        const SizedBox(height: 8),
        _Action(
          title: 'כולל צימוד',
          subtitle: 'קובץ בלבד · המכשיר השני יעבוד מיד',
          icon: Icons.vpn_key_rounded,
          warning: true,
          onTap: () => _export(context, withCredentials: true),
        ),
        const SizedBox(height: 24),
        const _Label('קבלה'),
        _Action(
          title: 'סרוק קוד',
          subtitle: 'מצלמה — לקוד שמוצג במכשיר השני',
          icon: Icons.photo_camera_rounded,
          onTap: () => _scan(context),
        ),
        const SizedBox(height: 8),
        _Action(
          title: 'בחר קובץ',
          subtitle: 'קובץ גיבוי שקיבלת',
          icon: Icons.folder_open_rounded,
          onTap: () => _pickFile(context),
        ),
      ],
    ),
  );

  Future<void> _export(
    BuildContext context, {
    required bool withCredentials,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final backup = await controller.buildBackup(
      includeCredentials: withCredentials,
    );

    if (backup.devices.isEmpty) {
      _toast(messenger, 'אין מה לשלוח — עדיין לא הוגדר אף מכשיר');
      return;
    }
    if (!context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => _ExportView(backup: backup)),
    );
  }

  Future<void> _scan(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final code = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const _ScannerView()));
    if (code == null) return;

    try {
      await controller.applyBackup(Backup.fromCompact(code));
      _toast(messenger, 'ההגדרות התקבלו', ok: true);
    } on Object catch (failure) {
      _toast(messenger, '$failure');
    }
  }

  Future<void> _pickFile(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final file = await FilePicker.pickFile();
    if (file == null) return;

    try {
      final text = utf8.decode(await file.readAsBytes());
      final backup = Backup.fromText(text);
      final count = await controller.applyBackup(backup);
      _toast(
        messenger,
        backup.includesCredentials
            ? 'התקבלו $count מכשירים, כולל הצימוד'
            : 'התקבלו $count מכשירים — יש לצמד אותם',
        ok: true,
      );
    } on Object catch (failure) {
      _toast(messenger, '$failure');
    }
  }

  static void _toast(
    ScaffoldMessengerState messenger,
    String message, {
    bool ok = false,
  }) {
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(14),
        duration: Duration(seconds: ok ? 4 : 10),
      ),
    );
  }
}

/// Shows the backup as a QR code when it fits, and offers it as a file always.
class _ExportView extends StatelessWidget {
  const _ExportView({required this.backup});
  final Backup backup;

  /// Beyond this a phone camera struggles to read the code in one go.
  static const _qrLimit = 2200;

  @override
  Widget build(BuildContext context) {
    final compact = backup.toCompact();
    final fitsInQr = !backup.includesCredentials && compact.length <= _qrLimit;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Palette.ground,
        title: Text(
          backup.includesCredentials ? 'כולל צימוד' : 'הגדרות בלבד',
          style: const TextStyle(fontSize: 17),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          if (fitsInQr) ...[
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  // A QR code needs a light field to be read reliably.
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(Radii.lg),
                ),
                child: QrImageView(
                  data: compact,
                  version: QrVersions.auto,
                  size: 260,
                  gapless: true,
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'במכשיר השני: העברה למכשיר אחר ← סרוק קוד',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: Palette.inkMid),
            ),
            const SizedBox(height: 24),
          ] else
            const _Note(
              'הגיבוי הזה נושא אישורי גישה והוא גדול מכדי להיקרא כקוד '
              '\u2068QR\u2069. '
              'שלח אותו כקובץ בערוץ שאתה סומך עליו — הוא שקול למפתח.',
              warning: true,
            ),
          const SizedBox(height: 8),
          _Action(
            title: 'שלח כקובץ',
            subtitle: 'וואטסאפ, \u2068Quick Share\u2069, או כל דרך אחרת',
            icon: Icons.ios_share_rounded,
            onTap: () => _share(context),
          ),
          const SizedBox(height: 20),
          Text(
            '${backup.devices.length} מכשירים · '
            '${backup.shortcuts.values.fold(0, (n, list) => n + list.length)} קיצורים'
            '${backup.includesCredentials ? " · ${backup.certificates.length} צימודים" : ""}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11.5, color: Palette.inkDim),
          ),
        ],
      ),
    );
  }

  Future<void> _share(BuildContext context) async {
    final directory = await getTemporaryDirectory();
    final stamp = DateTime.now().toIso8601String().split('T').first;
    final file = File('${directory.path}/tv-remote-$stamp.json');
    await file.writeAsString(backup.toPrettyJson());

    if (!context.mounted) return;
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: 'הגדרות Orbit'),
    );
  }
}

/// Camera view that returns the first backup-looking code it sees.
class _ScannerView extends StatefulWidget {
  const _ScannerView();

  @override
  State<_ScannerView> createState() => _ScannerViewState();
}

class _ScannerViewState extends State<_ScannerView> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: Palette.ground,
      title: const Text('סרוק קוד', style: TextStyle(fontSize: 17)),
    ),
    body: Stack(
      alignment: Alignment.center,
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: (capture) {
            if (_handled) return;
            final value = capture.barcodes.firstOrNull?.rawValue;
            if (value == null || value.isEmpty) return;
            _handled = true;
            Navigator.of(context).pop(value);
          },
        ),
        // A frame to aim with; the scanner itself reads the whole image.
        IgnorePointer(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: Palette.amber, width: 2.5),
              borderRadius: BorderRadius.circular(Radii.lg),
            ),
          ),
        ),
      ],
    ),
  );
}

/* ---------------- pieces ---------------- */

class _Action extends StatelessWidget {
  const _Action({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.warning = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool warning;

  @override
  Widget build(BuildContext context) => Raised(
    radius: Radii.md,
    onTap: onTap,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    child: Row(
      spacing: 14,
      children: [
        Icon(icon, size: 22, color: warning ? Palette.dead : Palette.amber),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 11.5, color: Palette.inkDim),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text, {this.warning = false});
  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: warning
          ? Palette.dead.withValues(alpha: 0.12)
          : Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(Radii.md),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12.5,
        height: 1.65,
        color: warning ? Palette.ink : Palette.inkMid,
      ),
    ),
  );
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
