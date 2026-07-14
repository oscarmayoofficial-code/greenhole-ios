import 'package:flutter_test/flutter_test.dart';

import 'package:greenhole/main.dart';

void main() {
  testWidgets('App builds and shows the brand + hint', (tester) async {
    await tester.pumpWidget(const GreenHoleApp());
    await tester.pump();

    expect(find.text('GREEN HOLE'), findsOneWidget);
    expect(find.textContaining('Copy a video link'), findsWidgets);
  });
}
