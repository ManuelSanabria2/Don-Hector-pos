import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;

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

    // Cargar logo LogoV1 desde assets
    pw.MemoryImage? logoImage;
    try {
      final byteData = await rootBundle.load('assets/images/logo_v1.png');
      final imageBytes = byteData.buffer.asUint8List();
      logoImage = pw.MemoryImage(imageBytes);
    } catch (e) {
      // Ignorar error para permitir testing u otros entornos sin asset bundle
    }

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(0), // Eliminar márgenes de página transparentes
        theme: pw.ThemeData.withFont(
          base: pw.Font.helvetica(),
          bold: pw.Font.helveticaBold(),
        ).copyWith(
          defaultTextStyle: const pw.TextStyle(color: PdfColors.black, fontSize: 12),
        ),
        build: (context) {
          return pw.Container(
            color: PdfColors.white, // Forzar fondo blanco en toda la página
            padding: const pw.EdgeInsets.all(40), // Márgenes internos del documento
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (logoImage != null)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(right: 20),
                        child: pw.Image(logoImage, width: 80, height: 80),
                      ),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'Comprobante de venta',
                            style: pw.TextStyle(
                              fontSize: 22,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.black,
                            ),
                          ),
                          pw.SizedBox(height: 8),
                          pw.Text('Venta: $ventaNumero', style: const pw.TextStyle(color: PdfColors.black)),
                          pw.Text('Fecha: ${DateFormatter.dateTime(receipt.fecha)}', style: const pw.TextStyle(color: PdfColors.black)),
                          pw.Text(
                            'Método de pago: ${_metodoPagoLabel(receipt.metodoPago)}',
                            style: const pw.TextStyle(color: PdfColors.black),
                          ),
                        ],
                      ),
                    ),
                  ],
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
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.black),
                  cellStyle: const pw.TextStyle(color: PdfColors.black),
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
                pw.Divider(color: PdfColors.grey),
                _totalRow('Total', receipt.total, bold: true),
              ],
            ),
          );
        },
      ),
    );

    return doc.save();
  }

  static pw.Widget _totalRow(String label, num value, {bool bold = false}) {
    final style = bold 
        ? pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.black) 
        : const pw.TextStyle(color: PdfColors.black);

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
