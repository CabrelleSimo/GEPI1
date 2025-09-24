import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

class PdfExporter {
  // Police lisible + accents ; chargée via fonts par défaut de pdf
  static pw.ThemeData _theme() {
    return pw.ThemeData.withFont(
      base: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
      italic: pw.Font.helveticaOblique(),
      boldItalic: pw.Font.helveticaBoldOblique(),
    );
  }

  static Future<void> exportDataTable({
    required String title,
    required List<String> headers,
    required List<List<String>> rows,
    bool landscape = false,
    String? subtitle,
  }) async {
    final doc = pw.Document();
    final now = DateTime.now();
    final df = DateFormat('yyyy-MM-dd HH:mm');

    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          orientation: landscape ? pw.PageOrientation.landscape : pw.PageOrientation.portrait,
          margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          theme: _theme(),
        ),
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            if (subtitle != null) pw.SizedBox(height: 2),
            if (subtitle != null) pw.Text(subtitle, style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 6),
            pw.Container(height: 1, color: PdfColors.grey300),
          ],
        ),
        footer: (ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Généré le ${df.format(now)}', style: const pw.TextStyle(fontSize: 9)),
            pw.Text('Page ${ctx.pageNumber}/${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
        build: (context) => [
          pw.Table.fromTextArray(
            headers: headers,
            data: rows,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo),
            cellAlignment: pw.Alignment.centerLeft,
            cellStyle: const pw.TextStyle(fontSize: 9),
            border: null,
            cellHeight: 20,
            headerAlignment: pw.Alignment.centerLeft,
            columnWidths: {
              // ajuste les col. essentielles
              0: const pw.FlexColumnWidth(1.2), // Etat
              1: const pw.FlexColumnWidth(1.4), // N° série
              2: const pw.FlexColumnWidth(1.4), // Modèle
              3: const pw.FlexColumnWidth(1.4), // Marque
              4: const pw.FlexColumnWidth(1.6), // Host
              5: const pw.FlexColumnWidth(1.2), // Type
              6: const pw.FlexColumnWidth(1.8), // Statut
              7: const pw.FlexColumnWidth(2.4), // Emplacement
              8: const pw.FlexColumnWidth(1.2), // Date achat
              9: const pw.FlexColumnWidth(2.0), // Attribué à
              10: const pw.FlexColumnWidth(1.6), // Dernière modif
            },
          ),
        ],
      ),
    );

    final bytes = await doc.save();

    // Ouvre la boîte de dialogue "Enregistrer / Imprimer" (Web, Desktop, Mobile)
    await Printing.sharePdf(
      bytes: Uint8List.fromList(bytes),
      filename: '${_slug(title)}-${DateFormat('yyyyMMdd-HHmm').format(now)}.pdf',
    );
  }

  static String _slug(String s) {
    final lower = s.toLowerCase();
    final cleaned = lower
        .replaceAll(RegExp(r"[éèêë]"), 'e')
        .replaceAll(RegExp(r"[àâ]"), 'a')
        .replaceAll(RegExp(r"[îï]"), 'i')
        .replaceAll(RegExp(r"[ôö]"), 'o')
        .replaceAll(RegExp(r"[ûüù]"), 'u')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-');
    return cleaned.replaceAll(RegExp(r'^-|-$'), '');
  }
}
