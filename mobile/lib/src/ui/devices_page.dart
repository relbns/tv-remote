import 'dart:async';

import 'package:flutter/material.dart';

import '../data/controller.dart';
import '../data/device.dart';
import '../data/discovery.dart';
import 'theme.dart';
import 'widgets/controls.dart';

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key, required this.controller});
  final RemoteController controller;

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  final _found = <Discovered>[];
  StreamSubscription<Discovered>? _sweep;
  bool _scanning = false;

  RemoteController get c => widget.controller;

  @override
  void dispose() {
    unawaited(_sweep?.cancel());
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _found.clear();
    });

    final known = {for (final device in c.devices) device.host};
    _sweep = Discovery.sweep().listen(
      (device) {
        if (known.contains(device.host)) return;
        if (mounted) setState(() => _found.add(device));
      },
      onDone: () {
        if (mounted) setState(() => _scanning = false);
      },
    );
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
    children: [
      const _Label('מכשירים'),
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
          selected: c.current?.id == device.id,
          onSelect: () => c.select(device),
          onPair: () => _pair(device),
          onRemove: () => c.remove(device.id),
        ),
        const SizedBox(height: 8),
      ],
      const SizedBox(height: 14),
      Raised(
        radius: Radii.md,
        onTap: _scanning ? null : _scan,
        enabled: !_scanning,
        padding: const EdgeInsets.symmetric(vertical: 15),
        child: Center(
          child: Text(
            _scanning ? 'סורק את הרשת…' : 'חפש מכשירים',
            style: const TextStyle(
              color: Palette.amber,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
      if (_found.isNotEmpty) ...[
        const SizedBox(height: 18),
        const _Label('נמצאו ברשת'),
        for (final found in _found) ...[
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
    if (mounted) setState(() => _found.remove(found));
  }

  Future<void> _pair(Device device) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await c.beginPairing(device);
    } on Object catch (failure) {
      messenger.showSnackBar(SnackBar(content: Text('$failure')));
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
      messenger.showSnackBar(SnackBar(content: Text('$failure')));
    }
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.device,
    required this.paired,
    required this.selected,
    required this.onSelect,
    required this.onPair,
    required this.onRemove,
  });

  final Device device;
  final bool paired;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onPair;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Raised(
    radius: Radii.md,
    onTap: paired ? onSelect : null,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(
      spacing: 12,
      children: [
        Lamp(color: selected ? Palette.live : Palette.inkDim),
        Expanded(
          child: Column(
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
            child: const Text('צמד', style: TextStyle(color: Palette.amber)),
          ),
        IconButton(
          onPressed: onRemove,
          icon: const Icon(
            Icons.delete_outline_rounded,
            size: 20,
            color: Palette.inkDim,
          ),
          tooltip: 'הסר',
        ),
      ],
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
        TextField(
          controller: _controller,
          autofocus: true,
          maxLength: 6,
          textAlign: TextAlign.center,
          textCapitalization: TextCapitalization.characters,
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
