import 'package:flutter_test/flutter_test.dart';
import 'package:lfm_music_app/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const AuraStreamApp());
  });
}
