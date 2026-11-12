import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vms_moldova/app.dart';

void main() {
  testWidgets('aplicația pornește și afișează meniul', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('ro');
    await tester.pumpWidget(const VmsApp());
    expect(find.text('Dobânzi'), findsWidgets);
    expect(find.text('Portofoliu'), findsWidgets);
    expect(find.text('Licitații'), findsWidgets);
  });
}
