import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:pilipala/common/widgets/recommendation_visibility.dart';

void main() {
  testWidgets(
      'prefetched or inactive card does not become exposure; actual visibility does',
      (tester) async {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    var active = false;
    var starts = 0;
    var ends = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RecommendationVisibility(
                key: const ValueKey('card'),
                isActive: () => active,
                clock: () => tester.binding.clock.now().millisecondsSinceEpoch,
                onStart: (_) => starts++,
                onEnd: (_, __) => ends++,
                child: const SizedBox(width: 100, height: 100)))));
    await tester.pump(const Duration(seconds: 2));
    expect(starts, 0);
    active = true;
    for (var n = 0; n < 6; n++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(starts, 1);
    active = false;
    await tester.pump(const Duration(milliseconds: 250));
    expect(ends, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
