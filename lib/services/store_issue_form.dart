import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/inventory_models.dart';

Future<bool?> printStoreIssueForm({
  String hotelName = 'THE DREAM OF SAU INN BEACH HOTEL',
  StoreRequisition? requisition,
}) {
  return Printing.layoutPdf(
    onLayout: (_) =>
        buildStoreIssueFormPdf(hotelName: hotelName, requisition: requisition),
    name: requisition == null
        ? 'store-issue-form.pdf'
        : 'store-issue-${requisition.id}.pdf',
  );
}

Future<Uint8List> buildStoreIssueFormPdf({
  String hotelName = 'THE DREAM OF SAU INN BEACH HOTEL',
  StoreRequisition? requisition,
}) async {
  final document = pw.Document();
  final navy = PdfColor.fromHex('#123B45');
  final teal = PdfColor.fromHex('#006D77');
  final pale = PdfColor.fromHex('#EAF3F2');
  final muted = PdfColor.fromHex('#52656A');
  final border = PdfColor.fromHex('#89999C');
  final lines = requisition?.lines ?? const <RequisitionLine>[];
  final rowCount = lines.length < 12 ? 12 : lines.length;
  final requestedAt = requisition?.requestedAt;

  pw.Widget field(String label, {String value = ''}) => pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(7, 5, 7, 6),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: border, width: .6),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(
          '$label: ',
          style: pw.TextStyle(
            fontSize: 8,
            color: muted,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 1),
            decoration: pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: border, width: .5),
              ),
            ),
            child: pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 9,
                color: navy,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  pw.Widget signature(String title, {String? name}) => pw.Container(
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: border, width: .6),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 8,
            color: teal,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 7),
        pw.Text(
          'Jina / Name: ${name ?? ''}',
          style: const pw.TextStyle(fontSize: 8),
        ),
        pw.SizedBox(height: 14),
        pw.Container(height: .6, color: border),
        pw.SizedBox(height: 3),
        pw.Text(
          'Sahihi / Signature                         Tarehe / Date',
          style: pw.TextStyle(fontSize: 7, color: muted),
        ),
      ],
    ),
  );

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 30),
      footer: (context) => pw.Container(
        alignment: pw.Alignment.centerRight,
        padding: const pw.EdgeInsets.only(top: 8),
        child: pw.Text(
          'DreamStore - ${context.pageNumber}/${context.pagesCount}',
          style: pw.TextStyle(fontSize: 7, color: muted),
        ),
      ),
      build: (context) => [
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: navy,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Text(
                hotelName.toUpperCase(),
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Text(
                'STORE REQUISITION & ISSUE VOUCHER',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'FOMU YA OMBI, MATUMIZI NA UTOAJI WA BIDHAA STORE',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(color: PdfColors.white, fontSize: 8),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 10),
        pw.Row(
          children: [
            pw.Expanded(
              flex: 2,
              child: field(
                'Namba ya fomu / Voucher No.',
                value: requisition?.id ?? '',
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: field('Tarehe / Date', value: _formatDate(requestedAt)),
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Row(
          children: [
            pw.Expanded(
              child: field(
                'Department',
                value: requisition?.department.label ?? '',
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: field(
                'Aliyeomba / Requested by',
                value: requisition?.requestedBy ?? '',
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        field('Sababu / Purpose of issue', value: requisition?.note ?? ''),
        pw.SizedBox(height: 9),
        pw.Text(
          'Jaza kiasi halisi kilichotolewa, kilichotumika na kilichorudishwa store.',
          style: pw.TextStyle(fontSize: 8, color: muted),
        ),
        pw.SizedBox(height: 4),
        pw.Table(
          border: pw.TableBorder.all(color: border, width: .55),
          columnWidths: const {
            0: pw.FixedColumnWidth(25),
            1: pw.FlexColumnWidth(3.2),
            2: pw.FlexColumnWidth(1.05),
            3: pw.FlexColumnWidth(.85),
            4: pw.FlexColumnWidth(.9),
            5: pw.FlexColumnWidth(.9),
            6: pw.FlexColumnWidth(.9),
            7: pw.FlexColumnWidth(1.35),
          },
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: pale),
              repeat: true,
              children:
                  [
                        'Na.',
                        'Bidhaa / Item',
                        'Code',
                        'Unit',
                        'Qty\\nAsked',
                        'Qty\\nIssued',
                        'Qty\\nUsed',
                        'Qty Returned / Notes',
                      ]
                      .map(
                        (label) => pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(
                            horizontal: 3,
                            vertical: 6,
                          ),
                          child: pw.Text(
                            label,
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(
                              fontSize: 7,
                              fontWeight: pw.FontWeight.bold,
                              color: navy,
                            ),
                          ),
                        ),
                      )
                      .toList(),
            ),
            for (var index = 0; index < rowCount; index++)
              pw.TableRow(
                children:
                    [
                          '${index + 1}',
                          index < lines.length ? lines[index].productName : '',
                          index < lines.length ? lines[index].productSku : '',
                          index < lines.length ? lines[index].unit : '',
                          index < lines.length
                              ? '${lines[index].quantity}'
                              : '',
                          '',
                          '',
                          '',
                        ]
                        .map(
                          (value) => pw.Container(
                            height: 24,
                            alignment: pw.Alignment.centerLeft,
                            padding: const pw.EdgeInsets.symmetric(
                              horizontal: 4,
                            ),
                            child: pw.Text(
                              value,
                              style: const pw.TextStyle(fontSize: 7),
                            ),
                          ),
                        )
                        .toList(),
              ),
          ],
        ),
        pw.SizedBox(height: 8),
        field('Maelezo / Remarks', value: requisition?.note ?? ''),
        pw.SizedBox(height: 9),
        pw.Text(
          'UTHIBITISHO NA SAHIHI / APPROVAL & HANDOVER',
          style: pw.TextStyle(
            fontSize: 9,
            color: navy,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 5),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: signature(
                'Aliyeomba / Requested by',
                name: requisition?.requestedBy,
              ),
            ),
            pw.SizedBox(width: 7),
            pw.Expanded(
              child: signature(
                'Mkuu wa department / Approved by',
                name: requisition?.approvedBy,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: signature(
                'Storekeeper / Issued by',
                name: requisition?.issuedBy,
              ),
            ),
            pw.SizedBox(width: 7),
            pw.Expanded(
              child: signature(
                'Aliyechukua / Received by',
                name: requisition?.receivedBy,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          'Store copy: Hifadhi fomu hii pamoja na kumbukumbu za matumizi ya department.',
          style: pw.TextStyle(fontSize: 7, color: muted),
        ),
      ],
    ),
  );

  return document.save();
}

String _formatDate(DateTime? date) {
  if (date == null) return '';
  final local = date.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/${local.year}';
}
