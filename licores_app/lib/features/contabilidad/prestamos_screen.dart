import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/models/pago_prestamo.dart';
import '../../data/models/prestamo.dart';
import '../../data/models/venta_enums.dart';
import '../../data/repositories/prestamos_repository.dart';
import '../compras/compras_providers.dart';
import 'contabilidad_providers.dart';
import 'prestamos_providers.dart';

/// Panel de préstamos que el negocio recibió y debe devolver.
///
/// Un préstamo es un pasivo: recibirlo sube el efectivo pero no la
/// utilidad, y devolver el capital baja el efectivo pero tampoco la
/// utilidad. Solo el interés es un gasto real.
class PrestamosScreen extends ConsumerWidget {
  const PrestamosScreen({super.key});

  /// Refresca todo lo que un movimiento de préstamo puede mover.
  static void invalidarTodo(WidgetRef ref) {
    ref.invalidate(prestamosProvider);
    ref.invalidate(totalPrestamosPendienteProvider);
    ref.invalidate(metricasDiaProvider);
    ref.invalidate(metricasMesProvider);
    ref.invalidate(resumenPatrimonioProvider);
    // El interés se registra como gasto, así que los gastos cambian.
    ref.invalidate(resumenHoyProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prestamosAsync = ref.watch(prestamosProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Préstamos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => const _NuevoPrestamoSheet(),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo préstamo'),
      ),
      body: prestamosAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No se pudieron cargar los préstamos:\n$error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ),
        data: (prestamos) {
          final activos = prestamos.where((p) => !p.estaPagado).toList();
          final pagados = prestamos.where((p) => p.estaPagado).toList();

          final totalDeuda = prestamos.fold<num>(0, (s, p) => s + p.saldo);
          final totalInteres =
              prestamos.fold<num>(0, (s, p) => s + p.interesPagado);

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(prestamosProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                _ResumenCard(deuda: totalDeuda, interes: totalInteres),
                const SizedBox(height: 16),
                if (prestamos.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        'No hay préstamos registrados.\n'
                        'Use el botón de abajo para registrar uno.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                for (final p in activos) _PrestamoCard(prestamo: p),
                if (pagados.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'Ya pagados',
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
                  for (final p in pagados) _PrestamoCard(prestamo: p),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ResumenCard extends StatelessWidget {
  const _ResumenCard({required this.deuda, required this.interes});

  final num deuda;
  final num interes;

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
              'Total que debe',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: AppColors.blancoD),
            ),
            const SizedBox(height: 8),
            Text(
              CurrencyFormatter.cop(deuda),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: deuda > 0 ? Colors.redAccent : AppColors.verde,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              'Intereses pagados: ${CurrencyFormatter.cop(interes)}',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.ambar),
            ),
            const SizedBox(height: 4),
            Text(
              'Lo que ha costado el crédito. Ya está contado como gasto.',
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

class _PrestamoCard extends StatelessWidget {
  const _PrestamoCard({required this.prestamo});

  final Prestamo prestamo;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final debe = !prestamo.estaPagado;

    return Card(
      color: debe ? colors.primary : null,
      child: ListTile(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => _DetallePrestamoSheet(prestamo: prestamo),
        ),
        leading: CircleAvatar(
          backgroundColor: debe ? Colors.black : colors.primary,
          foregroundColor: debe ? colors.primary : colors.onPrimary,
          child: Icon(
            prestamo.tipo == TipoPrestamo.banco
                ? Icons.account_balance
                : Icons.person_outline,
            size: 20,
          ),
        ),
        title: Text(
          prestamo.acreedor,
          style: TextStyle(
            color: debe ? Colors.black : null,
            fontWeight: debe ? FontWeight.bold : null,
          ),
        ),
        subtitle: Text(
          debe
              ? 'Debe ${CurrencyFormatter.cop(prestamo.saldo)} '
                  'de ${CurrencyFormatter.cop(prestamo.monto)}'
              : 'Pagado · ${CurrencyFormatter.cop(prestamo.monto)}',
          style: TextStyle(color: debe ? Colors.black87 : null),
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: debe ? Colors.black : null,
        ),
      ),
    );
  }
}

class _DetallePrestamoSheet extends ConsumerWidget {
  const _DetallePrestamoSheet({required this.prestamo});

  final Prestamo prestamo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pagosAsync = ref.watch(pagosDePrestamoProvider(prestamo.id));
    final systemBottom = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, systemBottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(prestamo.acreedor,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            '${prestamo.tipo.label}'
            '${prestamo.tasaInteres != null ? ' · ${prestamo.tasaInteres}% de interés' : ''}',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.blancoD),
          ),
          const SizedBox(height: 12),
          _FilaResumen(
            etiqueta: 'Prestado',
            valor: CurrencyFormatter.cop(prestamo.monto),
          ),
          _FilaResumen(
            etiqueta: 'Ya abonado',
            valor: CurrencyFormatter.cop(prestamo.capitalPagado),
            color: AppColors.verde,
          ),
          _FilaResumen(
            etiqueta: 'Falta por pagar',
            valor: CurrencyFormatter.cop(prestamo.saldo),
            color: prestamo.saldo > 0 ? Colors.redAccent : AppColors.verde,
            destacado: true,
          ),
          _FilaResumen(
            etiqueta: 'Intereses pagados',
            valor: CurrencyFormatter.cop(prestamo.interesPagado),
            color: AppColors.ambar,
          ),
          const Divider(height: 24),
          Text('Cuotas pagadas',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Flexible(
            child: pagosAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('No se pudieron cargar las cuotas: $error',
                    style: const TextStyle(color: Colors.redAccent)),
              ),
              data: (pagos) => pagos.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('Todavía no se ha pagado ninguna cuota.'),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: pagos.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, i) => _PagoTile(pago: pagos[i]),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          // Se permite aunque el saldo sea cero: se puede pagar solo interés.
          FilledButton.icon(
            onPressed: () async {
              Navigator.of(context).pop();
              await showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => _RegistrarCuotaSheet(prestamo: prestamo),
              );
            },
            icon: const Icon(Icons.payments),
            label: const Text('Registrar cuota'),
          ),
        ],
      ),
    );
  }
}

class _FilaResumen extends StatelessWidget {
  const _FilaResumen({
    required this.etiqueta,
    required this.valor,
    this.color,
    this.destacado = false,
  });

  final String etiqueta;
  final String valor;
  final Color? color;
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(etiqueta,
              style: TextStyle(
                color: AppColors.blancoD,
                fontWeight: destacado ? FontWeight.bold : null,
              )),
          Text(
            valor,
            style: TextStyle(
              color: color,
              fontWeight: destacado ? FontWeight.bold : FontWeight.w500,
              fontSize: destacado ? 16 : 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _PagoTile extends StatelessWidget {
  const _PagoTile({required this.pago});

  final PagoPrestamo pago;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        pago.fecha != null
            ? DateFormat('dd/MM/yyyy HH:mm').format(pago.fecha!.toLocal())
            : 'Sin fecha',
      ),
      subtitle: Text(
        'Abono ${CurrencyFormatter.cop(pago.abonoCapital)} · '
        'Interés ${CurrencyFormatter.cop(pago.interes)}',
      ),
      trailing: Text(
        CurrencyFormatter.cop(pago.monto),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _NuevoPrestamoSheet extends ConsumerStatefulWidget {
  const _NuevoPrestamoSheet();

  @override
  ConsumerState<_NuevoPrestamoSheet> createState() =>
      _NuevoPrestamoSheetState();
}

class _NuevoPrestamoSheetState extends ConsumerState<_NuevoPrestamoSheet> {
  final _formKey = GlobalKey<FormState>();
  final _acreedorCtrl = TextEditingController();
  final _montoCtrl = TextEditingController();
  final _tasaCtrl = TextEditingController();
  final _notasCtrl = TextEditingController();
  TipoPrestamo _tipo = TipoPrestamo.prestamista;
  MetodoPago _metodoPago = MetodoPago.efectivo;
  bool _saving = false;

  @override
  void dispose() {
    _acreedorCtrl.dispose();
    _montoCtrl.dispose();
    _tasaCtrl.dispose();
    _notasCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      await ref.read(prestamosRepositoryProvider).registrarPrestamo(
            acreedor: _acreedorCtrl.text,
            tipo: _tipo,
            monto: CurrencyFormatter.parseCop(_montoCtrl.text),
            metodoPago: _metodoPago,
            tasaInteres: _tasaCtrl.text.trim().isEmpty
                ? null
                : num.tryParse(_tasaCtrl.text.trim().replaceAll(',', '.')),
            notas: _notasCtrl.text.trim().isEmpty ? null : _notasCtrl.text.trim(),
          );

      PrestamosScreen.invalidarTodo(ref);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo registrar el préstamo: $error')),
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Nuevo préstamo',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextFormField(
                controller: _acreedorCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: '¿Quién le prestó?',
                  hintText: 'Nombre del banco o de la persona',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<TipoPrestamo>(
                initialValue: _tipo,
                decoration: const InputDecoration(labelText: 'Tipo'),
                items: [
                  for (final t in TipoPrestamo.values)
                    DropdownMenuItem(value: t, child: Text(t.label)),
                ],
                onChanged: (v) => setState(() => _tipo = v ?? _tipo),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _montoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Monto prestado',
                  prefixText: '\$ ',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [CopInputFormatter(allowDecimals: true)],
                validator: (v) {
                  final monto = CurrencyFormatter.parseCop(v ?? '');
                  if (monto <= 0) return 'Ingresa un monto valido';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tasaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Interés (%) — opcional',
                  helperText: 'Solo informativo, para recordar lo pactado',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<MetodoPago>(
                initialValue: _metodoPago,
                decoration: const InputDecoration(
                  labelText: '¿Cómo recibió la plata?',
                  helperText: 'Solo el efectivo entra a la caja',
                ),
                items: const [
                  DropdownMenuItem(
                      value: MetodoPago.efectivo, child: Text('Efectivo')),
                  DropdownMenuItem(
                      value: MetodoPago.nequi, child: Text('Nequi')),
                  DropdownMenuItem(
                      value: MetodoPago.transferencia,
                      child: Text('Bancolombia')),
                ],
                onChanged: (v) => setState(() => _metodoPago = v ?? _metodoPago),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notasCtrl,
                decoration: const InputDecoration(labelText: 'Notas'),
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              Text(
                'El préstamo sube el efectivo disponible pero no cuenta como '
                'venta ni como ganancia.',
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
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check),
                label: const Text('Guardar préstamo'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RegistrarCuotaSheet extends ConsumerStatefulWidget {
  const _RegistrarCuotaSheet({required this.prestamo});

  final Prestamo prestamo;

  @override
  ConsumerState<_RegistrarCuotaSheet> createState() =>
      _RegistrarCuotaSheetState();
}

class _RegistrarCuotaSheetState extends ConsumerState<_RegistrarCuotaSheet> {
  final _formKey = GlobalKey<FormState>();
  final _abonoCtrl = TextEditingController();
  final _interesCtrl = TextEditingController();
  MetodoPago _metodoPago = MetodoPago.efectivo;
  bool _saving = false;

  num get _abono => CurrencyFormatter.parseCop(_abonoCtrl.text);
  num get _interes => CurrencyFormatter.parseCop(_interesCtrl.text);

  @override
  void dispose() {
    _abonoCtrl.dispose();
    _interesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_abono + _interes <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La cuota no puede ser de cero')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(prestamosRepositoryProvider).registrarPago(
            prestamoId: widget.prestamo.id,
            abonoCapital: _abono,
            interes: _interes,
            metodoPago: _metodoPago,
          );

      PrestamosScreen.invalidarTodo(ref);
      ref.invalidate(pagosDePrestamoProvider(widget.prestamo.id));

      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo registrar la cuota: $error')),
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Cuota de ${widget.prestamo.acreedor}',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('Falta por pagar: '
                  '${CurrencyFormatter.cop(widget.prestamo.saldo)}'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _abonoCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Abono a la deuda',
                  prefixText: '\$ ',
                  helperText: 'Baja lo que debe. No cuenta como gasto.',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [CopInputFormatter(allowDecimals: true)],
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  final monto = CurrencyFormatter.parseCop(v ?? '');
                  if (monto < 0) return 'No puede ser negativo';
                  if (monto > widget.prestamo.saldo) {
                    return 'No puede superar lo que falta por pagar';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _interesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Interés',
                  prefixText: '\$ ',
                  helperText: 'Se registra como gasto del negocio.',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [CopInputFormatter(allowDecimals: true)],
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  final monto = CurrencyFormatter.parseCop(v ?? '');
                  if (monto < 0) return 'No puede ser negativo';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.superficie2,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total de la cuota',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                      CurrencyFormatter.cop(_abono + _interes),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<MetodoPago>(
                initialValue: _metodoPago,
                decoration: const InputDecoration(
                  labelText: 'Método de pago',
                  helperText: 'Solo el efectivo descuenta de la caja',
                ),
                items: const [
                  DropdownMenuItem(
                      value: MetodoPago.efectivo, child: Text('Efectivo')),
                  DropdownMenuItem(
                      value: MetodoPago.nequi, child: Text('Nequi')),
                  DropdownMenuItem(
                      value: MetodoPago.transferencia,
                      child: Text('Bancolombia')),
                ],
                onChanged: (v) => setState(() => _metodoPago = v ?? _metodoPago),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check),
                label: const Text('Registrar cuota'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
