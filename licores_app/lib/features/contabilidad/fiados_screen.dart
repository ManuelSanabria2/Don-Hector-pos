import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/models/fiado_publico.dart';
import '../../data/models/venta_enums.dart';
import '../../data/repositories/fiados_repository.dart';
import 'contabilidad_providers.dart';
import 'fiados_providers.dart';

/// Panel de deudas informales de ventas al público ("fiados").
///
/// Las deudas se agrupan por el nombre del deudor, así que varias ventas
/// fiadas a la misma persona se ven y se cobran como una sola cuenta.
class FiadosScreen extends ConsumerStatefulWidget {
  const FiadosScreen({super.key});

  @override
  ConsumerState<FiadosScreen> createState() => _FiadosScreenState();
}

class _FiadosScreenState extends ConsumerState<FiadosScreen> {
  String _busqueda = '';

  @override
  Widget build(BuildContext context) {
    final cuentasAsync = ref.watch(estadoCuentaFiadosProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Fiados')),
      body: cuentasAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No se pudieron cargar los fiados:\n$error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ),
        data: (cuentas) {
          final filtro = _busqueda.trim().toLowerCase();
          final visibles = filtro.isEmpty
              ? cuentas
              : cuentas
                  .where((c) => c.deudorNombre.toLowerCase().contains(filtro))
                  .toList();

          final conDeuda = visibles.where((c) => c.tieneDeuda).toList()
            ..sort((a, b) => b.deudaPendiente.compareTo(a.deudaPendiente));
          final sinDeuda = visibles.where((c) => !c.tieneDeuda).toList()
            ..sort((a, b) => a.deudorNombre
                .toLowerCase()
                .compareTo(b.deudorNombre.toLowerCase()));

          final totalDeuda =
              cuentas.fold<num>(0, (sum, c) => sum + c.deudaPendiente);

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(estadoCuentaFiadosProvider),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _TotalFiadoCard(total: totalDeuda, deudores: conDeuda.length),
                const SizedBox(height: 16),
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Buscar por nombre',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() => _busqueda = value),
                ),
                const SizedBox(height: 16),
                if (cuentas.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        'Todavía no hay ventas fiadas.\n'
                        'Para fiar, en el POS elige "Crédito (fiado)" '
                        'y escribe el nombre de la persona.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else if (visibles.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: Text('Nadie coincide con la búsqueda')),
                  ),
                for (final cuenta in conDeuda)
                  _DeudorCard(cuenta: cuenta),
                if (sinDeuda.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'Ya pagaron',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.blancoD),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final cuenta in sinDeuda) _DeudorCard(cuenta: cuenta),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TotalFiadoCard extends StatelessWidget {
  const _TotalFiadoCard({required this.total, required this.deudores});

  final num total;
  final int deudores;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Total fiado por cobrar',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: AppColors.blancoD),
            ),
            const SizedBox(height: 8),
            Text(
              CurrencyFormatter.cop(total),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: total > 0 ? Colors.redAccent : AppColors.verde,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              deudores == 1
                  ? '1 persona debe'
                  : '$deudores personas deben',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.blancoD),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeudorCard extends StatelessWidget {
  const _DeudorCard({required this.cuenta});

  final CuentaFiado cuenta;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final debe = cuenta.tieneDeuda;

    final cardColor = debe ? colors.primary : null;
    final textColor = debe ? Colors.black : null;
    final subColor = debe ? Colors.black87 : null;

    final inicial = cuenta.deudorNombre.trim().isEmpty
        ? '?'
        : cuenta.deudorNombre.trim()[0].toUpperCase();

    return Card(
      color: cardColor,
      child: ListTile(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => _DetalleDeudorSheet(cuenta: cuenta),
        ),
        leading: CircleAvatar(
          backgroundColor: debe ? Colors.black : colors.primary,
          foregroundColor: debe ? colors.primary : colors.onPrimary,
          child: Text(inicial),
        ),
        title: Text(
          cuenta.deudorNombre,
          style: TextStyle(
            color: textColor,
            fontWeight: debe ? FontWeight.bold : null,
          ),
        ),
        subtitle: Text(
          debe
              ? 'Debe ${CurrencyFormatter.cop(cuenta.deudaPendiente)} · '
                  '${cuenta.numVentas} ${cuenta.numVentas == 1 ? "venta" : "ventas"}'
              : 'Sin deuda pendiente',
          style: TextStyle(color: subColor),
        ),
        trailing: Icon(Icons.chevron_right, color: textColor),
      ),
    );
  }
}

/// Ventas fiadas de una persona y botón para abonar.
class _DetalleDeudorSheet extends ConsumerWidget {
  const _DetalleDeudorSheet({required this.cuenta});

  final CuentaFiado cuenta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fiadosAsync = ref.watch(fiadosDeDeudorProvider(cuenta.deudorNombre));
    final systemBottom = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, systemBottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            cuenta.deudorNombre,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Saldo pendiente: ${CurrencyFormatter.cop(cuenta.deudaPendiente)}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: cuenta.tieneDeuda ? Colors.redAccent : AppColors.verde,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: fiadosAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No se pudieron cargar las ventas: $error',
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
              data: (fiados) => ListView.separated(
                shrinkWrap: true,
                itemCount: fiados.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, i) => _FiadoTile(fiado: fiados[i]),
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: cuenta.tieneDeuda
                ? () async {
                    Navigator.of(context).pop();
                    await showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => _RegistrarAbonoSheet(cuenta: cuenta),
                    );
                  }
                : null,
            icon: const Icon(Icons.payments),
            label: const Text('Registrar abono'),
          ),
        ],
      ),
    );
  }
}

class _FiadoTile extends StatelessWidget {
  const _FiadoTile({required this.fiado});

  final FiadoPublico fiado;

  @override
  Widget build(BuildContext context) {
    final fecha = fiado.createdAt;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        fecha != null
            ? DateFormat('dd/MM/yyyy HH:mm').format(fecha.toLocal())
            : 'Sin fecha',
      ),
      subtitle: Text(
        'Total ${CurrencyFormatter.cop(fiado.totalVenta)} · '
        'Abonado ${CurrencyFormatter.cop(fiado.totalPagado)}',
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _EstadoFiadoBadge(estado: fiado.estado),
          const SizedBox(height: 4),
          Text(
            CurrencyFormatter.cop(fiado.saldo),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _EstadoFiadoBadge extends StatelessWidget {
  const _EstadoFiadoBadge({required this.estado});

  final EstadoCobro estado;

  @override
  Widget build(BuildContext context) {
    final (color, texto) = switch (estado) {
      EstadoCobro.pendiente => (Colors.red, 'Pendiente'),
      EstadoCobro.parcial => (AppColors.ambar, 'Parcial'),
      EstadoCobro.pagado => (AppColors.verde, 'Pagado'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        texto,
        style: TextStyle(
          color: estado == EstadoCobro.parcial ? Colors.black : Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _RegistrarAbonoSheet extends ConsumerStatefulWidget {
  const _RegistrarAbonoSheet({required this.cuenta});

  final CuentaFiado cuenta;

  @override
  ConsumerState<_RegistrarAbonoSheet> createState() =>
      _RegistrarAbonoSheetState();
}

class _RegistrarAbonoSheetState extends ConsumerState<_RegistrarAbonoSheet> {
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
      await ref.read(fiadosRepositoryProvider).registrarAbono(
            deudorNombre: widget.cuenta.deudorNombre,
            monto: monto,
            metodoPago: _metodoPago,
          );

      ref.invalidate(estadoCuentaFiadosProvider);
      ref.invalidate(totalFiadosPendienteProvider);
      ref.invalidate(fiadosDeDeudorProvider(widget.cuenta.deudorNombre));
      // El abono en efectivo entra a caja.
      ref.invalidate(metricasDiaProvider);
      ref.invalidate(metricasMesProvider);

      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo registrar el abono: $error')),
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
              'Abono de ${widget.cuenta.deudorNombre}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text('Debe: ${CurrencyFormatter.cop(widget.cuenta.deudaPendiente)}'),
            const SizedBox(height: 12),
            TextFormField(
              controller: _montoController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Monto',
                prefixText: '\$ ',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [CopInputFormatter(allowDecimals: true)],
              validator: (value) {
                final monto = CurrencyFormatter.parseCop(value ?? '');
                if (monto <= 0) return 'Ingresa un monto valido';
                if (monto > widget.cuenta.deudaPendiente) {
                  return 'No puede superar la deuda';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<MetodoPago>(
              initialValue: _metodoPago,
              decoration: const InputDecoration(labelText: 'Metodo de pago'),
              items: const [
                DropdownMenuItem(
                    value: MetodoPago.efectivo, child: Text('Efectivo')),
                DropdownMenuItem(value: MetodoPago.nequi, child: Text('Nequi')),
                DropdownMenuItem(
                    value: MetodoPago.transferencia, child: Text('Bancolombia')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _metodoPago = value);
              },
            ),
            const SizedBox(height: 8),
            Text(
              'Si debe varias ventas, el abono se aplica primero a la más '
              'antigua.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.blancoD),
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
              label: const Text('Registrar abono'),
            ),
          ],
        ),
      ),
    );
  }
}
