import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/carrito_item.dart';
import '../../../data/models/venta_enums.dart';
import '../../../data/repositories/pos_repository.dart';
import '../../contabilidad/contabilidad_providers.dart';
import '../../inventario/inventario_providers.dart';
import '../../mayoristas/mayoristas_providers.dart';
import '../pos_providers.dart';
import '../pos_receipt_pdf.dart';

class CartPanel extends ConsumerStatefulWidget {
  const CartPanel({super.key});

  @override
  ConsumerState<CartPanel> createState() => _CartPanelState();
}

class _CartPanelState extends ConsumerState<CartPanel> {
  bool _submitting = false;

  @override
  void dispose() {
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
      ref.invalidate(resumenHoyProvider);
      ref.invalidate(metricasMesProvider);
      ref.invalidate(ventasUltimos7DiasProvider);

      if (!mounted) return;
      await _showSuccessDialog(context, receipt);
    } catch (error) {
      debugPrint('Error registering sale: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pudo registrar la venta. Por favor, verifica el stock o la conexion.',
          ),
        ),
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
      debugPrint('Error sharing receipt PDF: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al generar o compartir el archivo PDF.')),
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
      debugPrint('Error sharing receipt Image: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al generar o compartir la imagen del comprobante.')),
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
            const ClienteSelector(),
            if (cart.clienteId != null) ...[
              const SizedBox(height: 12),
              SaldoPendienteInfo(clienteId: cart.clienteId!),
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
                return CartItemTile(item: cart.items[index]);
              },
            ),
          const SizedBox(height: 12),
          Builder(
            builder: (tileContext) {
              return ListTile(
                title: const Text('Metodo de pago'),
                subtitle: Text(
                  cart.metodoPago == MetodoPago.efectivo
                      ? 'Efectivo'
                      : cart.metodoPago == MetodoPago.nequi
                          ? 'Nequi'
                          : 'Bancolombia',
                  style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
                ),
                trailing: const Icon(Icons.arrow_drop_down),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: AppColors.borde),
                ),
                tileColor: AppColors.superficie2,
                onTap: () {
                  final RenderBox button = tileContext.findRenderObject() as RenderBox;
                  final RenderBox overlay = Navigator.of(tileContext).overlay!.context.findRenderObject() as RenderBox;
                  
                  final Offset buttonLocation = button.localToGlobal(Offset.zero, ancestor: overlay);
                  
                  final RelativeRect position = RelativeRect.fromLTRB(
                    buttonLocation.dx,
                    buttonLocation.dy + button.size.height,
                    buttonLocation.dx + button.size.width,
                    buttonLocation.dy + button.size.height + 200,
                  );
                  
                  showMenu<MetodoPago>(
                    context: tileContext,
                    position: position,
                    color: const Color(0xFA131310),
                    items: [
                      if (cart.metodoPago != MetodoPago.efectivo)
                        const PopupMenuItem(
                          value: MetodoPago.efectivo,
                          child: Text('Efectivo'),
                        ),
                      if (cart.metodoPago != MetodoPago.nequi)
                        const PopupMenuItem(
                          value: MetodoPago.nequi,
                          child: Text('Nequi'),
                        ),
                      if (cart.metodoPago != MetodoPago.transferencia)
                        const PopupMenuItem(
                          value: MetodoPago.transferencia,
                          child: Text('Bancolombia'),
                        ),
                    ],
                  ).then((value) {
                    if (value != null) {
                      ref.read(posCartProvider.notifier).setMetodoPago(value);
                    }
                  });
                },
              );
            },
          ),
          const SizedBox(height: 12),
          Totals(cart: cart),
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

class ClienteSelector extends ConsumerWidget {
  const ClienteSelector({super.key});

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
          error: (error, stackTrace) {
            debugPrint('Error loading clients selector: $error');
            return const Text('Error al cargar clientes');
          },
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

class CartItemTile extends ConsumerWidget {
  const CartItemTile({super.key, required this.item});

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
                  GreenRoundButton(
                    label: '+6',
                    onPressed: () => controller.increment(item.producto.id, cantidad: 6),
                  ),
                  const SizedBox(width: 8),
                  GreenRoundButton(
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

class Totals extends StatelessWidget {
  const Totals({super.key, required this.cart});

  final PosCartState cart;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TotalRow(label: 'Total', value: cart.total, bold: true),
      ],
    );
  }
}

class TotalRow extends StatelessWidget {
  const TotalRow({
    super.key,
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

class GreenRoundButton extends StatelessWidget {
  const GreenRoundButton({
    super.key,
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

class SaldoPendienteInfo extends ConsumerWidget {
  const SaldoPendienteInfo({super.key, required this.clienteId});

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
