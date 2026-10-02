import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:url_launcher/url_launcher.dart';

import '../data/controller.dart';
import '../protocol/androidtv/remote.dart';
import '../data/updates.dart';
import 'rooms_page.dart';
import 'theme.dart';
import 'typing_page.dart';
import 'widgets/controls.dart';
import 'widgets/dpad.dart';
import 'widgets/remote_keys.dart';

/// The remote, in whichever arrangement the settings pick.
///
/// All three show the same commands; they differ in what is on screen at once
/// and how you navigate. Classic is the default because it reads like the
/// plastic remote everyone already knows.
class RemotePage extends StatefulWidget {
  const RemotePage({super.key, required this.controller, this.onOpenApps});
  final RemoteController controller;

  /// Shows the full app list, for the "more" tile.
  final VoidCallback? onOpenApps;

  @override
  State<RemotePage> createState() => _RemotePageState();
}

class _RemotePageState extends State<RemotePage> {
  RemoteController get c => widget.controller;

  /// The section the modes layout is showing.
  String _mode = 'nav';

  static const _modes = [
    ('nav', 'ניווט'),
    ('watch', 'צפייה'),
    ('numbers', 'מספרים'),
  ];

  void _openTyping() => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => TypingPage(controller: c)));

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

    final body = switch (c.remoteLayout) {
      'touchpad' => _touchpad(live),
      'modes' => _modesLayout(live),
      _ => _classic(live),
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      children: [
        if (c.update case final update?) ...[
          _UpdateBanner(update: update),
          const SizedBox(height: 10),
        ],
        _Header(controller: c),
        const SizedBox(height: 14),
        ...body,
        const SizedBox(height: 16),
        _secondaryKeys(live),
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

  /* ---------------- classic ---------------- */

  /// Everything on one screen, laid out like a physical remote: the four
  /// navigation companions in the corners around the ring, upright volume and
  /// channel rockers either side of the media keys, apps along the bottom.
  List<Widget> _classic(bool live) => [
    _CornerPad(controller: c, enabled: live),
    const SizedBox(height: 18),
    SizedBox(
      height: 156,
      child: Row(
        spacing: 12,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _volumeRocker(live),
          Expanded(child: _mediaGrid(live)),
          _channelRocker(live),
        ],
      ),
    ),
    const SizedBox(height: 16),
    _appRow(live),
  ];

  Widget _mediaGrid(bool live) {
    final muted = c.deviceState.muted ?? false;
    return Directionality(
      // Transport keys map to the direction time runs, not reading order.
      textDirection: TextDirection.ltr,
      child: Column(
        spacing: 10,
        children: [
          Expanded(
            child: Row(
              spacing: 10,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PadKey(
                  icon: Icons.fast_rewind_rounded,
                  label: 'הרץ אחורה',
                  enabled: live,
                  onTap: () => c.send('rewind'),
                ),
                PadKey(
                  icon: Icons.play_arrow_rounded,
                  label: 'נגן או השהה',
                  enabled: live,
                  accent: true,
                  onTap: () => c.send('playpause'),
                ),
                PadKey(
                  icon: Icons.fast_forward_rounded,
                  label: 'הרץ קדימה',
                  enabled: live,
                  onTap: () => c.send('forward'),
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              spacing: 10,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PadKey(
                  icon: Icons.keyboard_alt_outlined,
                  label: 'הקלדה בטלוויזיה',
                  enabled: live,
                  // Lit while a field is open on screen: that is the moment
                  // this key is worth pressing.
                  accent: c.remoteTextField != null,
                  onTap: _openTyping,
                ),
                PadKey(
                  icon: Icons.closed_caption_outlined,
                  label: 'כתוביות',
                  enabled: live,
                  onTap: () => c.send('captions'),
                ),
                PadKey(
                  icon: muted
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                  label: 'השתק',
                  enabled: live,
                  accent: muted,
                  onTap: () => _volume(context, c, 'mute'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _volumeRocker(bool live) => TallRocker(
    label: 'עוצמה',
    // Showing what the device actually reports separates "the command never
    // arrived" from "this device has no volume to give".
    value: _volumeReading(c.deviceState),
    enabled: live,
    upIcon: Icons.add_rounded,
    upLabel: 'הגבר עוצמה',
    onUp: () => _volume(context, c, 'volup'),
    downIcon: Icons.remove_rounded,
    downLabel: 'הנמך עוצמה',
    onDown: () => _volume(context, c, 'voldown'),
  );

  Widget _channelRocker(bool live) => TallRocker(
    label: 'ערוץ',
    enabled: live,
    upIcon: Icons.keyboard_arrow_up_rounded,
    upLabel: 'ערוץ הבא',
    onUp: () => c.send('chup'),
    downIcon: Icons.keyboard_arrow_down_rounded,
    downLabel: 'ערוץ קודם',
    onDown: () => c.send('chdown'),
  );

  /// Three saved apps and a way to the rest, always in the same four slots.
  Widget _appRow(bool live) {
    final apps = c.shortcuts().take(3).toList();
    return Row(
      spacing: 8,
      children: [
        for (final app in apps)
          AppTile(
            label: app.label,
            color: parseColor(app.color),
            enabled: live,
            onTap: () => c.launch(app.launch),
          ),
        for (var i = apps.length; i < 3; i++) const Spacer(),
        AppTile(
          label: 'עוד',
          icon: Icons.more_horiz_rounded,
          onTap: widget.onOpenApps ?? () {},
        ),
      ],
    );
  }

  /* ---------------- touchpad ---------------- */

  /// A wide surface to swipe on, with the navigation keys right under it.
  List<Widget> _touchpad(bool live) {
    final app = c.deviceState.currentApp;
    return [
      TouchSurface(
        enabled: live,
        onCommand: c.send,
        caption: app == null ? null : '${c.labelFor(app)} · פועל',
      ),
      const SizedBox(height: 12),
      Row(
        spacing: 8,
        children: [
          LabeledKey(
            icon: Icons.arrow_back_rounded,
            label: 'חזור',
            enabled: live,
            onTap: () => c.send('back'),
          ),
          LabeledKey(
            icon: Icons.home_rounded,
            label: 'בית',
            enabled: live,
            onTap: () => c.send('home'),
          ),
          LabeledKey(
            icon: Icons.menu_rounded,
            label: 'תפריט',
            enabled: live,
            onTap: () => c.send('menu'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _Transport(controller: c, enabled: live),
      const SizedBox(height: 10),
      _volumeRow(live),
      const SizedBox(height: 18),
      _AppShelf(controller: c, enabled: live),
      const SizedBox(height: 16),
      _TypingCard(controller: c, enabled: live, onTap: _openTyping),
    ];
  }

  /// Volume, mute and channel side by side.
  Widget _volumeRow(bool live, {bool channel = true}) => Row(
    spacing: 8,
    children: [
      Rocker(
        label: 'עוצמה',
        value: _volumeReading(c.deviceState),
        enabled: live,
        onDown: () => _volume(context, c, 'voldown'),
        onUp: () => _volume(context, c, 'volup'),
      ),
      Raised(
        radius: 28,
        enabled: live,
        onTap: () => _volume(context, c, 'mute'),
        child: SizedBox(
          width: 56,
          height: 56,
          // The box reports its mute state, so show it rather than a fixed
          // icon — a control that never reflects reality is worse than no
          // indicator at all.
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
      if (channel)
        Rocker(
          label: 'ערוץ',
          enabled: live,
          onDown: () => c.send('chdown'),
          onUp: () => c.send('chup'),
        ),
    ],
  );

  /* ---------------- modes ---------------- */

  /// One job at a time: navigating, watching, or entering a number. Volume
  /// stays put underneath whichever is showing.
  List<Widget> _modesLayout(bool live) => [
    ModeSwitch(
      value: _mode,
      options: _modes,
      onChanged: (mode) => setState(() => _mode = mode),
    ),
    const SizedBox(height: 16),
    // A fixed floor keeps the volume row from jumping between modes, so it
    // stays where the thumb learned it is.
    ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 400),
      child: Align(
        alignment: Alignment.topCenter,
        child: switch (_mode) {
          'watch' => _watchPanel(live),
          'numbers' => _numberPanel(live),
          _ => _navPanel(live),
        },
      ),
    ),
    const SizedBox(height: 14),
    _volumeRow(live, channel: false),
  ];

  Widget _navPanel(bool live) {
    final ring = (MediaQuery.sizeOf(context).width * 0.66).clamp(0.0, 260.0);
    return Column(
      children: [
        DPad(enabled: live, onCommand: c.send, size: ring),
        const SizedBox(height: 18),
        Row(
          spacing: 8,
          children: [
            IconKey(
              icon: Icons.arrow_back_rounded,
              label: 'חזור',
              enabled: live,
              onTap: () => c.send('back'),
            ),
            IconKey(
              icon: Icons.home_rounded,
              label: 'בית',
              enabled: live,
              onTap: () => c.send('home'),
            ),
            IconKey(
              icon: Icons.menu_rounded,
              label: 'תפריט',
              enabled: live,
              onTap: () => c.send('menu'),
            ),
            IconKey(
              icon: Icons.keyboard_alt_outlined,
              label: 'הקלדה בטלוויזיה',
              enabled: live,
              accent: c.remoteTextField != null,
              onTap: _openTyping,
            ),
          ],
        ),
        const SizedBox(height: 18),
        _AppShelf(controller: c, enabled: live),
      ],
    );
  }

  Widget _watchPanel(bool live) {
    final app = c.deviceState.currentApp;
    return Column(
      spacing: 20,
      children: [
        Text(
          app == null ? 'מה שמתנגן עכשיו' : 'מתנגן ב־${c.labelFor(app)}',
          style: const TextStyle(fontSize: 12, color: Palette.inkDim),
        ),
        _PlayButton(enabled: live, onTap: () => c.send('playpause')),
        SizedBox(
          height: 64,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              spacing: 8,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PadKey(
                  icon: Icons.skip_previous_rounded,
                  label: 'הקודם',
                  enabled: live,
                  onTap: () => c.send('prev'),
                ),
                PadKey(
                  icon: Icons.fast_rewind_rounded,
                  label: 'הרץ אחורה',
                  enabled: live,
                  onTap: () => c.send('rewind'),
                ),
                PadKey(
                  icon: Icons.fast_forward_rounded,
                  label: 'הרץ קדימה',
                  enabled: live,
                  onTap: () => c.send('forward'),
                ),
                PadKey(
                  icon: Icons.skip_next_rounded,
                  label: 'הבא',
                  enabled: live,
                  onTap: () => c.send('next'),
                ),
              ],
            ),
          ),
        ),
        Row(
          spacing: 8,
          children: [
            LabeledKey(
              icon: Icons.arrow_back_rounded,
              label: 'חזור',
              enabled: live,
              onTap: () => c.send('back'),
            ),
            LabeledKey(
              icon: Icons.closed_caption_outlined,
              label: 'כתוביות',
              enabled: live,
              onTap: () => c.send('captions'),
            ),
            LabeledKey(
              icon: Icons.info_outline_rounded,
              label: 'מידע',
              enabled: live,
              onTap: () => c.send('info'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _numberPanel(bool live) {
    Widget digit(String n) =>
        DigitKey(label: n, enabled: live, onTap: () => c.send('num$n'));

    return Row(
      spacing: 12,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Directionality(
            // A number pad reads left to right in every language.
            textDirection: TextDirection.ltr,
            child: Column(
              spacing: 8,
              children: [
                for (final row in const [
                  ['1', '2', '3'],
                  ['4', '5', '6'],
                  ['7', '8', '9'],
                ])
                  Row(spacing: 8, children: [for (final n in row) digit(n)]),
                Row(
                  spacing: 8,
                  children: [
                    DigitKey(
                      label: 'מחק',
                      icon: Icons.backspace_outlined,
                      enabled: live,
                      onTap: () => c.send('backspace'),
                    ),
                    digit('0'),
                    DigitKey(
                      label: 'אישור',
                      icon: Icons.keyboard_return_rounded,
                      enabled: live,
                      onTap: () => c.send('enter'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Column(
          spacing: 8,
          children: [
            SizedBox(height: 208, child: _channelRocker(live)),
            Semantics(
              button: true,
              label: 'מדריך',
              child: Raised(
                radius: 20,
                enabled: live,
                onTap: () => c.send('guide'),
                child: const SizedBox(
                  width: 68,
                  height: 64,
                  child: Icon(
                    Icons.grid_view_rounded,
                    size: 20,
                    color: Palette.amber,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /* ---------------- shared ---------------- */

  Widget _secondaryKeys(bool live) => Row(
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
  );
}

/// The ring with back, home, menu and guide in its four corners.
///
/// The corners are otherwise dead space beside a circle, and putting the four
/// keys there frees the whole row they used to take above it.
class _CornerPad extends StatelessWidget {
  const _CornerPad({required this.controller, required this.enabled});
  final RemoteController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width.clamp(0.0, 420.0);
    final ring = (width * 0.66).clamp(0.0, 270.0);

    CornerKey corner(IconData icon, String label, String command) => CornerKey(
      icon: icon,
      label: label,
      enabled: enabled,
      onTap: () => controller.send(command),
    );

    return SizedBox(
      height: ring + 24,
      child: Stack(
        alignment: Alignment.center,
        children: [
          DPad(enabled: enabled, onCommand: controller.send, size: ring),
          Align(
            alignment: AlignmentDirectional.topStart,
            child: corner(Icons.arrow_back_rounded, 'חזור', 'back'),
          ),
          Align(
            alignment: AlignmentDirectional.topEnd,
            child: corner(Icons.home_rounded, 'בית', 'home'),
          ),
          Align(
            alignment: AlignmentDirectional.bottomStart,
            child: corner(Icons.menu_rounded, 'תפריט', 'menu'),
          ),
          Align(
            alignment: AlignmentDirectional.bottomEnd,
            child: corner(Icons.grid_view_rounded, 'מדריך', 'guide'),
          ),
        ],
      ),
    );
  }
}

/// The one big key of the watching mode.
class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.onTap, this.enabled = true});
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'נגן או השהה',
    child: Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GestureDetector(
        onTap: enabled
            ? () {
                HapticFeedback.mediumImpact();
                onTap();
              }
            : null,
        child: Container(
          width: 136,
          height: 136,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF2BC5C), Palette.amber, Palette.amberDeep],
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x47E9A93F),
                blurRadius: 30,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: const Icon(
            Icons.play_arrow_rounded,
            size: 52,
            color: Color(0xFF2A1D08),
          ),
        ),
      ),
    ),
  );
}

/// The way into typing, lit when the screen has a field waiting for text.
class _TypingCard extends StatelessWidget {
  const _TypingCard({
    required this.controller,
    required this.enabled,
    required this.onTap,
  });

  final RemoteController controller;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Typing gets its own screen rather than a field wedged into the remote:
    // the phone keyboard covers half the display, and a field under it is a
    // field you cannot see while typing into it.
    final open = controller.remoteTextField != null;
    return Raised(
      enabled: enabled,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(
            Icons.keyboard_alt_outlined,
            size: 19,
            color: open ? Palette.amber : Palette.inkDim,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              open ? 'שדה טקסט פתוח על המסך — הקש כאן' : 'הקלדה בטלוויזיה',
              style: TextStyle(
                fontSize: 13,
                fontWeight: open ? FontWeight.w600 : FontWeight.w400,
                color: open ? Palette.ink : Palette.inkMid,
              ),
            ),
          ),
          const Icon(
            Icons.chevron_left_rounded,
            size: 18,
            color: Palette.inkDim,
          ),
        ],
      ),
    );
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

/// What the device says its volume is. A box that passes HDMI audio through
/// untouched reports a maximum of zero — worth showing, because it explains why
/// the volume keys are silent without leaving the user guessing.
String? _volumeReading(RemoteState state) {
  final max = state.volumeMax;
  final level = state.volumeLevel;
  if (max == null || level == null) return null;
  if (max == 0) return 'אין';
  return '$level';
}

/// A box that reports no volume scale swallows volume keys silently. Send the
/// command anyway — some devices act on it without reporting — but say once
/// what is going on, because silence here reads as a broken app.
void _volume(BuildContext context, RemoteController c, String command) {
  c.send(command);
  if (c.deviceState.volumeMax != 0 || c.current?.display != null) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.clearSnackBars();
  messenger?.showSnackBar(
    SnackBar(
      content: const Text(
        'הממיר מדווח שאין לו סקאלת עוצמה, כי הוא מוסר אותה לטלוויזיה ב-CEC '
        'והיא לא מיישמת את זה. בהגדרות הממיר: HDMI-CEC ← בקרת עוצמה ← כבוי. '
        'לחלופין צרף את הטלוויזיה לסט ושלוט בעוצמה דרכה.',
      ),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(14),
      duration: const Duration(seconds: 6),
      action: SnackBarAction(
        label: 'לסטים',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => RoomsPage(controller: c)),
        ),
      ),
    ),
  );
}
