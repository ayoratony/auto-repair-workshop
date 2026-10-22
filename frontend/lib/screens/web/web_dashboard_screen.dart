import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'estimate_form.dart';
import 'invoice_pdf_service.dart';
import 'pdf_saver_stub.dart' if (dart.library.html) 'pdf_saver_web.dart';
import '../mobile/vehicle_damage_map.dart';
import '../mobile/walk_around_checklist.dart';

class WebDashboardScreen extends StatefulWidget {
  const WebDashboardScreen({Key? key}) : super(key: key);

  @override
  State<WebDashboardScreen> createState() => _WebDashboardScreenState();
}

class _WebDashboardScreenState extends State<WebDashboardScreen> {
  static const String _baseUrl = 'https://auto.zksms.online/api';

  // Navigation state
  String _activeSidebar = 'Dashboard';
  String _activeTab = 'Current Job Cards';

  // Real data collections from PostgreSQL
  Map<String, dynamic> _dashboard = {
    'totalRevenue': 0.0,
    'activeJobsCount': 0,
    'completedJobsCount': 0,
    'totalJobsCount': 0,
    'pendingEstimatesCount': 0,
    'lowStockCount': 0,
    'customersCount': 0,
    'employeesCount': 0,
    'weeklyJobs': [
      {'day': 'M', 'count': 0},
      {'day': 'T', 'count': 0},
      {'day': 'W', 'count': 0},
      {'day': 'T', 'count': 0},
      {'day': 'F', 'count': 0},
      {'day': 'S', 'count': 0},
    ],
    'recentActivities': [],
  };

  List<dynamic> _jobs = [];
  List<dynamic> _parts = [];
  List<dynamic> _estimates = [];
  List<dynamic> _invoices = [];
  List<dynamic> _customers = [];
  List<dynamic> _employees = [];
  List<dynamic> _appointments = [];
  List<dynamic> _expenses = [];
  Map<String, dynamic> _workshopSettings = {};

  bool _isLoading = true;
  bool _showEstimateCreator = false;
  String? _preselectedJobIdForEstimate;

  // Filters for Job Cards
  String _searchQuery = '';
  String _statusFilter = 'All';
  String _technicianFilter = 'All';
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _topSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refreshAllData();
  }

  Future<void> _refreshAllData() async {
    setState(() => _isLoading = true);
    try {
      final responses = await Future.wait([
        http.get(Uri.parse('$_baseUrl/dashboard')),
        http.get(Uri.parse('$_baseUrl/jobs')),
        http.get(Uri.parse('$_baseUrl/parts')),
        http.get(Uri.parse('$_baseUrl/estimates')),
        http.get(Uri.parse('$_baseUrl/invoices')),
        http.get(Uri.parse('$_baseUrl/customers')),
        http.get(Uri.parse('$_baseUrl/employees')),
        http.get(Uri.parse('$_baseUrl/settings')),
        http.get(Uri.parse('$_baseUrl/appointments')),
        http.get(Uri.parse('$_baseUrl/expenses')),
      ]);

      if (!mounted) return;
      setState(() {
        if (responses[0].statusCode == 200) _dashboard = json.decode(responses[0].body);
        if (responses[1].statusCode == 200) _jobs = json.decode(responses[1].body);
        if (responses[2].statusCode == 200) _parts = json.decode(responses[2].body);
        if (responses[3].statusCode == 200) _estimates = json.decode(responses[3].body);
        if (responses[4].statusCode == 200) _invoices = json.decode(responses[4].body);
        if (responses[5].statusCode == 200) _customers = json.decode(responses[5].body);
        if (responses[6].statusCode == 200) _employees = json.decode(responses[6].body);
        if (responses[7].statusCode == 200) _workshopSettings = json.decode(responses[7].body);
        if (responses[8].statusCode == 200) _appointments = json.decode(responses[8].body);
        if (responses[9].statusCode == 200) _expenses = json.decode(responses[9].body);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching data from backend: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _launchWhatsAppMessage(String rawPhone, String message) {
    String clean = rawPhone.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.startsWith('0') && clean.length == 10) {
      clean = '254${clean.substring(1)}';
    } else if (clean.isEmpty) {
      clean = '254700000000';
    }
    final encoded = Uri.encodeComponent(message);
    openExternalUrlImpl('https://wa.me/$clean?text=$encoded');
  }

  String _formatDate(dynamic isoString) {
    if (isoString == null) return '-';
    final str = isoString.toString();
    return str.length >= 10 ? str.substring(0, 10) : str;
  }

  List<dynamic> get _filteredJobs {
    return _jobs.where((job) {
      if (_statusFilter != 'All' && job['status'] != _statusFilter) {
        return false;
      }
      if (_technicianFilter != 'All' && (job['technician'] ?? 'Unassigned') != _technicianFilter) {
        return false;
      }
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final jobNo = (job['jobNumber'] ?? job['id'] ?? '').toString().toLowerCase();
        final customer = (job['customer']?['name'] ?? '').toString().toLowerCase();
        final reg = (job['vehicle']?['registrationNo'] ?? '').toString().toLowerCase();
        final make = (job['vehicle']?['make'] ?? '').toString().toLowerCase();
        final model = (job['vehicle']?['model'] ?? '').toString().toLowerCase();
        final service = (job['workRequested'] ?? '').toString().toLowerCase();
        final tech = (job['technician'] ?? '').toString().toLowerCase();
        return jobNo.contains(q) ||
            customer.contains(q) ||
            reg.contains(q) ||
            make.contains(q) ||
            model.contains(q) ||
            service.contains(q) ||
            tech.contains(q);
      }
      return true;
    }).toList();
  }

  List<String> get _availableTechnicians {
    final Set<String> techs = {'All', 'Unassigned'};
    for (final emp in _employees) {
      if (emp['name'] != null && emp['name'].toString().isNotEmpty) {
        techs.add(emp['name'].toString());
      }
    }
    for (final job in _jobs) {
      if (job['technician'] != null && job['technician'].toString().isNotEmpty) {
        techs.add(job['technician'].toString());
      }
    }
    return techs.toList();
  }

  String _formatDateShort(dynamic isoString) {
    if (isoString == null) return '-';
    try {
      final dt = DateTime.parse(isoString.toString()).toLocal();
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[dt.month - 1]} ${dt.day}';
    } catch (_) {
      return '-';
    }
  }

  String _formatTimeAgo(dynamic isoString) {
    if (isoString == null) return '';
    try {
      final dt = DateTime.parse(isoString.toString()).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours} hours ago';
      return '${diff.inDays} days ago';
    } catch (_) {
      return '';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'INSPECTION':
        return Colors.purple;
      case 'AWAITING_APPROVAL':
        return Colors.amber.shade800;
      case 'IN_PROGRESS':
        return Colors.blue;
      case 'WAITING':
        return Colors.orange;
      case 'QUALITY_CHECK':
        return Colors.cyan.shade700;
      case 'COMPLETED':
        return Colors.green;
      case 'READY':
        return Colors.teal;
      case 'BOOKED':
      default:
        return Colors.indigo;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'BOOKED':
        return '1. Checked-In';
      case 'INSPECTION':
        return '2. Inspection';
      case 'AWAITING_APPROVAL':
        return '3. Awaiting Approval';
      case 'IN_PROGRESS':
        return '4. In Repair';
      case 'WAITING':
        return '5. Waiting Parts';
      case 'QUALITY_CHECK':
        return '6. Quality Check (QC)';
      case 'READY':
        return '7. Ready for Pickup';
      case 'COMPLETED':
        return 'Delivered / Closed';
      default:
        return status;
    }
  }

  Color _priorityColor(String priority) {
    switch (priority) {
      case 'High':
        return Colors.red;
      case 'Low':
        return Colors.green;
      case 'Medium':
      default:
        return Colors.grey.shade700;
    }
  }

  // ==========================================
  // DIALOGS: CREATE / EDIT / VIEW JOB CARD
  // ==========================================
  Future<void> _showJobCardDialog({Map<String, dynamic>? existingJob}) async {
    final isEdit = existingJob != null;
    final customerNameCtrl = TextEditingController(text: existingJob?['customer']?['name'] ?? '');
    final phoneCtrl = TextEditingController(text: existingJob?['customer']?['phone'] ?? '');
    final regCtrl = TextEditingController(text: existingJob?['vehicle']?['registrationNo'] ?? '');
    final makeCtrl = TextEditingController(text: existingJob?['vehicle']?['make'] ?? '');
    final modelCtrl = TextEditingController(text: existingJob?['vehicle']?['model'] ?? '');
    final serviceCtrl = TextEditingController(text: existingJob?['workRequested'] ?? '');
    final techCtrl = TextEditingController(text: existingJob?['technician'] ?? '');
    final odometerCtrl = TextEditingController(text: existingJob?['odometer']?.toString() ?? '');
    final nextMileageCtrl = TextEditingController(
      text: (existingJob?['nextServiceMileage'] ?? existingJob?['vehicle']?['nextServiceMileage'])?.toString() ?? '',
    );
    final estHoursCtrl = TextEditingController(text: (existingJob?['estimatedHours'] ?? 2.0).toString());
    final warrantyNotesCtrl = TextEditingController(text: existingJob?['warrantyNotes']?.toString() ?? '');

    String status = existingJob?['status'] ?? 'IN_PROGRESS';
    String priority = existingJob?['priority'] ?? 'Medium';
    String fuelLevel = existingJob?['fuelLevel'] ?? 'Half';
    String bayNumber = existingJob?['bayNumber']?.toString() ?? 'Bay 1';
    bool isWarranty = existingJob?['isWarranty'] == true;
    DateTime dueDate = existingJob?['dueDate'] != null
        ? (DateTime.tryParse(existingJob!['dueDate'].toString()) ?? DateTime.now().add(const Duration(days: 2)))
        : DateTime.now().add(const Duration(days: 2));

    List<DamageMarker> markers = [];
    VehicleBodyType bodyType = VehicleBodyType.sedan;
    ReceivingMemoDetails memoDetails = ReceivingMemoDetails(
      vinNumber: existingJob?['vehicle']?['vinNumber']?.toString() ?? '',
    );
    Map<String, String> diagnostics = {
      'Engine': 'Pass',
      'Brakes': 'Pass',
      'Suspension': 'Pass',
      'Tyres': 'Pass',
      'Battery': 'Pass',
      'Electrical': 'Pass',
      'AC': 'Pass',
      'Transmission': 'Pass',
    };
    final obdCodesCtrl = TextEditingController();
    bool qcPassed = false;
    List<String> assetKeys = [];

    final existingWalkAround = existingJob?['walkAroundData'];
    if (existingWalkAround is Map) {
      if (existingWalkAround['bodyType'] != null) {
        final btName = existingWalkAround['bodyType'].toString();
        bodyType = VehicleBodyType.values.firstWhere(
          (e) => e.name == btName,
          orElse: () => VehicleBodyType.sedan,
        );
      }
      if (existingWalkAround['markers'] is List) {
        markers = (existingWalkAround['markers'] as List)
            .map((m) => DamageMarker.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      }
      if (existingWalkAround['memoDetails'] is Map) {
        memoDetails = ReceivingMemoDetails.fromJson(
          Map<String, dynamic>.from(existingWalkAround['memoDetails']),
        );
      }
      if (existingWalkAround['diagnostics'] is Map) {
        final rawDiag = Map<String, dynamic>.from(existingWalkAround['diagnostics']);
        for (final k in diagnostics.keys.toList()) {
          if (rawDiag[k] != null) diagnostics[k] = rawDiag[k].toString();
        }
      }
      if (existingWalkAround['obdCodes'] != null) {
        obdCodesCtrl.text = existingWalkAround['obdCodes'].toString();
      }
      if (existingWalkAround['qcPassed'] == true) {
        qcPassed = true;
      }
      if (existingWalkAround['assetKeys'] is List) {
        assetKeys = (existingWalkAround['assetKeys'] as List).map((e) => e.toString()).toList();
      }
    }

    bool isSaving = false;
    const bayOptions = ['Bay 1', 'Bay 2', 'Bay 3', 'Lift 1', 'Lift 2', 'Diagnostics Bay', 'Body & Paint Bay'];

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              title: Text(isEdit
                  ? 'Edit Job Card (${existingJob['jobNumber'] ?? existingJob['id'].toString().substring(0, 8).toUpperCase()})'
                  : 'Create New Job Card & Vehicle Walk-Around'),
              content: SizedBox(
                width: 720,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: customerNameCtrl,
                              decoration: const InputDecoration(labelText: 'Customer Name *', border: OutlineInputBorder()),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: phoneCtrl,
                              decoration: const InputDecoration(labelText: 'Customer Phone (WhatsApp)', border: OutlineInputBorder()),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: regCtrl,
                              decoration: const InputDecoration(labelText: 'Registration No. * (e.g. KDA 123A)', border: OutlineInputBorder()),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: makeCtrl,
                              decoration: const InputDecoration(labelText: 'Vehicle Make (e.g. Toyota)', border: OutlineInputBorder()),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: modelCtrl,
                              decoration: const InputDecoration(labelText: 'Vehicle Model (e.g. Prado)', border: OutlineInputBorder()),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: serviceCtrl,
                              decoration: const InputDecoration(labelText: 'Service / Work Requested *', border: OutlineInputBorder()),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 1,
                            child: TextField(
                              controller: techCtrl,
                              decoration: InputDecoration(
                                labelText: 'Assigned Technician',
                                border: const OutlineInputBorder(),
                                suffixIcon: _employees.isNotEmpty
                                    ? PopupMenuButton<String>(
                                        icon: const Icon(Icons.arrow_drop_down),
                                        onSelected: (val) => setModalState(() => techCtrl.text = val),
                                        itemBuilder: (_) => _employees
                                            .map((e) => PopupMenuItem<String>(
                                                  value: e['name'].toString(),
                                                  child: Text(e['name'].toString()),
                                                ))
                                            .toList(),
                                      )
                                    : null,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 1,
                            child: DropdownButtonFormField<String>(
                              value: bayOptions.contains(bayNumber) ? bayNumber : 'Bay 1',
                              decoration: const InputDecoration(labelText: 'Workshop Bay / Lift', border: OutlineInputBorder()),
                              items: bayOptions.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
                              onChanged: (val) => setModalState(() => bayNumber = val ?? 'Bay 1'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: status,
                              decoration: const InputDecoration(labelText: '7-Stage Workflow Status', border: OutlineInputBorder()),
                              items: const [
                                DropdownMenuItem(value: 'BOOKED', child: Text('1. Checked-In')),
                                DropdownMenuItem(value: 'INSPECTION', child: Text('2. Inspection & OBD-II')),
                                DropdownMenuItem(value: 'AWAITING_APPROVAL', child: Text('3. Awaiting Approval')),
                                DropdownMenuItem(value: 'IN_PROGRESS', child: Text('4. In Repair')),
                                DropdownMenuItem(value: 'WAITING', child: Text('5. Waiting Parts')),
                                DropdownMenuItem(value: 'QUALITY_CHECK', child: Text('6. Quality Check (QC)')),
                                DropdownMenuItem(value: 'READY', child: Text('7. Ready for Pickup')),
                                DropdownMenuItem(value: 'COMPLETED', child: Text('Delivered / Closed')),
                              ],
                              onChanged: (val) => setModalState(() => status = val ?? 'IN_PROGRESS'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: priority,
                              decoration: const InputDecoration(labelText: 'Priority', border: OutlineInputBorder()),
                              items: const [
                                DropdownMenuItem(value: 'Low', child: Text('Low')),
                                DropdownMenuItem(value: 'Medium', child: Text('Medium')),
                                DropdownMenuItem(value: 'High', child: Text('High')),
                              ],
                              onChanged: (val) => setModalState(() => priority = val ?? 'Medium'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: ctx,
                                  initialDate: dueDate,
                                  firstDate: DateTime(2024),
                                  lastDate: DateTime(2030),
                                );
                                if (picked != null) {
                                  setModalState(() => dueDate = picked);
                                }
                              },
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  labelText: 'Expected Completion',
                                  border: OutlineInputBorder(),
                                  suffixIcon: Icon(Icons.calendar_today, size: 18),
                                ),
                                child: Text(_formatDateShort(dueDate.toIso8601String())),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: odometerCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Current Odometer (km)', border: OutlineInputBorder()),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: nextMileageCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Next Service Due (km)', border: OutlineInputBorder()),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: ['Empty', '1/4', 'Half', '3/4', 'Full'].contains(fuelLevel) ? fuelLevel : 'Half',
                              decoration: const InputDecoration(labelText: 'Fuel Level', border: OutlineInputBorder()),
                              items: ['Empty', '1/4', 'Half', '3/4', 'Full']
                                  .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                                  .toList(),
                              onChanged: (val) => setModalState(() => fuelLevel = val ?? 'Half'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 110,
                            child: TextField(
                              controller: estHoursCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Est. Hrs', border: OutlineInputBorder()),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isWarranty ? Colors.amber.shade50 : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: isWarranty ? Colors.amber.shade300 : Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Checkbox(
                              value: isWarranty,
                              onChanged: (v) => setModalState(() => isWarranty = v ?? false),
                            ),
                            const Text('Warranty / Comeback Rework Job', style: TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(width: 24),
                            Checkbox(
                              value: qcPassed,
                              activeColor: Colors.green,
                              onChanged: (v) => setModalState(() => qcPassed = v ?? false),
                            ),
                            const Text('Quality Control (QC) Road-Test Passed', style: TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      if (isWarranty) ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: warrantyNotesCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Warranty / Rework Claim Reference & Notes',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blueGrey.shade100),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Mechanical & OBD-II Diagnostic Health Check (Tap to toggle Pass / Attention / Fail)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              children: diagnostics.keys.map((sys) {
                                final currentVal = diagnostics[sys] ?? 'Pass';
                                final chipColor = currentVal == 'Pass'
                                    ? Colors.green
                                    : currentVal == 'Attention'
                                        ? Colors.orange
                                        : Colors.red;
                                return InkWell(
                                  onTap: () {
                                    setModalState(() {
                                      diagnostics[sys] = currentVal == 'Pass'
                                          ? 'Attention'
                                          : currentVal == 'Attention'
                                              ? 'Fail'
                                              : 'Pass';
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: chipColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: chipColor.withOpacity(0.5)),
                                    ),
                                    child: Text(
                                      '$sys: $currentVal',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: chipColor),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: obdCodesCtrl,
                              decoration: const InputDecoration(
                                labelText: 'OBD-II Fault Codes / Scanner Notes (e.g. P0300 Random Misfire, ABS C1201)',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      const Text(
                        '360° Vehicle Walk-Around Inspection (Select Body Type, Angle & Tap to Mark Dents/Scratches/Cuts)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                      ),
                      const SizedBox(height: 8),
                      VehicleDamageMap(
                        initialMarkers: markers,
                        initialBodyType: bodyType,
                        onMarkersChanged: (updated) {
                          markers = updated;
                        },
                        onBodyTypeChanged: (updatedType) {
                          bodyType = updatedType;
                        },
                      ),
                      const SizedBox(height: 16),
                      WalkAroundChecklistWidget(
                        details: memoDetails,
                        onChanged: () => setModalState(() {}),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                if (isEdit)
                  TextButton.icon(
                    onPressed: isSaving
                        ? null
                        : () async {
                            setModalState(() => isSaving = true);
                            try {
                              await http.delete(Uri.parse('$_baseUrl/jobs/${existingJob['id']}'));
                              if (ctx.mounted) Navigator.pop(ctx);
                              _refreshAllData();
                            } finally {
                              if (ctx.mounted) setModalState(() => isSaving = false);
                            }
                          },
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text('Delete Job', style: TextStyle(color: Colors.red)),
                  ),
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                  ),
                  icon: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(isEdit ? Icons.save_outlined : Icons.add_task, size: 18),
                  label: Text(
                    isSaving
                        ? 'Saving...'
                        : (isEdit ? 'Save Changes' : 'Create Job Card'),
                  ),
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (customerNameCtrl.text.trim().isEmpty || regCtrl.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(backgroundColor: Colors.orange, content: Text('Customer Name and Registration No. are required.')),
                            );
                            return;
                          }
                          if (!memoDetails.termsAccepted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(backgroundColor: Colors.orange, content: Text('Please tick that the Customer agrees to the Workshop Receiving Terms & Conditions.')),
                            );
                            return;
                          }
                          setModalState(() => isSaving = true);
                          try {
                            final payload = {
                              'customerName': customerNameCtrl.text.trim(),
                              'phone': phoneCtrl.text.trim(),
                              'registrationNo': regCtrl.text.trim(),
                              'make': makeCtrl.text.trim(),
                              'model': modelCtrl.text.trim(),
                              'vinNumber': memoDetails.vinNumber,
                              'service': serviceCtrl.text.trim().isEmpty
                                  ? memoDetails.selectedCategories.join(', ')
                                  : serviceCtrl.text.trim(),
                              'technician': techCtrl.text.trim().isEmpty ? 'Unassigned' : techCtrl.text.trim(),
                              'bayNumber': bayNumber,
                              'status': status,
                              'priority': priority,
                              'dueDate': dueDate.toIso8601String(),
                              'odometer': int.tryParse(odometerCtrl.text.trim()),
                              'nextServiceMileage': int.tryParse(nextMileageCtrl.text.trim()),
                              'fuelLevel': fuelLevel,
                              'estimatedHours': double.tryParse(estHoursCtrl.text.trim()) ?? 2.0,
                              'isWarranty': isWarranty,
                              'warrantyNotes': warrantyNotesCtrl.text.trim(),
                              'walkAroundData': {
                                'bodyType': bodyType.name,
                                'markers': markers.map((m) => m.toJson()).toList(),
                                'memoDetails': memoDetails.toJson(),
                                'diagnostics': diagnostics,
                                'obdCodes': obdCodesCtrl.text.trim(),
                                'qcPassed': qcPassed,
                                'assetKeys': assetKeys,
                                'updatedAt': DateTime.now().toIso8601String(),
                              },
                            };

                            if (isEdit) {
                              await http.put(
                                Uri.parse('$_baseUrl/jobs/${existingJob['id']}'),
                                headers: {'Content-Type': 'application/json'},
                                body: json.encode(payload),
                              );
                            } else {
                              await http.post(
                                Uri.parse('$_baseUrl/jobs'),
                                headers: {'Content-Type': 'application/json'},
                                body: json.encode(payload),
                              );
                            }
                            if (ctx.mounted) Navigator.pop(ctx);
                            _refreshAllData();
                          } catch (e) {
                            if (ctx.mounted) {
                              setModalState(() => isSaving = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(backgroundColor: Colors.red, content: Text('Failed to save Job Card: $e')),
                              );
                            }
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showViewJobDialog(Map<String, dynamic> job) async {
    final jobNo = job['jobNumber'] ?? job['id'].toString().substring(0, 8).toUpperCase();
    final customer = job['customer'] ?? {};
    final vehicle = job['vehicle'] ?? {};
    final estimates = (job['estimates'] as List<dynamic>?) ?? [];

    List<DamageMarker> markers = [];
    VehicleBodyType bodyType = VehicleBodyType.sedan;
    ReceivingMemoDetails memoDetails = ReceivingMemoDetails(
      vinNumber: vehicle['vinNumber']?.toString() ?? '',
    );
    Map<String, dynamic> diagnostics = {};
    String obdCodes = '';
    bool qcPassed = false;
    List<String> assetKeys = [];

    final walkAround = job['walkAroundData'];
    if (walkAround is Map) {
      if (walkAround['bodyType'] != null) {
        final btName = walkAround['bodyType'].toString();
        bodyType = VehicleBodyType.values.firstWhere(
          (e) => e.name == btName,
          orElse: () => VehicleBodyType.sedan,
        );
      }
      if (walkAround['markers'] is List) {
        markers = (walkAround['markers'] as List)
            .map((m) => DamageMarker.fromJson(Map<String, dynamic>.from(m)))
            .toList();
      }
      if (walkAround['memoDetails'] is Map) {
        memoDetails = ReceivingMemoDetails.fromJson(
          Map<String, dynamic>.from(walkAround['memoDetails']),
        );
      }
      if (walkAround['diagnostics'] is Map) {
        diagnostics = Map<String, dynamic>.from(walkAround['diagnostics']);
      }
      if (walkAround['obdCodes'] != null) {
        obdCodes = walkAround['obdCodes'].toString();
      }
      if (walkAround['qcPassed'] == true) {
        qcPassed = true;
      }
      if (walkAround['assetKeys'] is List) {
        assetKeys = (walkAround['assetKeys'] as List).map((e) => e.toString()).toList();
      }
    }

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text('Job Card $jobNo — ${customer['name'] ?? ''}')),
                  if (job['isWarranty'] == true)
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Chip(
                        label: const Text('WARRANTY', style: TextStyle(color: Colors.brown, fontWeight: FontWeight.bold, fontSize: 11)),
                        backgroundColor: Colors.amber.shade100,
                      ),
                    ),
                  Chip(
                    label: Text(_statusLabel(job['status'] ?? 'IN_PROGRESS'),
                        style: TextStyle(color: _statusColor(job['status'] ?? 'IN_PROGRESS'), fontWeight: FontWeight.bold)),
                    backgroundColor: _statusColor(job['status'] ?? 'IN_PROGRESS').withOpacity(0.1),
                  ),
                ],
              ),
              content: SizedBox(
                width: 700,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Info summary grid
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('CUSTOMER DETAILS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                                  const SizedBox(height: 6),
                                  Text('Name: ${customer['name'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w600)),
                                  Text('Phone: ${customer['phone'] ?? '-'}'),
                                  const SizedBox(height: 12),
                                  const Text('WORKSHOP ASSIGNMENT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                                  const SizedBox(height: 6),
                                  Text('Service: ${job['workRequested'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w600)),
                                  Text('Technician: ${job['technician'] ?? 'Unassigned'}  •  Bay: ${job['bayNumber'] ?? 'Bay 1'}'),
                                  Text('Priority: ${job['priority'] ?? 'Medium'} • Due: ${_formatDateShort(job['dueDate'])}'),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('VEHICLE & DIAGNOSTIC SUMMARY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                                  const SizedBox(height: 6),
                                  Text('Reg No: ${vehicle['registrationNo'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w600)),
                                  Text('Make/Model: ${vehicle['make'] ?? ''} ${vehicle['model'] ?? ''}'),
                                  Text('Odometer: ${job['odometer'] != null ? '${job['odometer']} km' : 'Not recorded'}  •  Next Service: ${job['nextServiceMileage'] != null ? '${job['nextServiceMileage']} km' : 'TBA'}'),
                                  Text('Fuel Level: ${job['fuelLevel'] ?? 'Not recorded'}  •  QC Passed: ${qcPassed ? 'YES ✓' : 'Pending'}'),
                                  if (obdCodes.isNotEmpty)
                                    Text('OBD-II Codes: $obdCodes', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: () async {
                              final key = 'jobs/$jobNo/inspection-${DateTime.now().millisecondsSinceEpoch}.txt';
                              final reportText = 'Inspection Snapshot for $jobNo (${vehicle['registrationNo']}) - Status: ${job['status']} - OBD: $obdCodes - Damages: ${markers.length}';
                              final resp = await http.post(
                                Uri.parse('$_baseUrl/assets/upload'),
                                headers: {'Content-Type': 'application/json'},
                                body: json.encode({
                                  'key': key,
                                  'contentText': reportText,
                                  'contentType': 'text/plain',
                                  'jobCardId': job['id'],
                                }),
                              );
                              if (resp.statusCode == 201) {
                                setModalState(() {
                                  if (!assetKeys.contains(key)) assetKeys.add(key);
                                });
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(backgroundColor: Colors.green, content: Text('Uploaded $key to Neon Object Storage!')),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.cloud_upload_outlined, size: 16),
                            label: Text('Archive Inspection to Neon Cloud (${assetKeys.length})'),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: () {
                              final msg = 'Hello ${customer['name'] ?? 'Customer'}, your vehicle ${vehicle['registrationNo'] ?? ''} (Job Card $jobNo) at ${_workshopSettings['name'] ?? 'MechanicHQ'} is currently in stage: ${_statusLabel(job['status'] ?? 'IN_PROGRESS')}.';
                              _launchWhatsAppMessage(customer['phone']?.toString() ?? '', msg);
                            },
                            icon: const Icon(Icons.chat_outlined, size: 16, color: Colors.green),
                            label: const Text('Send WhatsApp Status Update', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text('Walk-Around Damage Map (Tap to mark or update vehicle damages)', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      VehicleDamageMap(
                        initialMarkers: markers,
                        initialBodyType: bodyType,
                        onMarkersChanged: (updated) {
                          markers = updated;
                        },
                        onBodyTypeChanged: (updatedType) {
                          bodyType = updatedType;
                        },
                      ),
                      const SizedBox(height: 16),
                      WalkAroundChecklistWidget(
                        details: memoDetails,
                        onChanged: () {},
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Linked Estimates (${estimates.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              setState(() {
                                _activeSidebar = 'Estimates';
                                _activeTab = 'Estimates';
                                _showEstimateCreator = true;
                                _preselectedJobIdForEstimate = job['id'];
                              });
                            },
                            icon: const Icon(Icons.receipt_long, size: 16),
                            label: const Text('Create Estimate for this Job'),
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (estimates.isEmpty)
                        const Text('No estimates generated for this job card yet.', style: TextStyle(color: Colors.grey))
                      else
                        ...estimates.map((est) {
                          return Card(
                            child: ListTile(
                              title: Text('Total: KSH ${(est['total'] as num).toStringAsFixed(2)} (Incl. 16% VAT & ${est['discountRate']}% Discount)'),
                              subtitle: Text('Status: ${est['status']} • Subtotal: KSH ${(est['subtotal'] as num).toStringAsFixed(2)}'),
                            ),
                          );
                        }).toList(),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    final updatedJob = Map<String, dynamic>.from(job);
                    updatedJob['walkAroundData'] = {
                      'bodyType': bodyType.name,
                      'markers': markers.map((m) => m.toJson()).toList(),
                      'memoDetails': memoDetails.toJson(),
                      'diagnostics': diagnostics,
                      'obdCodes': obdCodes,
                      'qcPassed': qcPassed,
                      'assetKeys': assetKeys,
                    };
                    InvoicePdfService.showJobCardPreviewModal(
                      context: context,
                      workshopSettings: _workshopSettings,
                      job: updatedJob,
                    );
                  },
                  icon: const Icon(Icons.print_outlined, size: 17, color: Color(0xFF1D4ED8)),
                  label: const Text(
                    'Print / PDF Customer Copy',
                    style: TextStyle(color: Color(0xFF1D4ED8), fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF1D4ED8)),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await http.put(
                      Uri.parse('$_baseUrl/jobs/${job['id']}'),
                      headers: {'Content-Type': 'application/json'},
                      body: json.encode({
                        'walkAroundData': {
                          'bodyType': bodyType.name,
                          'markers': markers.map((m) => m.toJson()).toList(),
                          'memoDetails': memoDetails.toJson(),
                          'diagnostics': diagnostics,
                          'obdCodes': obdCodes,
                          'qcPassed': qcPassed,
                          'assetKeys': assetKeys,
                          'updatedAt': DateTime.now().toIso8601String(),
                        }
                      }),
                    );
                    if (mounted) Navigator.pop(ctx);
                    _refreshAllData();
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                  child: const Text('Save Inspection & Checklist'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ==========================================
  // DIALOG: ADD / EDIT PART IN CATALOG + STOCK LEDGER
  // ==========================================
  Future<void> _showPartDialog({Map<String, dynamic>? existingPart}) async {
    final isEdit = existingPart != null;
    final partNoCtrl = TextEditingController(text: existingPart?['partNumber'] ?? '');
    final descCtrl = TextEditingController(text: existingPart?['description'] ?? '');
    final brandCtrl = TextEditingController(text: existingPart?['brand']?.toString() ?? '');
    final compatCtrl = TextEditingController(text: existingPart?['compatibility']?.toString() ?? '');
    final costCtrl = TextEditingController(text: existingPart?['costPrice']?.toString() ?? '');
    final priceCtrl = TextEditingController(text: existingPart?['unitPrice']?.toString() ?? '');
    final stockCtrl = TextEditingController(text: existingPart?['stockQuantity']?.toString() ?? '10');
    final reorderCtrl = TextEditingController(text: (existingPart?['reorderLevel'] ?? 5).toString());
    final supplierCtrl = TextEditingController(text: existingPart?['supplierName']?.toString() ?? '');

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(isEdit ? 'Edit Spare Part & Supplier Info' : 'Add New Part to Catalog'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: partNoCtrl,
                          decoration: const InputDecoration(labelText: 'Part / SKU No (e.g. BP-2040)', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: brandCtrl,
                          decoration: const InputDecoration(labelText: 'Brand (e.g. Toyota OEM / Denso)', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(labelText: 'Part Description (e.g. Ceramic Front Brake Pads)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: compatCtrl,
                          decoration: const InputDecoration(labelText: 'Compatible Models (e.g. Hilux / Prado)', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: supplierCtrl,
                          decoration: const InputDecoration(labelText: 'Supplier Name', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: costCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Buying Cost (KSH)', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: priceCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Selling Price (KSH)', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: stockCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Current Stock Qty', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: reorderCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Min Reorder Alert Qty', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
              onPressed: () async {
                final sellingPrice = double.tryParse(priceCtrl.text.trim()) ?? 0;
                final buyingCost = double.tryParse(costCtrl.text.trim()) ?? (sellingPrice * 0.65);
                final payload = {
                  'partNumber': partNoCtrl.text.trim(),
                  'description': descCtrl.text.trim(),
                  'brand': brandCtrl.text.trim(),
                  'compatibility': compatCtrl.text.trim(),
                  'supplierName': supplierCtrl.text.trim(),
                  'costPrice': buyingCost,
                  'unitPrice': sellingPrice,
                  'stockQuantity': int.tryParse(stockCtrl.text.trim()) ?? 0,
                  'reorderLevel': int.tryParse(reorderCtrl.text.trim()) ?? 5,
                };
                if (isEdit) {
                  await http.put(
                    Uri.parse('$_baseUrl/parts/${existingPart['id']}'),
                    headers: {'Content-Type': 'application/json'},
                    body: json.encode(payload),
                  );
                } else {
                  await http.post(
                    Uri.parse('$_baseUrl/parts'),
                    headers: {'Content-Type': 'application/json'},
                    body: json.encode(payload),
                  );
                }
                if (mounted) Navigator.pop(ctx);
                _refreshAllData();
              },
              child: Text(isEdit ? 'Update Part' : 'Add Part'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showStockMovementDialog(Map<String, dynamic> part) async {
    String moveType = 'RECEIVED';
    final qtyCtrl = TextEditingController(text: '5');
    final costCtrl = TextEditingController(text: (part['costPrice'] ?? 0).toString());
    final supplierCtrl = TextEditingController(text: part['supplierName']?.toString() ?? '');
    final refCtrl = TextEditingController();
    final movements = (part['stockMovements'] as List<dynamic>?) ?? [];

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              title: Text('Stock Ledger: ${part['partNumber']} — ${part['description']}'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Current In-Stock: ${part['stockQuantity']} units', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: moveType,
                              decoration: const InputDecoration(labelText: 'Movement Type', border: OutlineInputBorder()),
                              items: const [
                                DropdownMenuItem(value: 'RECEIVED', child: Text('Receive Stock (+ In)')),
                                DropdownMenuItem(value: 'ISSUED', child: Text('Issue to Job (- Out)')),
                                DropdownMenuItem(value: 'RETURNED', child: Text('Customer/Job Return (+ In)')),
                                DropdownMenuItem(value: 'ADJUSTED', child: Text('Stocktake Set Exact (=)')),
                              ],
                              onChanged: (v) => setModalState(() => moveType = v ?? 'RECEIVED'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 120,
                            child: TextField(
                              controller: qtyCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Quantity', border: OutlineInputBorder()),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: costCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Unit Buying Cost (KSH)', border: OutlineInputBorder()),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: supplierCtrl,
                              decoration: const InputDecoration(labelText: 'Supplier / Source', border: OutlineInputBorder()),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: refCtrl,
                        decoration: const InputDecoration(labelText: 'Reference (LPO #, Delivery Note, or Job Card #)', border: OutlineInputBorder()),
                      ),
                      if (movements.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Text('Recent Stock Movements', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const Divider(),
                        ...movements.take(5).map((m) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text('${m['type']}: ${m['quantity']} units  •  Ref: ${m['reference'] ?? '-'}',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                              subtitle: Text('Supplier: ${m['supplierName'] ?? '-'}  •  ${_formatDateShort(m['createdAt'])}',
                                  style: const TextStyle(fontSize: 11)),
                            )),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save_alt, size: 16),
                  label: const Text('Record Stock Movement'),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
                  onPressed: () async {
                    await http.post(
                      Uri.parse('$_baseUrl/parts/${part['id']}/stock'),
                      headers: {'Content-Type': 'application/json'},
                      body: json.encode({
                        'type': moveType,
                        'quantity': int.tryParse(qtyCtrl.text.trim()) ?? 0,
                        'unitCost': double.tryParse(costCtrl.text.trim()),
                        'supplierName': supplierCtrl.text.trim(),
                        'reference': refCtrl.text.trim(),
                      }),
                    );
                    if (mounted) Navigator.pop(ctx);
                    _refreshAllData();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showRecordPaymentDialog(Map<String, dynamic> inv) async {
    final est = inv['estimate'] ?? {};
    final total = (est['total'] as num?)?.toDouble() ?? 0.0;
    final alreadyPaid = (inv['amountPaid'] as num?)?.toDouble() ?? 0.0;
    final remaining = (total - alreadyPaid).clamp(0.0, total);
    final amountCtrl = TextEditingController(text: remaining > 0 ? remaining.toStringAsFixed(0) : total.toStringAsFixed(0));
    final refCtrl = TextEditingController(text: inv['mpesaReceiptNo']?.toString() ?? '');
    String mode = inv['paymentMode']?.toString() ?? 'MPESA';
    if (!['MPESA', 'CASH', 'BANK TRANSFER', 'CARD', 'INVOICE CREDIT'].contains(mode)) {
      mode = 'MPESA';
    }

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              title: Text('Record Payment / Deposit — INV-${inv['id'].toString().substring(0, 6).toUpperCase()}'),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Invoice Total: KSH ${total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('Already Paid: KSH ${alreadyPaid.toStringAsFixed(2)}  •  Balance Due: KSH ${remaining.toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.blueGrey, fontSize: 13)),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: mode,
                      decoration: const InputDecoration(labelText: 'Payment Mode', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'MPESA', child: Text('M-Pesa (Paybill / Till)')),
                        DropdownMenuItem(value: 'CASH', child: Text('Cash')),
                        DropdownMenuItem(value: 'BANK TRANSFER', child: Text('Bank Transfer / Cheque')),
                        DropdownMenuItem(value: 'CARD', child: Text('POS Card')),
                        DropdownMenuItem(value: 'INVOICE CREDIT', child: Text('Pay Later / Corporate Credit')),
                      ],
                      onChanged: (v) => setModalState(() => mode = v ?? 'MPESA'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Amount Received Now (KSH) — Enter Deposit or Full Balance',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: refCtrl,
                      decoration: const InputDecoration(
                        labelText: 'M-Pesa Receipt / Bank Reference (e.g. QKA82910XY)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                ElevatedButton.icon(
                  icon: const Icon(Icons.payments_outlined, size: 16),
                  label: const Text('Save Payment'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
                  onPressed: () async {
                    final payAmt = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                    await http.put(
                      Uri.parse('$_baseUrl/invoices/${inv['id']}'),
                      headers: {'Content-Type': 'application/json'},
                      body: json.encode({
                        'paymentMode': mode,
                        'paymentAmount': payAmt,
                        'mpesaReceiptNo': refCtrl.text.trim(),
                        if (mode == 'INVOICE CREDIT' && payAmt <= 0) 'paymentStatus': 'PAY_LATER',
                      }),
                    );
                    if (mounted) Navigator.pop(ctx);
                    _refreshAllData();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showCustomerHistoryDialog(Map<String, dynamic> customer) async {
    final vehicles = (customer['vehicles'] as List<dynamic>?) ?? [];
    final jobs = (customer['jobCards'] as List<dynamic>?) ?? [];

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Vehicle & Service History — ${customer['name'] ?? ''}'),
              OutlinedButton.icon(
                onPressed: () {
                  final firstReg = vehicles.isNotEmpty ? vehicles.first['registrationNo'] : 'your vehicle';
                  final msg = 'Hello ${customer['name']}, this is a courtesy reminder from ${_workshopSettings['name'] ?? 'MechanicHQ'} that $firstReg is due for its scheduled routine maintenance service.';
                  _launchWhatsAppMessage(customer['phone']?.toString() ?? '', msg);
                },
                icon: const Icon(Icons.chat_outlined, size: 16, color: Colors.green),
                label: const Text('Send WhatsApp Service Reminder', style: TextStyle(color: Colors.green)),
              ),
            ],
          ),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Phone: ${customer['phone'] ?? '-'}  •  Registered Vehicles: ${vehicles.length}  •  Total Visits: ${jobs.length}',
                      style: const TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.w600)),
                  const Divider(height: 24),
                  if (jobs.isEmpty)
                    const Padding(padding: EdgeInsets.all(24), child: Text('No job cards recorded for this customer yet.'))
                  else
                    ...jobs.map((j) {
                      final v = j['vehicle'] ?? {};
                      final ests = (j['estimates'] as List<dynamic>?) ?? [];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          title: Text(
                            '${j['jobNumber'] ?? 'Job'} — ${v['registrationNo'] ?? ''} (${v['make'] ?? ''} ${v['model'] ?? ''})',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Work: ${j['workRequested'] ?? '-'}  •  Technician: ${j['technician'] ?? '-'}'),
                              Text('Odometer: ${j['odometer'] ?? '-'} km  •  Date: ${_formatDateShort(j['createdAt'])}  •  Estimates: ${ests.length}'),
                            ],
                          ),
                          trailing: Chip(
                            label: Text(_statusLabel(j['status'] ?? 'IN_PROGRESS'), style: const TextStyle(fontSize: 11)),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          ],
        );
      },
    );
  }

  Future<void> _showAppointmentDialog() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final regCtrl = TextEditingController();
    final vehicleCtrl = TextEditingController();
    final serviceCtrl = TextEditingController(text: 'Routine Service & Inspection');
    final techCtrl = TextEditingController();
    String bay = 'Bay 1';
    DateTime scheduledAt = DateTime.now().add(const Duration(days: 1));

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              title: const Text('Book Customer Appointment & Workshop Bay'),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(child: TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Customer Name *', border: OutlineInputBorder()))),
                        const SizedBox(width: 12),
                        Expanded(child: TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Phone Number', border: OutlineInputBorder()))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: regCtrl, decoration: const InputDecoration(labelText: 'Reg No (e.g. KDA 456B)', border: OutlineInputBorder()))),
                        const SizedBox(width: 12),
                        Expanded(child: TextField(controller: vehicleCtrl, decoration: const InputDecoration(labelText: 'Make / Model', border: OutlineInputBorder()))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(controller: serviceCtrl, decoration: const InputDecoration(labelText: 'Service Type', border: OutlineInputBorder())),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: bay,
                            decoration: const InputDecoration(labelText: 'Assigned Bay', border: OutlineInputBorder()),
                            items: ['Bay 1', 'Bay 2', 'Bay 3', 'Lift 1', 'Lift 2']
                                .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                                .toList(),
                            onChanged: (v) => setModalState(() => bay = v ?? 'Bay 1'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: ctx,
                                initialDate: scheduledAt,
                                firstDate: DateTime.now().subtract(const Duration(days: 1)),
                                lastDate: DateTime(2030),
                              );
                              if (picked != null) setModalState(() => scheduledAt = picked);
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(labelText: 'Scheduled Date', border: OutlineInputBorder()),
                              child: Text(_formatDateShort(scheduledAt.toIso8601String())),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
                  onPressed: () async {
                    await http.post(
                      Uri.parse('$_baseUrl/appointments'),
                      headers: {'Content-Type': 'application/json'},
                      body: json.encode({
                        'customerName': nameCtrl.text.trim(),
                        'phone': phoneCtrl.text.trim(),
                        'registrationNo': regCtrl.text.trim(),
                        'makeModel': vehicleCtrl.text.trim(),
                        'serviceType': serviceCtrl.text.trim(),
                        'assignedBay': bay,
                        'technician': techCtrl.text.trim().isEmpty ? 'Unassigned' : techCtrl.text.trim(),
                        'scheduledAt': scheduledAt.toIso8601String(),
                      }),
                    );
                    if (mounted) Navigator.pop(ctx);
                    _refreshAllData();
                  },
                  child: const Text('Book Appointment'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showExpenseDialog() async {
    String category = 'Workshop Consumables';
    final descCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    String mode = 'CASH';

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              title: const Text('Record Workshop Operating Expense'),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: category,
                      decoration: const InputDecoration(labelText: 'Expense Category', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'Workshop Consumables', child: Text('Workshop Consumables & Oils')),
                        DropdownMenuItem(value: 'Rent & Utilities', child: Text('Rent, Electricity & Water')),
                        DropdownMenuItem(value: 'Casual Labour & Allowances', child: Text('Casual Labour & Technician Allowances')),
                        DropdownMenuItem(value: 'Tools & Equipment', child: Text('Tools & Equipment Maintenance')),
                        DropdownMenuItem(value: 'Transport & Parts Delivery', child: Text('Transport & Parts Delivery')),
                      ],
                      onChanged: (v) => setModalState(() => category = v ?? 'Workshop Consumables'),
                    ),
                    const SizedBox(height: 12),
                    TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder())),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: amountCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Amount (KSH)', border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: mode,
                            decoration: const InputDecoration(labelText: 'Paid Via', border: OutlineInputBorder()),
                            items: const [
                              DropdownMenuItem(value: 'CASH', child: Text('Cash')),
                              DropdownMenuItem(value: 'MPESA', child: Text('M-Pesa')),
                              DropdownMenuItem(value: 'BANK', child: Text('Bank')),
                            ],
                            onChanged: (v) => setModalState(() => mode = v ?? 'CASH'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
                  onPressed: () async {
                    await http.post(
                      Uri.parse('$_baseUrl/expenses'),
                      headers: {'Content-Type': 'application/json'},
                      body: json.encode({
                        'category': category,
                        'description': descCtrl.text.trim(),
                        'amount': double.tryParse(amountCtrl.text.trim()) ?? 0,
                        'paymentMode': mode,
                      }),
                    );
                    if (mounted) Navigator.pop(ctx);
                    _refreshAllData();
                  },
                  child: const Text('Save Expense'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ==========================================
  // MAIN SCAFFOLD BUILD
  // ==========================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSidebar(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTopHeader(),
                  const SizedBox(height: 24),
                  _buildStatsRow(),
                  const SizedBox(height: 24),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: _buildMainWorkspaceSection(),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        flex: 1,
                        child: _buildRightSidePanels(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 250,
      color: const Color(0xFF1E2329),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Row(
              children: [
                const Icon(Icons.settings, color: Colors.blueAccent, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _workshopSettings['name']?.toString().split(' ').first ?? 'MechanicHQ',
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sidebarItem(Icons.dashboard, 'Dashboard', tabTarget: 'Current Job Cards'),
                  _sidebarItem(Icons.directions_car, 'Job Cards', tabTarget: 'Current Job Cards'),
                  _sidebarItem(Icons.calendar_month, 'Appointments'),
                  _sidebarItem(Icons.inventory, 'Parts Catalog', tabTarget: 'Parts Catalog'),
                  _sidebarItem(Icons.receipt, 'Estimates', tabTarget: 'Estimates'),
                  _sidebarItem(Icons.request_quote, 'Invoices', tabTarget: 'Invoices'),
                  _sidebarItem(Icons.people, 'Customers'),
                  _sidebarItem(Icons.badge, 'Employees'),
                  _sidebarItem(Icons.bar_chart, 'Reports'),
                  const Divider(color: Colors.white12, height: 24),
                  _sidebarItem(Icons.settings, 'Settings'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _sidebarItem(IconData icon, String title, {String? tabTarget}) {
    final isActive = _activeSidebar == title;
    return Container(
      color: isActive ? Colors.white.withOpacity(0.1) : Colors.transparent,
      child: ListTile(
        leading: Icon(icon, color: isActive ? Colors.white : Colors.white70),
        title: Text(
          title,
          style: TextStyle(
            color: isActive ? Colors.white : Colors.white70,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24.0),
        onTap: () {
          setState(() {
            _activeSidebar = title;
            if (tabTarget != null) {
              _activeTab = tabTarget;
            }
          });
        },
      ),
    );
  }

  Widget _buildTopHeader() {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 12,
      children: [
        Text(
          _workshopSettings['name'] != null
              ? 'Manager View: ${_workshopSettings['name']}'
              : 'Manager View: Accounts & Workshop',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 260,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: TextField(
                controller: _topSearchController,
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val;
                    _searchController.text = val;
                  });
                },
                decoration: const InputDecoration(
                  icon: Icon(Icons.search, color: Colors.grey),
                  hintText: 'Search jobs, vehicles, customers...',
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              tooltip: 'Refresh Data from PostgreSQL',
              icon: const Icon(Icons.refresh, color: Color(0xFF2563EB)),
              onPressed: _refreshAllData,
            ),
            const SizedBox(width: 8),
            const CircleAvatar(backgroundColor: Colors.blueAccent, child: Text('AR', style: TextStyle(color: Colors.white))),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Shop Manager', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('Live Connected', style: TextStyle(fontSize: 12, color: Colors.green)),
              ],
            )
          ],
        )
      ],
    );
  }

  Widget _buildStatsRow() {
    final rev = (_dashboard['totalRevenue'] as num?)?.toDouble() ?? 0.0;
    final activeJobs = _dashboard['activeJobsCount'] ?? 0;
    final pendingEst = _dashboard['pendingEstimatesCount'] ?? 0;
    final lowStock = _dashboard['lowStockCount'] ?? 0;

    return Row(
      children: [
        _statCard(
          'Total Revenue',
          'KSH ${rev.toStringAsFixed(2)}',
          '↑ Paid & Approved',
          Colors.green,
          Icons.show_chart,
          Colors.blue,
          onPlusTap: () => setState(() {
            _activeSidebar = 'Invoices';
            _activeTab = 'Invoices';
          }),
        ),
        const SizedBox(width: 16),
        _statCard(
          'Active Jobs',
          '$activeJobs',
          '↑ Total Jobs: ${_dashboard['totalJobsCount'] ?? 0}',
          Colors.green,
          Icons.bar_chart,
          Colors.blue,
          onPlusTap: () => _showJobCardDialog(),
        ),
        const SizedBox(width: 16),
        _statCard(
          'Pending Estimates',
          '$pendingEst',
          '16% VAT Calculated',
          Colors.orange.shade800,
          Icons.show_chart,
          Colors.orange,
          onPlusTap: () => setState(() {
            _activeSidebar = 'Estimates';
            _activeTab = 'Estimates';
            _showEstimateCreator = true;
          }),
        ),
        const SizedBox(width: 16),
        _statCard(
          'Low Stock Items',
          '$lowStock',
          'Catalog Parts: ${_parts.length}',
          lowStock > 0 ? Colors.red : Colors.green,
          Icons.show_chart,
          Colors.deepOrange,
          onPlusTap: () => _showPartDialog(),
        ),
      ],
    );
  }

  Widget _statCard(
    String title,
    String value,
    String subtitle,
    Color color,
    IconData chartIcon,
    Color chartColor, {
    VoidCallback? onPlusTap,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: onPlusTap,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(4)),
                          child: const Icon(Icons.add, size: 12, color: Colors.green),
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(subtitle, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Icon(chartIcon, color: chartColor.withOpacity(0.5), size: 46),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // WORKSPACE SWITCHER (TABS & SIDEBAR VIEWS)
  // ==========================================
  Widget _buildMainWorkspaceSection() {
    if (_activeSidebar == 'Appointments') return _buildAppointmentsSection();
    if (_activeSidebar == 'Customers') return _buildCustomersSection();
    if (_activeSidebar == 'Employees') return _buildEmployeesSection();
    if (_activeSidebar == 'Reports') return _buildReportsSection();
    if (_activeSidebar == 'Settings') return _buildSettingsSection();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Interactive Tabs Row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildTabItem('Current Job Cards'),
                const SizedBox(width: 24),
                _buildTabItem('Parts Catalog'),
                const SizedBox(width: 24),
                _buildTabItem('Estimates'),
                const SizedBox(width: 24),
                _buildTabItem('Invoices'),
              ],
            ),
          ),
          const Divider(height: 32),
          if (_activeTab == 'Current Job Cards') _buildJobCardsTabContent(),
          if (_activeTab == 'Parts Catalog') _buildPartsCatalogTabContent(),
          if (_activeTab == 'Estimates') _buildEstimatesTabContent(),
          if (_activeTab == 'Invoices') _buildInvoicesTabContent(),
        ],
      ),
    );
  }

  Widget _buildTabItem(String text) {
    final isActive = _activeTab == text;
    return InkWell(
      onTap: () {
        setState(() {
          _activeTab = text;
        });
      },
      child: Container(
        padding: EdgeInsets.only(bottom: isActive ? 12 : 14),
        decoration: isActive
            ? const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFF2563EB), width: 2)),
              )
            : null,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 16,
            fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
            color: isActive ? const Color(0xFF1E3A8A) : Colors.black87,
          ),
        ),
      ),
    );
  }

  // ==========================================
  // TAB 1: CURRENT JOB CARDS
  // ==========================================
  Widget _buildJobCardsTabContent() {
    final rows = _filteredJobs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Filters Row
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            Container(
              width: 250,
              height: 40,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(6),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Filters (Name, Reg, Job ID...)',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            _topSearchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Status Filter Dropdown
                Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _statusFilter,
                      icon: const Icon(Icons.keyboard_arrow_down, size: 16),
                      items: const [
                        DropdownMenuItem(value: 'All', child: Text('Status: All', style: TextStyle(fontSize: 14))),
                        DropdownMenuItem(value: 'BOOKED', child: Text('1. Checked-In', style: TextStyle(fontSize: 14))),
                        DropdownMenuItem(value: 'INSPECTION', child: Text('2. Inspection', style: TextStyle(fontSize: 14))),
                        DropdownMenuItem(value: 'AWAITING_APPROVAL', child: Text('3. Awaiting Approval', style: TextStyle(fontSize: 14))),
                        DropdownMenuItem(value: 'IN_PROGRESS', child: Text('4. In Repair', style: TextStyle(fontSize: 14))),
                        DropdownMenuItem(value: 'WAITING', child: Text('5. Waiting Parts', style: TextStyle(fontSize: 14))),
                        DropdownMenuItem(value: 'QUALITY_CHECK', child: Text('6. Quality Check', style: TextStyle(fontSize: 14))),
                        DropdownMenuItem(value: 'READY', child: Text('7. Ready for Pickup', style: TextStyle(fontSize: 14))),
                        DropdownMenuItem(value: 'COMPLETED', child: Text('Delivered / Closed', style: TextStyle(fontSize: 14))),
                      ],
                      onChanged: (val) => setState(() => _statusFilter = val ?? 'All'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Technician Filter Dropdown
                Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _availableTechnicians.contains(_technicianFilter) ? _technicianFilter : 'All',
                      icon: const Icon(Icons.keyboard_arrow_down, size: 16),
                      items: _availableTechnicians
                          .map((t) => DropdownMenuItem(
                                value: t,
                                child: Text(t == 'All' ? 'Technician: All' : t, style: const TextStyle(fontSize: 14)),
                              ))
                          .toList(),
                      onChanged: (val) => setState(() => _technicianFilter = val ?? 'All'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => _showJobCardDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New Job'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            if (_isLoading) {
              return const Center(child: Padding(padding: EdgeInsets.all(40.0), child: CircularProgressIndicator()));
            }
            if (rows.isEmpty) {
              return Container(
                width: constraints.maxWidth,
                padding: const EdgeInsets.symmetric(vertical: 48),
                alignment: Alignment.center,
                child: Column(
                  children: [
                    const Icon(Icons.car_repair, size: 48, color: Colors.grey),
                    const SizedBox(height: 12),
                    const Text('No Job Cards match your filter (or database is empty).', style: TextStyle(color: Colors.grey, fontSize: 15)),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => _showJobCardDialog(),
                      icon: const Icon(Icons.add),
                      label: const Text('Create First Job Card'),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
                    ),
                  ],
                ),
              );
            }
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: DataTable(
                  headingRowColor: MaterialStateProperty.all(Colors.grey.shade50),
                  columnSpacing: 12,
                  horizontalMargin: 8,
                  dataRowMinHeight: 52,
                  dataRowMaxHeight: 52,
                  columns: const [
                    DataColumn(label: Text('Job ID', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Customer', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Vehicle', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Service', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Technician', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Priority', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Due Date', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('')),
                  ],
                  rows: rows.map((job) {
                    final jobNo = job['jobNumber'] ?? job['id'].toString().substring(0, 8).toUpperCase();
                    final customerName = job['customer']?['name'] ?? 'Unknown';
                    final make = job['vehicle']?['make'] ?? '';
                    final model = job['vehicle']?['model'] ?? '';
                    final reg = job['vehicle']?['registrationNo'] ?? '';
                    final vehicleDisplay = '$make $model ($reg)'.trim();
                    final service = job['workRequested'] ?? 'General Service';
                    final technician = job['technician'] ?? 'Unassigned';
                    final rawStatus = job['status'] ?? 'IN_PROGRESS';
                    final priority = job['priority'] ?? 'Medium';
                    final dueDateStr = _formatDateShort(job['dueDate'] ?? job['createdAt']);

                    return _buildJobDataRow(
                      job: Map<String, dynamic>.from(job),
                      id: jobNo,
                      customer: customerName,
                      vehicle: vehicleDisplay,
                      service: service,
                      technician: technician,
                      statusLabel: _statusLabel(rawStatus),
                      statusColor: _statusColor(rawStatus),
                      priority: priority,
                      priorityColor: _priorityColor(priority),
                      dueDate: dueDateStr,
                    );
                  }).toList(),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  DataRow _buildJobDataRow({
    required Map<String, dynamic> job,
    required String id,
    required String customer,
    required String vehicle,
    required String service,
    required String technician,
    required String statusLabel,
    required Color statusColor,
    required String priority,
    required Color priorityColor,
    required String dueDate,
  }) {
    return DataRow(
      cells: [
        DataCell(Text(id, style: const TextStyle(fontWeight: FontWeight.bold))),
        DataCell(Text(customer)),
        DataCell(Text(vehicle)),
        DataCell(Text(service)),
        DataCell(Text(technician)),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: priorityColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Text(priority, style: TextStyle(color: priorityColor, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ),
        DataCell(Text(dueDate)),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton(
                onPressed: () => _showViewJobDialog(job),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 32),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                child: const Text('View', style: TextStyle(color: Colors.black87, fontSize: 12)),
              ),
              const SizedBox(width: 6),
              OutlinedButton(
                onPressed: () => _showJobCardDialog(existingJob: job),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 32),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                child: const Text('Edit', style: TextStyle(color: Colors.black87, fontSize: 12)),
              ),
              const SizedBox(width: 6),
              OutlinedButton.icon(
                onPressed: () => InvoicePdfService.showJobCardPreviewModal(
                  context: context,
                  workshopSettings: _workshopSettings,
                  job: job,
                ),
                icon: const Icon(Icons.print_outlined, size: 15, color: Color(0xFF1D4ED8)),
                label: const Text('Customer Copy', style: TextStyle(color: Color(0xFF1D4ED8), fontSize: 12, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 32),
                  side: const BorderSide(color: Color(0xFF93C5FD)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================
  // TAB 2: PARTS CATALOG
  // ==========================================
  Widget _buildPartsCatalogTabContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Workshop Parts Inventory (${_parts.length} items)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _showStockLedgerHistoryDialog,
                  icon: const Icon(Icons.history_edu, size: 17),
                  label: const Text('Stock Ledger History'),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: () => _showPartDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Part'),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_parts.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text('No parts in catalog yet. Click "+ Add Part" to add inventory.', style: TextStyle(color: Colors.grey))),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: DataTable(
                    headingRowColor: MaterialStateProperty.all(Colors.grey.shade50),
                    columns: const [
                      DataColumn(label: Text('Part Number', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Description & Brand', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Cost / Retail (KSH)', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Stock Qty', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Stock Status', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                    rows: _parts.map((part) {
                      final stock = (part['stockQuantity'] as num?)?.toInt() ?? 0;
                      final reorder = (part['reorderLevel'] as num?)?.toInt() ?? 5;
                      final isLow = stock <= reorder;
                      final cost = (part['costPrice'] as num?)?.toDouble() ?? 0.0;
                      final retail = (part['unitPrice'] as num?)?.toDouble() ?? 0.0;
                      final brand = part['brand']?.toString() ?? '';
                      return DataRow(
                        cells: [
                          DataCell(Text(part['partNumber'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold))),
                          DataCell(Text('${part['description'] ?? ''}${brand.isNotEmpty ? ' ($brand)' : ''}')),
                          DataCell(Text('${cost.toStringAsFixed(0)} / ${retail.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w600))),
                          DataCell(Text('$stock')),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isLow ? Colors.red.withOpacity(0.1) : Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                isLow ? 'Low Stock' : 'In Stock',
                                style: TextStyle(color: isLow ? Colors.red : Colors.green, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => _showStockMovementDialog(Map<String, dynamic>.from(part)),
                                  icon: const Icon(Icons.inventory_2_outlined, size: 14),
                                  label: const Text('+ Stock', style: TextStyle(fontSize: 12)),
                                ),
                                const SizedBox(width: 6),
                                OutlinedButton(
                                  onPressed: () => _showPartDialog(existingPart: Map<String, dynamic>.from(part)),
                                  child: const Text('Edit', style: TextStyle(fontSize: 12)),
                                ),
                                const SizedBox(width: 6),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                                  onPressed: () async {
                                    await http.delete(Uri.parse('$_baseUrl/parts/${part['id']}'));
                                    _refreshAllData();
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  // ==========================================
  // TAB 3: ESTIMATES (20% Discount + 16% VAT)
  // ==========================================
  Widget _buildEstimatesTabContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Workshop Estimates (${_estimates.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ElevatedButton.icon(
              onPressed: () => setState(() => _showEstimateCreator = !_showEstimateCreator),
              icon: Icon(_showEstimateCreator ? Icons.close : Icons.add, size: 18),
              label: Text(_showEstimateCreator ? 'Close Estimate Form' : 'New Estimate'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
            ),
          ],
        ),
        if (_showEstimateCreator) ...[
          const SizedBox(height: 16),
          EstimateForm(
            initialJobCardId: _preselectedJobIdForEstimate,
            onSaved: () {
              setState(() => _showEstimateCreator = false);
              _refreshAllData();
            },
          ),
        ],
        const SizedBox(height: 16),
        if (_estimates.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text('No estimates created yet. Click "+ New Estimate" to calculate parts, discount, and 16% VAT.', style: TextStyle(color: Colors.grey))),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: DataTable(
                    headingRowColor: MaterialStateProperty.all(Colors.grey.shade50),
                    columns: const [
                      DataColumn(label: Text('Customer / Vehicle', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Subtotal', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Discount', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('VAT (16%)', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Final Total', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                    rows: _estimates.map((est) {
                      final job = est['jobCard'] ?? {};
                      final customer = job['customer']?['name'] ?? 'Customer';
                      final reg = job['vehicle']?['registrationNo'] ?? '';
                      final subtotal = (est['subtotal'] as num).toDouble();
                      final discRate = (est['discountRate'] as num).toDouble();
                      final afterDisc = subtotal * (1 - discRate / 100);
                      final vat = afterDisc * 0.16;
                      final total = (est['total'] as num).toDouble();
                      final hasInvoice = est['invoice'] != null;

                      return DataRow(
                        cells: [
                          DataCell(Text('$customer ($reg)', style: const TextStyle(fontWeight: FontWeight.bold))),
                          DataCell(Text('KSH ${subtotal.toStringAsFixed(2)}')),
                          DataCell(Text('${discRate.toStringAsFixed(0)}%')),
                          DataCell(Text('KSH ${vat.toStringAsFixed(2)}')),
                          DataCell(Text('KSH ${total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)))),
                          DataCell(Chip(label: Text(est['status'] ?? 'DRAFT', style: const TextStyle(fontSize: 11)))),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!hasInvoice)
                                  ElevatedButton.icon(
                                    onPressed: () async {
                                      await http.post(
                                        Uri.parse('$_baseUrl/invoices'),
                                        headers: {'Content-Type': 'application/json'},
                                        body: json.encode({'estimateId': est['id'], 'paymentStatus': 'UNPAID', 'paymentMode': 'MPESA'}),
                                      );
                                      await _refreshAllData();
                                      setState(() => _activeTab = 'Invoices');
                                    },
                                    icon: const Icon(Icons.request_quote, size: 14),
                                    label: const Text('Convert to Invoice', style: TextStyle(fontSize: 12)),
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                                  )
                                else
                                  const Text('Invoiced ✓', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: () => InvoicePdfService.showPreviewModal(
                                    context: context,
                                    workshopSettings: _workshopSettings,
                                    estimate: Map<String, dynamic>.from(est),
                                    isInvoice: false,
                                  ),
                                  icon: const Icon(Icons.picture_as_pdf, size: 15, color: Color(0xFF1D4ED8)),
                                  label: const Text('A4 PDF / Print', style: TextStyle(fontSize: 12, color: Color(0xFF1D4ED8))),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  tooltip: 'Delete Estimate',
                                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                                  onPressed: () async {
                                    await http.delete(Uri.parse('$_baseUrl/estimates/${est['id']}'));
                                    _refreshAllData();
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  // ==========================================
  // TAB 4: INVOICES (Deposits, Partial Payments, M-Pesa Ref & Pay-Later)
  // ==========================================
  Widget _buildInvoicesTabContent() {
    if (_invoices.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text('No invoices generated yet. Convert an Estimate to an Invoice from the Estimates tab.', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              headingRowColor: MaterialStateProperty.all(Colors.grey.shade50),
              columns: const [
                DataColumn(label: Text('Invoice #', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Customer & Vehicle', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Total / Balance (KSH)', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Payment Status', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Mode & M-Pesa Ref', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Record Payment', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('A4 Invoice & PDF', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: _invoices.map((inv) {
                final est = inv['estimate'] ?? {};
                final job = est['jobCard'] ?? {};
                final customer = job['customer']?['name'] ?? 'Customer';
                final phone = job['customer']?['phone']?.toString() ?? '';
                final reg = job['vehicle']?['registrationNo'] ?? '';
                final total = (est['total'] as num?)?.toDouble() ?? 0.0;
                final payStatus = inv['paymentStatus'] ?? 'UNPAID';
                final paid = (inv['amountPaid'] as num?)?.toDouble() ?? (payStatus == 'PAID' ? total : 0.0);
                final bal = (inv['balanceDue'] as num?)?.toDouble() ?? (total - paid).clamp(0.0, total);
                final mpesaRef = inv['mpesaReceiptNo']?.toString() ?? '';

                return DataRow(
                  cells: [
                    DataCell(Text('INV-${inv['id'].toString().substring(0, 6).toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.bold))),
                    DataCell(Text('$customer ($reg)')),
                    DataCell(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('KSH ${total.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          if (paid > 0 && bal > 0)
                            Text('Bal: KSH ${bal.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    DataCell(
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: payStatus == 'PAID'
                              ? Colors.green.withOpacity(0.1)
                              : (payStatus == 'PARTIAL' || payStatus == 'PAY_LATER')
                                  ? Colors.orange.withOpacity(0.1)
                                  : Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          payStatus,
                          style: TextStyle(
                            color: payStatus == 'PAID'
                                ? Colors.green
                                : (payStatus == 'PARTIAL' || payStatus == 'PAY_LATER')
                                    ? Colors.orange.shade800
                                    : Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    DataCell(Text('${inv['paymentMode'] ?? 'N/A'}${mpesaRef.isNotEmpty ? ' ($mpesaRef)' : ''}')),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (payStatus != 'PAID') ...[
                            ElevatedButton.icon(
                              onPressed: () => _showRecordPaymentDialog(Map<String, dynamic>.from(inv)),
                              icon: const Icon(Icons.payments_outlined, size: 14),
                              label: const Text('Pay / Deposit', style: TextStyle(fontSize: 12)),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
                            ),
                            const SizedBox(width: 6),
                            OutlinedButton(
                              onPressed: () async {
                                await http.put(
                                  Uri.parse('$_baseUrl/invoices/${inv['id']}'),
                                  headers: {'Content-Type': 'application/json'},
                                  body: json.encode({'paymentStatus': 'PAID', 'paymentMode': 'MPESA'}),
                                );
                                _refreshAllData();
                              },
                              child: const Text('Full M-Pesa', style: TextStyle(fontSize: 12)),
                            ),
                          ] else
                            const Text('Paid in Full ✓', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () => InvoicePdfService.showPreviewModal(
                              context: context,
                              workshopSettings: _workshopSettings,
                              estimate: Map<String, dynamic>.from(est),
                              invoice: Map<String, dynamic>.from(inv),
                              isInvoice: true,
                            ),
                            icon: const Icon(Icons.visibility, size: 15),
                            label: const Text('Preview A4', style: TextStyle(fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F172A),
                              foregroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            tooltip: 'Print A4 Invoice',
                            icon: const Icon(Icons.print, color: Color(0xFF2563EB), size: 20),
                            onPressed: () => InvoicePdfService.printDocument(
                              workshopSettings: _workshopSettings,
                              estimate: Map<String, dynamic>.from(est),
                              invoice: Map<String, dynamic>.from(inv),
                              isInvoice: true,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Export / Download A4 PDF',
                            icon: const Icon(Icons.picture_as_pdf, color: Colors.redAccent, size: 20),
                            onPressed: () => InvoicePdfService.exportPdfFile(
                              workshopSettings: _workshopSettings,
                              estimate: Map<String, dynamic>.from(est),
                              invoice: Map<String, dynamic>.from(inv),
                              isInvoice: true,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Send WhatsApp Invoice Summary',
                            icon: const Icon(Icons.chat_outlined, color: Colors.green, size: 20),
                            onPressed: () {
                              final msg = 'Hello $customer, your invoice INV-${inv['id'].toString().substring(0, 6).toUpperCase()} for $reg at ${_workshopSettings['name'] ?? 'MechanicHQ'} is KSH ${total.toStringAsFixed(0)} (Paid: KSH ${paid.toStringAsFixed(0)}, Balance Due: KSH ${bal.toStringAsFixed(0)}). Thank you!';
                              _launchWhatsAppMessage(phone, msg);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  // ==========================================
  // SIDEBAR SECTIONS: APPOINTMENTS, CUSTOMERS, EMPLOYEES, REPORTS, SETTINGS
  // ==========================================
  Widget _buildAppointmentsSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Appointments & Bay Schedule (${_appointments.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ElevatedButton.icon(
                onPressed: _showAppointmentDialog,
                icon: const Icon(Icons.calendar_month, size: 18),
                label: const Text('+ Book Appointment'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
              ),
            ],
          ),
          const Divider(height: 24),
          if (_appointments.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('No appointments scheduled yet. Click "+ Book Appointment" to reserve a bay or mechanic.')),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Scheduled Date', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Customer', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Vehicle Reg', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Service Type', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Bay / Lift', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: _appointments.map((a) {
                  final status = a['status'] ?? 'SCHEDULED';
                  return DataRow(
                    cells: [
                      DataCell(Text(_formatDate(a['scheduledAt']))),
                      DataCell(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(a['customerName'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            if ((a['customerPhone'] ?? '').toString().isNotEmpty)
                              Text(a['customerPhone'].toString(), style: const TextStyle(fontSize: 11, color: Colors.black54)),
                          ],
                        ),
                      ),
                      DataCell(Text(a['registrationNo'] ?? '-', style: const TextStyle(fontWeight: FontWeight.w600))),
                      DataCell(Text(a['serviceType'] ?? '-')),
                      DataCell(Text(a['bayNumber'] ?? 'Unassigned')),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: status == 'ARRIVED' ? Colors.green.shade50 : Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            status.toString(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: status == 'ARRIVED' ? Colors.green.shade800 : Colors.blue.shade800,
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton.icon(
                              onPressed: () async {
                                await http.put(
                                  Uri.parse('$_baseUrl/appointments/${a['id']}'),
                                  headers: {'Content-Type': 'application/json'},
                                  body: json.encode({'status': 'ARRIVED'}),
                                );
                                _refreshAllData();
                                _showJobCardDialog();
                              },
                              icon: const Icon(Icons.assignment_add, size: 15, color: Color(0xFF2563EB)),
                              label: const Text('Convert to Job Card', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                            if ((a['customerPhone'] ?? '').toString().isNotEmpty)
                              IconButton(
                                tooltip: 'WhatsApp Appointment Reminder',
                                icon: const Icon(Icons.chat, size: 16, color: Color(0xFF16A34A)),
                                onPressed: () {
                                  _launchWhatsAppMessage(
                                    a['customerPhone'].toString(),
                                    'Hello ${a['customerName']}, reminder of your ${a['serviceType']} appointment for ${a['registrationNo']} on ${_formatDate(a['scheduledAt'])} (${a['bayNumber'] ?? 'Workshop'}).',
                                  );
                                },
                              ),
                            IconButton(
                              tooltip: 'Delete Appointment',
                              icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                              onPressed: () async {
                                await http.delete(Uri.parse('$_baseUrl/appointments/${a['id']}'));
                                _refreshAllData();
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCustomersSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Registered Customers & Vehicle History (${_customers.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ElevatedButton.icon(
                onPressed: () => _showJobCardDialog(),
                icon: const Icon(Icons.person_add, size: 18),
                label: const Text('New Customer & Job'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
              ),
            ],
          ),
          const Divider(height: 24),
          if (_customers.isEmpty)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No customers recorded yet.')))
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Customer Name', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Phone', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Vehicles (Reg & Make)', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Total Jobs', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Service History & Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: _customers.map((c) {
                  final vehicles = (c['vehicles'] as List<dynamic>?) ?? [];
                  final jobs = (c['jobCards'] as List<dynamic>?) ?? [];
                  return DataRow(
                    cells: [
                      DataCell(Text(c['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text(c['phone'] ?? '-')),
                      DataCell(
                        Text(
                          vehicles.map((v) => '${v['registrationNo']} (${v['make']} ${v['model']})').join(', '),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      DataCell(Text('${jobs.length}', style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () => _showCustomerHistoryDialog(Map<String, dynamic>.from(c)),
                              icon: const Icon(Icons.history, size: 15),
                              label: const Text('Service History', style: TextStyle(fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.indigo.shade50,
                                foregroundColor: Colors.indigo.shade800,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if ((c['phone'] ?? '').toString().isNotEmpty)
                              IconButton(
                                tooltip: 'WhatsApp Service Reminder',
                                icon: const Icon(Icons.chat, size: 17, color: Color(0xFF16A34A)),
                                onPressed: () {
                                  final firstReg = vehicles.isNotEmpty ? vehicles.first['registrationNo'] : 'your vehicle';
                                  _launchWhatsAppMessage(
                                    c['phone'].toString(),
                                    'Hello ${c['name']}, friendly reminder from ${_workshopSettings['name'] ?? 'our Auto Workshop'} that $firstReg may be due for periodic maintenance/service. Reply to book a bay!',
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmployeesSection() {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    String selectedRole = 'MECHANIC';

    return StatefulBuilder(
      builder: (context, setEmpState) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Workshop Technicians, Service Advisors & Staff', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Staff / Technician Name', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: emailCtrl,
                      decoration: const InputDecoration(labelText: 'Email Address', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: DropdownButtonFormField<String>(
                      value: selectedRole,
                      decoration: const InputDecoration(labelText: 'Role', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'MECHANIC', child: Text('MECHANIC')),
                        DropdownMenuItem(value: 'ADVISOR', child: Text('SERVICE ADVISOR')),
                        DropdownMenuItem(value: 'MANAGER', child: Text('MANAGER')),
                        DropdownMenuItem(value: 'STOREKEEPER', child: Text('STOREKEEPER')),
                        DropdownMenuItem(value: 'CASHIER', child: Text('CASHIER')),
                      ],
                      onChanged: (v) => setEmpState(() => selectedRole = v ?? 'MECHANIC'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () async {
                      if (nameCtrl.text.trim().isEmpty) return;
                      await http.post(
                        Uri.parse('$_baseUrl/employees'),
                        headers: {'Content-Type': 'application/json'},
                        body: json.encode({
                          'name': nameCtrl.text.trim(),
                          'email': emailCtrl.text.trim(),
                          'role': selectedRole,
                        }),
                      );
                      _refreshAllData();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add Staff'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                    ),
                  ),
                ],
              ),
              const Divider(height: 32),
              if (_employees.isEmpty)
                const Padding(padding: EdgeInsets.all(24), child: Text('No employees added yet. Add technicians above so they appear in Job Card assignments.'))
              else
                DataTable(
                  columns: const [
                    DataColumn(label: Text('Name', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Email', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Role', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                  rows: _employees.map((e) {
                    return DataRow(
                      cells: [
                        DataCell(Text(e['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold))),
                        DataCell(Text(e['email'] ?? '')),
                        DataCell(Chip(label: Text(e['role'] ?? 'MECHANIC', style: const TextStyle(fontSize: 11)))),
                        DataCell(
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () async {
                              await http.delete(Uri.parse('$_baseUrl/employees/${e['id']}'));
                              _refreshAllData();
                            },
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildReportsSection() {
    final rev = (_dashboard['totalRevenue'] as num?)?.toDouble() ?? 0.0;
    final billed = (_dashboard['totalBilled'] as num?)?.toDouble() ?? rev;
    final outstanding = (_dashboard['outstandingBalance'] as num?)?.toDouble() ?? 0.0;
    final partsCostCogs = ((_dashboard['partsCostTotal'] ?? _dashboard['partsCostCogs']) as num?)?.toDouble() ?? 0.0;
    final totalExpenses = ((_dashboard['expensesTotal'] ?? _dashboard['totalExpenses']) as num?)?.toDouble() ?? 0.0;
    final netProfit = (_dashboard['netProfit'] as num?)?.toDouble() ?? (rev - partsCostCogs - totalExpenses);
    final labourRev = (_dashboard['labourRevenue'] as num?)?.toDouble() ?? 0.0;
    final partsRev = (_dashboard['partsRevenue'] as num?)?.toDouble() ?? 0.0;
    final stockValCost = (_dashboard['stockValuationCost'] as num?)?.toDouble() ?? 0.0;
    final stockValRetail = (_dashboard['stockValuationRetail'] as num?)?.toDouble() ?? 0.0;
    final mechProd = (_dashboard['mechanicProductivity'] as List<dynamic>?) ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top Financial P&L Cards
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Workshop Profit & Loss (P&L) & Financial Analytics', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ElevatedButton.icon(
                    onPressed: _showExpenseDialog,
                    icon: const Icon(Icons.receipt_long, size: 18),
                    label: const Text('+ Record Workshop Expense'),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEA580C), foregroundColor: Colors.white),
                  ),
                ],
              ),
              const Divider(height: 24),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _pnlCard('Collected Revenue', 'KSH ${rev.toStringAsFixed(0)}', 'Total Billed: KSH ${billed.toStringAsFixed(0)}', Colors.blue.shade700, Colors.blue.shade50),
                  _pnlCard('Spare Parts COGS', 'KSH ${partsCostCogs.toStringAsFixed(0)}', 'Buying cost of parts sold', Colors.orange.shade800, Colors.orange.shade50),
                  _pnlCard('Workshop Expenses', 'KSH ${totalExpenses.toStringAsFixed(0)}', '${_expenses.length} recorded expenses', Colors.red.shade700, Colors.red.shade50),
                  _pnlCard('True Net Profit', 'KSH ${netProfit.toStringAsFixed(0)}', 'Revenue - COGS - Expenses', netProfit >= 0 ? Colors.green.shade800 : Colors.red.shade900, netProfit >= 0 ? Colors.green.shade50 : Colors.red.shade50),
                  _pnlCard('Outstanding Debtors', 'KSH ${outstanding.toStringAsFixed(0)}', 'Unpaid / Partial Invoices', Colors.purple.shade800, Colors.purple.shade50),
                ],
              ),
              const SizedBox(height: 24),
              _summaryRow('Labour Charges Revenue (Estimates & Repairs)', 'KSH ${labourRev.toStringAsFixed(2)}'),
              _summaryRow('Spare Parts Sales Revenue', 'KSH ${partsRev.toStringAsFixed(2)}'),
              _summaryRow('Inventory Stock Valuation (At Buying Cost)', 'KSH ${stockValCost.toStringAsFixed(2)}'),
              _summaryRow('Inventory Stock Valuation (At Retail Selling Price)', 'KSH ${stockValRetail.toStringAsFixed(2)}'),
              _summaryRow('Total Job Cards / Active / Completed', '${_dashboard['totalJobsCount'] ?? 0} Total • ${_dashboard['activeJobsCount'] ?? 0} Active • ${_dashboard['completedJobsCount'] ?? 0} Completed'),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Mechanic Productivity & Turnaround Table
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Mechanic Productivity & Turnaround Performance', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Divider(height: 20),
              if (mechProd.isEmpty)
                const Text('No technicians assigned to jobs yet.', style: TextStyle(color: Colors.grey))
              else
                DataTable(
                  columns: const [
                    DataColumn(label: Text('Technician', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Role', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Assigned Jobs', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Completed Jobs', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Est. Hours Logged', style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                  rows: mechProd.map((m) {
                    return DataRow(
                      cells: [
                        DataCell(Text((m['technician'] ?? m['name'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.bold))),
                        DataCell(Text((m['role'] ?? 'MECHANIC').toString())),
                        DataCell(Text('${m['totalJobs'] ?? m['assignedJobs'] ?? 0}')),
                        DataCell(Text('${m['completedJobs'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green))),
                        DataCell(Text('${m['estimatedHours'] ?? m['totalEstimatedHours'] ?? 0} hrs')),
                      ],
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // Workshop Expenses Ledger
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Workshop Operating Expenses (${_expenses.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  TextButton.icon(
                    onPressed: _showExpenseDialog,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Expense'),
                  ),
                ],
              ),
              const Divider(height: 20),
              if (_expenses.isEmpty)
                const Text('No workshop expenses recorded yet.', style: TextStyle(color: Colors.grey))
              else
                DataTable(
                  columns: const [
                    DataColumn(label: Text('Date', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Category', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Description', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Amount (KSH)', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                  rows: _expenses.map((e) {
                    return DataRow(
                      cells: [
                        DataCell(Text(_formatDate(e['incurredAt']))),
                        DataCell(Chip(label: Text(e['category'] ?? 'GENERAL', style: const TextStyle(fontSize: 11)))),
                        DataCell(Text(e['description'] ?? '')),
                        DataCell(Text('KSH ${((e['amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red))),
                        DataCell(
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                            onPressed: () async {
                              await http.delete(Uri.parse('$_baseUrl/expenses/${e['id']}'));
                              _refreshAllData();
                            },
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _pnlCard(String title, String value, String subtitle, Color textColor, Color bgColor) {
    return Container(
      width: 210,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: textColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: textColor)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: textColor)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.black54)),
        ],
      ),
    );
  }

  Widget _buildSettingsSection() {
    final nameCtrl = TextEditingController(text: _workshopSettings['name'] ?? '');
    final addressCtrl = TextEditingController(text: _workshopSettings['address'] ?? '');
    final pinCtrl = TextEditingController(text: _workshopSettings['taxPin'] ?? '');

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Workshop Settings (Tenant Profile)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Workshop Name', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: addressCtrl, decoration: const InputDecoration(labelText: 'Workshop Address', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: pinCtrl, decoration: const InputDecoration(labelText: 'Tax / KRA PIN', border: OutlineInputBorder())),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () async {
              await http.put(
                Uri.parse('$_baseUrl/settings'),
                headers: {'Content-Type': 'application/json'},
                body: json.encode({
                  'name': nameCtrl.text.trim(),
                  'address': addressCtrl.text.trim(),
                  'taxPin': pinCtrl.text.trim(),
                }),
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(backgroundColor: Colors.green, content: Text('Workshop settings updated!')),
                );
              }
              _refreshAllData();
            },
            icon: const Icon(Icons.save),
            label: const Text('Save Workshop Settings'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  Future<void> _showStockLedgerHistoryDialog() async {
    List<dynamic> movements = [];
    try {
      final res = await http.get(Uri.parse('$_baseUrl/stock-movements'));
      if (res.statusCode == 200) {
        movements = json.decode(res.body);
      }
    } catch (_) {}

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Spare Parts Stock Movement Ledger (Audit Trail)'),
        content: SizedBox(
          width: 720,
          height: 460,
          child: movements.isEmpty
              ? const Center(child: Text('No stock movements recorded yet.'))
              : ListView.separated(
                  itemCount: movements.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (_, idx) {
                    final m = movements[idx];
                    final type = (m['type'] ?? 'IN').toString();
                    final part = m['part'] ?? {};
                    final isOut = type == 'OUT' || type == 'ISSUED';
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isOut ? Colors.orange.shade50 : Colors.green.shade50,
                        child: Icon(
                          isOut ? Icons.call_made : Icons.call_received,
                          color: isOut ? Colors.orange.shade800 : Colors.green.shade800,
                          size: 18,
                        ),
                      ),
                      title: Text(
                        '${part['partNumber'] ?? 'Part'} • ${part['description'] ?? ''} (${isOut ? '-' : '+'}${m['quantity'] ?? 0})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      subtitle: Text('Reason: ${m['reason'] ?? '-'} • Date: ${_formatDate(m['createdAt'])}'),
                      trailing: Chip(
                        label: Text(type, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        backgroundColor: isOut ? Colors.orange.shade50 : Colors.green.shade50,
                      ),
                    );
                  },
                ),
        ),
        actions: [
          ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  // ==========================================
  // RIGHT SIDE PANELS (LIVE FROM DATABASE)
  // ==========================================
  Widget _buildRightSidePanels() {
    final activities = (_dashboard['recentActivities'] as List<dynamic>?) ?? [];
    final weeklyJobs = (_dashboard['weeklyJobs'] as List<dynamic>?) ?? [];
    final rev = (_dashboard['totalRevenue'] as num?)?.toDouble() ?? 0.0;
    final netProfit = (_dashboard['netProfit'] as num?)?.toDouble() ?? 0.0;
    final outstanding = (_dashboard['outstandingBalance'] as num?)?.toDouble() ?? 0.0;

    return Column(
      children: [
        _rightPanelBox(
          'Recent activities',
          activities.isEmpty
              ? const Text('No workshop activity yet. Create a Job Card to see live updates.', style: TextStyle(color: Colors.grey, fontSize: 13))
              : Column(
                  children: List.generate(activities.length, (index) {
                    final act = activities[index];
                    final isLast = index == activities.length - 1;
                    final type = act['type'] ?? 'job';
                    final dotColor = type == 'completed'
                        ? Colors.green
                        : type == 'estimate'
                            ? Colors.orange
                            : Colors.blue;
                    return _activityItem(
                      act['title']?.toString() ?? '',
                      act['subtitle']?.toString() ?? '',
                      _formatTimeAgo(act['timestamp']),
                      dotColor,
                      isLast,
                    );
                  }),
                ),
        ),
        const SizedBox(height: 24),
        _rightPanelBox(
          'Weekly Jobs',
          SizedBox(
            height: 150,
            width: double.infinity,
            child: CustomPaint(
              painter: _WeeklyJobsChartPainter(weeklyJobs),
            ),
          ),
        ),
        const SizedBox(height: 24),
        _rightPanelBox(
          'Workshop & Financial Summary',
          Column(
            children: [
              _summaryRow('Collected Revenue', 'KSH ${rev.toStringAsFixed(0)}'),
              _summaryRow('Net Profit (KSH)', netProfit.toStringAsFixed(0)),
              _summaryRow('Outstanding Balances', 'KSH ${outstanding.toStringAsFixed(0)}'),
              _summaryRow('Today / Week / Month', '${_dashboard['todayJobsCount'] ?? 0} / ${_dashboard['weekJobsCount'] ?? 0} / ${_dashboard['monthJobsCount'] ?? 0}'),
              _summaryRow('Overdue Jobs', '${_dashboard['overdueJobsCount'] ?? 0}'),
              _summaryRow('Upcoming Appointments', '${_dashboard['upcomingAppointmentsCount'] ?? _appointments.length}'),
              _summaryRow('Customers', '${_dashboard['customersCount'] ?? 0}'),
              _summaryRow('Low Stock Alerts', '${_dashboard['lowStockCount'] ?? 0}'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _rightPanelBox(String title, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _activityItem(String title, String subtitle, String time, Color dotColor, bool isLast) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 4, bottom: 4),
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.blue.shade50, width: 3),
                ),
              ),
              if (!isLast) Expanded(child: Container(width: 2, color: Colors.grey.shade300)),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.black87)),
                  const SizedBox(height: 4),
                  Text(time, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.black87)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ],
      ),
    );
  }
}

class _WeeklyJobsChartPainter extends CustomPainter {
  final List<dynamic> weeklyJobs;
  _WeeklyJobsChartPainter(this.weeklyJobs);

  @override
  void paint(Canvas canvas, Size size) {
    final days = weeklyJobs.isNotEmpty
        ? weeklyJobs
        : [
            {'day': 'M', 'count': 0},
            {'day': 'T', 'count': 0},
            {'day': 'W', 'count': 0},
            {'day': 'T', 'count': 0},
            {'day': 'F', 'count': 0},
            {'day': 'S', 'count': 0},
          ];

    int maxVal = 5;
    for (final d in days) {
      final c = (d['count'] as num?)?.toInt() ?? 0;
      if (c > maxVal) maxVal = c;
    }

    final chartBottom = size.height - 24;
    final chartTop = 10.0;
    final chartHeight = chartBottom - chartTop;
    final leftPad = 28.0;
    final usableWidth = size.width - leftPad - 8;
    final colWidth = usableWidth / days.length;

    final gridPaint = Paint()
      ..color = Colors.grey.shade200
      ..strokeWidth = 1;

    // Draw horizontal grid lines
    for (int i = 0; i <= 4; i++) {
      final y = chartBottom - (chartHeight * (i / 4));
      canvas.drawLine(Offset(leftPad, y), Offset(size.width, y), gridPaint);
      final labelVal = ((maxVal * i) / 4).round();
      final tp = TextPainter(
        text: TextSpan(text: '$labelVal', style: const TextStyle(fontSize: 10, color: Colors.grey)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y - 6));
    }

    final barPaint = Paint()
      ..color = const Color(0xFF93C5FD).withOpacity(0.55)
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = const Color(0xFF1D4ED8)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final List<Offset> points = [];

    for (int i = 0; i < days.length; i++) {
      final count = (days[i]['count'] as num?)?.toDouble() ?? 0.0;
      final dayLabel = days[i]['day']?.toString() ?? '';
      final xCenter = leftPad + (i * colWidth) + (colWidth / 2);
      final barHeight = maxVal > 0 ? (count / maxVal) * chartHeight : 0.0;
      final yTop = chartBottom - barHeight;

      // Bar
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(xCenter - 8, yTop, 16, barHeight),
        const Radius.circular(4),
      );
      canvas.drawRRect(rect, barPaint);

      points.add(Offset(xCenter, yTop));

      // Day label
      final tp = TextPainter(
        text: TextSpan(text: dayLabel, style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(xCenter - (tp.width / 2), chartBottom + 6));
    }

    if (points.length > 1) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (int i = 1; i < points.length; i++) {
        final prev = points[i - 1];
        final curr = points[i];
        final midX = (prev.dx + curr.dx) / 2;
        path.cubicTo(midX, prev.dy, midX, curr.dy, curr.dx, curr.dy);
      }
      canvas.drawPath(path, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
