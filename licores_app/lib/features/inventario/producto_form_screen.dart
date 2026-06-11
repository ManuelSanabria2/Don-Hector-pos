import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_routes.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/models/producto.dart';
import '../../data/repositories/inventario_repository.dart';
import 'inventario_providers.dart';

class ProductoFormScreen extends ConsumerStatefulWidget {
  const ProductoFormScreen({this.producto, super.key});

  final Producto? producto;

  @override
  ConsumerState<ProductoFormScreen> createState() => _ProductoFormScreenState();
}

class _ProductoFormScreenState extends ConsumerState<ProductoFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreController;
  late final TextEditingController _precioPublicoController;
  late final TextEditingController _precioMayoristaController;
  late final TextEditingController _costoController;
  late final TextEditingController _stockActualController;
  late final TextEditingController _stockMinimoController;
  late final TextEditingController _barcodeController;
  String? _categoriaId;
  bool _activo = true;
  bool _saving = false;

  Producto? get _producto => widget.producto;

  @override
  void initState() {
    super.initState();
    final producto = _producto;

    _nombreController = TextEditingController(text: producto?.nombre ?? '');
    _precioPublicoController = TextEditingController(
      text: producto == null
          ? ''
          : CurrencyFormatter.copNumberOnly(producto.precioPublico),
    );
    _precioMayoristaController = TextEditingController(
      text: producto == null
          ? ''
          : CurrencyFormatter.copNumberOnly(producto.precioMayorista),
    );
    _costoController = TextEditingController(
      text: producto == null ? '' : CurrencyFormatter.copNumberOnly(producto.costo),
    );
    _stockActualController = TextEditingController(
      text: producto?.stockActual.toString() ?? '0',
    );
    _stockMinimoController = TextEditingController(
      text: producto?.stockMinimo.toString() ?? '5',
    );
    _barcodeController = TextEditingController(
      text: producto?.codigoBarras ?? '',
    );
    _categoriaId = producto?.categoriaId;
    _activo = producto?.activo ?? true;
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _precioPublicoController.dispose();
    _precioMayoristaController.dispose();
    _costoController.dispose();
    _stockActualController.dispose();
    _stockMinimoController.dispose();
    _barcodeController.dispose();
    super.dispose();
  }

  Future<void> _scanBarcode() async {
    final barcode = await context.push<String>(AppRoutes.barcodeScanner);
    if (barcode == null || barcode.isEmpty) return;

    _barcodeController.text = barcode;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final isEditing = _producto != null;
    final nuevoStock = int.tryParse(_stockActualController.text) ?? 0;

    final producto = Producto(
      id: _producto?.id ?? '',
      nombre: _nombreController.text.trim(),
      categoriaId: _categoriaId,
      precioPublico: CurrencyFormatter.parseCop(_precioPublicoController.text),
      precioMayorista: CurrencyFormatter.parseCop(
        _precioMayoristaController.text,
      ),
      costo: CurrencyFormatter.parseCop(_costoController.text),
      stockActual: _producto?.stockActual ?? 0,
      stockMinimo: _producto?.stockMinimo ?? 5,
      codigoBarras: _barcodeController.text.trim().isEmpty
          ? null
          : _barcodeController.text.trim(),
      activo: _activo,
    );

    try {
      final repo = ref.read(inventarioRepositoryProvider);
      final productoId = await repo.upsertProducto(producto);
      
      if (isEditing) {
        final stockAnterior = _producto!.stockActual;
        final diff = nuevoStock - stockAnterior;
        if (diff != 0) {
          await repo.ajustarStock(
            productoId: productoId,
            cantidad: diff.abs(),
            tipo: diff > 0 ? 'entrada' : 'salida',
            motivo: 'Ajuste manual por edicion',
          );
        }
      } else {
        if (nuevoStock > 0) {
          await repo.ajustarStock(
            productoId: productoId,
            cantidad: nuevoStock,
            tipo: 'entrada',
            motivo: 'Stock inicial',
          );
        }
      }

      ref.invalidate(inventarioProductosProvider);
      ref.invalidate(stockBajoProvider);

      if (mounted) context.pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo guardar: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categorias = ref.watch(inventarioCategoriasProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_producto == null ? 'Nuevo producto' : 'Editar producto'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nombreController,
              decoration: const InputDecoration(labelText: 'Nombre'),
              textInputAction: TextInputAction.next,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Ingresa el nombre';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            categorias.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, stackTrace) => Text('Error categorias: $error'),
              data: (items) => DropdownButtonFormField<String>(
                initialValue: _categoriaId,
                decoration: const InputDecoration(labelText: 'Categoria'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Sin categoria'),
                  ),
                  for (final categoria in items)
                    DropdownMenuItem(
                      value: categoria.id,
                      child: Text(categoria.nombre),
                    ),
                ],
                onChanged: (value) => setState(() => _categoriaId = value),
              ),
            ),
            const SizedBox(height: 12),
            _MoneyField(
              controller: _precioPublicoController,
              label: 'Precio publico',
            ),
            const SizedBox(height: 12),
            _MoneyField(
              controller: _precioMayoristaController,
              label: 'Precio mayorista',
              validator: (_) {
                final mayorista = CurrencyFormatter.parseCop(
                  _precioMayoristaController.text,
                );
                final costo = CurrencyFormatter.parseCop(_costoController.text);
                if (mayorista < costo) {
                  return 'Debe ser mayor o igual al costo';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            _MoneyField(controller: _costoController, label: 'Costo'),
            const SizedBox(height: 12),
            _IntegerField(
              controller: _stockActualController,
              label: 'Stock actual',
              enabled: true,
              validator: (value) {
                final val = int.tryParse(value ?? '') ?? 0;
                if (val < 0) return 'Debe ser >= 0';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _barcodeController,
              decoration: InputDecoration(
                labelText: 'Codigo de barras',
                suffixIcon: IconButton(
                  tooltip: 'Escanear',
                  onPressed: _scanBarcode,
                  icon: const Icon(Icons.qr_code_scanner),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Activo'),
              value: _activo,
              onChanged: (value) => setState(() => _activo = value),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoneyField extends StatelessWidget {
  const _MoneyField({
    required this.controller,
    required this.label,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixText: '\$ ',
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [CopInputFormatter()],
      validator: validator,
    );
  }
}

class _IntegerField extends StatelessWidget {
  const _IntegerField({
    required this.controller,
    required this.label,
    this.validator,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String>? validator;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      validator: validator,
      enabled: enabled,
    );
  }
}
