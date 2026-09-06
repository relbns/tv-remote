import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/controller.dart';
import '../data/device.dart';
import '../data/discovery.dart';
import '../data/target.dart';
import 'settings_sheet.dart';
import 'help_page.dart';
import 'theme.dart';
import 'widgets/controls.dart';

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key, required this.controller});
  final RemoteController controller;

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  RemoteController get c => widget.controller;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
    children: [
      Row(
        children: [
          const Expanded(child: _Label('מכשירים')),
          IconButton(
            onPressed: () => showSettingsSheet(context, c),
            icon: const Icon(
              Icons.tune_rounded,
              size: 20,
              color: Palette.inkDim,
            ),
            tooltip: 'הגדרות',
          ),
        ],
      ),
      if (c.devices.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Text(
            'אין מכשירים. חפש ברשת כדי להוסיף.',
            style: TextStyle(color: Palette.inkDim, fontSize: 13),
          ),
        ),
      for (final device in c.devices) ...[
        _DeviceRow(
          device: device,
          paired: c.isPaired(device),
          connected: c.isDeviceConnected(device.id),
          selected: c.current?.devices.any((d) => d.id == device.id) ?? false,
          onSelect: () =>
              c.select(c.targetFor(device.id) ?? Target.forDevice(device)),
          onPair: () => _pair(device),
          onRename: () => _rename(device),
          onRemove: () => _confirmRemove(device),
        ),
        const SizedBox(height: 8),
      ],
      const SizedBox(height: 14),
      Raised(
        radius: Radii.md,
        onTap: c.scanning ? null : c.scan,
        enabled: !c.scanning,
        padding: const EdgeInsets.symmetric(vertical: 15),
        child: Center(
          child: Text(
            c.scanning
                ? 'סורק את הרשת…'
                : c.found.isEmpty
                ? 'חפש מכשירים'
                : 'סרוק שוב',
            style: const TextStyle(
              color: Palette.amber,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
      if (c.found.isNotEmpty) ...[
        const SizedBox(height: 18),
        const _Label('נמצאו ברשת'),
        for (final found in c.found) ...[
          _FoundRow(found: found, onAdd: () => _add(found)),
          const SizedBox(height: 8),
        ],
      ],
      const SizedBox(height: 20),
      const Text(
        'החיפוש בודק כל כתובת ברשת המקומית. מכשיר כבוי לא ייענה — הדלק אותו '
        'וסרוק שוב.',
        style: TextStyle(fontSize: 11.5, color: Palette.inkDim, height: 1.6),
      ),
    ],
  );

  Future<void> _add(Discovered found) async {
    await c.add(
      Device(
        id: Device.idFor(found.kind, found.host),
        kind: found.kind,
        name: found.kind.short,
        host: found.host,
      ),
    );
    c.forgetFound(found);
  }

  /// Errors here are things a person has to act on — a wrong code, an
  /// unreachable device — so they stay up long enough to read and can be
  /// dismissed deliberately.
  void _showError(ScaffoldMessengerState messenger, String message) {
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 12),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(14),
        action: SnackBarAction(
          label: 'סגור',
          onPressed: messenger.hideCurrentSnackBar,
        ),
      ),
    );
  }

  Future<void> _rename(Device device) async {
    final controller = TextEditingController(text: device.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        title: const Text('שם המכשיר', style: TextStyle(fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            const Text(
              'תן לו שם שאומר לך משהו — למשל "סלון" או "בית של אמא".',
              style: TextStyle(
                fontSize: 12.5,
                color: Palette.inkMid,
                height: 1.6,
              ),
            ),
            TextField(
              controller: controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(hintText: 'שם'),
              onSubmitted: (value) => Navigator.pop(dialogContext, value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('ביטול', style: TextStyle(color: Palette.inkDim)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('שמור', style: TextStyle(color: Palette.amber)),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null) await c.rename(device, name);
  }

  /// Removing a device throws away its pairing certificate, and pairing again
  /// means walking to the television — worth a question first.
  Future<void> _confirmRemove(Device device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        title: Text(
          'להסיר את ${device.name}?',
          style: const TextStyle(fontSize: 17),
        ),
        content: const Text(
          'הצימוד יימחק. כדי לחבר את המכשיר מחדש תצטרך לצמד אותו שוב מול '
          'הקוד שיופיע על המסך.',
          style: TextStyle(fontSize: 13, color: Palette.inkMid, height: 1.65),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('ביטול', style: TextStyle(color: Palette.inkDim)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('הסר', style: TextStyle(color: Palette.dead)),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await c.remove(device.id);
  }

  Future<void> _pair(Device device) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await c.beginPairing(device);
    } on Object catch (failure) {
      _showError(messenger, '$failure');
      return;
    }
    if (!mounted) return;

    final code = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CodeDialog(),
    );

    if (code == null) {
      await c.cancelPairing();
      return;
    }

    try {
      await c.submitCode(device, code);
      messenger.showSnackBar(const SnackBar(content: Text('הצימוד הושלם')));
    } on Object catch (failure) {
      _showError(messenger, '$failure');
    }
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.paired,
    required this.connected,
    required this.selected,
    required this.onSelect,
    required this.onPair,
    required this.onRename,
    required this.onRemove,
  });

  final Device device;
  final bool paired;

  /// Whether a session to this device is open right now.
  final bool connected;

  /// Whether this platform has a driver for the device's protocol.
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onPair;
  final VoidCallback onRename;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(Radii.md),
      // Selection is a ring; the lamp is reserved for the connection itself,
      // which is what a coloured dot is read as.
      border: selected
          ? Border.all(color: Palette.amber.withValues(alpha: 0.55), width: 1.5)
          : null,
    ),
    child: Raised(
      radius: Radii.md,
      onTap: paired ? onSelect : null,
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        spacing: 10,
        children: [
          Lamp(
            color: connected
                ? Palette.live
                : paired
                ? Palette.dead
                : Palette.inkDim,
            tooltip: connected
                ? 'מחובר'
                : paired
                ? 'מצומד, לא מחובר'
                : 'לא מצומד',
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  '${device.kind.label} · ${device.host}',
                  style: const TextStyle(fontSize: 11, color: Palette.inkDim),
                ),
              ],
            ),
          ),
          if (!paired)
            TextButton(
              onPressed: onPair,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: Text(
                // A device whose protocol has no driver here must not offer a
                // button that can only fail.
                'צמד',
                style: TextStyle(color: Palette.amber),
              ),
            ),
          IconButton(
            onPressed: onRename,
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.edit_outlined,
              size: 18,
              color: Palette.inkDim,
            ),
            tooltip: 'שנה שם',
          ),
          IconButton(
            onPressed: onRemove,
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.delete_outline_rounded,
              size: 19,
              color: Palette.inkDim,
            ),
            tooltip: 'הסר',
          ),
        ],
      ),
    ),
  );
}

class _FoundRow extends StatelessWidget {
  const _FoundRow({required this.found, required this.onAdd});
  final Discovered found;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Raised(
    radius: Radii.md,
    onTap: onAdd,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(
      spacing: 12,
      children: [
        const Lamp(color: Palette.amber),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                found.kind.label,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              Text(
                found.host,
                style: const TextStyle(fontSize: 11, color: Palette.inkDim),
              ),
            ],
          ),
        ),
        const Text(
          'הוסף',
          style: TextStyle(color: Palette.amber, fontSize: 13),
        ),
      ],
    ),
  );
}

/// Collects the six characters shown on the screen.
class _CodeDialog extends StatefulWidget {
  const _CodeDialog();

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: Palette.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.lg),
    ),
    title: const Text('הזן את הקוד מהמסך', style: TextStyle(fontSize: 17)),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 14,
      children: [
        const Text(
          'על מסך הטלוויזיה מופיע קוד בן שישה תווים. הצימוד נדרש פעם אחת בלבד.',
          style: TextStyle(fontSize: 12.5, color: Palette.inkMid, height: 1.6),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const HelpPage(openSection: 'pairing'),
              ),
            ),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'הקוד לא מתקבל? →',
              style: TextStyle(fontSize: 12, color: Palette.amber),
            ),
          ),
        ),
        TextField(
          controller: _controller,
          autofocus: true,
          maxLength: 6,
          textAlign: TextAlign.center,
          textCapitalization: TextCapitalization.characters,
          // The code is hexadecimal, so ask for a Latin keyboard and reject
          // anything that cannot appear in one. Without this the phone offers
          // its Hebrew layout, where none of the keys are usable.
          keyboardType: TextInputType.visiblePassword,
          autocorrect: false,
          enableSuggestions: false,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
            TextInputFormatter.withFunction(
              (_, next) => next.copyWith(text: next.text.toUpperCase()),
            ),
          ],
          style: const TextStyle(
            fontSize: 22,
            letterSpacing: 8,
            fontWeight: FontWeight.w600,
          ),
          decoration: const InputDecoration(
            hintText: 'ABC123',
            counterText: '',
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('ביטול', style: TextStyle(color: Palette.inkDim)),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: const Text('אישור', style: TextStyle(color: Palette.amber)),
      ),
    ],
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
