import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:url_launcher/url_launcher.dart';

import '../data/controller.dart';
import '../data/updates.dart';
import 'theme.dart';
import 'widgets/controls.dart';
import 'widgets/dpad.dart';

class RemotePage extends StatefulWidget {
  const RemotePage({super.key, required this.controller});
  final RemoteController controller;

  @override
  State<RemotePage> createState() => _RemotePageState();
}

class _RemotePageState extends State<RemotePage> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  RemoteController get c => widget.controller;

  @override
  Widget build(BuildContext context) {
    final live = c.isConnected;
    final target = c.current;

    if (target == null) {
      return const _Empty(
        message: 'עדיין לא הוגדר אף מכשיר.',
        hint: 'עבור ללשונית "מכשירים" וחפש ברשת.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      children: [
        if (c.update case final update?) ...[
          _UpdateBanner(update: update),
          const SizedBox(height: 10),
        ],
        _Header(controller: c),
        const SizedBox(height: 14),
        Row(
          spacing: 8,
          children: [
            IconKey(
              icon: Icons.home_rounded,
              label: 'בית',
              enabled: live,
              onTap: () => c.send('home'),
            ),
            IconKey(
              icon: Icons.arrow_back_rounded,
              label: 'חזור',
              enabled: live,
              onTap: () => c.send('back'),
            ),
            IconKey(
              icon: Icons.menu_rounded,
              label: 'תפריט',
              enabled: live,
              onTap: () => c.send('menu'),
            ),
            IconKey(
              icon: Icons.grid_view_rounded,
              label: 'מדריך',
              enabled: live,
              onTap: () => c.send('guide'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Center(
          child: DPad(enabled: live, onCommand: c.send),
        ),
        const SizedBox(height: 8),
        const Center(
          child: Text(
            'אפשר גם להחליק אצבע על הטבעת',
            style: TextStyle(fontSize: 11, color: Palette.inkDim),
          ),
        ),
        const SizedBox(height: 18),
        _Transport(controller: c, enabled: live),
        const SizedBox(height: 10),
        Row(
          spacing: 8,
          children: [
            Rocker(
              label: 'עוצמה',
              enabled: live,
              onDown: () => c.send('voldown'),
              onUp: () => c.send('volup'),
            ),
            Raised(
              radius: 28,
              enabled: live,
              onTap: () => c.send('mute'),
              child: SizedBox(
                width: 56,
                height: 56,
                // The box reports its mute state, so show it rather than a
                // fixed icon — a control that never reflects reality is worse
                // than no indicator at all.
                child: Icon(
                  c.deviceState.muted ?? false
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                  color: (c.deviceState.muted ?? false)
                      ? Palette.amber
                      : Palette.inkMid,
                  size: 20,
                ),
              ),
            ),
            Rocker(
              label: 'ערוץ',
              enabled: live,
              onDown: () => c.send('chdown'),
              onUp: () => c.send('chup'),
            ),
          ],
        ),
        const SizedBox(height: 22),
        _AppShelf(controller: c, enabled: live),
        const SizedBox(height: 18),
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: TextField(
                controller: _text,
                enabled: live,
                textInputAction: TextInputAction.send,
                decoration: const InputDecoration(
                  hintText: 'הקלד לחיפוש בטלוויזיה…',
                ),
                onSubmitted: _send,
              ),
            ),
            Raised(
              enabled: live,
              onTap: () => _send(_text.text),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
              child: const Text('שלח', style: TextStyle(color: Palette.amber)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          spacing: 8,
          children: [
            IconKey(
              icon: Icons.power_settings_new_rounded,
              label: 'כיבוי מסך',
              enabled: live,
              onTap: () => c.send('tvpower'),
            ),
            IconKey(
              icon: Icons.input_rounded,
              label: 'בחירת מקור',
              enabled: live,
              onTap: () => c.send('input'),
            ),
            IconKey(
              icon: Icons.settings_rounded,
              label: 'הגדרות',
              enabled: live,
              onTap: () => c.send('settings'),
            ),
            IconKey(
              icon: Icons.info_outline_rounded,
              label: 'מידע',
              enabled: live,
              onTap: () => c.send('info'),
            ),
          ],
        ),
        if (target.source != null) ...[
          const SizedBox(height: 14),
          const Text(
            'הכפתורים "כיבוי מסך" ו"מקור" מועברים לטלוויזיה בכבל ה־'
            '\u2068HDMI\u2069 בתקן \u2068CEC\u2069, וזה עובד רק אם הממיר '
            'תומך בהעברה כזו. חלק מהממירים אינם תומכים, ואז אין דרך תוכנה '
            'לשלוט בטלוויזיה.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Palette.inkDim, height: 1.6),
          ),
        ],
      ],
    );
  }

  void _send(String value) {
    if (value.isEmpty) return;
    c.sendText(value);
    _text.clear();
    FocusScope.of(context).unfocus();
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});
  final RemoteController controller;

  @override
  Widget build(BuildContext context) {
    final target = controller.current!;
    final (color, label) = switch (controller.link) {
      LinkState.connected => (Palette.live, 'מחובר'),
      LinkState.connecting => (Palette.amber, 'מתחבר…'),
      LinkState.pairing => (Palette.amber, 'ממתין לצימוד'),
      LinkState.failed => (Palette.dead, 'מנותק'),
      LinkState.idle => (Palette.inkDim, 'לא מצומד'),
    };

    // A set shows one lamp per half, so a screen that dropped is visible even
    // while the box is still answering.
    final lamps = target.devices
        .map(
          (d) => Lamp(
            color: controller.isDeviceConnected(d.id)
                ? Palette.live
                : Palette.dead,
            tooltip: '${d.name} · ${d.host}',
          ),
        )
        .toList();

    return Raised(
      radius: Radii.lg,
      onTap: controller.targets.length > 1
          ? () => _showTargetPicker(context, controller)
          : null,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        spacing: 12,
        children: [
          if (lamps.length > 1)
            Row(mainAxisSize: MainAxisSize.min, spacing: 5, children: lamps)
          else
            Lamp(color: color),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  target.isRoom ? '${target.name} · סט' : target.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                Text(
                  target.isRoom
                      ? '${target.source?.name ?? "—"} + ${target.display?.name ?? "—"} · $label'
                      : '${target.source?.kind.short ?? target.display?.kind.short} · '
                            '${target.devices.firstOrNull?.host} · $label',
                  style: const TextStyle(fontSize: 11, color: Palette.inkDim),
                ),
              ],
            ),
          ),
          if (controller.deviceState.currentApp != null)
            Text(
              controller.labelFor(controller.deviceState.currentApp!),
              style: const TextStyle(fontSize: 11.5, color: Palette.amber),
            ),
          _PowerButton(controller: controller),
        ],
      ),
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({required this.controller, required this.enabled});
  final RemoteController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Directionality(
    // Transport controls map to the direction time runs, not reading order.
    textDirection: TextDirection.ltr,
    child: Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.035),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _Key(Icons.skip_previous_rounded, 'prev', controller, enabled),
            _Key(Icons.fast_rewind_rounded, 'rewind', controller, enabled),
            _Key(
              Icons.play_arrow_rounded,
              'playpause',
              controller,
              enabled,
              accent: true,
            ),
            _Key(Icons.fast_forward_rounded, 'forward', controller, enabled),
            _Key(Icons.skip_next_rounded, 'next', controller, enabled),
          ],
        ),
      ),
    ),
  );
}

class _Key extends StatelessWidget {
  const _Key(
    this.icon,
    this.command,
    this.controller,
    this.enabled, {
    this.accent = false,
  });

  final IconData icon;
  final String command;
  final RemoteController controller;
  final bool enabled;
  final bool accent;

  @override
  Widget build(BuildContext context) => InkResponse(
    radius: 26,
    onTap: enabled ? () => controller.send(command) : null,
    child: Container(
      width: accent ? 46 : 40,
      height: accent ? 46 : 40,
      decoration: accent
          ? const BoxDecoration(
              shape: BoxShape.circle,
              color: Palette.amberWash,
            )
          : null,
      child: Icon(
        icon,
        size: accent ? 24 : 22,
        color: accent ? Palette.amber : Palette.inkMid,
      ),
    ),
  );
}

class _AppShelf extends StatelessWidget {
  const _AppShelf({required this.controller, required this.enabled});
  final RemoteController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final apps = controller.shortcuts();
    if (apps.isEmpty) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(right: 4, bottom: 8),
          child: Text(
            'אפליקציות',
            style: TextStyle(fontSize: 12, color: Palette.inkDim),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: apps.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, index) => Pill(
              label: apps[index].label,
              enabled: enabled,
              onTap: () => controller.launch(apps[index].launch),
            ),
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message, required this.hint});
  final String message;
  final String hint;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 10,
        children: [
          const Icon(Icons.tv_rounded, size: 48, color: Palette.inkDim),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15),
          ),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              color: Palette.inkDim,
              height: 1.6,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Toggles the box's own power.
///
/// A box that is asleep still answers the network, so this is a plain toggle
/// rather than the wake-on-LAN dance a television needs.
class _PowerButton extends StatelessWidget {
  const _PowerButton({required this.controller});
  final RemoteController controller;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'הפעלה וכיבוי',
    child: InkResponse(
      radius: 26,
      onTap: controller.isConnected
          ? () {
              HapticFeedback.mediumImpact();
              controller.power();
            }
          : null,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Palette.dead.withValues(
            alpha: controller.isConnected ? 0.14 : 0.05,
          ),
        ),
        child: Icon(
          Icons.power_settings_new_rounded,
          size: 20,
          color: controller.isConnected
              ? Palette.dead
              : Palette.dead.withValues(alpha: 0.4),
        ),
      ),
    ),
  );
}

/// Choose which set or device the remote points at.
Future<void> _showTargetPicker(
  BuildContext context,
  RemoteController controller,
) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: Palette.surface,
  showDragHandle: true,
  useSafeArea: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.lg)),
  ),
  builder: (sheetContext) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Center(
              child: Text(
                'במה לשלוט',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          for (final target in controller.targets)
            Raised(
              radius: Radii.md,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              onTap: () {
                Navigator.pop(sheetContext);
                controller.select(target);
              },
              child: Row(
                spacing: 10,
                children: [
                  Icon(
                    target.isRoom ? Icons.link_rounded : Icons.tv_rounded,
                    size: 19,
                    color: target.id == controller.current?.id
                        ? Palette.amber
                        : Palette.inkDim,
                  ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          target.name,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        Text(
                          target.isRoom
                              ? '${target.source?.name} + ${target.display?.name}'
                              : target.devices.firstOrNull?.host ?? '',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Palette.inkDim,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (target.id == controller.current?.id)
                    const Icon(
                      Icons.check_rounded,
                      size: 19,
                      color: Palette.amber,
                    ),
                ],
              ),
            ),
        ],
      ),
    ),
  ),
);

/// Offers a newer build.
///
/// Sideloaded apps have nothing telling a person a new version exists, so the
/// app says so itself and links straight at the file.
class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner({required this.update});
  final AvailableUpdate update;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
    decoration: BoxDecoration(
      color: Palette.amberWash,
      borderRadius: BorderRadius.circular(Radii.md),
    ),
    child: Row(
      spacing: 12,
      children: [
        const Icon(
          Icons.system_update_alt_rounded,
          size: 20,
          color: Palette.amber,
        ),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'גרסה ${update.version} זמינה',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
              const Text(
                'ההורדה תיפתח בדפדפן',
                style: TextStyle(fontSize: 11, color: Palette.inkDim),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: () async {
            final uri = Uri.parse(update.downloadUrl);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          child: const Text('עדכן', style: TextStyle(color: Palette.amber)),
        ),
      ],
    ),
  );
}
