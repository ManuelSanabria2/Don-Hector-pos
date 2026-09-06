import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/models/proveedor.dart';
import '../../data/models/producto.dart';
import '../../data/models/detalle_compra.dart';
import '../../data/repositories/compras_repository.dart';
import '../../data/repositories/inventario_repository.dart';
import '../inventario/inventario_providers.dart';
import '../contabilidad/contabilidad_providers.dart';
import 'compras_providers.dart';

/// Registra una compra nueva, o edita una ya registrada si se le pasa
/// [compraId].
///
/// Es la misma pantalla en los dos modos a propósito: lo que se corrige
/// son los mismos campos que se digitaron, así que separarlas obligaría
/// a mantener dos formularios en paralelo.
class CompraFormScreen extends ConsumerStatefulWidget {
  const CompraFormScreen({super.key, this.compraId});

  /// null = compra nueva.
  final String? compraId;

  @override
  ConsumerState<CompraFormScreen> createState() => _CompraFormScreenState();
}

class _CompraFormScreenState extends ConsumerState<CompraFormScreen> {
  final _formKey = GlobalKey<FormState>();

  String? _proveedorId;
  DateTime _fecha = DateTime.now();
  String _metodoPago = 'efectivo';
  // Método con el que se pagó la parte de contado en compras a crédito.
  String _metodoPagoContado = 'efectivo';
  late final TextEditingController _notasCtrl;
  late final TextEditingController _ajusteCtrl;
  late final TextEditingController _deudaCtrl;

  final List<_FormLinea> _lineas = [];
  bool _saving = false;

  /// Solo en edición: mientras se traen la factura y sus líneas.
  bool _cargando = false;
  String? _errorCarga;

  bool get _esEdicion => widget.compraId != null;

  @override
  void initState() {
    super.initState();
    _notasCtrl = TextEditingController();
    _ajusteCtrl = TextEditingController(text: '0');
    _deudaCtrl = TextEditingController(text: '0');

    if (_esEdicion) {
      _cargando = true;
      _cargarCompra();
    }
  }

  /// Trae la factura y deja el formulario tal como quedó registrada.
  Future<void> _cargarCompra() async {
    try {
      final compra = await ref
          .read(comprasRepositoryProvider)
          .getCompraConDetalle(widget.compraId!);

      if (!mounted) return;

      setState(() {
        _proveedorId = compra.proveedorId;
        _fecha = compra.fecha;
        _metodoPago = compra.metodoPago;
        _notasCtrl.text = compra.notas ?? '';
        _ajusteCtrl.text = CurrencyFormatter.copNumberOnly(
          compra.ajuste,
          allowDecimals: true,
        );
        _deudaCtrl.text = CurrencyFormatter.copNumberOnly(
          compra.valorDeuda,
          allowDecimals: true,
        );

        _lineas
          ..clear()
          ..addAll(compra.lineas.map(
            (l) => _FormLinea(
              productoId: l.productoId,
              nombreProducto: l.nombreProducto ?? 'Producto',
              cantidadCtrl: TextEditingController(text: l.cantidad.toString()),
              costoUnitarioCtrl: TextEditingController(
                text: CurrencyFormatter.copNumberOnly(
                  l.costoUnitario,
                  allowDecimals: true,
                ),
              ),
              onChanged: () => setState(() {}),
            ),
          ));

        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorCarga = e.toString();
        _cargando = false;
      });
    }
  }

  @override
  void dispose() {
    _notasCtrl.dispose();
    _ajusteCtrl.dispose();
    _deudaCtrl.dispose();
    for (final l in _lineas) {
      l.cantidadCtrl.dispose();
      l.costoUnitarioCtrl.dispose();
    }
    super.dispose();
  }

  num _calcularTotalCompra(bool esLider) {
    final baseTotal = _lineas.fold<num>(0, (sum, l) => sum + l.subtotal);
    if (esLider) {
      final ajuste = CurrencyFormatter.parseCop(_ajusteCtrl.text);
      return baseTotal + ajuste;
    }
    return baseTotal;
  }

  Future<void> _showCrearProveedorDialog() async {
    final nombreCtrl = TextEditingController();
    final telefonoCtrl = TextEditingController();
    final dialogFormKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF131310),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF262626)),
          ),
          title: const Text('Nuevo Proveedor', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Form(
            key: dialogFormKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: telefonoCtrl,
                  decoration: const InputDecoration(labelText: 'Teléfono (Opcional)'),
                  keyboardType: TextInputType.phone,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
            ),
            FilledButton(
              onPressed: () async {
                if (!dialogFormKey.currentState!.validate()) return;
                final name = nombreCtrl.text.trim();
                final phone = telefonoCtrl.text.trim();
                Navigator.pop(ctx);

                try {
                  await ref.read(comprasRepositoryProvider).upsertProveedor(
                    Proveedor(
                      id: '',
                      nombre: name,
                      telefono: phone.isEmpty ? null : phone,
                    ),
                  );
                  ref.invalidate(proveedoresProvider);
                  
                  final list = await ref.read(proveedoresProvider.future);
                  final match = list.firstWhere(
                    (p) => p.nombre == name,
                    orElse: () => list.last,
                  );
                  setState(() {
                    _proveedorId = match.id;
                  });
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error al crear proveedor: $e')),
                    );
                  }
                }
              },
              child: const Text('Crear'),
            ),
          ],
        );
      },
    );
  }

  void _abrirBuscarProductoBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF131310),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return _ProductSearchBottomSheet(
          onProductSelected: (producto) {
            setState(() {
              final existe = _lineas.any((l) => l.productoId == producto.id);
              if (existe) {
                final match = _lineas.firstWhere((l) => l.productoId == producto.id);
                final cantActual = int.tryParse(match.cantidadCtrl.text) ?? 1;
                match.cantidadCtrl.text = (cantActual + 1).toString();
              } else {
                _lineas.add(
                  _FormLinea(
                    productoId: producto.id,
                    nombreProducto: producto.nombre,
                    cantidadCtrl: TextEditingController(text: '1'),
                    costoUnitarioCtrl: TextEditingController(
                      text: CurrencyFormatter.copNumberOnly(producto.costo, allowDecimals: true),
                    ),
                    onChanged: () => setState(() {}),
                  ),
                );
              }
            });
          },
        );
      },
    );
  }

  Future<void> _guardar() async {
    if (_lineas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe agregar al menos un producto a la compra')),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    final proveedoresList = ref.read(proveedoresProvider).value ?? [];
    final selectedProv = proveedoresList.firstWhere(
      (p) => p.id == _proveedorId,
      orElse: () => Proveedor(id: '', nombre: ''),
    );
    final esLider = selectedProv.nombre.trim().toUpperCase() == 'LIDER';

    setState(() => _saving = true);

    try {
      final repo = ref.read(comprasRepositoryProvider);

      final ajuste = esLider ? CurrencyFormatter.parseCop(_ajusteCtrl.text) : 0;
      final valorDeuda = _metodoPago == 'credito' ? CurrencyFormatter.parseCop(_deudaCtrl.text) : 0;

      final lineasDeDetalle = _lineas.map((l) {
        return DetalleCompra(
          id: '',
          compraId: '',
          productoId: l.productoId,
          cantidad: int.parse(l.cantidadCtrl.text),
          costoUnitario: CurrencyFormatter.parseCop(l.costoUnitarioCtrl.text),
          subtotal: 0,
        );
      }).toList();

      final notas = _notasCtrl.text.trim().isEmpty ? null : _notasCtrl.text.trim();

      if (_esEdicion) {
        // La deuda no se manda: el RPC la recalcula como el total nuevo
        // menos lo que ya se haya pagado de esta factura.
        await repo.editarCompra(
          compraId: widget.compraId!,
          proveedorId: _proveedorId,
          fecha: _fecha,
          metodoPago: _metodoPago,
          notas: notas,
          lineas: lineasDeDetalle,
          ajuste: ajuste,
        );
      } else {
        await repo.registrarCompra(
          proveedorId: _proveedorId,
          fecha: _fecha,
          metodoPago: _metodoPago,
          notas: notas,
          lineas: lineasDeDetalle,
          ajuste: ajuste,
          valorDeuda: valorDeuda,
          metodoPagoContado: _metodoPagoContado,
        );
      }

      if (_esEdicion) {
        ref.invalidate(compraDetalleProvider(widget.compraId!));
      }
      ref.invalidate(comprasDelMesProvider);
      ref.invalidate(totalComprasRangoProvider);
      ref.invalidate(inventarioProductosProvider);
      ref.invalidate(stockBajoProvider);
      ref.invalidate(valorInventarioProvider);
      ref.invalidate(resumenHoyProvider);
      ref.invalidate(metricasMesProvider);
      ref.invalidate(resumenPatrimonioProvider);

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _esEdicion
                  ? 'Factura actualizada exitosamente'
                  : 'Compra registrada exitosamente',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _esEdicion
                  ? 'Error al editar la factura: $e'
                  : 'Error al registrar compra: $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final proveedoresAsync = ref.watch(proveedoresProvider);
    final colors = Theme.of(context).colorScheme;

    final proveedoresList = proveedoresAsync.value ?? [];
    final selectedProv = proveedoresList.firstWhere(
      (p) => p.id == _proveedorId,
      orElse: () => Proveedor(id: '', nombre: ''),
    );
    final esLider = selectedProv.nombre.trim().toUpperCase() == 'LIDER';
    final totalCompra = _calcularTotalCompra(esLider);

    if (_cargando) {
      return Scaffold(
        appBar: AppBar(title: const Text('Editar Factura')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorCarga != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Editar Factura')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: AppColors.rojo, size: 48),
                const SizedBox(height: 16),
                Text(
                  'No se pudo cargar la factura:\n$_errorCarga',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.blancoD, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_esEdicion ? 'Editar Factura' : 'Registrar Compra'),
      ),
      body: Form(
        key: _formKey,
        child: SafeArea(
          bottom: true,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      color: AppColors.superficie,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: Color(0xFF262626)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Información de la Compra',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: colors.primary,
                                  ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: proveedoresAsync.when(
                                    loading: () => const LinearProgressIndicator(),
                                    error: (err, _) => Text('Error proveedores: $err'),
                                    data: (list) => DropdownButtonFormField<String>(
                                      value: _proveedorId,
                                      decoration: const InputDecoration(labelText: 'Proveedor'),
                                      items: [
                                        const DropdownMenuItem(
                                          value: null,
                                          child: Text('Sin proveedor'),
                                        ),
                                        for (final prov in list)
                                          DropdownMenuItem(
                                            value: prov.id,
                                            child: Text(prov.nombre),
                                          ),
                                      ],
                                      onChanged: (val) {
                                        setState(() {
                                          _proveedorId = val;
                                          final matchProv = list.firstWhere(
                                            (p) => p.id == val,
                                            orElse: () => Proveedor(id: '', nombre: ''),
                                          );
                                          final esLiderNew = matchProv.nombre.trim().toUpperCase() == 'LIDER';
                                          if (!esLiderNew) {
                                            _ajusteCtrl.text = '0';
                                          }
                                        });
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton.filledTonal(
                                  icon: const Icon(Icons.add),
                                  tooltip: 'Nuevo Proveedor',
                                  onPressed: _showCrearProveedorDialog,
                                  style: IconButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.all(14),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Fecha de Compra'),
                              subtitle: Text(DateFormat('yyyy-MM-dd').format(_fecha)),
                              trailing: const Icon(Icons.calendar_today),
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _fecha,
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2100),
                                );
                                if (picked != null) {
                                  setState(() => _fecha = picked);
                                }
                              },
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              value: _metodoPago,
                              decoration: const InputDecoration(labelText: 'Método de pago'),
                              items: const [
                                DropdownMenuItem(value: 'efectivo', child: Text('Efectivo')),
                                DropdownMenuItem(value: 'nequi', child: Text('Nequi')),
                                DropdownMenuItem(value: 'daviplata', child: Text('Daviplata')),
                                DropdownMenuItem(value: 'transferencia', child: Text('Transferencia')),
                                DropdownMenuItem(value: 'credito', child: Text('Crédito')),
                                DropdownMenuItem(value: 'otro', child: Text('Otro')),
                              ],
                              onChanged: (val) {
                                setState(() {
                                  _metodoPago = val ?? 'efectivo';
                                  if (_metodoPago == 'credito') {
                                    _deudaCtrl.text = CurrencyFormatter.copNumberOnly(totalCompra, allowDecimals: true);
                                  } else {
                                    _deudaCtrl.text = '0';
                                  }
                                });
                              },
                            ),
                            if (esLider) ...[
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _ajusteCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Ajustar factura',
                                  prefixText: '\$ ',
                                  helperText:
                                      'Negativo para descontar (rebate, devolución)',
                                ),
                                keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true,
                                  signed: true,
                                ),
                                inputFormatters: [
                                  CopInputFormatter(
                                    allowDecimals: true,
                                    allowNegative: true,
                                  ),
                                ],
                                validator: (v) {
                                  if (v == null || v.isEmpty) return null;
                                  // Un descuento puede ser mayor que cero en
                                  // valor absoluto, pero no puede dejar la
                                  // factura en negativo.
                                  if (_calcularTotalCompra(true) < 0) {
                                    return 'El descuento deja la factura en negativo';
                                  }
                                  return null;
                                },
                                onChanged: (val) {
                                  setState(() {});
                                },
                              ),
                            ],
                            // En edición la deuda no se digita: el RPC la
                            // recalcula como el total nuevo menos lo ya
                            // pagado. Dejarla escribible permitiría que
                            // deuda y pagos dejaran de cuadrar.
                            if (_metodoPago == 'credito' && _esEdicion) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.superficie2,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.info_outline,
                                        size: 18, color: AppColors.ambar),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'La deuda se recalcula sola: total nuevo '
                                        'menos lo que ya se haya pagado de esta '
                                        'factura. Los pagos registrados no se tocan.',
                                        style: TextStyle(
                                          color: AppColors.blancoD,
                                          fontSize: 12,
                                          height: 1.3,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (_metodoPago == 'credito' && !_esEdicion) ...[
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _deudaCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Valor en deuda',
                                  prefixText: '\$ ',
                                ),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [CopInputFormatter(allowDecimals: true)],
                                validator: (v) {
                                  if (v == null || v.isEmpty) return 'Requerido';
                                  final val = CurrencyFormatter.parseCop(v);
                                  if (val <= 0) return 'Monto > 0';
                                  if (val > totalCompra) {
                                    return 'La deuda no puede superar el total';
                                  }
                                  return null;
                                },
                                onChanged: (val) {
                                  setState(() {});
                                },
                              ),
                              if (CurrencyFormatter.parseCop(_deudaCtrl.text) <
                                  totalCompra) ...[
                                const SizedBox(height: 12),
                                DropdownButtonFormField<String>(
                                  value: _metodoPagoContado,
                                  decoration: const InputDecoration(
                                    labelText: '¿Cómo pagaste la parte de contado?',
                                    helperText:
                                        'Solo el pago en efectivo descuenta de la caja',
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                        value: 'efectivo', child: Text('Efectivo')),
                                    DropdownMenuItem(
                                        value: 'nequi', child: Text('Nequi')),
                                    DropdownMenuItem(
                                        value: 'transferencia',
                                        child: Text('Transferencia')),
                                  ],
                                  onChanged: (val) {
                                    setState(() =>
                                        _metodoPagoContado = val ?? 'efectivo');
                                  },
                                ),
                              ],
                            ],
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _notasCtrl,
                              decoration: const InputDecoration(labelText: 'Notas (Opcional)'),
                              maxLines: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Productos Comprados',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        TextButton.icon(
                          onPressed: _abrirBuscarProductoBottomSheet,
                          icon: const Icon(Icons.add),
                          label: const Text('Agregar producto'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_lineas.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Column(
                            children: [
                              Icon(Icons.inventory_2_outlined, size: 48, color: colors.onSurfaceVariant.withOpacity(0.5)),
                              const SizedBox(height: 8),
                              Text(
                                'Aún no hay productos en la compra.',
                                style: TextStyle(color: colors.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _lineas.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (ctx, index) {
                          final linea = _lineas[index];
                          return Card(
                            color: AppColors.superficie,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(color: Color(0xFF262626)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          linea.nombreProducto,
                                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close, color: Colors.redAccent),
                                        onPressed: () {
                                          setState(() {
                                            _lineas.removeAt(index);
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          controller: linea.cantidadCtrl,
                                          decoration: const InputDecoration(
                                            labelText: 'Cantidad',
                                          ),
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                          validator: (v) {
                                            if (v == null || v.isEmpty) return 'Requerido';
                                            final val = int.tryParse(v) ?? 0;
                                            if (val <= 0) return 'Monto > 0';
                                            return null;
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: TextFormField(
                                          controller: linea.costoUnitarioCtrl,
                                          decoration: const InputDecoration(
                                            labelText: 'Costo unitario',
                                            prefixText: '\$ ',
                                          ),
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          inputFormatters: [CopInputFormatter(allowDecimals: true)],
                                          validator: (v) {
                                            if (v == null || v.isEmpty) return 'Requerido';
                                            final val = CurrencyFormatter.parseCop(v);
                                            if (val < 0) return 'Monto >= 0';
                                            return null;
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'Subtotal:',
                                        style: TextStyle(color: AppColors.blancoD, fontSize: 13),
                                      ),
                                      Text(
                                        CurrencyFormatter.cop(linea.subtotal),
                                        style: const TextStyle(
                                          color: AppColors.verde,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ],
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
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.superficie,
                  border: Border(top: BorderSide(color: Color(0xFF262626))),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total de la compra:',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        Text(
                          CurrencyFormatter.cop(totalCompra),
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: AppColors.ambar,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _guardar,
                        icon: _saving
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.check),
                        label: Text(
                          _esEdicion ? 'Guardar Cambios' : 'Registrar Compra',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormLinea {
  _FormLinea({
    required this.productoId,
    required this.nombreProducto,
    required this.cantidadCtrl,
    required this.costoUnitarioCtrl,
    required VoidCallback onChanged,
  }) {
    cantidadCtrl.addListener(onChanged);
    costoUnitarioCtrl.addListener(onChanged);
  }

  final String productoId;
  final String nombreProducto;
  final TextEditingController cantidadCtrl;
  final TextEditingController costoUnitarioCtrl;

  num get subtotal {
    final cant = int.tryParse(cantidadCtrl.text) ?? 0;
    final cost = CurrencyFormatter.parseCop(costoUnitarioCtrl.text);
    return cant * cost;
  }
}

class _ProductSearchBottomSheet extends ConsumerStatefulWidget {
  const _ProductSearchBottomSheet({required this.onProductSelected});
  final ValueChanged<Producto> onProductSelected;

  @override
  ConsumerState<_ProductSearchBottomSheet> createState() => _ProductSearchBottomSheetState();
}

class _ProductSearchBottomSheetState extends ConsumerState<_ProductSearchBottomSheet> {
  final _searchCtrl = TextEditingController();
  List<Producto> _allProducts = [];
  List<Producto> _filteredProducts = [];
  bool _loading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _searchCtrl.addListener(_filterProducts);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    try {
      final list = await ref.read(inventarioRepositoryProvider).getProductos();
      list.sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
      if (mounted) {
        setState(() {
          _allProducts = list;
          _filteredProducts = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _filterProducts() {
    final query = _searchCtrl.text.toLowerCase();
    setState(() {
      _filteredProducts = _allProducts.where((p) {
        return p.nombre.toLowerCase().contains(query) ||
            (p.codigoBarras?.toLowerCase().contains(query) ?? false);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Agregar Producto',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              labelText: 'Buscar por nombre o código de barras',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.4,
            ),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage.isNotEmpty
                    ? Center(child: Text('Error: $_errorMessage'))
                    : _filteredProducts.isEmpty
                        ? const Center(child: Padding(
                            padding: EdgeInsets.all(24.0),
                            child: Text('No se encontraron productos'),
                          ))
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: _filteredProducts.length,
                            separatorBuilder: (_, __) => const Divider(color: Colors.white10),
                            itemBuilder: (context, idx) {
                              final p = _filteredProducts[idx];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(p.nombre, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                subtitle: Text(
                                  'Stock: ${p.stockActual} | Costo: ${formatCOP(p.costo.toDouble())}',
                                  style: const TextStyle(color: AppColors.blancoD, fontSize: 13),
                                ),
                                trailing: const Icon(Icons.add_circle_outline, color: AppColors.ambar),
                                onTap: () {
                                  widget.onProductSelected(p);
                                  Navigator.pop(context);
                                },
                              );
                            },
                          ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
