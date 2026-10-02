import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/core/models.dart';
import 'package:readlater/core/retrieval.dart';
import 'package:readlater/services/conversation_service.dart';
import 'package:readlater/services/intelligence_service.dart';

void main() {
  final source = LibraryItem(
    id: 'src',
    title: '资料',
    kind: ItemKind.text,
    contentVersion: 2,
    contentBlocks: [
      ContentBlock(
        id: 'body-1',
        kind: ContentBlockKind.paragraph,
        text: '这个段落说明渐进式读取能避免每次把全文提交给模型。',
      ),
    ],
  );

  test(
    'buildPrompt keeps question intact and trims windows to text budget',
    () {
      final first = readSourceWindow(source, 'body-1', 0, 12);
      final second = SourceWindow(
        id: 'manual',
        sourceId: 'src',
        sourceVersion: 2,
        blockId: 'body-1',
        start: 12,
        end: 25,
        text: List.filled(160, '额外上下文').join(),
        fingerprint: 'manual',
      );
      final turn = ConversationTurn(
        id: 'turn',
        conversationId: 'c',
        question: '为什么不要每次提交全文？',
        windows: [first, second],
        textBudgetChars: 1400,
      );

      final built = const ConversationService().buildPrompt(turn, [source]);
      final payload =
          jsonDecode(built.prompt.split('输入数据：').last) as Map<String, dynamic>;

      expect(payload['question'], '为什么不要每次提交全文？');
      expect(payload['windows'], hasLength(1));
      expect((payload['windows'] as List).single['id'], first.id);
      expect(
        IntelligenceService.textualRequestChars(built.prompt),
        lessThanOrEqualTo(turn.textBudgetChars),
      );
    },
  );

  test('parseModelStep accepts only bounded local read actions', () {
    final turn = ConversationTurn(
      id: 'turn',
      conversationId: 'c',
      question: '继续读',
      callLimit: 1,
    );
    final step = const ConversationService().parseModelStep(
      {
        'actions': [
          {'id': 'a1', 'type': 'search', 'query': '渐进式读取'},
          {
            'id': 'a2',
            'type': 'readText',
            'sourceId': 'src',
            'sourceVersion': 2,
          },
        ],
      },
      turn: turn,
      actionLimit: 3,
    );

    expect(step.isAnswer, isFalse);
    expect(step.actions, hasLength(1));
    expect(step.actions.single.type, 'search');
    final readStep = const ConversationService().parseStep({
      'actions': [
        {'id': 'a2', 'type': 'readText', 'sourceId': 'src', 'sourceVersion': 2},
      ],
    }, turn);
    expect(readStep.actions.single.sourceVersion, 2);
    expect(
      () => const ConversationService().parseModelStep({
        'actions': [
          {'type': 'openUrl', 'url': 'https://example.com'},
        ],
      }, turn: turn),
      throwsFormatException,
    );
    expect(
      () => const ConversationService().parseStep(
        {
          'actions': [
            {'type': 'search', 'query': '渐进式读取'},
          ],
        },
        turn,
        answerOnly: true,
      ),
      throwsFormatException,
    );
  });

  test('parseAnswerResult validates evidence against delivered windows', () {
    final window = readSourceWindow(source, 'body-1', 0, 23);
    final turn = ConversationTurn(
      id: 'turn',
      conversationId: 'c',
      question: '为什么？',
      windows: [window],
      inputItemIds: ['src'],
      sourceVersions: {'src': 2},
      sourceFingerprints: {'src': sourceFingerprint(source)},
    );

    final result = const ConversationService().parseAnswerResult({
      'answer': '因为可以只读取相关证据。',
      'evidence': [
        {
          'sourceId': 'src',
          'sourceVersion': 2,
          'blockId': 'body-1',
          'windowId': window.id,
          'start': window.start,
          'end': window.end,
          'quote': '渐进式读取',
        },
      ],
      'remainingGaps': ['还没有读取全部段落'],
      'proposals': [
        {
          'id': 'p',
          'title': '渐进式读取',
          'question': '如何避免超时？',
          'presentation': {
            'brief': '只读取相关窗口。',
            'sections': [
              {'title': '做法', 'body': '先搜索，再读取命中的原文窗口。'},
            ],
          },
        },
      ],
    }, turn: turn);

    expect(result.answer, contains('相关证据'));
    expect(result.evidence.single.windowId, window.id);
    expect(result.remainingGaps, ['还没有读取全部段落']);
    expect(result.proposals.single.originTurnId, 'turn');

    expect(
      () => const ConversationService().parseAnswerResult({
        'answer': '编造证据',
        'evidence': [
          {
            'sourceId': 'src',
            'sourceVersion': 2,
            'blockId': 'body-1',
            'windowId': 'missing',
            'start': 0,
            'end': 4,
            'quote': '不存在',
          },
        ],
      }, turn: turn),
      throwsFormatException,
    );
  });

  test(
    'parseAnswerResult accepts only provided unverified visual evidence',
    () {
      final turn = ConversationTurn(
        id: 'turn',
        conversationId: 'c',
        question: '图里是什么？',
        visualEvidence: [
          VisualEvidence(
            sourceId: 'img',
            sourceVersion: 1,
            assetFingerprint: 'asset-sha',
            observation: '图中有流程图',
          ),
        ],
      );

      final result = const ConversationService().parseAnswerResult({
        'answer': '图像观察仍需人工核验。',
        'evidence': [
          {
            'sourceId': 'img',
            'sourceVersion': 1,
            'assetFingerprint': 'asset-sha',
            'quote': '图中有流程图',
          },
        ],
      }, turn: turn);

      expect(result.evidence.single.unresolved, isTrue);
      expect(
        () => const ConversationService().parseAnswerResult({
          'answer': '错误',
          'evidence': [
            {
              'sourceId': 'img',
              'sourceVersion': 1,
              'assetFingerprint': 'other',
            },
          ],
        }, turn: turn),
        throwsFormatException,
      );
    },
  );
}
