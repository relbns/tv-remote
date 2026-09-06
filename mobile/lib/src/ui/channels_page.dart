import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/controller.dart';
import '../data/device.dart';
import 'player_page.dart';
import 'theme.dart';
import 'widgets/controls.dart';

/// Direct access to the broadcast channels.
///
/// None of these protocols has a "go to channel" message — a remote presses
/// digits, and so does this. Israel's main channels are branded by their
/// number, so the same tile works on any provider; the list is still editable,
/// because a different provider or a set with its own ordering can disagree.
class ChannelsPage extends StatefulWidget {
  const ChannelsPage({super.key, required this.controller});

  final RemoteController controller;

  @override
  State<ChannelsPage> createState() => _ChannelsPageState();
}

class _ChannelsPageState extends State<ChannelsPage> {
  String _typed = '';

  RemoteController get c => widget.controller;

  Future<void> _tune(String number) async {
    HapticFeedback.selectionClick();
    await c.tuneTo(number);
    if (mounted) setState(() => _typed = '');
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      final live = c.isConnected;
      final channels = c.channels;
      return ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'ערוצים',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: () => _edit(context),
                child: const Text(
                  'עריכה',
                  style: TextStyle(fontSize: 12.5, color: Palette.amber),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (channels.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Text(
                'הרשימה ריקה. הוסף ערוץ ב"עריכה".',
                textAlign: TextAlign.center,
                style: TextStyle(color: Palette.inkDim, fontSize: 12.5),
              ),
            )
          else
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.1,
              children: [
                for (final channel in channels)
                  _ChannelTile(
                    channel: channel,
                    // Tuning without a connection reports itself; dimming the
                    // whole tile would also put watching on the phone — which
                    // needs no television at all — out of reach.
                    enabled: true,
                    onTap: () => _tune(channel.number),
                    onWatch: channel.watch == null && channel.stream == null
                        ? null
                        : () => _play(channel),
                    playsHere: channel.stream != null,
                  ),
              ],
            ),
          const SizedBox(height: 22),
          const _Label('הקלדת אפיק'),
          const SizedBox(height: 10),
          _Keypad(
            typed: _typed,
            enabled: live,
            onDigit: (d) => setState(() {
              if (_typed.length < 4) _typed += d;
            }),
            onClear: () => setState(() => _typed = ''),
            onSend: _typed.isEmpty ? null : () => _tune(_typed),
          ),
          if (!live) ...[
            const SizedBox(height: 14),
            const Text(
              'אין חיבור פעיל — בחר מכשיר בלשונית השלט.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Palette.inkDim, fontSize: 11.5),
            ),
          ],
        ],
      );
    },
  );

  /// Play here when the broadcaster publishes an open stream; otherwise open
  /// their page, which is the only honest option for a protected feed.
  Future<void> _play(Channel channel) async {
    if (channel.stream != null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => PlayerPage(channel: channel)),
      );
      return;
    }
    await _watch(channel);
  }

  Future<void> _watch(Channel channel) async {
    final uri = Uri.tryParse(channel.watch ?? '');
    if (uri == null) return;
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('לא ניתן לפתוח את השידור של ${channel.name}')),
      );
    }
  }

  Future<void> _edit(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => _EditChannelsPage(controller: c)),
    );
    if (mounted) setState(() {});
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    required this.channel,
    required this.enabled,
    required this.onTap,
    required this.onWatch,
    required this.playsHere,
  });

  final Channel channel;
  final bool enabled;
  final VoidCallback onTap;

  /// Watching on the phone does not need the television, so this stays live
  /// even when nothing is connected.
  final VoidCallback? onWatch;

  /// True when the stream plays inside the app rather than opening a browser —
  /// worth showing, because the two are a different experience.
  final bool playsHere;

  @override
  Widget build(BuildContext context) {
    final tint = parseColor(channel.color) ?? Palette.amber;
    return Raised(
      enabled: enabled,
      onTap: enabled ? onTap : null,
      radius: Radii.sm,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              channel.number,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: tint,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              channel.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, height: 1.3),
            ),
          ),
          if (onWatch != null)
            IconButton(
              onPressed: onWatch,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
              icon: Icon(
                playsHere
                    ? Icons.play_circle_fill_rounded
                    : Icons.open_in_new_rounded,
                size: 19,
                color: playsHere ? Palette.amber : Palette.inkDim,
              ),
              tooltip: playsHere ? 'צפייה כאן' : 'פתיחה באתר השדרן',
            ),
        ],
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.typed,
    required this.enabled,
    required this.onDigit,
    required this.onClear,
    required this.onSend,
  });

  final String typed;
  final bool enabled;
  final ValueChanged<String> onDigit;
  final VoidCallback onClear;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Palette.surface,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Text(
          typed.isEmpty ? '—' : typed,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: 3,
            color: typed.isEmpty ? Palette.inkDim : Palette.ink,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
      const SizedBox(height: 10),
      // Left to right, like every keypad — the digits are not language.
      Directionality(
        textDirection: TextDirection.ltr,
        child: GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.7,
          children: [
            for (final digit in ['1', '2', '3', '4', '5', '6', '7', '8', '9'])
              _Key(label: digit, enabled: enabled, onTap: () => onDigit(digit)),
            _Key(
              label: 'C',
              enabled: enabled && typed.isNotEmpty,
              onTap: onClear,
              dim: true,
            ),
            _Key(label: '0', enabled: enabled, onTap: () => onDigit('0')),
            _Key(
              label: '↵',
              enabled: enabled && onSend != null,
              onTap: onSend ?? () {},
              accent: true,
            ),
          ],
        ),
      ),
    ],
  );
}

class _Key extends StatelessWidget {
  const _Key({
    required this.label,
    required this.enabled,
    required this.onTap,
    this.dim = false,
    this.accent = false,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;
  final bool dim;
  final bool accent;

  @override
  Widget build(BuildContext context) => Raised(
    enabled: enabled,
    radius: Radii.sm,
    onTap: enabled
        ? () {
            HapticFeedback.selectionClick();
            onTap();
          }
        : null,
    child: Center(
      child: Text(
        label,
        style: TextStyle(
          fontSize: accent ? 19 : 18,
          fontWeight: FontWeight.w600,
          color: accent
              ? Palette.amber
              : dim
              ? Palette.inkDim
              : Palette.ink,
        ),
      ),
    ),
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: Text(
      text,
      style: const TextStyle(fontSize: 11.5, color: Palette.inkDim),
    ),
  );
}

/* ---------------- editing ---------------- */

class _EditChannelsPage extends StatefulWidget {
  const _EditChannelsPage({required this.controller});
  final RemoteController controller;

  @override
  State<_EditChannelsPage> createState() => _EditChannelsPageState();
}

class _EditChannelsPageState extends State<_EditChannelsPage> {
  late List<Channel> _channels = [...widget.controller.channels];

  Future<void> _save() => widget.controller.saveChannels(_channels);

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('עריכת ערוצים'),
      actions: [
        TextButton(
          onPressed: () async {
            await widget.controller.resetChannels();
            if (!mounted) return;
            setState(() => _channels = [...widget.controller.channels]);
          },
          child: const Text(
            'איפוס',
            style: TextStyle(fontSize: 12.5, color: Palette.inkDim),
          ),
        ),
      ],
    ),
    body: ReorderableListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 90),
      onReorderItem: (from, to) async {
        setState(() => _channels.insert(to, _channels.removeAt(from)));
        await _save();
      },
      children: [
        for (final (index, channel) in _channels.indexed)
          Padding(
            key: ValueKey('${channel.number}-$index'),
            padding: const EdgeInsets.only(bottom: 8),
            child: Raised(
              radius: Radii.sm,
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(
                      channel.number,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      channel.name,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    color: Palette.inkDim,
                    onPressed: () => _editOne(index),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    color: Palette.inkDim,
                    onPressed: () async {
                      setState(() => _channels.removeAt(index));
                      await _save();
                    },
                  ),
                  const Icon(
                    Icons.drag_handle_rounded,
                    size: 18,
                    color: Palette.inkDim,
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ),
          ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      backgroundColor: Palette.amber,
      foregroundColor: Palette.ground,
      onPressed: () => _editOne(null),
      icon: const Icon(Icons.add_rounded),
      label: const Text('ערוץ'),
    ),
  );

  Future<void> _editOne(int? index) async {
    final existing = index == null ? null : _channels[index];
    final number = TextEditingController(text: existing?.number ?? '');
    final name = TextEditingController(text: existing?.name ?? '');
    final watch = TextEditingController(text: existing?.watch ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Palette.surface,
        title: Text(existing == null ? 'ערוץ חדש' : 'עריכת ערוץ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: number,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: const InputDecoration(
                labelText: 'אפיק',
                counterText: '',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'שם'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: watch,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'קישור לצפייה בטלפון',
                helperText: 'עמוד השידור החי של השדרן — לא חובה',
                helperMaxLines: 2,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('שמור'),
          ),
        ],
      ),
    );

    if (saved != true) return;
    final digits = number.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return;
    final label = name.text.trim().isEmpty ? 'ערוץ $digits' : name.text.trim();

    setState(() {
      final url = watch.text.trim();
      final channel = Channel(
        number: digits,
        name: label,
        color: existing?.color,
        watch: url.isEmpty ? null : url,
      );
      if (index == null) {
        _channels.add(channel);
      } else {
        _channels[index] = channel;
      }
    });
    await _save();
  }
}
