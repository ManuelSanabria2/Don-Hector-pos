import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'contabilidad_providers.dart';
import '../../core/constants/app_colors.dart';
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
    Map<String, dynamic> hoy,
    Map<String, dynamic> mes,
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
    
    final currency = NumberFormat('#,##0.00');
    
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Reporte de Contabilidad', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 20),
              pw.Text('Ventas Hoy: \$ ${currency.format(hoy['total_ventas'] ?? 0)} (${hoy['num_ventas'] ?? 0} txs)', style: const pw.TextStyle(fontSize: 16)),
              pw.Text('Ventas del Mes: \$ ${currency.format(mes['ventas_mes'] ?? 0)}', style: const pw.TextStyle(fontSize: 16)),
              pw.Text('Gastos del Mes: \$ ${currency.format(mes['gastos_mes'] ?? 0)}', style: const pw.TextStyle(fontSize: 16)),
              pw.Text('Utilidad Estimada: \$ ${currency.format(mes['utilidad_estimada'] ?? 0)}', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.Text('Deuda de Mayoristas: \$ ${currency.format(mes['deuda_pendiente'] ?? 0)}', style: const pw.TextStyle(fontSize: 16)),
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Factura'),
        content: const Text('¿Estás seguro de eliminar esta venta? El registro se borrará permanentemente y el stock será restaurado.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      try {
        await ref.read(contabilidadRepositoryProvider).eliminarVenta(ventaId);
        
        // Invalidate providers to refresh UI
        ref.invalidate(resumenHoyProvider);
        ref.invalidate(metricasMesProvider);
        ref.invalidate(ventasUltimos7DiasProvider);
        ref.invalidate(topProductosMesProvider);
        ref.invalidate(ventasPorDiaProvider);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Venta eliminada exitosamente')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al eliminar: $e')),
          );
        }
      }
    }
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withOpacity(0.1),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.grey[700])),
                  Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resumenHoy = ref.watch(resumenHoyProvider);
    final metricasMes = ref.watch(metricasMesProvider);
    final ventas7Dias = ref.watch(ventasUltimos7DiasProvider);
    final topProductos = ref.watch(topProductosMesProvider);
    final ventasHoy = ref.watch(ventasPorDiaProvider(_selectedDate));

    final isLoading = resumenHoy.isLoading || metricasMes.isLoading || ventas7Dias.isLoading || topProductos.isLoading;

    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final currency = NumberFormat('#,##0.00');

    final hoy = resumenHoy.value ?? {};
    final mes = metricasMes.value ?? {};
    final dias7 = ventas7Dias.value ?? [];
    final top = topProductos.value ?? [];
    final ventasHoyList = ventasHoy.value ?? [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Contabilidad',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w400,
                    color: AppColors.blanco,
                  ),
            ),
            FilledButton.icon(
              onPressed: () => _exportarPdf(hoy, mes, top),
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Exportar PDF'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildMetricCard(
          'Ventas Hoy (${hoy['num_ventas'] ?? 0} txs)',
          '\$ ${currency.format(hoy['total_ventas'] ?? 0)}',
          Icons.today,
          Colors.blue,
        ),
        _buildMetricCard(
          'Ventas Este Mes',
          '\$ ${currency.format(mes['ventas_mes'] ?? 0)}',
          Icons.calendar_month,
          Colors.green,
        ),
        _buildMetricCard(
          'Gastos Este Mes',
          '\$ ${currency.format(mes['gastos_mes'] ?? 0)}',
          Icons.money_off,
          Colors.red,
        ),
        _buildMetricCard(
          'Utilidad Estimada',
          '\$ ${currency.format(mes['utilidad_estimada'] ?? 0)}',
          Icons.trending_up,
          Colors.teal,
        ),
        _buildMetricCard(
          'Deuda Mayoristas',
          '\$ ${currency.format(mes['deuda_pendiente'] ?? 0)}',
          Icons.warning_amber,
          Colors.orange,
        ),
        const SizedBox(height: 24),
        Text('Ventas últimos 7 días', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        SizedBox(
          height: 250,
          child: RepaintBoundary(
            key: _chartKey,
            child: Container(
              color: Theme.of(context).scaffoldBackgroundColor, // Background for the image export
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  barTouchData: BarTouchData(enabled: false),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() < 0 || value.toInt() >= dias7.length) {
                            return const SizedBox.shrink();
                          }
                          // Reverse because query is desc
                          final row = dias7[dias7.length - 1 - value.toInt()];
                          final dateStr = row['dia'] as String?;
                          if (dateStr == null) return const SizedBox.shrink();
                          final date = DateTime.parse(dateStr);
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(DateFormat('E', 'es').format(date)),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 50,
                        getTitlesWidget: (value, meta) {
                          if (value == 0) return const SizedBox.shrink();
                          return Text(NumberFormat.compact().format(value));
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: const FlGridData(show: true, drawVerticalLine: false),
                  borderData: FlBorderData(show: false),
                  barGroups: List.generate(dias7.length, (i) {
                    final row = dias7[dias7.length - 1 - i];
                    final total = (row['total_ventas'] as num?)?.toDouble() ?? 0.0;
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: total,
                          color: Colors.blue,
                          width: 16,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
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
                    Text('\$ ${currency.format(p['ingresos_totales'] ?? 0)}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _selectedDate.day == DateTime.now().day && _selectedDate.month == DateTime.now().month && _selectedDate.year == DateTime.now().year 
                ? 'Facturas del día' 
                : 'Facturas del ${DateFormat('dd/MM/yyyy').format(_selectedDate)}',
              style: Theme.of(context).textTheme.titleLarge,
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
                final subtotal = venta['subtotal'] as num? ?? 0;
                final descuento = venta['descuento'] as num? ?? 0;
                final total = venta['total'] as num? ?? 0;
                final metodoPago = venta['metodo_pago'] as String? ?? '';
                final tipo = venta['tipo'] as String? ?? '';
                final clienteId = venta['cliente_id'] as String?;
                final notas = venta['notas'] as String?;

                return ListTile(
                  title: Row(
                    children: [
                      Text(
                        'Venta ${venta['id'].toString().substring(0, 8)}',
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
                      if (clienteId != null)
                        Text(
                          'Cliente: $clienteId',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppColors.blancoD,
                              ),
                        ),
                      if (notas != null && notas.isNotEmpty)
                        Text(
                          'Notas: $notas',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppColors.blancoD,
                              ),
                        ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '\$ ${currency.format(total)}',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: AppColors.verde,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _confirmarEliminarVenta(context, venta['id'].toString()),
                      ),
                    ],
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
