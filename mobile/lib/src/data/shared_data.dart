import 'dart:convert';

import 'package:flutter/services.dart';

/// The key tables and app catalogue shared with the desktop client.
///
/// `tool/sync_shared.sh` copies these in from the repository's `shared/`
/// directory before a build, so a mapping cannot drift between platforms.
class SharedData {
  SharedData._(this._keys, this._apps, this._help);

  final Map<String, dynamic> _keys;
  final Map<String, dynamic> _apps;
  final Map<String, dynamic> _help;

  static SharedData? _instance;
  static SharedData get instance {
    final loaded = _instance;
    if (loaded == null) throw StateError('SharedData.load() לא נקרא');
    return loaded;
  }

  static Future<SharedData> load() async {
    final keys = jsonDecode(
      await rootBundle.loadString('assets/shared/keys.json'),
    );
    final apps = jsonDecode(
      await rootBundle.loadString('assets/shared/apps.json'),
    );
    final help = jsonDecode(
      await rootBundle.loadString('assets/shared/help.json'),
    );
    return _instance = SharedData._(
      keys as Map<String, dynamic>,
      apps as Map<String, dynamic>,
      help as Map<String, dynamic>,
    );
  }

  /// Help sections that apply to this platform, in the order they should show.
  List<Map<String, dynamic>> get helpSections => [
    for (final section in _help['sections'] as List)
      if ((section as Map<String, dynamic>)['only'] != 'desktop')
        section.cast<String, dynamic>(),
  ];

  /// Commands the screen half of a set should handle, when there is one.
  Set<String> get preferDisplay => {
    ...(_keys['routing']['preferDisplay'] as List).cast<String>(),
  };

  /// Command name to Android `KeyEvent` constant name.
  Map<String, String> get androidKeyNames => _plain(_keys['androidtv']);

  /// Command name to the button the webOS pointer socket expects.
  Map<String, String> get webosButtons => _plain(_keys['webos']['buttons']);

  /// Command name to the Samsung remote key constant (e.g. KEY_VOLUP).
  Map<String, String> get tizenKeys => _plain(_keys['tizen']);

  /// Command name to the SSAP endpoint that performs it.
  Map<String, String> get webosRequests => _plain(_keys['webos']['requests']);

  /// The starting shortcuts for a box, before any are learned.
  List<AppShortcut> get catalog => [
    for (final entry in _apps['catalog'] as List)
      AppShortcut(
        label: entry['label'] as String,
        launch: entry['androidLink'] as String,
        package: entry['package'] as String?,
        color: entry['color'] as String?,
      ),
  ];

  /// Recognisable names for packages the box reports running.
  Map<String, String> get friendlyNames => {
    for (final entry in _apps['catalog'] as List)
      entry['package'] as String: entry['label'] as String,
    ..._plain(_apps['friendlyNames']),
  };

  /// Launchers and system screens — never worth offering as a shortcut.
  Set<String> get ignoredPackages => {
    ...(_apps['ignoredPackages'] as List).cast<String>(),
  };

  /// Strip the `$comment` documentation keys the JSON carries for readers.
  static Map<String, String> _plain(dynamic map) => {
    for (final entry in (map as Map<String, dynamic>).entries)
      if (!entry.key.startsWith(r'$')) entry.key: entry.value as String,
  };
}

class AppShortcut {
  const AppShortcut({
    required this.label,
    required this.launch,
    this.package,
    this.color,
  });

  final String label;

  /// Brand colour for the shortcut tile, as `#RRGGBB`.
  final String? color;

  /// A deep link, or `intent:#Intent;package=…;end` for a learned package.
  final String launch;
  final String? package;

  Map<String, dynamic> toJson() => {
    'label': label,
    'launch': launch,
    if (package != null) 'package': package,
    if (color != null) 'color': color,
  };

  factory AppShortcut.fromJson(Map<String, dynamic> json) => AppShortcut(
    label: json['label'] as String,
    launch: json['launch'] as String,
    package: json['package'] as String?,
    color: json['color'] as String?,
  );

  /// What to send for a package we have no catalogue entry for. The box
  /// resolves the string itself, so an intent URI naming the package is the
  /// only handle available.
  static String launchTargetFor(String package, Map<String, String> catalog) =>
      catalog[package] ?? 'intent:#Intent;package=$package;end';
}
