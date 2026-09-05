import 'package:flutter/material.dart';

import '../data/shared_data.dart';
import 'theme.dart';

/// The explanations, rendered from `shared/help.json`.
///
/// Every one of these answers a question the hardware raises rather than the
/// app: why pairing exists, why the volume keys can be silent, why an old
/// television still obeys. Keeping them here rather than only in a README is
/// the difference between an answer and a search.
class HelpPage extends StatelessWidget {
  const HelpPage({super.key, this.openSection});

  /// Section id to expand on arrival, when the user came from a "why?" link.
  final String? openSection;

  @override
  Widget build(BuildContext context) {
    final sections = SharedData.instance.helpSections;
    return Scaffold(
      appBar: AppBar(title: const Text('עזרה')),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
        itemCount: sections.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final section = sections[index];
          return _Section(
            title: '${section['title']}',
            blocks: (section['blocks'] as List).cast<Map<String, dynamic>>(),
            startOpen: section['id'] == openSection,
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.blocks,
    required this.startOpen,
  });

  final String title;
  final List<Map<String, dynamic>> blocks;
  final bool startOpen;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Palette.surface,
      borderRadius: BorderRadius.circular(Radii.sm),
    ),
    child: Theme(
      // The default divider draws a line across a rounded card.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: startOpen,
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        iconColor: Palette.amber,
        collapsedIconColor: Palette.inkDim,
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
        ),
        children: [for (final block in blocks) _block(block)],
      ),
    ),
  );

  Widget _block(Map<String, dynamic> block) {
    if (block['p'] != null) return _Paragraph('${block['p']}');
    if (block['note'] != null) {
      return _Paragraph('${block['note']}', dim: true);
    }
    if (block['ul'] != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in (block['ul'] as List).cast<String>())
            _Bullet(item),
        ],
      );
    }
    if (block['table'] != null) {
      return _Table((block['table'] as List).cast<List<dynamic>>());
    }
    return const SizedBox.shrink();
  }
}

/// `*emphasis*` is the only markup the shared file carries, so one sentence can
/// be rendered by an HTML page and by a widget without keeping two copies.
List<TextSpan> _spans(String text) {
  final spans = <TextSpan>[];
  var bold = false;
  for (final piece in text.split('*')) {
    if (piece.isNotEmpty) {
      spans.add(
        TextSpan(
          text: piece,
          style: bold ? const TextStyle(fontWeight: FontWeight.w600) : null,
        ),
      );
    }
    bold = !bold;
  }
  return spans;
}

class _Paragraph extends StatelessWidget {
  const _Paragraph(this.text, {this.dim = false});
  final String text;
  final bool dim;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text.rich(
      TextSpan(children: _spans(text)),
      style: TextStyle(
        fontSize: 12.5,
        height: 1.65,
        color: dim ? Palette.inkDim : Palette.inkMid,
      ),
    ),
  );
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 7),
          child: SizedBox(
            width: 5,
            height: 5,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Palette.amber,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(children: _spans(text)),
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.6,
              color: Palette.inkMid,
            ),
          ),
        ),
      ],
    ),
  );
}

class _Table extends StatelessWidget {
  const _Table(this.rows);
  final List<List<dynamic>> rows;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Text.rich(
                    TextSpan(children: _spans('${row[0]}')),
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: Palette.inkMid,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Text.rich(
                    TextSpan(children: _spans('${row[1]}')),
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                      color: Palette.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
