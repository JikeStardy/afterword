import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/core/store.dart';

void main() {
  late Directory directory;
  late LocalStore store;

  setUp(() {
    directory = Directory.systemTemp.createTempSync(
      'readlater-knowledge-store-',
    );
    store = LocalStore(directory.path);
  });

  tearDown(() {
    store.close();
    directory.deleteSync(recursive: true);
  });

  Uint8List archiveOf(AppData data) => Uint8List.fromList(
    ZipEncoder().encode(
      Archive()..addFile(
        ArchiveFile.string('manifest.json', jsonEncode(data.toJson())),
      ),
    ),
  );

  test(
    'restore interrupts pending dialogue turns without resubmitting them',
    () {
      final bytes = archiveOf(
        AppData(
          conversations: [
            Conversation(
              id: 'conversation-1',
              title: '问资料',
              scope: ConversationScope.item,
              scopeId: 'item-1',
            ),
          ],
          conversationTurns: [
            ConversationTurn(
              id: 'turn-queued',
              conversationId: 'conversation-1',
              question: '继续读',
              status: 'queued',
              requestPending: true,
            ),
            ConversationTurn(
              id: 'turn-running',
              conversationId: 'conversation-1',
              question: '解释证据',
              status: 'running',
            ),
            ConversationTurn(
              id: 'turn-complete',
              conversationId: 'conversation-1',
              question: '已完成问题',
              status: 'complete',
              answer: '已回答',
            ),
          ],
        ),
      );

      store.restore(bytes);
      final turns = {
        for (final turn in store.load().conversationTurns) turn.id: turn,
      };

      expect(turns['turn-queued']!.status, 'interrupted');
      expect(turns['turn-queued']!.requestPending, isTrue);
      expect(turns['turn-queued']!.error, isNotEmpty);
      expect(turns['turn-running']!.status, 'interrupted');
      expect(turns['turn-complete']!.status, 'complete');
      expect(store.loadRuntime().jobs, isEmpty);
    },
  );

  test('backup keeps visual proof as fingerprints while preserving original assets', () async {
    final asset = await store.writeAsset(
      Uint8List.fromList([1, 2, 3, 4]),
      'page.png',
      'image/png',
    );
    store.save(
      AppData(
        items: [
          LibraryItem(
            id: 'item-1',
            title: '图像',
            kind: ItemKind.image,
            assets: [asset],
          ),
        ],
        conversations: [
          Conversation(
            id: 'conversation-1',
            title: '看图',
            scope: ConversationScope.item,
          ),
        ],
        conversationTurns: [
          ConversationTurn(
            id: 'turn-1',
            conversationId: 'conversation-1',
            question: '图里有什么？',
            visualEvidence: [
              VisualEvidence(
                sourceId: 'item-1',
                sourceVersion: 1,
                assetFingerprint: 'sha256-visual',
                observation: '图中有标注',
              ),
            ],
          ),
        ],
      ),
    );

    final manifest = ZipDecoder()
        .decodeBytes(store.backup())
        .findFile('manifest.json')!;
    final decoded = jsonDecode(utf8.decode(manifest.content)) as Map;
    final turns = decoded['conversationTurns'] as List;

    expect(
      (turns.single['visualEvidence'] as List).single['assetFingerprint'],
      'sha256-visual',
    );
    expect(
      (turns.single['visualEvidence'] as List).single.toString(),
      isNot(contains(asset.path)),
    );
  });

  test('restore validates conversation owners and knowledge topic links', () {
    final missingConversation = AppData(
      conversationTurns: [
        ConversationTurn(
          id: 'turn-1',
          conversationId: 'missing-conversation',
          question: '孤儿轮次',
        ),
      ],
    );
    expect(
      () => store.restore(archiveOf(missingConversation)),
      throwsFormatException,
    );

    final missingTopic = AppData(
      knowledgeRevisions: [
        KnowledgeRevision(
          id: 'rev-1',
          topicId: 'missing-topic',
          presentation: ReadingPresentation(brief: '孤儿知识'),
        ),
      ],
    );
    expect(() => store.restore(archiveOf(missingTopic)), throwsFormatException);
  });
}
