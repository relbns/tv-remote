import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'src/data/controller.dart';
import 'src/data/device.dart';
import 'src/data/shared_data.dart';
import 'src/ui/apps_page.dart';
import 'src/ui/devices_page.dart';
import 'src/ui/remote_page.dart';
import 'src/ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Android 15 draws every app behind the system bars. Make them transparent
  // and let SafeArea inset the content, rather than fighting the platform.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  final shared = await SharedData.load();
  final store = await DeviceStore.open();
  final controller = RemoteController(store, shared);
  await controller.refreshPaired();
  await controller.load();

  runApp(TvRemoteApp(controller: controller));
}

class TvRemoteApp extends StatelessWidget {
  const TvRemoteApp({super.key, required this.controller});
  final RemoteController controller;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'שלט טלוויזיה',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    // Real localisation rather than a Directionality around the home widget:
    // a pushed route is a new route at this level and would not inherit it, so
    // every screen opened with Navigator.push came up left-to-right.
    locale: const Locale('he'),
    supportedLocales: const [Locale('he'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: HomeShell(controller: controller),
  );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.controller});
  final RemoteController controller;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int _tab = widget.controller.defaultTab;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      return Scaffold(
        // IndexedStack keeps every tab alive. Swapping widgets instead would
        // throw away each page's state on every switch — which is what made
        // discovery results vanish the moment you looked at the remote.
        body: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: _tab,
            children: [
              RemotePage(controller: widget.controller),
              AppsPage(controller: widget.controller),
              DevicesPage(controller: widget.controller),
            ],
          ),
        ),
        bottomNavigationBar: _TabBar(
          index: _tab,
          onChanged: (index) => setState(() => _tab = index),
        ),
      );
    },
  );
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.index, required this.onChanged});
  final int index;
  final ValueChanged<int> onChanged;

  static const _items = [
    (Icons.settings_remote_rounded, 'שלט'),
    (Icons.apps_rounded, 'אפליקציות'),
    (Icons.tv_rounded, 'מכשירים'),
  ];

  @override
  Widget build(BuildContext context) => Container(
    color: Palette.groundLift,
    padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
    child: SafeArea(
      top: false,
      child: Row(
        children: [
          for (var i = 0; i < _items.length; i++)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(Radii.sm),
                onTap: () {
                  HapticFeedback.selectionClick();
                  onChanged(i);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: i == index ? Palette.amberWash : null,
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 4,
                    children: [
                      Icon(
                        _items[i].$1,
                        size: 21,
                        color: i == index ? Palette.amber : Palette.inkDim,
                      ),
                      Text(
                        _items[i].$2,
                        style: TextStyle(
                          fontSize: 11,
                          color: i == index ? Palette.amber : Palette.inkDim,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
