part of 'app_controller.dart';

extension SourceController on AppController {
  Future<Analysis> _analyzeSourceV2(
    LibraryItem item,
    LibraryItem original,
    AppSettings settings,
    List<LibraryItem> related,
  ) async {
    final understanding = SourceUnderstandingService(intelligence);
    final summaries = <SourceSegmentSummary>[];
    final lifecycle = _lifecycleRevision;
    final version = item.contentVersion;
    final rawFingerprint = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              item.title,
              item.body,
              item.contentBlocks.map((b) => b.toJson()).toList(),
              version,
            ]),
          ),
        )
        .toString();
    void guard() {
      _guard(lifecycle);
      _requireActive(item);
      if (item.contentVersion != version ||
          sha256
                  .convert(
                    utf8.encode(
                      jsonEncode([
                        item.title,
                        item.body,
                        item.contentBlocks.map((b) => b.toJson()).toList(),
                        version,
                      ]),
                    ),
                  )
                  .toString() !=
              rawFingerprint) {
        throw const DiagnosticCancelled();
      }
      DiagnosticScope.ensureAllowed();
    }

    void persist(SourceSegmentSummary summary) {
      guard();
      _commitBusiness((draft) {
        draft.segmentSummaries.removeWhere((s) => s.id == summary.id);
        draft.segmentSummaries.add(
          SourceSegmentSummary.fromJson(summary.toJson()),
        );
      });
      _saveCheckpoint('已保存原文片段摘要', {
        'segmentIds': summaries.map((s) => s.id).toList(),
      });
    }

    if (item.kind == ItemKind.pdf) {
      final path = assetPath(item.assets.first);
      final assetFingerprint = sha256
          .convert(await File(path).readAsBytes())
          .toString();
      guard();
      var page = 0, total = item.pdfPageCount ?? 1;
      while (page < total) {
        guard();
        if (sha256.convert(await File(path).readAsBytes()).toString() !=
            assetFingerprint) {
          throw const DiagnosticCancelled();
        }
        final rendered = await native.renderPdf(
          path,
          startPage: page,
          maxPages: 4,
        );
        guard();
        total = rendered.pageCount;
        if (total < 1 || rendered.images.isEmpty) {
          throw const FormatException('PDF 没有可分析的页面');
        }
        if (total > 100) {
          throw const FormatException('当前支持100页以内PDF，请拆分后导入；原文件已保留');
        }
        item.pdfPageCount = total;
        final fingerprint = understanding.pdfFingerprint(
          original,
          page + 1,
          rendered.images,
          assetFingerprint,
        );
        var summary = data.segmentSummaries
            .where(
              (s) =>
                  s.sourceId == item.id &&
                  s.sourceVersion == version &&
                  s.promptVersion == SourceUnderstandingService.promptVersion &&
                  s.fingerprint == fingerprint,
            )
            .firstOrNull;
        if (summary == null) {
          _saveCheckpoint('理解 PDF 第 ${page + 1} 页起', {'requestPending': true});
          summary = await understanding.summarizePdf(
            settings,
            _apiKey,
            original,
            page + 1,
            rendered.images,
            assetFingerprint,
          );
          guard();
          summaries.add(summary);
          persist(summary);
        } else {
          summaries.add(summary);
        }
        page += rendered.images.length;
        _saveCheckpoint('PDF $page / $total 页', {
          'requestPending': false,
          'completed': page,
          'total': total,
        });
      }
    } else {
      final windows = <SourceWindow>[];
      final chunkChars = (settings.modelTextContextChars ~/ 12).clamp(
        400,
        1600,
      );
      for (final block in KnowledgeService.contentBlocksForItem(original)) {
        final text = block['text'] as String;
        var start = 0;
        while (start < text.length) {
          var end = (start + chunkChars).clamp(0, text.length);
          if (end < text.length &&
              end > start &&
              text.codeUnitAt(end - 1) >= 0xd800 &&
              text.codeUnitAt(end - 1) <= 0xdbff &&
              text.codeUnitAt(end) >= 0xdc00 &&
              text.codeUnitAt(end) <= 0xdfff) {
            end--;
          }
          final window = readSourceWindow(
            original,
            block['id'] as String,
            start,
            end,
          );
          windows.add(window);
          start = window.end;
        }
      }
      final segments = understanding.segmentWindows(
        windows,
        maxChars: chunkChars,
      );
      for (var index = 0; index < segments.length; index++) {
        guard();
        final segment = segments[index];
        final fingerprint = understanding.textFingerprint(original, segment);
        var summary = data.segmentSummaries
            .where(
              (s) =>
                  s.sourceId == item.id &&
                  s.sourceVersion == version &&
                  s.promptVersion == SourceUnderstandingService.promptVersion &&
                  s.fingerprint == fingerprint,
            )
            .firstOrNull;
        if (summary == null) {
          _saveCheckpoint('理解原文 ${index + 1} / ${segments.length} 段', {
            'requestPending': true,
          });
          summary = await understanding.summarizeText(
            settings,
            _apiKey,
            original,
            segment,
          );
          guard();
          summaries.add(summary);
          persist(summary);
        } else {
          summaries.add(summary);
        }
        _saveCheckpoint('原文 ${index + 1} / ${segments.length} 段', {
          'requestPending': false,
          'completed': index + 1,
          'total': segments.length,
        });
      }
    }
    guard();
    _saveCheckpoint('层次合并原文摘要', {'requestPending': true});
    final combinedText = await understanding.mergeSummaries(
      settings,
      _apiKey,
      summaries,
    );
    guard();
    final evidence = <EvidenceAnchor>[];
    final allEvidence = summaries.expand((s) => s.evidence).toList();
    final count = allEvidence.length.clamp(0, 12);
    for (var index = 0; index < count; index++) {
      final position = count == 1
          ? 0
          : (index * (allEvidence.length - 1) / (count - 1)).round();
      final compact = EvidenceAnchor.fromJson(allEvidence[position].toJson());
      if (compact.quote.length > 160) {
        compact.quote = compact.quote.substring(0, 160);
      }
      evidence.add(compact);
    }
    final combined = LibraryItem.fromJson(original.toJson())
      ..body = combinedText
      ..contentBlocks = [];
    _saveCheckpoint('综合资料认识', {'requestPending': false});
    return _analyzeWithTrace(
      settings,
      _apiKey,
      combined,
      related,
      availableEvidence: evidence,
    );
  }
}
