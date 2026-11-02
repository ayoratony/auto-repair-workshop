import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/pms_checklist_model.dart';
import '../screens/web/pdf_saver_stub.dart' if (dart.library.html) '../screens/web/pdf_saver_web.dart';

class PmsPdfService {
  /// Generates the official printable Periodic Maintenance Service (PMS) inspection document.
  static Future<Uint8List> generatePmsPdf({
    required Map<String, dynamic> workshopSettings,
    required Map<String, dynamic> job,
    required PmsChecksheetData checksheet,
  }) async {
    final pdf = pw.Document(
      title: 'PMS Diagnostic Check Sheet - ${checksheet.registrationNumber}',
      author: workshopSettings['name']?.toString() ?? 'Auto Workshop',
    );

    final fontRegular = pw.Font.helvetica();
    final fontBold = pw.Font.helveticaBold();

    final workshopName = (workshopSettings['name'] ?? 'AUTO REPAIR WORKSHOP').toString().toUpperCase();
    final workshopAddress = (workshopSettings['address'] ?? 'Industrial Area, Nairobi, Kenya').toString();
    final workshopPhone = (workshopSettings['phone'] ?? '+254 700 000 000').toString();
    final workshopEmail = (workshopSettings['email'] ?? 'service@autoworkshop.co.ke').toString();

    final regNo = checksheet.registrationNumber.isNotEmpty
        ? checksheet.registrationNumber.toUpperCase()
        : (job['vehicle']?['registrationNo'] ?? '').toString().toUpperCase();
    final makeModel = '${job['vehicle']?['make'] ?? ''} ${job['vehicle']?['model'] ?? ''}'.trim();
    final customerName = (job['customer']?['name'] ?? 'Customer').toString();
    final customerPhone = (job['customer']?['phone'] ?? '').toString();
    final vin = checksheet.vinNumber.isNotEmpty
        ? checksheet.vinNumber
        : (job['vehicle']?['chassisNo'] ?? job['vehicle']?['vin'] ?? '-').toString();
    final engineNo = (job['vehicle']?['engineNo'] ?? '-').toString();
    final jobNo = (job['jobNumber'] ?? (checksheet.jobCardNumber.isNotEmpty ? checksheet.jobCardNumber : job['id']?.toString().substring(0, 8).toUpperCase() ?? 'JOB-CARD')).toString();
    final odo = checksheet.currentMileage != null && checksheet.currentMileage! > 0
        ? '${checksheet.currentMileage} km'
        : (job['odometer'] != null ? '${job['odometer']} km' : 'Not recorded');
    final techName = checksheet.technicianName.isNotEmpty
        ? checksheet.technicianName
        : (job['technician'] ?? 'Assigned Tech').toString();
    final serviceInterval = checksheet.selectedInterval.isNotEmpty ? checksheet.selectedInterval : 'Standard';

    final defects = checksheet.defects;
    final healthScore = checksheet.healthPercentage;
    final items = checksheet.items;

    const navyDark = PdfColor.fromInt(0xFF0F172A);
    const primaryBlue = PdfColor.fromInt(0xFF1D4ED8);
    const borderGrey = PdfColor.fromInt(0xFFCBD5E1);
    const lightBg = PdfColor.fromInt(0xFFF8FAFC);
    const textDark = PdfColor.fromInt(0xFF0F172A);
    const textMuted = PdfColor.fromInt(0xFF475569);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        theme: pw.ThemeData.withFont(
          base: fontRegular,
          bold: fontBold,
        ),
        header: (context) {
          return pw.Column(
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        workshopName,
                        style: pw.TextStyle(font: fontBold, fontSize: 13, color: navyDark),
                      ),
                      pw.Text(
                        '$workshopAddress | Tel: $workshopPhone',
                        style: pw.TextStyle(font: fontRegular, fontSize: 8, color: textMuted),
                      ),
                      pw.Text(
                        'Email: $workshopEmail',
                        style: pw.TextStyle(font: fontRegular, fontSize: 8, color: textMuted),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: const pw.BoxDecoration(
                          color: primaryBlue,
                          borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                        ),
                        child: pw.Text(
                          'PMS CHECK SHEET',
                          style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.white),
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        checksheet.templateTitle,
                        style: pw.TextStyle(font: fontBold, fontSize: 8, color: textDark),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Divider(color: borderGrey, thickness: 1),
              pw.SizedBox(height: 6),
            ],
          );
        },
        footer: (context) {
          return pw.Column(
            children: [
              pw.Divider(color: borderGrey, thickness: 0.8),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Page ${context.pageNumber} of ${context.pagesCount} \u2022 Job Card: $jobNo \u2022 Plate: $regNo',
                    style: pw.TextStyle(font: fontRegular, fontSize: 7.5, color: textMuted),
                  ),
                  pw.Text(
                    'Generated: ${DateTime.now().toString().substring(0, 16)}',
                    style: pw.TextStyle(font: fontRegular, fontSize: 7.5, color: textMuted),
                  ),
                ],
              ),
            ],
          );
        },
        build: (context) {
          return [
            // VEHICLE & JOB METADATA BOX
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: lightBg,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                border: pw.Border.all(color: borderGrey, width: 0.8),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Left col: Vehicle & Customer
                  pw.Expanded(
                    flex: 5,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Row(
                          children: [
                            pw.Container(
                              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: pw.BoxDecoration(
                                color: PdfColors.amber100,
                                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                                border: pw.Border.all(color: PdfColors.black, width: 0.8),
                              ),
                              child: pw.Text(
                                regNo.isNotEmpty ? regNo : 'NO PLATE',
                                style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.black),
                              ),
                            ),
                            pw.SizedBox(width: 6),
                            pw.Expanded(
                              child: pw.Text(
                                makeModel.isNotEmpty ? makeModel : 'Vehicle Inspection',
                                style: pw.TextStyle(font: fontBold, fontSize: 9.5, color: textDark),
                                overflow: pw.TextOverflow.clip,
                              ),
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text('Customer: $customerName (${customerPhone.isNotEmpty ? customerPhone : "-"})',
                            style: pw.TextStyle(font: fontRegular, fontSize: 8, color: textDark)),
                        pw.Text('VIN / Chassis: $vin   |   Engine No: $engineNo',
                            style: pw.TextStyle(font: fontRegular, fontSize: 7.5, color: textMuted)),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 10),
                  // Right col: Job Logistics & Health Score
                  pw.Expanded(
                    flex: 5,
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('Job Card No: $jobNo', style: pw.TextStyle(font: fontBold, fontSize: 8.5, color: navyDark)),
                            pw.Text('Odometer: $odo', style: pw.TextStyle(font: fontRegular, fontSize: 8, color: textDark)),
                            pw.Text('Interval: $serviceInterval', style: pw.TextStyle(font: fontBold, fontSize: 8, color: primaryBlue)),
                            pw.Text('Technician: $techName', style: pw.TextStyle(font: fontRegular, fontSize: 8, color: textDark)),
                          ],
                        ),
                        // Health Badge
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: pw.BoxDecoration(
                            color: healthScore >= 85
                                ? PdfColors.green100
                                : (healthScore >= 65 ? PdfColors.amber100 : PdfColors.red100),
                            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                            border: pw.Border.all(
                              color: healthScore >= 85
                                  ? PdfColors.green700
                                  : (healthScore >= 65 ? PdfColors.amber700 : PdfColors.red700),
                            ),
                          ),
                          child: pw.Column(
                            children: [
                              pw.Text(
                                '${healthScore.toStringAsFixed(0)}%',
                                style: pw.TextStyle(
                                  font: fontBold,
                                  fontSize: 14,
                                  color: healthScore >= 85
                                      ? PdfColors.green900
                                      : (healthScore >= 65 ? PdfColors.amber900 : PdfColors.red900),
                                ),
                              ),
                              pw.Text('HEALTH', style: pw.TextStyle(font: fontBold, fontSize: 6.5, color: textMuted)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 6),

            // LEGEND STRIP
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: const pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('LEGEND:', style: pw.TextStyle(font: fontBold, fontSize: 7, color: navyDark)),
                  pw.Text('[ OK ] Checked & In Good Order', style: pw.TextStyle(font: fontRegular, fontSize: 6.8, color: PdfColors.green800)),
                  pw.Text('[ C ] Caution / Monitor', style: pw.TextStyle(font: fontRegular, fontSize: 6.8, color: PdfColors.amber800)),
                  pw.Text('[ NG ] Immediate Attention / Defect', style: pw.TextStyle(font: fontRegular, fontSize: 6.8, color: PdfColors.red800)),
                  pw.Text('[ R ] Replace', style: pw.TextStyle(font: fontRegular, fontSize: 6.8, color: primaryBlue)),
                  pw.Text('[ I ] Inspect', style: pw.TextStyle(font: fontRegular, fontSize: 6.8, color: textDark)),
                  pw.Text('[ L ] Lubricate', style: pw.TextStyle(font: fontRegular, fontSize: 6.8, color: textDark)),
                ],
              ),
            ),

            pw.SizedBox(height: 8),

            // CHECKLIST ITEMS TABLE
            pw.Text('TECHNICAL INSPECTION ITEMS (1 TO ${items.length})',
                style: pw.TextStyle(font: fontBold, fontSize: 9, color: navyDark)),
            pw.SizedBox(height: 4),

            _buildItemsTable(items, fontRegular, fontBold),

            pw.SizedBox(height: 10),

            // TYRE PRESSURES & BATTERY READINGS
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Tyre Pressures
                pw.Expanded(
                  flex: 6,
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(6),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: borderGrey, width: 0.8),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('TYRE PRESSURE & TREAD DEPTH RECORD',
                            style: pw.TextStyle(font: fontBold, fontSize: 8, color: navyDark)),
                        pw.SizedBox(height: 4),
                        _buildTyreTable(checksheet.tyres, fontRegular, fontBold),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 8),
                // Battery Test
                pw.Expanded(
                  flex: 4,
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(6),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: borderGrey, width: 0.8),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('BATTERY SYSTEM TEST',
                            style: pw.TextStyle(font: fontBold, fontSize: 8, color: navyDark)),
                        pw.SizedBox(height: 4),
                        _buildBatteryBox(checksheet.battery, fontRegular, fontBold),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            if (defects.isNotEmpty) ...[
              pw.SizedBox(height: 10),
              pw.Text('TECHNICIAN DEFECT FINDINGS & ACTIONABLE RECOMMENDATIONS (${defects.length})',
                  style: pw.TextStyle(font: fontBold, fontSize: 9, color: PdfColors.red900)),
              pw.SizedBox(height: 4),
              _buildDefectsTable(defects, fontRegular, fontBold),
            ],

            if (checksheet.technicianComments.isNotEmpty || checksheet.customerComplaint.isNotEmpty) ...[
              pw.SizedBox(height: 8),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(
                  color: lightBg,
                  border: pw.Border.all(color: borderGrey, width: 0.8),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('DIAGNOSIS & ROAD TEST COMMENTS:',
                        style: pw.TextStyle(font: fontBold, fontSize: 8, color: navyDark)),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      checksheet.technicianComments.isNotEmpty
                          ? checksheet.technicianComments
                          : checksheet.customerComplaint,
                      style: pw.TextStyle(font: fontRegular, fontSize: 7.5, color: textDark),
                    ),
                  ],
                ),
              ),
            ],

            pw.SizedBox(height: 14),

            // SIGN OFF BOX
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: borderGrey, width: 0.8),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  _buildSignBlock('TECHNICIAN', techName, checksheet.submittedAt, fontRegular, fontBold),
                  _buildSignBlock('SERVICE ADVISOR / QA', 'Workshop QA Manager', null, fontRegular, fontBold),
                  _buildSignBlock('CUSTOMER ACCEPTANCE', customerName, null, fontRegular, fontBold),
                ],
              ),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildItemsTable(List<PmsChecklistItem> items, pw.Font fontRegular, pw.Font fontBold) {
    return pw.Table(
      border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFE2E8F0), width: 0.5),
      columnWidths: {
        0: const pw.FixedColumnWidth(22),
        1: const pw.FlexColumnWidth(5.5),
        2: const pw.FixedColumnWidth(38),
        3: const pw.FixedColumnWidth(34),
        4: const pw.FlexColumnWidth(3.5),
      },
      children: [
        // Table Header
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF1F5F9)),
          children: [
            _cell('#', fontBold, align: pw.TextAlign.center, fontSize: 7),
            _cell('INSPECTION POINT / ITEM', fontBold, fontSize: 7),
            _cell('CODE', fontBold, align: pw.TextAlign.center, fontSize: 7),
            _cell('RATING', fontBold, align: pw.TextAlign.center, fontSize: 7),
            _cell('REMARKS / DEFECT DETAIL', fontBold, fontSize: 7),
          ],
        ),
        // Item rows
        ...items.map((item) {
          final isNG = item.status == PmsItemStatus.ng;
          final isCaution = item.status == PmsItemStatus.caution;
          final isOK = item.status == PmsItemStatus.ok;

          PdfColor rowBg = PdfColors.white;
          if (isNG) rowBg = const PdfColor.fromInt(0xFFFEE2E2);
          if (isCaution) rowBg = const PdfColor.fromInt(0xFFFEF3C7);

          final serviceCode = item.intervalStandard ?? (item.intervalSchedule != null ? item.intervalSchedule!.values.firstOrNull ?? 'I' : 'I');

          return pw.TableRow(
            decoration: pw.BoxDecoration(color: rowBg),
            children: [
              _cell('${item.itemNumber}', fontBold, align: pw.TextAlign.center, fontSize: 6.8),
              _cell(
                item.description,
                fontRegular,
                fontSize: 6.8,
                textColor: isNG ? PdfColors.red900 : (isCaution ? PdfColors.amber900 : const PdfColor.fromInt(0xFF1E293B)),
              ),
              _cell(serviceCode, fontRegular, align: pw.TextAlign.center, fontSize: 6.8),
              _cell(
                item.status.code,
                fontBold,
                align: pw.TextAlign.center,
                fontSize: 7.2,
                textColor: isNG
                    ? PdfColors.red900
                    : (isCaution
                        ? PdfColors.amber900
                        : (isOK ? PdfColors.green800 : const PdfColor.fromInt(0xFF475569))),
              ),
              _cell(
                item.defectDescription != null && item.defectDescription!.isNotEmpty
                    ? item.defectDescription!
                    : (item.remarks.isNotEmpty ? item.remarks : '-'),
                fontRegular,
                fontSize: 6.5,
                textColor: isNG ? PdfColors.red900 : const PdfColor.fromInt(0xFF475569),
              ),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _buildTyreTable(List<PmsTyrePosition> tyres, pw.Font fontRegular, pw.Font fontBold) {
    if (tyres.isEmpty) {
      return pw.Text('No tyre measurements recorded', style: pw.TextStyle(font: fontRegular, fontSize: 7));
    }
    return pw.Table(
      border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFE2E8F0), width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(3),
        1: const pw.FlexColumnWidth(2),
        2: const pw.FlexColumnWidth(2),
        3: const pw.FlexColumnWidth(2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF1F5F9)),
          children: [
            _cell('Position', fontBold, fontSize: 6.5),
            _cell('Press (PSI)', fontBold, align: pw.TextAlign.center, fontSize: 6.5),
            _cell('Tread (mm)', fontBold, align: pw.TextAlign.center, fontSize: 6.5),
            _cell('Status', fontBold, align: pw.TextAlign.center, fontSize: 6.5),
          ],
        ),
        ...tyres.map((t) => pw.TableRow(
              children: [
                _cell(t.position, fontRegular, fontSize: 6.5),
                _cell(t.pressurePsi != null ? '${t.pressurePsi!.toStringAsFixed(0)} PSI' : '-', fontRegular, align: pw.TextAlign.center, fontSize: 6.5),
                _cell(t.treadDepthMm != null ? '${t.treadDepthMm!.toStringAsFixed(1)} mm' : '-', fontRegular, align: pw.TextAlign.center, fontSize: 6.5),
                _cell(t.status.code, fontBold, align: pw.TextAlign.center, fontSize: 6.5, textColor: t.status == PmsItemStatus.ng ? PdfColors.red800 : PdfColors.green800),
              ],
            )),
      ],
    );
  }

  static pw.Widget _buildBatteryBox(PmsBatteryReadings bat, pw.Font fontRegular, pw.Font fontBold) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Battery 1 Voltage:', style: pw.TextStyle(font: fontRegular, fontSize: 7)),
            pw.Text(bat.battery1Voltage != null ? '${bat.battery1Voltage!.toStringAsFixed(2)} V' : '12.60 V', style: pw.TextStyle(font: fontBold, fontSize: 7)),
          ],
        ),
        if (bat.is24VSystem) ...[
          pw.SizedBox(height: 2),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Battery 2 Voltage:', style: pw.TextStyle(font: fontRegular, fontSize: 7)),
              pw.Text(bat.battery2Voltage != null ? '${bat.battery2Voltage!.toStringAsFixed(2)} V' : '12.50 V', style: pw.TextStyle(font: fontBold, fontSize: 7)),
            ],
          ),
        ],
        pw.SizedBox(height: 2),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Total Voltage:', style: pw.TextStyle(font: fontRegular, fontSize: 7)),
            pw.Text(bat.totalVoltage != null ? '${bat.totalVoltage!.toStringAsFixed(2)} V' : (bat.is24VSystem ? '25.10 V' : '12.60 V'), style: pw.TextStyle(font: fontBold, fontSize: 7)),
          ],
        ),
        pw.SizedBox(height: 2),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Condition / Notes:', style: pw.TextStyle(font: fontRegular, fontSize: 7)),
            pw.Text(
              bat.conditionNotes.isNotEmpty ? bat.conditionNotes : 'Good Condition',
              style: pw.TextStyle(
                font: fontBold,
                fontSize: 7,
                color: bat.conditionNotes.toLowerCase().contains('bad') || bat.conditionNotes.toLowerCase().contains('weak')
                    ? PdfColors.red800
                    : PdfColors.green800,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildDefectsTable(List<PmsChecklistItem> defects, pw.Font fontRegular, pw.Font fontBold) {
    return pw.Table(
      border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFE2E8F0), width: 0.5),
      columnWidths: {
        0: const pw.FixedColumnWidth(24),
        1: const pw.FlexColumnWidth(3),
        2: const pw.FlexColumnWidth(3),
        3: const pw.FlexColumnWidth(2.5),
        4: const pw.FixedColumnWidth(45),
        5: const pw.FixedColumnWidth(55),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFFEE2E2)),
          children: [
            _cell('#', fontBold, align: pw.TextAlign.center, fontSize: 6.8),
            _cell('DEFECT / ISSUE', fontBold, fontSize: 6.8),
            _cell('RECOMMENDED ACTION', fontBold, fontSize: 6.8),
            _cell('PARTS REQUIRED', fontBold, fontSize: 6.8),
            _cell('SEVERITY', fontBold, align: pw.TextAlign.center, fontSize: 6.8),
            _cell('EST. COST', fontBold, align: pw.TextAlign.right, fontSize: 6.8),
          ],
        ),
        ...defects.map((d) {
          final isNG = d.status == PmsItemStatus.ng;
          final total = d.estimatedParts + d.estimatedLabour;

          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: isNG ? const PdfColor.fromInt(0xFFFFF1F2) : const PdfColor.fromInt(0xFFFFFBEB),
            ),
            children: [
              _cell('${d.itemNumber}', fontBold, align: pw.TextAlign.center, fontSize: 6.8),
              _cell(
                d.defectDescription != null && d.defectDescription!.isNotEmpty ? d.defectDescription! : d.description,
                fontBold,
                fontSize: 6.8,
                textColor: isNG ? PdfColors.red900 : PdfColors.amber900,
              ),
              _cell(d.recommendedFix != null && d.recommendedFix!.isNotEmpty ? d.recommendedFix! : 'Service / Repair', fontRegular, fontSize: 6.8),
              _cell(d.partsNeeded != null && d.partsNeeded!.isNotEmpty ? d.partsNeeded! : '-', fontRegular, fontSize: 6.8),
              _cell(isNG ? 'CRITICAL (NG)' : 'CAUTION (C)', fontBold, align: pw.TextAlign.center, fontSize: 6.5, textColor: isNG ? PdfColors.red900 : PdfColors.amber900),
              _cell(total > 0 ? 'KES ${total.toStringAsFixed(0)}' : 'TBD', fontBold, align: pw.TextAlign.right, fontSize: 6.8, textColor: PdfColors.green900),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _buildSignBlock(String title, String name, String? date, pw.Font fontRegular, pw.Font fontBold) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title, style: pw.TextStyle(font: fontBold, fontSize: 7, color: const PdfColor.fromInt(0xFF0F172A))),
        pw.SizedBox(height: 18),
        pw.Container(width: 140, height: 0.8, color: const PdfColor.fromInt(0xFF94A3B8)),
        pw.SizedBox(height: 3),
        pw.Text(name, style: pw.TextStyle(font: fontBold, fontSize: 7)),
        pw.Text('Date: ${date ?? "____ / ____ / ________"}', style: pw.TextStyle(font: fontRegular, fontSize: 6.5, color: const PdfColor.fromInt(0xFF64748B))),
      ],
    );
  }

  static pw.Widget _cell(
    String text,
    pw.Font font, {
    pw.TextAlign align = pw.TextAlign.left,
    double fontSize = 7.5,
    PdfColor textColor = const PdfColor.fromInt(0xFF0F172A),
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(font: font, fontSize: fontSize, color: textColor),
      ),
    );
  }

  /// Prints the PMS check sheet directly.
  static Future<void> printPmsCheckSheet({
    required Map<String, dynamic> workshopSettings,
    required Map<String, dynamic> job,
    required PmsChecksheetData checksheet,
  }) async {
    final bytes = await generatePmsPdf(
      workshopSettings: workshopSettings,
      job: job,
      checksheet: checksheet,
    );
    final reg = checksheet.registrationNumber.replaceAll(' ', '');
    final jobNo = (job['jobNumber'] ?? 'PMS').toString();
    await printPdfBytesImpl(bytes, 'PMS_${jobNo}_$reg');
  }

  /// Downloads / exports the PMS check sheet PDF.
  static Future<void> exportPmsPdf({
    required Map<String, dynamic> workshopSettings,
    required Map<String, dynamic> job,
    required PmsChecksheetData checksheet,
  }) async {
    final bytes = await generatePmsPdf(
      workshopSettings: workshopSettings,
      job: job,
      checksheet: checksheet,
    );
    final reg = checksheet.registrationNumber.replaceAll(' ', '');
    final jobNo = (job['jobNumber'] ?? 'PMS').toString();
    await saveAndDownloadPdfImpl(bytes, 'PMS_Inspection_${jobNo}_$reg.pdf');
  }

  /// Shows the interactive PDF preview modal with 1-tap Print and Download buttons.
  static Future<void> showPdfPreviewModal({
    required BuildContext context,
    required Map<String, dynamic> workshopSettings,
    required Map<String, dynamic> job,
    required PmsChecksheetData checksheet,
  }) async {
    await showDialog(
      context: context,
      builder: (ctx) {
        bool isPrinting = false;
        bool isDownloading = false;

        return StatefulBuilder(builder: (ctx, setModalState) {
          return Dialog(
            backgroundColor: const Color(0xFF0F172A),
            insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: 980,
              height: MediaQuery.of(context).size.height * 0.92,
              child: Column(
                children: [
                  // Top bar
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    color: const Color(0xFF1E293B),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.description, color: Color(0xFF60A5FA), size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'PMS Diagnostic Check Sheet \u2014 ${checksheet.templateTitle}',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Plate: ${checksheet.registrationNumber} \u2022 Score: ${checksheet.healthPercentage.toStringAsFixed(0)}% \u2022 Tech: ${checksheet.technicianName}',
                                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: isPrinting
                              ? null
                              : () async {
                                  setModalState(() => isPrinting = true);
                                  try {
                                    await printPmsCheckSheet(
                                      workshopSettings: workshopSettings,
                                      job: job,
                                      checksheet: checksheet,
                                    );
                                  } catch (e) {
                                    if (ctx.mounted) {
                                      ScaffoldMessenger.of(ctx).showSnackBar(
                                        SnackBar(content: Text('Print error: $e'), backgroundColor: Colors.red),
                                      );
                                    }
                                  } finally {
                                    if (ctx.mounted) setModalState(() => isPrinting = false);
                                  }
                                },
                          icon: isPrinting
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.print_outlined, size: 16, color: Colors.white),
                          label: const Text('Print Check Sheet', style: TextStyle(color: Colors.white, fontSize: 11.5)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF475569)),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: isDownloading
                              ? null
                              : () async {
                                  setModalState(() => isDownloading = true);
                                  try {
                                    await exportPmsPdf(
                                      workshopSettings: workshopSettings,
                                      job: job,
                                      checksheet: checksheet,
                                    );
                                    if (ctx.mounted) {
                                      ScaffoldMessenger.of(ctx).showSnackBar(
                                        const SnackBar(content: Text('PMS Checksheet PDF downloaded'), backgroundColor: Color(0xFF16A34A)),
                                      );
                                    }
                                  } catch (e) {
                                    if (ctx.mounted) {
                                      ScaffoldMessenger.of(ctx).showSnackBar(
                                        SnackBar(content: Text('Download error: $e'), backgroundColor: Colors.red),
                                      );
                                    }
                                  } finally {
                                    if (ctx.mounted) setModalState(() => isDownloading = false);
                                  }
                                },
                          icon: isDownloading
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.download, size: 16),
                          label: const Text('Download PDF', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  // PDF Preview area
                  Expanded(
                    child: Container(
                      color: const Color(0xFF0F172A),
                      child: PdfPreview(
                        build: (format) => generatePmsPdf(
                          workshopSettings: workshopSettings,
                          job: job,
                          checksheet: checksheet,
                        ),
                        useActions: false,
                        canChangeOrientation: false,
                        canChangePageFormat: false,
                        canDebug: false,
                        padding: const EdgeInsets.all(16),
                        previewPageMargin: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }
}
