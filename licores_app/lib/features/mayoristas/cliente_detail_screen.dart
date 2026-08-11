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
import '../../core/utils/date_formatter.dart';
import '../../data/models/cliente_mayorista.dart';
import '../../data/models/cobro_mayorista.dart';
import '../../data/models/venta_enums.dart';
import '../../data/repositories/mayoristas_repository.dart';
import '../pos/pos_receipt_pdf.dart';
import 'mayoristas_providers.dart';

class ClienteDetailScreen extends ConsumerWidget {
  const ClienteDetailScreen({required this.cliente, super.key});

  final ClienteMayorista cliente;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cobros = ref.watch(clienteCobrosProvider(cliente.id));
    final productosAsync = ref.watch(clienteVentasProductosProvider(cliente.id));

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          // Dos líneas y algo más pequeño: los nombres largos se cortaban.
          title: Text(
            cliente.nombre,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 17),
          ),
          actions: [
            IconButton(
              tooltip: 'Editar',
              onPressed: () {
                context.push(AppRoutes.clienteForm, extra: cliente);
              },
              icon: const Icon(Icons.edit),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: 'Pedidos'),
              Tab(text: 'Productos'),
              Tab(text: 'Cuenta'),
            ],
          ),
        ),
        body: cobros.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => Center(child: Text('Error: $error')),
          data: (items) => productosAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => Center(child: Text('Error productos: $error')),
            data: (productos) => TabBarView(
              children: [
                _PedidosTab(cobros: items),
                _ProductosTab(productos: productos),
                _CuentaTab(cliente: cliente, cobros: items),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PedidosTab extends ConsumerWidget {
  const _PedidosTab({required this.cobros});

  final List<CobroMayorista> cobros;

  Future<void> _compartirRecibo(BuildContext context, WidgetRef ref, String ventaId, String action) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final repo = ref.read(mayoristasRepositoryProvider);
      final receipt = await repo.getVentaConDetalles(ventaId);
      
      if (context.mounted) Navigator.of(context).pop(); // Dismiss loading

      if (action == 'pdf') {
        final pdfBytes = await PosReceiptPdf.build(receipt);
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/comprobante_${receipt.ventaId.substring(0, 8)}.pdf');
        await file.writeAsBytes(pdfBytes);
        await Share.shareXFiles(
          [XFile(file.path)],
          text: 'Comprobante de Venta por ${CurrencyFormatter.cop(receipt.total)}',
        );
      } else if (action == 'image') {
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
      } else if (action == 'print') {
        await Printing.layoutPdf(
          onLayout: (_) => PosReceiptPdf.build(receipt),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop(); // Dismiss loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al procesar el recibo: $e')),
        );
      }
    }
  }

  void _mostrarOpcionesRecibo(BuildContext context, WidgetRef ref, String ventaId) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFA131310),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.redAccent),
              title: const Text('Compartir PDF', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _compartirRecibo(context, ref, ventaId, 'pdf');
              },
            ),
            ListTile(
              leading: const Icon(Icons.image, color: Colors.blueAccent),
              title: const Text('Compartir Imagen', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _compartirRecibo(context, ref, ventaId, 'image');
              },
            ),
            ListTile(
              leading: const Icon(Icons.print, color: Colors.tealAccent),
              title: const Text('Imprimir', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _compartirRecibo(context, ref, ventaId, 'print');
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (cobros.isEmpty) {
      return const Center(child: Text('Sin pedidos mayoristas'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: cobros.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final cobro = cobros[index];
        return Card(
          child: ListTile(
            title: Text(
              cobro.createdAt == null
                  ? 'Pedido'
                  : DateFormatter.dateTime(cobro.createdAt!),
            ),
            subtitle: Text('Total ${CurrencyFormatter.cop(cobro.totalVenta)}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _EstadoCobroBadge(estado: cobro.estado),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Compartir recibo',
                  icon: const Icon(Icons.share, size: 20),
                  onPressed: () => _mostrarOpcionesRecibo(context, ref, cobro.ventaId),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProductosTab extends StatelessWidget {
  const _ProductosTab({required this.productos});

  final List<Map<String, dynamic>> productos;

  @override
  Widget build(BuildContext context) {
    if (productos.isEmpty) {
      return const Center(child: Text('Sin productos en ventas'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: productos.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = productos[index];
        final venta = item['ventas'] as Map<String, dynamic>?;
        final producto = item['productos'] as Map<String, dynamic>?;
        final fecha = venta?['fecha'] as String?;
        final nombreProducto = producto?['nombre'] as String? ?? 'Desconocido';
        final categoriaData = producto?['categorias'] as Map<String, dynamic>?;
        final categoriaNombre = categoriaData?['nombre'] as String? ?? 'Sin categoría';
        final cantidad = item['cantidad'] as int? ?? 0;
        final precioUnitario = item['precio_unitario'] as num? ?? 0;

        return Card(
          child: ListTile(
            title: Text(
              nombreProducto,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.blanco,
                  ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Categoría: $categoriaNombre',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.blancoD,
                      ),
                ),
                Text(
                  'Cantidad: $cantidad · Precio: ${CurrencyFormatter.cop(precioUnitario)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.blanco,
                      ),
                ),
                if (fecha != null)
                  Text(
                    'Fecha: ${DateFormatter.dateTime(DateTime.parse(fecha))}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.blancoD,
                        ),
                  ),
              ],
            ),
            trailing: Text(
              CurrencyFormatter.cop(cantidad * precioUnitario),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.verde,
                  ),
            ),
          ),
        );
      },
    );
  }
}

class _CuentaTab extends ConsumerWidget {
  const _CuentaTab({required this.cliente, required this.cobros});

  final ClienteMayorista cliente;
  final List<CobroMayorista> cobros;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saldo = cobros.fold<num>(0, (sum, cobro) => sum + cobro.saldo);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Saldo pendiente',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  CurrencyFormatter.cop(saldo),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: saldo <= 0
                      ? null
                      : () => _showPagoSheet(context, ref, cliente, saldo),
                  icon: const Icon(Icons.payments),
                  label: const Text('Registrar pago'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showPagoSheet(
    BuildContext context,
    WidgetRef ref,
    ClienteMayorista cliente,
    num saldo,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _RegistrarPagoSheet(cliente: cliente, saldo: saldo),
    );
  }
}

class _RegistrarPagoSheet extends ConsumerStatefulWidget {
  const _RegistrarPagoSheet({required this.cliente, required this.saldo});

  final ClienteMayorista cliente;
  final num saldo;

  @override
  ConsumerState<_RegistrarPagoSheet> createState() =>
      _RegistrarPagoSheetState();
}

class _RegistrarPagoSheetState extends ConsumerState<_RegistrarPagoSheet> {
  final _formKey = GlobalKey<FormState>();
  final _montoController = TextEditingController();
  MetodoPago _metodoPago = MetodoPago.efectivo;
  bool _saving = false;

  @override
  void dispose() {
    _montoController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final monto = CurrencyFormatter.parseCop(_montoController.text);

    try {
      await ref
          .read(mayoristasRepositoryProvider)
          .registrarPagoCliente(
            clienteId: widget.cliente.id,
            monto: monto,
            metodoPago: _metodoPago,
          );
      ref.invalidate(clienteCobrosProvider(widget.cliente.id));
      ref.invalidate(mayoristasClientesProvider);

      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo registrar el pago: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final systemBottom = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + systemBottom + 16),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Registrar pago',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text('Saldo: ${CurrencyFormatter.cop(widget.saldo)}'),
            const SizedBox(height: 12),
            TextFormField(
              controller: _montoController,
              decoration: const InputDecoration(
                labelText: 'Monto',
                prefixText: '\$ ',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [CopInputFormatter(allowDecimals: true)],
              validator: (value) {
                final monto = CurrencyFormatter.parseCop(value ?? '');
                if (monto <= 0) return 'Ingresa un monto valido';
                if (monto > widget.saldo) return 'No puede superar el saldo';
                return null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<MetodoPago>(
              initialValue: _metodoPago,
              decoration: const InputDecoration(labelText: 'Metodo de pago'),
              items: const [
                DropdownMenuItem(value: MetodoPago.efectivo, child: Text('Efectivo')),
                DropdownMenuItem(value: MetodoPago.nequi, child: Text('Nequi')),
                DropdownMenuItem(value: MetodoPago.transferencia, child: Text('Bancolombia')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _metodoPago = value);
              },
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: const Text('Registrar pago'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EstadoCobroBadge extends StatelessWidget {
  const _EstadoCobroBadge({required this.estado});

  final EstadoCobro estado;

  @override
  Widget build(BuildContext context) {
    final (label, color, foreground) = switch (estado) {
      EstadoCobro.pendiente => ('Pendiente', Colors.red.shade700, Colors.white),
      EstadoCobro.parcial => ('Parcial', Colors.amber.shade700, Colors.black),
      EstadoCobro.pagado => ('Pagado', Colors.green.shade700, Colors.white),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
