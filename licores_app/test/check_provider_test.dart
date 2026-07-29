import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:licores_app/data/repositories/contabilidad_repository.dart';
import 'package:licores_app/data/models/model_helpers.dart';

void main() {
  test('Debug getTotalComprasEfectivoRango', () async {
    await dotenv.load(fileName: '.env');
    final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
    final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';

    final client = SupabaseClient(supabaseUrl, supabaseAnonKey);
    final repo = ContabilidadRepository(client);

    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    print('now: $now');
    print('startOfMonth: $startOfMonth, dateOnly: ${dateOnly(startOfMonth)}');
    print('endOfMonth: $endOfMonth, dateOnly: ${dateOnly(endOfMonth)}');

    final sum = await repo.getTotalComprasEfectivoRango(startOfMonth, endOfMonth);
    print('Sum: $sum');

    final rows = await client
        .from('compras_inventario')
        .select()
        .eq('anulado', false)
        .eq('metodo_pago', 'efectivo')
        .gte('fecha', dateOnly(startOfMonth)!)
        .lte('fecha', dateOnly(endOfMonth)!);
    
    print('Query results:');
    for (final r in rows) {
      print('  - fecha: ${r['fecha']}, total: ${r['total']}');
    }

    expect(1, 1);
  });
}
