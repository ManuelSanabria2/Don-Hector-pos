import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_colors.dart';
import '../gastos/gastos_providers.dart';
import 'contabilidad_providers.dart';

class AnalisisFinancieroScreen extends ConsumerStatefulWidget {
  const AnalisisFinancieroScreen({super.key});

  @override
  ConsumerState<AnalisisFinancieroScreen> createState() => _AnalisisFinancieroScreenState();
}

class _AnalisisFinancieroScreenState extends ConsumerState<AnalisisFinancieroScreen> {
  late DateTimeRange _dateRange;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateRange = DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month, now.day),
    );
  }

  Widget _buildPieLegend(String title, String value, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 12,
          height: 12,
          color: color,
          margin: const EdgeInsets.only(top: 4),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: AppColors.blancoD, fontSize: 12)),
              Text(value, style: const TextStyle(color: AppColors.blanco, fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCardContainer({required String title, required Widget child}) {
    return Card(
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
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.blanco,
              ),
            ),
            const SizedBox(height: 20),
            child,
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
    final currency = NumberFormat('#,##0.00');
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
            fontSize: isHighlight ? 14 : 12,
            fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          '${isNegative ? "-" : (isPositive ? "+" : "")} \$ ${currency.format(value)}',
          style: TextStyle(
            color: textColor,
            fontSize: isHighlight ? 15 : 13,
            fontWeight: isHighlight ? FontWeight.bold : FontWeight.bold,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final resumenHoy = ref.watch(resumenHoyProvider);
    final metricasMes = ref.watch(metricasMesProvider);
    final ventas7Dias = ref.watch(ventasUltimos7DiasProvider);
    final topProductos = ref.watch(topProductosMesProvider);
    final gastosAsync = ref.watch(gastosDelMesProvider);
    final categoriasAsync = ref.watch(categoriasGastoProvider);
    final valorInventario = ref.watch(valorInventarioProvider);
    final utilidadRango = ref.watch(utilidadRangoProvider(_dateRange));

    final isLoading = resumenHoy.isLoading ||
        metricasMes.isLoading ||
        ventas7Dias.isLoading ||
        topProductos.isLoading ||
        gastosAsync.isLoading ||
        categoriasAsync.isLoading ||
        valorInventario.isLoading ||
        utilidadRango.isLoading;

    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final currency = NumberFormat('#,##0.00');

    final hoy = resumenHoy.value ?? {};
    final dias7 = ventas7Dias.value ?? [];
    final gastos = gastosAsync.value ?? [];
    final top = topProductos.value ?? [];
    final inventarioData = valorInventario.value ?? {};
    final rangeData = utilidadRango.value ?? {};

    final totalGastos = gastos.fold<num>(0, (sum, g) => sum + g.monto);

    // Calculate totals per category
    final Map<String, num> totalesPorCategoria = {};
    for (final g in gastos) {
      final catId = g.categoriaId ?? 'sin_categoria';
      totalesPorCategoria[catId] = (totalesPorCategoria[catId] ?? 0) + g.monto;
    }

    // Map category names
    final Map<String, String> nombresCategorias = {
      'sin_categoria': 'Sin Categoría'
    };
    if (categoriasAsync.hasValue) {
      for (final cat in categoriasAsync.value!) {
        nombresCategorias[cat.id] = cat.nombre;
      }
    }

    final categoriesList = totalesPorCategoria.entries.toList();
    categoriesList.sort((a, b) => b.value.compareTo(a.value));

    final hasTodaySales = hoy['total_ventas'] != null && (hoy['total_ventas'] as num) > 0;
    final hasExpenses = totalGastos > 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Análisis Financiero'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 0. RESUMEN DE HOY Y UTILIDAD DIARIA REAL
          Card(
            elevation: 0,
            color: AppColors.superficie,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.borde, width: 1.5),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Resumen del Día & Utilidad Diaria Real',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.blanco,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Ventas de Hoy',
                              style: TextStyle(color: AppColors.blancoD, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '\$ ${currency.format(hoy['total_ventas'] ?? 0)}',
                              style: const TextStyle(
                                color: AppColors.blanco,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${hoy['num_ventas'] ?? 0} transacciones',
                              style: const TextStyle(color: AppColors.blancoD, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        height: 50,
                        width: 1.5,
                        color: AppColors.borde,
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Utilidad Diaria Real',
                              style: TextStyle(color: AppColors.blancoD, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '\$ ${currency.format(hoy['utilidad_hoy'] ?? 0)}',
                              style: const TextStyle(
                                color: AppColors.verde,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Margen real: ${((hoy['utilidad_hoy'] ?? 0) / ((hoy['total_ventas'] ?? 1) > 0 ? (hoy['total_ventas'] ?? 1) : 1) * 100).toStringAsFixed(1)}%',
                              style: const TextStyle(color: AppColors.blancoD, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // VALOR TOTAL DEL INVENTARIO
          Card(
            elevation: 0,
            color: AppColors.superficie,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.borde, width: 1.5),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.inventory_2_outlined, color: AppColors.ambar),
                      const SizedBox(width: 8),
                      const Text(
                        'Valor de Inventario Actual',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.blanco,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Valor al Costo',
                              style: TextStyle(color: AppColors.blancoD, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '\$ ${currency.format(inventarioData['total_costo'] ?? 0)}',
                              style: const TextStyle(
                                color: AppColors.blanco,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        height: 40,
                        width: 1.5,
                        color: AppColors.borde,
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Valor de Venta (Público)',
                              style: TextStyle(color: AppColors.blancoD, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '\$ ${currency.format(inventarioData['total_venta'] ?? 0)}',
                              style: const TextStyle(
                                color: AppColors.blanco,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: AppColors.borde, height: 24, thickness: 1.5),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Utilidad Potencial Estimada',
                        style: TextStyle(color: AppColors.blancoD, fontSize: 13),
                      ),
                      Text(
                        '\$ ${currency.format(inventarioData['utilidad_potencial'] ?? 0)}',
                        style: const TextStyle(
                          color: AppColors.verde,
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
          const SizedBox(height: 16),

          // UTILIDAD POR RANGO DE FECHAS
          Card(
            elevation: 0,
            color: AppColors.superficie,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.borde, width: 1.5),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(Icons.date_range, color: AppColors.ambar),
                            const SizedBox(width: 8),
                            const Text(
                              'Filtro de Utilidad',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.blanco,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.calendar_month, size: 16),
                        label: Text(
                          '${DateFormat('dd/MM/yy').format(_dateRange.start)} - ${DateFormat('dd/MM/yy').format(_dateRange.end)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        onPressed: () async {
                          final picked = await showDateRangePicker(
                            context: context,
                            initialDateRange: _dateRange,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                            builder: (context, child) {
                              return Theme(
                                data: Theme.of(context).copyWith(
                                  colorScheme: ColorScheme.dark(
                                    primary: AppColors.ambar,
                                    onPrimary: Colors.black,
                                    surface: const Color(0xFA131310),
                                    onSurface: AppColors.blanco,
                                  ),
                                  dialogBackgroundColor: const Color(0xFA131310),
                                ),
                                child: child!,
                              );
                            },
                          );
                          if (picked != null) {
                            setState(() {
                              _dateRange = picked;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                  const Divider(color: AppColors.borde, height: 20, thickness: 1.5),
                  const SizedBox(height: 8),
                  _buildAnalysisRow('(+) Ingresos por Ventas', rangeData['ventas'] ?? 0, isPositive: true),
                  const SizedBox(height: 8),
                  _buildAnalysisRow('(-) Costo de Productos (COGS)', rangeData['cogs'] ?? 0, isNegative: true),
                  const SizedBox(height: 8),
                  _buildAnalysisRow('(-) Gastos en el Periodo', rangeData['gastos'] ?? 0, isNegative: true),
                  const Divider(color: AppColors.borde, height: 24, thickness: 1.5),
                  _buildAnalysisRow(
                    '(=) Utilidad Neta Real',
                    rangeData['utilidad'] ?? 0,
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
                        '${((rangeData['utilidad'] ?? 0) / ((rangeData['ventas'] ?? 1) > 0 ? (rangeData['ventas'] ?? 1) : 1) * 100).toStringAsFixed(1)}%',
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
          const SizedBox(height: 16),

          // 1. VENTAS ÚLTIMOS 7 DÍAS
          _buildCardContainer(
            title: 'Ventas últimos 7 días',
            child: SizedBox(
              height: 250,
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: dias7.isEmpty
                        ? 100
                        : dias7
                                .map((e) => (e['total_ventas'] as num?)?.toDouble() ?? 0.0)
                                .reduce((a, b) => a > b ? a : b) *
                            1.15,
                    barTouchData: BarTouchData(
                      enabled: true,
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipColor: (group) => AppColors.superficie2,
                        tooltipRoundedRadius: 0,
                        tooltipBorder: const BorderSide(color: AppColors.borde, width: 1.5),
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          if (group.x.toInt() < 0 || group.x.toInt() >= dias7.length) return null;
                          final row = dias7[dias7.length - 1 - group.x.toInt()];
                          final dateStr = row['dia'] as String?;
                          final date = dateStr != null ? DateTime.parse(dateStr) : DateTime.now();
                          final dateFormatted = DateFormat('dd/MM/yyyy').format(date);
                          return BarTooltipItem(
                            '$dateFormatted\n',
                            const TextStyle(color: AppColors.blancoD, fontSize: 11, fontWeight: FontWeight.normal),
                            children: [
                              TextSpan(
                                text: '\$ ${currency.format(rod.toY)}',
                                style: const TextStyle(color: AppColors.ambar, fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    titlesData: FlTitlesData(
                      show: true,
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            if (value.toInt() < 0 || value.toInt() >= dias7.length) {
                              return const SizedBox.shrink();
                            }
                            final row = dias7[dias7.length - 1 - value.toInt()];
                            final dateStr = row['dia'] as String?;
                            if (dateStr == null) return const SizedBox.shrink();
                            final date = DateTime.parse(dateStr);
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                DateFormat('E', 'es').format(date).toUpperCase(),
                                style: const TextStyle(color: AppColors.blancoD, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            );
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 55,
                          getTitlesWidget: (value, meta) {
                            if (value == 0) return const SizedBox.shrink();
                            return Text(
                              '\$${NumberFormat.compact().format(value)}',
                              style: const TextStyle(color: AppColors.blancoD, fontSize: 10),
                            );
                          },
                        ),
                      ),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: true,
                      getDrawingHorizontalLine: (value) => const FlLine(
                        color: AppColors.borde,
                        strokeWidth: 1,
                      ),
                      getDrawingVerticalLine: (value) => const FlLine(
                        color: AppColors.borde,
                        strokeWidth: 1,
                      ),
                    ),
                    borderData: FlBorderData(
                      show: true,
                      border: const Border(
                        bottom: BorderSide(color: AppColors.borde, width: 1.5),
                      ),
                    ),
                    barGroups: List.generate(dias7.length, (i) {
                      final row = dias7[dias7.length - 1 - i];
                      final total = (row['total_ventas'] as num?)?.toDouble() ?? 0.0;
                      return BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: total,
                            gradient: const LinearGradient(
                              colors: [AppColors.ambarOs, AppColors.ambar],
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                            ),
                            width: 18,
                            borderRadius: BorderRadius.zero,
                          ),
                        ],
                      );
                    }),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 2. GASTOS POR CATEGORÍA
          if (hasExpenses)
            _buildCardContainer(
              title: 'Distribución de Gastos (%)',
              child: SizedBox(
                height: 250,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: 100,
                      barTouchData: BarTouchData(
                        enabled: true,
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipColor: (group) => AppColors.superficie2,
                          tooltipRoundedRadius: 0,
                          tooltipBorder: const BorderSide(color: AppColors.borde, width: 1.5),
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            if (group.x.toInt() < 0 || group.x.toInt() >= categoriesList.length) return null;
                            final entry = categoriesList[group.x.toInt()];
                            final catName = nombresCategorias[entry.key] ?? 'Otros';
                            final pct = (entry.value / totalGastos) * 100;
                            return BarTooltipItem(
                              '$catName\n',
                              const TextStyle(color: AppColors.blancoD, fontSize: 11, fontWeight: FontWeight.normal),
                              children: [
                                TextSpan(
                                  text: '${pct.toStringAsFixed(1)}%\n',
                                  style: const TextStyle(color: AppColors.rojo, fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                                TextSpan(
                                  text: '\$ ${currency.format(entry.value)}',
                                  style: const TextStyle(color: AppColors.blanco, fontSize: 11),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              final idx = value.toInt();
                              if (idx < 0 || idx >= categoriesList.length) return const SizedBox.shrink();
                              final catName = nombresCategorias[categoriesList[idx].key] ?? 'Otros';
                              final displayName = catName.length > 8 ? '${catName.substring(0, 7)}…' : catName;
                              return Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(
                                  displayName.toUpperCase(),
                                  style: const TextStyle(color: AppColors.blancoD, fontSize: 9, fontWeight: FontWeight.bold),
                                ),
                              );
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 45,
                            getTitlesWidget: (value, meta) {
                              if (value == 0 || value == 100 || value % 25 == 0) {
                                  return Text(
                                    '${value.toInt()}%',
                                    style: const TextStyle(color: AppColors.blancoD, fontSize: 10),
                                  );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: true,
                        getDrawingHorizontalLine: (value) => const FlLine(
                          color: AppColors.borde,
                          strokeWidth: 1,
                        ),
                        getDrawingVerticalLine: (value) => const FlLine(
                          color: AppColors.borde,
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(
                        show: true,
                        border: const Border(
                          bottom: BorderSide(color: AppColors.borde, width: 1.5),
                        ),
                      ),
                      barGroups: List.generate(categoriesList.length, (i) {
                        final entry = categoriesList[i];
                        final pct = (entry.value / totalGastos) * 100;
                        return BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: pct,
                              gradient: const LinearGradient(
                                colors: [AppColors.rojo, Colors.redAccent],
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                              ),
                              width: 20,
                              borderRadius: BorderRadius.zero,
                            ),
                          ],
                        );
                      }),
                    ),
                  ),
                ),
              ),
            )
          else
            _buildCardContainer(
              title: 'Distribución de Gastos (%)',
              child: const SizedBox(
                height: 100,
                child: Center(
                  child: Text('No hay gastos registrados en este mes.', style: TextStyle(color: AppColors.blancoD)),
                ),
              ),
            ),
          const SizedBox(height: 16),

          // 3. DISTRIBUCIÓN VENTAS DE HOY (PIE CHART)
          if (hasTodaySales)
            _buildCardContainer(
              title: 'Distribución de Ventas (Hoy)',
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                height: 180,
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: PieChart(
                        PieChartData(
                          sectionsSpace: 4,
                          centerSpaceRadius: 35,
                          sections: [
                            PieChartSectionData(
                              value: (hoy['ventas_publico'] as num?)?.toDouble() ?? 0.0,
                              title: '',
                              color: AppColors.ambar,
                              radius: 25,
                            ),
                            PieChartSectionData(
                              value: (hoy['ventas_mayorista'] as num?)?.toDouble() ?? 0.0,
                              title: '',
                              color: AppColors.verde,
                              radius: 25,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      flex: 4,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildPieLegend('Ventas Público', '\$ ${currency.format(hoy['ventas_publico'] ?? 0)}', AppColors.ambar),
                          const SizedBox(height: 16),
                          _buildPieLegend('Ventas Mayorista', '\$ ${currency.format(hoy['ventas_mayorista'] ?? 0)}', AppColors.verde),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            _buildCardContainer(
              title: 'Distribución de Ventas (Hoy)',
              child: const SizedBox(
                height: 100,
                child: Center(
                  child: Text('No hay ventas registradas en el día de hoy.', style: TextStyle(color: AppColors.blancoD)),
                ),
              ),
            ),
          const SizedBox(height: 16),

          // 4. TOP 5 PRODUCTOS MÁS VENDIDOS (BAR CHART)
          if (top.isNotEmpty)
            _buildCardContainer(
              title: 'Top 5 Productos del Mes (Unidades)',
              child: SizedBox(
                height: 250,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: top.isEmpty ? 10 : top.map((e) => (e['unidades_vendidas'] as num?)?.toDouble() ?? 0.0).reduce((a, b) => a > b ? a : b) * 1.15,
                      barTouchData: BarTouchData(
                        enabled: true,
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipColor: (group) => AppColors.superficie2,
                          tooltipRoundedRadius: 0,
                          tooltipBorder: const BorderSide(color: AppColors.borde, width: 1.5),
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            if (group.x.toInt() < 0 || group.x.toInt() >= top.length) return null;
                            final p = top[group.x.toInt()];
                            final nombre = p['nombre'] ?? '';
                            return BarTooltipItem(
                              '$nombre\n',
                              const TextStyle(color: AppColors.blancoD, fontSize: 11, fontWeight: FontWeight.normal),
                              children: [
                                TextSpan(
                                  text: '${rod.toY.toInt()} unidades\n',
                                  style: const TextStyle(color: AppColors.ambar, fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                                TextSpan(
                                  text: '\$ ${currency.format(p['ingresos_totales'] ?? 0)}',
                                  style: const TextStyle(color: AppColors.blanco, fontSize: 11),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              final idx = value.toInt();
                              if (idx < 0 || idx >= top.length) return const SizedBox.shrink();
                              final p = top[idx];
                              final nombre = p['nombre'] ?? '';
                              final displayName = nombre.length > 7 ? '${nombre.substring(0, 6)}…' : nombre;
                              return Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(
                                  displayName.toUpperCase(),
                                  style: const TextStyle(color: AppColors.blancoD, fontSize: 9, fontWeight: FontWeight.bold),
                                ),
                              );
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 45,
                            getTitlesWidget: (value, meta) {
                              if (value == 0) return const SizedBox.shrink();
                              return Text(
                                '${value.toInt()} uds',
                                style: const TextStyle(color: AppColors.blancoD, fontSize: 10),
                              );
                            },
                          ),
                        ),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: true,
                        getDrawingHorizontalLine: (value) => const FlLine(
                          color: AppColors.borde,
                          strokeWidth: 1,
                        ),
                        getDrawingVerticalLine: (value) => const FlLine(
                          color: AppColors.borde,
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(
                        show: true,
                        border: const Border(
                          bottom: BorderSide(color: AppColors.borde, width: 1.5),
                        ),
                      ),
                      barGroups: List.generate(top.length, (i) {
                        final p = top[i];
                        final unidades = (p['unidades_vendidas'] as num?)?.toDouble() ?? 0.0;
                        return BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: unidades,
                              gradient: const LinearGradient(
                                colors: [Colors.teal, Colors.tealAccent],
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                              ),
                              width: 20,
                              borderRadius: BorderRadius.zero,
                            ),
                          ],
                        );
                      }),
                    ),
                  ),
                ),
              ),
            )
          else
            _buildCardContainer(
              title: 'Top 5 Productos del Mes (Unidades)',
              child: const SizedBox(
                height: 100,
                child: Center(
                  child: Text('No hay productos registrados este mes.', style: TextStyle(color: AppColors.blancoD)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
