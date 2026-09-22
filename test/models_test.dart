import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/models.dart';

void main() {
  test('restoring a snapshot retains original content, citations and tracking scope', () {
    final data = AppData();
    data.items.add(
      LibraryItem(
        id: 'i1',
        title: '读书',
        kind: ItemKind.text,
        body: '原文',
        notes: '适用条件',
        analysis: Analysis(
          summary: '认识',
          insights: ['有条件适用'],
          sourceIds: ['i1'],
        ),
      ),
    );
    data.topics.add(
      Topic(
        id: 't1',
        title: '知识管理',
        question: '如何积累认识？',
        tracking: true,
        authorizedScope: '如何积累认识？',
        callLimit: 4,
      ),
    );
    final restored = AppData.fromJson(data.toJson());
    expect(restored.items.single.body, '原文');
    expect(restored.items.single.analysis!.sourceIds, ['i1']);
    expect(restored.topics.single.authorizedScope, '如何积累认识？');
    expect(restored.topics.single.tracking, isTrue);
    expect(restored.topics.single.callLimit, 4);
  });

  test(
    'preferences keep explicit interests separate from inferred attention',
    () {
      final settings = AppSettings(
        explicitInterests: ['适用条件'],
        inferredInterests: ['笔记工具'],
      );
      final copy = AppSettings.fromJson(settings.toJson());
      expect(copy.explicitInterests, ['适用条件']);
      expect(copy.inferredInterests, ['笔记工具']);
      expect(
        copy.toJson().keys.any((key) => key.toLowerCase().contains('key')),
        isFalse,
      );
    },
  );

  test('unknown backup schema is rejected instead of silently losing data', () {
    expect(() => AppData.fromJson({'version': 999}), throwsFormatException);
  });
}
