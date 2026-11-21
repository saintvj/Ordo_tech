import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../domain/bill.dart';
import '../../domain/bill_formatter.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';

/// Shares the bill as plain text through the platform share sheet (the
/// native Android sheet, the iOS share sheet).
Future<void> shareBillText(Gathering gathering) {
  return SharePlus.instance.share(
    ShareParams(
      text: formatBillText(gathering),
      subject: '${gathering.restaurantName} — ${gathering.name}',
    ),
  );
}

/// Builds a PDF of the bill and shares it through the platform share sheet.
Future<void> shareBillPdf(Gathering gathering) async {
  final bytes = await buildBillPdf(gathering);
  final safeName = gathering.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(
          bytes,
          mimeType: 'application/pdf',
          name: 'ordo_$safeName.pdf',
        ),
      ],
      subject: '${gathering.restaurantName} — ${gathering.name}',
    ),
  );
}

/// Renders the bill to PDF bytes. Separated out so it can be tested without
/// touching the share sheet.
Future<Uint8List> buildBillPdf(Gathering gathering) async {
  final config = gathering.billConfig;
  final bill = GatheringBill.of(gathering, config);
  final paid = gathering.paidParticipantIds;

  // Inter is bundled with the app (OFL) and has the ₹ glyph, so the PDF
  // renders prices offline without the default Helvetica, which cannot.
  final regular = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Inter-Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Inter-SemiBold.ttf'),
  );
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: regular, bold: bold),
  );

  pw.Widget money(String label, int paise, {bool bold = false}) => pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(
        label,
        style: pw.TextStyle(
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
      pw.Text(
        formatRupees(paise),
        style: pw.TextStyle(
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    ],
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (context) => [
        pw.Header(
          level: 0,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                gathering.restaurantName,
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(gathering.name),
              pw.Text(
                'Hosted by ${gathering.hostName} · '
                '${config.splitMethod == SplitMethod.splitEqually ? 'Split equally' : 'Pay as you eat'}',
                style: const pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
        ),
        for (final share in bill.shares) ...[
          pw.SizedBox(height: 12),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                '${share.name}'
                '${paid.contains(share.participantId) ? ' (paid)' : ''}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                formatRupees(share.totalPaise),
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
          if (config.splitMethod == SplitMethod.payAsYouEat)
            for (final line in gathering.linesFor(share.participantId))
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 12, top: 2),
                child: money(
                  '${line.itemName} × ${line.quantity}',
                  line.totalPaise,
                ),
              ),
        ],
        pw.Divider(),
        money('Subtotal', bill.subtotalPaise),
        if (bill.discountPaise > 0) money('Discount', -bill.discountPaise),
        if (bill.cgstPaise > 0) money('CGST', bill.cgstPaise),
        if (bill.sgstPaise > 0) money('SGST', bill.sgstPaise),
        if (bill.serviceChargePaise > 0)
          money('Service charge', bill.serviceChargePaise),
        pw.Divider(),
        money('Grand Total', bill.grandTotalPaise, bold: true),
      ],
    ),
  );

  return doc.save();
}
