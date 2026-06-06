import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/models/carrito_item.dart';
import '../../data/models/producto.dart';
import '../../data/models/venta_enums.dart';
import '../../data/models/pago_mayorista.dart';
import '../../data/repositories/inventario_repository.dart';
import '../../data/repositories/pos_repository.dart';
import '../../data/repositories/mayoristas_repository.dart';
import '../inventario/inventario_providers.dart';
import '../mayoristas/mayoristas_providers.dart';
import 'pos_providers.dart';
import 'pos_receipt_pdf.dart';

class PosScreen extends ConsumerWidget {
  const PosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    final cart = ref.watch(posCartProvider);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: isWide
            ? const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _ProductSearchPanel()),
                  SizedBox(width: 16),
                  SizedBox(width: 420, child: _CartPanel()),
                ],
              )
            : const _ProductSearchPanel(),
      ),
      bottomNavigationBar: isWide
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: () => _showCartSheet(context),
                  icon: const Icon(Icons.shopping_cart),
                  label: Text(
                    '${cart.totalItems} items · ${CurrencyFormatter.cop(cart.total)}',
                  ),
                ),
              ),
            ),
    );
  }

  void _showCartSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const FractionallySizedBox(
        heightFactor: 0.9,
        child: Padding(padding: EdgeInsets.all(16), child: _CartPanel()),
      ),
    );
  }
}

class _ProductSearchPanel extends ConsumerWidget {
  const _ProductSearchPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productos = ref.watch(posProductosProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'POS',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w400,
                color: AppColors.blanco,
              ),
        ),
        const SizedBox(height: 16),
        SearchBar(
          leading: const Icon(Icons.search),
          hintText: 'Buscar producto',
          onChanged: (value) {
            ref.read(posBusquedaProvider.notifier).state = value;
          },
          trailing: [
            IconButton(
              tooltip: 'Escanear codigo',
              onPressed: () => _scanBarcode(context, ref),
              icon: const Icon(Icons.qr_code_scanner),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: productos.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => Center(child: Text('Error: $error')),
            data: (items) {
              if (items.isEmpty) {
                return const Center(child: Text('No hay productos'));
              }

              return ListView.separated(
                itemCount: items.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  return _ProductTile(producto: items[index]);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _scanBarcode(BuildContext context, WidgetRef ref) async {
    final codigo = await context.push<String>(AppRoutes.barcodeScanner);
    if (codigo == null || codigo.isEmpty) return;

    try {
      final producto = await ref
          .read(inventarioRepositoryProvider)
          .getProductoPorBarcode(codigo);

      if (producto == null) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Producto no encontrado')));
        return;
      }

      ref.read(posCartProvider.notifier).addProduct(producto);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo escanear: $error')));
    }
  }
}

class _ProductTile extends ConsumerWidget {
  const _ProductTile({required this.producto});

  final Producto producto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final disabled = producto.stockActual <= 0;
    
    final categorias = ref.watch(inventarioCategoriasProvider).value ?? [];
    final isCerveza = producto.categoriaId != null &&
        categorias.any((c) => c.id == producto.categoriaId && c.nombre.toLowerCase() == 'cerveza');

    return Card(
      child: ListTile(
        enabled: !disabled,
        onTap: disabled
            ? null
            : () => ref.read(posCartProvider.notifier).addProduct(
                  producto,
                  cantidad: 0,
                ),
        title: Text(producto.nombre),
        subtitle: Text(
          '${CurrencyFormatter.cop(producto.precioPublico)} · Stock ${producto.stockActual}',
        ),
        trailing: Icon(disabled ? Icons.block : Icons.add_shopping_cart),
      ),
    );
  }
}

class _CartPanel extends ConsumerStatefulWidget {
  const _CartPanel();

  @override
  ConsumerState<_CartPanel> createState() => _CartPanelState();
}

class _CartPanelState extends ConsumerState<_CartPanel> {
  final _abonoController = TextEditingController();
  bool _debeTodo = true;
  bool _submitting = false;

  @override
  void dispose() {
    _abonoController.dispose();
    super.dispose();
  }

  Future<void> _registerSale() async {
    final cart = ref.read(posCartProvider);
    if (!cart.canSubmit) return;

    setState(() => _submitting = true);

    final receiptItems = List<CarritoItem>.from(cart.items);
    final receiptSubtotal = cart.subtotal;
    final receiptDescuento = cart.descuento;
    final receiptTotal = cart.total;
    final receiptMetodoPago = cart.metodoPago;

    try {
      final ventaId = await ref
          .read(posRepositoryProvider)
          .registrarVenta(
            tipo: cart.tipoVenta,
            clienteId: cart.clienteId,
            metodoPago: cart.metodoPago,
            descuento: cart.descuento,
            notas: null,
            items: cart.items,
          );

      if (cart.tipoVenta == TipoVenta.mayorista && !_debeTodo) {
        final abono = CurrencyFormatter.parseCop(_abonoController.text);
        if (abono > 0) {
          final mayoristasRepo = ref.read(mayoristasRepositoryProvider);
          final cobros = await mayoristasRepo.getCobrosCliente(cart.clienteId!);
          final cobroVenta = cobros.firstWhere((c) => c.ventaId == ventaId);
          
          await mayoristasRepo.registrarPago(PagoMayorista(
            id: '',
            cobroId: cobroVenta.id,
            monto: abono,
            metodoPago: cart.metodoPago,
            fecha: DateTime.now(),
            notas: 'Abono inicial en venta',
          ));
        }
      }

      final receipt = PosReceiptData(
        ventaId: ventaId,
        fecha: DateTime.now(),
        items: receiptItems,
        subtotal: receiptSubtotal,
        descuento: receiptDescuento,
        total: receiptTotal,
        metodoPago: receiptMetodoPago,
      );

      ref.read(posCartProvider.notifier).clear();
      ref.invalidate(posProductosProvider);
      ref.invalidate(inventarioProductosProvider);
      ref.invalidate(stockBajoProvider);
      ref.invalidate(mayoristasClientesProvider);
      _abonoController.clear();
      setState(() {
        _debeTodo = true;
      });

      if (!mounted) return;
      await _showSuccessDialog(context, receipt);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo registrar la venta: $error')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showSuccessDialog(
    BuildContext context,
    PosReceiptData receipt,
  ) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Column(
            children: [
              Icon(
                Icons.check_circle_outline_rounded,
                color: Colors.green,
                size: 64,
              ),
              SizedBox(height: 12),
              Text(
                '¡Venta Registrada!',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                CurrencyFormatter.cop(receipt.total),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.greenAccent,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                '¿Cómo deseas entregar el comprobante?',
                style: TextStyle(color: Colors.grey, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.redAccent),
                title: const Text('Compartir PDF'),
                subtitle: const Text('Envía el PDF por WhatsApp'),
                onTap: () => _shareReceiptPdf(receipt),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: Colors.grey.withOpacity(0.2)),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.image, color: Colors.blueAccent),
                title: const Text('Compartir Imagen'),
                subtitle: const Text('Envía como foto por WhatsApp'),
                onTap: () => _shareReceiptImage(receipt),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: Colors.grey.withOpacity(0.2)),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.print, color: Colors.tealAccent),
                title: const Text('Imprimir'),
                subtitle: const Text('Imprimir comprobante físico'),
                onTap: () async {
                  await Printing.layoutPdf(
                    onLayout: (_) => PosReceiptPdf.build(receipt),
                  );
                },
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: Colors.grey.withOpacity(0.2)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Finalizar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _shareReceiptPdf(PosReceiptData receipt) async {
    try {
      final pdfBytes = await PosReceiptPdf.build(receipt);
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/comprobante_${receipt.ventaId.substring(0, 8)}.pdf');
      await file.writeAsBytes(pdfBytes);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Comprobante de Venta por ${CurrencyFormatter.cop(receipt.total)}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al compartir PDF: $e')),
      );
    }
  }

  Future<void> _shareReceiptImage(PosReceiptData receipt) async {
    try {
      final pdfBytes = await PosReceiptPdf.build(receipt);
      final images = Printing.raster(pdfBytes, pages: [0], dpi: 200);
      await for (final image in images) {
        final pngBytes = await image.toPng();
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/comprobante_${receipt.ventaId.substring(0, 8)}.png');
        await file.writeAsBytes(pngBytes);
        await Share.shareXFiles(
          [XFile(file.path)],
          text: 'Comprobante de Venta por ${CurrencyFormatter.cop(receipt.total)}',
        );
        break;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al compartir Imagen: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(posCartProvider);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Carrito',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.blanco,
                ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<TipoVenta>(
            segments: const [
              ButtonSegment(value: TipoVenta.publico, label: Text('Publico')),
              ButtonSegment(value: TipoVenta.mayorista, label: Text('Mayorista')),
            ],
            selected: {cart.tipoVenta},
            onSelectionChanged: (values) {
              ref.read(posCartProvider.notifier).setTipoVenta(values.first);
            },
          ),
          if (cart.tipoVenta == TipoVenta.mayorista) ...[
            const SizedBox(height: 12),
            const _ClienteSelector(),
            if (cart.clienteId != null) ...[
              const SizedBox(height: 12),
              _SaldoPendienteInfo(clienteId: cart.clienteId!),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Debe todo'),
                value: _debeTodo,
                onChanged: (value) {
                  setState(() {
                    _debeTodo = value ?? true;
                    if (_debeTodo) {
                      _abonoController.clear();
                    }
                  });
                },
              ),
              if (!_debeTodo) ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _abonoController,
                  decoration: const InputDecoration(
                    labelText: 'Abono inicial',
                    prefixText: '\$ ',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [CopInputFormatter()],
                ),
              ],
            ],
          ],
          const SizedBox(height: 12),
          if (cart.items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('Agrega productos a la venta')),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cart.items.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: 8),
              itemBuilder: (context, index) {
                return _CartItemTile(item: cart.items[index]);
              },
            ),
          DropdownButtonFormField<MetodoPago>(
            initialValue: cart.metodoPago,
            decoration: const InputDecoration(labelText: 'Metodo de pago'),
            items: const [
              DropdownMenuItem(value: MetodoPago.efectivo, child: Text('Efectivo')),
              DropdownMenuItem(value: MetodoPago.nequi, child: Text('Nequi')),
              DropdownMenuItem(value: MetodoPago.transferencia, child: Text('Bancolombia')),
            ],
            onChanged: (value) {
              if (value == null) return;
              ref.read(posCartProvider.notifier).setMetodoPago(value);
            },
          ),
          const SizedBox(height: 12),
          _Totals(cart: cart),
          const SizedBox(height: 16),
          SafeArea(
            top: false,
            bottom: true,
            child: FilledButton.icon(
              onPressed: cart.canSubmit && !_submitting ? _registerSale : null,
              icon: _submitting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle),
              label: const Text('Registrar venta'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClienteSelector extends ConsumerWidget {
  const _ClienteSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clientes = ref.watch(posClientesProvider);
    final selectedId = ref.watch(posCartProvider).clienteId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SearchBar(
          leading: const Icon(Icons.search),
          hintText: 'Buscar cliente',
          onChanged: (value) {
            ref.read(posClienteBusquedaProvider.notifier).state = value;
          },
        ),
        const SizedBox(height: 8),
        clientes.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, stackTrace) => Text('Error clientes: $error'),
          data: (items) {
            if (items.isEmpty) {
              return const Text('No hay clientes');
            }

            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final item in items)
                    ListTile(
                      dense: true,
                      selected: item.cliente.id == selectedId,
                      title: Text(item.cliente.nombre),
                      subtitle: Text(
                        'Deuda: ${CurrencyFormatter.cop(item.deudaPendiente)}'
                        '${item.cliente.telefono != null ? " · ${item.cliente.telefono}" : ""}',
                      ),
                      trailing: item.cliente.id == selectedId
                          ? const Icon(Icons.check_circle)
                          : const Icon(Icons.circle_outlined),
                      onTap: () {
                        ref
                            .read(posCartProvider.notifier)
                            .setCliente(item.cliente.id);
                      },
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _CartItemTile extends ConsumerWidget {
  const _CartItemTile({required this.item});

  final CarritoItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(posCartProvider.notifier);

    final categorias = ref.watch(inventarioCategoriasProvider).value ?? [];
    final isCerveza = item.producto.categoriaId != null &&
        categorias.any((c) => c.id == item.producto.categoriaId && c.nombre.toLowerCase() == 'cerveza');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.producto.nombre,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Eliminar',
                  onPressed: () => controller.remove(item.producto.id),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            Row(
              children: [
                IconButton.filledTonal(
                  tooltip: 'Disminuir',
                  onPressed: () => controller.decrement(item.producto.id),
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    item.cantidad.toString(),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Aumentar',
                  onPressed: () => controller.increment(item.producto.id),
                  icon: const Icon(Icons.add),
                ),
                if (isCerveza) ...[
                  const SizedBox(width: 8),
                  _GreenRoundButton(
                    label: '+6',
                    onPressed: () => controller.increment(item.producto.id, cantidad: 6),
                  ),
                  const SizedBox(width: 8),
                  _GreenRoundButton(
                    label: '+24',
                    onPressed: () => controller.increment(item.producto.id, cantidad: 24),
                  ),
                ],
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(CurrencyFormatter.cop(item.precioUnitario)),
                    Text(
                      CurrencyFormatter.cop(item.subtotal),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.cart});

  final PosCartState cart;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TotalRow(label: 'Total', value: cart.total, bold: true),
      ],
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  final String label;
  final num value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = bold ? Theme.of(context).textTheme.titleMedium : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(CurrencyFormatter.cop(value), style: style),
        ],
      ),
    );
  }
}

class _GreenRoundButton extends StatelessWidget {
  const _GreenRoundButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 36,
      child: RawMaterialButton(
        onPressed: onPressed,
        elevation: 0,
        fillColor: AppColors.verde,
        shape: const CircleBorder(),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            fontFamily: 'DMMono',
          ),
        ),
      ),
    );
  }
}

class _SaldoPendienteInfo extends ConsumerWidget {
  const _SaldoPendienteInfo({required this.clienteId});

  final String clienteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(mayoristasClientesProvider).value ?? [];
    ClienteConCuenta? selected;
    for (final item in list) {
      if (item.cliente.id == clienteId) {
        selected = item;
        break;
      }
    }

    if (selected == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.superficie,
        border: Border.all(color: AppColors.borde),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Saldo pendiente',
            style: TextStyle(color: AppColors.blancoD),
          ),
          Text(
            CurrencyFormatter.cop(selected.deudaPendiente),
            style: TextStyle(
              color: selected.tieneCobroPendiente ? AppColors.ambar : AppColors.verde,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
