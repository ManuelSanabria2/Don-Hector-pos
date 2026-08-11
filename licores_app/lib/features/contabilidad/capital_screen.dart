import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/models/capital_negocio.dart';
import '../../data/repositories/capital_repository.dart';
import '../compras/compras_providers.dart';

class CapitalScreen extends ConsumerStatefulWidget {
  const CapitalScreen({super.key});

  @override
  ConsumerState<CapitalScreen> createState() => _CapitalScreenState();
}

class _CapitalScreenState extends ConsumerState<CapitalScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _efectivoCtrl;
  late final TextEditingController _inventarioCtrl;
  late final TextEditingController _notasCtrl;

  bool _initialized = false;
  bool _saving = false;
  String? _capitalId;

  @override
  void initState() {
    super.initState();
    _efectivoCtrl = TextEditingController();
    _inventarioCtrl = TextEditingController();
    _notasCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _efectivoCtrl.dispose();
    _inventarioCtrl.dispose();
    _notasCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final repo = ref.read(capitalRepositoryProvider);

      final capital = CapitalNegocio(
        id: _capitalId ?? '',
        efectivoInicial: CurrencyFormatter.parseCop(_efectivoCtrl.text),
        valorInventarioInicial: CurrencyFormatter.parseCop(_inventarioCtrl.text),
        notas: _notasCtrl.text.trim().isEmpty ? null : _notasCtrl.text.trim(),
        fechaRegistro: DateTime.now(),
        // Recalibración de caja: el efectivo real acumula flujos desde
        // este instante sobre la base del efectivo contado.
        fechaCorte: DateTime.now(),
      );

      await repo.upsertCapital(capital);

      ref.invalidate(capitalNegocioProvider);
      ref.invalidate(resumenPatrimonioProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Capital guardado exitosamente')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar capital: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final capitalAsync = ref.watch(capitalNegocioProvider);
    final resumenAsync = ref.watch(resumenPatrimonioProvider);
    final colors = Theme.of(context).colorScheme;

    capitalAsync.whenData((capital) {
      if (!_initialized) {
        _capitalId = capital?.id;
        _efectivoCtrl.text = capital == null
            ? '0'
            : CurrencyFormatter.copNumberOnly(capital.efectivoInicial);
        _inventarioCtrl.text = capital == null
            ? '0'
            : CurrencyFormatter.copNumberOnly(capital.valorInventarioInicial);
        _notasCtrl.text = capital?.notas ?? '';
        _initialized = true;
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Capital y Patrimonio'),
      ),
      body: capitalAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error al cargar capital: $err')),
        data: (_) => Form(
          key: _formKey,
          child: SafeArea(
            bottom: true,
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
                          'Capital Inicial de Arranque',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colors.primary,
                              ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'El efectivo inicial es el dinero contado en caja en este '
                          'momento. Al guardar, el "Efectivo Real" de Contabilidad se '
                          'recalcula desde hoy con este valor como base. Guarda aquí '
                          'cada vez que hagas un conteo físico para recalibrar la caja.',
                          style: TextStyle(color: AppColors.blancoD, fontSize: 12),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _efectivoCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Efectivo inicial (COP)',
                            prefixText: '\$ ',
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [CopInputFormatter(allowDecimals: false)],
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Requerido';
                            final val = CurrencyFormatter.parseCop(v);
                            if (val < 0) return 'Debe ser >= 0';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _inventarioCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Valor del inventario inicial (COP)',
                            prefixText: '\$ ',
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [CopInputFormatter(allowDecimals: false)],
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Requerido';
                            final val = CurrencyFormatter.parseCop(v);
                            if (val < 0) return 'Debe ser >= 0';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _notasCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Notas / Observaciones',
                          ),
                          maxLines: 2,
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
                                : const Icon(Icons.save),
                            label: const Text('Guardar capital inicial'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Resumen Patrimonial',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                resumenAsync.when(
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  error: (err, _) => Text('Error al calcular resumen: $err', style: const TextStyle(color: Colors.redAccent)),
                  data: (resumen) {
                    final capIniEf = resumen['capital_efectivo_inicial'] ?? 0;
                    final capIniInv = resumen['capital_inventario_inicial'] ?? 0;
                    final capIniTot = capIniEf + capIniInv;

                    final ventasHist = resumen['total_ventas_historico'] ?? 0;
                    final comprasHist = resumen['total_compras_historico'] ?? 0;
                    final gastosHist = resumen['total_gastos_historico'] ?? 0;
                    final invAct = resumen['valor_inventario_actual'] ?? 0;
                    final patEst = resumen['patrimonio_estimado'] ?? 0;
                    final deudaPrestamos = resumen['deuda_prestamos'] ?? 0;
                    final dineroDisponible = resumen['dinero_disponible'] ?? 0;
                    final porCobrar = resumen['cuentas_por_cobrar'] ?? 0;
                    final deudaProveedores = resumen['deuda_proveedores'] ?? 0;

                    final isPositivo = patEst >= 0;

                    // Lo que el negocio TIENE menos lo que DEBE. Estas filas
                    // suman exactamente el patrimonio de abajo.
                    return Column(
                      children: [
                        _buildRowItem('Dinero disponible (+)', dineroDisponible, AppColors.verde),
                        const SizedBox(height: 8),
                        _buildRowItem('Valor del Inventario Actual (+)', invAct, AppColors.verde),
                        if (porCobrar > 0) ...[
                          const SizedBox(height: 8),
                          _buildRowItem('Le deben a usted (+)', porCobrar, AppColors.verde),
                        ],
                        if (deudaProveedores > 0) ...[
                          const SizedBox(height: 8),
                          _buildRowItem('Deuda con Proveedores (-)', deudaProveedores, Colors.redAccent),
                        ],
                        if (deudaPrestamos > 0) ...[
                          const SizedBox(height: 8),
                          _buildRowItem('Préstamos por Pagar (-)', deudaPrestamos, Colors.redAccent),
                        ],
                        const SizedBox(height: 16),
                        Card(
                          color: isPositivo
                              ? AppColors.verde.withOpacity(0.1)
                              : Colors.redAccent.withOpacity(0.1),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: isPositivo ? AppColors.verde : Colors.redAccent,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'PATRIMONIO ESTIMADO',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                                Text(
                                  formatCOP(patEst.toDouble()),
                                  style: TextStyle(
                                    color: isPositivo ? AppColors.verde : Colors.redAccent,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 20,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '* Lo que el negocio tiene hoy menos lo que debe. Es una '
                            'aproximación y no reemplaza una auditoría contable formal.',
                            style: TextStyle(color: Colors.white38, fontSize: 11, fontStyle: FontStyle.italic),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Actividad Histórica',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Acumulados desde el inicio. Son referencia de actividad, no '
                            'componentes del patrimonio de arriba.',
                            style: TextStyle(color: Colors.white38, fontSize: 11, fontStyle: FontStyle.italic),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildRowItem('Capital Inicial Registrado', capIniTot, Colors.white70),
                        const SizedBox(height: 8),
                        _buildRowItem('Ventas Históricas', ventasHist, Colors.white70),
                        const SizedBox(height: 8),
                        _buildRowItem('Compras de Inventario Históricas', comprasHist, Colors.white70),
                        const SizedBox(height: 8),
                        _buildRowItem('Gastos Operativos Históricos', gastosHist, Colors.white70),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRowItem(String label, num value, Color valColor) {
    return Card(
      color: AppColors.superficie,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF262626)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(color: AppColors.blancoD, fontSize: 13.5),
            ),
            Text(
              formatCOP(value.toDouble()),
              style: TextStyle(
                color: valColor,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
