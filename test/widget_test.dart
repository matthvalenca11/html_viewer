import 'package:flutter_test/flutter_test.dart';

import 'package:html_viewer/main.dart';

void main() {
  testWidgets('Tela inicial mostra Abrir Arquivo', (WidgetTester tester) async {
    await tester.pumpWidget(const HtmlViewerApp());
    expect(find.text('Abrir Arquivo'), findsOneWidget);
  });
}
