import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../mobile/vehicle_damage_map.dart';
import '../mobile/walk_around_checklist.dart';
import 'pdf_saver_stub.dart' if (dart.library.html) 'pdf_saver_web.dart';

class InvoicePdfService {
  /// Generates an A4 PDF document with a modern company letterhead for an Invoice or Estimate.
  /// Uses built-in Helvetica fonts and strict ASCII-safe text so it works 100% offline with zero network/font errors.
  static Future<Uint8List> generateDocumentPdf({
    required Map<String, dynamic> workshopSettings,
    required Map<String, dynamic> estimate,
    Map<String, dynamic>? invoice,
    bool isInvoice = true,
  }) async {
    final pdf = pw.Document(
      title: isInvoice ? 'Tax Invoice' : 'Official Estimate',
      author: workshopSettings['name']?.toString() ?? 'AutoKe Auto Workshop',
    );

    final fontRegular = pw.Font.helvetica();
    final fontBold = pw.Font.helveticaBold();

    final d = _extractDocData(
      workshopSettings: workshopSettings,
      estimate: estimate,
      invoice: invoice,
      isInvoice: isInvoice,
    );

    const navyDark = PdfColor.fromInt(0xFF0F172A);
    const primaryBlue = PdfColor.fromInt(0xFF1D4ED8);
    const accentBlue = PdfColor.fromInt(0xFF2563EB);
    const lightBg = PdfColor.fromInt(0xFFF8FAFC);
    const borderGrey = PdfColor.fromInt(0xFFE2E8F0);
    const textMuted = PdfColor.fromInt(0xFF64748B);
    const textDark = PdfColor.fromInt(0xFF1E293B);

    final statusColor = (d.paymentStatus == 'PAID' || d.paymentStatus == 'APPROVED')
        ? const PdfColor.fromInt(0xFF15803D)
        : (d.paymentStatus == 'PAY_LATER' || d.paymentStatus == 'SENT')
            ? const PdfColor.fromInt(0xFFB45309)
            : const PdfColor.fromInt(0xFFB91C1C);

    final statusBgColor = (d.paymentStatus == 'PAID' || d.paymentStatus == 'APPROVED')
        ? const PdfColor.fromInt(0xFFDCFCE7)
        : (d.paymentStatus == 'PAY_LATER' || d.paymentStatus == 'SENT')
            ? const PdfColor.fromInt(0xFFFEF3C7)
            : const PdfColor.fromInt(0xFFFEE2E2);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(0),
        theme: pw.ThemeData.withFont(
          base: fontRegular,
          bold: fontBold,
        ),
        header: (context) {
          return pw.Column(
            children: [
              pw.Row(
                children: [
                  pw.Expanded(flex: 7, child: pw.Container(height: 10, color: navyDark)),
                  pw.Expanded(flex: 3, child: pw.Container(height: 10, color: accentBlue)),
                ],
              ),
              pw.Container(
                padding: const pw.EdgeInsets.fromLTRB(36, 24, 36, 20),
                decoration: const pw.BoxDecoration(
                  color: PdfColors.white,
                  border: pw.Border(bottom: pw.BorderSide(color: borderGrey, width: 1.5)),
                ),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      flex: 6,
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Container(
                            width: 52,
                            height: 52,
                            decoration: pw.BoxDecoration(
                              color: navyDark,
                              borderRadius: pw.BorderRadius.circular(10),
                            ),
                            child: pw.Center(
                              child: pw.Column(
                                mainAxisAlignment: pw.MainAxisAlignment.center,
                                children: [
                                  pw.Text(
                                    d.monogram,
                                    style: pw.TextStyle(
                                      font: fontBold,
                                      color: PdfColors.white,
                                      fontSize: 15,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  pw.Container(
                                    margin: const pw.EdgeInsets.only(top: 3),
                                    width: 24,
                                    height: 2.5,
                                    color: accentBlue,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          pw.SizedBox(width: 14),
                          pw.Expanded(
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  d.workshopName.toUpperCase(),
                                  style: pw.TextStyle(
                                    font: fontBold,
                                    fontSize: 16,
                                    color: navyDark,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                pw.SizedBox(height: 3),
                                pw.Text(
                                  'PRECISION AUTO REPAIR, DIAGNOSTICS & BODYWORK',
                                  style: pw.TextStyle(
                                    font: fontBold,
                                    fontSize: 8,
                                    color: accentBlue,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                pw.SizedBox(height: 6),
                                pw.Text(
                                  d.workshopAddress,
                                  style: const pw.TextStyle(fontSize: 9.5, color: textMuted),
                                ),
                                pw.SizedBox(height: 2),
                                pw.Text(
                                  'Tax / KRA PIN: ${d.workshopPin}  |  Tel: +254 700 000 000',
                                  style: pw.TextStyle(font: fontBold, fontSize: 9, color: textDark),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 16),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          isInvoice ? 'TAX INVOICE' : 'ESTIMATE',
                          style: pw.TextStyle(
                            font: fontBold,
                            fontSize: 21,
                            color: navyDark,
                            letterSpacing: 1.2,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: pw.BoxDecoration(
                            color: statusBgColor,
                            borderRadius: pw.BorderRadius.circular(6),
                          ),
                          child: pw.Text(
                            d.paymentStatus.toUpperCase(),
                            style: pw.TextStyle(
                              font: fontBold,
                              fontSize: 9,
                              color: statusColor,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                        pw.SizedBox(height: 8),
                        _metaKeyValue(fontRegular, fontBold, isInvoice ? 'Invoice No:' : 'Estimate No:', d.docNumber),
                        _metaKeyValue(fontRegular, fontBold, 'Job Card Ref:', d.jobNumber),
                        _metaKeyValue(fontRegular, fontBold, 'Issue Date:', d.createdAtStr),
                        _metaKeyValue(fontRegular, fontBold, 'Due Date:', d.dueDateStr),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
        footer: (context) {
          return pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 14),
            decoration: const pw.BoxDecoration(
              color: lightBg,
              border: pw.Border(top: pw.BorderSide(color: borderGrey, width: 1)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      '${d.workshopName} - Official Workshop Document',
                      style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: navyDark),
                    ),
                    pw.Text(
                      'All replacement parts and workmanship carry our standard workshop guarantee. Thank you for your business!',
                      style: const pw.TextStyle(fontSize: 8, color: textMuted),
                    ),
                  ],
                ),
                pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: textMuted),
                ),
              ],
            ),
          );
        },
        build: (context) {
          return [
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(36, 20, 36, 24),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Container(
                          padding: const pw.EdgeInsets.all(14),
                          decoration: pw.BoxDecoration(
                            color: lightBg,
                            borderRadius: pw.BorderRadius.circular(8),
                            border: pw.Border.all(color: borderGrey),
                          ),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                'BILL TO CUSTOMER',
                                style: pw.TextStyle(
                                  font: fontBold,
                                  fontSize: 8.5,
                                  color: accentBlue,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              pw.SizedBox(height: 6),
                              pw.Text(
                                d.customerName,
                                style: pw.TextStyle(font: fontBold, fontSize: 13, color: navyDark),
                              ),
                              pw.SizedBox(height: 4),
                              pw.Text('Phone: ${d.customerPhone}', style: const pw.TextStyle(fontSize: 9.5, color: textDark)),
                              if (d.customerEmail.isNotEmpty)
                                pw.Text('Email: ${d.customerEmail}', style: const pw.TextStyle(fontSize: 9.5, color: textDark)),
                              pw.Text('Location: ${d.customerAddress}', style: const pw.TextStyle(fontSize: 9.5, color: textMuted)),
                            ],
                          ),
                        ),
                      ),
                      pw.SizedBox(width: 16),
                      pw.Expanded(
                        child: pw.Container(
                          padding: const pw.EdgeInsets.all(14),
                          decoration: pw.BoxDecoration(
                            color: lightBg,
                            borderRadius: pw.BorderRadius.circular(8),
                            border: pw.Border.all(color: borderGrey),
                          ),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Row(
                                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                children: [
                                  pw.Text(
                                    'VEHICLE & JOB SPECIFICATIONS',
                                    style: pw.TextStyle(
                                      font: fontBold,
                                      fontSize: 8.5,
                                      color: accentBlue,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  pw.Container(
                                    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: pw.BoxDecoration(
                                      color: navyDark,
                                      borderRadius: pw.BorderRadius.circular(4),
                                    ),
                                    child: pw.Text(
                                      d.regNo.toUpperCase(),
                                      style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: PdfColors.white),
                                    ),
                                  ),
                                ],
                              ),
                              pw.SizedBox(height: 6),
                              pw.Text(
                                d.makeModel.isEmpty ? 'Registered Workshop Vehicle' : d.makeModel,
                                style: pw.TextStyle(font: fontBold, fontSize: 12, color: navyDark),
                              ),
                              pw.SizedBox(height: 4),
                              pw.Text('Service: ${d.serviceRequested}', style: const pw.TextStyle(fontSize: 9.5, color: textDark)),
                              pw.Text('Odometer: ${d.odometer}  |  Fuel: ${d.fuelLevel}', style: const pw.TextStyle(fontSize: 9, color: textMuted)),
                              pw.Text('Lead Technician: ${d.technician}', style: const pw.TextStyle(fontSize: 9, color: textMuted)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 22),

                  // Line Items Table
                  pw.Table(
                    border: pw.TableBorder.all(color: borderGrey, width: 0.8),
                    columnWidths: {
                      0: const pw.FixedColumnWidth(34),
                      1: const pw.FlexColumnWidth(4),
                      2: const pw.FixedColumnWidth(55),
                      3: const pw.FixedColumnWidth(95),
                      4: const pw.FixedColumnWidth(105),
                    },
                    children: [
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: navyDark),
                        children: [
                          _tableHeaderCell(fontBold, '#', alignRight: false),
                          _tableHeaderCell(fontBold, 'PART / LABOR DESCRIPTION', alignRight: false),
                          _tableHeaderCell(fontBold, 'QTY', alignRight: true),
                          _tableHeaderCell(fontBold, 'UNIT PRICE', alignRight: true),
                          _tableHeaderCell(fontBold, 'TOTAL (KSH)', alignRight: true),
                        ],
                      ),
                      if (d.lineItems.isEmpty)
                        pw.TableRow(
                          children: [
                            _tableBodyCell(fontRegular, '1'),
                            _tableBodyCell(fontBold, d.serviceRequested),
                            _tableBodyCell(fontRegular, '1', alignRight: true),
                            _tableBodyCell(fontRegular, _formatCurrency(d.subtotal), alignRight: true),
                            _tableBodyCell(fontBold, _formatCurrency(d.subtotal), alignRight: true),
                          ],
                        )
                      else
                        ...List.generate(d.lineItems.length, (i) {
                          final item = d.lineItems[i];
                          final qty = (item['quantity'] as num?)?.toInt() ?? 1;
                          final unitPrice = (item['unitPrice'] as num?)?.toDouble() ?? 0.0;
                          final rowTotal = (item['total'] as num?)?.toDouble() ?? (qty * unitPrice);
                          final isEven = i % 2 == 1;

                          return pw.TableRow(
                            decoration: pw.BoxDecoration(
                              color: isEven ? lightBg : PdfColors.white,
                            ),
                            children: [
                              _tableBodyCell(fontRegular, '${i + 1}'),
                              _tableBodyCell(fontBold, item['description']?.toString() ?? 'Part / Service'),
                              _tableBodyCell(fontRegular, '$qty', alignRight: true),
                              _tableBodyCell(fontRegular, _formatCurrency(unitPrice), alignRight: true),
                              _tableBodyCell(fontBold, _formatCurrency(rowTotal), alignRight: true),
                            ],
                          );
                        }),
                    ],
                  ),

                  pw.SizedBox(height: 22),

                  // Bottom Summary Section: Payment Info + QR Code on Left, Totals Card on Right
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        flex: 6,
                        child: pw.Container(
                          padding: const pw.EdgeInsets.all(14),
                          decoration: pw.BoxDecoration(
                            color: PdfColors.white,
                            borderRadius: pw.BorderRadius.circular(8),
                            border: pw.Border.all(color: borderGrey),
                          ),
                          child: pw.Row(
                            crossAxisAlignment: pw.CrossAxisAlignment.center,
                            children: [
                              pw.Expanded(
                                child: pw.Column(
                                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                                  children: [
                                    pw.Text(
                                      'PAYMENT & VERIFICATION DETAILS',
                                      style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: accentBlue, letterSpacing: 0.7),
                                    ),
                                    pw.SizedBox(height: 6),
                                    pw.Text('Payment Mode: ${d.paymentMode}', style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: navyDark)),
                                    if (d.mpesaReceiptNo.isNotEmpty) ...[
                                      pw.SizedBox(height: 2),
                                      pw.Text('Ref / M-Pesa Receipt: ${d.mpesaReceiptNo}', style: pw.TextStyle(font: fontBold, fontSize: 9, color: const PdfColor.fromInt(0xFF15803D))),
                                    ],
                                    pw.SizedBox(height: 3),
                                    pw.Text('M-Pesa Paybill: 400200  |  Account: ${d.docNumber}', style: const pw.TextStyle(fontSize: 9, color: textDark)),
                                    pw.Text('Bank: Stanbic / KCB Auto Workshop Account', style: const pw.TextStyle(fontSize: 9, color: textMuted)),
                                    pw.SizedBox(height: 6),
                                    pw.Text('KRA Tax PIN: ${d.workshopPin}', style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: textDark)),
                                  ],
                                ),
                              ),
                              pw.SizedBox(width: 12),
                              pw.Column(
                                children: [
                                  pw.BarcodeWidget(
                                    barcode: pw.Barcode.qrCode(),
                                    data: '${d.workshopName}|${d.docNumber}|PIN:${d.workshopPin}|REG:${d.regNo}|TOTAL:KSH ${d.grandTotal.toStringAsFixed(2)}',
                                    width: 60,
                                    height: 60,
                                    color: navyDark,
                                  ),
                                  pw.SizedBox(height: 3),
                                  pw.Text('Scan to Verify', style: const pw.TextStyle(fontSize: 7, color: textMuted)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      pw.SizedBox(width: 20),

                      pw.Expanded(
                        flex: 5,
                        child: pw.Container(
                          padding: const pw.EdgeInsets.all(14),
                          decoration: pw.BoxDecoration(
                            color: lightBg,
                            borderRadius: pw.BorderRadius.circular(8),
                            border: pw.Border.all(color: borderGrey),
                          ),
                          child: pw.Column(
                            children: [
                              _summaryLine(fontRegular, fontBold, 'Parts & Labor Subtotal', 'KSH ${_formatCurrency(d.subtotal)}'),
                              if (d.discountRate > 0) ...[
                                pw.SizedBox(height: 6),
                                _summaryLine(
                                  fontRegular,
                                  fontBold,
                                  'Workshop Discount (${d.discountRate.toStringAsFixed(0)}%)',
                                  '- KSH ${_formatCurrency(d.discountAmount)}',
                                  valueColor: const PdfColor.fromInt(0xFFB45309),
                                ),
                                pw.SizedBox(height: 6),
                                _summaryLine(fontRegular, fontBold, 'Net Taxable Amount', 'KSH ${_formatCurrency(d.taxableSubtotal)}'),
                              ],
                              pw.SizedBox(height: 6),
                              _summaryLine(fontRegular, fontBold, 'VAT (${d.taxRate.toStringAsFixed(0)}%)', '+ KSH ${_formatCurrency(d.taxAmount)}'),
                              if (isInvoice && d.amountPaid > 0) ...[
                                pw.SizedBox(height: 6),
                                _summaryLine(
                                  fontRegular,
                                  fontBold,
                                  'Amount Paid / Deposit',
                                  '- KSH ${_formatCurrency(d.amountPaid)}',
                                  valueColor: const PdfColor.fromInt(0xFF15803D),
                                ),
                                pw.SizedBox(height: 6),
                                _summaryLine(
                                  fontRegular,
                                  fontBold,
                                  'Balance Due',
                                  'KSH ${_formatCurrency(d.balanceDue)}',
                                  valueColor: d.balanceDue > 0 ? const PdfColor.fromInt(0xFFB91C1C) : const PdfColor.fromInt(0xFF15803D),
                                ),
                              ],
                              pw.SizedBox(height: 10),
                              pw.Container(
                                padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: pw.BoxDecoration(
                                  color: primaryBlue,
                                  borderRadius: pw.BorderRadius.circular(6),
                                ),
                                child: pw.Row(
                                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                  children: [
                                    pw.Text(
                                      isInvoice ? 'INVOICE TOTAL' : 'ESTIMATE TOTAL',
                                      style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.white),
                                    ),
                                    pw.Text(
                                      'KSH ${_formatCurrency(d.grandTotal)}',
                                      style: pw.TextStyle(font: fontBold, fontSize: 12.5, color: PdfColors.white),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  pw.SizedBox(height: 36),

                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Container(width: 170, height: 1, color: borderGrey),
                          pw.SizedBox(height: 6),
                          pw.Text('Authorized Workshop Signature & Stamp', style: const pw.TextStyle(fontSize: 8.5, color: textMuted)),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Container(width: 170, height: 1, color: borderGrey),
                          pw.SizedBox(height: 6),
                          pw.Text('Customer Acceptance Signature', style: const pw.TextStyle(fontSize: 8.5, color: textMuted)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  /// Directly triggers the system/browser A4 print dialog.
  static Future<void> printDocument({
    required Map<String, dynamic> workshopSettings,
    required Map<String, dynamic> estimate,
    Map<String, dynamic>? invoice,
    bool isInvoice = true,
  }) async {
    final bytes = await generateDocumentPdf(
      workshopSettings: workshopSettings,
      estimate: estimate,
      invoice: invoice,
      isInvoice: isInvoice,
    );
    await printPdfBytesImpl(bytes, _buildFileName(estimate, invoice, isInvoice));
  }

  /// Directly exports/downloads the A4 PDF file.
  static Future<void> exportPdfFile({
    required Map<String, dynamic> workshopSettings,
    required Map<String, dynamic> estimate,
    Map<String, dynamic>? invoice,
    bool isInvoice = true,
  }) async {
    final bytes = await generateDocumentPdf(
      workshopSettings: workshopSettings,
      estimate: estimate,
      invoice: invoice,
      isInvoice: isInvoice,
    );
    await saveAndDownloadPdfImpl(bytes, '${_buildFileName(estimate, invoice, isInvoice)}.pdf');
  }

  /// Opens a high-resolution native Flutter A4 Sheet Preview Modal with instant Print A4 and Export PDF buttons.
  static Future<void> showPreviewModal({
    required BuildContext context,
    required Map<String, dynamic> workshopSettings,
    required Map<String, dynamic> estimate,
    Map<String, dynamic>? invoice,
    bool isInvoice = true,
  }) async {
    final fileName = _buildFileName(estimate, invoice, isInvoice);
    final d = _extractDocData(
      workshopSettings: workshopSettings,
      estimate: estimate,
      invoice: invoice,
      isInvoice: isInvoice,
    );

    await showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: SizedBox(
            width: 900,
            height: 820,
            child: Column(
              children: [
                // Top Action Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: const BoxDecoration(
                    color: Color(0xFF0F172A),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.description_outlined, color: Colors.white),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${isInvoice ? "A4 Tax Invoice" : "A4 Official Estimate"} — $fileName',
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () async {
                          await printDocument(
                            workshopSettings: workshopSettings,
                            estimate: estimate,
                            invoice: invoice,
                            isInvoice: isInvoice,
                          );
                        },
                        icon: const Icon(Icons.print, size: 16),
                        label: const Text('Print A4'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: () async {
                          await exportPdfFile(
                            workshopSettings: workshopSettings,
                            estimate: estimate,
                            invoice: invoice,
                            isInvoice: isInvoice,
                          );
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                backgroundColor: Colors.green.shade700,
                                content: Text('Downloaded $fileName.pdf'),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.download, size: 16),
                        label: const Text('Export PDF'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close, color: Colors.white70),
                      ),
                    ],
                  ),
                ),

                // Scrollable Crisp A4 Paper Sheet Preview
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
                    child: Center(
                      child: Container(
                        width: 794, // Standard A4 width at 96 DPI
                        constraints: const BoxConstraints(minHeight: 1050),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.45),
                              blurRadius: 24,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: _buildFlutterA4SheetPreview(d, isInvoice),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Builds the visual A4 Sheet inside the preview dialog so it renders with 100% vector clarity.
  static Widget _buildFlutterA4SheetPreview(_DocData d, bool isInvoice) {
    final isPaid = d.paymentStatus == 'PAID' || d.paymentStatus == 'APPROVED';
    final isPending = d.paymentStatus == 'PAY_LATER' || d.paymentStatus == 'SENT';
    final statusColor = isPaid
        ? const Color(0xFF15803D)
        : isPending
            ? const Color(0xFFB45309)
            : const Color(0xFFB91C1C);
    final statusBg = isPaid
        ? const Color(0xFFDCFCE7)
        : isPending
            ? const Color(0xFFFEF3C7)
            : const Color(0xFFFEE2E2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Geometric Brand Ribbon
            Row(
              children: [
                Expanded(flex: 7, child: Container(height: 12, color: const Color(0xFF0F172A))),
                Expanded(flex: 3, child: Container(height: 12, color: const Color(0xFF2563EB))),
              ],
            ),
            // Company Letterhead Header
            Container(
              padding: const EdgeInsets.fromLTRB(44, 28, 44, 24),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1.5)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    flex: 6,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                d.monogram,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                width: 28,
                                height: 3,
                                color: const Color(0xFF2563EB),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                d.workshopName.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 3),
                              const Text(
                                'PRECISION AUTO REPAIR, DIAGNOSTICS & BODYWORK',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF2563EB),
                                  letterSpacing: 0.9,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                d.workshopAddress,
                                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Tax / KRA PIN: ${d.workshopPin}   •   Tel: +254 700 000 000',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        isInvoice ? 'TAX INVOICE' : 'ESTIMATE',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusBg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          d.paymentStatus.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _previewMetaRow(isInvoice ? 'Invoice No:' : 'Estimate No:', d.docNumber),
                      _previewMetaRow('Job Card Ref:', d.jobNumber),
                      _previewMetaRow('Issue Date:', d.createdAtStr),
                      _previewMetaRow('Due Date:', d.dueDateStr),
                    ],
                  ),
                ],
              ),
            ),

            // Body Content
            Padding(
              padding: const EdgeInsets.fromLTRB(44, 24, 44, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Two-Column Customer & Vehicle Cards
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'BILL TO CUSTOMER',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2563EB),
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                d.customerName,
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                              ),
                              const SizedBox(height: 4),
                              Text('Phone: ${d.customerPhone}', style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B))),
                              if (d.customerEmail.isNotEmpty)
                                Text('Email: ${d.customerEmail}', style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B))),
                              Text('Location: ${d.customerAddress}', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'VEHICLE & JOB SPECIFICATIONS',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF2563EB),
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0F172A),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      d.regNo.toUpperCase(),
                                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                d.makeModel.isEmpty ? 'Registered Workshop Vehicle' : d.makeModel,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                              ),
                              const SizedBox(height: 4),
                              Text('Service: ${d.serviceRequested}', style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B))),
                              Text('Odometer: ${d.odometer}  •  Fuel: ${d.fuelLevel}', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                              Text('Lead Technician: ${d.technician}', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Line Items Table
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                          decoration: const BoxDecoration(
                            color: Color(0xFF0F172A),
                            borderRadius: BorderRadius.vertical(top: Radius.circular(5)),
                          ),
                          child: const Row(
                            children: [
                              SizedBox(width: 36, child: Text('#', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
                              Expanded(flex: 4, child: Text('PART / LABOR DESCRIPTION', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
                              SizedBox(width: 60, child: Text('QTY', textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
                              SizedBox(width: 110, child: Text('UNIT PRICE', textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
                              SizedBox(width: 120, child: Text('TOTAL (KSH)', textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
                            ],
                          ),
                        ),
                        if (d.lineItems.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Row(
                              children: [
                                const SizedBox(width: 36, child: Text('1', style: TextStyle(fontSize: 12))),
                                Expanded(flex: 4, child: Text(d.serviceRequested, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                                const SizedBox(width: 60, child: Text('1', textAlign: TextAlign.right, style: TextStyle(fontSize: 12))),
                                SizedBox(width: 110, child: Text(_formatCurrency(d.subtotal), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
                                SizedBox(width: 120, child: Text(_formatCurrency(d.subtotal), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                              ],
                            ),
                          )
                        else
                          ...List.generate(d.lineItems.length, (i) {
                            final item = d.lineItems[i];
                            final qty = (item['quantity'] as num?)?.toInt() ?? 1;
                            final unitPrice = (item['unitPrice'] as num?)?.toDouble() ?? 0.0;
                            final rowTotal = (item['total'] as num?)?.toDouble() ?? (qty * unitPrice);
                            return Container(
                              color: i % 2 == 1 ? const Color(0xFFF8FAFC) : Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                              child: Row(
                                children: [
                                  SizedBox(width: 36, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
                                  Expanded(flex: 4, child: Text(item['description']?.toString() ?? 'Part / Service', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                                  SizedBox(width: 60, child: Text('$qty', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
                                  SizedBox(width: 110, child: Text(_formatCurrency(unitPrice), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
                                  SizedBox(width: 120, child: Text(_formatCurrency(rowTotal), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Payment Info + Financial Totals Row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 6,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'PAYMENT & VERIFICATION DETAILS',
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF2563EB), letterSpacing: 0.7),
                                    ),
                                    const SizedBox(height: 8),
                                    Text('Payment Mode: ${d.paymentMode}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF0F172A))),
                                    if (d.mpesaReceiptNo.isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Text('Ref / M-Pesa Receipt: ${d.mpesaReceiptNo}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: Color(0xFF15803D))),
                                    ],
                                    const SizedBox(height: 4),
                                    Text('M-Pesa Paybill: 400200  •  Account: ${d.docNumber}', style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B))),
                                    const Text('Bank: Stanbic / KCB Auto Workshop Account', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                                    const SizedBox(height: 6),
                                    Text('KRA Tax PIN: ${d.workshopPin}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: Color(0xFF1E293B))),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: const Column(
                                  children: [
                                    Icon(Icons.qr_code_2, size: 56, color: Color(0xFF0F172A)),
                                    Text('Verified QR', style: TextStyle(fontSize: 9, color: Color(0xFF64748B))),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        flex: 5,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            children: [
                              _previewSummaryLine('Parts & Labor Subtotal', 'KSH ${_formatCurrency(d.subtotal)}'),
                              if (d.discountRate > 0) ...[
                                const SizedBox(height: 8),
                                _previewSummaryLine(
                                  'Workshop Discount (${d.discountRate.toStringAsFixed(0)}%)',
                                  '- KSH ${_formatCurrency(d.discountAmount)}',
                                  valueColor: const Color(0xFFB45309),
                                ),
                                const SizedBox(height: 8),
                                _previewSummaryLine('Net Taxable Amount', 'KSH ${_formatCurrency(d.taxableSubtotal)}'),
                              ],
                              const SizedBox(height: 8),
                              _previewSummaryLine('VAT (${d.taxRate.toStringAsFixed(0)}%)', '+ KSH ${_formatCurrency(d.taxAmount)}'),
                              if (isInvoice && d.amountPaid > 0) ...[
                                const SizedBox(height: 8),
                                _previewSummaryLine(
                                  'Amount Paid / Deposit',
                                  '- KSH ${_formatCurrency(d.amountPaid)}',
                                  valueColor: const Color(0xFF15803D),
                                ),
                                const SizedBox(height: 8),
                                _previewSummaryLine(
                                  'Balance Due',
                                  'KSH ${_formatCurrency(d.balanceDue)}',
                                  valueColor: d.balanceDue > 0 ? const Color(0xFFB91C1C) : const Color(0xFF15803D),
                                ),
                              ],
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1D4ED8),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      isInvoice ? 'INVOICE TOTAL' : 'ESTIMATE TOTAL',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                                    ),
                                    Text(
                                      'KSH ${_formatCurrency(d.grandTotal)}',
                                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 48),

                  // Signature Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(width: 200, height: 1, color: const Color(0xFFCBD5E1)),
                          const SizedBox(height: 6),
                          const Text('Authorized Workshop Signature & Stamp', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(width: 200, height: 1, color: const Color(0xFFCBD5E1)),
                          const SizedBox(height: 6),
                          const Text('Customer Acceptance Signature', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),

        // Bottom Letterhead Footer Strip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 16),
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${d.workshopName} — Official Workshop Document',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF0F172A)),
                  ),
                  const Text(
                    'All replacement parts and workmanship carry our standard workshop guarantee. Thank you for your business!',
                    style: TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                  ),
                ],
              ),
              const Text('Page 1 of 1', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: Color(0xFF64748B))),
            ],
          ),
        ),
      ],
    );
  }

  static Widget _previewMetaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label ', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
          Text(value, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
        ],
      ),
    );
  }

  static Widget _previewSummaryLine(String label, String value, {Color valueColor = const Color(0xFF0F172A)}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
        Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: valueColor)),
      ],
    );
  }

  static _DocData _extractDocData({
    required Map<String, dynamic> workshopSettings,
    required Map<String, dynamic> estimate,
    Map<String, dynamic>? invoice,
    required bool isInvoice,
  }) {
    final workshopName = (workshopSettings['name']?.toString().trim().isNotEmpty ?? false)
        ? workshopSettings['name'].toString()
        : 'AutoKe Auto Workshop';
    final workshopAddress = (workshopSettings['address']?.toString().trim().isNotEmpty ?? false)
        ? workshopSettings['address'].toString()
        : 'Enterprise Road, Industrial Area, Nairobi, Kenya';
    final workshopPin = (workshopSettings['taxPin']?.toString().trim().isNotEmpty ?? false)
        ? workshopSettings['taxPin'].toString()
        : 'P051234567X';

    final job = (estimate['jobCard'] as Map<String, dynamic>?) ?? {};
    final customer = (job['customer'] as Map<String, dynamic>?) ?? {};
    final vehicle = (job['vehicle'] as Map<String, dynamic>?) ?? {};
    final lineItems = (estimate['lineItems'] as List<dynamic>?) ?? [];

    final docIdRaw = isInvoice
        ? (invoice?['id'] ?? estimate['id'] ?? '000000').toString()
        : (estimate['id'] ?? '000000').toString();
    final docShortId = docIdRaw.length >= 6 ? docIdRaw.substring(0, 6).toUpperCase() : docIdRaw.toUpperCase();
    final docNumber = isInvoice ? 'INV-$docShortId' : 'EST-$docShortId';

    final jobNumber = job['jobNumber']?.toString() ??
        (job['id'] != null && job['id'].toString().length >= 6
            ? 'JC-${job['id'].toString().substring(0, 6).toUpperCase()}'
            : 'JC-01001');

    final createdAtStr = _formatFullDate(isInvoice ? (invoice?['createdAt'] ?? estimate['createdAt']) : estimate['createdAt']);
    final dueDateStr = _formatFullDate(job['dueDate'] ?? DateTime.now().add(const Duration(days: 7)).toIso8601String());

    final customerName = customer['name']?.toString() ?? 'Valued Customer';
    final customerPhone = (customer['phone']?.toString().trim().isNotEmpty ?? false) ? customer['phone'].toString() : 'N/A';
    final customerEmail = (customer['email']?.toString().trim().isNotEmpty ?? false) ? customer['email'].toString() : '';
    final customerAddress = (customer['address']?.toString().trim().isNotEmpty ?? false) ? customer['address'].toString() : 'Nairobi, Kenya';

    final regNo = vehicle['registrationNo']?.toString() ?? 'N/A';
    final makeModel = '${vehicle['make'] ?? ''} ${vehicle['model'] ?? ''}'.trim();
    final odometer = job['odometer'] != null ? '${job['odometer']} km' : 'Recorded at intake';
    final fuelLevel = job['fuelLevel']?.toString() ?? 'Recorded at intake';
    final technician = job['technician']?.toString() ?? 'Workshop Team';
    final serviceRequested = job['workRequested']?.toString() ?? 'General Service & Repairs';

    final subtotal = (estimate['subtotal'] as num?)?.toDouble() ?? 0.0;
    final discountRate = (estimate['discountRate'] as num?)?.toDouble() ?? 0.0;
    final discountAmount = subtotal * (discountRate / 100.0);
    final taxableSubtotal = subtotal - discountAmount;
    final taxRate = (estimate['taxRate'] as num?)?.toDouble() ?? 16.0;
    final taxAmount = taxableSubtotal * (taxRate / 100.0);
    final grandTotal = (estimate['total'] as num?)?.toDouble() ?? (taxableSubtotal + taxAmount);

    final paymentStatus = isInvoice
        ? (invoice?['paymentStatus']?.toString() ?? 'UNPAID')
        : (estimate['status']?.toString() ?? 'APPROVED');
    final paymentMode = isInvoice ? (invoice?['paymentMode']?.toString() ?? 'MPESA / CASH') : 'N/A';
    final amountPaid = isInvoice
        ? ((invoice?['amountPaid'] as num?)?.toDouble() ?? (paymentStatus == 'PAID' ? grandTotal : 0.0))
        : 0.0;
    final balanceDue = isInvoice
        ? ((invoice?['balanceDue'] as num?)?.toDouble() ?? (grandTotal - amountPaid).clamp(0.0, grandTotal))
        : grandTotal;
    final mpesaReceiptNo = isInvoice ? (invoice?['mpesaReceiptNo']?.toString() ?? '') : '';

    final monogram = workshopName.substring(0, workshopName.length >= 3 ? 3 : 1).toUpperCase();

    return _DocData(
      workshopName: workshopName,
      workshopAddress: workshopAddress,
      workshopPin: workshopPin,
      monogram: monogram,
      docNumber: docNumber,
      jobNumber: jobNumber,
      createdAtStr: createdAtStr,
      dueDateStr: dueDateStr,
      customerName: customerName,
      customerPhone: customerPhone,
      customerEmail: customerEmail,
      customerAddress: customerAddress,
      regNo: regNo,
      makeModel: makeModel,
      odometer: odometer,
      fuelLevel: fuelLevel,
      technician: technician,
      serviceRequested: serviceRequested,
      lineItems: lineItems,
      subtotal: subtotal,
      discountRate: discountRate,
      discountAmount: discountAmount,
      taxableSubtotal: taxableSubtotal,
      taxRate: taxRate,
      taxAmount: taxAmount,
      grandTotal: grandTotal,
      paymentStatus: paymentStatus,
      paymentMode: paymentMode,
      amountPaid: amountPaid,
      balanceDue: balanceDue,
      mpesaReceiptNo: mpesaReceiptNo,
    );
  }

  static String _buildFileName(Map<String, dynamic> estimate, Map<String, dynamic>? invoice, bool isInvoice) {
    final raw = isInvoice ? (invoice?['id'] ?? estimate['id'] ?? '000000').toString() : (estimate['id'] ?? '000000').toString();
    final shortId = raw.length >= 6 ? raw.substring(0, 6).toUpperCase() : raw.toUpperCase();
    return isInvoice ? 'Invoice_INV-$shortId' : 'Estimate_EST-$shortId';
  }

  static pw.Widget _metaKeyValue(pw.Font labelFont, pw.Font valueFont, String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text('$label ', style: pw.TextStyle(font: labelFont, fontSize: 9, color: const PdfColor.fromInt(0xFF64748B))),
          pw.Text(value, style: pw.TextStyle(font: valueFont, fontSize: 9.5, color: const PdfColor.fromInt(0xFF0F172A))),
        ],
      ),
    );
  }

  static pw.Widget _tableHeaderCell(pw.Font boldFont, String text, {bool alignRight = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: pw.Text(
        text,
        textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(
          font: boldFont,
          fontSize: 8.5,
          color: PdfColors.white,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  static pw.Widget _tableBodyCell(pw.Font font, String text, {bool alignRight = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      child: pw.Text(
        text,
        textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(
          font: font,
          fontSize: 9.5,
          color: const PdfColor.fromInt(0xFF1E293B),
        ),
      ),
    );
  }

  static pw.Widget _summaryLine(
    pw.Font labelFont,
    pw.Font valueFont,
    String label,
    String value, {
    PdfColor valueColor = const PdfColor.fromInt(0xFF0F172A),
  }) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: pw.TextStyle(font: labelFont, fontSize: 9.5, color: const PdfColor.fromInt(0xFF475569))),
        pw.Text(value, style: pw.TextStyle(font: valueFont, fontSize: 9.5, color: valueColor)),
      ],
    );
  }

  static String _formatCurrency(double val) {
    final parts = val.toStringAsFixed(2).split('.');
    final intPart = parts[0].replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},');
    return '$intPart.${parts[1]}';
  }

  static String _formatFullDate(dynamic isoString) {
    if (isoString == null) return '-';
    try {
      final dt = DateTime.parse(isoString.toString()).toLocal();
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return '-';
    }
  }

  // ===========================================================================
  // A4 VEHICLE RECEIVING MEMO & JOB CARD (CUSTOMER COPY)
  // ===========================================================================

  /// Generates an A4 PDF document for the Vehicle Receiving Memo / Job Card (Customer Copy).
  static Future<Uint8List> generateJobCardPdf({
    required Map<String, dynamic> workshopSettings,
    required Map<String, dynamic> job,
  }) async {
    final pdf = pw.Document(
      title: 'Vehicle Receiving Memo & Job Card - Customer Copy',
      author: workshopSettings['name']?.toString() ?? 'AutoKe Auto Workshop',
    );

    final fontRegular = pw.Font.helvetica();
    final fontBold = pw.Font.helveticaBold();

    final d = _extractJobCardData(workshopSettings: workshopSettings, job: job);

    const navyDark = PdfColor.fromInt(0xFF0F172A);
    const primaryBlue = PdfColor.fromInt(0xFF1D4ED8);
    const accentBlue = PdfColor.fromInt(0xFF2563EB);
    const lightBg = PdfColor.fromInt(0xFFF8FAFC);
    const borderGrey = PdfColor.fromInt(0xFFE2E8F0);
    const textMuted = PdfColor.fromInt(0xFF64748B);
    const textDark = PdfColor.fromInt(0xFF1E293B);
    const greenColor = PdfColor.fromInt(0xFF15803D);
    const greenBg = PdfColor.fromInt(0xFFDCFCE7);
    const amberColor = PdfColor.fromInt(0xFFB45309);
    const amberBg = PdfColor.fromInt(0xFFFEF3C7);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(0),
        theme: pw.ThemeData.withFont(
          base: fontRegular,
          bold: fontBold,
        ),
        header: (context) {
          return pw.Column(
            children: [
              // Top Accent Ribbon
              pw.Container(
                height: 8,
                width: double.infinity,
                color: primaryBlue,
              ),
              // Main Letterhead Banner
              pw.Container(
                color: navyDark,
                padding: const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Container(
                          width: 42,
                          height: 42,
                          decoration: pw.BoxDecoration(
                            color: accentBlue,
                            borderRadius: pw.BorderRadius.circular(8),
                          ),
                          alignment: pw.Alignment.center,
                          child: pw.Text(
                            d.monogram,
                            style: pw.TextStyle(
                              font: fontBold,
                              color: PdfColors.white,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        pw.SizedBox(width: 12),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              d.workshopName.toUpperCase(),
                              style: pw.TextStyle(
                                font: fontBold,
                                color: PdfColors.white,
                                fontSize: 15,
                                letterSpacing: 0.6,
                              ),
                            ),
                            pw.SizedBox(height: 2),
                            pw.Text(
                              'VEHICLE RECEIVING MEMO & JOB CARD (CUSTOMER COPY)',
                              style: pw.TextStyle(
                                font: fontBold,
                                color: const PdfColor.fromInt(0xFF93C5FD),
                                fontSize: 8,
                                letterSpacing: 0.8,
                              ),
                            ),
                            pw.SizedBox(height: 3),
                            pw.Text(
                              '${d.workshopAddress}  |  Tax PIN: ${d.workshopPin}',
                              style: pw.TextStyle(
                                font: fontRegular,
                                color: const PdfColor.fromInt(0xFFCBD5E1),
                                fontSize: 8.5,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: pw.BoxDecoration(
                            color: accentBlue,
                            borderRadius: pw.BorderRadius.circular(4),
                          ),
                          child: pw.Text(
                            'CUSTOMER COPY',
                            style: pw.TextStyle(
                              font: fontBold,
                              color: PdfColors.white,
                              fontSize: 8.5,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          d.jobNumber,
                          style: pw.TextStyle(
                            font: fontBold,
                            color: PdfColors.white,
                            fontSize: 14,
                          ),
                        ),
                        pw.Text(
                          'Status: ${d.status.replaceAll('_', ' ')}',
                          style: pw.TextStyle(
                            font: fontBold,
                            color: const PdfColor.fromInt(0xFF93C5FD),
                            fontSize: 8.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.Container(height: 1.5, width: double.infinity, color: borderGrey),
            ],
          );
        },
        footer: (context) {
          return pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            decoration: const pw.BoxDecoration(
              color: lightBg,
              border: pw.Border(top: pw.BorderSide(color: borderGrey, width: 1)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      '${d.workshopName} - Official Vehicle Receiving Memo & Job Card Copy',
                      style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: navyDark),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Please present this Customer Copy when collecting your vehicle. Thank you for choosing us!',
                      style: pw.TextStyle(font: fontRegular, fontSize: 7.5, color: textMuted),
                    ),
                  ],
                ),
                pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: textMuted),
                ),
              ],
            ),
          );
        },
        build: (context) {
          return [
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(32, 16, 32, 16),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Top Metadata Strip
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: pw.BoxDecoration(
                      color: lightBg,
                      borderRadius: pw.BorderRadius.circular(6),
                      border: pw.Border.all(color: borderGrey),
                    ),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        _metaKeyValue(fontRegular, fontBold, 'Date In:', d.createdAtStr),
                        _metaKeyValue(fontRegular, fontBold, 'Promised Delivery:', d.dueDateStr),
                        _metaKeyValue(fontRegular, fontBold, 'Section:', d.memo.workshopSection.split(' ').first),
                        _metaKeyValue(fontRegular, fontBold, 'Visit Type:', d.memo.visitType),
                        _metaKeyValue(fontRegular, fontBold, 'Payment:', d.memo.paymentMode),
                      ],
                    ),
                  ),

                  pw.SizedBox(height: 12),

                  // Customer + Vehicle Info Row
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      // Customer Box
                      pw.Expanded(
                        flex: 5,
                        child: pw.Container(
                          padding: const pw.EdgeInsets.all(11),
                          decoration: pw.BoxDecoration(
                            color: PdfColors.white,
                            borderRadius: pw.BorderRadius.circular(6),
                            border: pw.Border.all(color: borderGrey),
                          ),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                'CUSTOMER / OWNER DETAILS',
                                style: pw.TextStyle(font: fontBold, fontSize: 8, color: accentBlue, letterSpacing: 0.6),
                              ),
                              pw.SizedBox(height: 5),
                              pw.Text(
                                d.customerName,
                                style: pw.TextStyle(font: fontBold, fontSize: 11.5, color: navyDark),
                              ),
                              pw.SizedBox(height: 3),
                              _metaKeyValue(fontRegular, fontBold, 'Phone:', d.customerPhone),
                              if (d.customerEmail.isNotEmpty)
                                _metaKeyValue(fontRegular, fontBold, 'Email:', d.customerEmail),
                              _metaKeyValue(fontRegular, fontBold, 'Address:', d.customerAddress),
                              _metaKeyValue(fontRegular, fontBold, 'Service Advisor / Tech:', d.technician),
                            ],
                          ),
                        ),
                      ),
                      pw.SizedBox(width: 12),
                      // Vehicle Box
                      pw.Expanded(
                        flex: 6,
                        child: pw.Container(
                          padding: const pw.EdgeInsets.all(11),
                          decoration: pw.BoxDecoration(
                            color: lightBg,
                            borderRadius: pw.BorderRadius.circular(6),
                            border: pw.Border.all(color: borderGrey),
                          ),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Row(
                                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                children: [
                                  pw.Text(
                                    'VEHICLE IDENTIFICATION & SPECS',
                                    style: pw.TextStyle(font: fontBold, fontSize: 8, color: accentBlue, letterSpacing: 0.6),
                                  ),
                                  pw.Container(
                                    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: pw.BoxDecoration(
                                      color: navyDark,
                                      borderRadius: pw.BorderRadius.circular(3),
                                    ),
                                    child: pw.Text(
                                      d.bodyTypeLabel.toUpperCase(),
                                      style: pw.TextStyle(font: fontBold, fontSize: 7, color: PdfColors.white),
                                    ),
                                  ),
                                ],
                              ),
                              pw.SizedBox(height: 5),
                              pw.Text(
                                '${d.regNo}  -  ${d.makeModel.isEmpty ? "Vehicle" : d.makeModel}',
                                style: pw.TextStyle(font: fontBold, fontSize: 11, color: navyDark),
                              ),
                              pw.SizedBox(height: 4),
                              pw.Row(
                                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                children: [
                                  _metaKeyValue(fontRegular, fontBold, 'Odometer:', d.odometer),
                                  _metaKeyValue(fontRegular, fontBold, 'Fuel Level:', d.fuelLevel),
                                ],
                              ),
                              pw.Row(
                                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                children: [
                                  _metaKeyValue(fontRegular, fontBold, 'VIN / Chassis:', d.memo.vinNumber.isEmpty ? 'N/A' : d.memo.vinNumber),
                                  _metaKeyValue(fontRegular, fontBold, 'Avg KM/Day:', d.memo.avgKmPerDay.isEmpty ? 'N/A' : d.memo.avgKmPerDay),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  pw.SizedBox(height: 10),

                  // Service Categories + Work Requested Box
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(11),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.white,
                      borderRadius: pw.BorderRadius.circular(6),
                      border: pw.Border.all(color: borderGrey),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              'SERVICE CATEGORIES & CUSTOMER INSTRUCTIONS / DEFECTS DESCRIPTION',
                              style: pw.TextStyle(font: fontBold, fontSize: 8, color: accentBlue, letterSpacing: 0.6),
                            ),
                            if (d.memo.approxCostEstimate.isNotEmpty)
                              pw.Text(
                                'Approx. Initial Estimate: KSH ${d.memo.approxCostEstimate}',
                                style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: greenColor),
                              ),
                          ],
                        ),
                        pw.SizedBox(height: 5),
                        pw.Text(
                          'Selected Categories: ${d.memo.selectedCategories.isEmpty ? "General Service & Inspection" : d.memo.selectedCategories.join("  |  ")}',
                          style: pw.TextStyle(font: fontBold, fontSize: 9, color: textDark),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Container(
                          width: double.infinity,
                          padding: const pw.EdgeInsets.all(8),
                          decoration: pw.BoxDecoration(
                            color: lightBg,
                            borderRadius: pw.BorderRadius.circular(4),
                            border: pw.Border.all(color: borderGrey),
                          ),
                          child: pw.Text(
                            d.workRequested,
                            style: pw.TextStyle(font: fontRegular, fontSize: 9.5, color: navyDark),
                          ),
                        ),
                        if (d.notes.isNotEmpty) ...[
                          pw.SizedBox(height: 4),
                          pw.Text(
                            'Advisor / Technician Notes: ${d.notes}',
                            style: pw.TextStyle(font: fontRegular, fontSize: 8.5, color: textMuted),
                          ),
                        ],
                      ],
                    ),
                  ),

                  pw.SizedBox(height: 10),

                  // 14-Item Walk-Around Inventory Checklist Grid
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(11),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.white,
                      borderRadius: pw.BorderRadius.circular(6),
                      border: pw.Border.all(color: borderGrey),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              'WALK-AROUND INVENTORY & ACCESSORIES CHECKLIST (${d.presentCount}/${kWalkAroundChecklistItems.length} PRESENT)',
                              style: pw.TextStyle(font: fontBold, fontSize: 8, color: accentBlue, letterSpacing: 0.6),
                            ),
                            pw.Row(
                              children: [
                                pw.Container(
                                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: pw.BoxDecoration(
                                    color: d.memo.keepReplacedParts ? amberBg : lightBg,
                                    borderRadius: pw.BorderRadius.circular(3),
                                  ),
                                  child: pw.Text(
                                    'Keep Old Parts: ${d.memo.keepReplacedParts ? "YES" : "NO"}',
                                    style: pw.TextStyle(font: fontBold, fontSize: 7.5, color: d.memo.keepReplacedParts ? amberColor : textDark),
                                  ),
                                ),
                                pw.SizedBox(width: 6),
                                pw.Container(
                                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: pw.BoxDecoration(
                                    color: d.memo.valuablesRemoved ? greenBg : amberBg,
                                    borderRadius: pw.BorderRadius.circular(3),
                                  ),
                                  child: pw.Text(
                                    'Valuables Removed: ${d.memo.valuablesRemoved ? "YES" : "NO"}',
                                    style: pw.TextStyle(font: fontBold, fontSize: 7.5, color: d.memo.valuablesRemoved ? greenColor : amberColor),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 7),
                        pw.Wrap(
                          spacing: 8,
                          runSpacing: 5,
                          children: kWalkAroundChecklistItems.map((item) {
                            final present = d.memo.checklist[item] ?? false;
                            return pw.Container(
                              width: 122,
                              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              decoration: pw.BoxDecoration(
                                color: present ? greenBg : lightBg,
                                borderRadius: pw.BorderRadius.circular(4),
                                border: pw.Border.all(
                                  color: present ? const PdfColor.fromInt(0xFF86EFAC) : borderGrey,
                                ),
                              ),
                              child: pw.Row(
                                mainAxisSize: pw.MainAxisSize.min,
                                children: [
                                  pw.Text(
                                    present ? '[X]' : '[ ]',
                                    style: pw.TextStyle(
                                      font: fontBold,
                                      fontSize: 8,
                                      color: present ? greenColor : textMuted,
                                    ),
                                  ),
                                  pw.SizedBox(width: 4),
                                  pw.Expanded(
                                    child: pw.Text(
                                      item,
                                      style: pw.TextStyle(
                                        font: present ? fontBold : fontRegular,
                                        fontSize: 8,
                                        color: present ? greenColor : textDark,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                        if (d.memo.remarks.isNotEmpty) ...[
                          pw.SizedBox(height: 6),
                          pw.Text(
                            'Checklist Remarks / Loose Items: ${d.memo.remarks}',
                            style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: textDark),
                          ),
                        ],
                      ],
                    ),
                  ),

                  pw.SizedBox(height: 10),

                  // 360° Walk-Around Exterior Damage Inspection Summary
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(11),
                    decoration: pw.BoxDecoration(
                      color: lightBg,
                      borderRadius: pw.BorderRadius.circular(6),
                      border: pw.Border.all(color: borderGrey),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              '360-DEGREE EXTERIOR BODY DAMAGE INSPECTION (${d.markers.length} MARKERS RECORDED)',
                              style: pw.TextStyle(font: fontBold, fontSize: 8, color: accentBlue, letterSpacing: 0.6),
                            ),
                            pw.Text(
                              'Body Profile: ${d.bodyTypeLabel}',
                              style: pw.TextStyle(font: fontBold, fontSize: 8, color: textMuted),
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 6),
                        if (d.markers.isEmpty)
                          pw.Text(
                            'No exterior dents, scratches, or body cuts recorded at vehicle check-in.',
                            style: pw.TextStyle(font: fontRegular, fontSize: 8.5, color: greenColor),
                          )
                        else
                          pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: ['front', 'left', 'rear', 'right', 'top'].map((angle) {
                              final angleMarkers = d.markers.where((m) => m.viewAngle.name == angle).toList();
                              final dents = angleMarkers.where((m) => m.type == DamageType.dent).length;
                              final scratches = angleMarkers.where((m) => m.type == DamageType.scratch).length;
                              final cuts = angleMarkers.where((m) => m.type == DamageType.cut).length;
                              final label = angle == 'front'
                                  ? 'FRONT'
                                  : angle == 'left'
                                      ? 'LEFT SIDE'
                                      : angle == 'rear'
                                          ? 'REAR'
                                          : angle == 'right'
                                              ? 'RIGHT SIDE'
                                              : 'TOP / ROOF';
                              return pw.Container(
                                width: 98,
                                padding: const pw.EdgeInsets.all(6),
                                decoration: pw.BoxDecoration(
                                  color: PdfColors.white,
                                  borderRadius: pw.BorderRadius.circular(4),
                                  border: pw.Border.all(
                                    color: angleMarkers.isNotEmpty ? const PdfColor.fromInt(0xFFFCA5A5) : borderGrey,
                                  ),
                                ),
                                child: pw.Column(
                                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                                  children: [
                                    pw.Text(label, style: pw.TextStyle(font: fontBold, fontSize: 7.5, color: navyDark)),
                                    pw.SizedBox(height: 2),
                                    if (angleMarkers.isEmpty)
                                      pw.Text('Clean (0)', style: pw.TextStyle(font: fontRegular, fontSize: 7.5, color: greenColor))
                                    else
                                      pw.Text(
                                        'D:$dents  S:$scratches  C:$cuts',
                                        style: pw.TextStyle(font: fontBold, fontSize: 7.5, color: const PdfColor.fromInt(0xFFB91C1C)),
                                      ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),

                  pw.SizedBox(height: 10),

                  // Terms & Conditions + QR Box
                  pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.white,
                      borderRadius: pw.BorderRadius.circular(6),
                      border: pw.Border.all(color: borderGrey),
                    ),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Row(
                                children: [
                                  pw.Text(
                                    'TERMS & CONDITIONS AUTHORIZATION  ',
                                    style: pw.TextStyle(font: fontBold, fontSize: 8, color: accentBlue),
                                  ),
                                  pw.Container(
                                    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                    decoration: pw.BoxDecoration(
                                      color: d.memo.termsAccepted ? greenBg : amberBg,
                                      borderRadius: pw.BorderRadius.circular(3),
                                    ),
                                    child: pw.Text(
                                      d.memo.termsAccepted ? 'ACCEPTED BY CUSTOMER' : 'PENDING SIGNATURE',
                                      style: pw.TextStyle(
                                        font: fontBold,
                                        fontSize: 7,
                                        color: d.memo.termsAccepted ? greenColor : amberColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              pw.SizedBox(height: 4),
                              pw.Text(
                                '1. I hereby authorize the above repair work to be done along with necessary material and agree that the workshop is not responsible for loss or damage to the vehicle or articles left in the vehicle in case of fire, theft, accidents, or any other cause beyond your control.\n'
                                '2. I authorize you and your employees to operate the vehicle herein described on streets, highways, or elsewhere for the purpose of testing and/or inspection.\n'
                                '3. An express mechanic\'s lien is hereby acknowledged on the above vehicle to secure the amount of repairs thereto. Storage charges apply if uncollected 48 hours after completion notice.',
                                style: pw.TextStyle(font: fontRegular, fontSize: 7.2, color: textMuted, lineSpacing: 1.2),
                              ),
                            ],
                          ),
                        ),
                        pw.SizedBox(width: 12),
                        pw.Column(
                          children: [
                            pw.BarcodeWidget(
                              barcode: pw.Barcode.qrCode(),
                              data: 'JOBCARD:${d.jobNumber}|REG:${d.regNo}|CUST:${d.customerName}|DATE:${d.createdAtStr}',
                              width: 48,
                              height: 48,
                              color: navyDark,
                            ),
                            pw.SizedBox(height: 2),
                            pw.Text('Gate Pass QR', style: pw.TextStyle(font: fontRegular, fontSize: 6.5, color: textMuted)),
                          ],
                        ),
                      ],
                    ),
                  ),

                  pw.SizedBox(height: 24),

                  // Signatures Row
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Container(width: 165, height: 1, color: const PdfColor.fromInt(0xFF94A3B8)),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            'Customer Signature (Check-In Authorization)',
                            style: pw.TextStyle(font: fontBold, fontSize: 8, color: textDark),
                          ),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Container(width: 165, height: 1, color: const PdfColor.fromInt(0xFF94A3B8)),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            'Service Advisor Signature (${d.technician})',
                            style: pw.TextStyle(font: fontBold, fontSize: 8, color: textDark),
                          ),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Container(width: 140, height: 1, color: const PdfColor.fromInt(0xFF94A3B8)),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            'Vehicle Released & Received By',
                            style: pw.TextStyle(font: fontBold, fontSize: 8, color: textDark),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  /// Triggers the A4 Print dialog for a Job Card / Vehicle Receiving Memo.
  static Future<void> printJobCard({
    required Map<String, dynamic> workshopSettings,
    required Map<String, dynamic> job,
  }) async {
    final bytes = await generateJobCardPdf(
      workshopSettings: workshopSettings,
      job: job,
    );
    final d = _extractJobCardData(workshopSettings: workshopSettings, job: job);
    await printPdfBytesImpl(bytes, 'JobCard_${d.jobNumber}_${d.regNo.replaceAll(' ', '')}');
  }

  /// Exports and downloads the A4 Job Card Customer Copy as a `.pdf` file.
  static Future<void> exportJobCardPdf({
    required Map<String, dynamic> workshopSettings,
    required Map<String, dynamic> job,
  }) async {
    final bytes = await generateJobCardPdf(
      workshopSettings: workshopSettings,
      job: job,
    );
    final d = _extractJobCardData(workshopSettings: workshopSettings, job: job);
    await saveAndDownloadPdfImpl(bytes, 'JobCard_${d.jobNumber}_${d.regNo.replaceAll(' ', '')}.pdf');
  }

  /// Opens a high-resolution interactive A4 Preview Modal for the Job Card Customer Copy
  /// with one-click Print A4 and Download PDF buttons.
  static Future<void> showJobCardPreviewModal({
    required BuildContext context,
    required Map<String, dynamic> workshopSettings,
    required Map<String, dynamic> job,
  }) async {
    final d = _extractJobCardData(workshopSettings: workshopSettings, job: job);

    await showDialog(
      context: context,
      builder: (ctx) {
        bool isProcessing = false;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Dialog(
              backgroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: 960,
                height: MediaQuery.of(context).size.height * 0.90,
                child: Column(
                  children: [
                    // Top Action Bar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      color: const Color(0xFF1E293B),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2563EB).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.assignment_turned_in_outlined, color: Color(0xFF60A5FA), size: 22),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'A4 Job Card & Receiving Memo (Customer Copy) — ${d.jobNumber}',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                  Text(
                                    '${d.regNo} (${d.makeModel}) • Customer: ${d.customerName}',
                                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              OutlinedButton.icon(
                                onPressed: isProcessing
                                    ? null
                                    : () async {
                                        setModalState(() => isProcessing = true);
                                        try {
                                          await printJobCard(
                                            workshopSettings: workshopSettings,
                                            job: job,
                                          );
                                        } catch (e) {
                                          if (ctx.mounted) {
                                            ScaffoldMessenger.of(ctx).showSnackBar(
                                              SnackBar(content: Text('Print error: $e'), backgroundColor: Colors.red),
                                            );
                                          }
                                        } finally {
                                          if (ctx.mounted) setModalState(() => isProcessing = false);
                                        }
                                      },
                                icon: const Icon(Icons.print_outlined, size: 18, color: Colors.white),
                                label: const Text('Print Customer Copy', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xFF475569)),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                ),
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton.icon(
                                onPressed: isProcessing
                                    ? null
                                    : () async {
                                        setModalState(() => isProcessing = true);
                                        try {
                                          await exportJobCardPdf(
                                            workshopSettings: workshopSettings,
                                            job: job,
                                          );
                                          if (ctx.mounted) {
                                            ScaffoldMessenger.of(ctx).showSnackBar(
                                              SnackBar(
                                                content: Text('Downloaded JobCard_${d.jobNumber}.pdf'),
                                                backgroundColor: const Color(0xFF16A34A),
                                              ),
                                            );
                                          }
                                        } catch (e) {
                                          if (ctx.mounted) {
                                            ScaffoldMessenger.of(ctx).showSnackBar(
                                              SnackBar(content: Text('PDF Export error: $e'), backgroundColor: Colors.red),
                                            );
                                          }
                                        } finally {
                                          if (ctx.mounted) setModalState(() => isProcessing = false);
                                        }
                                      },
                                icon: isProcessing
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                                label: const Text('Download PDF', style: TextStyle(fontWeight: FontWeight.bold)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF2563EB),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                onPressed: () => Navigator.pop(ctx),
                                icon: const Icon(Icons.close, color: Colors.white70),
                                tooltip: 'Close Preview',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Interactive A4 Sheet Preview Area
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        color: const Color(0xFF334155),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Container(
                                width: 794,
                                constraints: const BoxConstraints(minHeight: 1123),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(4),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.45),
                                      blurRadius: 24,
                                      offset: const Offset(0, 12),
                                    ),
                                  ],
                                ),
                                child: _buildFlutterA4JobCardSheet(d),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Builds the visual A4 Job Card & Vehicle Receiving Memo sheet in pure Flutter widgets.
  static Widget _buildFlutterA4JobCardSheet(_JobCardDocData d) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Accent Ribbon
            Container(height: 10, width: double.infinity, color: const Color(0xFF1D4ED8)),
            // Main Letterhead Banner
            Container(
              color: const Color(0xFF0F172A),
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          d.monogram,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d.workshopName.toUpperCase(),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 0.6),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'VEHICLE RECEIVING MEMO & JOB CARD (CUSTOMER COPY)',
                            style: TextStyle(color: Color(0xFF93C5FD), fontWeight: FontWeight.w700, fontSize: 10, letterSpacing: 0.8),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${d.workshopAddress}  •  Tax PIN: ${d.workshopPin}',
                            style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'CUSTOMER COPY',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.1),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        d.jobNumber,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
                      ),
                      Text(
                        'Status: ${d.status.replaceAll('_', ' ')}',
                        style: const TextStyle(color: Color(0xFF93C5FD), fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Metadata Strip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _previewMetaRow('Date In:', d.createdAtStr),
                        _previewMetaRow('Promised Delivery:', d.dueDateStr),
                        _previewMetaRow('Section:', d.memo.workshopSection.split(' ').first),
                        _previewMetaRow('Visit Type:', d.memo.visitType),
                        _previewMetaRow('Payment:', d.memo.paymentMode),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Customer & Vehicle Row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 5,
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'CUSTOMER / OWNER DETAILS',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF2563EB), letterSpacing: 0.6),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                d.customerName,
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                              ),
                              const SizedBox(height: 4),
                              _previewMetaRow('Phone:', d.customerPhone),
                              if (d.customerEmail.isNotEmpty) _previewMetaRow('Email:', d.customerEmail),
                              _previewMetaRow('Address:', d.customerAddress),
                              _previewMetaRow('Service Advisor / Tech:', d.technician),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 6,
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'VEHICLE IDENTIFICATION & SPECS',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF2563EB), letterSpacing: 0.6),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0F172A),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      d.bodyTypeLabel.toUpperCase(),
                                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${d.regNo}  •  ${d.makeModel.isEmpty ? "Vehicle" : d.makeModel}',
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _previewMetaRow('Odometer:', d.odometer),
                                  _previewMetaRow('Fuel Level:', d.fuelLevel),
                                ],
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _previewMetaRow('VIN / Chassis:', d.memo.vinNumber.isEmpty ? 'N/A' : d.memo.vinNumber),
                                  _previewMetaRow('Avg KM/Day:', d.memo.avgKmPerDay.isEmpty ? 'N/A' : d.memo.avgKmPerDay),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Service Categories & Customer Instructions
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'SERVICE CATEGORIES & CUSTOMER INSTRUCTIONS / DEFECTS DESCRIPTION',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF2563EB), letterSpacing: 0.6),
                            ),
                            if (d.memo.approxCostEstimate.isNotEmpty)
                              Text(
                                'Approx. Initial Estimate: KSH ${d.memo.approxCostEstimate}',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Selected Categories: ${d.memo.selectedCategories.isEmpty ? "General Service & Inspection" : d.memo.selectedCategories.join("  •  ")}',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Text(
                            d.workRequested,
                            style: const TextStyle(fontSize: 12, color: Color(0xFF0F172A)),
                          ),
                        ),
                        if (d.notes.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Advisor / Technician Notes: ${d.notes}',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 14-Item Walk-Around Inventory Checklist
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'WALK-AROUND INVENTORY & ACCESSORIES CHECKLIST (${d.presentCount}/${kWalkAroundChecklistItems.length} PRESENT)',
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF2563EB), letterSpacing: 0.6),
                            ),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: d.memo.keepReplacedParts ? const Color(0xFFFEF3C7) : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Keep Old Parts: ${d.memo.keepReplacedParts ? "YES" : "NO"}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: d.memo.keepReplacedParts ? const Color(0xFFB45309) : const Color(0xFF334155),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: d.memo.valuablesRemoved ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Valuables Removed: ${d.memo.valuablesRemoved ? "YES" : "NO"}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: d.memo.valuablesRemoved ? const Color(0xFF15803D) : const Color(0xFFB45309),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: kWalkAroundChecklistItems.map((item) {
                            final present = d.memo.checklist[item] ?? false;
                            return Container(
                              width: 165,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                color: present ? const Color(0xFFDCFCE7) : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: present ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    present ? Icons.check_box : Icons.check_box_outline_blank,
                                    size: 15,
                                    color: present ? const Color(0xFF15803D) : const Color(0xFF94A3B8),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      item,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: present ? FontWeight.bold : FontWeight.normal,
                                        color: present ? const Color(0xFF15803D) : const Color(0xFF475569),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                        if (d.memo.remarks.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Checklist Remarks / Loose Items: ${d.memo.remarks}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 360-Degree Exterior Body Damage Summary
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '360° EXTERIOR BODY DAMAGE INSPECTION (${d.markers.length} MARKERS RECORDED)',
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF2563EB), letterSpacing: 0.6),
                            ),
                            Text(
                              'Body Profile: ${d.bodyTypeLabel}',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (d.markers.isEmpty)
                          const Text(
                            '✓ No exterior dents, scratches, or body cuts recorded at vehicle check-in.',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF15803D)),
                          )
                        else
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: ['front', 'left', 'rear', 'right', 'top'].map((angle) {
                              final angleMarkers = d.markers.where((m) => m.viewAngle.name == angle).toList();
                              final dents = angleMarkers.where((m) => m.type == DamageType.dent).length;
                              final scratches = angleMarkers.where((m) => m.type == DamageType.scratch).length;
                              final cuts = angleMarkers.where((m) => m.type == DamageType.cut).length;
                              final label = angle == 'front'
                                  ? 'FRONT'
                                  : angle == 'left'
                                      ? 'LEFT SIDE'
                                      : angle == 'rear'
                                          ? 'REAR'
                                          : angle == 'right'
                                              ? 'RIGHT SIDE'
                                              : 'TOP / ROOF';
                              return Container(
                                width: 130,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: angleMarkers.isNotEmpty ? const Color(0xFFFCA5A5) : const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                                    const SizedBox(height: 4),
                                    if (angleMarkers.isEmpty)
                                      const Text('Clean (0)', style: TextStyle(fontSize: 10.5, color: Color(0xFF15803D)))
                                    else
                                      Text(
                                        'D:$dents  S:$scratches  C:$cuts',
                                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFFB91C1C)),
                                      ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Terms & Conditions + QR Gate Pass
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    'TERMS & CONDITIONS AUTHORIZATION  ',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: d.memo.termsAccepted ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      d.memo.termsAccepted ? '✓ ACCEPTED BY CUSTOMER' : 'PENDING SIGNATURE',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                        color: d.memo.termsAccepted ? const Color(0xFF15803D) : const Color(0xFFB45309),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                '1. I hereby authorize the above repair work to be done along with necessary material and agree that the workshop is not responsible for loss or damage to the vehicle or articles left in the vehicle in case of fire, theft, accidents, or any other cause beyond your control.\n'
                                '2. I authorize you and your employees to operate the vehicle herein described on streets, highways, or elsewhere for the purpose of testing and/or inspection.\n'
                                '3. An express mechanic\'s lien is hereby acknowledged on the above vehicle to secure the amount of repairs thereto. Storage charges apply if uncollected 48 hours after completion notice.',
                                style: TextStyle(fontSize: 9.5, color: Color(0xFF64748B), height: 1.35),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: const Column(
                            children: [
                              Icon(Icons.qr_code_2, size: 54, color: Color(0xFF0F172A)),
                              Text('Gate Pass QR', style: TextStyle(fontSize: 9, color: Color(0xFF64748B))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Signatures Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(width: 210, height: 1, color: const Color(0xFFCBD5E1)),
                          const SizedBox(height: 6),
                          const Text('Customer Signature (Check-In Authorization)', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(width: 210, height: 1, color: const Color(0xFFCBD5E1)),
                          const SizedBox(height: 6),
                          Text('Service Advisor Signature (${d.technician})', style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(width: 180, height: 1, color: const Color(0xFFCBD5E1)),
                          const SizedBox(height: 6),
                          const Text('Vehicle Released & Received By', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),

        // Bottom Letterhead Footer Strip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${d.workshopName} — Official Vehicle Receiving Memo & Job Card Copy',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF0F172A)),
                  ),
                  const Text(
                    'Please present this Customer Copy when collecting your vehicle. Thank you for choosing us!',
                    style: TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                  ),
                ],
              ),
              const Text('Page 1 of 1', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: Color(0xFF64748B))),
            ],
          ),
        ),
      ],
    );
  }

  static _JobCardDocData _extractJobCardData({
    required Map<String, dynamic> workshopSettings,
    required Map<String, dynamic> job,
  }) {
    final workshopName = (workshopSettings['name']?.toString().trim().isNotEmpty ?? false)
        ? workshopSettings['name'].toString()
        : 'AutoKe Auto Workshop';
    final workshopAddress = (workshopSettings['address']?.toString().trim().isNotEmpty ?? false)
        ? workshopSettings['address'].toString()
        : 'Enterprise Road, Industrial Area, Nairobi, Kenya';
    final workshopPin = (workshopSettings['taxPin']?.toString().trim().isNotEmpty ?? false)
        ? workshopSettings['taxPin'].toString()
        : 'P051234567X';
    final monogram = workshopName.substring(0, workshopName.length >= 3 ? 3 : 1).toUpperCase();

    final customer = (job['customer'] as Map<String, dynamic>?) ?? {};
    final vehicle = (job['vehicle'] as Map<String, dynamic>?) ?? {};

    final jobNumber = job['jobNumber']?.toString() ??
        (job['id'] != null && job['id'].toString().length >= 6
            ? 'JC-${job['id'].toString().substring(0, 6).toUpperCase()}'
            : 'JC-01001');

    final status = job['status']?.toString() ?? 'IN_PROGRESS';
    final createdAtStr = _formatFullDate(job['createdAt'] ?? DateTime.now().toIso8601String());
    final dueDateStr = _formatFullDate(job['dueDate'] ?? DateTime.now().add(const Duration(days: 2)).toIso8601String());

    final customerName = customer['name']?.toString() ?? 'Valued Customer';
    final customerPhone = (customer['phone']?.toString().trim().isNotEmpty ?? false) ? customer['phone'].toString() : 'N/A';
    final customerEmail = (customer['email']?.toString().trim().isNotEmpty ?? false) ? customer['email'].toString() : '';
    final customerAddress = (customer['address']?.toString().trim().isNotEmpty ?? false) ? customer['address'].toString() : 'Nairobi, Kenya';

    final regNo = vehicle['registrationNo']?.toString() ?? 'N/A';
    final makeModel = '${vehicle['make'] ?? ''} ${vehicle['model'] ?? ''}'.trim();
    final odometer = job['odometer'] != null ? '${job['odometer']} km' : 'Recorded at intake';
    final fuelLevel = job['fuelLevel']?.toString() ?? '1/2';
    final technician = (job['technician']?.toString().trim().isNotEmpty ?? false) ? job['technician'].toString() : 'Workshop Team';
    final workRequested = (job['workRequested']?.toString().trim().isNotEmpty ?? false)
        ? job['workRequested'].toString()
        : 'General Service & Inspection';
    final notes = (job['notes']?.toString().trim().isNotEmpty ?? false) ? job['notes'].toString() : '';

    final walkAround = job['walkAroundData'];
    String bodyType = 'sedan';
    List<DamageMarker> parsedMarkers = [];
    if (walkAround is Map) {
      if (walkAround['bodyType'] != null) {
        bodyType = walkAround['bodyType'].toString();
      }
      if (walkAround['markers'] is List) {
        parsedMarkers = (walkAround['markers'] as List)
            .map((m) => DamageMarker.fromJson(Map<String, dynamic>.from(m as Map)))
            .toList();
      }
    } else if (walkAround is List) {
      parsedMarkers = walkAround
          .map((m) => DamageMarker.fromJson(Map<String, dynamic>.from(m as Map)))
          .toList();
    }

    final bodyTypeLabel = bodyType == 'suv'
        ? 'SUV / 4x4'
        : bodyType == 'pickup'
            ? 'Pick-up / Double Cab'
            : bodyType == 'lorry'
                ? 'Lorry / Truck'
                : bodyType == 'van'
                    ? 'Van / Matatu'
                    : 'Sedan / Saloon';

    final memo = (walkAround is Map && walkAround['memoDetails'] is Map)
        ? ReceivingMemoDetails.fromJson(Map<String, dynamic>.from(walkAround['memoDetails'] as Map))
        : ReceivingMemoDetails();

    final presentCount = memo.checklist.values.where((v) => v).length;

    return _JobCardDocData(
      workshopName: workshopName,
      workshopAddress: workshopAddress,
      workshopPin: workshopPin,
      monogram: monogram,
      jobNumber: jobNumber,
      status: status,
      createdAtStr: createdAtStr,
      dueDateStr: dueDateStr,
      customerName: customerName,
      customerPhone: customerPhone,
      customerEmail: customerEmail,
      customerAddress: customerAddress,
      regNo: regNo,
      makeModel: makeModel,
      odometer: odometer,
      fuelLevel: fuelLevel,
      technician: technician,
      workRequested: workRequested,
      notes: notes,
      bodyTypeLabel: bodyTypeLabel,
      markers: parsedMarkers,
      memo: memo,
      presentCount: presentCount,
    );
  }

  // ===========================================================================
  // MODULE 6: OFFICIAL A4 PAYMENT RECEIPT & VEHICLE RELEASE GATE PASS PDF
  // ===========================================================================
  static Future<Uint8List> generatePaymentReceiptPdf({
    required Map<String, dynamic> workshopSettings,
    required Map<String, dynamic> invoice,
  }) async {
    final pdf = pw.Document(
      title: 'Official Payment Receipt & Gate Pass',
      author: workshopSettings['name']?.toString() ?? 'AutoKe Auto Workshop',
    );
    final fontRegular = pw.Font.helvetica();
    final fontBold = pw.Font.helveticaBold();

    final est = (invoice['estimate'] as Map<String, dynamic>?) ?? {};
    final d = _extractDocData(
      workshopSettings: workshopSettings,
      estimate: est,
      invoice: invoice,
      isInvoice: true,
    );
    final history = (invoice['paymentHistory'] as List<dynamic>?) ?? [];
    final isCleared = d.balanceDue <= 0.01;

    const navyDark = PdfColor.fromInt(0xFF0F172A);
    const primaryBlue = PdfColor.fromInt(0xFF1D4ED8);
    const greenColor = PdfColor.fromInt(0xFF15803D);
    const greenBg = PdfColor.fromInt(0xFFDCFCE7);
    const amberColor = PdfColor.fromInt(0xFFB45309);
    const amberBg = PdfColor.fromInt(0xFFFEF3C7);
    const borderGrey = PdfColor.fromInt(0xFFE2E8F0);
    const lightBg = PdfColor.fromInt(0xFFF8FAFC);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // Header
              pw.Container(
                padding: const pw.EdgeInsets.all(20),
                decoration: pw.BoxDecoration(
                  color: navyDark,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          d.workshopName.toUpperCase(),
                          style: pw.TextStyle(font: fontBold, color: PdfColors.white, fontSize: 16),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          '${d.workshopAddress}  |  Tax PIN: ${d.workshopPin}',
                          style: pw.TextStyle(font: fontRegular, color: const PdfColor.fromInt(0xFFCBD5E1), fontSize: 9),
                        ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'OFFICIAL PAYMENT RECEIPT',
                          style: pw.TextStyle(font: fontBold, color: PdfColors.white, fontSize: 14),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'Receipt Ref: RCT-${d.docNumber.replaceAll("INV-", "")}  •  Job: ${d.jobNumber}',
                          style: pw.TextStyle(font: fontBold, color: const PdfColor.fromInt(0xFF93C5FD), fontSize: 9.5),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 18),
              // Customer & Vehicle Box
              pw.Container(
                padding: const pw.EdgeInsets.all(14),
                decoration: pw.BoxDecoration(
                  color: lightBg,
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(color: borderGrey),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('RECEIVED FROM CUSTOMER', style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: primaryBlue)),
                        pw.SizedBox(height: 4),
                        pw.Text(d.customerName, style: pw.TextStyle(font: fontBold, fontSize: 12, color: navyDark)),
                        pw.Text('Phone: ${d.customerPhone}', style: pw.TextStyle(font: fontRegular, fontSize: 9.5)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('VEHICLE & SERVICE DETAILS', style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: primaryBlue)),
                        pw.SizedBox(height: 4),
                        pw.Text('${d.regNo} — ${d.makeModel}', style: pw.TextStyle(font: fontBold, fontSize: 11, color: navyDark)),
                        pw.Text('Service: ${d.serviceRequested}', style: pw.TextStyle(font: fontRegular, fontSize: 9.5)),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 18),
              // Payment Ledger Table
              pw.Text('PAYMENT & DEPOSIT TRANSACTION LEDGER', style: pw.TextStyle(font: fontBold, fontSize: 10, color: navyDark)),
              pw.SizedBox(height: 6),
              pw.Table(
                border: pw.TableBorder.all(color: borderGrey),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: navyDark),
                    children: [
                      _tableHeaderCell(fontBold, 'DATE'),
                      _tableHeaderCell(fontBold, 'PAYMENT MODE'),
                      _tableHeaderCell(fontBold, 'M-PESA / TXN REF'),
                      _tableHeaderCell(fontBold, 'NOTES'),
                      _tableHeaderCell(fontBold, 'AMOUNT PAID (KSH)', alignRight: true),
                    ],
                  ),
                  if (history.isEmpty)
                    pw.TableRow(
                      children: [
                        _tableBodyCell(fontRegular, d.createdAtStr),
                        _tableBodyCell(fontBold, d.paymentMode),
                        _tableBodyCell(fontBold, d.mpesaReceiptNo.isEmpty ? '-' : d.mpesaReceiptNo),
                        _tableBodyCell(fontRegular, d.paymentStatus),
                        _tableBodyCell(fontBold, _formatCurrency(d.amountPaid), alignRight: true),
                      ],
                    )
                  else
                    ...history.map((h) {
                      final amt = (h['amount'] as num?)?.toDouble() ?? 0.0;
                      return pw.TableRow(
                        children: [
                          _tableBodyCell(fontRegular, _formatFullDate(h['date'])),
                          _tableBodyCell(fontBold, (h['mode'] ?? d.paymentMode).toString()),
                          _tableBodyCell(fontBold, (h['reference'] ?? d.mpesaReceiptNo ?? '-').toString()),
                          _tableBodyCell(fontRegular, (h['notes'] ?? 'Payment').toString()),
                          _tableBodyCell(fontBold, _formatCurrency(amt), alignRight: true),
                        ],
                      );
                    }),
                ],
              ),
              pw.SizedBox(height: 18),
              // Financial Summary Box
              pw.Container(
                padding: const pw.EdgeInsets.all(14),
                decoration: pw.BoxDecoration(
                  color: lightBg,
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(color: borderGrey),
                ),
                child: pw.Column(
                  children: [
                    _summaryLine(fontRegular, fontBold, 'Total Invoice Amount (Incl. VAT)', 'KSH ${_formatCurrency(d.grandTotal)}'),
                    pw.SizedBox(height: 6),
                    _summaryLine(fontRegular, fontBold, 'Total Amount Received / Paid to Date', 'KSH ${_formatCurrency(d.amountPaid)}', valueColor: greenColor),
                    pw.SizedBox(height: 6),
                    _summaryLine(
                      fontBold,
                      fontBold,
                      'Remaining Balance Due',
                      'KSH ${_formatCurrency(d.balanceDue)}',
                      valueColor: isCleared ? greenColor : amberColor,
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 22),
              // Gate Pass Authorization Box
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: isCleared ? greenBg : amberBg,
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: isCleared ? greenColor : amberColor, width: 1.5),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          isCleared
                              ? 'SECURITY GATE PASS: CLEARED FOR VEHICLE RELEASE'
                              : 'PARTIAL DEPOSIT RECEIPT — VEHICLE RELEASE SUBJECT TO MANAGER APPROVAL',
                          style: pw.TextStyle(font: fontBold, fontSize: 11, color: isCleared ? greenColor : amberColor),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'Vehicle Reg: ${d.regNo}  •  Job Card: ${d.jobNumber}  •  Customer: ${d.customerName}',
                          style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: navyDark),
                        ),
                      ],
                    ),
                    pw.Text(
                      isCleared ? 'CLEARED' : 'BALANCE DUE',
                      style: pw.TextStyle(font: fontBold, fontSize: 13, color: isCleared ? greenColor : amberColor),
                    ),
                  ],
                ),
              ),
              pw.Spacer(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(width: 170, height: 1, color: borderGrey),
                      pw.SizedBox(height: 4),
                      pw.Text('Cashier / Accounts Signature', style: pw.TextStyle(font: fontRegular, fontSize: 9)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(width: 170, height: 1, color: borderGrey),
                      pw.SizedBox(height: 4),
                      pw.Text('Security Gate Officer Stamp & Time Out', style: pw.TextStyle(font: fontRegular, fontSize: 9)),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  static Future<void> showPaymentReceiptPreviewModal({
    required BuildContext context,
    required Map<String, dynamic> workshopSettings,
    required Map<String, dynamic> invoice,
  }) async {
    final est = (invoice['estimate'] as Map<String, dynamic>?) ?? {};
    final d = _extractDocData(
      workshopSettings: workshopSettings,
      estimate: est,
      invoice: invoice,
      isInvoice: true,
    );
    final history = (invoice['paymentHistory'] as List<dynamic>?) ?? [];
    final isCleared = d.balanceDue <= 0.01;
    final fileName = 'Receipt_${d.docNumber.replaceAll("INV-", "RCT-")}';

    await showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: const Color(0xFF0F172A),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: SizedBox(
            width: 820,
            height: MediaQuery.of(ctx).size.height * 0.9,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E293B),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.verified_outlined, color: Colors.greenAccent),
                          const SizedBox(width: 10),
                          Text(
                            'Official Payment Receipt & Gate Pass (${d.regNo})',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: () async {
                              final bytes = await generatePaymentReceiptPdf(
                                workshopSettings: workshopSettings,
                                invoice: invoice,
                              );
                              await printPdfBytesImpl(bytes, fileName);
                            },
                            icon: const Icon(Icons.print, size: 16),
                            label: const Text('Print Receipt & Gate Pass'),
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final bytes = await generatePaymentReceiptPdf(
                                workshopSettings: workshopSettings,
                                invoice: invoice,
                              );
                              await saveAndDownloadPdfImpl(bytes, '$fileName.pdf');
                            },
                            icon: const Icon(Icons.download, size: 16, color: Colors.white),
                            label: const Text('Download PDF', style: TextStyle(color: Colors.white)),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close, color: Colors.white70),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(28),
                    child: Container(
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(d.workshopName.toUpperCase(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                                  Text('${d.workshopAddress} • PIN: ${d.workshopPin}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text('OFFICIAL PAYMENT RECEIPT', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1D4ED8))),
                                  Text('Job Card: ${d.jobNumber} • Vehicle: ${d.regNo}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                ],
                              ),
                            ],
                          ),
                          const Divider(height: 28),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Customer: ${d.customerName} (${d.customerPhone})', style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text('Vehicle: ${d.regNo} (${d.makeModel})', style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Text('Payment & Deposit History Ledger:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 8),
                          if (history.isEmpty)
                            ListTile(
                              dense: true,
                              tileColor: Colors.grey.shade50,
                              title: Text('${d.paymentMode} ${d.mpesaReceiptNo.isNotEmpty ? "• Ref: ${d.mpesaReceiptNo}" : ""}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('Date: ${d.createdAtStr}'),
                              trailing: Text('KSH ${_formatCurrency(d.amountPaid)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                            )
                          else
                            ...history.map((h) {
                              final amt = (h['amount'] as num?)?.toDouble() ?? 0.0;
                              return ListTile(
                                dense: true,
                                tileColor: Colors.grey.shade50,
                                title: Text('${h['mode'] ?? d.paymentMode} • Ref: ${h['reference'] ?? d.mpesaReceiptNo ?? '-'}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('${_formatFullDate(h['date'])} — ${h['notes'] ?? ''}'),
                                trailing: Text('KSH ${_formatCurrency(amt)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                              );
                            }),
                          const Divider(height: 28),
                          _previewSummaryLine('Total Invoice Amount (Incl. 16% VAT)', 'KSH ${_formatCurrency(d.grandTotal)}'),
                          const SizedBox(height: 6),
                          _previewSummaryLine('Total Amount Paid / Received', 'KSH ${_formatCurrency(d.amountPaid)}', valueColor: Colors.green.shade800),
                          const SizedBox(height: 6),
                          _previewSummaryLine('Remaining Balance Due', 'KSH ${_formatCurrency(d.balanceDue)}', valueColor: isCleared ? Colors.green.shade800 : Colors.red.shade800),
                          const SizedBox(height: 24),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isCleared ? Colors.green.shade50 : Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: isCleared ? Colors.green : Colors.amber.shade800),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isCleared ? 'SECURITY GATE PASS: CLEARED FOR EXIT ✓' : 'PARTIAL DEPOSIT RECEIPT (BALANCE DUE)',
                                      style: TextStyle(fontWeight: FontWeight.bold, color: isCleared ? Colors.green.shade900 : Colors.amber.shade900),
                                    ),
                                    Text('Vehicle ${d.regNo} (${d.makeModel}) — Job ${d.jobNumber}', style: const TextStyle(fontSize: 12)),
                                  ],
                                ),
                                Icon(isCleared ? Icons.verified : Icons.schedule, color: isCleared ? Colors.green : Colors.amber.shade900, size: 28),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _JobCardDocData {
  final String workshopName;
  final String workshopAddress;
  final String workshopPin;
  final String monogram;
  final String jobNumber;
  final String status;
  final String createdAtStr;
  final String dueDateStr;
  final String customerName;
  final String customerPhone;
  final String customerEmail;
  final String customerAddress;
  final String regNo;
  final String makeModel;
  final String odometer;
  final String fuelLevel;
  final String technician;
  final String workRequested;
  final String notes;
  final String bodyTypeLabel;
  final List<DamageMarker> markers;
  final ReceivingMemoDetails memo;
  final int presentCount;

  _JobCardDocData({
    required this.workshopName,
    required this.workshopAddress,
    required this.workshopPin,
    required this.monogram,
    required this.jobNumber,
    required this.status,
    required this.createdAtStr,
    required this.dueDateStr,
    required this.customerName,
    required this.customerPhone,
    required this.customerEmail,
    required this.customerAddress,
    required this.regNo,
    required this.makeModel,
    required this.odometer,
    required this.fuelLevel,
    required this.technician,
    required this.workRequested,
    required this.notes,
    required this.bodyTypeLabel,
    required this.markers,
    required this.memo,
    required this.presentCount,
  });
}

class _DocData {
  final String workshopName;
  final String workshopAddress;
  final String workshopPin;
  final String monogram;
  final String docNumber;
  final String jobNumber;
  final String createdAtStr;
  final String dueDateStr;
  final String customerName;
  final String customerPhone;
  final String customerEmail;
  final String customerAddress;
  final String regNo;
  final String makeModel;
  final String odometer;
  final String fuelLevel;
  final String technician;
  final String serviceRequested;
  final List<dynamic> lineItems;
  final double subtotal;
  final double discountRate;
  final double discountAmount;
  final double taxableSubtotal;
  final double taxRate;
  final double taxAmount;
  final double grandTotal;
  final String paymentStatus;
  final String paymentMode;
  final double amountPaid;
  final double balanceDue;
  final String mpesaReceiptNo;

  _DocData({
    required this.workshopName,
    required this.workshopAddress,
    required this.workshopPin,
    required this.monogram,
    required this.docNumber,
    required this.jobNumber,
    required this.createdAtStr,
    required this.dueDateStr,
    required this.customerName,
    required this.customerPhone,
    required this.customerEmail,
    required this.customerAddress,
    required this.regNo,
    required this.makeModel,
    required this.odometer,
    required this.fuelLevel,
    required this.technician,
    required this.serviceRequested,
    required this.lineItems,
    required this.subtotal,
    required this.discountRate,
    required this.discountAmount,
    required this.taxableSubtotal,
    required this.taxRate,
    required this.taxAmount,
    required this.grandTotal,
    required this.paymentStatus,
    required this.paymentMode,
    this.amountPaid = 0.0,
    this.balanceDue = 0.0,
    this.mpesaReceiptNo = '',
  });
}
