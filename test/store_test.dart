import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/core/store.dart';

void main() {
  late Directory dir;
  late LocalStore store;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('readlater-store-');
    store = LocalStore(dir.path);
  });
  tearDown(() {
    store.close();
    dir.deleteSync(recursive: true);
  });
  test('SQLite survives reopening with original and generated content', () {
    final data = AppData(
      items: [
        LibraryItem(id: 'i1', title: '文章', kind: ItemKind.text, body: '原文'),
      ],
    );
    store.save(data);
    store.close();
    store = LocalStore(dir.path);
    expect(store.load().items.single.body, '原文');
  });
  test(
    'backup and restore preserves local assets and source relationships',
    () async {
      final asset = await store.writeAsset(
        Uint8List.fromList([1, 2, 3]),
        'diagram.png',
        'image/png',
      );
      store.save(
        AppData(
          items: [
            LibraryItem(
              id: 'i1',
              title: '图',
              kind: ItemKind.image,
              assets: [asset],
              contentBlocks: [
                ContentBlock(
                  id: 'image',
                  kind: ContentBlockKind.image,
                  assetId: asset.path,
                ),
              ],
              contentHistory: [
                ContentRevision(
                  version: 1,
                  title: '旧正文',
                  body: '',
                  blocks: [
                    ContentBlock(
                      id: 'old-image',
                      kind: ContentBlockKind.image,
                      assetId: asset.path,
                    ),
                  ],
                ),
              ],
              analysis: Analysis(summary: '观点', sourceIds: ['i1']),
            ),
          ],
        ),
      );
      final bytes = store.backup();
      final other = Directory.systemTemp.createTempSync('readlater-restore-');
      final destination = LocalStore(other.path);
      try {
        destination.restore(bytes);
        final item = destination.load().items.single;
        expect(
          File(destination.assetPath(item.assets.single)).readAsBytesSync(),
          [1, 2, 3],
        );
        expect(item.analysis!.sourceIds, ['i1']);
        expect(item.contentBlocks.single.assetId, item.assets.single.path);
        expect(
          item.contentHistory.single.blocks.single.assetId,
          item.assets.single.path,
        );
      } finally {
        destination.close();
        other.deleteSync(recursive: true);
      }
    },
  );
  test(
    'invalid archive paths cannot escape and do not replace existing data',
    () {
      store.save(
        AppData(
          items: [LibraryItem(id: 'keep', title: 'keep', kind: ItemKind.text)],
        ),
      );
      final archive = Archive()
        ..addFile(
          ArchiveFile(
            'manifest.json',
            0,
            utf8.encode(jsonEncode(AppData().toJson())),
          ),
        )
        ..addFile(ArchiveFile('../escape.txt', 3, [1, 2, 3]));
      expect(
        () => store.restore(Uint8List.fromList(ZipEncoder().encode(archive))),
        throwsFormatException,
      );
      expect(store.load().items.single.id, 'keep');
    },
  );
  test('missing referenced assets reject restore instead of silently losing originals', () {
    final data = AppData(
      items: [
        LibraryItem(
          id: 'x',
          title: 'x',
          kind: ItemKind.pdf,
          assets: [
            Asset(
              path: 'assets/missing.pdf',
              name: 'x.pdf',
              mime: 'application/pdf',
            ),
          ],
        ),
      ],
    );
    final archive = Archive()
      ..addFile(
        ArchiveFile('manifest.json', 0, utf8.encode(jsonEncode(data.toJson()))),
      );
    expect(
      () => store.restore(Uint8List.fromList(ZipEncoder().encode(archive))),
      throwsFormatException,
    );
  });
  test(
    'forged huge ZIP entry size is rejected before decoding its content',
    () {
      final archive = Archive()
        ..addFile(
          ArchiveFile.string('manifest.json', jsonEncode(AppData().toJson())),
        );
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
      final view = ByteData.sublistView(bytes);
      for (var n = 0; n < bytes.length - 46; n++) {
        if (view.getUint32(n, Endian.little) == 0x02014b50) {
          view.setUint32(n + 24, 600 * 1024 * 1024, Endian.little);
          break;
        }
      }
      expect(() => store.restore(bytes), throwsFormatException);
    },
  );
  test(
    'export refuses an archive larger than the supported restore budget',
    () {
      store.close();
      store = LocalStore(dir.path, maxBackupBytes: 100);
      store.save(
        AppData(
          items: [
            LibraryItem(
              id: 'a',
              title: 'article',
              kind: ItemKind.text,
              body: 'some original text',
            ),
          ],
        ),
      );
      expect(() => store.backup(), throwsFormatException);
    },
  );
  test('runtime state is saved atomically with the app snapshot', () {
    store.save(AppData());
    final runtime = RuntimeState(
      epoch: 1,
      jobs: [
        BackgroundJob(
          id: 'job1',
          type: 'analyzeItem',
          entityId: 'i1',
          status: 'running',
          stage: 'fetch',
          checkpoint: {'step': 1},
          createdAt: DateTime.utc(2026, 9, 22),
        ),
      ],
      outbox: [
        PendingNotification(
          id: 'n1',
          channel: 'results',
          title: '完成',
          body: '完成',
          entityType: 'item',
          entityId: 'i1',
          createdAt: DateTime.utc(2026, 9, 22),
        ),
      ],
    );

    store.saveWithRuntime(
      AppData(
        items: [LibraryItem(id: 'i1', title: '文章', kind: ItemKind.text)],
      ),
      runtime,
    );

    expect(store.load().items.single.id, 'i1');
    expect(store.loadRuntime().jobs.single.stage, 'fetch');
    expect(store.loadRuntime().outbox.single.id, 'n1');
  });

  test('failed combined save rolls back both snapshot and runtime state', () {
    store.saveWithRuntime(
      AppData(
        items: [LibraryItem(id: 'keep', title: 'keep', kind: ItemKind.text)],
      ),
      RuntimeState(epoch: 7),
    );

    expect(
      () => store.saveWithRuntime(
        AppData(
          items: [LibraryItem(id: 'bad', title: 'bad', kind: ItemKind.text)],
        ),
        RuntimeState(
          epoch: 8,
          jobs: [
            BackgroundJob(
              id: 'bad',
              type: 'analyzeItem',
              entityId: 'bad',
              status: 'running',
              stage: 'bad',
              checkpoint: {'invalid': Object()},
              createdAt: DateTime.utc(2026, 9, 22),
            ),
          ],
        ),
      ),
      throwsA(anything),
    );

    expect(store.load().items.single.id, 'keep');
    expect(store.loadRuntime().epoch, 7);
  });

  test(
    'backup excludes runtime queue and restore clears runtime with a new epoch',
    () {
      store.saveWithRuntime(
        AppData(
          items: [
            LibraryItem(
              id: 'i1',
              title: '文章',
              kind: ItemKind.text,
              status: 'analyzing',
            ),
          ],
        ),
        RuntimeState(
          epoch: 5,
          jobs: [
            BackgroundJob(
              id: 'job1',
              type: 'analyzeItem',
              entityId: 'i1',
              status: 'running',
              stage: 'model',
              createdAt: DateTime.utc(2026, 9, 22),
            ),
          ],
          outbox: [
            PendingNotification(
              id: 'n1',
              channel: 'progress',
              title: '运行中',
              body: '运行中',
              entityType: 'item',
              entityId: 'i1',
              createdAt: DateTime.utc(2026, 9, 22),
            ),
          ],
        ),
      );

      final manifest = ZipDecoder()
          .decodeBytes(store.backup())
          .findFile('manifest.json')!;
      final decoded = jsonDecode(utf8.decode(manifest.content)) as Map;
      expect(decoded.containsKey('runtime'), isFalse);

      final other = Directory.systemTemp.createTempSync(
        'readlater-restore-runtime-',
      );
      final destination = LocalStore(other.path);
      try {
        destination.saveWithRuntime(AppData(), RuntimeState(epoch: 9));
        destination.restore(store.backup());
        expect(destination.loadRuntime().epoch, 10);
        expect(destination.loadRuntime().jobs, isEmpty);
        expect(destination.loadRuntime().outbox, isEmpty);
        expect(destination.load().items.single.status, 'retryable');
      } finally {
        destination.close();
        other.deleteSync(recursive: true);
      }
    },
  );
}
