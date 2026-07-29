import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  print('Loading env...');
  await dotenv.load(fileName: '.env');
  final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  print('Initializing Supabase client...');
  final supabase = SupabaseClient(supabaseUrl, supabaseAnonKey);

  print('Querying capital_negocio...');
  final capitalRows = await supabase.from('capital_negocio').select();
  print('Capital Negocio Rows:');
  for (final row in capitalRows) {
    print('  - ID: ${row['id']}, efectivo_inicial: ${row['efectivo_inicial']}, valor_inventario_inicial: ${row['valor_inventario_inicial']}, fecha: ${row['fecha_registro']}');
  }

  print('\nQuerying compras_inventario in cash (non-annulled)...');
  final comprasRows = await supabase
      .from('compras_inventario')
      .select('fecha, total, metodo_pago, anulado')
      .eq('metodo_pago', 'efectivo')
      .eq('anulado', false);
  print('Compras en efectivo:');
  num totalComprasEfectivo = 0;
  for (final row in comprasRows) {
    print('  - Fecha: ${row['fecha']}, total: ${row['total']}, metodo_pago: ${row['metodo_pago']}, anulado: ${row['anulado']}');
    totalComprasEfectivo += row['total'] as num? ?? 0;
  }
  print('Total Compras Efectivo: $totalComprasEfectivo');

  print('\nQuerying active capital general summary...');
  final generalRows = await supabase.from('resumen_financiero_general').select();
  print('Resumen General:');
  for (final row in generalRows) {
    print('  - capital_efectivo_inicial: ${row['capital_efectivo_inicial']}');
    print('  - capital_inventario_inicial: ${row['capital_inventario_inicial']}');
    print('  - total_ventas_historico: ${row['total_ventas_historico']}');
    print('  - total_compras_historico: ${row['total_compras_historico']}');
    print('  - total_gastos_historico: ${row['total_gastos_historico']}');
    print('  - valor_inventario_actual: ${row['valor_inventario_actual']}');
    print('  - patrimonio_estimado: ${row['patrimonio_estimado']}');
  }

  print('\nCheck done.');
}
