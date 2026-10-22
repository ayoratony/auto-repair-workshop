import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/main.dart';
import 'package:frontend/screens/web/invoice_pdf_service.dart';

void main() {
  testWidgets('AutoRepairApp smoke test & A4 PDF generation test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const AutoRepairApp());
    expect(find.byType(AutoRepairApp), findsOneWidget);

    final pdfBytes = await InvoicePdfService.generateDocumentPdf(
      workshopSettings: {
        'name': 'MechanicHQ Auto Workshop',
        'address': 'Industrial Area, Nairobi',
        'taxPin': 'P051234567X',
      },
      estimate: {
        'id': '8ae57a00-1111-2222-3333-444444444444',
        'subtotal': 15000.0,
        'discountRate': 20.0,
        'taxRate': 16.0,
        'total': 13920.0,
        'status': 'APPROVED',
        'lineItems': [
          {'description': 'Ceramic Brake Pads', 'quantity': 2, 'unitPrice': 5000.0, 'total': 10000.0},
          {'description': 'Brake Disc Skimming & Labor', 'quantity': 1, 'unitPrice': 5000.0, 'total': 5000.0},
        ],
        'jobCard': {
          'jobNumber': 'JC01001',
          'workRequested': 'Brake Overhaul',
          'technician': 'Mark T.',
          'odometer': 84500,
          'fuelLevel': 'Half',
          'customer': {'name': 'Sarah Chen', 'phone': '+254 712 345 678'},
          'vehicle': {'registrationNo': 'KDA 450X', 'make': 'Honda', 'model': 'CR-V'},
        },
      },
      invoice: {
        'id': '8ae57a00-1111-2222-3333-444444444444',
        'paymentStatus': 'PAID',
        'paymentMode': 'MPESA',
      },
      isInvoice: true,
    );

    expect(pdfBytes.isNotEmpty, isTrue);
    expect(String.fromCharCodes(pdfBytes.sublist(0, 4)), equals('%PDF'));

    final jobCardPdfBytes = await InvoicePdfService.generateJobCardPdf(
      workshopSettings: {
        'name': 'MechanicHQ Auto Workshop',
        'address': 'Industrial Area, Nairobi',
        'taxPin': 'P051234567X',
      },
      job: {
        'jobNumber': 'JC01001',
        'status': 'IN_PROGRESS',
        'workRequested': 'Periodic Maintenance & Brake Check',
        'technician': 'Mark T.',
        'odometer': 84500,
        'fuelLevel': 'Half',
        'customer': {'name': 'Sarah Chen', 'phone': '+254 712 345 678'},
        'vehicle': {'registrationNo': 'KDA 450X', 'make': 'Toyota', 'model': 'Hilux'},
        'walkAroundData': {
          'bodyType': 'pickup',
          'markers': [
            {'nx': 0.3, 'ny': 0.4, 'type': 'scratch', 'viewAngle': 'front'},
            {'nx': 0.6, 'ny': 0.5, 'type': 'dent', 'viewAngle': 'left'},
          ],
          'memoDetails': {
            'checklist': {
              'Tool Kit': true,
              'Jack & Handle': true,
              'Spare Wheel': true,
              'First Aid Kit': true,
            },
            'selectedCategories': ['Periodic Maintenance', 'General Repair'],
            'visitType': 'Scheduled',
            'keepReplacedParts': true,
            'valuablesRemoved': true,
            'termsAccepted': true,
            'paymentMode': 'MPESA',
            'workshopSection': 'LC (Light Commercial / Passenger)',
            'vinNumber': 'JTEBU25J905012345',
            'avgKmPerDay': '65',
            'approxCostEstimate': '18,500',
            'remarks': 'Laptop bag removed by customer.',
          },
        },
      },
    );

    expect(jobCardPdfBytes.isNotEmpty, isTrue);
    expect(String.fromCharCodes(jobCardPdfBytes.sublist(0, 4)), equals('%PDF'));
  });
}
