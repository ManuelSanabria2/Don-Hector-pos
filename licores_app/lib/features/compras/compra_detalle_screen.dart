import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/models/compra_inventario.dart';
import '../../data/repositories/compras_repository.dart';
import '../contabilidad/contabilidad_providers.dart';
import 'compras_providers.dart';
import 'compra_form_screen.dart';

class CompraDetalleScreen extends ConsumerWidget {
  const CompraDetalleScreen({
    super.key,
    required this.compraId,
  });

  final String compraId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compraAsync = ref.watch(compraDetalleProvider(compraId));
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: AppColors.negro,
      appBar: AppBar(
        title: const Text('Detalle de Compra'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: compraAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.ambar),
        ),
        error: (err, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: AppColors.rojo, size: 60),
                const SizedBox(height: 16),
                Text(
                  'Error al cargar el detalle de la compra',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.blanco,
                        fontWeight: FontWeight.bold,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  err.toString(),
                  style: const TextStyle(color: AppColors.blancoD, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(compraDetalleProvider(compraId)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
        data: (compra) {
          // El desglose solo aporta cuando hay un ajuste que explicar; si
          // no, el total por si solo ya dice todo.
          final tieneAjuste = compra.ajuste != 0;
          final esDescuento = compra.ajuste < 0;
          final subtotalCalculado = compra.lineas.fold<num>(
            0,
            (sum, l) => sum + (l.cantidad * l.costoUnitario),
          );

          return Column(
            children: [
              if (compra.anulado)
                Container(
                  width: double.infinity,
                  color: AppColors.rojo.withOpacity(0.2),
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: AppColors.rojo),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'COMPRA ANULADA',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                color: AppColors.rojo,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Tarjeta de información principal
                    Card(
                      color: AppColors.superficie,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Proveedor',
                                        style: TextStyle(
                                          color: AppColors.blancoD,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        compra.nombreProveedor ?? 'Sin proveedor',
                                        style: const TextStyle(
                                          color: AppColors.blanco,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.superficie2,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    compra.metodoPago.toUpperCase(),
                                    style: const TextStyle(
                                      color: AppColors.ambar,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(color: Colors.white10, height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Fecha de compra',
                                      style: TextStyle(
                                        color: AppColors.blancoD,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      DateFormat('dd / MM / yyyy').format(compra.fecha),
                                      style: const TextStyle(
                                        color: AppColors.blanco,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    const Text(
                                      'Hora de registro',
                                      style: TextStyle(
                                        color: AppColors.blancoD,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      compra.createdAt != null
                                          ? DateFormat('hh:mm a').format(compra.createdAt!.toLocal())
                                          : 'N/A',
                                      style: const TextStyle(
                                        color: AppColors.blanco,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            if (compra.notas != null && compra.notas!.isNotEmpty) ...[
                              const Divider(color: Colors.white10, height: 24),
                              const Text(
                                'Notas',
                                style: TextStyle(
                                  color: AppColors.blancoD,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                compra.notesText,
                                style: const TextStyle(
                                  color: AppColors.blanco,
                                  fontSize: 14,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Productos Adquiridos',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppColors.blanco,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    if (compra.lineas.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32.0),
                          child: Text(
                            'No hay productos registrados en esta compra.',
                            style: TextStyle(color: AppColors.blancoD),
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: compra.lineas.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final linea = compra.lineas[index];
                          return Card(
                            color: AppColors.superficie,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          linea.nombreProducto ?? 'Producto desconocido',
                                          style: const TextStyle(
                                            color: AppColors.blanco,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${linea.cantidad} un.  ×  ${CurrencyFormatter.cop(linea.costoUnitario)}',
                                          style: const TextStyle(
                                            color: AppColors.blancoD,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    CurrencyFormatter.cop(linea.cantidad * linea.costoUnitario),
                                    style: const TextStyle(
                                      color: AppColors.verde,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
              // Panel de resumen y totales
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: AppColors.superficie,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (tieneAjuste) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Subtotal productos:',
                              style: TextStyle(
                                color: AppColors.blancoD,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              CurrencyFormatter.cop(subtotalCalculado),
                              style: const TextStyle(
                                color: AppColors.blanco,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              esDescuento ? 'Descuento:' : 'Ajustar factura:',
                              style: const TextStyle(
                                color: AppColors.blancoD,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              '${esDescuento ? '− ' : '+ '}'
                              '${CurrencyFormatter.cop(compra.ajuste.abs())}',
                              style: TextStyle(
                                color: esDescuento ? AppColors.verde : AppColors.ambar,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const Divider(color: Colors.white10, height: 20),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            compra.anulado ? 'Total original:' : 'Total de la compra:',
                            style: const TextStyle(
                              color: AppColors.blanco,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            CurrencyFormatter.cop(compra.total),
                            style: const TextStyle(
                              color: AppColors.verde,
                              fontWeight: FontWeight.w900,
                              fontSize: 22,
                            ),
                          ),
                        ],
                      ),
                      if (compra.metodoPago == 'credito') ...[
                        const Divider(color: Colors.white10, height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Valor en deuda:',
                              style: TextStyle(
                                color: AppColors.rojo,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            Text(
                              CurrencyFormatter.cop(compra.valorDeuda),
                              style: const TextStyle(
                                color: AppColors.rojo,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (compra.metodoPago == 'credito' && compra.valorDeuda > 0 && !compra.anulado) ...[
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.rojo,
                              side: const BorderSide(color: AppColors.rojo),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text(
                              'REGISTRAR PAGO',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.1,
                              ),
                            ),
                            onPressed: () async {
                              final pago = await showDialog<_PagoCompraResult>(
                                context: context,
                                builder: (ctx) =>
                                    _PagoCompraDialog(saldo: compra.valorDeuda),
                              );

                              if (pago != null) {
                                try {
                                  await ref
                                      .read(comprasRepositoryProvider)
                                      .registrarPagoCompra(
                                        compraId: compra.id,
                                        monto: pago.monto,
                                        metodoPago: pago.metodoPago,
                                      );

                                  ref.invalidate(compraDetalleProvider(compra.id));
                                  ref.invalidate(comprasDelMesProvider);
                                  ref.invalidate(totalComprasRangoProvider);
                                  ref.invalidate(resumenHoyProvider);
                                  ref.invalidate(metricasMesProvider);
                                  ref.invalidate(metricasDiaProvider(compra.fecha));

                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Pago registrado exitosamente')),
                                    );
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Error al registrar el pago: $e')),
                                    );
                                  }
                                }
                              }
                            },
                          ),
                        ),
                      ],
                      // Editar la factura completa: proveedor, fecha,
                      // método, descuento y líneas. Una compra anulada ya
                      // no se toca.
                      if (!compra.anulado) ...[
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.ambar,
                              side: const BorderSide(color: AppColors.ambar),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text(
                              'EDITAR FACTURA',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.1,
                              ),
                            ),
                            onPressed: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      CompraFormScreen(compraId: compra.id),
                                ),
                              );
                              ref.invalidate(compraDetalleProvider(compra.id));
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// Extensión para formatear o procesar notas si es necesario
extension on CompraInventario {
  String get notesText {
    if (notas == null) return '';
    // Si contiene "ANULADA:", podemos dejarlo o limpiarlo si ya mostramos el banner.
    // Aunque es mejor mostrar las notas tal cual por si hay aclaraciones adicionales.
    return notas!;
  }
}

class _PagoCompraResult {
  const _PagoCompraResult({required this.monto, required this.metodoPago});

  final num monto;
  final String metodoPago;
}

/// Diálogo para registrar un pago (total o parcial) de la deuda de una
/// compra a crédito, indicando el método de pago para que el efectivo
/// de caja se descuente correctamente.
class _PagoCompraDialog extends StatefulWidget {
  const _PagoCompraDialog({required this.saldo});

  final num saldo;

  @override
  State<_PagoCompraDialog> createState() => _PagoCompraDialogState();
}

class _PagoCompraDialogState extends State<_PagoCompraDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _montoCtrl;
  String _metodoPago = 'efectivo';

  @override
  void initState() {
    super.initState();
    _montoCtrl = TextEditingController(
      text: CurrencyFormatter.copNumberOnly(widget.saldo, allowDecimals: true),
    );
  }

  @override
  void dispose() {
    _montoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF131310),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF262626)),
      ),
      title: const Text('Registrar Pago', style: TextStyle(fontWeight: FontWeight.bold)),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Deuda pendiente: ${CurrencyFormatter.cop(widget.saldo)}',
              style: const TextStyle(color: AppColors.blancoD, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _montoCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Monto a pagar',
                prefixText: '\$ ',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [CopInputFormatter(allowDecimals: true)],
              validator: (v) {
                if (v == null || v.isEmpty) return 'Requerido';
                final val = CurrencyFormatter.parseCop(v);
                if (val <= 0) return 'Monto > 0';
                if (val > widget.saldo) {
                  return 'No puede superar la deuda pendiente';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _metodoPago,
              decoration: const InputDecoration(
                labelText: 'Método de pago',
                helperText: 'Solo el efectivo descuenta de la caja',
              ),
              items: const [
                DropdownMenuItem(value: 'efectivo', child: Text('Efectivo')),
                DropdownMenuItem(value: 'nequi', child: Text('Nequi')),
                DropdownMenuItem(value: 'transferencia', child: Text('Transferencia')),
              ],
              onChanged: (val) => setState(() => _metodoPago = val ?? 'efectivo'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.verde),
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _PagoCompraResult(
                monto: CurrencyFormatter.parseCop(_montoCtrl.text),
                metodoPago: _metodoPago,
              ),
            );
          },
          child: const Text('Registrar', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
