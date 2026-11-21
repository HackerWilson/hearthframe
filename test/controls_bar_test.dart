import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearthframe/controls_bar.dart';
import 'package:hearthframe/l10n.dart';

void main() {
  Widget controls({required bool visible, required VoidCallback onNext}) =>
      MaterialApp(
        localizationsDelegates: const [
          AppStrings.delegate,
          ...GlobalMaterialLocalizations.delegates
        ],
        home: Scaffold(
            body: Stack(children: [
          SlideshowControls(
            visible: visible,
            paused: false,
            onPrevious: () {},
            onPlayPause: () {},
            onNext: onNext,
            onSource: () {},
            onRefresh: () {},
            onSettings: () {},
          ),
        ])),
      );

  testWidgets('visible controls respond and hidden controls cannot take focus',
      (tester) async {
    var next = 0;
    await tester.pumpWidget(controls(visible: true, onNext: () => next++));
    await tester.tap(find.byTooltip('Next'));
    expect(next, 1);
    await tester.pumpWidget(controls(visible: false, onNext: () => next++));
    await tester.pumpAndSettle();
    final focus = tester.widget<ExcludeFocus>(find.byType(ExcludeFocus));
    expect(focus.excluding, isTrue);
    final ignoring = tester.widget<IgnorePointer>(find
        .descendant(
            of: find.byType(SlideshowControls),
            matching: find.byType(IgnorePointer))
        .first);
    expect(ignoring.ignoring, isTrue);
  });

  testWidgets('controls fit a narrow tablet window without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(controls(visible: true, onNext: () {}));
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Settings'), findsOneWidget);
  });
}
