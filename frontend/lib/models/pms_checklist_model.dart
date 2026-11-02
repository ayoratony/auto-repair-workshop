/// Status of an inspection item in the PMS check sheet
/// OK: Checked and Okay
/// C: Further Attention (Caution) - Amber
/// NG: Immediate Attention (No Good / Defect) - Red
/// R: Replace (for periodic maintenance items)
/// I: Inspect
/// L: Lubricate / Grease
enum PmsItemStatus {
  ok,
  caution, // C
  ng,      // NG
  replace, // R
  inspect, // I
  grease,  // L
  notApplicable,
}

extension PmsItemStatusExt on PmsItemStatus {
  String get code {
    switch (this) {
      case PmsItemStatus.ok:
        return 'OK';
      case PmsItemStatus.caution:
        return 'C';
      case PmsItemStatus.ng:
        return 'NG';
      case PmsItemStatus.replace:
        return 'R';
      case PmsItemStatus.inspect:
        return 'I';
      case PmsItemStatus.grease:
        return 'L';
      case PmsItemStatus.notApplicable:
        return 'N/A';
    }
  }

  String get label {
    switch (this) {
      case PmsItemStatus.ok:
        return 'Checked & OK (OK)';
      case PmsItemStatus.caution:
        return 'Caution / Further Attention (C)';
      case PmsItemStatus.ng:
        return 'Immediate Attention (NG)';
      case PmsItemStatus.replace:
        return 'Replace (R)';
      case PmsItemStatus.inspect:
        return 'Inspect (I)';
      case PmsItemStatus.grease:
        return 'Lubricate / Grease (L)';
      case PmsItemStatus.notApplicable:
        return 'Not Applicable';
    }
  }

  static PmsItemStatus fromString(String? val) {
    if (val == null) return PmsItemStatus.ok;
    final v = val.trim().toUpperCase();
    if (v == 'NG' || v == 'FAIL' || v == 'IMMEDIATE') return PmsItemStatus.ng;
    if (v == 'C' || v == 'CAUTION' || v == 'WARN' || v == 'ATTENTION') return PmsItemStatus.caution;
    if (v == 'R' || v == 'REPLACE') return PmsItemStatus.replace;
    if (v == 'I' || v == 'INSPECT') return PmsItemStatus.inspect;
    if (v == 'L' || v == 'GREASE' || v == 'LUBRICATE') return PmsItemStatus.grease;
    if (v == 'N/A' || v == 'NA') return PmsItemStatus.notApplicable;
    return PmsItemStatus.ok;
  }
}

/// Single item within a PMS Check Sheet
class PmsChecklistItem {
  final int itemNumber;
  final String category; // 'PMS Items', 'Body', 'Inside The Cabin', 'Under the Cabin / Bonnet', 'Under The Vehicle & Chassis', 'Tyre Wheel', 'Bus Body'
  final String description;
  final String? standardValue;
  final String? intervalStandard; // e.g. "R", "I", "L"
  final Map<String, String>? intervalSchedule; // e.g. {"1K": "R", "15K": "R", "30K": "R"}
  PmsItemStatus status;
  String remarks;
  String? defectDescription;
  String? recommendedFix;
  double estimatedParts;
  double estimatedLabour;
  String? partsNeeded;
  String? actualValue;

  PmsChecklistItem({
    required this.itemNumber,
    required this.category,
    required this.description,
    this.standardValue,
    this.intervalStandard,
    this.intervalSchedule,
    this.status = PmsItemStatus.ok,
    this.remarks = '',
    this.defectDescription,
    this.recommendedFix,
    this.estimatedParts = 0.0,
    this.estimatedLabour = 0.0,
    this.partsNeeded,
    this.actualValue,
  });

  bool get isDefect => status == PmsItemStatus.ng || status == PmsItemStatus.caution;
  bool get isImmediate => status == PmsItemStatus.ng;
  bool get isCaution => status == PmsItemStatus.caution;

  Map<String, dynamic> toJson() => {
        'itemNumber': itemNumber,
        'category': category,
        'description': description,
        'standardValue': standardValue,
        'intervalStandard': intervalStandard,
        'intervalSchedule': intervalSchedule,
        'status': status.code,
        'remarks': remarks,
        'defectDescription': defectDescription,
        'recommendedFix': recommendedFix,
        'estimatedParts': estimatedParts,
        'estimatedLabour': estimatedLabour,
        'partsNeeded': partsNeeded,
        'actualValue': actualValue,
      };

  factory PmsChecklistItem.fromJson(Map<String, dynamic> json) {
    return PmsChecklistItem(
      itemNumber: json['itemNumber'] is int ? json['itemNumber'] : int.tryParse(json['itemNumber']?.toString() ?? '0') ?? 0,
      category: json['category']?.toString() ?? 'General',
      description: json['description']?.toString() ?? '',
      standardValue: json['standardValue']?.toString(),
      intervalStandard: json['intervalStandard']?.toString(),
      intervalSchedule: json['intervalSchedule'] is Map
          ? Map<String, String>.from(
              (json['intervalSchedule'] as Map).map((k, v) => MapEntry(k.toString(), v.toString())))
          : null,
      status: PmsItemStatusExt.fromString(json['status']?.toString()),
      remarks: json['remarks']?.toString() ?? '',
      defectDescription: json['defectDescription']?.toString(),
      recommendedFix: json['recommendedFix']?.toString(),
      estimatedParts: (json['estimatedParts'] as num?)?.toDouble() ?? 0.0,
      estimatedLabour: (json['estimatedLabour'] as num?)?.toDouble() ?? 0.0,
      partsNeeded: json['partsNeeded']?.toString(),
      actualValue: json['actualValue']?.toString(),
    );
  }

  PmsChecklistItem copyWith({
    PmsItemStatus? status,
    String? remarks,
    String? defectDescription,
    String? recommendedFix,
    double? estimatedParts,
    double? estimatedLabour,
    String? partsNeeded,
    String? actualValue,
  }) {
    return PmsChecklistItem(
      itemNumber: itemNumber,
      category: category,
      description: description,
      standardValue: standardValue,
      intervalStandard: intervalStandard,
      intervalSchedule: intervalSchedule,
      status: status ?? this.status,
      remarks: remarks ?? this.remarks,
      defectDescription: defectDescription ?? this.defectDescription,
      recommendedFix: recommendedFix ?? this.recommendedFix,
      estimatedParts: estimatedParts ?? this.estimatedParts,
      estimatedLabour: estimatedLabour ?? this.estimatedLabour,
      partsNeeded: partsNeeded ?? this.partsNeeded,
      actualValue: actualValue ?? this.actualValue,
    );
  }
}

/// Single Tyre wheel measurement in table
class PmsTyrePosition {
  final String position; // 'Front Right', 'Front Left', 'Rear Right Inner', etc.
  double? pressurePsi;
  double? treadDepthMm;
  double pressureLimitPsi;
  double treadLimitMm;
  PmsItemStatus status;
  String remarks;

  PmsTyrePosition({
    required this.position,
    this.pressurePsi,
    this.treadDepthMm,
    this.pressureLimitPsi = 32.0,
    this.treadLimitMm = 2.0,
    this.status = PmsItemStatus.ok,
    this.remarks = '',
  });

  Map<String, dynamic> toJson() => {
        'position': position,
        'pressurePsi': pressurePsi,
        'treadDepthMm': treadDepthMm,
        'pressureLimitPsi': pressureLimitPsi,
        'treadLimitMm': treadLimitMm,
        'status': status.code,
        'remarks': remarks,
      };

  factory PmsTyrePosition.fromJson(Map<String, dynamic> json) {
    return PmsTyrePosition(
      position: json['position']?.toString() ?? '',
      pressurePsi: (json['pressurePsi'] as num?)?.toDouble(),
      treadDepthMm: (json['treadDepthMm'] as num?)?.toDouble(),
      pressureLimitPsi: (json['pressureLimitPsi'] as num?)?.toDouble() ?? 32.0,
      treadLimitMm: (json['treadLimitMm'] as num?)?.toDouble() ?? 2.0,
      status: PmsItemStatusExt.fromString(json['status']?.toString()),
      remarks: json['remarks']?.toString() ?? '',
    );
  }
}

/// Battery Voltage Measurements
class PmsBatteryReadings {
  double? battery1Voltage;
  double? battery2Voltage;
  double? totalVoltage;
  bool is24VSystem;
  String conditionNotes;

  PmsBatteryReadings({
    this.battery1Voltage,
    this.battery2Voltage,
    this.totalVoltage,
    this.is24VSystem = true,
    this.conditionNotes = '',
  });

  Map<String, dynamic> toJson() => {
        'battery1Voltage': battery1Voltage,
        'battery2Voltage': battery2Voltage,
        'totalVoltage': totalVoltage,
        'is24VSystem': is24VSystem,
        'conditionNotes': conditionNotes,
      };

  factory PmsBatteryReadings.fromJson(Map<String, dynamic> json) {
    return PmsBatteryReadings(
      battery1Voltage: (json['battery1Voltage'] as num?)?.toDouble(),
      battery2Voltage: (json['battery2Voltage'] as num?)?.toDouble(),
      totalVoltage: (json['totalVoltage'] as num?)?.toDouble(),
      is24VSystem: json['is24VSystem'] == true || json['is24VSystem'] == 'true',
      conditionNotes: json['conditionNotes']?.toString() ?? '',
    );
  }
}

/// Entire PMS Check Sheet state for a specific Job Card
class PmsChecksheetData {
  String templateCode; // 'nmr85_nqr81', 'nlr77', 'frr90_truck', etc.
  String templateTitle; // e.g. "PMS CHECK SHEET NMR85/NQR81/NPS81"
  String selectedInterval; // e.g. "1K", "15K", "30K", "45K"
  String status; // 'DRAFT', 'SUBMITTED_TO_ADVISOR', 'APPROVED_BY_CUSTOMER', 'COMPLETED'

  // Header / Vehicle Data
  String registrationNumber;
  String vinNumber;
  String jobCardNumber;
  int? currentMileage;
  int? lastServiceMileage;
  String? lastServiceDate;
  String? serviceTypeDone;
  String? lastDealerVisited;
  String fuelLevel;
  String inspectionDate;

  // Sections
  List<PmsChecklistItem> items;
  List<PmsTyrePosition> tyres;
  PmsBatteryReadings battery;

  // Diagnosis feedback
  String customerComplaint;
  String exteriorInspection;
  String technicianComments;
  String technicianName;
  String? technicianSignature;
  String? submittedAt;
  String? reviewedByAdvisor;
  String? reviewedAt;
  bool isLocked;

  PmsChecksheetData({
    required this.templateCode,
    required this.templateTitle,
    this.selectedInterval = '15K',
    this.status = 'DRAFT',
    this.isLocked = false,
    required this.registrationNumber,
    this.vinNumber = '',
    this.jobCardNumber = '',
    this.currentMileage,
    this.lastServiceMileage,
    this.lastServiceDate,
    this.serviceTypeDone,
    this.lastDealerVisited,
    this.fuelLevel = 'Half',
    required this.inspectionDate,
    required this.items,
    required this.tyres,
    required this.battery,
    this.customerComplaint = '',
    this.exteriorInspection = '',
    this.technicianComments = '',
    this.technicianName = '',
    this.technicianSignature,
    this.submittedAt,
    this.reviewedByAdvisor,
    this.reviewedAt,
  });

  int get okCount => items.where((i) => i.status == PmsItemStatus.ok || i.status == PmsItemStatus.replace || i.status == PmsItemStatus.grease).length;
  int get cautionCount => items.where((i) => i.status == PmsItemStatus.caution).length;
  int get ngCount => items.where((i) => i.status == PmsItemStatus.ng).length;
  int get totalInspected => items.where((i) => i.status != PmsItemStatus.notApplicable).length;

  double get healthPercentage {
    if (totalInspected == 0) return 100.0;
    final good = items.where((i) => i.status == PmsItemStatus.ok || i.status == PmsItemStatus.replace || i.status == PmsItemStatus.grease).length;
    return (good / totalInspected) * 100.0;
  }

  List<PmsChecklistItem> get defects => items.where((i) => i.isDefect).toList();
  List<PmsChecklistItem> get immediateDefects => items.where((i) => i.isImmediate).toList();
  List<PmsChecklistItem> get cautionDefects => items.where((i) => i.isCaution).toList();

  /// Converts all identified NG and Caution defects into structured recommendation records
  List<Map<String, dynamic>> generateRecommendations() {
    final List<Map<String, dynamic>> recs = [];
    for (final item in defects) {
      final isImmediate = item.status == PmsItemStatus.ng;
      final issueText = (item.defectDescription != null && item.defectDescription!.trim().isNotEmpty)
          ? item.defectDescription!.trim()
          : (item.remarks.trim().isNotEmpty ? item.remarks.trim() : '${item.description} failed inspection (${item.status.code})');

      final fixText = (item.recommendedFix != null && item.recommendedFix!.trim().isNotEmpty)
          ? item.recommendedFix!.trim()
          : (isImmediate ? 'Urgent repair / component replacement required immediately.' : 'Further attention & servicing advised.');

      recs.add({
        'id': 'rec_pms_${item.itemNumber}_${DateTime.now().millisecondsSinceEpoch}',
        'pmsItemNumber': item.itemNumber,
        'system': item.category,
        'issue': issueText,
        'recommendation': fixText,
        'urgency': isImmediate ? 'CRITICAL' : 'RECOMMENDED',
        'estimatedLabour': item.estimatedLabour,
        'estimatedParts': item.estimatedParts,
        'totalEstimated': item.estimatedLabour + item.estimatedParts,
        'partsNeeded': item.partsNeeded ?? '',
        'technicianName': technicianName.isNotEmpty ? technicianName : 'Technician',
        'status': 'PENDING',
        'source': 'PMS_INSPECTION',
        'createdAt': DateTime.now().toISOString(),
      });
    }
    return recs;
  }

  Map<String, dynamic> toJson() => {
        'templateCode': templateCode,
        'templateTitle': templateTitle,
        'selectedInterval': selectedInterval,
        'status': status,
        'registrationNumber': registrationNumber,
        'vinNumber': vinNumber,
        'jobCardNumber': jobCardNumber,
        'currentMileage': currentMileage,
        'lastServiceMileage': lastServiceMileage,
        'lastServiceDate': lastServiceDate,
        'serviceTypeDone': serviceTypeDone,
        'lastDealerVisited': lastDealerVisited,
        'fuelLevel': fuelLevel,
        'inspectionDate': inspectionDate,
        'items': items.map((i) => i.toJson()).toList(),
        'tyres': tyres.map((t) => t.toJson()).toList(),
        'battery': battery.toJson(),
        'customerComplaint': customerComplaint,
        'exteriorInspection': exteriorInspection,
        'technicianComments': technicianComments,
        'technicianName': technicianName,
        'technicianSignature': technicianSignature,
        'submittedAt': submittedAt,
        'isLocked': isLocked,
        'reviewedByAdvisor': reviewedByAdvisor,
        'reviewedAt': reviewedAt,
        'summary': {
          'okCount': okCount,
          'cautionCount': cautionCount,
          'ngCount': ngCount,
          'healthPercentage': healthPercentage,
        },
      };

  factory PmsChecksheetData.fromJson(Map<String, dynamic> json) {
    return PmsChecksheetData(
      templateCode: json['templateCode']?.toString() ?? 'universal',
      templateTitle: json['templateTitle']?.toString() ?? 'PMS Check Sheet',
      selectedInterval: json['selectedInterval']?.toString() ?? '15K',
      status: json['status']?.toString() ?? 'DRAFT',
      registrationNumber: json['registrationNumber']?.toString() ?? '',
      vinNumber: json['vinNumber']?.toString() ?? '',
      jobCardNumber: json['jobCardNumber']?.toString() ?? '',
      currentMileage: json['currentMileage'] is int ? json['currentMileage'] : int.tryParse(json['currentMileage']?.toString() ?? ''),
      lastServiceMileage: json['lastServiceMileage'] is int ? json['lastServiceMileage'] : int.tryParse(json['lastServiceMileage']?.toString() ?? ''),
      lastServiceDate: json['lastServiceDate']?.toString(),
      serviceTypeDone: json['serviceTypeDone']?.toString(),
      lastDealerVisited: json['lastDealerVisited']?.toString(),
      fuelLevel: json['fuelLevel']?.toString() ?? 'Half',
      inspectionDate: json['inspectionDate']?.toString() ?? DateTime.now().toIso8601String(),
      items: json['items'] is List
          ? (json['items'] as List).whereType<Map>().map((i) => PmsChecklistItem.fromJson(Map<String, dynamic>.from(i))).toList()
          : <PmsChecklistItem>[],
      tyres: json['tyres'] is List
          ? (json['tyres'] as List).whereType<Map>().map((t) => PmsTyrePosition.fromJson(Map<String, dynamic>.from(t))).toList()
          : defaultTyrePositions(),
      battery: json['battery'] is Map
          ? PmsBatteryReadings.fromJson(Map<String, dynamic>.from(json['battery']))
          : PmsBatteryReadings(),
      customerComplaint: json['customerComplaint']?.toString() ?? '',
      exteriorInspection: json['exteriorInspection']?.toString() ?? '',
      technicianComments: json['technicianComments']?.toString() ?? '',
      technicianName: json['technicianName']?.toString() ?? '',
      technicianSignature: json['technicianSignature']?.toString(),
      submittedAt: json['submittedAt']?.toString(),
      isLocked: json['isLocked'] == true || json['status'] == 'SUBMITTED_TO_ADVISOR' || json['status'] == 'COMPLETED',
      reviewedByAdvisor: json['reviewedByAdvisor']?.toString(),
      reviewedAt: json['reviewedAt']?.toString(),
    );
  }

  static List<PmsTyrePosition> defaultTyrePositions({bool isDualRear = true}) {
    return [
      PmsTyrePosition(position: 'Front Right', pressureLimitPsi: 35.0, treadLimitMm: 3.0),
      PmsTyrePosition(position: 'Front Left', pressureLimitPsi: 35.0, treadLimitMm: 3.0),
      if (isDualRear) ...[
        PmsTyrePosition(position: 'Rear Right Inner', pressureLimitPsi: 40.0, treadLimitMm: 3.0),
        PmsTyrePosition(position: 'Rear Right Outer', pressureLimitPsi: 40.0, treadLimitMm: 3.0),
        PmsTyrePosition(position: 'Rear Left Inner', pressureLimitPsi: 40.0, treadLimitMm: 3.0),
        PmsTyrePosition(position: 'Rear Left Outer', pressureLimitPsi: 40.0, treadLimitMm: 3.0),
      ] else ...[
        PmsTyrePosition(position: 'Rear Right', pressureLimitPsi: 35.0, treadLimitMm: 3.0),
        PmsTyrePosition(position: 'Rear Left', pressureLimitPsi: 35.0, treadLimitMm: 3.0),
      ],
      PmsTyrePosition(position: 'Spare Wheel', pressureLimitPsi: 35.0, treadLimitMm: 3.0),
    ];
  }
}

extension DateTimeIso on DateTime {
  String toISOString() => toIso8601String();
}

/// Catalog of Templates based on User Specification
class PmsTemplateDefinition {
  final String code;
  final String title;
  final String description;
  final List<String> intervals;
  final bool isBus;
  final bool isDualRear;
  final bool is24V;
  final String? item14CustomTitle; // HBB fluid, Air drier, Pollen filter, etc.
  final List<PmsChecklistItem> Function() buildItems;

  const PmsTemplateDefinition({
    required this.code,
    required this.title,
    required this.description,
    required this.intervals,
    this.isBus = false,
    this.isDualRear = true,
    this.is24V = true,
    this.item14CustomTitle,
    required this.buildItems,
  });
}
