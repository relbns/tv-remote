import 'package:flutter/material.dart';

import '../data/controller.dart';
import '../data/device.dart';
import 'help_page.dart';
import 'theme.dart';
import 'widgets/controls.dart';

/// Building and unbuilding sets.
class RoomsPage extends StatefulWidget {
  const RoomsPage({super.key, required this.controller});
  final RemoteController controller;

  @override
  State<RoomsPage> createState() => _RoomsPageState();
}

class _RoomsPageState extends State<RoomsPage> {
  final _name = TextEditingController();
  String? _displayId;
  String? _sourceId;

  RemoteController get c => widget.controller;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displays = c.devices.where((d) => d.kind.isDisplay).toList();
    final sources = c.devices.where((d) => !d.kind.isDisplay).toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Palette.ground,
        title: const Text('סטים', style: TextStyle(fontSize: 17)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'סט מקשר בין מסך לממיר שמחובר אליו בכבל, כדי לשלוט בשניהם '
                  'כיחידה אחת. הניווט והמדיה הולכים לממיר, העוצמה ובחירת המקור '
                  'למסך, וכפתור ההפעלה מכבה ומדליק את שניהם.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.65,
                    color: Palette.inkMid,
                  ),
                ),
                // The full routing table is one tap away rather than repeated
                // here, so there is a single place it can be corrected.
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const HelpPage(openSection: 'sets'),
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'איך הניתוב עובד? →',
                      style: TextStyle(fontSize: 12, color: Palette.amber),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (c.rooms.isNotEmpty) ...[
            const SizedBox(height: 22),
            const _Label('סטים קיימים'),
            for (final room in c.rooms) ...[
              Raised(
                radius: Radii.md,
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(
                  spacing: 10,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            room.name,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          Text(
                            _describe(room),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Palette.inkDim,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => c.removeRoom(room.id),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.link_off_rounded,
                        size: 19,
                        color: Palette.inkDim,
                      ),
                      tooltip: 'פרק',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
          const SizedBox(height: 22),
          const _Label('סט חדש'),
          if (displays.isEmpty || sources.isEmpty)
            Text(
              displays.isEmpty
                  ? 'כדי ליצור סט צריך גם מסך. הוסף טלוויזיה בלשונית "מכשירים".'
                  : 'כדי ליצור סט צריך גם ממיר.',
              style: const TextStyle(
                fontSize: 12.5,
                color: Palette.inkDim,
                height: 1.6,
              ),
            )
          else ...[
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                hintText: 'שם הסט — למשל "סלון"',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            _Picker(
              label: 'מסך',
              devices: displays,
              value: _displayId,
              onChanged: (id) => setState(() => _displayId = id),
            ),
            const SizedBox(height: 8),
            _Picker(
              label: 'ממיר',
              devices: sources,
              value: _sourceId,
              onChanged: (id) => setState(() => _sourceId = id),
            ),
            const SizedBox(height: 14),
            Raised(
              radius: Radii.md,
              enabled: _ready,
              onTap: _ready ? _create : null,
              padding: const EdgeInsets.symmetric(vertical: 15),
              child: const Center(
                child: Text(
                  'צור סט',
                  style: TextStyle(
                    color: Palette.amber,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool get _ready =>
      _name.text.trim().isNotEmpty && _displayId != null && _sourceId != null;

  String _describe(Room room) {
    final byId = {for (final d in c.devices) d.id: d};
    return '${byId[room.sourceId]?.name ?? "—"} + ${byId[room.displayId]?.name ?? "—"}';
  }

  Future<void> _create() async {
    await c.saveRoom(
      name: _name.text,
      displayId: _displayId!,
      sourceId: _sourceId!,
    );
    if (!mounted) return;
    setState(() {
      _name.clear();
      _displayId = null;
      _sourceId = null;
    });
  }
}

class _Picker extends StatelessWidget {
  const _Picker({
    required this.label,
    required this.devices,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final List<Device> devices;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => Raised(
    radius: Radii.md,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12.5, color: Palette.inkDim),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              alignment: AlignmentDirectional.centerEnd,
              dropdownColor: Palette.surfaceHigh,
              hint: const Text(
                'בחר',
                style: TextStyle(fontSize: 13, color: Palette.inkDim),
              ),
              items: [
                for (final device in devices)
                  DropdownMenuItem(
                    value: device.id,
                    child: Text(
                      '${device.name} · ${device.host}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
              ],
              onChanged: onChanged,
            ),
          ),
        ),
      ],
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
