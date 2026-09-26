import 'package:flutter/material.dart';

import 'common.dart';

class ReadingSectionData {
  const ReadingSectionData({required this.title, required this.body});

  final String title;
  final String body;
}

class ReadingContent extends StatelessWidget {
  const ReadingContent({
    super.key,
    this.title,
    this.brief,
    this.sections = const <ReadingSectionData>[],
    this.fallback = '',
    this.sources = const <String>[],
    this.labelForSource,
    this.fontScale = 1,
    this.emptyText = '暂无内容',
    this.legacyLabel,
    this.initiallyExpandFallback = false,
  });

  final String? title;
  final String? brief;
  final List<ReadingSectionData> sections;
  final String fallback;
  final List<String> sources;
  final String Function(String source)? labelForSource;
  final double fontScale;
  final String emptyText;
  final String? legacyLabel;
  final bool initiallyExpandFallback;

  @override
  Widget build(BuildContext context) {
    final visibleSections = sections
        .map(_sectionWithBody)
        .where((section) => section.body.trim().isNotEmpty)
        .toList(growable: false);
    final hasStructured =
        _clean(brief).isNotEmpty || visibleSections.isNotEmpty;
    final legacy = _clean(fallback);
    final layout = ReadingLayout.of(context);
    final bodyStyle = Theme.of(context).textTheme.bodyLarge
        ?.copyWith(fontSize: 17 * fontScale, height: layout.bodyHeight);
    if (!hasStructured && legacy.isEmpty) {
      return SelectableText(emptyText, style: bodyStyle);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_clean(title).isNotEmpty) ...[
          Text(
            _clean(title),
            style: Theme.of(context).textTheme.titleSmall
                ?.copyWith(fontSize: layout.sectionTitleSize * fontScale),
          ),
          SizedBox(height: layout.rowPadding),
        ],
        if (_clean(brief).isNotEmpty)
          _LeadParagraph(
            text: readerCitationText(
              _clean(brief),
              sources,
              labelForSource: labelForSource,
            ),
            fontScale: fontScale,
          ),
        if (visibleSections.isNotEmpty) ...[
          if (_clean(brief).isNotEmpty) SizedBox(height: layout.sectionGap),
          for (final entry in visibleSections.indexed) ...[
            _ReadableSection(
              index: entry.$1,
              title: entry.$2.title,
              body: readerCitationText(
                entry.$2.body,
                sources,
                labelForSource: labelForSource,
              ),
              fontScale: fontScale,
            ),
            if (entry.$1 != visibleSections.length - 1)
              SizedBox(height: layout.sectionGap),
          ],
        ],
        if (legacy.isNotEmpty &&
            (!hasStructured ||
                legacyLabel != null ||
                _clean(brief).isNotEmpty)) ...[
          if (hasStructured) SizedBox(height: layout.sectionGap),
          _LegacyDisclosure(
            label: legacyLabel ?? '完整内容',
            text: readerCitationText(
              legacy,
              sources,
              labelForSource: labelForSource,
            ),
            fontScale: fontScale,
            initiallyExpanded: initiallyExpandFallback,
            showPreview: _clean(brief).isEmpty,
          ),
        ],
      ],
    );
  }
}

class _LeadParagraph extends StatelessWidget {
  const _LeadParagraph({required this.text, required this.fontScale});

  final String text;
  final double fontScale;

  @override
  Widget build(BuildContext context) {
    final layout = ReadingLayout.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            width: 3,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(left: layout.rowPadding),
        child: SelectableText(
          text,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontSize: 18 * fontScale,
            height: layout.bodyHeight,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _ReadableSection extends StatelessWidget {
  const _ReadableSection({
    required this.index,
    required this.title,
    required this.body,
    required this.fontScale,
  });

  final int index;
  final String title;
  final String body;
  final double fontScale;

  @override
  Widget build(BuildContext context) {
    final layout = ReadingLayout.of(context);
    final heading = title.trim().isEmpty ? '第 ${index + 1} 节' : title.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReadingHeading(heading, fontScale: fontScale),
        SizedBox(height: layout.rowPadding * 0.6),
        SelectableText(
          body,
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(fontSize: 17 * fontScale, height: layout.bodyHeight),
        ),
      ],
    );
  }
}

class _LegacyDisclosure extends StatelessWidget {
  const _LegacyDisclosure({
    required this.label,
    required this.text,
    required this.fontScale,
    required this.initiallyExpanded,
    required this.showPreview,
  });

  final String label;
  final String text;
  final double fontScale;
  final bool initiallyExpanded;
  final bool showPreview;

  @override
  Widget build(BuildContext context) {
    final layout = ReadingLayout.of(context);
    final preview = _clean(text).split(RegExp(r'\s+')).join(' ');
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      initiallyExpanded: initiallyExpanded,
      title: Text(label),
      subtitle: initiallyExpanded || !showPreview
          ? null
          : Text(preview, maxLines: 5, overflow: TextOverflow.ellipsis),
      childrenPadding: EdgeInsets.only(bottom: layout.rowPadding),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SelectableText(
            text,
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(fontSize: 17 * fontScale, height: layout.bodyHeight),
          ),
        ),
      ],
    );
  }
}

String _clean(String? value) => value?.trim() ?? '';

ReadingSectionData _sectionWithBody(ReadingSectionData section) {
  if (section.body.trim().isNotEmpty) return section;
  if (section.title.trim().isEmpty) return section;
  return ReadingSectionData(title: '', body: section.title.trim());
}

List<ReadingSectionData> sectionsFromPresentation(Object? presentation) {
  if (presentation is! Map) return const <ReadingSectionData>[];
  final rawSections = presentation['sections'];
  if (rawSections is! List) return const <ReadingSectionData>[];
  return rawSections
      .whereType<Map>()
      .map(
        (section) => ReadingSectionData(
          title: (section['title'] as String? ?? '').trim(),
          body: (section['body'] as String? ?? '').trim(),
        ),
      )
      .map(_sectionWithBody)
      .where((section) => section.body.isNotEmpty)
      .toList(growable: false);
}

String briefFromPresentation(Object? presentation) {
  if (presentation is! Map) return '';
  return (presentation['brief'] as String? ?? '').trim();
}

String stringField(Map<String, dynamic> json, String key) {
  return (json[key] as String? ?? '').trim();
}
