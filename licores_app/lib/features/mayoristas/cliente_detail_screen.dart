import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_routes.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../data/models/cliente_mayorista.dart';
import '../../data/models/cobro_mayorista.dart';
import '../../data/models/venta_enums.dart';
import '../../data/repositories/mayoristas_repository.dart';
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
          title: Text(cliente.nombre),
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

class _PedidosTab extends StatelessWidget {
  const _PedidosTab({required this.cobros});

  final List<CobroMayorista> cobros;

  @override
  Widget build(BuildContext context) {
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
            trailing: _EstadoCobroBadge(estado: cobro.estado),
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
        final categoria = producto?['categoria_id'] as String?;
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
                  'Categoria: ${categoria ?? 'Sin categoria'}',
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

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
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
              decoration: const InputDecoration(labelText: 'Monto'),
              keyboardType: TextInputType.number,
              inputFormatters: [CopInputFormatter()],
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
                DropdownMenuItem(
                  value: MetodoPago.efectivo,
                  child: Text('Efectivo'),
                ),
                DropdownMenuItem(value: MetodoPago.nequi, child: Text('Nequi')),
                DropdownMenuItem(
                  value: MetodoPago.daviplata,
                  child: Text('Daviplata'),
                ),
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
