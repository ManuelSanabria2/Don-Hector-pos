import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../data/models/carrito_item.dart';
import '../../data/models/venta_enums.dart';

class PosReceiptData {
  const PosReceiptData({
    required this.ventaId,
    required this.fecha,
    required this.items,
    required this.subtotal,
    required this.descuento,
    required this.total,
    required this.metodoPago,
  });

  final String ventaId;
  final DateTime fecha;
  final List<CarritoItem> items;
  final num subtotal;
  final num descuento;
  final num total;
  final MetodoPago metodoPago;
}

class PosReceiptPdf {
  static Future<Uint8List> build(PosReceiptData receipt) async {
    final doc = pw.Document();
    final ventaNumero = receipt.ventaId.length >= 8
        ? receipt.ventaId.substring(0, 8)
        : receipt.ventaId;

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Comprobante de venta',
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Text('Venta: $ventaNumero'),
              pw.Text('Fecha: ${DateFormatter.dateTime(receipt.fecha)}'),
              pw.Text(
                'Metodo de pago: ${_metodoPagoLabel(receipt.metodoPago)}',
              ),
              pw.SizedBox(height: 20),
              pw.TableHelper.fromTextArray(
                headers: ['Producto', 'Cant.', 'Unitario', 'Subtotal'],
                data: [
                  for (final item in receipt.items)
                    [
                      item.producto.nombre,
                      item.cantidad.toString(),
                      CurrencyFormatter.cop(item.precioUnitario),
                      CurrencyFormatter.cop(item.subtotal),
                    ],
                ],
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFE8F2ED),
                ),
                cellAlignment: pw.Alignment.centerLeft,
                cellAlignments: {
                  1: pw.Alignment.centerRight,
                  2: pw.Alignment.centerRight,
                  3: pw.Alignment.centerRight,
                },
              ),
              pw.SizedBox(height: 20),
              _totalRow('Subtotal', receipt.subtotal),
              _totalRow('Descuento', receipt.descuento),
              pw.Divider(),
              _totalRow('Total', receipt.total, bold: true),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  static pw.Widget _totalRow(String label, num value, {bool bold = false}) {
    final style = bold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null;

    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.end,
      children: [
        pw.Text(label, style: style),
        pw.SizedBox(width: 24),
        pw.SizedBox(
          width: 100,
          child: pw.Text(
            CurrencyFormatter.cop(value),
            textAlign: pw.TextAlign.right,
            style: style,
          ),
        ),
      ],
    );
  }
}

String _metodoPagoLabel(MetodoPago metodoPago) {
  return switch (metodoPago) {
    MetodoPago.efectivo => 'Efectivo',
    MetodoPago.nequi => 'Nequi',
    MetodoPago.daviplata => 'Daviplata',
    MetodoPago.transferencia => 'Transferencia',
    MetodoPago.otro => 'Otro',
  };
}
