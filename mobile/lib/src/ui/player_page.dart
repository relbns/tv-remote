import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/device.dart';
import '../platform/pip.dart';
import 'theme.dart';

/// Watch a channel on the phone itself.
///
/// This plays the live stream the broadcaster publishes openly — the same feed
/// their own site serves, with no token and no encryption. It exists only for
/// the channels where that was verified; the rest open the broadcaster's page
/// instead, because their streams are delivered protected and the only open
/// copies are unauthorised rebroadcasts.
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.channel});

  final Channel channel;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  VideoPlayerController? _controller;
  String? _failure;
  bool _pipSupported = false;

  /// Set once the video has been in a floating window, and kept until the app
  /// is fully back — closing that window stops the activity, and by then the
  /// system may already have reported that picture-in-picture ended.
  bool _wasInPip = false;

  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    Pip.active.addListener(_onPip);
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
    _open();
  }

  Future<void> _open() async {
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.channel.stream!),
    );
    _controller = controller;
    try {
      await controller.initialize();
      await controller.play();
      // Live television with the screen going dark is not television.
      await WakelockPlus.enable();
      // The stream is landscape; so is watching it.
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

      _pipSupported = await Pip.isSupported();
      // Leaving the app while a channel plays shrinks it into a window rather
      // than stopping it, which is what someone watching actually wants.
      if (_pipSupported) {
        await Pip.setAutoEnter(true, controller.value.size);
      }
    } on Object catch (failure) {
      _failure = '$failure';
    }
    if (mounted) setState(() {});
  }

  void _onPip() {
    if (Pip.active.value) _wasInPip = true;
    if (mounted) setState(() {});
  }

  void _onLifecycle(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _wasInPip = false;
    } else if (state == AppLifecycleState.paused && _wasInPip) {
      // A floating window that is visible leaves the activity paused, not
      // stopped; reaching "paused" here means the user closed it. The player
      // has already stopped, so leave the page too — otherwise opening the
      // app later would resume a channel nobody asked for.
      if (mounted) Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    Pip.active.removeListener(_onPip);
    _lifecycle.dispose();
    // The rest of the app has nothing to shrink.
    Pip.setAutoEnter(false);
    _controller?.dispose();
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;

    // In the floating window there is room for the picture and nothing else;
    // controls there would be too small to hit and would cover the programme.
    if (Pip.active.value && ready) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: switch ((ready, _failure)) {
              (true, _) => AspectRatio(
                aspectRatio: controller!.value.aspectRatio,
                child: VideoPlayer(controller),
              ),
              (_, final String message) => Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.wifi_off_rounded,
                      color: Palette.inkDim,
                      size: 30,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'השידור לא נטען',
                      style: TextStyle(color: Palette.ink, fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Palette.inkDim,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              _ => const CircularProgressIndicator(color: Palette.amber),
            },
          ),
          SafeArea(
            child: Align(
              alignment: AlignmentDirectional.topStart,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                      color: Colors.white,
                      tooltip: 'סגירה',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                      ),
                    ),
                    if (_pipSupported && ready) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => Pip.enter(controller.value.size),
                        icon: const Icon(Icons.picture_in_picture_alt_rounded),
                        color: Colors.white,
                        tooltip: 'תמונה בתוך תמונה',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black54,
                        ),
                      ),
                    ],
                    const SizedBox(width: 10),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Text(
                          widget.channel.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
