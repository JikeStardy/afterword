import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:readlater/ui/afterword_art.dart';
import 'package:readlater/ui/afterword_vectors.dart';

void main() {
  test('generated vector catalog exposes expected core assets', () {
    expect(afterwordVectorFactories, contains('brand:fox'));
    expect(afterwordVectorFactories, contains('icon:today'));
    expect(afterwordVectorFactories, contains('icon:today-selected'));
    expect(afterwordVectorFactories, contains('scene:library-empty'));
    expect(afterwordMaterialIds[Icons.today_outlined], 'today');
  });

  test('vector cache reuses generated geometry', () {
    final first = cachedAfterwordVectorNodes('brand:fox');
    final second = cachedAfterwordVectorNodes('brand:fox');
    expect(first, isNotNull);
    expect(identical(first, second), isTrue);
  });

  testWidgets(
    'AfterwordIcon follows IconTheme color, size, text scaling and semantics',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: IconTheme(
                data: const IconThemeData(
                  color: Color(0xff123456),
                  size: 20,
                  opacity: .5,
                  applyTextScaling: true,
                ),
                child: const Center(
                  child: AfterwordIcon(
                    Icons.today_outlined,
                    semanticLabel: '今日',
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final picture = tester.widget<AfterwordVectorPicture>(
        find.byType(AfterwordVectorPicture),
      );
      final box = tester.renderObject<RenderBox>(
        find.byType(AfterwordVectorPicture),
      );
      expect(box.size, const Size.square(30));
      expect(picture.color, const Color(0xff123456).withValues(alpha: .5));
      expect(find.bySemanticsLabel('今日'), findsOneWidget);
      expect(find.byType(RichText), findsNothing);
    },
  );

  testWidgets(
    'AfterwordIcon can select variants and mirror directional assets in RTL',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Row(
              children: [
                AfterwordIcon(Icons.today_outlined, selected: true),
                AfterwordIcon(null, asset: 'back'),
              ],
            ),
          ),
        ),
      );

      final pictures = tester.widgetList<AfterwordVectorPicture>(
        find.byType(AfterwordVectorPicture),
      );
      expect(pictures.first.id, 'icon:today-selected');
      expect(pictures.last.id, 'icon:back');
      expect(find.byType(Transform), findsOneWidget);
    },
  );

  testWidgets('AfterwordIcon falls back to Material glyph for unmapped icons', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.ltr,
          child: AfterwordIcon(Icons.abc),
        ),
      ),
    );

    expect(find.byType(AfterwordVectorPicture), findsNothing);
    expect(find.byType(RichText), findsOneWidget);
  });

  testWidgets('all generated vectors paint without throwing', (tester) async {
    final ids = afterwordVectorFactories.keys.toList()..sort();

    await tester.pumpWidget(
      MaterialApp(
        home: SingleChildScrollView(
          child: Wrap(
            children: [
              for (final id in ids.take(120))
                AfterwordVectorPicture(
                  id: id,
                  viewBox: id.startsWith('icon:')
                      ? afterwordIconViewBox
                      : afterwordSceneViewBox,
                  size: 32,
                  color: Colors.green,
                  eyeColor: Colors.white,
                ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('AfterwordScene plays one-shot motion to completion', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AfterwordScene(scene: 'saved', motion: FoxMotion.saved),
      ),
    );

    await tester.pump();
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpWidget(
      const MaterialApp(
        home: AfterwordScene(scene: 'saved', motion: FoxMotion.saved),
      ),
    );
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('AfterwordScene loops only supported repeated busy motions', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AfterwordScene(
          scene: 'analyzing',
          motion: FoxMotion.analyze,
          repeat: true,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(tester.hasRunningAnimations, isTrue);
    final picture = tester.widget<AfterwordVectorPicture>(
      find.byType(AfterwordVectorPicture),
    );
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      identical(
        picture,
        tester.widget<AfterwordVectorPicture>(
          find.byType(AfterwordVectorPicture),
        ),
      ),
      isTrue,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: AfterwordScene(
          scene: 'saved',
          motion: FoxMotion.saved,
          repeat: true,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets(
    'AfterwordScene respects disabled animations and semantics opt-in',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: const AfterwordScene(
              scene: 'analyzing',
              motion: FoxMotion.analyze,
              repeat: true,
              semanticLabel: '分析中',
            ),
          ),
        ),
      );

      await tester.pump(const Duration(seconds: 1));
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.bySemanticsLabel('分析中'), findsOneWidget);
    },
  );

  testWidgets('AfterwordScene pauses when ticker is disabled', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: TickerMode(
          enabled: false,
          child: AfterwordScene(
            scene: 'capturing',
            motion: FoxMotion.collect,
            repeat: true,
          ),
        ),
      ),
    );

    await tester.pump(const Duration(seconds: 1));
    expect(tester.hasRunningAnimations, isFalse);

    await tester.pumpWidget(
      const MaterialApp(
        home: TickerMode(
          enabled: true,
          child: AfterwordScene(
            scene: 'capturing',
            motion: FoxMotion.collect,
            repeat: true,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.hasRunningAnimations, isTrue);
  });

  testWidgets(
    'AfterwordScene stops in background, resumes, and disposes cleanly',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpWidget(
        const MaterialApp(
          home: AfterwordScene(
            scene: 'analyzing',
            motion: FoxMotion.analyze,
            repeat: true,
          ),
        ),
      );
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(tester.hasRunningAnimations, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(tester.hasRunningAnimations, isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}
