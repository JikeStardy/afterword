import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:sqlite3/sqlite3.dart';

import 'models.dart';

/// One transaction owns the complete domain snapshot; original assets are immutable.
/// This keeps backup/restore and relationships atomic without code generation.
class LocalStore {
  final String root;
  final DateTime Function() _now;
  final int maxBackupBytes, maxUnpackedBytes, maxBackupEntries;
  late final Database _database;
  bool _closed = false;
  LocalStore(
    this.root, {
    DateTime Function()? now,
    this.maxBackupBytes = 256 * 1024 * 1024,
    this.maxUnpackedBytes = 512 * 1024 * 1024,
    this.maxBackupEntries = 10000,
  }) : _now = now ?? DateTime.now {
    Directory('$root/assets').createSync(recursive: true);
    _database = sqlite3.open('$root/readlater.sqlite');
    _database.execute('PRAGMA journal_mode=WAL');
    _database.execute('PRAGMA busy_timeout=5000');
    _database.execute(
      'CREATE TABLE IF NOT EXISTS app_state (id INTEGER PRIMARY KEY CHECK(id=1), data TEXT NOT NULL)',
    );
    _database.execute(
      'CREATE TABLE IF NOT EXISTS runtime_state (id INTEGER PRIMARY KEY CHECK(id=1), data TEXT NOT NULL)',
    );
  }
  AppData load() {
    final rows = _database.select('SELECT data FROM app_state WHERE id=1');
    return rows.isEmpty
        ? AppData()
        : AppData.fromJson(json(jsonDecode(rows.single['data'] as String)));
  }

  void save(AppData data) {
    _saveAppState(data);
  }

  RuntimeState loadRuntime() {
    final rows = _database.select('SELECT data FROM runtime_state WHERE id=1');
    return rows.isEmpty
        ? RuntimeState()
        : RuntimeState.fromJson(
            json(jsonDecode(rows.single['data'] as String)),
          );
  }

  void saveWithRuntime(AppData data, RuntimeState runtime) {
    final payload = jsonEncode(data.toJson());
    final runtimePayload = jsonEncode(runtime.toJson());
    _database.execute('BEGIN IMMEDIATE');
    try {
      _writeAppPayload(payload);
      _database.execute(
        'INSERT INTO runtime_state(id,data) VALUES(1,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data',
        [runtimePayload],
      );
      _database.execute('COMMIT');
    } catch (_) {
      _database.execute('ROLLBACK');
      rethrow;
    }
  }

  void _saveAppState(AppData data) {
    _writeAppPayload(jsonEncode(data.toJson()));
  }

  void _writeAppPayload(String payload) {
    _database.execute(
      'INSERT INTO app_state(id,data) VALUES(1,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data',
      [payload],
    );
  }

  String assetPath(Asset asset) {
    if (!_validAssetPath(asset.path)) throw const FormatException('无效的本地附件路径');
    return '$root/${asset.path}';
  }

  static bool _validAssetPath(String path) =>
      RegExp(r'^assets/[a-zA-Z0-9_-]+\.[a-zA-Z0-9]+$').hasMatch(path);
  Future<Asset> writeAsset(Uint8List bytes, String name, String mime) async {
    if (bytes.isEmpty || bytes.length > 50 * 1024 * 1024) {
      throw const FormatException('附件需在 1 字节至 50 MB 之间');
    }
    var extension = name.split('.').last.toLowerCase();
    if (!RegExp(r'^[a-z0-9]{1,8}$').hasMatch(extension)) extension = 'bin';
    final asset = Asset(
      path: 'assets/${newId()}.$extension',
      name: name,
      mime: mime,
    );
    await File(assetPath(asset)).writeAsBytes(bytes, flush: true);
    return asset;
  }

  Future<Asset> importAsset(String path, String name, String mime) async {
    final file = File(path);
    if (await file.length() > 50 * 1024 * 1024) {
      throw const FormatException('文件超过 50 MB');
    }
    return writeAsset(await file.readAsBytes(), name, mime);
  }

  Uint8List backup() {
    final data = load();
    _removeExpiredTrash(data);
    final archive = Archive()
      ..addFile(ArchiveFile.string('manifest.json', jsonEncode(data.toJson())));
    final paths = <String>{};
    var expanded = archive.files.single.size;
    for (final item in data.items) {
      for (final asset in item.assets) {
        if (!paths.add(asset.path)) continue;
        final file = File(assetPath(asset));
        if (!file.existsSync()) {
          throw FileSystemException('附件缺失，无法生成完整备份', asset.path);
        }
        expanded += file.lengthSync();
        if (expanded > maxUnpackedBytes ||
            paths.length + 1 > maxBackupEntries) {
          throw const FormatException('资料库超过单份备份容量，请减少附件后重试');
        }
        final bytes = file.readAsBytesSync();
        archive.addFile(ArchiveFile(asset.path, bytes.length, bytes));
      }
    }
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
    if (bytes.length > maxBackupBytes || expanded > maxUnpackedBytes) {
      throw const FormatException('备份超过可恢复容量');
    }
    return bytes;
  }

  void restore(Uint8List bytes, {AppSettings? serviceSettings}) {
    if (bytes.length > maxBackupBytes) {
      throw const FormatException('备份超过 256 MB');
    }
    final directory = ZipDirectory()..read(InputMemoryStream(bytes));
    var declaredTotal = 0;
    final declaredNames = <String>{};
    if (directory.fileHeaders.length > maxBackupEntries) {
      throw const FormatException('备份条目过多');
    }
    for (final header in directory.fileHeaders) {
      declaredTotal += header.uncompressedSize;
      if (declaredTotal > maxUnpackedBytes ||
          !declaredNames.add(header.filename) ||
          ((header.externalFileAttributes >> 16) & 0xf000) == 0xa000 ||
          (header.filename != 'manifest.json' &&
              !_validAssetPath(header.filename))) {
        throw const FormatException('备份元数据不安全或展开后过大');
      }
    }
    final archive = ZipDecoder().decodeBytes(bytes);
    final names = <String>{};
    var total = 0;
    for (final file in archive.files) {
      if (!file.isFile ||
          file.isSymbolicLink ||
          !names.add(file.name) ||
          (file.name != 'manifest.json' && !_validAssetPath(file.name))) {
        throw const FormatException('备份包含不安全或重复路径');
      }
      total += file.size;
      if (total > maxUnpackedBytes || archive.files.length > maxBackupEntries) {
        throw const FormatException('备份展开后过大');
      }
    }
    final manifest = archive.findFile('manifest.json');
    if (manifest == null) throw const FormatException('备份缺少数据清单');
    final restored = AppData.fromJson(
      json(jsonDecode(utf8.decode(manifest.content))),
    );
    final ids = <String>{};
    for (final item in restored.items) {
      if (!ids.add(item.id)) throw const FormatException('重复资料编号');
      for (final asset in item.assets) {
        if (!_validAssetPath(asset.path) || !names.contains(asset.path)) {
          throw const FormatException('备份缺少原始附件');
        }
      }
    }
    _validateRestoredKnowledgeGraph(restored);
    _removeExpiredTrash(restored);
    // Give imported assets new immutable names. A failed restore never alters
    // originals belonging to the currently committed database snapshot.
    final mapping = <String, String>{};
    final created = <File>[];
    try {
      for (final item in restored.items) {
        for (final asset in item.assets) {
          final original = asset.path;
          if (!mapping.containsKey(original)) {
            final target = 'assets/${newId()}.${original.split('.').last}';
            final file = File('$root/$target');
            created.add(file);
            file.writeAsBytesSync(
              archive.findFile(original)!.content,
              flush: true,
            );
            mapping[original] = target;
          }
          asset.path = mapping[original]!;
        }
      }
      for (final item in restored.items) {
        for (final block in [
          ...item.contentBlocks,
          for (final revision in item.contentHistory) ...revision.blocks,
        ]) {
          if (mapping.containsKey(block.assetId)) {
            block.assetId = mapping[block.assetId]!;
          }
        }
      }
      // Imported tracking grants are not silently renewed on another device.
      for (final topic in restored.topics) {
        topic.tracking = false;
        topic.authorizedScope = '';
      }
      // A backup is content, not permission to send device-held secrets to a new host.
      final device = serviceSettings ?? load().settings;
      restored.settings.endpoint = device.endpoint;
      restored.settings.textModel = device.textModel;
      restored.settings.visionModel = device.visionModel;
      restored.settings.searchEndpoint = device.searchEndpoint;
      restored.settings.debugModelLogging = false;
      _prepareRestoredOperationalState(restored);
      saveWithRuntime(restored, RuntimeState(epoch: loadRuntime().epoch + 1));
    } catch (_) {
      for (final file in created) {
        if (file.existsSync()) file.deleteSync();
      }
      rethrow;
    }
  }

  void _prepareRestoredOperationalState(AppData data) {
    for (final item in data.items) {
      if (['analyzing', 'pending', 'waiting'].contains(item.status)) {
        item.status = 'retryable';
      }
    }
    for (final topic in data.topics) {
      if (['running', 'synthesizing', 'waiting'].contains(topic.status)) {
        topic.status = 'pending';
      }
    }
    for (final run in data.runs) {
      if (run.status == 'running') run.status = 'interrupted';
    }
    for (final turn in data.conversationTurns) {
      if (turn.status == 'queued' || turn.status == 'running') {
        turn.status = 'interrupted';
        turn.error = turn.error.isEmpty ? '恢复后需重新提交本轮对话' : turn.error;
      }
    }
  }

  void _validateRestoredKnowledgeGraph(AppData data) {
    void requireUnique(Iterable<String> values, String message) {
      final seen = <String>{};
      for (final value in values) {
        if (value.isEmpty || !seen.add(value)) throw FormatException(message);
      }
    }

    requireUnique(data.conversations.map((c) => c.id), '重复会话编号');
    requireUnique(data.conversationTurns.map((t) => t.id), '重复会话轮次编号');
    requireUnique(data.segmentSummaries.map((s) => s.id), '重复摘要编号');
    requireUnique(data.knowledgeProposals.map((p) => p.id), '重复知识提案编号');
    requireUnique(data.knowledgeRevisions.map((r) => r.id), '重复知识修订编号');

    final conversationIds = data.conversations.map((c) => c.id).toSet();
    for (final turn in data.conversationTurns) {
      if (!conversationIds.contains(turn.conversationId)) {
        throw const FormatException('会话轮次缺少所属会话');
      }
    }

    final topicIds = data.topics.map((t) => t.id).toSet();
    final revisionIds = data.knowledgeRevisions.map((r) => r.id).toSet();
    for (final topic in data.topics) {
      final revisionId = topic.currentKnowledgeRevisionId;
      if (revisionId != null && !revisionIds.contains(revisionId)) {
        throw const FormatException('主题指向不存在的知识修订');
      }
    }
    for (final proposal in data.knowledgeProposals) {
      final topicId = proposal.topicId;
      if (topicId != null && !topicIds.contains(topicId)) {
        throw const FormatException('知识提案指向不存在的主题');
      }
      for (final relatedTopicId in proposal.relatedTopicIds) {
        if (!topicIds.contains(relatedTopicId)) {
          throw const FormatException('知识提案关联不存在的主题');
        }
      }
      final acceptedRevisionId = proposal.acceptedRevisionId;
      if (acceptedRevisionId != null &&
          !revisionIds.contains(acceptedRevisionId)) {
        throw const FormatException('知识提案指向不存在的已接受修订');
      }
    }
    for (final revision in data.knowledgeRevisions) {
      if (!topicIds.contains(revision.topicId)) {
        throw const FormatException('知识修订指向不存在的主题');
      }
      for (final relatedTopicId in revision.relatedTopicIds) {
        if (!topicIds.contains(relatedTopicId)) {
          throw const FormatException('知识修订关联不存在的主题');
        }
      }
      final parentId = revision.parentId;
      if (parentId != null && !revisionIds.contains(parentId)) {
        throw const FormatException('知识修订父级不存在');
      }
    }
  }

  // Retain historical source and input IDs so old outputs never acquire a false
  // claim of provenance after a referenced original expires.
  void _removeExpiredTrash(AppData data) {
    final cutoff = _now().subtract(
      Duration(days: data.settings.trashRetentionDays),
    );
    final expired = data.items
        .where(
          (item) => item.trashedAt != null && !item.trashedAt!.isAfter(cutoff),
        )
        .map((item) => item.id)
        .toSet();
    data.items.removeWhere((item) => expired.contains(item.id));
    for (final entry in data.entries) {
      if (expired.contains(entry.savedItemId)) entry.savedItemId = null;
    }
  }

  /// Call only after all attachment imports and their snapshot saves finish.
  /// Only direct regular files with managed names are eligible. Failed cleanup
  /// is harmless and will be retried on the next maintenance pass.
  void cleanUnusedAssets(AppData data) {
    final referenced = {
      for (final item in data.items)
        for (final asset in item.assets) asset.path,
    };
    final assets = Directory('$root/assets');
    try {
      if (FileSystemEntity.typeSync(assets.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        return;
      }
      for (final entity in assets.listSync(followLinks: false)) {
        if (entity is! File) continue;
        final relative = 'assets/${entity.uri.pathSegments.last}';
        if (!_validAssetPath(relative) || referenced.contains(relative)) {
          continue;
        }
        try {
          if (FileSystemEntity.typeSync(entity.path, followLinks: false) ==
              FileSystemEntityType.file) {
            entity.deleteSync();
          }
        } on FileSystemException {
          // A locked or concurrently removed file is safe to retry later.
        }
      }
    } on FileSystemException {
      // Directory enumeration failure must not fail the saved domain change.
    }
  }

  void close() {
    if (!_closed) {
      _database.close();
      _closed = true;
    }
  }
}
