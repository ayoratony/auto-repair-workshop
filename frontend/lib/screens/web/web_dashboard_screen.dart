import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'estimate_form.dart';
import 'invoice_pdf_service.dart';
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
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching data from backend: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
      case 'IN_PROGRESS':
        return Colors.blue;
      case 'WAITING':
        return Colors.orange;
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
      case 'IN_PROGRESS':
        return 'In Progress';
      case 'WAITING':
        return 'Waiting (Parts)';
      case 'COMPLETED':
        return 'Completed';
      case 'READY':
        return 'Ready';
      case 'BOOKED':
        return 'Booked';
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

    String status = existingJob?['status'] ?? 'IN_PROGRESS';
    String priority = existingJob?['priority'] ?? 'Medium';
    String fuelLevel = existingJob?['fuelLevel'] ?? 'Half';
    DateTime dueDate = existingJob?['dueDate'] != null
        ? (DateTime.tryParse(existingJob!['dueDate'].toString()) ?? DateTime.now().add(const Duration(days: 2)))
        : DateTime.now().add(const Duration(days: 2));

    List<DamageMarker> markers = [];
    VehicleBodyType bodyType = VehicleBodyType.sedan;
    ReceivingMemoDetails memoDetails = ReceivingMemoDetails(
      vinNumber: existingJob?['vehicle']?['vinNumber']?.toString() ?? '',
    );
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
    }

    bool isSaving = false;

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
                width: 680,
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
                              decoration: const InputDecoration(labelText: 'Customer Phone', border: OutlineInputBorder()),
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
                              decoration: const InputDecoration(labelText: 'Vehicle Make (e.g. Honda)', border: OutlineInputBorder()),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: modelCtrl,
                              decoration: const InputDecoration(labelText: 'Vehicle Model (e.g. CR-V)', border: OutlineInputBorder()),
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
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: status,
                              decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
                              items: const [
                                DropdownMenuItem(value: 'BOOKED', child: Text('Booked')),
                                DropdownMenuItem(value: 'IN_PROGRESS', child: Text('In Progress')),
                                DropdownMenuItem(value: 'WAITING', child: Text('Waiting (Parts)')),
                                DropdownMenuItem(value: 'READY', child: Text('Ready')),
                                DropdownMenuItem(value: 'COMPLETED', child: Text('Completed')),
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
                                  labelText: 'Due Date',
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
                              decoration: const InputDecoration(labelText: 'Odometer (km)', border: OutlineInputBorder()),
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
                        ],
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
                              'status': status,
                              'priority': priority,
                              'dueDate': dueDate.toIso8601String(),
                              'odometer': int.tryParse(odometerCtrl.text.trim()),
                              'fuelLevel': fuelLevel,
                              'walkAroundData': {
                                'bodyType': bodyType.name,
                                'markers': markers.map((m) => m.toJson()).toList(),
                                'memoDetails': memoDetails.toJson(),
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
    }

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Job Card $jobNo — ${customer['name'] ?? ''}'),
              Chip(
                label: Text(_statusLabel(job['status'] ?? 'IN_PROGRESS'),
                    style: TextStyle(color: _statusColor(job['status'] ?? 'IN_PROGRESS'), fontWeight: FontWeight.bold)),
                backgroundColor: _statusColor(job['status'] ?? 'IN_PROGRESS').withOpacity(0.1),
              ),
            ],
          ),
          content: SizedBox(
            width: 680,
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
                              Text('Technician: ${job['technician'] ?? 'Unassigned'}'),
                              Text('Priority: ${job['priority'] ?? 'Medium'} • Due: ${_formatDateShort(job['dueDate'])}'),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('VEHICLE DETAILS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                              const SizedBox(height: 6),
                              Text('Reg No: ${vehicle['registrationNo'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text('Make/Model: ${vehicle['make'] ?? ''} ${vehicle['model'] ?? ''}'),
                              Text('Odometer: ${job['odometer'] != null ? '${job['odometer']} km' : 'Not recorded'}'),
                              Text('Fuel Level: ${job['fuelLevel'] ?? 'Not recorded'}'),
                            ],
                          ),
                        ),
                      ],
                    ),
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
  }

  // ==========================================
  // DIALOG: ADD / EDIT PART IN CATALOG
  // ==========================================
  Future<void> _showPartDialog({Map<String, dynamic>? existingPart}) async {
    final isEdit = existingPart != null;
    final partNoCtrl = TextEditingController(text: existingPart?['partNumber'] ?? '');
    final descCtrl = TextEditingController(text: existingPart?['description'] ?? '');
    final priceCtrl = TextEditingController(text: existingPart?['unitPrice']?.toString() ?? '');
    final stockCtrl = TextEditingController(text: existingPart?['stockQuantity']?.toString() ?? '10');

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(isEdit ? 'Edit Part' : 'Add New Part to Catalog'),
          content: SizedBox(
            width: 450,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: partNoCtrl,
                  decoration: const InputDecoration(labelText: 'Part Number (e.g. BP-2040)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'Part Description (e.g. Ceramic Brake Pads)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: priceCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Unit Price (KSH)', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: stockCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Stock Quantity', border: OutlineInputBorder()),
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
                final payload = {
                  'partNumber': partNoCtrl.text.trim(),
                  'description': descCtrl.text.trim(),
                  'unitPrice': double.tryParse(priceCtrl.text.trim()) ?? 0,
                  'stockQuantity': int.tryParse(stockCtrl.text.trim()) ?? 0,
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
                        DropdownMenuItem(value: 'BOOKED', child: Text('Booked', style: TextStyle(fontSize: 14))),
                        DropdownMenuItem(value: 'IN_PROGRESS', child: Text('In Progress', style: TextStyle(fontSize: 14))),
                        DropdownMenuItem(value: 'WAITING', child: Text('Waiting (Parts)', style: TextStyle(fontSize: 14))),
                        DropdownMenuItem(value: 'READY', child: Text('Ready', style: TextStyle(fontSize: 14))),
                        DropdownMenuItem(value: 'COMPLETED', child: Text('Completed', style: TextStyle(fontSize: 14))),
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
            ElevatedButton.icon(
              onPressed: () => _showPartDialog(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Part'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
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
                      DataColumn(label: Text('Description', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Unit Price (KSH)', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Stock Qty', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Stock Status', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                    rows: _parts.map((part) {
                      final stock = (part['stockQuantity'] as num?)?.toInt() ?? 0;
                      final isLow = stock <= 5;
                      return DataRow(
                        cells: [
                          DataCell(Text(part['partNumber'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold))),
                          DataCell(Text(part['description'] ?? '')),
                          DataCell(Text('KSH ${(part['unitPrice'] as num).toStringAsFixed(2)}')),
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
                                OutlinedButton(
                                  onPressed: () => _showPartDialog(existingPart: Map<String, dynamic>.from(part)),
                                  child: const Text('Edit', style: TextStyle(fontSize: 12)),
                                ),
                                const SizedBox(width: 8),
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
  // TAB 4: INVOICES (Payment & Pay-Later)
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
                DataColumn(label: Text('Amount Due (KSH)', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Payment Status', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Payment Mode', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Record Payment', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('A4 Invoice & PDF', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: _invoices.map((inv) {
                final est = inv['estimate'] ?? {};
                final job = est['jobCard'] ?? {};
                final customer = job['customer']?['name'] ?? 'Customer';
                final reg = job['vehicle']?['registrationNo'] ?? '';
                final total = (est['total'] as num?)?.toDouble() ?? 0.0;
                final payStatus = inv['paymentStatus'] ?? 'UNPAID';

                return DataRow(
                  cells: [
                    DataCell(Text('INV-${inv['id'].toString().substring(0, 6).toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.bold))),
                    DataCell(Text('$customer ($reg)')),
                    DataCell(Text('KSH ${total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold))),
                    DataCell(
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: payStatus == 'PAID'
                              ? Colors.green.withOpacity(0.1)
                              : payStatus == 'PAY_LATER'
                                  ? Colors.orange.withOpacity(0.1)
                                  : Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          payStatus,
                          style: TextStyle(
                            color: payStatus == 'PAID'
                                ? Colors.green
                                : payStatus == 'PAY_LATER'
                                    ? Colors.orange.shade800
                                    : Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    DataCell(Text(inv['paymentMode'] ?? 'N/A')),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (payStatus != 'PAID') ...[
                            ElevatedButton(
                              onPressed: () async {
                                await http.put(
                                  Uri.parse('$_baseUrl/invoices/${inv['id']}'),
                                  headers: {'Content-Type': 'application/json'},
                                  body: json.encode({'paymentStatus': 'PAID', 'paymentMode': 'MPESA'}),
                                );
                                _refreshAllData();
                              },
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                              child: const Text('Pay M-Pesa', style: TextStyle(fontSize: 12)),
                            ),
                            const SizedBox(width: 6),
                            OutlinedButton(
                              onPressed: () async {
                                await http.put(
                                  Uri.parse('$_baseUrl/invoices/${inv['id']}'),
                                  headers: {'Content-Type': 'application/json'},
                                  body: json.encode({'paymentStatus': 'PAID', 'paymentMode': 'CASH'}),
                                );
                                _refreshAllData();
                              },
                              child: const Text('Pay Cash', style: TextStyle(fontSize: 12)),
                            ),
                            const SizedBox(width: 6),
                            OutlinedButton(
                              onPressed: () async {
                                await http.put(
                                  Uri.parse('$_baseUrl/invoices/${inv['id']}'),
                                  headers: {'Content-Type': 'application/json'},
                                  body: json.encode({'paymentStatus': 'PAY_LATER', 'paymentMode': 'INVOICE CREDIT'}),
                                );
                                _refreshAllData();
                              },
                              child: const Text('Pay Later', style: TextStyle(fontSize: 12)),
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
  // SIDEBAR SECTIONS: CUSTOMERS, EMPLOYEES, REPORTS, SETTINGS
  // ==========================================
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
              Text('Registered Customers (${_customers.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
            DataTable(
              columns: const [
                DataColumn(label: Text('Customer Name', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Phone', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Vehicles', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Total Jobs', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: _customers.map((c) {
                final vehicles = (c['vehicles'] as List<dynamic>?) ?? [];
                final jobs = (c['jobCards'] as List<dynamic>?) ?? [];
                return DataRow(
                  cells: [
                    DataCell(Text(c['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold))),
                    DataCell(Text(c['phone'] ?? '-')),
                    DataCell(Text(vehicles.map((v) => v['registrationNo']).join(', '))),
                    DataCell(Text('${jobs.length}')),
                  ],
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildEmployeesSection() {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    String selectedRole = 'MECHANIC';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Workshop Technicians & Employees', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Technician / Employee Name', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email Address', border: OutlineInputBorder()),
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
                label: const Text('Add Technician'),
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
  }

  Widget _buildReportsSection() {
    final rev = (_dashboard['totalRevenue'] as num?)?.toDouble() ?? 0.0;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Workshop Operational & Financial Summary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Divider(height: 24),
          _summaryRow('Total Realized & Approved Revenue', 'KSH ${rev.toStringAsFixed(2)}'),
          _summaryRow('Total Job Cards Created', '${_dashboard['totalJobsCount'] ?? 0}'),
          _summaryRow('Active / In-Progress Job Cards', '${_dashboard['activeJobsCount'] ?? 0}'),
          _summaryRow('Completed Job Cards', '${_dashboard['completedJobsCount'] ?? 0}'),
          _summaryRow('Total Estimates Generated', '${_estimates.length}'),
          _summaryRow('Total Invoices Issued', '${_invoices.length}'),
          _summaryRow('Registered Customers', '${_dashboard['customersCount'] ?? 0}'),
          _summaryRow('Catalog Parts Count', '${_parts.length}'),
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

  // ==========================================
  // RIGHT SIDE PANELS (LIVE FROM DATABASE)
  // ==========================================
  Widget _buildRightSidePanels() {
    final activities = (_dashboard['recentActivities'] as List<dynamic>?) ?? [];
    final weeklyJobs = (_dashboard['weeklyJobs'] as List<dynamic>?) ?? [];
    final rev = (_dashboard['totalRevenue'] as num?)?.toDouble() ?? 0.0;

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
          'Customer Summary',
          Column(
            children: [
              _summaryRow('Revenue (KSH)', rev.toStringAsFixed(0)),
              _summaryRow('Active Jobs', '${_dashboard['activeJobsCount'] ?? 0}'),
              _summaryRow('Customers', '${_dashboard['customersCount'] ?? 0}'),
              _summaryRow('Low Stock', '${_dashboard['lowStockCount'] ?? 0}'),
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
