import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawress/ui/widgets.dart';

void main() {
  testWidgets('BackToTop shows past two screens and scrolls up', (
    tester,
  ) async {
    final controller = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BackToTop(
            child: ListView.builder(
              controller: controller,
              itemCount: 500,
              itemBuilder: (_, index) =>
                  SizedBox(height: 100, child: Text('row $index')),
            ),
          ),
        ),
      ),
    );
    final arrow = find.byIcon(Icons.arrow_upward_rounded);
    double opacity() => tester
        .widget<AnimatedOpacity>(
          find.ancestor(of: arrow, matching: find.byType(AnimatedOpacity)),
        )
        .opacity;
    expect(opacity(), 0);

    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(2000));
    expect(opacity(), 1);

    await tester.tap(arrow);
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
    expect(opacity(), 0);
  });
}
