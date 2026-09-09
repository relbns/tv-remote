import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/controller.dart';
import 'theme.dart';

/// Type into whatever field the box has focus in.
///
/// The protocol's text edit carries the whole value, not a keystroke, so every
/// character typed here replaces the field on screen. That is what makes it
/// feel like a keyboard for the television rather than a form to submit.
class TypingPage extends StatefulWidget {
  const TypingPage({super.key, required this.controller});

  final RemoteController controller;

  @override
  State<TypingPage> createState() => _TypingPageState();
}

class _TypingPageState extends State<TypingPage> {
  late final TextEditingController _text = TextEditingController(
    text: widget.controller.remoteTextField ?? '',
  );
  final _focus = FocusNode();

  RemoteController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    // The keyboard is the reason this screen exists; opening it should not
    // cost another tap.
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('הקלדה'),
      actions: [
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
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 17),
            decoration: const InputDecoration(
              hintText: 'הקלד, וזה יופיע על המסך',
            ),
            // Every character replaces the field on the television, so the two
            // stay identical without a send step.
            onChanged: c.typeInto,
            onSubmitted: (value) async {
              await c.typeInto(value);
              await c.send('enter');
              if (context.mounted) Navigator.of(context).pop();
            },
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
                  onPressed: () async {
                    HapticFeedback.selectionClick();
                    await c.typeInto(_text.text);
                    await c.send('enter');
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: const Text('חפש'),
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
          const Text(
            'הטקסט נשלח תוך כדי הקלדה, כך שמה שמופיע על המסך זהה למה שכאן. '
            'אפשר גם למחוק — המחיקה נשלחת באותו אופן.',
            style: TextStyle(
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
