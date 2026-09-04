import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/repositories/compras_repository.dart';
import '../inventario/inventario_providers.dart';
import '../contabilidad/contabilidad_providers.dart';
import 'compras_providers.dart';
import 'compra_form_screen.dart';
import 'compra_detalle_screen.dart';
import 'rebates_screen.dart';

class ComprasScreen extends ConsumerStatefulWidget {
  const ComprasScreen({super.key});

  @override
  ConsumerState<ComprasScreen> createState() => _ComprasScreenState();
}

class _ComprasScreenState extends ConsumerState<ComprasScreen> {
  DateTimeRange? _selectedRange;

  DateTimeRange get _currentMonthRange {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    return DateTimeRange(start: start, end: end);
  }

  Future<void> _confirmarAnulacion(String compraId) async {
    final motivoCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final conf = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131310),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF262626)),
        ),
        title: const Text('Anular Compra', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '¿Está seguro de que desea anular esta compra? Esto revertirá el stock de los productos correspondientes.',
                style: TextStyle(color: AppColors.blancoD, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: motivoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Motivo de anulación',
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Requerido' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Anular'),
          ),
        ],
      ),
    );

    if (conf == true) {
      try {
        final motivo = motivoCtrl.text.trim();
        await ref.read(comprasRepositoryProvider).anularCompra(compraId, motivo: motivo);
        
        ref.invalidate(comprasDelMesProvider);
        if (_selectedRange != null) {
          ref.invalidate(comprasPorRangoProvider(_selectedRange!));
        }
        ref.invalidate(totalComprasRangoProvider);
        ref.invalidate(inventarioProductosProvider);
        ref.invalidate(stockBajoProvider);
        ref.invalidate(valorInventarioProvider);
        ref.invalidate(resumenHoyProvider);
        ref.invalidate(metricasMesProvider);
        ref.invalidate(resumenPatrimonioProvider);
        // Si la compra se pagó con rebate, el canje se anuló con ella
        // y el saldo del proveedor volvió a estar disponible.
        ref.invalidate(saldosRebatesProvider);
        ref.invalidate(movimientosRebateProvider);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Compra anulada exitosamente')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al anular compra: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rangeToQuery = _selectedRange ?? _currentMonthRange;
    final purchasesAsync = _selectedRange == null
        ? ref.watch(comprasDelMesProvider)
        : ref.watch(comprasPorRangoProvider(_selectedRange!));

    final totalAsync = ref.watch(totalComprasRangoProvider(rangeToQuery));
    final proveedoresAsync = ref.watch(proveedoresProvider);
    final saldoRebateAsync = ref.watch(saldoRebateTotalProvider);
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Compras de Inventario',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w400,
                color: AppColors.blanco,
              ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.card_giftcard, color: Colors.white70),
            tooltip: 'Rebates de proveedor',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RebatesScreen()),
            ),
          ),
          IconButton(
            icon: Icon(
              _selectedRange == null ? Icons.calendar_today : Icons.calendar_today_outlined,
              color: _selectedRange == null ? Colors.white70 : AppColors.ambar,
            ),
            tooltip: 'Filtrar rango de fechas',
            onPressed: () async {
              final picked = await showDateRangePicker(
                context: context,
                initialDateRange: _selectedRange ?? _currentMonthRange,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
                builder: (context, child) {
                  return Theme(
                    data: Theme.of(context).copyWith(
                      colorScheme: const ColorScheme.dark(
                        primary: AppColors.ambar,
                        onPrimary: Colors.black,
                        surface: Color(0xFF131310),
                        onSurface: AppColors.blanco,
                      ),
                      dialogBackgroundColor: const Color(0xFF131310),
                    ),
                    child: child!,
                  );
                },
              );
              if (picked != null) {
                setState(() {
                  _selectedRange = picked;
                });
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              color: AppColors.superficie,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFF262626)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          const Text(
                            'Total comprado este mes',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.blancoD, fontSize: 12),
                          ),
                          const SizedBox(height: 6),
                          totalAsync.when(
                            data: (total) => Text(
                              formatCOP(total.toDouble()),
                              style: const TextStyle(
                                color: AppColors.ambar,
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                              ),
                            ),
                            loading: () => const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            error: (_, __) => const Text('Error', style: TextStyle(color: Colors.redAccent)),
                          ),
                        ],
                      ),
                    ),
                    Container(width: 1, height: 40, color: Colors.white10),
                    Expanded(
                      child: InkWell(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const RebatesScreen()),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'Saldo rebate',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.blancoD, fontSize: 12),
                            ),
                            const SizedBox(height: 6),
                            saldoRebateAsync.when(
                              data: (saldo) => Text(
                                formatCOP(saldo.toDouble()),
                                style: TextStyle(
                                  color: saldo > 0 ? AppColors.verde : AppColors.blancoD,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                ),
                              ),
                              loading: () => const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              error: (_, __) => const Text('!', style: TextStyle(color: Colors.redAccent)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(width: 1, height: 40, color: Colors.white10),
                    Expanded(
                      child: Column(
                        children: [
                          const Text(
                            'Proveedores',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.blancoD, fontSize: 12),
                          ),
                          const SizedBox(height: 6),
                          proveedoresAsync.when(
                            data: (list) => Text(
                              list.length.toString(),
                              style: const TextStyle(
                                color: AppColors.verde,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            loading: () => const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            error: (_, __) => const Text('!', style: TextStyle(color: Colors.redAccent)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_selectedRange != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.filter_list, size: 16, color: AppColors.ambar),
                      const SizedBox(width: 8),
                      Text(
                        'Rango: ${DateFormat('dd/MM/yyyy').format(_selectedRange!.start)} a ${DateFormat('dd/MM/yyyy').format(_selectedRange!.end)}',
                        style: const TextStyle(color: AppColors.blancoD, fontSize: 13),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: () => setState(() => _selectedRange = null),
                    child: const Text('Limpiar', style: TextStyle(color: Colors.redAccent)),
                  ),
                ],
              ),
            ),
          Expanded(
            child: purchasesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Error al cargar compras: $err', style: const TextStyle(color: Colors.redAccent)),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () {
                        ref.invalidate(comprasDelMesProvider);
                        if (_selectedRange != null) {
                          ref.invalidate(comprasPorRangoProvider(_selectedRange!));
                        }
                      },
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
              data: (compras) {
                if (compras.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 64, color: colors.onSurfaceVariant.withOpacity(0.5)),
                        const SizedBox(height: 16),
                        Text(
                          _selectedRange == null
                              ? 'No hay compras registradas este mes.'
                              : 'No hay compras en el rango seleccionado.',
                          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 15),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(comprasDelMesProvider);
                    if (_selectedRange != null) {
                      ref.invalidate(comprasPorRangoProvider(_selectedRange!));
                    }
                  },
                  child: ListView.builder(
                    itemCount: compras.length,
                    itemBuilder: (context, index) {
                      final compra = compras[index];
                      
                      Widget cardContent = Card(
                        color: AppColors.superficie,
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: compra.anulado ? Colors.redAccent.withOpacity(0.3) : const Color(0xFF262626),
                          ),
                        ),
                        child: ListTile(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => CompraDetalleScreen(compraId: compra.id),
                              ),
                            );
                          },
                          title: Row(
                            children: [
                              Text(
                                DateFormat('dd/MM/yyyy').format(compra.fecha),
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 8),
                              if (compra.anulado)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'ANULADA',
                                    style: TextStyle(color: Colors.redAccent, fontSize: 9, fontWeight: FontWeight.bold),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                compra.nombreProveedor ?? 'Sin proveedor',
                                style: const TextStyle(color: AppColors.blancoD),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white10,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  compra.metodoPago.toUpperCase(),
                                  style: const TextStyle(fontSize: 10, color: AppColors.blancoD, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                formatCOP(compra.total.toDouble()),
                                style: const TextStyle(
                                  color: AppColors.ambar,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              if (!compra.anulado) ...[
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                  tooltip: 'Anular Compra',
                                  onPressed: () => _confirmarAnulacion(compra.id),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );

                      if (compra.anulado) {
                        return Opacity(
                          opacity: 0.5,
                          child: cardContent,
                        );
                      }
                      return cardContent;
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CompraFormScreen()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
