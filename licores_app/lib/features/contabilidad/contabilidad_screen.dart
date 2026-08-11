import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'contabilidad_providers.dart';
import 'analisis_financiero_screen.dart';
import 'capital_screen.dart';
import 'fiados_screen.dart';
import 'prestamos_screen.dart';
import 'utilidad_producto_tab.dart';
import '../mayoristas/mayoristas_providers.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/repositories/contabilidad_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ContabilidadScreen extends ConsumerStatefulWidget {
  const ContabilidadScreen({super.key});

  @override
  ConsumerState<ContabilidadScreen> createState() => _ContabilidadScreenState();
}

class _ContabilidadScreenState extends ConsumerState<ContabilidadScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime _selectedDate = DateTime.now();

  /// Rango de la lista de facturas. Es independiente de [_selectedDate], que
  /// sigue controlando las métricas del día y el PDF.
  late DateTimeRange _facturasRange;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    final hoy = DateTime.now();
    final dia = DateTime(hoy.year, hoy.month, hoy.day);
    _facturasRange = DateTimeRange(start: dia, end: dia);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _exportarPdf(
    Map<String, dynamic> dia,
    List<Map<String, dynamic>> topProductos,
  ) async {
    final inventario = ref.read(valorInventarioProvider).value ?? {};
    List<Map<String, dynamic>> productosVendidos = [];
    List<Map<String, dynamic>> productosPublico = [];
    List<Map<String, dynamic>> productosMayorista = [];
    try {
      final start = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      final end = start.add(const Duration(days: 1));
      
      var rows = [];
      try {
        rows = await Supabase.instance.client
            .from('detalle_ventas')
            .select('''
              cantidad,
              precio_unitario,
              subtotal,
              productos (
                nombre,
                categorias (
                  nombre
                )
              ),
              ventas!inner (
                fecha,
                estado,
                tipo
              )
            ''')
            .eq('ventas.estado', 'completada')
            .gte('ventas.fecha', start.toUtc().toIso8601String())
            .lt('ventas.fecha', end.toUtc().toIso8601String());
      } catch (_) {
        rows = await Supabase.instance.client
            .from('detalle_ventas')
            .select('''
              cantidad,
              precio_unitario,
              subtotal,
              productos (
                nombre
              ),
              ventas!inner (
                fecha,
                estado,
                tipo
              )
            ''')
            .eq('ventas.estado', 'completada')
            .gte('ventas.fecha', start.toUtc().toIso8601String())
            .lt('ventas.fecha', end.toUtc().toIso8601String());
      }
      
      final Map<String, Map<String, dynamic>> grouped = {};
      final Map<String, Map<String, dynamic>> groupedPublico = {};
      final Map<String, Map<String, dynamic>> groupedMayorista = {};

      void acumular(
        Map<String, Map<String, dynamic>> target,
        String prodName,
        String catName,
        int qty,
        double subtotal,
      ) {
        if (target.containsKey(prodName)) {
          target[prodName]!['cantidad'] = (target[prodName]!['cantidad'] as int) + qty;
          target[prodName]!['total'] = (target[prodName]!['total'] as double) + subtotal;
        } else {
          target[prodName] = {
            'nombre': prodName,
            'categoria': catName,
            'cantidad': qty,
            'total': subtotal,
          };
        }
      }

      for (final r in rows) {
        final prod = r['productos'] as Map<String, dynamic>?;
        if (prod == null) continue;
        final prodName = prod['nombre'] as String? ?? 'Desconocido';

        String catName = 'Otros';
        if (prod['categorias'] != null) {
          final cat = prod['categorias'] as Map<String, dynamic>?;
          catName = cat?['nombre'] as String? ?? 'Otros';
        } else if (prod['categoria'] != null) {
          final cat = prod['categoria'] as Map<String, dynamic>?;
          catName = cat?['nombre'] as String? ?? 'Otros';
        }

        final qty = (r['cantidad'] as num?)?.toInt() ?? 0;
        final subtotal = (r['subtotal'] as num?)?.toDouble() ?? 0.0;

        final venta = r['ventas'] as Map<String, dynamic>?;
        final tipo = venta?['tipo'] as String? ?? 'publico';

        acumular(grouped, prodName, catName, qty, subtotal);
        if (tipo == 'mayorista') {
          acumular(groupedMayorista, prodName, catName, qty, subtotal);
        } else {
          acumular(groupedPublico, prodName, catName, qty, subtotal);
        }
      }
      int porCantidad(Map<String, dynamic> a, Map<String, dynamic> b) =>
          (b['cantidad'] as int).compareTo(a['cantidad'] as int);
      productosVendidos = grouped.values.toList()..sort(porCantidad);
      productosPublico = groupedPublico.values.toList()..sort(porCantidad);
      productosMayorista = groupedMayorista.values.toList()..sort(porCantidad);
    } catch (e) {
      // Silencioso
    }

    final pdf = pw.Document();
    
    // Cargar logo remove-bg desde assets
    pw.MemoryImage? logoImage;
    try {
      final byteData = await DefaultAssetBundle.of(context).load('assets/images/logov1_removebg.png');
      final imageBytes = byteData.buffer.asUint8List();
      logoImage = pw.MemoryImage(imageBytes);
    } catch (_) {
      // Ignorar error para entornos sin assets cargados
    }

    // Agregar página del reporte contable
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        theme: pw.ThemeData.withFont(
          base: pw.Font.helvetica(),
          bold: pw.Font.helveticaBold(),
        ).copyWith(
          defaultTextStyle: const pw.TextStyle(color: PdfColors.black, fontSize: 11),
        ),
        header: (pw.Context context) {
          return pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(bottom: 20),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Reporte Financiero - Distribuidora Don Héctor', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                pw.Text('Pág. ${context.pageNumber} de ${context.pagesCount}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
              ],
            ),
          );
        },
        build: (pw.Context ctx) {
          return [
            // Encabezado
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logoImage != null)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(right: 16),
                    child: pw.Image(logoImage, width: 60, height: 60),
                  ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'DISTRIBUIDORA DON HÉCTOR',
                        style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Reporte Completo de Ventas y Contabilidad',
                        style: const pw.TextStyle(fontSize: 13, color: PdfColors.grey700),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'Fecha del informe: ${DateFormat('dd MMMM yyyy', 'es').format(_selectedDate)}  ·  Generado: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
                        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 24),

            // Métricas Clave (Tarjetas en PDF usando Tabla)
            pw.Text('Resumen del Periodo', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF5F5F5)),
                  children: [
                    _buildTableCell('Métrica', isHeader: true),
                    _buildTableCell('Venta / Ingreso', isHeader: true),
                    _buildTableCell('Gasto / Salida', isHeader: true),
                    _buildTableCell('Utilidad Neta', isHeader: true),
                  ],
                ),
                pw.TableRow(
                  children: [
                    _buildTableCell('Operación Diaria (${dia['num_ventas'] ?? 0} Ventas)'),
                    _buildTableCell(CurrencyFormatter.cop(dia['ventas_dia'] ?? 0)),
                    _buildTableCell(CurrencyFormatter.cop(dia['gastos_dia'] ?? 0)),
                    _buildTableCell(
                      CurrencyFormatter.cop(dia['utilidad_dia'] ?? 0),
                      color: (dia['utilidad_dia'] ?? 0) >= 0 ? PdfColors.green700 : PdfColors.red700,
                      isBold: true,
                    ),
                  ],
                ),
                pw.TableRow(
                  children: [
                    _buildTableCell('Efectivo Real (Caja)'),
                    _buildTableCell('—'),
                    _buildTableCell('—'),
                    _buildTableCell(CurrencyFormatter.cop(dia['efectivo_real'] ?? 0), isBold: true),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 12),

            // Detalles Adicionales
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('DEUDA TOTAL MAYORISTAS', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                        pw.SizedBox(height: 2),
                        pw.Text(CurrencyFormatter.cop(dia['deuda_pendiente'] ?? 0), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.red700)),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('VALOR TOTAL INVENTARIO', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                        pw.SizedBox(height: 2),
                        pw.Text(CurrencyFormatter.cop(inventario['total_venta'] ?? 0), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.blue700)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 24),

            // Top Productos del Mes
            pw.Text('Top 5 Productos más Vendidos del Mes', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)),
            pw.SizedBox(height: 8),
            if (topProductos.isEmpty)
              pw.Text('No hay ventas registradas en el mes para este ranking.', style: pw.TextStyle(fontStyle: pw.FontStyle.italic, color: PdfColors.grey600))
            else
              pw.TableHelper.fromTextArray(
                headers: ['#', 'Producto', 'Categoría', 'Cant. Vendida', 'Ingresos Totales'],
                data: [
                  for (int i = 0; i < topProductos.length; i++) ...[
                    [
                      (i + 1).toString(),
                      topProductos[i]['nombre'] ?? '',
                      topProductos[i]['categoria'] ?? 'Otros',
                      topProductos[i]['unidades_vendidas']?.toString() ?? '0',
                      CurrencyFormatter.cop(topProductos[i]['ingresos_totales'] ?? 0),
                    ]
                  ]
                ],
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.black),
                cellStyle: const pw.TextStyle(color: PdfColors.black),
                headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE8F2ED)),
                headerAlignment: pw.Alignment.center,
                cellAlignment: pw.Alignment.centerLeft,
                cellAlignments: {
                  0: pw.Alignment.center,
                  3: pw.Alignment.centerRight,
                  4: pw.Alignment.centerRight,
                },
              ),
            pw.SizedBox(height: 24),

            // Listado de todos los productos vendidos en el día
            pw.Text('Productos Vendidos del Día', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)),
            pw.SizedBox(height: 8),
            if (productosVendidos.isEmpty)
              pw.Text('No hay productos vendidos en este día.', style: pw.TextStyle(fontStyle: pw.FontStyle.italic, color: PdfColors.grey600))
            else
              pw.TableHelper.fromTextArray(
                headers: ['Producto', 'Categoría', 'Cant. Vendida', 'Total Venta'],
                data: [
                  for (final prod in productosVendidos) ...[
                    [
                      prod['nombre'] ?? '',
                      prod['categoria'] ?? 'Otros',
                      prod['cantidad']?.toString() ?? '0',
                      CurrencyFormatter.cop(prod['total'] ?? 0),
                    ]
                  ]
                ],
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.black),
                cellStyle: const pw.TextStyle(color: PdfColors.black),
                headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFECEFF1)),
                headerAlignment: pw.Alignment.center,
                cellAlignment: pw.Alignment.centerLeft,
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.center,
                  3: pw.Alignment.centerRight,
                },
              ),
            pw.SizedBox(height: 24),

            // Ventas discriminadas: al público
            _buildPdfTablaPorTipo(
              'Ventas al Público (Discriminado)',
              productosPublico,
              const PdfColor.fromInt(0xFFE8F2ED),
            ),
            pw.SizedBox(height: 24),

            // Ventas discriminadas: a mayoristas
            _buildPdfTablaPorTipo(
              'Ventas a Mayoristas (Discriminado)',
              productosMayorista,
              const PdfColor.fromInt(0xFFF2ECE0),
            ),
            pw.SizedBox(height: 24),

            // Gráfica de Distribución (Pie Chart) al final
            pw.Text('Distribución de Productos Vendidos (Volumen)', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)),
            pw.SizedBox(height: 8),
            _buildPdfPieChart(productosVendidos),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }

  /// Tabla de productos vendidos filtrada por tipo de venta (público o mayorista),
  /// con una fila de totales (unidades e ingresos) al final.
  pw.Widget _buildPdfTablaPorTipo(
    String titulo,
    List<Map<String, dynamic>> productos,
    PdfColor headerColor,
  ) {
    final totalIngresos = productos.fold<double>(
      0.0,
      (sum, p) => sum + ((p['total'] as num?)?.toDouble() ?? 0.0),
    );
    final totalUnidades = productos.fold<int>(
      0,
      (sum, p) => sum + ((p['cantidad'] as num?)?.toInt() ?? 0),
    );
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          titulo,
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800),
        ),
        pw.SizedBox(height: 8),
        if (productos.isEmpty)
          pw.Text(
            'No hay ventas de este tipo en este día.',
            style: pw.TextStyle(fontStyle: pw.FontStyle.italic, color: PdfColors.grey600),
          )
        else ...[
          pw.TableHelper.fromTextArray(
            headers: ['Producto', 'Categoría', 'Cant. Vendida', 'Total Venta'],
            data: [
              for (final prod in productos)
                [
                  prod['nombre'] ?? '',
                  prod['categoria'] ?? 'Otros',
                  prod['cantidad']?.toString() ?? '0',
                  CurrencyFormatter.cop(prod['total'] ?? 0),
                ],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.black),
            cellStyle: const pw.TextStyle(color: PdfColors.black),
            headerDecoration: pw.BoxDecoration(color: headerColor),
            headerAlignment: pw.Alignment.center,
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.center,
              3: pw.Alignment.centerRight,
            },
          ),
          pw.SizedBox(height: 4),
          pw.Container(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Total:  $totalUnidades und  ·  ${CurrencyFormatter.cop(totalIngresos)}',
              style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800),
            ),
          ),
        ],
      ],
    );
  }

  pw.Widget _buildTableCell(String text, {bool isHeader = false, bool isBold = false, PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        textAlign: isHeader ? pw.TextAlign.center : pw.TextAlign.left,
        style: pw.TextStyle(
          fontWeight: isHeader || isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
          fontSize: isHeader ? 10 : 9.5,
          color: color ?? PdfColors.black,
        ),
      ),
    );
  }

  pw.Widget _buildPdfPieChart(List<Map<String, dynamic>> productosVendidos) {
    if (productosVendidos.isEmpty) {
      return pw.Center(
        child: pw.Text(
          'No hay datos de productos vendidos hoy para graficar.',
          style: const pw.TextStyle(color: PdfColors.grey600),
        ),
      );
    }

    // Agrupar los top 4 y el resto en 'Otros'
    final List<Map<String, dynamic>> slices = [];
    double otrosTotal = 0.0;
    
    for (int i = 0; i < productosVendidos.length; i++) {
      final p = productosVendidos[i];
      final qty = (p['cantidad'] as num?)?.toDouble() ?? 0.0;
      if (i < 4) {
        slices.add({
          'nombre': p['nombre'] as String? ?? 'Desconocido',
          'cantidad': qty,
        });
      } else {
        otrosTotal += qty;
      }
    }
    
    if (otrosTotal > 0) {
      slices.add({
        'nombre': 'Otros',
        'cantidad': otrosTotal,
      });
    }

    final totalQty = slices.fold<double>(0.0, (sum, s) => sum + (s['cantidad'] as double));
    if (totalQty == 0) {
      return pw.Center(
        child: pw.Text(
          'No hay volumen de venta para graficar.',
          style: const pw.TextStyle(color: PdfColors.grey600),
        ),
      );
    }

    final sliceColors = [
      PdfColors.blue400,
      PdfColors.green400,
      PdfColors.amber400,
      PdfColors.red400,
      PdfColors.purple400,
    ];

    return pw.Container(
      height: 160,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Row(
        children: [
          // Gráfica de pastel
          pw.Expanded(
            flex: 2,
            child: pw.Chart(
              grid: pw.PieGrid(),
              datasets: [
                for (int i = 0; i < slices.length; i++)
                  pw.PieDataSet(
                    legend: slices[i]['nombre'] as String,
                    value: slices[i]['cantidad'] as double,
                    color: sliceColors[i % sliceColors.length],
                  ),
              ],
            ),
          ),
          pw.SizedBox(width: 20),
          // Leyenda detallada
          pw.Expanded(
            flex: 3,
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < slices.length; i++) ...[
                  pw.Row(
                    children: [
                      pw.Container(
                        width: 10,
                        height: 10,
                        decoration: pw.BoxDecoration(
                          color: sliceColors[i % sliceColors.length],
                          shape: pw.BoxShape.circle,
                        ),
                      ),
                      pw.SizedBox(width: 8),
                      pw.Expanded(
                        child: pw.Text(
                          '${slices[i]['nombre']} (${(slices[i]['cantidad'] as double).toStringAsFixed(0)} uds - ${((slices[i]['cantidad'] as double) / totalQty * 100).toStringAsFixed(1)}%)',
                          style: const pw.TextStyle(fontSize: 9),
                          maxLines: 1,
                          overflow: pw.TextOverflow.clip,
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 6),
                ]
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _esRangoDeUnDia() {
    final inicio = _facturasRange.start;
    final fin = _facturasRange.end;
    return inicio.year == fin.year &&
        inicio.month == fin.month &&
        inicio.day == fin.day;
  }

  String _rangoFacturasTexto() {
    final formato = DateFormat('dd/MM/yyyy');
    if (_esRangoDeUnDia()) {
      return formato.format(_facturasRange.start);
    }
    return '${formato.format(_facturasRange.start)} - ${formato.format(_facturasRange.end)}';
  }

  String _tituloFacturas() {
    final hoy = DateTime.now();
    final inicio = _facturasRange.start;
    final esHoy = _esRangoDeUnDia() &&
        inicio.year == hoy.year &&
        inicio.month == hoy.month &&
        inicio.day == hoy.day;
    if (esHoy) return 'Facturas del día';
    return 'Facturas del ${_rangoFacturasTexto()}';
  }

  Future<void> _seleccionarRangoFacturas() async {
    final rango = await showDateRangePicker(
      context: context,
      initialDateRange: _facturasRange,
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
    if (rango != null) {
      setState(() {
        _facturasRange = rango;
      });
    }
  }

  Future<void> _mostrarItemsVenta(
    BuildContext context,
    String ventaId,
    String clienteNombre,
    num totalVenta,
  ) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFA131310),
        title: Text('Items de la venta · $clienteNombre'),
        content: SizedBox(
          width: 460,
          child: Consumer(
            builder: (context, ref, _) {
              final items = ref.watch(itemsVentaProvider(ventaId));
              return items.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No se pudieron cargar los items: $error',
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
                data: (lista) {
                  if (lista.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Esta venta no tiene items registrados.'),
                    );
                  }

                  final sumaItems = lista.fold<num>(
                    0,
                    (suma, item) => suma + ((item['subtotal'] as num?) ?? 0),
                  );

                  return SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildFilaItem(
                          nombre: 'Producto',
                          cantidad: 'Cant.',
                          precioUnitario: 'P. Unit.',
                          total: 'Total',
                          esEncabezado: true,
                        ),
                        const Divider(height: 12),
                        for (final item in lista)
                          _buildFilaItem(
                            nombre: (item['productos'] as Map?)?['nombre'] as String? ??
                                'Producto eliminado',
                            cantidad: '${(item['cantidad'] as num?)?.toInt() ?? 0}',
                            precioUnitario:
                                CurrencyFormatter.cop(item['precio_unitario'] ?? 0),
                            total: CurrencyFormatter.cop(item['subtotal'] ?? 0),
                          ),
                        const Divider(height: 12),
                        _buildFilaItem(
                          nombre: 'TOTAL',
                          cantidad: '',
                          precioUnitario: '',
                          total: CurrencyFormatter.cop(sumaItems),
                          esEncabezado: true,
                        ),
                        if (sumaItems != totalVenta) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              'Total facturado con descuento: '
                              '${CurrencyFormatter.cop(totalVenta)}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.blancoD,
                                  ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _buildFilaItem({
    required String nombre,
    required String cantidad,
    required String precioUnitario,
    required String total,
    bool esEncabezado = false,
  }) {
    final estilo = TextStyle(
      color: esEncabezado ? AppColors.blanco : AppColors.blancoD,
      fontWeight: esEncabezado ? FontWeight.bold : FontWeight.normal,
      fontSize: 13,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(nombre, style: estilo, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            flex: 1,
            child: Text(cantidad, style: estilo, textAlign: TextAlign.right),
          ),
          Expanded(
            flex: 3,
            child: Text(precioUnitario, style: estilo, textAlign: TextAlign.right),
          ),
          Expanded(
            flex: 3,
            child: Text(total, style: estilo, textAlign: TextAlign.right),
          ),
        ],
      ),
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
            const Text(
              '¿Estás seguro de anular esta venta? El stock de los productos '
              'asociados será restaurado. Si es una venta mayorista, la deuda '
              'y los abonos recibidos se marcarán como devueltos.',
            ),
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
        ref.invalidate(ventasPorRangoProvider);
        ref.invalidate(mayoristasClientesProvider);
        ref.invalidate(clienteCobrosProvider);
        ref.invalidate(clienteVentasProductosProvider);

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

  Widget _buildMetricCard(String title, String value, IconData icon, Color color, {String? subtitle, String? subtitle2}) {
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
                  if (subtitle2 != null) ...[
                    const SizedBox(height: 1),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        subtitle2,
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




  @override
  Widget build(BuildContext context) {
    final metricasDia = ref.watch(metricasDiaProvider(_selectedDate));
    final ventas7Dias = ref.watch(ventasUltimos7DiasProvider);
    final topProductos = ref.watch(topProductosMesProvider);
    final facturas = ref.watch(ventasPorRangoProvider(_facturasRange));
    final metricasMes = ref.watch(metricasMesProvider);
    final valorInventario = ref.watch(valorInventarioProvider);

    final isLoading = metricasDia.isLoading || 
        ventas7Dias.isLoading || 
        topProductos.isLoading || 
        facturas.isLoading ||
        metricasMes.isLoading ||
        valorInventario.isLoading;

    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (metricasDia.hasError || 
        metricasMes.hasError || 
        valorInventario.hasError ||
        ventas7Dias.hasError ||
        topProductos.hasError ||
        facturas.hasError) {
      final error = metricasDia.error ?? 
          metricasMes.error ?? 
          valorInventario.error ?? 
          ventas7Dias.error ?? 
          topProductos.error ?? 
          facturas.error;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'Error al cargar los datos contables',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '$error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  ref.invalidate(metricasDiaProvider(_selectedDate));
                  ref.invalidate(metricasMesProvider);
                  ref.invalidate(valorInventarioProvider);
                  ref.invalidate(ventasUltimos7DiasProvider);
                  ref.invalidate(topProductosMesProvider);
                  ref.invalidate(ventasPorRangoProvider(_facturasRange));
                },
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    final dia = metricasDia.value ?? {};
    final top = topProductos.value ?? [];
    final facturasList = facturas.value ?? [];
    final mes = metricasMes.value ?? {};
    final inventario = valorInventario.value ?? {};

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(
              icon: Icon(Icons.today_outlined),
              text: 'Resumen Diario',
            ),
            Tab(
              icon: Icon(Icons.trending_up_outlined),
              text: 'Métricas Avanzadas',
            ),
            Tab(
              icon: Icon(Icons.insights_outlined),
              text: 'Utilidad x Producto',
            ),
          ],
          indicatorColor: AppColors.ambar,
          labelColor: AppColors.ambar,
          unselectedLabelColor: AppColors.blancoD,
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(metricasDiaProvider(_selectedDate));
                  ref.invalidate(metricasMesProvider);
                  ref.invalidate(valorInventarioProvider);
                  ref.invalidate(ventasUltimos7DiasProvider);
                  ref.invalidate(topProductosMesProvider);
                  ref.invalidate(ventasPorRangoProvider(_facturasRange));
                },
                child: ListView(
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
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CapitalScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.account_balance),
                  label: const Text('Capital y Patrimonio'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const FiadosScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.handshake_outlined),
                  label: const Text('Fiados'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const PrestamosScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.request_quote_outlined),
                  label: const Text('Préstamos'),
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
                  'Fiados Pendientes',
                  CurrencyFormatter.cop(dia['fiados_pendiente'] ?? 0),
                  Icons.handshake_outlined,
                  Colors.deepOrange,
                ),
                _buildMetricCard(
                  'Préstamos por Pagar',
                  CurrencyFormatter.cop(dia['prestamos_pendiente'] ?? 0),
                  Icons.request_quote_outlined,
                  Colors.purple,
                ),
                _buildMetricCard(
                  'Deuda',
                  CurrencyFormatter.cop(dia['deuda_compras'] ?? 0),
                  Icons.credit_card,
                  Colors.redAccent,
                ),
                _buildMetricCard(
                  'Efectivo Real',
                  CurrencyFormatter.cop(dia['efectivo_real'] ?? 0),
                  Icons.account_balance_wallet,
                  Colors.amber,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        ref.watch(resumenHoyProvider).when(
          data: (resHoy) {
            final comprasHoy = resHoy['compras_hoy'] as num? ?? 0;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: AppColors.blancoD),
                  const SizedBox(width: 8),
                  Text(
                    'Compras de inventario hoy: ${CurrencyFormatter.cop(comprasHoy)}',
                    style: const TextStyle(color: AppColors.blancoD, fontSize: 13),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Las compras aumentan tu inventario, no se restan de la utilidad diaria.',
                    triggerMode: TooltipTriggerMode.tap,
                    child: const Icon(Icons.help_outline, size: 14, color: AppColors.ambar),
                  ),
                ],
              ),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
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
                _tituloFacturas(),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.calendar_month),
              label: const Text('Filtrar fechas'),
              onPressed: _seleccionarRangoFacturas,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (facturasList.isEmpty)
          Center(child: Text('No hay facturas registradas en ${_rangoFacturasTexto()}'))
        else
          Card(
            elevation: 2,
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: facturasList.length,
              separatorBuilder: (c, i) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final venta = facturasList[i];
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
                        DateFormat(_esRangoDeUnDia() ? 'HH:mm' : 'dd/MM HH:mm')
                            .format(fecha != null ? DateTime.parse(fecha).toLocal() : DateTime.now()),
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
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.visibility_outlined, color: AppColors.ambar),
                        tooltip: 'Ver items',
                        onPressed: () => _mostrarItemsVenta(
                          context,
                          venta['id'].toString(),
                          clienteNombre,
                          total,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        tooltip: 'Anular venta',
                        onPressed: () => _confirmarEliminarVenta(context, venta['id'].toString()),
                      ),
                    ],
                  ),
                  isThreeLine: true,
                );
              },
            ),
          ),
        const SizedBox(height: 24),
        Center(
          child: TextButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CapitalScreen()),
              );
            },
            icon: const Icon(Icons.account_balance, color: AppColors.ambar),
            label: const Text(
              'Ver patrimonio del negocio →',
              style: TextStyle(color: AppColors.ambar, fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        ),
        const SizedBox(height: 32),
      ],
    ),
    ),
    _buildMetricasAvanzadasTab(context, mes, inventario),
    const UtilidadProductoTab(),
  ],
),
),
],
);
  }

  Widget _buildMetricasAvanzadasTab(
    BuildContext context,
    Map<String, dynamic> mes,
    Map<String, num> inventario,
  ) {
    final valorCosto = inventario['total_costo'] ?? 0;
    final cogsMes = mes['cogs_mes'] ?? 0;
    final ventasMes = mes['ventas_mes'] ?? 0;
    final gastosMes = mes['gastos_mes'] ?? 0;
    final deudaPendiente = mes['deuda_pendiente'] ?? 0;
    final ventasMayoristaMes = mes['ventas_mayorista_mes'] ?? 0;

    final daysInMonth = DateTime.now().day;
    final rotacion = cogsMes / (valorCosto > 0 ? valorCosto : 1);
    final dailyCogs = cogsMes / daysInMonth;
    final dsi = dailyCogs > 0 ? (valorCosto / dailyCogs) : 0;
    final margenBruto = (ventasMes > 0) ? ((ventasMes - cogsMes) / ventasMes * 100) : 0;
    final breakEven = (margenBruto > 0) ? (gastosMes / (margenBruto / 100)) : 0.0;
    final dailyMayoristaSales = ventasMayoristaMes / daysInMonth;
    final dso = (dailyMayoristaSales > 0) ? (deudaPendiente / dailyMayoristaSales) : 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // HITO 2: GESTIÓN DE INVENTARIO
        _buildSectionTitle('Gestión de Inventario (Hito 2)'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildAdvancedMetricCard(
                context,
                'Rotación de Inventario',
                '${rotacion.toStringAsFixed(2)}x al mes',
                Icons.loop,
                Colors.teal,
                'Mide cuántas veces al mes vendes y vuelves a llenar tu bodega. Si el número es alto, significa que tu mercancía se mueve rápido y no tienes dinero estancado en productos parados.',
                extraInfo: 'Inventario: ${CurrencyFormatter.cop(valorCosto)} al costo',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildAdvancedMetricCard(
                context,
                'Días de Stock Disponible',
                dsi > 365 ? '>365 días' : '${dsi.toStringAsFixed(0)} días',
                Icons.hourglass_empty,
                Colors.amber,
                'Te dice cuántos días te duraría la mercancía que tienes en bodega si no compraras nada más a partir de hoy. Te ayuda a saber cuándo pedir más mercancía antes de quedarte sin nada.',
                extraInfo: 'Consumo diario: ${CurrencyFormatter.cop(dailyCogs)}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // HITO 3: RENTABILIDAD AVANZADA
        _buildSectionTitle('Rentabilidad y Viabilidad (Hito 3)'),
        const SizedBox(height: 12),
        _buildAdvancedMetricCard(
          context,
          'Margen Bruto de Contribución',
          '${margenBruto.toStringAsFixed(1)}%',
          Icons.percent,
          Colors.blue,
          'Es el porcentaje de dinero que te queda libre de cada venta después de pagar lo que te costó comprar la mercancía. Te dice si estás cobrando lo suficiente para cubrir tus gastos.',
          extraInfo: 'Costo total de ventas (COGS): ${CurrencyFormatter.cop(cogsMes)}',
        ),
        const SizedBox(height: 10),
        _buildBreakEvenCard(context, breakEven, ventasMes),
        const SizedBox(height: 20),

        // HITO 4: CRÉDITOS Y COBROS
        _buildSectionTitle('Mayoristas y Crédito (Hito 4)'),
        const SizedBox(height: 12),
        _buildAdvancedMetricCard(
          context,
          'Período Promedio de Cobro',
          '${dso.toStringAsFixed(0)} días',
          Icons.assignment_ind,
          Colors.deepOrange,
          'Indica el número promedio de días que tardan tus clientes mayoristas en pagarte las facturas a crédito. Te sirve para saber si están pagando rápido o si se están demorando mucho en pagar.',
          extraInfo: 'Deuda por cobrar: ${CurrencyFormatter.cop(deudaPendiente)}',
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: AppColors.blanco,
        ),
      ),
    );
  }

  Widget _buildAdvancedMetricCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color,
    String helpText, {
    String? extraInfo,
  }) {
    return Card(
      elevation: 0,
      color: AppColors.superficie,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.borde, width: 1.5),
        ),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        color: color.withOpacity(0.2),
                        child: Icon(icon, color: color, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(color: AppColors.blancoD, fontSize: 12, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.help_outline, color: AppColors.ambar, size: 18),
                  onPressed: () => _mostrarAyudaMetricas(context, title, helpText),
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              value,
              style: const TextStyle(color: AppColors.blanco, fontSize: 22, fontWeight: FontWeight.bold),
            ),
            if (extraInfo != null) ...[
              const SizedBox(height: 6),
              Text(
                extraInfo,
                style: const TextStyle(color: AppColors.blancoD, fontSize: 10.5, fontWeight: FontWeight.w400),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBreakEvenCard(BuildContext context, num breakEven, num ventasMes) {
    final progress = breakEven > 0 ? (ventasMes / breakEven).clamp(0.0, 1.0) : 0.0;
    final percent = (progress * 100).toStringAsFixed(0);

    return Card(
      elevation: 0,
      color: AppColors.superficie,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.borde, width: 1.5),
        ),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      color: Colors.purple.withOpacity(0.2),
                      child: const Icon(Icons.balance, color: Colors.purple, size: 20),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Punto de Equilibrio Mensual',
                      style: TextStyle(color: AppColors.blancoD, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.help_outline, color: AppColors.ambar, size: 18),
                  onPressed: () => _mostrarAyudaMetricas(
                    context,
                    'Punto de Equilibrio Mensual',
                    'Es la cantidad mínima de dinero que debes vender en el mes para cubrir todos tus gastos y el costo de la mercancía. A partir de esta cifra, tu negocio empieza a tener ganancias reales.',
                  ),
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              CurrencyFormatter.cop(breakEven),
              style: const TextStyle(color: AppColors.blanco, fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Ventas del mes: ${CurrencyFormatter.cop(ventasMes)}',
                  style: const TextStyle(color: AppColors.blancoD, fontSize: 10.5),
                ),
                Text(
                  '$percent%',
                  style: TextStyle(
                    color: progress >= 1.0 ? AppColors.verde : AppColors.ambar,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: AppColors.borde,
                valueColor: AlwaysStoppedAnimation<Color>(
                  progress >= 1.0 ? AppColors.verde : AppColors.ambar,
                ),
                minHeight: 6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarAyudaMetricas(BuildContext context, String titulo, String explicacion) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131310),
        shape: Border.all(color: AppColors.borde, width: 1.5),
        title: Row(
          children: [
            const Icon(Icons.info_outline, color: AppColors.ambar),
            const SizedBox(width: 8),
            Text(
              titulo,
              style: const TextStyle(color: AppColors.blanco, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          explicacion,
          style: const TextStyle(color: AppColors.blancoD, fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Entendido',
              style: TextStyle(color: AppColors.ambar, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
