import 'pms_checklist_model.dart';

class PmsTemplates {
  /// Catalog of all 16 predefined PMS Check Sheets from the workshop specification
  static final List<PmsTemplateDefinition> definitions = [
    // 1. NMR85/NQR81/NPS81 Truck
    PmsTemplateDefinition(
      code: 'nmr85_nqr81_truck',
      title: 'PMS CHECK SHEET - NMR85 / NQR81 / NPS81 (Truck)',
      description: 'Light & Medium duty truck with HBB booster option and dual 24V batteries.',
      intervals: ['1K', '15K', '30K', '45K'],
      isBus: false,
      isDualRear: true,
      is24V: true,
      item14CustomTitle: 'Hydraulic Brake Booster Fluid (HBB) for NQR81M',
      buildItems: () => _buildItems(
        item14: 'Hydraulic Brake Booster Fluid (HBB) for NQR81M',
        intervalSchedule14: {'1K': 'I', '15K': 'I', '30K': 'I', '45K': 'R'},
        isBus: false,
        isHeavyAirBrake: false,
      ),
    ),

    // 2. NLR77 Truck
    PmsTemplateDefinition(
      code: 'nlr77_truck',
      title: 'PMS CHECK SHEET - NLR77 (Truck)',
      description: 'N-Series Light Truck (10K service intervals).',
      intervals: ['1K', '10K', '20K', '30K', '40K'],
      isBus: false,
      isDualRear: true,
      is24V: true,
      item14CustomTitle: 'Brake Fluid',
      buildItems: () => _buildItems(
        item14: 'Brake Fluid',
        intervalSchedule14: {'1K': 'I', '10K': 'I', '20K': 'I', '30K': 'I', '40K': 'R'},
        isBus: false,
        isHeavyAirBrake: false,
      ),
    ),

    // 3. NKR66/NPR66/NQR66 Truck
    PmsTemplateDefinition(
      code: 'nkr_npr_nqr_truck',
      title: 'PMS CHECK SHEET - NKR66 / NPR66 / NQR66 (Truck)',
      description: 'Medium Commercial Trucks (7.5K service intervals).',
      intervals: ['1K', '7.5K', '15K', '22.5K', '30K'],
      isBus: false,
      isDualRear: true,
      is24V: true,
      item14CustomTitle: 'Brake Fluid',
      buildItems: () => _buildItems(
        item14: 'Brake Fluid',
        intervalSchedule14: {'1K': 'I', '7.5K': 'I', '15K': 'I', '22.5K': 'I', '30K': 'I'},
        isBus: false,
        isHeavyAirBrake: true,
      ),
    ),

    // 4. FRR90 Truck
    PmsTemplateDefinition(
      code: 'frr90_truck',
      title: 'PMS CHECK SHEET - FRR90 TRUCK',
      description: 'Medium / Heavy commercial truck with Air Drier and dual batteries.',
      intervals: ['1K', '15K', '30K', '45K'],
      isBus: false,
      isDualRear: true,
      is24V: true,
      item14CustomTitle: 'Air Drier (Replace at 90,000Kms _ Comprehensive Service)',
      buildItems: () => _buildItems(
        item14: 'Air Drier (Replace at 90,000Kms _ Comprehensive Service)',
        intervalSchedule14: {'1K': 'I', '15K': 'I', '30K': 'I', '45K': 'I'},
        isBus: false,
        isHeavyAirBrake: true,
        hasClutchBooster: true,
      ),
    ),

    // 5. FVZ34/FVR90/FTR90/FTS34
    PmsTemplateDefinition(
      code: 'fvz_fvr_ftr_truck',
      title: 'PMS CHECK SHEET - FVZ34 / FVR90 / FTR90 / FTS34',
      description: 'Heavy Commercial multi-axle truck with cabin lock and air tanks.',
      intervals: ['1K', '10K', '20K', '30K', '40K'],
      isBus: false,
      isDualRear: true,
      is24V: true,
      item14CustomTitle: 'Air Drier (Replace at 80,000Kms _ Comprehensive Service)',
      buildItems: () => _buildItems(
        item14: 'Air Drier (Replace at 80,000Kms _ Comprehensive Service)',
        intervalSchedule14: {'1K': 'I', '10K': 'I', '20K': 'I', '30K': 'I', '40K': 'I'},
        isBus: false,
        isHeavyAirBrake: true,
        hasCabinLock: true,
      ),
    ),

    // 6. FVZ23/FVX23/FVR23/FTS33/FSR33/FRR33
    PmsTemplateDefinition(
      code: 'fvz23_fvr23_truck',
      title: 'PMS CHECK SHEET - FVZ23 / FVX23 / FVR23 / FSR33 / FRR33',
      description: 'F-Series Heavy Duty Truck (7.5K service intervals).',
      intervals: ['1K', '7.5K', '15K', '22.5K', '30K'],
      isBus: false,
      isDualRear: true,
      is24V: true,
      item14CustomTitle: 'Brake Fluid (if applicable)',
      buildItems: () => _buildItems(
        item14: 'Brake Fluid (if applicable)',
        intervalSchedule14: {'1K': 'I', '7.5K': 'I', '15K': 'I', '22.5K': 'I', '30K': 'I'},
        isBus: false,
        isHeavyAirBrake: true,
      ),
    ),

    // 7. GXZ60N Prime Mover
    PmsTemplateDefinition(
      code: 'gxz60n_prime_mover',
      title: 'PMS CHECK SHEET - GXZ60N (Prime Mover)',
      description: 'Heavy Tractor / Prime Mover with 5th Wheel coupling inspection.',
      intervals: ['1K', '20K', '40K', '60K', '80K'],
      isBus: false,
      isDualRear: true,
      is24V: true,
      item14CustomTitle: 'Air Drier (Replace at 80,000Kms _ Comprehensive Service)',
      buildItems: () => _buildItems(
        item14: 'Air Drier (Replace at 80,000Kms _ Comprehensive Service)',
        intervalSchedule14: {'1K': 'I', '20K': 'I', '40K': 'I', '60K': 'I', '80K': 'I'},
        isBus: false,
        isHeavyAirBrake: true,
        hasFifthWheel: true,
      ),
    ),

    // 8. TFR54/TFS54/TFS85 D-Max (Old Model)
    PmsTemplateDefinition(
      code: 'dmax_old_model',
      title: 'PMS CHECK SHEET - TFR54 / TFS54 / TFS85 (D-Max Old Model)',
      description: 'Light Commercial Pickup / Double Cabin (5K intervals, single 12V battery).',
      intervals: ['1K', '5K', '10K', '15K', '20K'],
      isBus: false,
      isDualRear: false,
      is24V: false,
      item14CustomTitle: 'Brake Fluid & Clutch Fluid (if applicable)',
      buildItems: () => _buildItems(
        item14: 'Brake Fluid & Clutch Fluid (if applicable)',
        intervalSchedule14: {'1K': 'I', '5K': 'I', '10K': 'I', '15K': 'I', '20K': 'R'},
        isBus: false,
        isHeavyAirBrake: false,
        isPickup: true,
      ),
    ),

    // 9. TFS40/TFS87/TFR87/TFS86 D-Max (Current Model)
    PmsTemplateDefinition(
      code: 'dmax_current_model',
      title: 'PMS CHECK SHEET - TFS40 / TFS87 / TFR87 / TFS86 (D-Max)',
      description: 'Modern D-Max Pickup / Double Cabin with Pollen Filter (10K intervals).',
      intervals: ['1K', '10K', '20K', '30K'],
      isBus: false,
      isDualRear: false,
      is24V: false,
      item14CustomTitle: 'Brake Fluid & Clutch Fluid (if applicable)',
      buildItems: () => _buildItems(
        item14: 'Brake Fluid & Clutch Fluid (if applicable)',
        intervalSchedule14: {'1K': 'I', '10K': 'I', '20K': 'I', '30K': 'R'},
        isBus: false,
        isHeavyAirBrake: false,
        isPickup: true,
        hasPollenFilter: true,
      ),
    ),

    // 10. UCS85/UCS86/UCS87/UCS40 mu-X SUV
    PmsTemplateDefinition(
      code: 'mux_suv',
      title: 'PMS CHECK SHEET - UCS85 / UCS86 / UCS87 / UCS40 (mu-X SUV)',
      description: 'mu-X Passenger SUV with ADAS Stereo Camera & 3rd Row seat inspection.',
      intervals: ['1K', '10K', '20K', '30K'],
      isBus: false,
      isDualRear: false,
      is24V: false,
      item14CustomTitle: 'Brake Fluid',
      buildItems: () => _buildItems(
        item14: 'Brake Fluid',
        intervalSchedule14: {'1K': 'I', '10K': 'I', '20K': 'I', '30K': 'R'},
        isBus: false,
        isHeavyAirBrake: false,
        isSuv: true,
        hasPollenFilter: true,
      ),
    ),

    // 11. MV123 Bus
    PmsTemplateDefinition(
      code: 'mv123_bus',
      title: 'PMS CHECK SHEET - MV123 Bus',
      description: 'Passenger Commercial Bus with 70-point check including interior bells & passenger racks.',
      intervals: ['1K', '10K', '20K', '30K'],
      isBus: true,
      isDualRear: true,
      is24V: true,
      item14CustomTitle: 'Brake Fluid (if applicable)',
      buildItems: () => _buildItems(
        item14: 'Brake Fluid (if applicable)',
        intervalSchedule14: {'1K': 'I', '10K': 'I', '20K': 'I', '30K': 'I'},
        isBus: true,
        isHeavyAirBrake: true,
      ),
    ),

    // 12. FVR34 Bus
    PmsTemplateDefinition(
      code: 'fvr34_bus',
      title: 'PMS CHECK SHEET - FVR34 BUS',
      description: 'Heavy Commercial Bus with Tag Axle (6X2) and Passenger AC checks.',
      intervals: ['1K', '15K', '30K', '45K'],
      isBus: true,
      isDualRear: true,
      is24V: true,
      item14CustomTitle: 'Air Drier (Replace at 90,000Kms _ Comprehensive Service)',
      buildItems: () => _buildItems(
        item14: 'Air Drier (Replace at 90,000Kms _ Comprehensive Service)',
        intervalSchedule14: {'1K': 'I', '15K': 'I', '30K': 'I', '45K': 'I'},
        isBus: true,
        isHeavyAirBrake: true,
        hasTagAxle: true,
      ),
    ),

    // 13. FRR90/FSR90/FTR90 Bus
    PmsTemplateDefinition(
      code: 'frr90_bus',
      title: 'PMS CHECK SHEET - FRR90 / FSR90 / FTR90 BUS',
      description: 'Medium / Heavy Passenger Bus with passenger safety belts and AC checks.',
      intervals: ['1K', '15K', '30K', '45K'],
      isBus: true,
      isDualRear: true,
      is24V: true,
      item14CustomTitle: 'Air Drier (Replace at 90,000Kms _ Comprehensive Service)',
      buildItems: () => _buildItems(
        item14: 'Air Drier (Replace at 90,000Kms _ Comprehensive Service)',
        intervalSchedule14: {'1K': 'I', '15K': 'I', '30K': 'I', '45K': 'I'},
        isBus: true,
        isHeavyAirBrake: true,
      ),
    ),

    // 14. NKR66/NPR66/NQR66 Bus
    PmsTemplateDefinition(
      code: 'nkr_bus',
      title: 'PMS CHECK SHEET - NKR66 / NPR66 / NQR66 Bus',
      description: 'Commercial Passenger Bus (7.5K service intervals).',
      intervals: ['1K', '7.5K', '15K', '22.5K', '30K'],
      isBus: true,
      isDualRear: true,
      is24V: true,
      item14CustomTitle: 'Brake Fluid',
      buildItems: () => _buildItems(
        item14: 'Brake Fluid',
        intervalSchedule14: {'1K': 'I', '7.5K': 'I', '15K': 'I', '22.5K': 'I', '30K': 'I'},
        isBus: true,
        isHeavyAirBrake: true,
      ),
    ),

    // 15. NMR85/NQR81 Bus
    PmsTemplateDefinition(
      code: 'nmr85_bus',
      title: 'PMS CHECK SHEET - NMR85 / NQR81 BUS',
      description: 'N-Series Passenger Bus (15K intervals with HBB fluid and bell operation).',
      intervals: ['1K', '15K', '30K', '45K'],
      isBus: true,
      isDualRear: true,
      is24V: true,
      item14CustomTitle: 'Hydraulic Brake Booster Fluid (HBB) for NQR81M',
      buildItems: () => _buildItems(
        item14: 'Hydraulic Brake Booster Fluid (HBB) for NQR81M',
        intervalSchedule14: {'1K': 'I', '15K': 'I', '30K': 'I', '45K': 'R'},
        isBus: true,
        isHeavyAirBrake: false,
      ),
    ),

    // 16. Universal / General Passenger & Commercial Check Sheet
    PmsTemplateDefinition(
      code: 'universal_pms',
      title: 'PMS CHECK SHEET - Universal Multi-Point Inspection',
      description: 'Comprehensive 64-point diagnostic inspection applicable to ANY vehicle make or model.',
      intervals: ['5K', '10K', '20K', '30K', '40K', '50K'],
      isBus: false,
      isDualRear: false,
      is24V: false,
      item14CustomTitle: 'Brake & Clutch Fluid Inspection',
      buildItems: () => _buildItems(
        item14: 'Brake & Clutch Fluid Inspection',
        intervalSchedule14: {'5K': 'I', '10K': 'I', '20K': 'I', '30K': 'I', '40K': 'R', '50K': 'I'},
        isBus: false,
        isHeavyAirBrake: false,
        isPickup: false,
      ),
    ),
  ];

  static PmsTemplateDefinition getByCode(String? code) {
    if (code == null || code.isEmpty) return definitions.first;
    return definitions.firstWhere(
      (d) => d.code.toLowerCase() == code.toLowerCase(),
      orElse: () => definitions.first,
    );
  }

  /// Automatically matches the best template based on vehicle model string or category
  static PmsTemplateDefinition autoDetect(String? make, String? model, String? category) {
    final m = '${make ?? ''} ${model ?? ''} ${category ?? ''}'.toLowerCase();
    if (m.contains('bus') || m.contains('mv123')) {
      if (m.contains('fvr34')) return getByCode('fvr34_bus');
      if (m.contains('frr') || m.contains('fsr') || m.contains('ftr')) return getByCode('frr90_bus');
      if (m.contains('nkr') || m.contains('npr') || m.contains('nqr66')) return getByCode('nkr_bus');
      if (m.contains('nmr85') || m.contains('nqr81')) return getByCode('nmr85_bus');
      return getByCode('mv123_bus');
    }
    if (m.contains('d-max') || m.contains('dmax') || m.contains('tfr') || m.contains('tfs')) {
      if (m.contains('54') || m.contains('old')) return getByCode('dmax_old_model');
      return getByCode('dmax_current_model');
    }
    if (m.contains('mu-x') || m.contains('mux') || m.contains('ucs')) {
      return getByCode('mux_suv');
    }
    if (m.contains('gxz')) {
      return getByCode('gxz60n_prime_mover');
    }
    if (m.contains('fvz') || m.contains('fvr') || m.contains('ftr') || m.contains('fts')) {
      return getByCode('fvz_fvr_ftr_truck');
    }
    if (m.contains('frr90')) {
      return getByCode('frr90_truck');
    }
    if (m.contains('nlr77')) {
      return getByCode('nlr77_truck');
    }
    if (m.contains('nmr85') || m.contains('nqr81') || m.contains('nps81')) {
      return getByCode('nmr85_nqr81_truck');
    }
    if (m.contains('nkr') || m.contains('npr') || m.contains('nqr')) {
      return getByCode('nkr_npr_nqr_truck');
    }
    if (m.contains('truck') || m.contains('commercial')) {
      return getByCode('nmr85_nqr81_truck');
    }
    return getByCode('universal_pms');
  }

  /// Builds the complete standard item list with model-specific adjustments
  static List<PmsChecklistItem> _buildItems({
    required String item14,
    required Map<String, String> intervalSchedule14,
    bool isBus = false,
    bool isHeavyAirBrake = false,
    bool hasClutchBooster = false,
    bool hasCabinLock = false,
    bool hasFifthWheel = false,
    bool isPickup = false,
    bool isSuv = false,
    bool hasPollenFilter = false,
    bool hasTagAxle = false,
  }) {
    final List<PmsChecklistItem> items = [
      // -------------------------------------------------------------
      // Section 1: Periodic Maintenance Items (1-14)
      // -------------------------------------------------------------
      PmsChecklistItem(
        itemNumber: 1,
        category: 'Periodic Maintenance Items',
        description: 'Engine Oil & Drain Plug Gasket',
        standardValue: 'Replace',
        intervalStandard: 'R',
      ),
      PmsChecklistItem(
        itemNumber: 2,
        category: 'Periodic Maintenance Items',
        description: 'Engine Oil Filter',
        standardValue: 'Replace',
        intervalStandard: 'R',
      ),
      PmsChecklistItem(
        itemNumber: 3,
        category: 'Periodic Maintenance Items',
        description: 'Main Fuel Filter',
        standardValue: 'Inspect / Replace',
        intervalStandard: 'I/R',
      ),
      PmsChecklistItem(
        itemNumber: 4,
        category: 'Periodic Maintenance Items',
        description: 'Water Separator (Pre-Fuel Filter / Sedimentor)',
        standardValue: 'Inspect & Drain / Replace',
        intervalStandard: 'I/R',
      ),
      PmsChecklistItem(
        itemNumber: 5,
        category: 'Periodic Maintenance Items',
        description: 'Air Cleaner Element (Inner & Outer)',
        standardValue: 'Inspect & Blow / Replace',
        intervalStandard: 'I/R',
      ),
      PmsChecklistItem(
        itemNumber: 6,
        category: 'Periodic Maintenance Items',
        description: hasFifthWheel ? 'Greasing King Pin & 5th Wheel' : 'Greasing Kingpin / Suspension Points',
        standardValue: 'Lubricate (Chassis Grease)',
        intervalStandard: 'L',
      ),
      PmsChecklistItem(
        itemNumber: 7,
        category: 'Periodic Maintenance Items',
        description: 'Greasing Propeller Shaft (Universal Joints, Center Bearing & Sliding Sleeves)',
        standardValue: 'Lubricate (Chassis Grease)',
        intervalStandard: 'L',
      ),
      PmsChecklistItem(
        itemNumber: 8,
        category: 'Periodic Maintenance Items',
        description: 'Greasing (Wheel Hub & Bearings)',
        standardValue: 'Inspect / Repack Grease',
        intervalStandard: 'I/L',
      ),
      PmsChecklistItem(
        itemNumber: 9,
        category: 'Periodic Maintenance Items',
        description: 'Oil & Oil FILLER Plug Gaskets (Transmission & Rear Differential)',
        standardValue: 'Inspect / Replace Gasket',
        intervalStandard: 'R/I',
      ),
      PmsChecklistItem(
        itemNumber: 10,
        category: 'Periodic Maintenance Items',
        description: isPickup || isSuv
            ? 'Automatic / Manual Transmission Fluid & DRAIN Plug Gaskets'
            : 'Oil & Oil DRAIN Plug Gaskets (Transmission & Rear Differential)',
        standardValue: 'Inspect / Replace Gasket',
        intervalStandard: 'R/I',
      ),
      PmsChecklistItem(
        itemNumber: 11,
        category: 'Periodic Maintenance Items',
        description: 'Engine Coolant (Replace at 120,000 km / 24 Months)',
        standardValue: 'Inspect Level & Freeze Point',
        intervalStandard: 'I',
      ),
      PmsChecklistItem(
        itemNumber: 12,
        category: 'Periodic Maintenance Items',
        description: hasPollenFilter
            ? 'Pollen Filter (AC Cabin Air Filter)'
            : 'Brake Fluid / Clutch Fluid Level & Moisture',
        standardValue: 'Inspect / Replace',
        intervalStandard: 'I/R',
      ),
      PmsChecklistItem(
        itemNumber: 13,
        category: 'Periodic Maintenance Items',
        description: 'Power Steering Fluid',
        standardValue: 'Inspect Level & Condition',
        intervalStandard: 'I/R',
      ),
      PmsChecklistItem(
        itemNumber: 14,
        category: 'Periodic Maintenance Items',
        description: item14,
        standardValue: 'Inspect / Replace per Interval',
        intervalStandard: 'I/R',
        intervalSchedule: intervalSchedule14,
      ),

      // -------------------------------------------------------------
      // Section 2: Body (15-21)
      // -------------------------------------------------------------
      PmsChecklistItem(
        itemNumber: 15,
        category: 'Body',
        description: 'Body panels for damage, dents, rust, or corrosion',
        standardValue: 'No major dents, scratches or rust',
      ),
      PmsChecklistItem(
        itemNumber: 16,
        category: 'Body',
        description: 'Verify all exterior mirrors are intact and correctly adjusted',
        standardValue: 'Secure mounting, clean glass',
      ),
      PmsChecklistItem(
        itemNumber: 17,
        category: 'Body',
        description: 'All lights illumination, flashing and damage (Headlights, Indicators, Hazards)',
        standardValue: 'Full illumination, no cracked lenses',
      ),
      PmsChecklistItem(
        itemNumber: 18,
        category: 'Body',
        description: 'Windshield for cracks, chips and contamination',
        standardValue: 'Clear visibility, no driver-line cracks',
      ),
      PmsChecklistItem(
        itemNumber: 19,
        category: 'Body',
        description: 'Brake light, Reverse & License plate light operation',
        standardValue: 'Instant activation upon engagement',
      ),
      PmsChecklistItem(
        itemNumber: 20,
        category: 'Body',
        description: 'Battery condition (terminals, cable, mounting, electrolyte level)',
        standardValue: 'Tight terminals, zero corrosion, secure clamp',
      ),
      PmsChecklistItem(
        itemNumber: 21,
        category: 'Body',
        description: 'Battery Voltage Test (Battery 1 >11.5V, Battery 2 >11.5V, Total >23V or >12.4V)',
        standardValue: '>11.5V each, >23.0V total (or >12.4V for 12V)',
      ),

      // -------------------------------------------------------------
      // Section 3: Inside The Cabin (22-37)
      // -------------------------------------------------------------
      PmsChecklistItem(
        itemNumber: 22,
        category: 'Inside The Cabin',
        description: 'Seats and seat belts operation (retraction & latching)',
        standardValue: 'Smooth locking & retraction',
      ),
      PmsChecklistItem(
        itemNumber: 23,
        category: 'Inside The Cabin',
        description: 'Horn operation',
        standardValue: 'Clear audible tone',
      ),
      PmsChecklistItem(
        itemNumber: 24,
        category: 'Inside The Cabin',
        description: 'Engine startability, idle speed & acceleration',
        standardValue: 'Instant start, smooth idle, crisp revs',
      ),
      PmsChecklistItem(
        itemNumber: 25,
        category: 'Inside The Cabin',
        description: 'Service sticker condition & visibility',
        standardValue: 'Updated next service mileage recorded',
      ),
      PmsChecklistItem(
        itemNumber: 26,
        category: 'Inside The Cabin',
        description: 'Dashboard (Radio & Clock reset, interior lighting, warning symbols)',
        standardValue: 'All interior lights & gauges operational',
      ),
      PmsChecklistItem(
        itemNumber: 27,
        category: 'Inside The Cabin',
        description: 'Combination switch operation (Wiper & washer spray, light switches)',
        standardValue: 'Effective spray, clean wiper sweep',
      ),
      PmsChecklistItem(
        itemNumber: 28,
        category: 'Inside The Cabin',
        description: 'Instrument cluster – speedometer, tachometer, temperature & fuel gauge',
        standardValue: 'Zero error lights, accurate needles',
      ),
      PmsChecklistItem(
        itemNumber: 29,
        category: 'Inside The Cabin',
        description: 'Window & door locks operations, door trim condition',
        standardValue: 'Smooth roll/power lift, solid latch',
      ),
      PmsChecklistItem(
        itemNumber: 30,
        category: 'Inside The Cabin',
        description: 'Roof lining, floor mats, glove box locking',
        standardValue: 'Clean, fastened, functional lock',
      ),
      PmsChecklistItem(
        itemNumber: 31,
        category: 'Inside The Cabin',
        description: 'AC Operation (blower speeds, vents, cooling and heating output)',
        standardValue: 'Cold air output, all vent dampers work',
      ),
      PmsChecklistItem(
        itemNumber: 32,
        category: 'Inside The Cabin',
        description: 'Gear control knob & shift lever condition / reverse camera operation',
        standardValue: 'Crisp gate engagement, camera display OK',
      ),
      PmsChecklistItem(
        itemNumber: 33,
        category: 'Inside The Cabin',
        description: 'Parking brake lever stroke (Notches / ratchet clicks)',
        standardValue: '5 - 8 notches to full lock',
      ),
      PmsChecklistItem(
        itemNumber: 34,
        category: 'Inside The Cabin',
        description: 'Power steering wheel free play',
        standardValue: '< 30 mm free play',
      ),
      PmsChecklistItem(
        itemNumber: 35,
        category: 'Inside The Cabin',
        description: 'Brake pedal free play & reserve travel',
        standardValue: 'Firm pedal, no sponge or sinking',
      ),
      PmsChecklistItem(
        itemNumber: 36,
        category: 'Inside The Cabin',
        description: isSuv
            ? 'Stereo Camera Condition (ADAS / Forward Collision Warning)'
            : 'Clutch pedal free play',
        standardValue: isSuv ? 'Clean windshield zone, zero faults' : '10 - 20 mm free play',
      ),
      PmsChecklistItem(
        itemNumber: 37,
        category: 'Inside The Cabin',
        description: isSuv
            ? 'Third row seats & tonneau cover condition'
            : 'Clutch pedal stroke & disengagement feel',
        standardValue: 'Full disengagement without drag',
      ),

      // -------------------------------------------------------------
      // Section 4: Under the Cabin / Bonnet (38-47)
      // -------------------------------------------------------------
      PmsChecklistItem(
        itemNumber: 38,
        category: 'Under the Cabin / Bonnet',
        description: 'Air intake ducts and hoses (damage, leakage, blockage, worn out)',
        standardValue: 'Airtight clamps, zero hose cracks',
      ),
      PmsChecklistItem(
        itemNumber: 39,
        category: 'Under the Cabin / Bonnet',
        description: hasClutchBooster
            ? 'Clutch booster (mini pack), leakages / damage / free play'
            : 'Clutch slave cylinder & master cylinder (condition, leakages)',
        standardValue: 'Dry seals, zero fluid seepage',
      ),
      PmsChecklistItem(
        itemNumber: 40,
        category: 'Under the Cabin / Bonnet',
        description: 'Engine mountings condition (rubber degradation & cracks)',
        standardValue: 'Intact rubber, no metal-to-metal collapse',
      ),
      PmsChecklistItem(
        itemNumber: 41,
        category: 'Under the Cabin / Bonnet',
        description: 'Radiator Core, upper/lower hoses, clips and leakages',
        standardValue: 'Zero green/pink crusting or wet leaks',
      ),
      PmsChecklistItem(
        itemNumber: 42,
        category: 'Under the Cabin / Bonnet',
        description: 'Intercooler & AC Condenser Core condition',
        standardValue: 'Straight fins, zero oil pooling or damage',
      ),
      PmsChecklistItem(
        itemNumber: 43,
        category: 'Under the Cabin / Bonnet',
        description: 'Power steering hose condition and leakages',
        standardValue: 'Dry crimps, no swelling or chaffing',
      ),
      PmsChecklistItem(
        itemNumber: 44,
        category: 'Under the Cabin / Bonnet',
        description: 'Engine oil leakages (Valve cover, oil pan, front/rear main seals)',
        standardValue: 'Completely dry engine exterior',
      ),
      PmsChecklistItem(
        itemNumber: 45,
        category: 'Under the Cabin / Bonnet',
        description: 'Fuel system leakages, supply/return hose and pipe condition',
        standardValue: 'Zero diesel/petrol smell or weep',
      ),
      PmsChecklistItem(
        itemNumber: 46,
        category: 'Under the Cabin / Bonnet',
        description: 'Fan belts / accessory belts condition (damage, wear, stretch, cracking)',
        standardValue: 'No ribs missing, no squeal',
      ),
      PmsChecklistItem(
        itemNumber: 47,
        category: 'Under the Cabin / Bonnet',
        description: 'Fan belts tension (Hz / deflection)',
        standardValue: 'Per PMS Manual (10-12 mm deflection)',
      ),

      // -------------------------------------------------------------
      // Section 5: Under The Vehicle & Chassis (48-59)
      // -------------------------------------------------------------
      PmsChecklistItem(
        itemNumber: 48,
        category: 'Under The Vehicle & Chassis',
        description: 'Exhaust pipe damage, leakage, hangers and flexi joint condition',
        standardValue: 'Gas-tight, solid rubber hangers',
      ),
      PmsChecklistItem(
        itemNumber: 49,
        category: 'Under The Vehicle & Chassis',
        description: 'Transmission, Transfer Case & Differential mountings condition',
        standardValue: 'Intact isolator blocks, tight bolts',
      ),
      PmsChecklistItem(
        itemNumber: 50,
        category: 'Under The Vehicle & Chassis',
        description: hasCabinLock
            ? 'Cabin locking mechanism (mounting, switch, safety hook)'
            : (isPickup || isSuv
                ? 'Sump guard & Skid plate (mounting & condition)'
                : 'Gear & clutch cable condition / shift linkages'),
        standardValue: 'Secure fastening, smooth pivot',
      ),
      PmsChecklistItem(
        itemNumber: 51,
        category: 'Under The Vehicle & Chassis',
        description: 'Body & chassis mountings condition (U-bolts, subframe bolts)',
        standardValue: 'Torqued tight, zero play',
      ),
      PmsChecklistItem(
        itemNumber: 52,
        category: 'Under The Vehicle & Chassis',
        description: 'Front suspension (shock absorbers, leaf springs/coils, bushes, ball joints)',
        standardValue: 'Dry shock body, intact rubber boots',
      ),
      PmsChecklistItem(
        itemNumber: 53,
        category: 'Under The Vehicle & Chassis',
        description: 'Rear suspension (shocks, leaf packs, shackles, stabilizer bushes)',
        standardValue: 'No broken leaves, centered alignment',
      ),
      PmsChecklistItem(
        itemNumber: 54,
        category: 'Under The Vehicle & Chassis',
        description: isHeavyAirBrake
            ? 'Air Pressure & Moisture from the air brake tanks (Drain valves)'
            : 'Fuel pipes & brake hardline hoses leakages and damages',
        standardValue: isHeavyAirBrake ? 'Drain moisture, rapid pressure build-up' : 'Zero corrosion or kinks',
      ),
      PmsChecklistItem(
        itemNumber: 55,
        category: 'Under The Vehicle & Chassis',
        description: 'Propeller shaft, universal joints, center support bearing & sliding sleeves',
        standardValue: 'Zero rotational or radial play in U-joint',
      ),
      PmsChecklistItem(
        itemNumber: 56,
        category: 'Under The Vehicle & Chassis',
        description: 'Brake shoe lining / disc pads, drum condition, fluid leakages',
        standardValue: '> 3mm lining thickness remaining',
      ),
      PmsChecklistItem(
        itemNumber: 57,
        category: 'Under The Vehicle & Chassis',
        description: 'Brake wheel hub and bearing condition (end play & noise)',
        standardValue: 'Smooth rotation, zero bearing rumble',
      ),
      PmsChecklistItem(
        itemNumber: 58,
        category: 'Under The Vehicle & Chassis',
        description: 'Parking brake system condition (drum, shoe, cable / air chambers)',
        standardValue: 'Holds vehicle firm on 20% gradient',
      ),
      PmsChecklistItem(
        itemNumber: 59,
        category: 'Under The Vehicle & Chassis',
        description: isPickup
            ? 'Cargo box inspection (locks, tailgate cables, leakage, bedliner)'
            : (isSuv
                ? 'Rear door locking mechanism (shock absorber struts & latch)'
                : 'Looseness in or damage to suspension mountings & shackle pins'),
        standardValue: 'Torqued to spec, solid bushings',
      ),

      // -------------------------------------------------------------
      // Section 6: Tyre Wheel (60-64)
      // -------------------------------------------------------------
      PmsChecklistItem(
        itemNumber: 60,
        category: 'Tyre Wheel',
        description: 'Inspect rims for damage, dents and structural cracks',
        standardValue: 'True round, zero bead damage',
      ),
      PmsChecklistItem(
        itemNumber: 61,
        category: 'Tyre Wheel',
        description: 'Inspect wheel nuts and stud bolts condition and torque',
        standardValue: 'Torqued to manufacturer spec, all studs present',
      ),
      PmsChecklistItem(
        itemNumber: 62,
        category: 'Tyre Wheel',
        description: 'Spare wheel condition (mounting bracket, winch & locking mechanism)',
        standardValue: 'Securely stowed, lock operable',
      ),
      PmsChecklistItem(
        itemNumber: 63,
        category: 'Tyre Wheel',
        description: 'Inspect tyres for trapped nails/stones, sidewall bulges and wear patterns',
        standardValue: 'Even tread wear, zero sidewall cords exposed',
      ),
      PmsChecklistItem(
        itemNumber: 64,
        category: 'Tyre Wheel',
        description: 'Tyre Pressure (PSI) & Tread Depth (mm) inspection on all wheels',
        standardValue: 'Pressure per placard, Tread > 2.0 mm',
      ),
    ];

    // If Bus model, add Bus Body section (items 65-70)
    if (isBus) {
      items.addAll([
        PmsChecklistItem(
          itemNumber: 65,
          category: 'Bus Body',
          description: 'Passenger interior saloon lights function & condition',
          standardValue: 'All fluorescent / LED tubes functional',
        ),
        PmsChecklistItem(
          itemNumber: 66,
          category: 'Bus Body',
          description: 'Passenger electric stop bell operation & buzzer',
          standardValue: 'Instant buzzer sound from all push switches',
        ),
        PmsChecklistItem(
          itemNumber: 67,
          category: 'Bus Body',
          description: 'Interior panels, parcel racks and handrail stanchions condition',
          standardValue: 'Firmly anchored, zero rattle or loose screws',
        ),
        PmsChecklistItem(
          itemNumber: 68,
          category: 'Bus Body',
          description: 'Body water leakages (windows, emergency roof hatches, windshield seals)',
          standardValue: 'Watertight rubber seals',
        ),
        PmsChecklistItem(
          itemNumber: 69,
          category: 'Bus Body',
          description: 'Passenger safety seatbelts condition and anchor points',
          standardValue: 'All passenger belts latch and unlatch properly',
        ),
        PmsChecklistItem(
          itemNumber: 70,
          category: 'Bus Body',
          description: hasTagAxle
              ? 'Tag Axle Operation (6X2 lifting / load distribution mechanism)'
              : 'Passenger Saloon AC functionality / Roof blower ventilation',
          standardValue: 'Normal temperature drop & ventilation',
        ),
      ]);
    }

    return items;
  }

  /// Instantiates a brand new PmsChecksheetData for a job card
  static PmsChecksheetData createNewChecksheet({
    required String templateCode,
    required String registrationNumber,
    String vinNumber = '',
    String jobCardNumber = '',
    int? currentMileage,
    int? lastServiceMileage,
    String? lastServiceDate,
    String? serviceTypeDone,
    String? lastDealerVisited,
    String fuelLevel = 'Half',
    String technicianName = '',
    String selectedInterval = '15K',
  }) {
    final def = getByCode(templateCode);
    final items = def.buildItems();
    final tyres = PmsChecksheetData.defaultTyrePositions(isDualRear: def.isDualRear);
    final battery = PmsBatteryReadings(is24VSystem: def.is24V);

    return PmsChecksheetData(
      templateCode: def.code,
      templateTitle: def.title,
      selectedInterval: def.intervals.contains(selectedInterval) ? selectedInterval : def.intervals.first,
      status: 'DRAFT',
      registrationNumber: registrationNumber.trim().toUpperCase(),
      vinNumber: vinNumber.trim().toUpperCase(),
      jobCardNumber: jobCardNumber,
      currentMileage: currentMileage,
      lastServiceMileage: lastServiceMileage,
      lastServiceDate: lastServiceDate,
      serviceTypeDone: serviceTypeDone,
      lastDealerVisited: lastDealerVisited,
      fuelLevel: fuelLevel,
      inspectionDate: DateTime.now().toIso8601String(),
      items: items,
      tyres: tyres,
      battery: battery,
      technicianName: technicianName,
    );
  }
}
