import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/core/store.dart';

void main() {
  final now = DateTime.utc(2026, 9, 22, 12);
  late Directory directory;
  late LocalStore store;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('readlater-lifecycle-');
    store = LocalStore(directory.path, now: () => now);
  });
  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  Uint8List archiveOf(Json manifest) => Uint8List.fromList(
    ZipEncoder().encode(
      Archive()
        ..addFile(ArchiveFile.string('manifest.json', jsonEncode(manifest))),
    ),
  );

  test(
    'lifecycle preserves archive state underneath trash and nullable ancestry',
    () {
      final archived = now.subtract(const Duration(days: 10));
      final item = LibraryItem(
        id: 'archived',
        title: 'Archived',
        kind: ItemKind.text,
        archivedAt: archived,
        trashedAt: now,
        analysis: Analysis(sourceIds: ['citation'], inputItemIds: ['ancestor']),
      );
      final copy = LibraryItem.fromJson(item.toJson());
      expect(copy.isArchived, isTrue);
      expect(copy.isTrashed, isTrue);
      expect(copy.isActive, isFalse);
      copy.trashedAt = null;
      expect(copy.archivedAt, archived);
      expect(copy.isActive, isFalse);
      copy.archivedAt = null;
      expect(copy.isActive, isTrue);
      expect(copy.analysis!.sourceIds, ['citation']);
      expect(copy.analysis!.inputItemIds, ['ancestor']);
      expect(Analysis.fromJson(Analysis().toJson()).inputItemIds, isNull);
      expect(
        Analysis.fromJson(Analysis(inputItemIds: []).toJson()).inputItemIds,
        isEmpty,
      );
      expect(
        Topic.fromJson(
          Topic(id: 't', title: 'T', question: 'Q', inputItemIds: []).toJson(),
        ).inputItemIds,
        isEmpty,
      );
      expect(
        ResearchRun.fromJson(
          ResearchRun(id: 'r', goal: 'G', inputItemIds: ['ancestor']).toJson(),
        ).inputItemIds,
        ['ancestor'],
      );
    },
  );

  test('version one migrates readable outputs with unknown rather than guessed inputs', () {
    final manifest = AppData(
      items: [
        LibraryItem(
          id: 'old',
          title: 'Old',
          kind: ItemKind.text,
          analysis: Analysis(summary: 'Old summary', sourceIds: ['old']),
        ),
      ],
      topics: [
        Topic(
          id: 'topic',
          title: 'Topic',
          question: 'Question',
          sourceIds: ['old'],
        ),
      ],
      runs: [ResearchRun(id: 'run', goal: 'Goal', report: 'Old report')],
    ).toJson()..['version'] = 1;
    ((manifest['items'] as List).single['analysis'] as Map).remove(
      'inputItemIds',
    );
    ((manifest['topics'] as List).single as Map).remove('inputItemIds');
    ((manifest['runs'] as List).single as Map).remove('inputItemIds');
    store.restore(archiveOf(manifest));
    final migrated = store.load();
    expect(migrated.toJson()['version'], 2);
    expect(migrated.items.single.analysis!.summary, 'Old summary');
    expect(migrated.items.single.analysis!.inputItemIds, isNull);
    expect(migrated.topics.single.inputItemIds, isNull);
    expect(migrated.runs.single.inputItemIds, isNull);
    expect(migrated.runs.single.report, 'Old report');
    expect(migrated.settings.trashRetentionDays, 7);
    expect(migrated.settings.debugModelLogging, isFalse);
  });

  test('restore expires trash at boundary and retains ancestry, timestamps and device settings', () {
    final recentTrash = now.subtract(const Duration(days: 2));
    final archived = now.subtract(const Duration(days: 20));
    final data = AppData(
      settings: AppSettings(
        trashRetentionDays: 3,
        debugModelLogging: true,
        confirmedInterests: ['Confirmed'],
        endpoint: 'https://import.invalid',
        textModel: 'import',
      ),
      items: [
        LibraryItem(
          id: 'active',
          title: 'Active',
          kind: ItemKind.text,
          analysis: Analysis(inputItemIds: ['expired'], sourceIds: ['expired']),
        ),
        LibraryItem(
          id: 'archived',
          title: 'Archived',
          kind: ItemKind.text,
          archivedAt: archived,
        ),
        LibraryItem(
          id: 'recent',
          title: 'Recent',
          kind: ItemKind.text,
          archivedAt: archived,
          trashedAt: recentTrash,
        ),
        LibraryItem(
          id: 'expired',
          title: 'Expired',
          kind: ItemKind.text,
          trashedAt: now.subtract(const Duration(days: 3)),
        ),
      ],
      entries: [
        FeedEntry(
          id: 'rss',
          feedId: 'feed',
          title: 'Entry',
          url: 'https://example.com',
          savedItemId: 'expired',
        ),
      ],
      topics: [
        Topic(
          id: 'topic',
          title: 'Topic',
          question: 'Question',
          inputItemIds: ['expired'],
          sourceIds: ['expired'],
        ),
      ],
      runs: [
        ResearchRun(id: 'run', goal: 'Goal', inputItemIds: ['expired']),
      ],
    );
    store.restore(
      archiveOf(data.toJson()),
      serviceSettings: AppSettings(
        endpoint: 'https://device.invalid',
        textModel: 'device-text',
        visionModel: 'device-vision',
        searchEndpoint: 'https://search.invalid',
        debugModelLogging: true,
      ),
    );
    final restored = store.load();
    expect(restored.items.map((item) => item.id), [
      'active',
      'archived',
      'recent',
    ]);
    expect(restored.items.last.trashedAt, recentTrash);
    expect(restored.items.last.archivedAt, archived);
    expect(restored.entries.single.savedItemId, isNull);
    expect(restored.items.first.analysis!.inputItemIds, ['expired']);
    expect(restored.topics.single.inputItemIds, ['expired']);
    expect(restored.topics.single.sourceIds, ['expired']);
    expect(restored.runs.single.inputItemIds, ['expired']);
    expect(restored.settings.endpoint, 'https://device.invalid');
    expect(restored.settings.textModel, 'device-text');
    expect(restored.settings.visionModel, 'device-vision');
    expect(restored.settings.searchEndpoint, 'https://search.invalid');
    expect(restored.settings.confirmedInterests, ['Confirmed']);
    expect(restored.settings.debugModelLogging, isFalse);
  });

  test(
    'backup retains archives and recent trash but excludes expired originals',
    () async {
      final asset = await store.writeAsset(
        Uint8List.fromList([1, 2]),
        'keep.png',
        'image/png',
      );
      final expiredAsset = await store.writeAsset(
        Uint8List.fromList([3]),
        'expired.png',
        'image/png',
      );
      store.save(
        AppData(
          items: [
            LibraryItem(
              id: 'archive',
              title: 'Archived',
              kind: ItemKind.image,
              assets: [asset],
              archivedAt: now,
            ),
            LibraryItem(
              id: 'recent',
              title: 'Recent',
              kind: ItemKind.text,
              trashedAt: now.subtract(const Duration(days: 6)),
            ),
            LibraryItem(
              id: 'expired',
              title: 'Expired',
              kind: ItemKind.image,
              assets: [expiredAsset],
              trashedAt: now.subtract(const Duration(days: 7)),
            ),
          ],
        ),
      );
      final archive = ZipDecoder().decodeBytes(store.backup());
      final manifest = AppData.fromJson(
        json(
          jsonDecode(utf8.decode(archive.findFile('manifest.json')!.content)),
        ),
      );
      expect(manifest.items.map((item) => item.id), ['archive', 'recent']);
      expect(archive.findFile(asset.path), isNotNull);
      expect(archive.findFile(expiredAsset.path), isNull);
      expect(store.load().items, hasLength(3));
    },
  );

  test('cleanup removes only unreferenced managed regular files and preserves historic IDs', () async {
    final referenced = await store.writeAsset(
      Uint8List.fromList([1]),
      'keep.png',
      'image/png',
    );
    final orphan = await store.writeAsset(
      Uint8List.fromList([2]),
      'orphan.png',
      'image/png',
    );
    final unmanaged = File('${directory.path}/assets/not managed.txt')
      ..writeAsStringSync('unmanaged');
    final outside = File('${directory.path}/outside.png')
      ..writeAsStringSync('outside');
    final link = Link('${directory.path}/assets/linked.png')
      ..createSync(outside.path);
    final nested = Directory('${directory.path}/assets/nested')..createSync();
    final nestedFile = File('${nested.path}/keep.png')
      ..writeAsStringSync('nested');
    final data = AppData(
      items: [
        LibraryItem(
          id: 'keep',
          title: 'Keep',
          kind: ItemKind.image,
          assets: [referenced],
          archivedAt: now,
          trashedAt: now,
          analysis: Analysis(inputItemIds: ['deleted']),
        ),
      ],
    );
    store.cleanUnusedAssets(data);
    expect(File(store.assetPath(referenced)).existsSync(), isTrue);
    expect(File(store.assetPath(orphan)).existsSync(), isFalse);
    expect(unmanaged.existsSync(), isTrue);
    expect(outside.existsSync(), isTrue);
    expect(link.existsSync(), isTrue);
    expect(nestedFile.existsSync(), isTrue);
    expect(data.items.single.analysis!.inputItemIds, ['deleted']);
    store.cleanUnusedAssets(data);
  });

  test(
    'restore keeps committed device configuration when none is supplied',
    () {
      store.save(
        AppData(
          settings: AppSettings(
            endpoint: 'https://device.invalid',
            textModel: 'device',
            debugModelLogging: true,
          ),
        ),
      );
      store.restore(
        archiveOf(
          AppData(
            settings: AppSettings(
              endpoint: 'https://foreign.invalid',
              textModel: 'foreign',
              debugModelLogging: true,
            ),
          ).toJson(),
        ),
      );
      final settings = store.load().settings;
      expect(settings.endpoint, 'https://device.invalid');
      expect(settings.textModel, 'device');
      expect(settings.debugModelLogging, isFalse);
    },
  );

  test(
    'retention accepts only 3 or 7 days and confirmed preferences round trip',
    () {
      final settings = AppSettings(
        trashRetentionDays: 3,
        debugModelLogging: true,
        confirmedInterests: ['Edited'],
      );
      final copy = AppSettings.fromJson(settings.toJson());
      expect(copy.trashRetentionDays, 3);
      expect(copy.debugModelLogging, isTrue);
      expect(copy.confirmedInterests, ['Edited']);
      expect(() => AppSettings(trashRetentionDays: 4), throwsArgumentError);
      expect(() => copy.trashRetentionDays = 0, throwsArgumentError);
      expect(
        AppSettings.fromJson({'trashRetentionDays': 99}).trashRetentionDays,
        7,
      );
    },
  );
}
