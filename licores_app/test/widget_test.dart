import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:licores_app/shared/widgets/loading_screen.dart';

void main() {
  testWidgets('loading screen renders message', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: LoadingScreen(message: 'Verificando sesion...')),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Verificando sesion...'), findsOneWidget);
  });
}
