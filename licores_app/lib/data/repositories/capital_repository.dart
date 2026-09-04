import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/capital_negocio.dart';
import '../models/model_helpers.dart';
import 'supabase_providers.dart';

final capitalRepositoryProvider = Provider<CapitalRepository>((ref) {
  return CapitalRepository(ref.watch(supabaseClientProvider));
});

class CapitalRepository {
  const CapitalRepository(this._client);

  final SupabaseClient _client;

  Future<CapitalNegocio?> getCapital() async {
    final rows = await _client.from('capital_negocio').select().limit(1);
    if (rows.isEmpty) return null;
    return CapitalNegocio.fromJson(rows.first);
  }

  Future<void> upsertCapital(CapitalNegocio c) async {
    final map = _withoutNulls(c.toJson());
    if (c.id.isEmpty) {
      map.remove('id');
      await _client.from('capital_negocio').insert(map);
    } else {
      await _client.from('capital_negocio').update(map).eq('id', c.id);
    }
  }

  Future<Map<String, num>> getResumenFinancieroGeneral() async {
    final rows = await _client.from('resumen_financiero_general').select().limit(1);
    if (rows.isEmpty) {
      return {
        'capital_efectivo_inicial': 0,
        'capital_inventario_inicial': 0,
        'total_ventas_historico': 0,
        'total_compras_historico': 0,
        'total_gastos_historico': 0,
        'valor_inventario_actual': 0,
        'patrimonio_estimado': 0,
        'deuda_prestamos': 0,
        'interes_prestamos_pagado': 0,
        'dinero_disponible': 0,
        'cuentas_por_cobrar': 0,
        'deuda_proveedores': 0,
        'saldo_rebates': 0,
        'total_rebates_canjeado': 0,
      };
    }
    
    final row = rows.first;
    return {
      'capital_efectivo_inicial': parseNum(row['capital_efectivo_inicial']),
      'capital_inventario_inicial': parseNum(row['capital_inventario_inicial']),
      'total_ventas_historico': parseNum(row['total_ventas_historico']),
      'total_compras_historico': parseNum(row['total_compras_historico']),
      'total_gastos_historico': parseNum(row['total_gastos_historico']),
      'valor_inventario_actual': parseNum(row['valor_inventario_actual']),
      'patrimonio_estimado': parseNum(row['patrimonio_estimado']),
      'deuda_prestamos': parseNum(row['deuda_prestamos']),
      'interes_prestamos_pagado': parseNum(row['interes_prestamos_pagado']),
      'dinero_disponible': parseNum(row['dinero_disponible']),
      'cuentas_por_cobrar': parseNum(row['cuentas_por_cobrar']),
      'deuda_proveedores': parseNum(row['deuda_proveedores']),
      // Fuera del patrimonio a propósito: es saldo canjeable solo en
      // mercancía, todavía no es plata ni inventario.
      'saldo_rebates': parseNum(row['saldo_rebates']),
      'total_rebates_canjeado': parseNum(row['total_rebates_canjeado']),
    };
  }
}

Map<String, dynamic> _withoutNulls(Map<String, dynamic> values) {
  return Map.fromEntries(values.entries.where((entry) => entry.value != null));
}
