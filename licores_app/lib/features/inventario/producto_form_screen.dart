import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_routes.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/models/categoria.dart';
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
  late final TextEditingController _agregarStockController;
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
    _agregarStockController = TextEditingController(text: '');
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
    _agregarStockController.dispose();
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
    final stockActualBase = int.tryParse(_stockActualController.text) ?? 0;
    final stockAdicional = int.tryParse(_agregarStockController.text) ?? 0;
    final nuevoStock = stockActualBase + stockAdicional;

    final producto = Producto(
      id: _producto?.id ?? '',
      nombre: _nombreController.text.trim(),
      categoriaId: _categoriaId,
      precioPublico: CurrencyFormatter.parseCop(_precioPublicoController.text),
      precioMayorista: CurrencyFormatter.parseCop(
        _precioMayoristaController.text,
      ),
      costo: CurrencyFormatter.parseCop(_costoController.text),
      stockActual: nuevoStock,
      stockMinimo: int.tryParse(_stockMinimoController.text) ?? 5,
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

  Future<void> _delete() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar producto'),
        content: const Text('¿Estás seguro de eliminar este producto?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    setState(() => _saving = true);

    try {
      final repo = ref.read(inventarioRepositoryProvider);
      await repo.deleteProducto(_producto!.id);
      
      ref.invalidate(inventarioProductosProvider);
      ref.invalidate(stockBajoProvider);

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Producto eliminado exitosamente')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo eliminar el producto. Si tiene ventas registradas, no podrá ser borrado. En su lugar, desactívalo.\n\nError: $error',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _stripDecimals(TextEditingController controller) {
    final text = controller.text;
    if (text.contains(',')) {
      controller.text = text.split(',')[0];
    }
  }

  @override
  Widget build(BuildContext context) {
    final categorias = ref.watch(inventarioCategoriasProvider);
    final categoriasList = categorias.value ?? [];
    final selectedCategory = categoriasList.firstWhere(
      (c) => c.id == _categoriaId,
      orElse: () => const Categoria(id: '', nombre: ''),
    );
    final isCerveza = selectedCategory.nombre.toLowerCase().trim() == 'cerveza';

    return Scaffold(
      appBar: AppBar(
        title: Text(_producto == null ? 'Nuevo producto' : 'Editar producto'),
        actions: [
          if (_producto != null)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              tooltip: 'Eliminar producto',
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SafeArea(
          bottom: true,
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
                  onChanged: (value) {
                    setState(() {
                      _categoriaId = value;
                      final selected = items.firstWhere(
                        (c) => c.id == value,
                        orElse: () => const Categoria(id: '', nombre: ''),
                      );
                      final isNewCerveza = selected.nombre.toLowerCase().trim() == 'cerveza';
                      if (!isNewCerveza) {
                        _stripDecimals(_precioPublicoController);
                        _stripDecimals(_precioMayoristaController);
                        _stripDecimals(_costoController);
                      }
                    });
                  },
                ),
              ),
              const SizedBox(height: 12),
              _MoneyField(
                controller: _precioPublicoController,
                label: 'Precio publico',
                allowDecimals: isCerveza,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Ingresa el precio público';
                  }
                  if (!isCerveza && value.contains(',')) {
                    return 'No se permiten decimales para esta categoría';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              _MoneyField(
                controller: _precioMayoristaController,
                label: 'Precio mayorista',
                allowDecimals: isCerveza,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Ingresa el precio mayorista';
                  }
                  if (!isCerveza && value.contains(',')) {
                    return 'No se permiten decimales para esta categoría';
                  }
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
              _MoneyField(
                controller: _costoController,
                label: 'Costo',
                allowDecimals: isCerveza,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Ingresa el costo';
                  }
                  if (!isCerveza && value.contains(',')) {
                    return 'No se permiten decimales para esta categoría';
                  }
                  return null;
                },
              ),
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
              if (_producto != null) ...[
                const SizedBox(height: 12),
                _IntegerField(
                  controller: _agregarStockController,
                  label: 'Agregar stock (+)',
                  validator: (value) {
                    if (value != null && value.isNotEmpty) {
                      final val = int.tryParse(value) ?? 0;
                      if (val < 0) return 'Debe ser >= 0';
                    }
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 12),
              _IntegerField(
                controller: _stockMinimoController,
                label: 'Stock mínimo (alerta)',
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
      ),
    );
  }
}

class _MoneyField extends StatelessWidget {
  const _MoneyField({
    required this.controller,
    required this.label,
    this.validator,
    this.allowDecimals = false,
  });

  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String>? validator;
  final bool allowDecimals;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixText: '\$ ',
      ),
      keyboardType: TextInputType.numberWithOptions(decimal: allowDecimals),
      inputFormatters: [CopInputFormatter(allowDecimals: allowDecimals)],
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
