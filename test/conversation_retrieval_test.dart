import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/core/retrieval.dart';

void main() {
  test('retrieves bounded source windows with stable offsets and fingerprints', () {
    final item = LibraryItem(
      id: 'src',
      title: '长文',
      kind: ItemKind.text,
      contentVersion: 3,
      contentBlocks: [
        ContentBlock(
          id: 'body-1',
          kind: ContentBlockKind.paragraph,
          text:
              '${List.filled(900, '开头背景').join()} 关键证据在这里，说明模型不应该读取整篇。 ${List.filled(900, '结尾背景').join()}',
        ),
      ],
    );

    final windows = retrieveSourceWindows([item], '关键证据', charBudget: 500);

    expect(windows, hasLength(1));
    final window = windows.single;
    expect(window.sourceId, 'src');
    expect(window.sourceVersion, 3);
    expect(window.blockId, 'body-1');
    expect(window.text, contains('关键证据在这里'));
    expect(window.text.length, lessThanOrEqualTo(500));
    expect(window.start, greaterThan(0));
    expect(window.end, lessThan(item.contentBlocks.single.text.length));
    expect(window.id, contains('src:3:body-1:${window.start}:${window.end}'));

    final reread = readSourceWindow(
      item,
      window.blockId,
      window.start,
      window.end,
      readActionId: 'read-1',
    );
    expect(reread.text, window.text);
    expect(reread.fingerprint, window.fingerprint);
    expect(reread.readActionId, 'read-1');
  });

  test('readSourceWindow rejects ranges that split surrogate pairs', () {
    final item = LibraryItem(
      id: 'emoji',
      title: 'emoji',
      kind: ItemKind.text,
      contentBlocks: [
        ContentBlock(
          id: 'body-1',
          kind: ContentBlockKind.paragraph,
          text: 'A😀B',
        ),
      ],
    );

    expect(() => readSourceWindow(item, 'body-1', 1, 2), throwsRangeError);
    expect(readSourceWindow(item, 'body-1', 1, 3).text, '😀');
  });

  test(
    'source fingerprint changes when evidence-bearing dependencies change',
    () {
      final base = LibraryItem(
        id: 'a',
        title: '文章',
        kind: ItemKind.text,
        body: '正文',
        notes: '笔记',
        feedback: 0,
        analysis: Analysis(summary: '旧认识'),
      );
      final changed = LibraryItem(
        id: 'a',
        title: '文章',
        kind: ItemKind.text,
        body: '正文',
        notes: '笔记已改',
        feedback: 0,
        analysis: Analysis(summary: '旧认识'),
      );

      expect(sourceFingerprint(base), isNot(sourceFingerprint(changed)));
      final originalPath = LibraryItem(
        id: 'img',
        title: '图片',
        kind: ItemKind.image,
        assets: [
          Asset(path: '/old/path.jpg', name: 'scan.jpg', mime: 'image/jpeg'),
        ],
        contentBlocks: [
          ContentBlock(
            id: 'image-1',
            kind: ContentBlockKind.image,
            assetId: '/old/path.jpg',
            alt: '流程图',
          ),
        ],
      );
      final restoredPath = LibraryItem(
        id: 'img',
        title: '图片',
        kind: ItemKind.image,
        assets: [
          Asset(path: '/new/path.jpg', name: 'scan.jpg', mime: 'image/jpeg'),
        ],
        contentBlocks: [
          ContentBlock(
            id: 'image-1',
            kind: ContentBlockKind.image,
            assetId: '/new/path.jpg',
            alt: '流程图',
          ),
        ],
      );
      expect(sourceFingerprint(originalPath), sourceFingerprint(restoredPath));
    },
  );
}
