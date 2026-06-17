import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'contabilidad_providers.dart';
import 'analisis_financiero_screen.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/repositories/contabilidad_repository.dart';

class ContabilidadScreen extends ConsumerStatefulWidget {
  const ContabilidadScreen({super.key});

  @override
  ConsumerState<ContabilidadScreen> createState() => _ContabilidadScreenState();
}

class _ContabilidadScreenState extends ConsumerState<ContabilidadScreen> {
  final GlobalKey _chartKey = GlobalKey();
  DateTime _selectedDate = DateTime.now();

  Future<void> _exportarPdf(
    Map<String, dynamic> dia,
    List<Map<String, dynamic>> topProductos,
  ) async {
    Uint8List? chartImageBytes;
    try {
      final boundary = _chartKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        final image = await boundary.toImage(pixelRatio: 2.0);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        chartImageBytes = byteData?.buffer.asUint8List();
      }
    } catch (_) {}

    final pdf = pw.Document();
    
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Reporte de Contabilidad', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 20),
              pw.Text('Ventas del Día: ${CurrencyFormatter.cop(dia['ventas_dia'] ?? 0)} (${dia['num_ventas'] ?? 0} txs)', style: const pw.TextStyle(fontSize: 16)),
              pw.Text('Gastos del Día: ${CurrencyFormatter.cop(dia['gastos_dia'] ?? 0)}', style: const pw.TextStyle(fontSize: 16)),
              pw.Text('Utilidad del Día: ${CurrencyFormatter.cop(dia['utilidad_dia'] ?? 0)}', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.Text('Deuda de Mayoristas: ${CurrencyFormatter.cop(dia['deuda_pendiente'] ?? 0)}', style: const pw.TextStyle(fontSize: 16)),
              pw.Text('Efectivo Real (Mes): ${CurrencyFormatter.cop(dia['efectivo_real'] ?? 0)}', style: const pw.TextStyle(fontSize: 16)),
              pw.SizedBox(height: 20),
              pw.Text('Top 5 Productos del Mes:', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              ...topProductos.map((p) {
                return pw.Text('- ${p['nombre']}: ${p['unidades_vendidas']} unidades vendidas');
              }).toList(),
              pw.SizedBox(height: 20),
              pw.Text('Ventas últimos 7 días:', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              if (chartImageBytes != null)
                pw.Image(pw.MemoryImage(chartImageBytes), width: 400, height: 200),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  Future<void> _confirmarEliminarVenta(BuildContext context, String ventaId) async {
    final TextEditingController motivoController = TextEditingController();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Anular Venta'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('¿Estás seguro de anular esta venta? El stock de los productos asociados será restaurado.'),
            const SizedBox(height: 16),
            TextField(
              controller: motivoController,
              decoration: const InputDecoration(
                labelText: 'Motivo de la anulación (opcional)',
                hintText: 'Ej. Error de digitación, devolución',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Anular Venta'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      try {
        final motivo = motivoController.text.trim();
        await ref.read(contabilidadRepositoryProvider).eliminarVenta(
          ventaId,
          motivo: motivo.isNotEmpty ? motivo : null,
        );
        
        // Invalidate providers to refresh UI
        ref.invalidate(resumenHoyProvider);
        ref.invalidate(metricasMesProvider);
        ref.invalidate(ventasUltimos7DiasProvider);
        ref.invalidate(topProductosMesProvider);
        ref.invalidate(ventasPorDiaProvider);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Venta anulada exitosamente')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al anular la venta: $e')),
          );
        }
      } finally {
        motivoController.dispose();
      }
    }
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color, {String? subtitle}) {
    return Card(
      elevation: 0,
      color: AppColors.superficie,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.borde, width: 1.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 12.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              color: color.withOpacity(0.25),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: const TextStyle(color: AppColors.blancoD, fontSize: 11, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: const TextStyle(color: AppColors.blanco, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        subtitle,
                        style: const TextStyle(color: AppColors.blancoD, fontSize: 9.5, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildAnalysisRow(
    String label,
    num value, {
    bool isPositive = false,
    bool isNegative = false,
    bool isHighlight = false,
    Color? highlightColor,
  }) {
    final textColor = isHighlight
        ? (highlightColor ?? AppColors.verde)
        : (isPositive
            ? AppColors.verde
            : (isNegative ? AppColors.rojo : AppColors.blanco));

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isHighlight ? AppColors.blanco : AppColors.blancoD,
            fontSize: isHighlight ? 15 : 13,
            fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          '${isNegative ? "-" : (isPositive ? "+" : "")} ${CurrencyFormatter.cop(value)}',
          style: TextStyle(
            color: textColor,
            fontSize: isHighlight ? 16 : 14,
            fontWeight: isHighlight ? FontWeight.bold : FontWeight.bold,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final metricasDia = ref.watch(metricasDiaProvider(_selectedDate));
    final ventas7Dias = ref.watch(ventasUltimos7DiasProvider);
    final topProductos = ref.watch(topProductosMesProvider);
    final ventasHoy = ref.watch(ventasPorDiaProvider(_selectedDate));

    final isLoading = metricasDia.isLoading || ventas7Dias.isLoading || topProductos.isLoading || ventasHoy.isLoading;

    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final dia = metricasDia.value ?? {};
    final top = topProductos.value ?? [];
    final ventasHoyList = ventasHoy.value ?? [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 16,
          children: [
            Text(
              'Contabilidad',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w400,
                    color: AppColors.blanco,
                  ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                      builder: (context, child) {
                        return Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: ColorScheme.dark(
                              primary: AppColors.ambar,
                              onPrimary: Colors.black,
                              surface: const Color(0xFA131310), // 98% opacidad oscura
                              onSurface: AppColors.blanco,
                            ),
                            dialogBackgroundColor: const Color(0xFA131310), // Fondo de ventana oscuro
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (date != null) {
                      setState(() {
                        _selectedDate = date;
                      });
                    }
                  },
                  icon: const Icon(Icons.date_range),
                  label: Text(
                    _selectedDate.day == DateTime.now().day && _selectedDate.month == DateTime.now().month && _selectedDate.year == DateTime.now().year
                        ? 'Fecha: Hoy'
                        : 'Fecha: ${DateFormat('dd/MM/yyyy').format(_selectedDate)}',
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AnalisisFinancieroScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.analytics_outlined),
                  label: const Text('Análisis Financiero'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _exportarPdf(dia, top),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Exportar PDF'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900 ? 3 : (constraints.maxWidth >= 600 ? 2 : 1);
            double aspectRatio = 1.6;
            if (constraints.maxWidth >= 900) {
              aspectRatio = 2.2;
            } else if (constraints.maxWidth >= 600) {
              aspectRatio = 2.5;
            }

            return GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: columns,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: aspectRatio,
              children: [
                _buildMetricCard(
                  _selectedDate.day == DateTime.now().day && _selectedDate.month == DateTime.now().month && _selectedDate.year == DateTime.now().year
                      ? 'Ventas Hoy (${dia['num_ventas'] ?? 0} txs)'
                      : 'Ventas del Día (${dia['num_ventas'] ?? 0} txs)',
                  CurrencyFormatter.cop(dia['ventas_dia'] ?? 0),
                  Icons.today,
                  Colors.blue,
                ),
                _buildMetricCard(
                  'Gastos del Día',
                  CurrencyFormatter.cop(dia['gastos_dia'] ?? 0),
                  Icons.money_off,
                  Colors.red,
                ),
                _buildMetricCard(
                  'Utilidad del Día',
                  CurrencyFormatter.cop(dia['utilidad_dia'] ?? 0),
                  Icons.trending_up,
                  Colors.teal,
                ),
                _buildMetricCard(
                  'Deuda Mayoristas',
                  CurrencyFormatter.cop(dia['deuda_pendiente'] ?? 0),
                  Icons.warning_amber,
                  Colors.orange,
                ),
                _buildMetricCard(
                  'Efectivo Real',
                  CurrencyFormatter.cop(dia['efectivo_real'] ?? 0),
                  Icons.account_balance_wallet,
                  Colors.amber,
                  subtitle: 'Transf: ${CurrencyFormatter.cop(dia['transferencias_mes'] ?? 0)}',
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          color: AppColors.superficie,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.borde, width: 1.5),
            ),
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.analytics_outlined, color: AppColors.ambar),
                    const SizedBox(width: 8),
                    Text(
                      'Análisis de Utilidad del Día',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.blanco,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildAnalysisRow('(+) Ingresos por Ventas', dia['ventas_dia'] ?? 0, isPositive: true),
                const SizedBox(height: 8),
                _buildAnalysisRow('(-) Costo de Productos (COGS)', dia['cogs_dia'] ?? 0, isNegative: true),
                const SizedBox(height: 8),
                _buildAnalysisRow('(-) Gastos Operativos', dia['gastos_dia'] ?? 0, isNegative: true),
                const Divider(color: AppColors.borde, height: 24, thickness: 1.5),
                _buildAnalysisRow(
                  '(=) Utilidad Neta Real',
                  dia['utilidad_dia'] ?? 0,
                  isHighlight: true,
                  highlightColor: AppColors.verde,
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Margen Neto Real',
                      style: TextStyle(color: AppColors.blancoD, fontSize: 13),
                    ),
                    Text(
                      '${((dia['utilidad_dia'] ?? 0) / ((dia['ventas_dia'] ?? 1) > 0 ? (dia['ventas_dia'] ?? 1) : 1) * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                        color: AppColors.blanco,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('Top 5 Productos del mes', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Card(
          elevation: 2,
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: top.length,
            separatorBuilder: (c, i) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final p = top[i];
              return ListTile(
                leading: CircleAvatar(child: Text('${i + 1}')),
                title: Text(p['nombre'] ?? ''),
                subtitle: Text('${p['categoria'] ?? ''}'),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${p['unidades_vendidas']} uds.', style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(CurrencyFormatter.cop(p['ingresos_totales'] ?? 0), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                _selectedDate.day == DateTime.now().day && _selectedDate.month == DateTime.now().month && _selectedDate.year == DateTime.now().year 
                  ? 'Facturas del día' 
                  : 'Facturas del ${DateFormat('dd/MM/yyyy').format(_selectedDate)}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.calendar_month),
              label: const Text('Elegir fecha'),
              onPressed: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                  builder: (context, child) {
                    return Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: ColorScheme.dark(
                          primary: AppColors.ambar,
                          onPrimary: Colors.black,
                          surface: const Color(0xFA131310), // 98% opacidad oscura
                          onSurface: AppColors.blanco,
                        ),
                        dialogBackgroundColor: const Color(0xFA131310), // Fondo de ventana oscuro
                      ),
                      child: child!,
                    );
                  },
                );
                if (date != null) {
                  setState(() {
                    _selectedDate = date;
                  });
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (ventasHoyList.isEmpty)
          Center(child: Text('No hay facturas registradas el ${DateFormat('dd/MM/yyyy').format(_selectedDate)}'))
        else
          Card(
            elevation: 2,
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: ventasHoyList.length,
              separatorBuilder: (c, i) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final venta = ventasHoyList[i];
                final fecha = venta['fecha'] as String?;
                final total = venta['total'] as num? ?? 0;
                final metodoPago = venta['metodo_pago'] as String? ?? '';
                final tipo = venta['tipo'] as String? ?? '';
                final clienteMap = venta['clientes_mayoristas'] as Map?;
                final clienteNombre = clienteMap?['nombre'] as String? ?? 'Público General';
                final notas = venta['notas'] as String?;

                return ListTile(
                  title: Row(
                    children: [
                      Text(
                        clienteNombre,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: AppColors.blanco,
                            ),
                      ),
                      const Spacer(),
                      Text(
                        DateFormat('HH:mm').format(fecha != null ? DateTime.parse(fecha) : DateTime.now()),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.blancoD,
                            ),
                      ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tipo: ${tipo == 'mayorista' ? 'Mayorista' : 'Público'} · Pago: $metodoPago',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.blanco,
                            ),
                      ),
                      if (notas != null && notas.isNotEmpty)
                        Text(
                          'Notas: $notas',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppColors.blancoD,
                              ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        CurrencyFormatter.cop(total),
                        style: const TextStyle(
                          color: Colors.blueAccent,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _confirmarEliminarVenta(context, venta['id'].toString()),
                  ),
                  isThreeLine: true,
                );
              },
            ),
          ),
      ],
    );
  }
}
