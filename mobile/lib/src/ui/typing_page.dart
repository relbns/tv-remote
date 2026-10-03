import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/controller.dart';
import 'theme.dart';

/// Type into whatever field the television or box has focus in.
///
/// Where the device takes the whole value (Android TV, LG), every character
/// typed here replaces the field on screen, so it feels like a keyboard for
/// the television rather than a form to submit. Samsung only appends, so there
/// the text is composed here and sent in one go.
class TypingPage extends StatefulWidget {
  const TypingPage({
    super.key,
    required this.controller,
    this.openedByField = false,
  });

  final RemoteController controller;

  /// Opened because a field appeared on screen, not by a tap. Such a page also
  /// closes itself when that field goes away.
  final bool openedByField;

  /// Whether a typing page is on screen, so a field opening does not stack a
  /// second one on top of the first.
  static bool get isOpen => _open > 0;
  static int _open = 0;

  @override
  State<TypingPage> createState() => _TypingPageState();
}

class _TypingPageState extends State<TypingPage> {
  RemoteController get c => widget.controller;

  // Read once: a set could change its mind mid-word as states arrive, and a
  // page that switches between live and compose while typing loses text.
  late final bool _live = c.typingIsLive;

  late final TextEditingController _text = TextEditingController(
    // Appending devices would duplicate whatever is already in the field.
    text: _live ? c.remoteTextField ?? '' : '',
  );
  final _focus = FocusNode();
  bool _sawField = false;

  @override
  void initState() {
    super.initState();
    TypingPage._open++;
    _sawField = c.remoteTextField != null;
    c.addListener(_onController);
    // The keyboard is the reason this screen exists; opening it should not
    // cost another tap.
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    TypingPage._open--;
    c.removeListener(_onController);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Follow the field on screen: close with it when this page came up for it.
  void _onController() {
    final open = c.remoteTextField != null;
    if (open) {
      _sawField = true;
      return;
    }
    if (widget.openedByField && _sawField && mounted) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _send() async {
    HapticFeedback.selectionClick();
    await c.typeInto(_text.text);
    await c.submitText();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('הקלדה'),
      actions: [
        if (_live)
          TextButton(
            onPressed: () async {
              _text.clear();
              await c.typeInto('');
            },
            child: const Text(
              'נקה',
              style: TextStyle(fontSize: 12.5, color: Palette.inkDim),
            ),
          ),
      ],
    ),
    body: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _text,
            focusNode: _focus,
            autofocus: true,
            textInputAction: TextInputAction.send,
            style: const TextStyle(fontSize: 17),
            decoration: InputDecoration(
              hintText: _live
                  ? 'הקלד, וזה יופיע על המסך'
                  : 'הקלד כאן ושלח לטלוויזיה',
            ),
            // Every character replaces the field on the television, so the two
            // stay identical without a send step.
            onChanged: _live ? c.typeInto : null,
            onSubmitted: (_) => _send(),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Palette.amber,
                    foregroundColor: Palette.ground,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _send,
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text('שלח'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: () => c.send('back'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  side: const BorderSide(color: Palette.surfaceHigh),
                ),
                child: const Text(
                  'חזור',
                  style: TextStyle(fontSize: 13, color: Palette.inkMid),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _live
                ? 'הטקסט נשלח תוך כדי הקלדה, כך שמה שמופיע על המסך זהה למה '
                      'שכאן. אפשר גם למחוק — המחיקה נשלחת באותו אופן.'
                : 'המכשיר הזה מוסיף טקסט לשדה ואינו מחליף אותו, לכן הטקסט '
                      'נשלח פעם אחת, בלחיצה על "שלח".',
            style: const TextStyle(
              fontSize: 11.5,
              height: 1.6,
              color: Palette.inkDim,
            ),
          ),
        ],
      ),
    ),
  );
}
