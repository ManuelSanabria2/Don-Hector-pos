import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/models/proveedor.dart';
import '../../data/models/rebate_proveedor.dart';
import '../../data/repositories/compras_repository.dart';
import 'compras_providers.dart';

/// Saldo a favor ("rebate") que los proveedores otorgan por cumplir metas.
///
/// Es plata que el proveedor reconoce pero que solo se puede canjear en
/// mercancía suya, así que se lleva aparte del efectivo y del patrimonio:
/// se vuelve utilidad el día del canje, cuando entra inventario sin que
/// salga plata de la caja. El canje no se registra aquí — se hace
/// creando la compra con método de pago "Rebate".
class RebatesScreen extends ConsumerWidget {
  const RebatesScreen({super.key});

  Future<void> _registrarMovimiento(
    BuildContext context,
    WidgetRef ref, {
    String? proveedorId,
  }) async {
    final proveedores = ref.read(proveedoresProvider).value ?? const [];
    if (proveedores.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero registra un proveedor')),
      );
      return;
    }

    final guardado = await showDialog<bool>(
      context: context,
      builder: (ctx) => _MovimientoRebateDialog(
        proveedores: proveedores,
        proveedorIdInicial: proveedorId,
      ),
    );

    if (guardado == true) {
      ref.invalidate(saldosRebatesProvider);
      ref.invalidate(movimientosRebateProvider);
      ref.invalidate(resumenPatrimonioProvider);
    }
  }

  Future<void> _anular(
    BuildContext context,
    WidgetRef ref,
    RebateProveedor mov,
  ) async {
    if (mov.tipo == RebateProveedor.tipoCanje) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Un canje se revierte anulando su compra, no desde aquí.',
          ),
        ),
      );
      return;
    }

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.superficie,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Anular movimiento'),
        content: Text(
          'Se anulará ${mov.tipoLegible.toLowerCase()} '
          'por ${formatCOP(mov.monto.toDouble())}. '
          'El saldo del proveedor se recalcula sin este movimiento.',
          style: const TextStyle(color: AppColors.blancoD, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.gris)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.rojo),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Anular'),
          ),
        ],
      ),
    );

    if (confirmado != true) return;

    try {
      await ref.read(comprasRepositoryProvider).anularMovimientoRebate(mov.id);
      ref.invalidate(saldosRebatesProvider);
      ref.invalidate(movimientosRebateProvider);
      ref.invalidate(resumenPatrimonioProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo anular: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saldosAsync = ref.watch(saldosRebatesProvider);
    final movimientosAsync = ref.watch(movimientosRebateProvider(''));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rebates de proveedor'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _registrarMovimiento(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Registrar rebate'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(saldosRebatesProvider);
          ref.invalidate(movimientosRebateProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            const _ExplicacionCard(),
            const SizedBox(height: 16),
            Text(
              'SALDO POR PROVEEDOR',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.blancoD,
                    letterSpacing: 1.2,
                  ),
            ),
            const SizedBox(height: 8),
            saldosAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Text(
                'Error al cargar saldos: $err',
                style: const TextStyle(color: AppColors.rojo),
              ),
              data: (saldos) {
                final conSaldo = saldos.where((s) => s.saldo != 0).toList();
                if (conSaldo.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Ningún proveedor tiene saldo de rebate.',
                      style: TextStyle(color: AppColors.blancoD),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final saldo in conSaldo)
                      _SaldoTile(
                        saldo: saldo,
                        onAgregar: () => _registrarMovimiento(
                          context,
                          ref,
                          proveedorId: saldo.proveedorId,
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            Text(
              'MOVIMIENTOS',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.blancoD,
                    letterSpacing: 1.2,
                  ),
            ),
            const SizedBox(height: 8),
            movimientosAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Text(
                'Error al cargar movimientos: $err',
                style: const TextStyle(color: AppColors.rojo),
              ),
              data: (movimientos) {
                if (movimientos.isEmpty) {
                  return const Text(
                    'Todavía no hay movimientos de rebate.',
                    style: TextStyle(color: AppColors.blancoD),
                  );
                }
                return Column(
                  children: [
                    for (final mov in movimientos)
                      _MovimientoTile(
                        movimiento: mov,
                        onAnular: () => _anular(context, ref, mov),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ExplicacionCard extends StatelessWidget {
  const _ExplicacionCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.superficie,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: AppColors.ambar, size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'El rebate es plata que el proveedor reconoce por cumplir '
                'metas, pero solo se canjea en mercancía suya. Por eso no '
                'suma al efectivo ni al patrimonio: se vuelve ganancia el '
                'día del canje.\n\n'
                'Para canjearlo, registra la compra normal (con los costos '
                'reales) y elige método de pago "Rebate".',
                style: TextStyle(color: AppColors.blancoD, fontSize: 13, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SaldoTile extends StatelessWidget {
  const _SaldoTile({required this.saldo, required this.onAgregar});

  final SaldoRebateProveedor saldo;
  final VoidCallback onAgregar;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.superficie,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        title: Text(
          saldo.proveedor,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'Acumulado ${formatCOP(saldo.acumulado.toDouble())} · '
          'Canjeado ${formatCOP(saldo.canjeado.toDouble())}',
          style: const TextStyle(color: AppColors.blancoD, fontSize: 12),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatCOP(saldo.saldo.toDouble()),
              style: TextStyle(
                color: saldo.tieneSaldo ? AppColors.verde : AppColors.blancoD,
                fontWeight: FontWeight.w900,
              ),
            ),
            const Text(
              'disponible',
              style: TextStyle(color: AppColors.blancoD, fontSize: 11),
            ),
          ],
        ),
        onTap: onAgregar,
      ),
    );
  }
}

class _MovimientoTile extends StatelessWidget {
  const _MovimientoTile({required this.movimiento, required this.onAnular});

  final RebateProveedor movimiento;
  final VoidCallback onAnular;

  @override
  Widget build(BuildContext context) {
    final suma = movimiento.montoConSigno > 0;
    final formato = DateFormat('dd/MM/yyyy');

    return Card(
      color: AppColors.superficie,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(
          suma ? Icons.arrow_downward : Icons.arrow_upward,
          color: suma ? AppColors.verde : AppColors.ambar,
        ),
        title: Text(
          '${movimiento.tipoLegible} · '
          '${movimiento.nombreProveedor ?? 'Sin proveedor'}',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text(
          [
            formato.format(movimiento.fecha),
            if (movimiento.notas != null && movimiento.notas!.isNotEmpty)
              movimiento.notas!,
          ].join(' · '),
          style: const TextStyle(color: AppColors.blancoD, fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${suma ? '+' : '-'}${formatCOP(movimiento.monto.toDouble())}',
              style: TextStyle(
                color: suma ? AppColors.verde : AppColors.ambar,
                fontWeight: FontWeight.w700,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              color: AppColors.gris,
              tooltip: 'Anular movimiento',
              onPressed: onAnular,
            ),
          ],
        ),
      ),
    );
  }
}

/// Alta de una acumulación, un ajuste o un vencimiento. El canje no está
/// aquí: lo crea registrar_compra para que descontar el saldo y meter la
/// mercancía sean la misma transacción.
class _MovimientoRebateDialog extends ConsumerStatefulWidget {
  const _MovimientoRebateDialog({
    required this.proveedores,
    this.proveedorIdInicial,
  });

  final List<Proveedor> proveedores;
  final String? proveedorIdInicial;

  @override
  ConsumerState<_MovimientoRebateDialog> createState() =>
      _MovimientoRebateDialogState();
}

class _MovimientoRebateDialogState
    extends ConsumerState<_MovimientoRebateDialog> {
  final _formKey = GlobalKey<FormState>();
  final _montoCtrl = TextEditingController();
  final _notasCtrl = TextEditingController();

  late String _proveedorId;
  String _tipo = RebateProveedor.tipoAcumulacion;
  DateTime _fecha = DateTime.now();
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _proveedorId = widget.proveedorIdInicial ?? widget.proveedores.first.id;
  }

  @override
  void dispose() {
    _montoCtrl.dispose();
    _notasCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);
    try {
      await ref.read(comprasRepositoryProvider).registrarMovimientoRebate(
            proveedorId: _proveedorId,
            monto: CurrencyFormatter.parseCop(_montoCtrl.text),
            tipo: _tipo,
            fecha: _fecha,
            notas: _notasCtrl.text.trim().isEmpty
                ? null
                : _notasCtrl.text.trim(),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _guardando = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo registrar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.superficie,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Movimiento de rebate'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: _proveedorId,
                decoration: const InputDecoration(labelText: 'Proveedor'),
                items: [
                  for (final prov in widget.proveedores)
                    DropdownMenuItem(value: prov.id, child: Text(prov.nombre)),
                ],
                onChanged: (val) =>
                    setState(() => _proveedorId = val ?? _proveedorId),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _tipo,
                decoration: const InputDecoration(
                  labelText: 'Tipo',
                  helperText: 'El canje se hace registrando la compra',
                ),
                items: const [
                  DropdownMenuItem(
                    value: RebateProveedor.tipoAcumulacion,
                    child: Text('Acumulación (el proveedor lo reconoce)'),
                  ),
                  DropdownMenuItem(
                    value: RebateProveedor.tipoAjuste,
                    child: Text('Ajuste a favor'),
                  ),
                  DropdownMenuItem(
                    value: RebateProveedor.tipoVencimiento,
                    child: Text('Vencimiento (se pierde)'),
                  ),
                ],
                onChanged: (val) => setState(() => _tipo = val ?? _tipo),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _montoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Monto',
                  prefixText: '\$ ',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [CopInputFormatter(allowDecimals: true)],
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Requerido';
                  if (CurrencyFormatter.parseCop(v) <= 0) return 'Monto > 0';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Fecha'),
                subtitle: Text(DateFormat('yyyy-MM-dd').format(_fecha)),
                trailing: const Icon(Icons.calendar_today, size: 18),
                onTap: () async {
                  final elegida = await showDatePicker(
                    context: context,
                    initialDate: _fecha,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (elegida != null) setState(() => _fecha = elegida);
                },
              ),
              TextFormField(
                controller: _notasCtrl,
                decoration: const InputDecoration(
                  labelText: 'Notas (opcional)',
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar', style: TextStyle(color: AppColors.gris)),
        ),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}
