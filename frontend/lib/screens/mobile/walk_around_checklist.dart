import 'package:flutter/material.dart';

/// Standard 14-item Walk-Around Inventory Checklist from the Vehicle Receiving Memo
const List<String> kWalkAroundChecklistItems = [
  'Tool Kit',
  'Jack & Handle',
  'Spare Wheel',
  'Wheel Spanner',
  'Radio',
  'Radio Face',
  'Keys',
  'Aerial',
  'Cigar Lighter',
  'Gear Lock',
  'Floor Mats',
  'Hazard Triangles',
  'Fire Extinguisher',
  'First Aid Kit',
];

/// Job Service Categories from the Receiving Memo header
const List<String> kServiceCategories = [
  'Periodic Maintenance',
  'General Repairs',
  'Body & Paint',
  'Warranty / Recall',
  'Internal',
  'Quick Service',
  'Repeat Visit',
];

/// Visit Types from the Receiving Memo
const List<String> kVisitTypes = [
  'Booked',
  'Waiting',
  'Walk In',
  'Not Waiting',
];

/// Payment Modes from the Receiving Memo
const List<String> kPaymentModes = [
  'MPESA',
  'Credit/Debit Card',
  'ACCOUNT',
  'Cash',
  'Internal',
  'Others',
];

/// Workshop Sections from the Receiving Memo
const List<String> kWorkshopSections = [
  'LC (Light Commercial / Passenger)',
  'HC (Heavy Commercial / Truck)',
  'Body & Paint Shop',
];

class ReceivingMemoDetails {
  Map<String, bool> checklist;
  List<String> selectedCategories;
  String visitType;
  bool keepReplacedParts;
  bool valuablesRemoved;
  bool termsAccepted;
  String paymentMode;
  String workshopSection;
  String vinNumber;
  String avgKmPerDay;
  String approxCostEstimate;
  String remarks;

  ReceivingMemoDetails({
    Map<String, bool>? checklist,
    List<String>? selectedCategories,
    this.visitType = 'Walk In',
    this.keepReplacedParts = false,
    this.valuablesRemoved = true,
    this.termsAccepted = false,
    this.paymentMode = 'MPESA',
    this.workshopSection = 'LC (Light Commercial / Passenger)',
    this.vinNumber = '',
    this.avgKmPerDay = '',
    this.approxCostEstimate = '',
    this.remarks = '',
  })  : checklist = checklist ??
            {
              for (final item in kWalkAroundChecklistItems) item: false,
            },
        selectedCategories = selectedCategories ?? ['Periodic Maintenance'];

  Map<String, dynamic> toJson() => {
        'checklist': checklist,
        'selectedCategories': selectedCategories,
        'visitType': visitType,
        'keepReplacedParts': keepReplacedParts,
        'valuablesRemoved': valuablesRemoved,
        'termsAccepted': termsAccepted,
        'paymentMode': paymentMode,
        'workshopSection': workshopSection,
        'vinNumber': vinNumber,
        'avgKmPerDay': avgKmPerDay,
        'approxCostEstimate': approxCostEstimate,
        'remarks': remarks,
      };

  factory ReceivingMemoDetails.fromJson(Map<String, dynamic>? json) {
    if (json == null) return ReceivingMemoDetails();

    final Map<String, bool> parsedChecklist = {
      for (final item in kWalkAroundChecklistItems) item: false,
    };
    if (json['checklist'] is Map) {
      (json['checklist'] as Map).forEach((k, v) {
        parsedChecklist[k.toString()] = v == true;
      });
    }

    final List<String> parsedCats = [];
    if (json['selectedCategories'] is List) {
      for (final c in (json['selectedCategories'] as List)) {
        parsedCats.add(c.toString());
      }
    }

    return ReceivingMemoDetails(
      checklist: parsedChecklist,
      selectedCategories: parsedCats.isEmpty ? ['Periodic Maintenance'] : parsedCats,
      visitType: json['visitType']?.toString() ?? 'Walk In',
      keepReplacedParts: json['keepReplacedParts'] == true,
      valuablesRemoved: json['valuablesRemoved'] ?? true,
      termsAccepted: json['termsAccepted'] == true,
      paymentMode: json['paymentMode']?.toString() ?? 'MPESA',
      workshopSection: json['workshopSection']?.toString() ?? 'LC (Light Commercial / Passenger)',
      vinNumber: json['vinNumber']?.toString() ?? '',
      avgKmPerDay: json['avgKmPerDay']?.toString() ?? '',
      approxCostEstimate: json['approxCostEstimate']?.toString() ?? '',
      remarks: json['remarks']?.toString() ?? '',
    );
  }
}

class WalkAroundChecklistWidget extends StatefulWidget {
  final ReceivingMemoDetails details;
  final VoidCallback onChanged;
  final bool readOnly;

  const WalkAroundChecklistWidget({
    Key? key,
    required this.details,
    required this.onChanged,
    this.readOnly = false,
  }) : super(key: key);

  @override
  State<WalkAroundChecklistWidget> createState() => _WalkAroundChecklistWidgetState();
}

class _WalkAroundChecklistWidgetState extends State<WalkAroundChecklistWidget> {
  late TextEditingController _vinController;
  late TextEditingController _avgKmController;
  late TextEditingController _approxCostController;
  late TextEditingController _remarksController;

  @override
  void initState() {
    super.initState();
    _vinController = TextEditingController(text: widget.details.vinNumber);
    _avgKmController = TextEditingController(text: widget.details.avgKmPerDay);
    _approxCostController = TextEditingController(text: widget.details.approxCostEstimate);
    _remarksController = TextEditingController(text: widget.details.remarks);
  }

  @override
  void dispose() {
    _vinController.dispose();
    _avgKmController.dispose();
    _approxCostController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  void _showTermsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.gavel, color: Color(0xFF0F4C81)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Workshop Receiving Terms & Conditions',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: const SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '1. Authorization for Repairs & Road Testing',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4),
                Text(
                  'I hereby authorize the workshop and its technicians to perform the requested repair work, diagnostics, and maintenance, and grant permission to operate the vehicle on streets or highways for the purpose of testing and inspection.',
                  style: TextStyle(fontSize: 13, color: Colors.black87),
                ),
                SizedBox(height: 12),
                Text(
                  '2. Personal Valuables & Belongings',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4),
                Text(
                  'All personal valuables and loose belongings must be removed prior to leaving the vehicle. The workshop is only responsible for accessories and tools explicitly ticked as present on the Walk-Around Check.',
                  style: TextStyle(fontSize: 13, color: Colors.black87),
                ),
                SizedBox(height: 12),
                Text(
                  '3. Estimates, Parts & Storage',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4),
                Text(
                  'Any additional faults discovered during teardown will be communicated via an Official Estimate for approval. Replaced parts will only be retained if "Keep Replaced Parts: Yes" is selected at intake.',
                  style: TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          if (!widget.readOnly)
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F4C81), foregroundColor: Colors.white),
              onPressed: () {
                setState(() => widget.details.termsAccepted = true);
                widget.onChanged();
                Navigator.pop(ctx);
              },
              child: const Text('I Agree & Accept Terms'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.details;
    final checkedCount = d.checklist.values.where((v) => v).length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section 1: Service Categories & Visit Type (from top of Receiving Memo)
          const Row(
            children: [
              Icon(Icons.assignment_turned_in, size: 18, color: Color(0xFF0F4C81)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'RECEIVING MEMO DETAILS & SERVICE CATEGORIES',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0F172A), letterSpacing: 0.4),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kServiceCategories.map((cat) {
              final isSelected = d.selectedCategories.contains(cat);
              return FilterChip(
                label: Text(cat, style: const TextStyle(fontSize: 12)),
                selected: isSelected,
                selectedColor: const Color(0xFFDBEAFE),
                checkmarkColor: const Color(0xFF1D4ED8),
                onSelected: widget.readOnly
                    ? null
                    : (sel) {
                        setState(() {
                          if (sel) {
                            d.selectedCategories.add(cat);
                          } else if (d.selectedCategories.length > 1) {
                            d.selectedCategories.remove(cat);
                          }
                        });
                        widget.onChanged();
                      },
              );
            }).toList(),
          ),
          const SizedBox(height: 14),

          // Visit Type, Payment Mode, Section & Keep Replaced Parts
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: kVisitTypes.contains(d.visitType) ? d.visitType : kVisitTypes.first,
                  decoration: const InputDecoration(
                    labelText: 'Customer Visit Type',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: kVisitTypes
                      .map((v) => DropdownMenuItem(
                            value: v,
                            child: Text(v, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: widget.readOnly
                      ? null
                      : (val) {
                          setState(() => d.visitType = val ?? 'Walk In');
                          widget.onChanged();
                        },
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: kPaymentModes.contains(d.paymentMode) ? d.paymentMode : kPaymentModes.first,
                  decoration: const InputDecoration(
                    labelText: 'Mode of Payment',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: kPaymentModes
                      .map((p) => DropdownMenuItem(
                            value: p,
                            child: Text(p, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: widget.readOnly
                      ? null
                      : (val) {
                          setState(() => d.paymentMode = val ?? 'MPESA');
                          widget.onChanged();
                        },
                ),
              ),
              SizedBox(
                width: 250,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: kWorkshopSections.contains(d.workshopSection) ? d.workshopSection : kWorkshopSections.first,
                  decoration: const InputDecoration(
                    labelText: 'Workshop Section (LC/HC/Body)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: kWorkshopSections
                      .map((s) => DropdownMenuItem(
                            value: s,
                            child: Text(s, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: widget.readOnly
                      ? null
                      : (val) {
                          setState(() => d.workshopSection = val ?? kWorkshopSections.first);
                          widget.onChanged();
                        },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // VIN Number, Avg KM/day, Approx Cost Estimate & Keep Replaced Parts
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 190,
                child: TextField(
                  controller: _vinController,
                  readOnly: widget.readOnly,
                  onChanged: (v) {
                    d.vinNumber = v;
                    widget.onChanged();
                  },
                  decoration: const InputDecoration(
                    labelText: 'VIN / Chassis Number',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _avgKmController,
                  readOnly: widget.readOnly,
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    d.avgKmPerDay = v;
                    widget.onChanged();
                  },
                  decoration: const InputDecoration(
                    labelText: 'Avg KM / Day',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              SizedBox(
                width: 180,
                child: TextField(
                  controller: _approxCostController,
                  readOnly: widget.readOnly,
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    d.approxCostEstimate = v;
                    widget.onChanged();
                  },
                  decoration: const InputDecoration(
                    labelText: 'Approx. Cost Est (KSH)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Keep Replaced Parts:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    Switch(
                      value: d.keepReplacedParts,
                      activeColor: const Color(0xFF2563EB),
                      onChanged: widget.readOnly
                          ? null
                          : (val) {
                              setState(() => d.keepReplacedParts = val);
                              widget.onChanged();
                            },
                    ),
                    Text(d.keepReplacedParts ? 'YES' : 'NO', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),

          const Divider(height: 28),

          // Section 2: Walk-Around Inventory Checklist (14 items from the form)
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.fact_check_outlined, size: 18, color: Color(0xFF0F4C81)),
                  const SizedBox(width: 8),
                  Text(
                    'WALK-AROUND INVENTORY ($checkedCount / ${kWalkAroundChecklistItems.length})',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                  ),
                ],
              ),
              if (!widget.readOnly)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () {
                        setState(() {
                          for (final k in kWalkAroundChecklistItems) {
                            d.checklist[k] = true;
                          }
                        });
                        widget.onChanged();
                      },
                      child: const Text('Tick All', style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () {
                        setState(() {
                          for (final k in kWalkAroundChecklistItems) {
                            d.checklist[k] = false;
                          }
                        });
                        widget.onChanged();
                      },
                      child: const Text('Clear All', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ),
                  ],
                ),
            ],
          ),

          // Valuables Removed Banner
          Container(
            margin: const EdgeInsets.only(top: 6, bottom: 10),
            decoration: BoxDecoration(
              color: d.valuablesRemoved ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: d.valuablesRemoved ? Colors.green.shade300 : Colors.red.shade300),
            ),
            child: CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: Colors.green.shade700,
              value: d.valuablesRemoved,
              title: const Text(
                'ALL VALUABLE AND PERSONAL BELONGINGS REMOVED BY CUSTOMER',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              onChanged: widget.readOnly
                  ? null
                  : (val) {
                      setState(() => d.valuablesRemoved = val ?? false);
                      widget.onChanged();
                    },
            ),
          ),

          // 14 Walk-Around Checkboxes Grid (Tool Kit, Jack & Handle, Spare Wheel, First Aid Kit, etc.)
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: kWalkAroundChecklistItems.map((item) {
              final isChecked = d.checklist[item] == true;
              return InkWell(
                onTap: widget.readOnly
                    ? null
                    : () {
                        setState(() => d.checklist[item] = !isChecked);
                        widget.onChanged();
                      },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 195,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isChecked ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isChecked ? const Color(0xFF2563EB) : const Color(0xFFE2E8F0),
                      width: isChecked ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isChecked ? Icons.check_box : Icons.check_box_outline_blank,
                        size: 18,
                        color: isChecked ? const Color(0xFF2563EB) : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: isChecked ? FontWeight.bold : FontWeight.w500,
                            color: isChecked ? const Color(0xFF1E3A8A) : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 14),
          // Remarks: Any other part/tool in the vehicle
          TextField(
            controller: _remarksController,
            readOnly: widget.readOnly,
            maxLines: 2,
            onChanged: (v) {
              d.remarks = v;
              widget.onChanged();
            },
            decoration: const InputDecoration(
              labelText: 'Remarks: Any Other Part / Tool in the Vehicle or Special Notes',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),

          const Divider(height: 24),

          // Section 3: Terms & Conditions Acceptance
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: d.termsAccepted ? const Color(0xFFEFF6FF) : const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: d.termsAccepted ? const Color(0xFF93C5FD) : const Color(0xFFFDE68A),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: d.termsAccepted,
                      activeColor: const Color(0xFF2563EB),
                      onChanged: widget.readOnly
                          ? null
                          : (val) {
                              setState(() => d.termsAccepted = val ?? false);
                              widget.onChanged();
                            },
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: widget.readOnly
                            ? null
                            : () {
                                setState(() => d.termsAccepted = !d.termsAccepted);
                                widget.onChanged();
                              },
                        child: const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Customer agrees to Workshop Receiving Terms & Conditions (authorizing repairs, road test, and confirming inventory check above). *',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => _showTermsDialog(context),
                    icon: const Icon(Icons.menu_book_outlined, size: 16),
                    label: const Text('Read Full Terms & Conditions', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
