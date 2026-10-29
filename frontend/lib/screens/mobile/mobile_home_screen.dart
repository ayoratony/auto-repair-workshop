import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import '../web/invoice_pdf_service.dart';
import '../web/estimate_form.dart';
import 'vehicle_damage_map.dart';
import 'walk_around_checklist.dart';
import '../../services/auth_service.dart';
import '../../services/platform_launcher.dart';
import '../../services/sync_service.dart';
import '../../services/vehicle_photo_service.dart';

class MobileHomeScreen extends StatefulWidget {
  const MobileHomeScreen({Key? key}) : super(key: key);

  @override
  State<MobileHomeScreen> createState() => _MobileHomeScreenState();
}

class _MobileHomeScreenState extends State<MobileHomeScreen> {
  static const String _baseUrl = 'https://auto.zksms.online/api';

  // Role-based mobile workspace: 'ADVISOR' (Service Advisor) or 'MECHANIC' (Technician)
  // Advisor tabs: 0 Home, 1 Jobs, 2 Intake, 3 Quotes, 4 Schedule
  // Technician tabs: 0 My Jobs, 1 Completed
  String _role = 'ADVISOR';
  String _techName = 'All';
  List<String> _technicians = [];
  List<dynamic> _estimates = [];
  Map<String, dynamic> _workshopSettings = {};
  String _jobSearch = '';
  String _jobStatusFilter = 'ALL';
  String _jobBayFilter = 'ALL';
  String _jobSortBy = 'NEWEST';
  String _selectedKpiFilter = 'ALL';
  final TextEditingController _jobSearchCtrl = TextEditingController();
  String _quoteSearch = '';
  String _quoteStatusFilter = 'ALL';

  int _selectedIndex = 0;
  List<dynamic> _jobs = [];
  List<dynamic> _appointments = [];
  List<dynamic> _itemRequests = [];
  bool _isLoadingJobs = false;
  bool _isSubmitting = false;

  // Intake form controllers
  final TextEditingController _customerController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _regController = TextEditingController();
  final TextEditingController _makeController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  final TextEditingController _odometerController = TextEditingController();
  final TextEditingController _serviceController = TextEditingController();
  final TextEditingController _obdController = TextEditingController();
  final TextEditingController _fleetUnitController = TextEditingController();
  final TextEditingController _driverController = TextEditingController();
  final TextEditingController _driverPhoneController = TextEditingController();

  String _selectedCategory = 'PERSONAL';
  Timer? _regLookupTimer;
  bool _isLookingUpVehicle = false;
  Map<String, dynamic>? _foundVehicleData;
  String? _selectedCustomerId;
  Timer? _customerLookupTimer;
  bool _isLookingUpCustomer = false;
  Map<String, dynamic>? _matchedCustomerData;
  List<Map<String, dynamic>> _matchedCustomerVehicles = [];

  String _fuelType = 'Petrol';
  String _fuelLevel = 'Half';
  String _priority = 'Medium';
  String _bayNumber = 'Bay 1';
  VehicleBodyType _selectedBodyType = VehicleBodyType.sedan;
  List<DamageMarker> _damageMarkers = [];
  ReceivingMemoDetails _memoDetails = ReceivingMemoDetails();
  bool _signatureCaptured = false;
  Map<String, String> _diagnostics = {
    'Engine': 'Pass',
    'Brakes': 'Pass',
    'Suspension': 'Pass',
    'Tyres': 'Pass',
    'Battery': 'Pass',
    'Electrical': 'Pass',
    'AC': 'Pass',
    'Transmission': 'Pass',
  };

  StreamSubscription<SyncEvent>? _syncSubscription;

  @override
  void initState() {
    super.initState();
    final authRole = AuthService.instance.role;
    if (authRole == 'MECHANIC') {
      _role = 'MECHANIC';
      _techName = AuthService.instance.userName;
    } else {
      _role = 'ADVISOR';
      _techName = 'All';
    }
    _fetchJobs();

    // Start Realtime Auto-Sync across all workshop devices
    SyncService.instance.startAutoSync();
    _syncSubscription = SyncService.instance.onSyncEvent.listen((evt) {
      if (!mounted) return;
      if (evt.type == 'RECOMMENDATION_ADDED') {
        final currentUserName = AuthService.instance.userName.trim().toLowerCase();
        final actor = evt.actorName.trim().toLowerCase();
        if (currentUserName.isEmpty || !actor.contains(currentUserName)) {
          final reg = evt.metadata['registrationNo'] ?? 'Vehicle';
          final sys = evt.metadata['recommendation']?['system'] ?? 'Defect';
          final cost = evt.metadata['recommendation']?['totalEstimated'] ?? 0;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFFB45309),
              duration: const Duration(seconds: 5),
              behavior: SnackBarBehavior.floating,
              content: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '🔔 ${evt.actorName}: $reg has $sys issue (KES $cost)!',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ],
              ),
              action: SnackBarAction(
                label: 'VIEW',
                textColor: Colors.yellow,
                onPressed: _fetchJobs,
              ),
            ),
          );
        }
      }
    });
    SyncService.instance.addListener(_onSyncNotification);
  }

  void _onSyncNotification() {
    if (mounted) {
      _fetchJobsSilently();
    }
  }

  @override
  void dispose() {
    _jobSearchCtrl.dispose();
    _syncSubscription?.cancel();
    SyncService.instance.removeListener(_onSyncNotification);
    super.dispose();
  }

  Future<void> _fetchJobsSilently() async {
    try {
      final authHeaders = AuthService.instance.authHeaders;
      final results = await Future.wait([
        http.get(Uri.parse('$_baseUrl/jobs'), headers: authHeaders),
        http.get(Uri.parse('$_baseUrl/appointments'), headers: authHeaders),
        http.get(Uri.parse('$_baseUrl/estimates'), headers: authHeaders),
        http.get(Uri.parse('$_baseUrl/employees'), headers: authHeaders),
        http.get(Uri.parse('$_baseUrl/inventory/requests'), headers: authHeaders),
        http.get(Uri.parse('$_baseUrl/settings'), headers: authHeaders),
      ]);
      if (mounted) {
        setState(() {
          if (results[0].statusCode == 200) _jobs = json.decode(results[0].body);
          if (results[1].statusCode == 200) _appointments = json.decode(results[1].body);
          if (results[2].statusCode == 200) _estimates = json.decode(results[2].body);
          if (results[3].statusCode == 200) {
            final allUsers = (json.decode(results[3].body) as List);
            const nonTechRoles = {'SUPER_ADMIN', 'OWNER', 'ADMIN', 'MANAGER', 'ADVISOR', 'ACCOUNTS', 'CASHIER', 'STOREKEEPER', 'INVENTORY_MANAGER'};
            var techFiltered = allUsers.where((u) {
              final role = (u['role'] ?? '').toString().toUpperCase();
              if (role == 'MECHANIC' || role == 'INSPECTOR' || role.contains('TECH')) return true;
              final spec = (u['specialization'] ?? '').toString().trim();
              return spec.isNotEmpty && !nonTechRoles.contains(role);
            }).map<String>((u) => u['name'].toString()).toList();
            if (techFiltered.isEmpty) {
              techFiltered = allUsers.where((u) {
                final role = (u['role'] ?? '').toString().toUpperCase();
                return role != 'SUPER_ADMIN' && role != 'ACCOUNTS' && role != 'CASHIER' && role != 'STOREKEEPER';
              }).map<String>((u) => u['name'].toString()).toList();
            }
            _technicians = techFiltered;
          }
          if (results[4].statusCode == 200) _itemRequests = json.decode(results[4].body);
          if (results[5].statusCode == 200) _workshopSettings = json.decode(results[5].body);
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchJobs() async {
    setState(() => _isLoadingJobs = true);
    try {
      final authHeaders = AuthService.instance.authHeaders;
      final results = await Future.wait([
        http.get(Uri.parse('$_baseUrl/jobs'), headers: authHeaders),
        http.get(Uri.parse('$_baseUrl/appointments'), headers: authHeaders),
        http.get(Uri.parse('$_baseUrl/estimates'), headers: authHeaders),
        http.get(Uri.parse('$_baseUrl/employees'), headers: authHeaders),
        http.get(
          Uri.parse('$_baseUrl/inventory/requests'),
          headers: authHeaders,
        ),
        http.get(Uri.parse('$_baseUrl/settings'), headers: authHeaders),
      ]);
      if (mounted) {
        setState(() {
          if (results[0].statusCode == 200) _jobs = json.decode(results[0].body);
          if (results[1].statusCode == 200) _appointments = json.decode(results[1].body);
          if (results[2].statusCode == 200) _estimates = json.decode(results[2].body);
          if (results[3].statusCode == 200) {
            final allUsers = (json.decode(results[3].body) as List);
            const nonTechRoles = {'SUPER_ADMIN', 'OWNER', 'ADMIN', 'MANAGER', 'ADVISOR', 'ACCOUNTS', 'CASHIER', 'STOREKEEPER', 'INVENTORY_MANAGER'};
            var techFiltered = allUsers.where((u) {
              final role = (u['role'] ?? '').toString().toUpperCase();
              if (role == 'MECHANIC' || role == 'INSPECTOR' || role.contains('TECH')) return true;
              final spec = (u['specialization'] ?? '').toString().trim();
              return spec.isNotEmpty && !nonTechRoles.contains(role);
            }).map<String>((u) => u['name'].toString()).toList();
            if (techFiltered.isEmpty) {
              techFiltered = allUsers.where((u) {
                final role = (u['role'] ?? '').toString().toUpperCase();
                return role != 'SUPER_ADMIN' && role != 'ACCOUNTS' && role != 'CASHIER' && role != 'STOREKEEPER';
              }).map<String>((u) => u['name'].toString()).toList();
            }
            _technicians = techFiltered;
          }
          if (results[4].statusCode == 200) _itemRequests = json.decode(results[4].body);
          if (results[5].statusCode == 200) _workshopSettings = json.decode(results[5].body);
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoadingJobs = false);
    }
  }

  Future<void> _submitIntakeJobCard() async {
    if (_customerController.text.trim().isEmpty || _regController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.orange,
          content: Text('Please enter Customer Name and Vehicle Registration Number.'),
        ),
      );
      return;
    }

    if (_phoneController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.orange,
          content: Text('Customer / Owner Phone Number is mandatory.'),
        ),
      );
      return;
    }

    if (!_memoDetails.termsAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.orange,
          content: Text('Please tick that the Customer agrees to the Workshop Receiving Terms & Conditions.'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/jobs'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'customerId': _selectedCustomerId,
          'customerName': _customerController.text.trim(),
          'phone': _phoneController.text.trim(),
          'registrationNo': _regController.text.trim(),
          'category': _selectedCategory,
          'bodyType': _selectedBodyType.name,
          'fleetUnitNumber': _fleetUnitController.text.trim().isEmpty ? null : _fleetUnitController.text.trim(),
          'assignedDriver': _driverController.text.trim().isEmpty ? null : _driverController.text.trim(),
          'driverPhone': _driverPhoneController.text.trim().isEmpty ? null : _driverPhoneController.text.trim(),
          'make': _makeController.text.trim(),
          'model': _modelController.text.trim(),
          'fuelType': _fuelType,
          'vinNumber': _memoDetails.vinNumber,
          'odometer': int.tryParse(_odometerController.text.trim()),
          'fuelLevel': _fuelLevel,
          'priority': _priority,
          'bayNumber': _bayNumber,
          'service': _serviceController.text.trim().isEmpty
              ? _memoDetails.selectedCategories.join(', ')
              : _serviceController.text.trim(),
          'status': 'BOOKED',
          'diagnosticChecklist': {
            'obdCodes': _obdController.text.trim(),
            'diagnostics': _diagnostics,
          },
          'walkAroundData': {
            'bodyType': _selectedBodyType.name,
            'markers': _damageMarkers.map((m) => m.toJson()).toList(),
            'memoDetails': _memoDetails.toJson(),
            'diagnostics': _diagnostics,
            'obdCodes': _obdController.text.trim(),
            'signed': _signatureCaptured,
            'capturedAt': DateTime.now().toIso8601String(),
          },
        }),
      );

      if (response.statusCode == 201 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.green,
            content: Text('Job Card & Receiving Memo synced to Workshop Database!'),
          ),
        );
        _customerController.clear();
        _phoneController.clear();
        _regController.clear();
        _makeController.clear();
        _modelController.clear();
        _odometerController.clear();
        _serviceController.clear();
        _obdController.clear();
        _fleetUnitController.clear();
        _driverController.clear();
        _driverPhoneController.clear();
        setState(() {
          _foundVehicleData = null;
          _selectedCustomerId = null;
          _matchedCustomerData = null;
          _matchedCustomerVehicles = [];
          _selectedCategory = 'PERSONAL';
          _damageMarkers = [];
          _memoDetails = ReceivingMemoDetails();
          _signatureCaptured = false;
          _diagnostics = {
            'Engine': 'Pass',
            'Brakes': 'Pass',
            'Suspension': 'Pass',
            'Tyres': 'Pass',
            'Battery': 'Pass',
            'Electrical': 'Pass',
            'AC': 'Pass',
            'Transmission': 'Pass',
          };
          _selectedIndex = 1; // Switch to Jobs list to see it
        });
        _fetchJobs();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Error saving Job Card: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _openSignatureModal() {
    List<Offset?> points = [];
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              title: const Text('Customer Sign-Off'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Sign inside the box below to confirm vehicle condition:', style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 12),
                  Container(
                    width: 300,
                    height: 160,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      color: Colors.grey.shade50,
                    ),
                    child: GestureDetector(
                      onPanUpdate: (details) {
                        setModalState(() {
                          points.add(details.localPosition);
                        });
                      },
                      onPanEnd: (_) => setModalState(() => points.add(null)),
                      child: CustomPaint(
                        painter: _SignaturePainter(points),
                        size: const Size(300, 160),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => setModalState(() => points.clear()),
                  child: const Text('Clear'),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() => _signatureCaptured = points.isNotEmpty);
                    Navigator.pop(ctx);
                  },
                  child: const Text('Confirm Signature'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  bool get _isAdvisor => _role == 'ADVISOR';

  Color _statusColor(String s) {
    switch (s) {
      case 'BOOKED':
        return const Color(0xFF64748B);
      case 'INSPECTION':
        return const Color(0xFF7C3AED);
      case 'AWAITING_APPROVAL':
        return const Color(0xFFD97706);
      case 'IN_PROGRESS':
        return const Color(0xFF2563EB);
      case 'WAITING':
        return const Color(0xFFEA580C);
      case 'QUALITY_CHECK':
        return const Color(0xFF0891B2);
      case 'READY':
        return const Color(0xFF16A34A);
      case 'COMPLETED':
        return const Color(0xFF15803D);
      default:
        return const Color(0xFF64748B);
    }
  }

  String _prettyStatus(String s) => s.replaceAll('_', ' ');

  void _toast(String msg, {Color color = Colors.green}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: color, content: Text(msg)));
  }

  Future<bool> _putJob(String id, Map<String, dynamic> body) async {
    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
        ...AuthService.instance.authHeaders,
      };
      final r = await http.put(
        Uri.parse('$_baseUrl/jobs/$id'),
        headers: headers,
        body: json.encode(body),
      );
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  int _stageIndex(String s) {
    switch (s) {
      case 'BOOKED':
        return 1;
      case 'INSPECTION':
        return 2;
      case 'AWAITING_APPROVAL':
        return 3;
      case 'IN_PROGRESS':
        return 4;
      case 'WAITING':
        return 5;
      case 'QUALITY_CHECK':
        return 6;
      case 'READY':
        return 7;
      case 'COMPLETED':
        return 7;
      default:
        return 1;
    }
  }

  String _stageTitle(String s) {
    switch (s) {
      case 'BOOKED':
        return '1. Checked-In';
      case 'INSPECTION':
        return '2. Inspection & OBD-II';
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
        return s.replaceAll('_', ' ');
    }
  }

  IconData _statusIcon(String s) {
    switch (s) {
      case 'BOOKED':
        return Icons.receipt_long;
      case 'INSPECTION':
        return Icons.search;
      case 'AWAITING_APPROVAL':
        return Icons.pending_actions;
      case 'IN_PROGRESS':
        return Icons.build;
      case 'WAITING':
        return Icons.hourglass_empty;
      case 'QUALITY_CHECK':
        return Icons.verified;
      case 'READY':
        return Icons.key;
      case 'COMPLETED':
        return Icons.task_alt;
      default:
        return Icons.info_outline;
    }
  }

  int _priorityWeight(String? p) {
    final lower = (p ?? '').toLowerCase();
    if (lower == 'high' || lower == 'urgent') return 3;
    if (lower == 'medium') return 2;
    return 1;
  }

  void _openWhatsApp(String customer, String phone, String reg, String status) {
    if (phone.isEmpty) {
      _toast('No customer phone number recorded', color: Colors.orange);
      return;
    }
    final clean = phone.replaceAll(RegExp(r'\D'), '');
    final international = clean.startsWith('0') ? '254${clean.substring(1)}' : (clean.startsWith('254') ? clean : '254$clean');
    final ready = status == 'READY';
    final stage = _stageTitle(status);
    final msg = ready
        ? 'Hello $customer, your vehicle $reg is ready for collection at AutoKe Workshop. Kindly let us know your estimated pickup time.'
        : 'Hello $customer, this is AutoKe Workshop regarding your vehicle $reg. We are currently working on it ($stage).';
    final url = 'https://wa.me/$international?text=${Uri.encodeComponent(msg)}';
    PlatformLauncher.openUrl(url);
    Clipboard.setData(ClipboardData(text: '$phone\n$msg'));
    _toast('Opening WhatsApp / Message copied to clipboard!');
  }

  void _launchWhatsAppMessage(String phone, String msg) {
    if (phone.isEmpty) {
      _toast('No customer phone number recorded', color: Colors.orange);
      return;
    }
    final clean = phone.replaceAll(RegExp(r'\D'), '');
    final international = clean.startsWith('0') ? '254${clean.substring(1)}' : (clean.startsWith('254') ? clean : '254$clean');
    final url = 'https://wa.me/$international?text=${Uri.encodeComponent(msg)}';
    PlatformLauncher.openUrl(url);
    Clipboard.setData(ClipboardData(text: '$phone\n$msg'));
    _toast('Opening WhatsApp / Message copied to clipboard!');
  }

  void _makePhoneCall(String phone) {
    if (phone.isEmpty) {
      _toast('No customer phone number recorded', color: Colors.orange);
      return;
    }
    final clean = phone.replaceAll(RegExp(r'\s+'), '');
    PlatformLauncher.openUrl('tel:$clean');
    Clipboard.setData(ClipboardData(text: clean));
    _toast('Dialing $clean / Copied to clipboard');
  }

  void _showQuickStatusPicker(Map<String, dynamic> job) {
    final curStatus = (job['status'] ?? 'BOOKED').toString();
    final jobNo = (job['jobNumber'] ?? job['id'].toString().substring(0, 8).toUpperCase()).toString();
    final reg = (job['vehicle']?['registrationNo'] ?? '').toString();

    final stages = <Map<String, dynamic>>[
      {'key': 'BOOKED', 'label': '1. Checked-In', 'desc': 'Vehicle received & memo logged', 'icon': Icons.receipt_long, 'color': const Color(0xFF64748B)},
      {'key': 'INSPECTION', 'label': '2. Inspection & OBD-II', 'desc': 'Diagnostics & teardown on bay', 'icon': Icons.search, 'color': const Color(0xFF7C3AED)},
      {'key': 'AWAITING_APPROVAL', 'label': '3. Awaiting Approval', 'desc': 'Quotation sent to client', 'icon': Icons.pending_actions, 'color': const Color(0xFFD97706)},
      {'key': 'IN_PROGRESS', 'label': '4. In Repair', 'desc': 'Mechanic active on assigned bay', 'icon': Icons.build, 'color': const Color(0xFF2563EB)},
      {'key': 'WAITING', 'label': '5. Waiting Parts', 'desc': 'Parts requisition in store/supplier', 'icon': Icons.hourglass_empty, 'color': const Color(0xFFEA580C)},
      {'key': 'QUALITY_CHECK', 'label': '6. Quality Check (QC)', 'desc': 'Manager road test & checklist OK', 'icon': Icons.verified, 'color': const Color(0xFF0891B2)},
      {'key': 'READY', 'label': '7. Ready for Pickup', 'desc': 'Cleaning done, keys ready for handover', 'icon': Icons.key, 'color': const Color(0xFF16A34A)},
      {'key': 'COMPLETED', 'label': 'Delivered / Closed', 'desc': 'Vehicle handed over & settled', 'icon': Icons.task_alt, 'color': const Color(0xFF15803D)},
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.published_with_changes, color: Color(0xFF0F4C81), size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Update Workflow Stage', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        Text('$jobNo \u2022 ${reg.isNotEmpty ? reg : "Vehicle"}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const Divider(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: stages.map((st) {
                      final isSelected = st['key'] == curStatus;
                      final Color color = st['color'] as Color;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? color.withOpacity(0.08) : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected ? color : Colors.grey.shade200,
                            width: isSelected ? 1.5 : 1.0,
                          ),
                        ),
                        child: ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: color.withOpacity(0.15),
                            child: Icon(st['icon'] as IconData, size: 16, color: color),
                          ),
                          title: Text(
                            st['label'] as String,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                              color: isSelected ? color : const Color(0xFF0F172A),
                            ),
                          ),
                          subtitle: Text(st['desc'] as String, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          trailing: isSelected
                              ? Icon(Icons.check_circle, color: color, size: 20)
                              : const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
                          onTap: () async {
                            Navigator.pop(ctx);
                            if (st['key'] == curStatus) return;
                            final ok = await _putJob(job['id'].toString(), {'status': st['key']});
                            if (ok) {
                              _toast('Moved to ${st['label']}');
                              _fetchJobs();
                            } else {
                              _toast('Failed to update stage', color: Colors.red);
                            }
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showJobsFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setFilterState) => Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.tune, color: Color(0xFF0F4C81), size: 20),
                        SizedBox(width: 8),
                        Text('Filter & Sort Job Cards', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      ],
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _jobBayFilter = 'ALL';
                          _jobSortBy = 'NEWEST';
                          _selectedKpiFilter = 'ALL';
                        });
                        setFilterState(() {});
                        Navigator.pop(ctx);
                      },
                      child: const Text('Reset All', style: TextStyle(color: Colors.red, fontSize: 12)),
                    ),
                  ],
                ),
                const Divider(),
                const Text('SORT JOBS BY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _filterChoiceChip('Newest Added', _jobSortBy == 'NEWEST', () {
                      setState(() => _jobSortBy = 'NEWEST');
                      setFilterState(() {});
                    }),
                    _filterChoiceChip('🔥 High Priority First', _jobSortBy == 'PRIORITY', () {
                      setState(() => _jobSortBy = 'PRIORITY');
                      setFilterState(() {});
                    }),
                    _filterChoiceChip('Reg Plate (A-Z)', _jobSortBy == 'PLATE', () {
                      setState(() => _jobSortBy = 'PLATE');
                      setFilterState(() {});
                    }),
                    _filterChoiceChip('Customer Name', _jobSortBy == 'CUSTOMER', () {
                      setState(() => _jobSortBy = 'CUSTOMER');
                      setFilterState(() {});
                    }),
                    _filterChoiceChip('Due Date', _jobSortBy == 'DUE_DATE', () {
                      setState(() => _jobSortBy = 'DUE_DATE');
                      setFilterState(() {});
                    }),
                  ],
                ),
                const SizedBox(height: 14),
                const Text('FILTER BY WORKSHOP BAY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    'ALL',
                    'Diagnostic Bay',
                    'Bay 1',
                    'Bay 2',
                    'Bay 3',
                    'Lift 1',
                    'Lift 2',
                  ].map((bay) {
                    final isSel = _jobBayFilter == bay;
                    return _filterChoiceChip(bay == 'ALL' ? 'All Bays' : bay, isSel, () {
                      setState(() => _jobBayFilter = bay);
                      setFilterState(() {});
                    });
                  }).toList(),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F4C81),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Apply Filters', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filterChoiceChip(String label, bool selected, VoidCallback onSelected) {
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.bold : FontWeight.w500, color: selected ? const Color(0xFF1E3A8A) : Colors.black87)),
      selected: selected,
      selectedColor: const Color(0xFFDBEAFE),
      backgroundColor: const Color(0xFFF1F5F9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: selected ? const Color(0xFF2563EB) : const Color(0xFFCBD5E1)),
      ),
      onSelected: (_) => onSelected(),
    );
  }

  void _switchRole(String role) {
    setState(() {
      _role = role;
      _selectedIndex = 0;
    });
  }

  void _confirmMobileSignOut() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.logout, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Sign Out'),
          ],
        ),
        content: const Text('Are you sure you want to sign out of AutoKe?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              await AuthService.instance.logout();
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final advisorTitles = ['Overview', 'Job Cards', 'Vehicle Intake', 'Quotations', 'Bay Schedule'];
    final techTitles = ['My Assigned Jobs', 'Item Requests', 'Completed Jobs'];
    final title = _isAdvisor ? advisorTitles[_selectedIndex] : techTitles[_selectedIndex];

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Row(
          children: [
            RichText(
              text: const TextSpan(
                children: [
                  TextSpan(
                    text: 'Auto',
                    style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: 0.4),
                  ),
                  TextSpan(
                    text: 'Ke',
                    style: TextStyle(color: Color(0xFF38BDF8), fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: 0.4),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${AuthService.instance.userName} (${AuthService.instance.role})',
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0F4C81),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_isAdvisor && _selectedIndex == 4)
            IconButton(
              tooltip: 'Book Appointment',
              icon: const Icon(Icons.add_box_outlined),
              onPressed: _showMobileAppointmentDialog,
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchJobs),
          IconButton(
            tooltip: 'Sign Out',
            icon: const Icon(Icons.logout),
            onPressed: _confirmMobileSignOut,
          ),
        ],
        bottom: (AuthService.instance.isOwner || AuthService.instance.isManager)
            ? PreferredSize(
                preferredSize: const Size.fromHeight(52),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(3),
                    child: Row(
                      children: [
                        _roleTab('ADVISOR', 'Service Advisor', Icons.support_agent),
                        _roleTab('MECHANIC', 'Technician', Icons.build_circle_outlined),
                      ],
                    ),
                  ),
                ),
              )
            : null,
      ),
      body: _isAdvisor ? _buildAdvisorBody() : _buildTechnicianBody(),
      floatingActionButton: (_isAdvisor && _selectedIndex == 3)
          ? FloatingActionButton.extended(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              elevation: 4,
              icon: const Icon(Icons.add, size: 20),
              label: const Text('New Estimate', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              onPressed: () => _openCreateEstimateModal(),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFDBEAFE),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 66,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
          if (!(_isAdvisor && index == 2)) _fetchJobs();
        },
        destinations: _isAdvisor
            ? const [
                NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Overview'),
                NavigationDestination(icon: Icon(Icons.assignment_outlined), selectedIcon: Icon(Icons.assignment), label: 'Jobs'),
                NavigationDestination(icon: Icon(Icons.add_circle_outline), selectedIcon: Icon(Icons.add_circle), label: 'Intake'),
                NavigationDestination(icon: Icon(Icons.request_quote_outlined), selectedIcon: Icon(Icons.request_quote), label: 'Quotes'),
                NavigationDestination(icon: Icon(Icons.calendar_today_outlined), selectedIcon: Icon(Icons.calendar_today), label: 'Schedule'),
              ]
            : const [
                NavigationDestination(icon: Icon(Icons.build_outlined), selectedIcon: Icon(Icons.build), label: 'My Jobs'),
                NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Item Requests'),
                NavigationDestination(icon: Icon(Icons.check_circle_outline), selectedIcon: Icon(Icons.check_circle), label: 'Completed'),
              ],
      ),
    );
  }

  Widget _roleTab(String role, String label, IconData icon) {
    final selected = _role == role;
    return Expanded(
      child: GestureDetector(
        onTap: () => _switchRole(role),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: selected ? const Color(0xFF0F4C81) : Colors.white70),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: selected ? const Color(0xFF0F4C81) : Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SERVICE ADVISOR WORKSPACE
  // ---------------------------------------------------------------------------
  Widget _buildAdvisorBody() {
    switch (_selectedIndex) {
      case 0:
        return _buildAdvisorHome();
      case 1:
        return _buildJobsList();
      case 2:
        return _buildIntakeForm();
      case 3:
        return _buildQuotesView();
      default:
        return _buildScheduleView();
    }
  }

  Widget _buildAdvisorHome() {
    int count(bool Function(dynamic) f) => _jobs.where(f).length;
    final active = count((j) => j['status'] != 'COMPLETED');
    final awaiting = count((j) => j['status'] == 'AWAITING_APPROVAL');
    final ready = count((j) => j['status'] == 'READY');

    final tiles = <List<dynamic>>[
      ['Job Cards', 'Create & track repairs', Icons.assignment, () => setState(() => _selectedIndex = 1)],
      ['Customers', 'Profiles & history', Icons.people_alt, _showCustomersSheet],
      ['Vehicles & Fleets', 'Personal, Govt, Schools & Fleets', Icons.directions_car_filled, _showVehiclesSheet],
      ['Appointments', 'Bookings & bays', Icons.event_available, () => setState(() => _selectedIndex = 4)],
      ['Quotations', 'Estimates & approvals', Icons.request_quote, () => setState(() => _selectedIndex = 3)],
      ['Communications', 'Customer updates', Icons.chat_bubble, _showCommunicationsSheet],
      ['New Intake', '360\u00B0 vehicle check-in', Icons.directions_car, () => setState(() => _selectedIndex = 2)],
    ];

    return RefreshIndicator(
      onRefresh: _fetchJobs,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          const Text('Today at the workshop', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Row(
            children: [
              _statTile('Active', '$active', const Color(0xFF2563EB)),
              const SizedBox(width: 8),
              _statTile('Awaiting OK', '$awaiting', const Color(0xFFD97706)),
              const SizedBox(width: 8),
              _statTile('Ready', '$ready', const Color(0xFF16A34A)),
            ],
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.25,
            children: tiles
                .map((t) => InkWell(
                      onTap: t[3] as VoidCallback,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: const Color(0xFFDBEAFE),
                              child: Icon(t[2] as IconData, color: const Color(0xFF0F4C81)),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t[0] as String, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                                Text(t[1] as String, style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 18),
          const Text('Needs your attention', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          ..._jobs
              .where((j) => j['status'] == 'AWAITING_APPROVAL' || j['status'] == 'READY')
              .take(5)
              .map((j) => _jobCard(j)),
          if (awaiting + ready == 0)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Nothing pending \u2014 all caught up.', style: TextStyle(color: Colors.black54)),
            ),
        ],
      ),
    );
  }

  Widget _statTile(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(color: color.withOpacity(0.10), borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color)),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  void _showCustomersSheet() {
    final Map<String, Map<String, dynamic>> customers = {};
    for (final j in _jobs) {
      final c = j['customer'];
      if (c == null) continue;
      final key = (c['id'] ?? c['name']).toString();
      customers.putIfAbsent(key, () => {'name': c['name'], 'phone': c['phone'], 'jobs': <dynamic>[]});
      (customers[key]!['jobs'] as List).add(j);
    }
    final list = customers.values.toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (_, scroll) => Column(
          children: [
            const SizedBox(height: 12),
            const Text('Customers & Vehicle History', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const Divider(),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('No customers yet.'))
                  : ListView.builder(
                      controller: scroll,
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final c = list[i];
                        final jobs = c['jobs'] as List;
                        return ExpansionTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF0F4C81),
                            child: Text(
                              (c['name'] ?? '?').toString().substring(0, 1).toUpperCase(),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          title: Text(c['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('${c['phone'] ?? 'No phone'} \u2022 ${jobs.length} visit(s)'),
                          children: jobs
                              .map<Widget>((j) => ListTile(
                                    dense: true,
                                    title: Text('${j['vehicle']?['registrationNo'] ?? ''} \u2022 ${j['workRequested'] ?? 'Service'}'),
                                    subtitle: Text('${j['jobNumber'] ?? ''} \u2022 ${_prettyStatus(j['status'] ?? '')}'),
                                  ))
                              .toList(),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _onMobilePlateChanged(String text) {
    _regLookupTimer?.cancel();
    final query = text.trim();
    if (query.length < 3) {
      if (_foundVehicleData != null) {
        setState(() => _foundVehicleData = null);
      }
      return;
    }
    _regLookupTimer = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _isLookingUpVehicle = true);
      try {
        final res = await http.get(
          Uri.parse('$_baseUrl/vehicles/lookup?q=${Uri.encodeComponent(query)}'),
          headers: {'Content-Type': 'application/json'},
        );
        if (res.statusCode == 200 && mounted) {
          final data = json.decode(res.body);
          if (data['found'] == true) {
            final v = data['vehicle'];
            final c = data['customer'];
            setState(() {
              _foundVehicleData = data;
              _isLookingUpVehicle = false;
              if (c != null && c['id'] != null) {
                _selectedCustomerId = c['id'].toString();
                _matchedCustomerData = Map<String, dynamic>.from(c);
                if (c['vehicles'] is List) {
                  _matchedCustomerVehicles = (c['vehicles'] as List)
                      .whereType<Map>()
                      .map((item) => Map<String, dynamic>.from(item))
                      .toList();
                }
              }
              if (_customerController.text.trim().isEmpty) {
                _customerController.text = c['name'] ?? '';
              }
              if (_phoneController.text.trim().isEmpty) {
                _phoneController.text = c['phone'] ?? '';
              }
              if (_makeController.text.trim().isEmpty) {
                _makeController.text = v['make'] ?? '';
              }
              if (_modelController.text.trim().isEmpty) {
                _modelController.text = v['model'] ?? '';
              }
              if (_memoDetails.vinNumber.isEmpty && (v['vinNumber'] ?? '').toString().isNotEmpty) {
                _memoDetails.vinNumber = v['vinNumber'].toString();
              }
              if (_fleetUnitController.text.trim().isEmpty && (v['fleetUnitNumber'] ?? '').toString().isNotEmpty) {
                _fleetUnitController.text = v['fleetUnitNumber'].toString();
              }
              if (_driverController.text.trim().isEmpty && (v['assignedDriver'] ?? '').toString().isNotEmpty) {
                _driverController.text = v['assignedDriver'].toString();
              }
              if (_driverPhoneController.text.trim().isEmpty && (v['driverPhone'] ?? '').toString().isNotEmpty) {
                _driverPhoneController.text = v['driverPhone'].toString();
              }
              if (v['category'] != null) {
                _selectedCategory = v['category'].toString();
              }
              if (v['fuelType'] != null && (v['fuelType'] as String).isNotEmpty) {
                _fuelType = v['fuelType'].toString();
              }
            });
            return;
          }
        }
      } catch (_) {}
      if (mounted) {
        setState(() {
          _foundVehicleData = null;
          _isLookingUpVehicle = false;
        });
      }
    });
  }

  void _onMobileCustomerInputChanged(String text) {
    _customerLookupTimer?.cancel();
    final query = text.trim();
    if (query.length < 3) {
      if (_matchedCustomerVehicles.isNotEmpty) {
        setState(() {
          _matchedCustomerData = null;
          _matchedCustomerVehicles = [];
        });
      }
      return;
    }
    _customerLookupTimer = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _isLookingUpCustomer = true);
      try {
        final res = await http.get(
          Uri.parse('$_baseUrl/customers/lookup?q=${Uri.encodeComponent(query)}'),
          headers: AuthService.instance.authHeaders,
        );
        if (res.statusCode == 200 && mounted) {
          final data = json.decode(res.body);
          if (data['found'] == true && data['customer'] != null) {
            final c = data['customer'];
            final vList = (c['vehicles'] as List<dynamic>?)
                ?.whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList() ?? [];
            setState(() {
              _matchedCustomerData = Map<String, dynamic>.from(c);
              _matchedCustomerVehicles = vList;
              _selectedCustomerId = c['id']?.toString();
              _isLookingUpCustomer = false;
              if (_customerController.text.trim().isEmpty && (c['name'] ?? '').toString().isNotEmpty) {
                _customerController.text = c['name'];
              }
              if (_phoneController.text.trim().isEmpty && (c['phone'] ?? '').toString().isNotEmpty) {
                _phoneController.text = c['phone'];
              }
              if (c['category'] != null) {
                _selectedCategory = c['category'].toString();
              }
            });
            return;
          }
        }
      } catch (_) {}
      if (mounted) {
        setState(() => _isLookingUpCustomer = false);
      }
    });
  }

  Widget _buildMobileCategoryBadge(String cat) {
    Color bg;
    Color fg;
    IconData icon;
    String label;

    switch (cat.toUpperCase()) {
      case 'GOVERNMENT':
        bg = const Color(0xFFEFF6FF);
        fg = const Color(0xFF1D4ED8);
        icon = Icons.account_balance;
        label = 'GOVERNMENT';
        break;
      case 'SCHOOL':
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFFB45309);
        icon = Icons.school;
        label = 'SCHOOL';
        break;
      case 'ORGANIZATION':
        bg = const Color(0xFFF3E8FF);
        fg = const Color(0xFF6D28D9);
        icon = Icons.business;
        label = 'ORGANIZATION';
        break;
      case 'PERSONAL':
      default:
        bg = const Color(0xFFECFDF5);
        fg = const Color(0xFF047857);
        icon = Icons.person;
        label = 'PERSONAL';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: fg),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildFuelTypePill(String fuel) {
    final clean = fuel.trim().toUpperCase();
    Color bg = const Color(0xFFEFF6FF);
    Color fg = const Color(0xFF1D4ED8);
    String icon = '⛽';
    if (clean == 'DIESEL') {
      bg = const Color(0xFFFEF3C7);
      fg = const Color(0xFFB45309);
      icon = '🛢️';
    } else if (clean == 'HYBRID') {
      bg = const Color(0xFFECFDF5);
      fg = const Color(0xFF047857);
      icon = '⚡';
    } else if (clean == 'ELECTRIC') {
      bg = const Color(0xFFF3E8FF);
      fg = const Color(0xFF7E22CE);
      icon = '🔌';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: fg.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 10)),
          const SizedBox(width: 3),
          Text(clean, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: fg)),
        ],
      ),
    );
  }

  void _showVehiclesSheet() {
    String categoryFilter = 'ALL';
    String searchQuery = '';
    List<dynamic> vehicles = [];
    bool isLoading = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          void fetchVehicles() async {
            try {
              final res = await http.get(
                Uri.parse('$_baseUrl/vehicles'),
                headers: AuthService.instance.authHeaders,
              );
              if (res.statusCode == 200 && mounted) {
                final data = json.decode(res.body);
                setSheetState(() {
                  vehicles = data is Map ? (data['vehicles'] ?? []) : (data is List ? data : []);
                  isLoading = false;
                });
              } else {
                setSheetState(() => isLoading = false);
              }
            } catch (_) {
              if (mounted) setSheetState(() => isLoading = false);
            }
          }

          if (isLoading && vehicles.isEmpty) {
            fetchVehicles();
          }

          final filtered = vehicles.where((v) {
            if (categoryFilter != 'ALL' && (v['category'] ?? 'PERSONAL') != categoryFilter) {
              return false;
            }
            if (searchQuery.isNotEmpty) {
              final q = searchQuery.toLowerCase();
              final reg = (v['registrationNo'] ?? '').toString().toLowerCase();
              final make = (v['make'] ?? '').toString().toLowerCase();
              final model = (v['model'] ?? '').toString().toLowerCase();
              final unit = (v['fleetUnitNumber'] ?? '').toString().toLowerCase();
              final driver = (v['assignedDriver'] ?? '').toString().toLowerCase();
              final cust = (v['customer']?['name'] ?? '').toString().toLowerCase();
              if (!reg.contains(q) && !make.contains(q) && !model.contains(q) && !unit.contains(q) && !driver.contains(q) && !cust.contains(q)) {
                return false;
              }
            }
            return true;
          }).toList();

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.85,
            maxChildSize: 0.95,
            builder: (_, scroll) => Column(
              children: [
                const SizedBox(height: 12),
                Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Vehicles & Fleets Registry', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: () => setSheetState(() { isLoading = true; fetchVehicles(); })),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search, size: 18),
                      hintText: 'Search plate, make, model, driver...',
                      hintStyle: const TextStyle(fontSize: 13),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onChanged: (val) => setSheetState(() => searchQuery = val),
                  ),
                ),
                // Category Pills
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      _buildMobileFilterChip('All (${vehicles.length})', 'ALL', categoryFilter, (k) => setSheetState(() => categoryFilter = k)),
                      const SizedBox(width: 6),
                      _buildMobileFilterChip('Personal', 'PERSONAL', categoryFilter, (k) => setSheetState(() => categoryFilter = k)),
                      const SizedBox(width: 6),
                      _buildMobileFilterChip('Government', 'GOVERNMENT', categoryFilter, (k) => setSheetState(() => categoryFilter = k)),
                      const SizedBox(width: 6),
                      _buildMobileFilterChip('School', 'SCHOOL', categoryFilter, (k) => setSheetState(() => categoryFilter = k)),
                      const SizedBox(width: 6),
                      _buildMobileFilterChip('Corporate', 'ORGANIZATION', categoryFilter, (k) => setSheetState(() => categoryFilter = k)),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : filtered.isEmpty
                          ? const Center(child: Text('No vehicles found.', style: TextStyle(color: Colors.grey)))
                          : ListView.builder(
                              controller: scroll,
                              itemCount: filtered.length,
                              itemBuilder: (_, i) {
                                final v = filtered[i];
                                final cust = v['customer'] ?? {};
                                return Card(
                                  margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    leading: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFF0F172A), width: 1.2),
                                      ),
                                      child: Text(
                                        (v['registrationNo'] ?? '-').toString().toUpperCase(),
                                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Color(0xFF0F172A)),
                                      ),
                                    ),
                                    title: Row(
                                      children: [
                                        Expanded(
                                          child: Text('${v['make'] ?? ''} ${v['model'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                        ),
                                        _buildMobileCategoryBadge(v['category'] ?? 'PERSONAL'),
                                      ],
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const SizedBox(height: 2),
                                        Text('Owner: ${cust['name'] ?? '-'}  \u2022  ${v['lastOdometer'] ?? 0} km', style: const TextStyle(fontSize: 12)),
                                        if ((v['assignedDriver'] ?? '').toString().isNotEmpty || (v['fleetUnitNumber'] ?? '').toString().isNotEmpty)
                                          Text('Driver: ${v['assignedDriver'] ?? '-'}  \u2022  Unit: ${v['fleetUnitNumber'] ?? '-'}',
                                              style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade700)),
                                      ],
                                    ),
                                    trailing: const Icon(Icons.chevron_right, size: 20),
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      _showMobileVehiclePassport(v['id'].toString());
                                    },
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMobileFilterChip(String label, String key, String activeKey, ValueChanged<String> onSelected) {
    final isSelected = activeKey == key;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? Colors.white : Colors.black87)),
      selected: isSelected,
      selectedColor: const Color(0xFF1E3A8A),
      backgroundColor: Colors.grey.shade100,
      visualDensity: VisualDensity.compact,
      onSelected: (_) => onSelected(key),
    );
  }

  void _showMobileVehiclePassport(String vehicleId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _MobileVehiclePassportSheet(
        vehicleId: vehicleId,
        baseUrl: _baseUrl,
      ),
    );
  }

  void _showCommunicationsSheet() {
    final pending = _jobs.where((j) => j['status'] == 'READY' || j['status'] == 'AWAITING_APPROVAL').toList();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (_, scroll) => Column(
          children: [
            const SizedBox(height: 12),
            const Text('Customer Follow-Ups', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const Text('Copy a ready message and send via SMS / WhatsApp', style: TextStyle(fontSize: 12, color: Colors.black54)),
            const Divider(),
            Expanded(
              child: pending.isEmpty
                  ? const Center(child: Text('No customers waiting for an update.'))
                  : ListView.builder(
                      controller: scroll,
                      itemCount: pending.length,
                      itemBuilder: (_, i) {
                        final j = pending[i];
                        final ready = j['status'] == 'READY';
                        final reg = j['vehicle']?['registrationNo'] ?? 'your vehicle';
                        final msg = ready
                            ? 'Hello ${j['customer']?['name'] ?? ''}, your vehicle $reg is ready for collection at AutoKe workshop. Thank you!'
                            : 'Hello ${j['customer']?['name'] ?? ''}, we have inspected $reg and prepared a quotation awaiting your approval. Please reply to authorise the repairs.';
                        return ListTile(
                          leading: Icon(ready ? Icons.check_circle : Icons.hourglass_top,
                              color: ready ? Colors.green : Colors.orange),
                          title: Text('${j['customer']?['name'] ?? ''} \u2022 $reg'),
                          subtitle: Text(msg, maxLines: 3, overflow: TextOverflow.ellipsis),
                          trailing: IconButton(
                            icon: const Icon(Icons.copy),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: '${j['customer']?['phone'] ?? ''}\n$msg'));
                              _toast('Message copied');
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateQuoteStatus(String estimateId, String newStatus) async {
    try {
      final res = await http.put(
        Uri.parse('$_baseUrl/estimates/$estimateId/status'),
        headers: AuthService.instance.authHeaders,
        body: json.encode({'status': newStatus}),
      );
      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: newStatus == 'APPROVED' ? Colors.green : (newStatus == 'REJECTED' ? Colors.red : Colors.blue),
              content: Text('Quotation status updated to $newStatus'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        _fetchJobs();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Error updating status: $e')),
        );
      }
    }
  }

  void _showQuotePreviewModal(Map<String, dynamic> e) {
    final jc = e['jobCard'];
    final cust = jc?['customer'];
    final veh = jc?['vehicle'];
    final status = (e['status'] ?? 'DRAFT').toString().toUpperCase();
    final total = (e['total'] is num) ? (e['total'] as num).toDouble() : (double.tryParse('${e['total']}') ?? 0.0);
    final subtotal = (e['subtotal'] is num) ? (e['subtotal'] as num).toDouble() : (double.tryParse('${e['subtotal']}') ?? total);
    final discountRate = (e['discountRate'] is num) ? (e['discountRate'] as num).toDouble() : 0.0;
    final taxRate = (e['taxRate'] is num) ? (e['taxRate'] as num).toDouble() : 16.0;
    final lineItems = (e['lineItems'] as List<dynamic>?) ?? [];

    final parts = lineItems.where((item) => (item['itemType'] ?? '').toString().toUpperCase() != 'LABOUR').toList();
    final labour = lineItems.where((item) => (item['itemType'] ?? '').toString().toUpperCase() == 'LABOUR').toList();

    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'APPROVED':
        statusColor = const Color(0xFF16A34A);
        statusIcon = Icons.check_circle_rounded;
        break;
      case 'SENT':
        statusColor = const Color(0xFF2563EB);
        statusIcon = Icons.send_rounded;
        break;
      case 'REJECTED':
        statusColor = const Color(0xFFDC2626);
        statusIcon = Icons.cancel_rounded;
        break;
      default:
        statusColor = const Color(0xFFD97706);
        statusIcon = Icons.edit_note_rounded;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Modal Handle & Top Header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                ),
                child: Column(
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(4)),
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F4C81).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.request_quote_rounded, color: Color(0xFF0F4C81), size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Quotation #${jc?['jobNumber'] ?? 'EST'}',
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: Color(0xFF0F172A)),
                              ),
                              Text(
                                'Job Card: ${jc?['jobNumber'] ?? 'N/A'} • ${_formatDate(e['createdAt'])}',
                                style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(statusIcon, size: 14, color: statusColor),
                              const SizedBox(width: 4),
                              Text(
                                status,
                                style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.grey),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Scrollable Quote Details Body
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Vehicle & Customer Info Card
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                // Kenyan style registration badge
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF08A),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.black87, width: 1.2),
                                  ),
                                  child: Text(
                                    (veh?['registrationNo'] ?? 'K-- ---').toString().toUpperCase(),
                                    style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.black, fontSize: 13, letterSpacing: 0.8),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${veh?['make'] ?? ''} ${veh?['model'] ?? ''}'.trim().isEmpty ? 'Vehicle' : '${veh?['make'] ?? ''} ${veh?['model'] ?? ''}'.toUpperCase(),
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                      Text(
                                        'Odometer: ${jc?['odometer'] ?? '-'} KM • Bay: ${jc?['bayNumber'] ?? 'General'}',
                                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 20),
                            Row(
                              children: [
                                const Icon(Icons.person_outline, size: 16, color: Color(0xFF0F4C81)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${cust?['name'] ?? 'Walk-in Customer'}',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                  ),
                                ),
                                if ((cust?['phone'] ?? '').toString().isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(6)),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.phone, size: 12, color: Color(0xFF2563EB)),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${cust?['phone']}',
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            if ((jc?['workRequested'] ?? '').toString().isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.build_circle_outlined, size: 16, color: Colors.orange),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Requested: ${jc?['workRequested']}',
                                      style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Line Items Breakdown
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Quoted Items & Services', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                Text('Amount (KES)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF64748B))),
                              ],
                            ),
                            const Divider(height: 18),

                            // Labour Items
                            if (labour.isNotEmpty) ...[
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4)),
                                      child: const Text('LABOUR & SERVICES', style: TextStyle(color: Color(0xFF1D4ED8), fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              ),
                              ...labour.map((item) {
                                final qty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
                                final up = (item['unitPrice'] as num?)?.toDouble() ?? 0.0;
                                final itmTot = (item['total'] as num?)?.toDouble() ?? (qty * up);
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.engineering_outlined, size: 16, color: Color(0xFF2563EB)),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(item['description'] ?? 'Labour service', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                            Text('${qty.toStringAsFixed(qty.truncateToDouble() == qty ? 0 : 1)} hr(s) @ KES ${up.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                          ],
                                        ),
                                      ),
                                      Text('KES ${itmTot.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    ],
                                  ),
                                );
                              }).toList(),
                              const SizedBox(height: 8),
                            ],

                            // Spare Parts & Supplies
                            if (parts.isNotEmpty) ...[
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(4)),
                                      child: const Text('PARTS & SUPPLIES', style: TextStyle(color: Color(0xFF0F766E), fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              ),
                              ...parts.map((item) {
                                final qty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
                                final up = (item['unitPrice'] as num?)?.toDouble() ?? 0.0;
                                final itmTot = (item['total'] as num?)?.toDouble() ?? (qty * up);
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.inventory_2_outlined, size: 16, color: Color(0xFF0F766E)),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(item['description'] ?? 'Replacement part', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                            Text('${qty.toStringAsFixed(qty.truncateToDouble() == qty ? 0 : 1)} pc(s) @ KES ${up.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                          ],
                                        ),
                                      ),
                                      Text('KES ${itmTot.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ],

                            if (lineItems.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(child: Text('No itemized parts or labour attached.', style: TextStyle(color: Colors.grey))),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Financial Summary Card
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Subtotal:', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                                Text('KES ${subtotal.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            if (discountRate > 0) ...[
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Discount (${discountRate.toStringAsFixed(0)}%):', style: const TextStyle(color: Color(0xFF34D399), fontSize: 13)),
                                  Text('- KES ${(subtotal * (discountRate / 100)).toStringAsFixed(0)}', style: const TextStyle(color: Color(0xFF34D399), fontSize: 13, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ],
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('VAT (${taxRate.toStringAsFixed(0)}%):', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                                Text('KES ${((subtotal * (1 - discountRate / 100)) * (taxRate / 100)).toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const Divider(color: Colors.white24, height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('GRAND TOTAL:', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
                                Text(
                                  'KES ${total.toStringAsFixed(0)}',
                                  style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 20, fontWeight: FontWeight.w900),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),

              // Bottom Action Bar
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -3))],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        // PDF Preview / Export Button
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              side: const BorderSide(color: Color(0xFF0F4C81)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.picture_as_pdf_outlined, color: Color(0xFF0F4C81), size: 18),
                            label: const Text('Export PDF', style: TextStyle(color: Color(0xFF0F4C81), fontWeight: FontWeight.bold)),
                            onPressed: () async {
                              final ws = _workshopSettings.isNotEmpty ? _workshopSettings : {
                                'name': 'AutoKe Workshop Ltd',
                                'phone': '0700 000 000',
                                'email': 'service@autocare.com',
                                'address': 'Nairobi, Kenya',
                                'currency': 'KES',
                              };
                              await InvoicePdfService.exportPdfFile(
                                workshopSettings: ws,
                                estimate: e,
                                isInvoice: false,
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Print Button
                        IconButton(
                          tooltip: 'Print Quotation',
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFFEFF6FF),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.all(12),
                          ),
                          icon: const Icon(Icons.print_outlined, color: Color(0xFF1D4ED8)),
                          onPressed: () async {
                            final ws = _workshopSettings.isNotEmpty ? _workshopSettings : {
                              'name': 'AutoKe Workshop Ltd',
                              'phone': '0700 000 000',
                              'email': 'service@autocare.com',
                              'address': 'Nairobi, Kenya',
                              'currency': 'KES',
                            };
                            await InvoicePdfService.printDocument(
                              workshopSettings: ws,
                              estimate: e,
                              isInvoice: false,
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Quick Status Action Button
                    if (status != 'APPROVED')
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF16A34A),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.check_circle_outline, size: 18),
                          label: const Text('Approve Quotation (Customer Confirmed)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await _updateQuoteStatus(e['id'], 'APPROVED');
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(dynamic dateRaw) {
    if (dateRaw == null) return '';
    try {
      final dt = DateTime.parse(dateRaw.toString());
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '';
    }
  }

  void _openCreateEstimateModal({String? initialJobCardId}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.90,
          minChildSize: 0.50,
          maxChildSize: 0.96,
          builder: (_, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 6),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      padding: EdgeInsets.only(
                        left: 14,
                        right: 14,
                        bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
                        top: 4,
                      ),
                      child: EstimateForm(
                        initialJobCardId: initialJobCardId,
                        isModal: true,
                        onCancel: () => Navigator.pop(ctx),
                        onSaved: () {
                          Navigator.pop(ctx);
                          _fetchJobs();
                        },
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildQuotesView() {
    if (_isLoadingJobs && _estimates.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // Filter estimates based on search and status
    final filtered = _estimates.where((e) {
      final status = (e['status'] ?? 'DRAFT').toString().toUpperCase();
      if (_quoteStatusFilter != 'ALL') {
        if (_quoteStatusFilter == 'PENDING' && (status != 'SENT' && status != 'DRAFT')) return false;
        if (_quoteStatusFilter != 'PENDING' && status != _quoteStatusFilter) return false;
      }
      if (_quoteSearch.isNotEmpty) {
        final q = _quoteSearch.toLowerCase();
        final jc = e['jobCard'];
        final plate = (jc?['vehicle']?['registrationNo'] ?? '').toString().toLowerCase();
        final make = (jc?['vehicle']?['make'] ?? '').toString().toLowerCase();
        final model = (jc?['vehicle']?['model'] ?? '').toString().toLowerCase();
        final cust = (jc?['customer']?['name'] ?? '').toString().toLowerCase();
        final jobNo = (jc?['jobNumber'] ?? '').toString().toLowerCase();
        return plate.contains(q) || make.contains(q) || model.contains(q) || cust.contains(q) || jobNo.contains(q);
      }
      return true;
    }).toList();

    // Stats calculations
    final totalQuotes = _estimates.length;
    final approvedCount = _estimates.where((e) => (e['status'] ?? '').toString().toUpperCase() == 'APPROVED').length;
    final pendingCount = _estimates.where((e) => (e['status'] ?? '').toString().toUpperCase() == 'SENT').length;
    double totalVal = 0.0;
    for (final e in _estimates) {
      totalVal += (e['total'] as num?)?.toDouble() ?? 0.0;
    }

    return RefreshIndicator(
      onRefresh: _fetchJobs,
      child: Column(
        children: [
          // Top Metrics Overview Banner
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            color: Colors.white,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _metricStatBox(
                        title: 'Total Quotes',
                        value: '$totalQuotes',
                        subtitle: 'KES ${totalVal.toStringAsFixed(0)}',
                        icon: Icons.request_quote_rounded,
                        color: const Color(0xFF0F4C81),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _metricStatBox(
                        title: 'Awaiting Client',
                        value: '$pendingCount',
                        subtitle: 'Pending Approval',
                        icon: Icons.schedule_rounded,
                        color: Colors.blue.shade700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _metricStatBox(
                        title: 'Approved',
                        value: '$approvedCount',
                        subtitle: 'Ready for Bay',
                        icon: Icons.check_circle_outline_rounded,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Create New Estimate Banner Button for Advisors
                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: ElevatedButton.icon(
                    onPressed: () => _openCreateEstimateModal(),
                    icon: const Icon(Icons.add_circle, size: 18),
                    label: const Text('Create New Estimate / Quotation', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Search Input
                Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    onChanged: (v) => setState(() => _quoteSearch = v),
                    decoration: InputDecoration(
                      hintText: 'Search plate, customer, job #...',
                      hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                      prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF64748B)),
                      suffixIcon: _quoteSearch.isNotEmpty
                          ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () => setState(() => _quoteSearch = ''))
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Status Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _statusFilterChip('ALL', 'All ($totalQuotes)'),
                      _statusFilterChip('SENT', 'Pending ($pendingCount)'),
                      _statusFilterChip('APPROVED', 'Approved ($approvedCount)'),
                      _statusFilterChip('DRAFT', 'Drafts'),
                      _statusFilterChip('REJECTED', 'Rejected'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Quotes List
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.request_quote_outlined, size: 60, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(
                            _quoteSearch.isNotEmpty || _quoteStatusFilter != 'ALL' ? 'No quotations match filters.' : 'No quotations yet.',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 15, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 6),
                          const Text('Estimates created from Job Cards will appear here.', style: TextStyle(color: Colors.grey, fontSize: 12), textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: () => _openCreateEstimateModal(),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Create New Estimate', style: TextStyle(fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final e = filtered[i];
                      final status = (e['status'] ?? 'DRAFT').toString().toUpperCase();
                      final jc = e['jobCard'];
                      final cust = jc?['customer'];
                      final veh = jc?['vehicle'];
                      final total = (e['total'] is num) ? (e['total'] as num).toStringAsFixed(0) : '0';
                      final lineItems = (e['lineItems'] as List?) ?? [];
                      final regNo = (veh?['registrationNo'] ?? 'K-- ---').toString().toUpperCase();

                      Color statusColor;
                      switch (status) {
                        case 'APPROVED':
                          statusColor = const Color(0xFF16A34A);
                          break;
                        case 'SENT':
                          statusColor = const Color(0xFF2563EB);
                          break;
                        case 'REJECTED':
                          statusColor = const Color(0xFFDC2626);
                          break;
                        default:
                          statusColor = const Color(0xFFD97706);
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2)),
                          ],
                        ),
                        child: InkWell(
                          onTap: () => _showQuotePreviewModal(e),
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Top Row: Plate, Make/Model, Status Badge
                                Row(
                                  children: [
                                    // Plate badge
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFEF08A),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.black87, width: 1.1),
                                      ),
                                      child: Text(
                                        regNo,
                                        style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.black, fontSize: 11, letterSpacing: 0.6),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${veh?['make'] ?? ''} ${veh?['model'] ?? ''}'.trim().isEmpty ? 'Vehicle' : '${veh?['make'] ?? ''} ${veh?['model'] ?? ''}',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            'Job #${jc?['jobNumber'] ?? ''}',
                                            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                                      ),
                                      child: Text(
                                        status,
                                        style: TextStyle(color: statusColor, fontSize: 10.5, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 18),

                                // Customer & Item Count Row
                                Row(
                                  children: [
                                    const Icon(Icons.person_outline, size: 14, color: Color(0xFF64748B)),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        '${cust?['name'] ?? 'Walk-in'}',
                                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      '${lineItems.length} item(s)',
                                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),

                                // Price & Quick Actions Row
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Total Estimate', style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B))),
                                        Text(
                                          'KES $total',
                                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF0F4C81)),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        // Preview button
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF0F4C81),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                            elevation: 0,
                                          ),
                                          icon: const Icon(Icons.visibility_outlined, size: 15),
                                          label: const Text('Preview', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                          onPressed: () => _showQuotePreviewModal(e),
                                        ),
                                        const SizedBox(width: 6),
                                        // PDF Export
                                        IconButton(
                                          tooltip: 'Export PDF',
                                          style: IconButton.styleFrom(
                                            backgroundColor: const Color(0xFFF1F5F9),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                            padding: const EdgeInsets.all(8),
                                          ),
                                          icon: const Icon(Icons.picture_as_pdf_outlined, size: 18, color: Color(0xFF0F4C81)),
                                          onPressed: () async {
                                            final ws = _workshopSettings.isNotEmpty ? _workshopSettings : {
                                              'name': 'AutoKe Workshop Ltd',
                                              'phone': '0700 000 000',
                                              'email': 'service@autocare.com',
                                              'address': 'Nairobi, Kenya',
                                              'currency': 'KES',
                                            };
                                            await InvoicePdfService.exportPdfFile(
                                              workshopSettings: ws,
                                              estimate: e,
                                              isInvoice: false,
                                            );
                                          },
                                        ),
                                        // Quick Status Menu
                                        PopupMenuButton<String>(
                                          icon: const Icon(Icons.more_vert, size: 18, color: Color(0xFF64748B)),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          onSelected: (val) => _updateQuoteStatus(e['id'], val),
                                          itemBuilder: (_) => const [
                                            PopupMenuItem(value: 'APPROVED', child: Text('Mark as Approved', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))),
                                            PopupMenuItem(value: 'SENT', child: Text('Mark as Sent')),
                                            PopupMenuItem(value: 'DRAFT', child: Text('Mark as Draft')),
                                            PopupMenuItem(value: 'REJECTED', child: Text('Mark as Rejected', style: TextStyle(color: Colors.red))),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _metricStatBox({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: color),
          ),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 9.5, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _statusFilterChip(String key, String label) {
    final selected = _quoteStatusFilter == key;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
        selected: selected,
        selectedColor: const Color(0xFFDBEAFE),
        onSelected: (_) => setState(() => _quoteStatusFilter = key),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SHARED JOB CARD LIST / CARD (HIGH SCALE + AUTOMOTIVE IDENTITY)
  // ---------------------------------------------------------------------------
  Widget _jobCard(dynamic job, {bool techMode = false}) {
    final jobNo = (job['jobNumber'] ?? job['id'].toString().substring(0, 8).toUpperCase()).toString();
    final customer = (job['customer']?['name'] ?? 'Customer').toString();
    final phone = (job['customer']?['phone'] ?? '').toString();
    final vehicle = '${job['vehicle']?['make'] ?? ''} ${job['vehicle']?['model'] ?? ''}'.trim();
    final reg = (job['vehicle']?['registrationNo'] ?? '').toString().trim();
    final status = (job['status'] ?? 'IN_PROGRESS').toString();
    final color = _statusColor(status);
    final stageIdx = _stageIndex(status);
    final priority = (job['priority'] ?? 'Medium').toString();
    final isHighPriority = priority.toLowerCase() == 'high' || priority.toLowerCase() == 'urgent';
    final bay = (job['bayNumber'] ?? '').toString();
    final tech = (job['technician'] ?? '').toString().trim();
    final hasTech = tech.isNotEmpty && tech.toLowerCase() != 'unassigned';
    final odo = job['odometer'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isHighPriority ? const Color(0xFFFCA5A5) : const Color(0xFFE2E8F0),
          width: isHighPriority ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openJobSheet(Map<String, dynamic>.from(job), techMode: techMode),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ROW 1: KENYAN LICENSE PLATE BADGE, JOB NUMBER, PRIORITY & WORKFLOW STATUS
              Row(
                children: [
                  // KENYAN LICENSE PLATE BADGE
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF08A),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: Colors.black87, width: 1.4),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 2, offset: const Offset(0, 1)),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                          decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(2)),
                          child: const Text('KE', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900)),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          reg.isNotEmpty ? reg.toUpperCase() : 'NO PLATE',
                          style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            fontFamily: 'monospace',
                            letterSpacing: 0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // JOB NO
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: Text(
                      jobNo,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF334155)),
                    ),
                  ),
                  if (isHighPriority) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFFCA5A5)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.local_fire_department, size: 12, color: Color(0xFFDC2626)),
                          SizedBox(width: 2),
                          Text('HIGH', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFFDC2626))),
                        ],
                      ),
                    ),
                  ],
                  Builder(builder: (_) {
                    final wad = job['walkAroundData'] is Map ? (job['walkAroundData'] as Map) : null;
                    final recs = (wad != null && wad['recommendations'] is List) ? (wad['recommendations'] as List) : [];
                    if (recs.isEmpty) return const SizedBox.shrink();
                    return Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFF59E0B)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lightbulb, size: 11, color: Color(0xFFB45309)),
                          const SizedBox(width: 3),
                          Text(
                            '${recs.length} Tech Finding${recs.length > 1 ? "s" : ""}',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFFB45309)),
                          ),
                        ],
                      ),
                    );
                  }),
                  const Spacer(),
                  // CLICKABLE STATUS BADGE
                  InkWell(
                    onTap: () => _showQuickStatusPicker(Map<String, dynamic>.from(job)),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: color.withOpacity(0.35)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_statusIcon(status), size: 12, color: color),
                          const SizedBox(width: 4),
                          Text(
                            _prettyStatus(status),
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color),
                          ),
                          const SizedBox(width: 2),
                          Icon(Icons.arrow_drop_down, size: 14, color: color),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // ROW 2: VEHICLE MODEL & WORK REQUESTED
              Row(
                children: [
                  Expanded(
                    child: Text(
                      vehicle.isNotEmpty ? vehicle : 'Vehicle Specification Pending',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF0F172A)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildFuelTypePill((job['fuelType'] ?? job['vehicle']?['fuelType'] ?? 'Petrol').toString()),
                ],
              ),
              const SizedBox(height: 3),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.build_circle_outlined, size: 14, color: Color(0xFF64748B)),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      job['workRequested']?.toString().isNotEmpty == true
                          ? job['workRequested'].toString()
                          : 'General Workshop Service & Inspection',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF475569), fontSize: 12.5, height: 1.3),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // ROW 3: 7-STAGE WORKFLOW PROGRESS STEPPER
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Workflow: Stage $stageIdx of 7 (${_stageTitle(status)})',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
                      ),
                      Text(
                        '${((stageIdx / 7.0) * 100).toInt()}%',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: stageIdx / 7.0,
                      minHeight: 5,
                      backgroundColor: const Color(0xFFE2E8F0),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // ROW 4: CUSTOMER DETAILS STRIP WITH 1-TAP WHATSAPP & PHONE CALL
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 13,
                      backgroundColor: const Color(0xFFDBEAFE),
                      child: Text(
                        customer.isNotEmpty ? customer[0].toUpperCase() : 'C',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            customer,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (phone.isNotEmpty)
                            Text(
                              phone,
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            ),
                        ],
                      ),
                    ),
                    if (phone.isNotEmpty) ...[
                      // 1-Tap WhatsApp
                      InkWell(
                        onTap: () => _openWhatsApp(customer, phone, reg, status),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.chat, size: 16, color: Color(0xFF15803D)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // 1-Tap Direct Call
                      InkWell(
                        onTap: () => _makePhoneCall(phone),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDBEAFE),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.phone, size: 16, color: Color(0xFF1D4ED8)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // ROW 5: WORKSHOP LOGISTICS BADGES (Bay, Tech, Mileage)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  // Technician badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: hasTech ? const Color(0xFFEEF2FF) : const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: hasTech ? const Color(0xFFC7D2FE) : const Color(0xFFFCD34D)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(hasTech ? Icons.engineering : Icons.warning_amber_rounded, size: 13, color: hasTech ? const Color(0xFF4338CA) : const Color(0xFFB45309)),
                        const SizedBox(width: 4),
                        Text(
                          hasTech ? tech : 'Unassigned Tech',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: hasTech ? const Color(0xFF3730A3) : const Color(0xFFB45309),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Bay badge
                  if (bay.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.garage_outlined, size: 13, color: Color(0xFF475569)),
                          const SizedBox(width: 4),
                          Text(bay, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
                        ],
                      ),
                    ),
                  // Odometer
                  if (odo != null && odo > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.speed, size: 13, color: Color(0xFF64748B)),
                          const SizedBox(width: 4),
                          Text('$odo km', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
                        ],
                      ),
                    ),
                ],
              ),

              const Divider(height: 18),

              // ROW 6: ACTION FOOTER
              Row(
                children: [
                  // Quick Status
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => _showQuickStatusPicker(Map<String, dynamic>.from(job)),
                    icon: const Icon(Icons.published_with_changes, size: 14, color: Color(0xFF0F4C81)),
                    label: const Text('Status', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF0F4C81))),
                  ),
                  const SizedBox(width: 8),
                  // Quotes shortcut / Quick Create Estimate
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () {
                      final hasEstimate = _estimates.any((e) =>
                          e['jobCardId'] == job['id'] || e['jobCard']?['id'] == job['id']);
                      if (hasEstimate) {
                        setState(() {
                          _selectedIndex = 3;
                          _quoteSearch = reg.isNotEmpty ? reg : jobNo;
                        });
                      } else {
                        _openCreateEstimateModal(initialJobCardId: job['id']);
                      }
                    },
                    icon: const Icon(Icons.request_quote_outlined, size: 14, color: Color(0xFF2563EB)),
                    label: Text(
                      _estimates.any((e) => e['jobCardId'] == job['id'] || e['jobCard']?['id'] == job['id'])
                          ? 'Quotes'
                          : '+ Quote',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
                    ),
                  ),
                  const Spacer(),
                  // View Job Sheet (Primary)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F4C81),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => _openJobSheet(Map<String, dynamic>.from(job), techMode: techMode),
                    icon: const Icon(Icons.description_outlined, size: 14),
                    label: const Text('Job Sheet', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<dynamic> _getFilteredJobs() {
    final q = _jobSearch.trim().toLowerCase();

    final filtered = _jobs.where((j) {
      final status = (j['status'] ?? 'BOOKED').toString();
      final bay = (j['bayNumber'] ?? '').toString();

      // KPI quick filter
      if (_selectedKpiFilter == 'ACTIVE' && status == 'COMPLETED') return false;
      if (_selectedKpiFilter == 'IN_REPAIR' && status != 'IN_PROGRESS') return false;
      if (_selectedKpiFilter == 'BLOCKED' && status != 'AWAITING_APPROVAL' && status != 'WAITING') return false;
      if (_selectedKpiFilter == 'READY' && status != 'READY') return false;

      // Status chip filter
      if (_jobStatusFilter != 'ALL' && status != _jobStatusFilter) return false;

      // Bay filter
      if (_jobBayFilter != 'ALL' && bay != _jobBayFilter) return false;

      // Search query across all fields
      if (q.isNotEmpty) {
        final jobNo = (j['jobNumber'] ?? '').toString().toLowerCase();
        final cust = (j['customer']?['name'] ?? '').toString().toLowerCase();
        final phone = (j['customer']?['phone'] ?? '').toString().toLowerCase();
        final plate = (j['vehicle']?['registrationNo'] ?? '').toString().toLowerCase();
        final make = (j['vehicle']?['make'] ?? '').toString().toLowerCase();
        final model = (j['vehicle']?['model'] ?? '').toString().toLowerCase();
        final tech = (j['technician'] ?? '').toString().toLowerCase();
        final work = (j['workRequested'] ?? '').toString().toLowerCase();

        final match = jobNo.contains(q) ||
            cust.contains(q) ||
            phone.contains(q) ||
            plate.contains(q) ||
            make.contains(q) ||
            model.contains(q) ||
            tech.contains(q) ||
            bay.toLowerCase().contains(q) ||
            work.contains(q);
        if (!match) return false;
      }

      return true;
    }).toList();

    filtered.sort((a, b) {
      if (_jobSortBy == 'PRIORITY') {
        final pA = _priorityWeight(a['priority']?.toString());
        final pB = _priorityWeight(b['priority']?.toString());
        return pB.compareTo(pA);
      } else if (_jobSortBy == 'PLATE') {
        final rA = (a['vehicle']?['registrationNo'] ?? '').toString();
        final rB = (b['vehicle']?['registrationNo'] ?? '').toString();
        return rA.compareTo(rB);
      } else if (_jobSortBy == 'CUSTOMER') {
        final cA = (a['customer']?['name'] ?? '').toString();
        final cB = (b['customer']?['name'] ?? '').toString();
        return cA.compareTo(cB);
      } else if (_jobSortBy == 'DUE_DATE') {
        final dA = a['dueDate'] != null ? DateTime.tryParse(a['dueDate'].toString()) : null;
        final dB = b['dueDate'] != null ? DateTime.tryParse(b['dueDate'].toString()) : null;
        if (dA == null) return 1;
        if (dB == null) return -1;
        return dA.compareTo(dB);
      } else {
        // NEWEST
        final tA = a['createdAt'] != null ? DateTime.tryParse(a['createdAt'].toString()) : null;
        final tB = b['createdAt'] != null ? DateTime.tryParse(b['createdAt'].toString()) : null;
        if (tA != null && tB != null) return tB.compareTo(tA);
        return (b['id'] ?? '').toString().compareTo((a['id'] ?? '').toString());
      }
    });

    return filtered;
  }

  Widget _buildJobsList() {
    if (_isLoadingJobs && _jobs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final total = _jobs.length;
    final activeCount = _jobs.where((j) => j['status'] != 'COMPLETED').length;
    final inRepairCount = _jobs.where((j) => j['status'] == 'IN_PROGRESS').length;
    final blockedCount = _jobs.where((j) => j['status'] == 'AWAITING_APPROVAL' || j['status'] == 'WAITING').length;
    final readyCount = _jobs.where((j) => j['status'] == 'READY').length;

    final shown = _getFilteredJobs();
    final hasActiveFilter = _jobBayFilter != 'ALL' || _jobSortBy != 'NEWEST' || _selectedKpiFilter != 'ALL';

    return Column(
      children: [
        // 1. TOP CAPACITY KPI METRICS (Handles High Volume Scalability)
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              _kpiMetricCard('All Active', '$activeCount', const Color(0xFF2563EB), _selectedKpiFilter == 'ACTIVE', () {
                setState(() {
                  _selectedKpiFilter = _selectedKpiFilter == 'ACTIVE' ? 'ALL' : 'ACTIVE';
                  _jobStatusFilter = 'ALL';
                });
              }),
              const SizedBox(width: 6),
              _kpiMetricCard('In Repair', '$inRepairCount', const Color(0xFF0F766E), _selectedKpiFilter == 'IN_REPAIR', () {
                setState(() {
                  _selectedKpiFilter = _selectedKpiFilter == 'IN_REPAIR' ? 'ALL' : 'IN_REPAIR';
                  _jobStatusFilter = 'ALL';
                });
              }),
              const SizedBox(width: 6),
              _kpiMetricCard('Waiting', '$blockedCount', const Color(0xFFD97706), _selectedKpiFilter == 'BLOCKED', () {
                setState(() {
                  _selectedKpiFilter = _selectedKpiFilter == 'BLOCKED' ? 'ALL' : 'BLOCKED';
                  _jobStatusFilter = 'ALL';
                });
              }),
              const SizedBox(width: 6),
              _kpiMetricCard('Ready', '$readyCount', const Color(0xFF16A34A), _selectedKpiFilter == 'READY', () {
                setState(() {
                  _selectedKpiFilter = _selectedKpiFilter == 'READY' ? 'ALL' : 'READY';
                  _jobStatusFilter = 'ALL';
                });
              }),
            ],
          ),
        ),

        // 2. SEARCH & SORT BAR
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4, offset: const Offset(0, 1)),
                    ],
                  ),
                  child: TextField(
                    controller: _jobSearchCtrl,
                    onChanged: (v) => setState(() => _jobSearch = v),
                    decoration: InputDecoration(
                      hintText: 'Search plate, customer, phone, job #...',
                      hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                      prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF0F4C81)),
                      suffixIcon: _jobSearch.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _jobSearchCtrl.clear();
                                setState(() => _jobSearch = '');
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Sort & Filter Sheet Button
              InkWell(
                onTap: _showJobsFilterSheet,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 44,
                  width: 44,
                  decoration: BoxDecoration(
                    color: hasActiveFilter ? const Color(0xFF0F4C81) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: hasActiveFilter ? const Color(0xFF0F4C81) : const Color(0xFFCBD5E1)),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4, offset: const Offset(0, 1)),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        Icons.tune,
                        size: 20,
                        color: hasActiveFilter ? Colors.white : const Color(0xFF0F4C81),
                      ),
                      if (hasActiveFilter)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: Color(0xFF38BDF8),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // 3. HORIZONTAL STAGE FILTER CHIPS (7-Stage Navigation)
        Container(
          height: 38,
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              _jobStageChip('ALL', 'All ($total)'),
              _jobStageChip('BOOKED', 'Checked-In (${_countStatus("BOOKED")})'),
              _jobStageChip('INSPECTION', 'Inspection (${_countStatus("INSPECTION")})'),
              _jobStageChip('AWAITING_APPROVAL', 'Awaiting OK (${_countStatus("AWAITING_APPROVAL")})'),
              _jobStageChip('IN_PROGRESS', 'In Repair (${_countStatus("IN_PROGRESS")})'),
              _jobStageChip('WAITING', 'Waiting Parts (${_countStatus("WAITING")})'),
              _jobStageChip('QUALITY_CHECK', 'QC (${_countStatus("QUALITY_CHECK")})'),
              _jobStageChip('READY', 'Ready (${_countStatus("READY")})'),
              _jobStageChip('COMPLETED', 'Delivered (${_countStatus("COMPLETED")})'),
            ],
          ),
        ),

        // 4. ACTIVE FILTERS PILL BANNER
        if (hasActiveFilter)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 4),
            child: Row(
              children: [
                const Icon(Icons.filter_alt, size: 14, color: Color(0xFF2563EB)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Active Filter: ${_selectedKpiFilter != "ALL" ? "KPI: $_selectedKpiFilter \u2022 " : ""}${_jobBayFilter != "ALL" ? "Bay: $_jobBayFilter \u2022 " : ""}Sort: $_jobSortBy',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  onTap: () => setState(() {
                    _jobBayFilter = 'ALL';
                    _jobSortBy = 'NEWEST';
                    _selectedKpiFilter = 'ALL';
                  }),
                  child: const Text('Reset', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red)),
                ),
              ],
            ),
          ),

        // 5. JOB CARDS LIST
        Expanded(
          child: shown.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.directions_car_outlined, size: 54, color: Colors.grey),
                      const SizedBox(height: 10),
                      Text(
                        _jobSearch.isNotEmpty || _jobStatusFilter != 'ALL' || hasActiveFilter
                            ? 'No job cards match your filter criteria.'
                            : 'No job cards found in the system.',
                        style: const TextStyle(fontSize: 15, color: Colors.black54, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 12),
                      if (_jobSearch.isNotEmpty || _jobStatusFilter != 'ALL' || hasActiveFilter)
                        TextButton.icon(
                          onPressed: () {
                            _jobSearchCtrl.clear();
                            setState(() {
                              _jobSearch = '';
                              _jobStatusFilter = 'ALL';
                              _jobBayFilter = 'ALL';
                              _jobSortBy = 'NEWEST';
                              _selectedKpiFilter = 'ALL';
                            });
                          },
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Reset All Filters'),
                        )
                      else
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F4C81), foregroundColor: Colors.white),
                          onPressed: () => setState(() => _selectedIndex = 2),
                          icon: const Icon(Icons.add),
                          label: const Text('Create Intake Job Card'),
                        ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchJobs,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                    itemCount: shown.length,
                    itemBuilder: (_, i) => _jobCard(shown[i]),
                  ),
                ),
        ),
      ],
    );
  }

  int _countStatus(String s) => _jobs.where((j) => j['status'] == s).length;

  Widget _kpiMetricCard(String title, String count, Color color, bool selected, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(
            color: selected ? color : color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? color : color.withOpacity(0.2)),
          ),
          child: Column(
            children: [
              Text(
                count,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: selected ? Colors.white : color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : const Color(0xFF475569),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _jobStageChip(String key, String label) {
    final selected = _jobStatusFilter == key;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.bold : FontWeight.w600,
            color: selected ? const Color(0xFF0F4C81) : const Color(0xFF475569),
          ),
        ),
        selected: selected,
        backgroundColor: Colors.white,
        selectedColor: const Color(0xFFDBEAFE),
        side: BorderSide(color: selected ? const Color(0xFF2563EB) : const Color(0xFFCBD5E1)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        onSelected: (_) => setState(() {
          _jobStatusFilter = key;
          _selectedKpiFilter = 'ALL';
        }),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TECHNICIAN WORKSPACE
  // ---------------------------------------------------------------------------
  String _requestStatusFilter = 'ALL';

  Widget _buildTechnicianBody() {
    if (_selectedIndex == 1) {
      return _buildTechnicianRequestsBody();
    }
    final showCompleted = _selectedIndex == 2;
    final auth = AuthService.instance;
    final isPrivileged = auth.isOwner || auth.isManager;

    final mine = _jobs.where((j) {
      final done = j['status'] == 'COMPLETED';
      if (done != showCompleted) return false;
      if (!isPrivileged) {
        final assigned = (j['technician'] ?? '').toString().trim().toLowerCase();
        final me = auth.userName.trim().toLowerCase();
        return assigned.isNotEmpty && (assigned == me || assigned.contains(me) || me.contains(assigned));
      }
      if (_techName == 'All') return true;
      return (j['technician'] ?? '').toString() == _techName;
    }).toList();

    return Column(
      children: [
        if (!isPrivileged)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.blue.shade100),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4, offset: const Offset(0, 1)),
              ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: const Color(0xFF0F4C81),
                  child: Text(
                    auth.userName.isNotEmpty ? auth.userName[0].toUpperCase() : 'T',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        auth.userName.isNotEmpty ? auth.userName : 'Technician',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Text(
                        'Workshop Bay \u2022 Assigned Jobs (${mine.length})',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    auth.role,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF0F4C81)),
                  ),
                ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              value: (_techName == 'All' || _technicians.contains(_techName)) ? _techName : 'All',
              decoration: InputDecoration(
                labelText: 'Technician Bay Filter (Admin View)',
                prefixIcon: const Icon(Icons.badge_outlined),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
              items: ['All', ..._technicians]
                  .map((t) => DropdownMenuItem(
                        value: t,
                        child: Text(t == 'All' ? 'All technicians (bay view)' : t, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) {
                setState(() => _techName = v ?? 'All');
                _fetchJobs();
              },
            ),
          ),
        Expanded(
          child: _isLoadingJobs && _jobs.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : mine.isEmpty
                  ? const Center(child: Text('No jobs here.', style: TextStyle(color: Colors.grey)))
                  : RefreshIndicator(
                      onRefresh: _fetchJobs,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: mine.length,
                        itemBuilder: (_, i) => _jobCard(mine[i], techMode: true),
                      ),
                    ),
        ),
      ],
    );
  }


  Widget _buildTechnicianRequestsBody() {
    final filtered = _itemRequests.where((r) {
      if (_requestStatusFilter == 'ALL') return true;
      return (r['status'] ?? '').toString().toUpperCase() == _requestStatusFilter;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F4C81),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.add_shopping_cart, size: 18),
                  label: const Text('Request Parts, Tools or Supplies', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () => _showItemRequestDialog(),
                ),
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: ['ALL', 'PENDING', 'ORDERED', 'APPROVED', 'PARTIALLY_ISSUED', 'ISSUED', 'REJECTED']
                .map((s) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(s.replaceAll('_', ' '), style: const TextStyle(fontSize: 11)),
                        selected: _requestStatusFilter == s,
                        onSelected: (_) => setState(() => _requestStatusFilter = s),
                      ),
                    ))
                .toList(),
          ),
        ),
        Expanded(
          child: _isLoadingJobs && _itemRequests.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.inventory_2_outlined, size: 56, color: Colors.grey),
                          const SizedBox(height: 12),
                          const Text('No item requests found.', style: TextStyle(color: Colors.grey, fontSize: 16)),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: () => _showItemRequestDialog(),
                            icon: const Icon(Icons.add),
                            label: const Text('Create First Request'),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchJobs,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: filtered.length,
                        itemBuilder: (_, i) => _buildRequestCard(filtered[i]),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildRequestCard(dynamic req) {
    final status = (req['status'] ?? 'PENDING').toString();
    final lines = (req['lines'] as List<dynamic>?) ?? [];
    final ref = req['reference'] ?? 'REQ';
    final reason = req['reason'] ?? '-';
    final bool hasIssuedItems = lines.any((l) => (l['qtyIssued'] ?? 0) > 0);
    final bool acknowledged = req['acknowledgedAt'] != null;

    Color badgeColor;
    switch (status) {
      case 'APPROVED': badgeColor = Colors.green; break;
      case 'ORDERED': badgeColor = Colors.indigo; break;
      case 'ISSUED': badgeColor = Colors.blue; break;
      case 'PARTIALLY_ISSUED': badgeColor = Colors.orange; break;
      case 'REJECTED': badgeColor = Colors.red; break;
      case 'CANCELLED': badgeColor = Colors.grey; break;
      default: badgeColor = Colors.amber.shade800;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(ref, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: badgeColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                  child: Text(status.replaceAll('_', ' '), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: badgeColor)),
                ),
              ],
            ),
            if (req['vehiclePlate'] != null || req['jobNumber'] != null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.directions_car, size: 13, color: Color(0xFF0F4C81)),
                    const SizedBox(width: 4),
                    Text(
                      '${req['vehiclePlate'] ?? ''}${req['vehicleDescription'] != null ? ' (${req['vehicleDescription']})' : ''}${req['jobNumber'] != null ? ' • ${req['jobNumber']}' : ''}'.trim(),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0F4C81)),
                    ),
                  ],
                ),
              ),
            ],
            if (status == 'ORDERED') ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.indigo.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.local_shipping, size: 16, color: Colors.indigo),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Ordered from Supplier • PO: ${req['poNumber'] ?? '-'} • ETA: ${req['estimatedArrival'] ?? 'TBA'}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 6),
            Text('Reason: $reason', style: const TextStyle(fontSize: 13, color: Colors.black87)),
            if (req['jobCardId'] != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.assignment, size: 14, color: Colors.black54),
                  const SizedBox(width: 4),
                  Text('Job Card: ${req['jobNumber'] ?? req['jobCardId'].toString().substring(0, 8).toUpperCase()}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ],
              ),
            ],
            const Divider(height: 20),
            const Text('Items Requested:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
            const SizedBox(height: 6),
            ...lines.map((l) {
              final cat = (l['category'] ?? 'SPARE_PART').toString();
              final desc = l['description'] ?? 'Item';
              final qReq = l['qtyRequested'] ?? 0;
              final qApp = l['qtyApproved'] ?? 0;
              final qIss = l['qtyIssued'] ?? 0;
              final qRet = l['qtyReturned'] ?? 0;
              final canReturn = qIss > qRet;

              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: cat == 'TOOL_EQUIPMENT' ? Colors.purple.shade50 : cat == 'CONSUMABLE' ? Colors.teal.shade50 : Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  cat == 'TOOL_EQUIPMENT' ? 'TOOL' : cat == 'CONSUMABLE' ? 'SUPPLY' : 'PART',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    color: cat == 'TOOL_EQUIPMENT' ? Colors.purple.shade800 : cat == 'CONSUMABLE' ? Colors.teal.shade800 : Colors.blue.shade800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(child: Text(desc, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text('Req: $qReq  |  Appr: $qApp  |  Issued: $qIss  |  Returned: $qRet', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                        ],
                      ),
                    ),
                    if (canReturn)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero),
                        icon: const Icon(Icons.assignment_return, size: 14),
                        label: const Text('Return', style: TextStyle(fontSize: 11)),
                        onPressed: () => _showReturnDialog(Map<String, dynamic>.from(l), req['id'].toString()),
                      ),
                  ],
                ),
              );
            }),
            if (hasIssuedItems && !acknowledged) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Confirm Physical Receipt', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: () => _acknowledgeReceipt(req['id'].toString()),
                ),
              ),
            ],
            if (acknowledged) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified, size: 16, color: Colors.green),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Physical receipt confirmed by ${req['acknowledgedBy'] ?? 'Technician'}',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _acknowledgeReceipt(String requestId) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/inventory/requests/$requestId/acknowledge'),
        headers: {'Content-Type': 'application/json', 'x-user-role': 'MECHANIC', 'x-user-name': _techName},
      );
      if (res.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Receipt acknowledged!'), backgroundColor: Colors.green),
        );
        _fetchJobs();
      } else {
        final err = json.decode(res.body)['error'] ?? 'Failed';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err), backgroundColor: Colors.red));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  void _showReturnDialog(Map<String, dynamic> line, String requestId) {
    final qtyCtrl = TextEditingController(text: '1');
    final reasonCtrl = TextEditingController();
    String condition = 'GOOD';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Return: ${line['description']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity to Return', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                isExpanded: true,
                value: condition,
                decoration: const InputDecoration(labelText: 'Condition', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'GOOD', child: Text('Good - Unused', overflow: TextOverflow.ellipsis)),
                  DropdownMenuItem(value: 'DAMAGED', child: Text('Damaged', overflow: TextOverflow.ellipsis)),
                  DropdownMenuItem(value: 'DEFECTIVE', child: Text('Defective / Faulty', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setSheet(() => condition = v ?? 'GOOD'),
              ),
              const SizedBox(height: 10),
              TextField(controller: reasonCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Reason for Return', border: OutlineInputBorder())),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F4C81), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                  icon: const Icon(Icons.assignment_return),
                  label: const Text('Submit Return'),
                  onPressed: () async {
                    final res = await http.post(
                      Uri.parse('$_baseUrl/inventory/returns'),
                      headers: {'Content-Type': 'application/json', 'x-user-role': 'MECHANIC', 'x-user-name': _techName},
                      body: json.encode({
                        'requestId': requestId,
                        'itemId': line['itemId'],
                        'quantity': int.tryParse(qtyCtrl.text) ?? 1,
                        'condition': condition,
                        'reason': reasonCtrl.text.trim().isEmpty ? 'Unused - returning to store' : reasonCtrl.text.trim(),
                      }),
                    );
                    if (res.statusCode == 201) {
                      if (ctx.mounted) Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Return submitted for inspection!'), backgroundColor: Colors.green),
                      );
                      _fetchJobs();
                    } else {
                      final err = json.decode(res.body)['error'] ?? 'Return failed';
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err), backgroundColor: Colors.red));
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showItemRequestDialog({String? preselectedJobId, String? preselectedVehiclePlate}) {
    List<dynamic> catalogResults = [];
    Map<String, dynamic>? selectedItem;
    bool isCustomItem = false;
    final customDescCtrl = TextEditingController();
    String customCategory = 'SPARE_PART';
    final qtyCtrl = TextEditingController(text: '1');
    final reasonCtrl = TextEditingController();
    String? linkedJobId = preselectedJobId;
    String category = 'ALL';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Request Parts, Tools, or Supplies', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 12),
                if (preselectedJobId != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.directions_car, color: Color(0xFF0F4C81), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Vehicle: ${preselectedVehiclePlate ?? 'Assigned Vehicle'} (Requisition linked to this vehicle)',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF0F4C81)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Toggle: Catalog Item vs Custom/Order Item
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => setSheet(() => isCustomItem = false),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: !isCustomItem ? const Color(0xFF0F4C81) : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              'Inventory Catalog',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: !isCustomItem ? Colors.white : Colors.black87),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: () => setSheet(() => isCustomItem = true),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: isCustomItem ? Colors.amber.shade800 : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              'Custom / Order Needed',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isCustomItem ? Colors.white : Colors.black87),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                if (!isCustomItem) ...[
                  // Category filter chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: ['ALL', 'SPARE_PART', 'TOOL_EQUIPMENT', 'CONSUMABLE'].map((c) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(c == 'ALL' ? 'All' : c == 'SPARE_PART' ? 'Parts' : c == 'TOOL_EQUIPMENT' ? 'Tools' : 'Supplies', style: const TextStyle(fontSize: 11)),
                          selected: category == c,
                          onSelected: (_) => setSheet(() => category = c),
                        ),
                      )).toList(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Search field
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Search inventory catalog...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onChanged: (q) async {
                      if (q.length < 2) { setSheet(() => catalogResults = []); return; }
                      try {
                        final catParam = category == 'ALL' ? '' : '&category=$category';
                        final res = await http.get(
                          Uri.parse('$_baseUrl/inventory/catalog?search=$q$catParam'),
                          headers: AuthService.instance.authHeaders,
                        );
                        if (res.statusCode == 200) {
                          setSheet(() => catalogResults = json.decode(res.body));
                        }
                      } catch (_) {}
                    },
                  ),
                  if (catalogResults.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: catalogResults.length,
                        itemBuilder: (_, i) {
                          final item = catalogResults[i];
                          final cat = item['category'] ?? '';
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              cat == 'TOOL_EQUIPMENT' ? Icons.build : cat == 'CONSUMABLE' ? Icons.cleaning_services : Icons.settings,
                              color: cat == 'TOOL_EQUIPMENT' ? Colors.purple : cat == 'CONSUMABLE' ? Colors.teal : Colors.blue,
                              size: 20,
                            ),
                            title: Text(item['name'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            subtitle: Text('Stock: ${item['quantity'] ?? 0}  |  ${cat.replaceAll('_', ' ')}', style: const TextStyle(fontSize: 11)),
                            selected: selectedItem?['id'] == item['id'],
                            selectedTileColor: Colors.blue.shade50,
                            onTap: () => setSheet(() { selectedItem = Map<String, dynamic>.from(item); catalogResults = []; }),
                          );
                        },
                      ),
                    ),
                  ],
                  if (selectedItem != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(10)),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Selected: ${selectedItem!['name']} (${selectedItem!['category']})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        ],
                      ),
                    ),
                  ],
                ] else ...[
                  // Custom Item Input
                  TextField(
                    controller: customDescCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Part / Supply Name * (e.g. Oxygen Sensor Bank 1)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: customCategory,
                    decoration: const InputDecoration(labelText: 'Item Category', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'SPARE_PART', child: Text('Spare Part (Vehicle Repair)', overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'CONSUMABLE', child: Text('Workshop Consumable', overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'TOOL_EQUIPMENT', child: Text('Tool / Special Equipment', overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setSheet(() => customCategory = v ?? 'SPARE_PART'),
                  ),
                ],
                const SizedBox(height: 10),
                TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity *', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: reasonCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Reason for Request *', hintText: 'e.g. Front brake pads replacement for vehicle', border: OutlineInputBorder())),
                if (preselectedJobId == null) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: linkedJobId,
                    decoration: const InputDecoration(labelText: 'Select Assigned Vehicle / Job Card *', border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('-- General Workshop (No Job Card) --', overflow: TextOverflow.ellipsis)),
                      ..._jobs.where((j) => j['status'] != 'COMPLETED').map((j) {
                        final plate = j['vehicle']?['registrationNo'] ?? j['vehiclePlate'] ?? '';
                        final make = j['vehicle']?['make'] ?? '';
                        final model = j['vehicle']?['model'] ?? '';
                        final id = j['id'].toString();
                        final jNo = j['jobNumber'] ?? id.substring(0, 8).toUpperCase();
                        return DropdownMenuItem(
                          value: id,
                          child: Text('$plate ${make.isNotEmpty ? "($make $model)" : ""} • $jNo', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                        );
                      }),
                    ],
                    onChanged: (v) => setSheet(() => linkedJobId = v),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F4C81),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.send),
                    label: const Text('Submit Vehicle Requisition', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    onPressed: () async {
                      if (!isCustomItem && selectedItem == null) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select an item from catalog or switch to Custom Item'), backgroundColor: Colors.orange));
                        return;
                      }
                      if (isCustomItem && customDescCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter the part description'), backgroundColor: Colors.orange));
                        return;
                      }
                      if (reasonCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a reason for the request'), backgroundColor: Colors.orange));
                        return;
                      }

                      final qty = int.tryParse(qtyCtrl.text) ?? 1;
                      final line = isCustomItem
                          ? {
                              'category': customCategory,
                              'description': customDescCtrl.text.trim(),
                              'quantity': qty,
                            }
                          : {
                              'category': selectedItem!['category'],
                              'itemId': selectedItem!['id'],
                              'description': selectedItem!['name'],
                              'quantity': qty,
                            };

                      final body = <String, dynamic>{
                        'reason': reasonCtrl.text.trim(),
                        'lines': [line],
                      };
                      if (linkedJobId != null) body['jobCardId'] = linkedJobId;

                      try {
                        final res = await http.post(
                          Uri.parse('$_baseUrl/inventory/requests'),
                          headers: {'Content-Type': 'application/json', 'x-user-role': 'MECHANIC', 'x-user-name': _techName},
                          body: json.encode(body),
                        );
                        if (res.statusCode == 201) {
                          if (ctx.mounted) Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Requisition submitted! Appears in Storekeeper & Manager queue.'), backgroundColor: Colors.green),
                          );
                          _fetchJobs();
                        } else {
                          final err = json.decode(res.body)['error'] ?? 'Request failed';
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err), backgroundColor: Colors.red));
                        }
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const List<String> _inspectionPoints = [
    'Engine & Oil',
    'Brakes',
    'Suspension & Steering',
    'Tyres & Wheels',
    'Battery & Electrical',
    'Lights',
    'Cooling System',
    'Exhaust & Transmission',
  ];

  Future<void> _showAddRecommendationSheet(Map<String, dynamic> job, StateSetter setParentSheet) async {
    String selectedSystem = 'Engine';
    String urgency = 'RECOMMENDED';
    final issueCtrl = TextEditingController();
    final fixCtrl = TextEditingController();
    final partsCtrl = TextEditingController();
    final labourPriceCtrl = TextEditingController();
    final partsPriceCtrl = TextEditingController();
    bool isSubmitting = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bCtx) => StatefulBuilder(
        builder: (bCtx, setModal) => Container(
          padding: EdgeInsets.only(
            left: 18,
            right: 18,
            top: 16,
            bottom: MediaQuery.of(bCtx).viewInsets.bottom + 20,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.build_circle, color: Color(0xFFB45309), size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Technician Defect Finding & Recommendation', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          Text('For: ${job['vehicle']?['registrationNo'] ?? ''} (${job['vehicle']?['make'] ?? ''} ${job['vehicle']?['model'] ?? ''})', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: selectedSystem,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Affected System *', border: OutlineInputBorder(), isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'Engine', child: Text('⚙️ Engine & Mechanical')),
                    DropdownMenuItem(value: 'Braking System', child: Text('🛑 Braking System')),
                    DropdownMenuItem(value: 'Suspension & Steering', child: Text('🔧 Suspension & Steering')),
                    DropdownMenuItem(value: 'Transmission & Drivetrain', child: Text('🔄 Transmission & Gearbox')),
                    DropdownMenuItem(value: 'Electrical & Battery', child: Text('⚡ Electrical & Battery')),
                    DropdownMenuItem(value: 'Air Conditioning', child: Text('❄️ Air Conditioning & Heating')),
                    DropdownMenuItem(value: 'Tyres & Alignment', child: Text('🛞 Tyres & Wheel Alignment')),
                    DropdownMenuItem(value: 'Exhaust & Emissions', child: Text('💨 Exhaust & Emissions')),
                    DropdownMenuItem(value: 'Body & Paint', child: Text('🚗 Bodywork & Paint')),
                    DropdownMenuItem(value: 'General Service', child: Text('📋 General Workshop Inspection')),
                  ],
                  onChanged: (v) => setModal(() => selectedSystem = v ?? 'Engine'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: urgency,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Severity / Urgency *', border: OutlineInputBorder(), isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'CRITICAL', child: Text('🔴 CRITICAL (Immediate Safety Risk / Failure Imminent)')),
                    DropdownMenuItem(value: 'RECOMMENDED', child: Text('🟡 RECOMMENDED (Service Required Soon)')),
                    DropdownMenuItem(value: 'ADVISORY', child: Text('🟢 ADVISORY (Preventive / Monitor Closely)')),
                  ],
                  onChanged: (v) => setModal(() => urgency = v ?? 'RECOMMENDED'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: issueCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Defect / Issue Found * (e.g. Engine oil leak & misfire)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: fixCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Recommended Action / Repair * (e.g. Replace valve cover gasket & spark plugs)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: partsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Specific Parts Needed (Optional, e.g. 1x Gasket Kit, 4x Iridium Plugs)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: labourPriceCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Est. Labour (KES)',
                          prefixText: 'KES ',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: partsPriceCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Est. Parts (KES)',
                          prefixText: 'KES ',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F4C81),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: isSubmitting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send_rounded, size: 18),
                    label: Text(isSubmitting ? 'Saving Finding...' : 'Submit Recommendation to Workshop', style: const TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            final issue = issueCtrl.text.trim();
                            final fix = fixCtrl.text.trim();
                            if (issue.isEmpty || fix.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(backgroundColor: Colors.orange, content: Text('Please enter both the Issue and Recommended Repair.')),
                              );
                              return;
                            }
                            setModal(() => isSubmitting = true);
                            try {
                              final authHeaders = AuthService.instance.authHeaders;
                              final techName = AuthService.instance.userName.isNotEmpty ? AuthService.instance.userName : _techName;
                              final resp = await http.post(
                                Uri.parse('$_baseUrl/jobs/${job['id']}/recommendations'),
                                headers: {
                                  'Content-Type': 'application/json',
                                  ...authHeaders,
                                  'x-user-name': techName,
                                  'x-user-role': AuthService.instance.role,
                                },
                                body: json.encode({
                                  'system': selectedSystem,
                                  'issue': issue,
                                  'recommendation': fix,
                                  'urgency': urgency,
                                  'partsNeeded': partsCtrl.text.trim(),
                                  'estimatedLabour': double.tryParse(labourPriceCtrl.text.trim()) ?? 0.0,
                                  'estimatedParts': double.tryParse(partsPriceCtrl.text.trim()) ?? 0.0,
                                  'technicianName': techName,
                                }),
                              );
                              if (resp.statusCode == 201) {
                                final resData = json.decode(resp.body);
                                final newRec = resData['recommendation'];
                                if (job['walkAroundData'] is! Map) {
                                  job['walkAroundData'] = <String, dynamic>{};
                                }
                                final wad = job['walkAroundData'] as Map<String, dynamic>;
                                final recs = (wad['recommendations'] is List) ? List<dynamic>.from(wad['recommendations']) : [];
                                wad['recommendations'] = [newRec, ...recs];

                                setParentSheet(() {});
                                if (bCtx.mounted) Navigator.pop(bCtx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: Colors.green.shade700,
                                    content: const Text('Recommendation logged! Admin and Service Advisor have been notified.'),
                                  ),
                                );
                                SyncService.instance.triggerSync();
                              } else {
                                throw Exception(resp.body);
                              }
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(backgroundColor: Colors.red, content: Text('Error saving recommendation: $e')),
                              );
                            } finally {
                              if (bCtx.mounted) setModal(() => isSubmitting = false);
                            }
                          },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openJobSheet(Map<String, dynamic> job, {required bool techMode}) {
    final walk = job['walkAroundData'] is Map ? Map<String, dynamic>.from(job['walkAroundData']) : <String, dynamic>{};
    final tech = walk['techInspection'] is Map ? Map<String, dynamic>.from(walk['techInspection']) : <String, dynamic>{};
    final rawDiag = walk['diagnostics'] is Map ? Map<String, dynamic>.from(walk['diagnostics']) : <String, dynamic>{};
    final sheetDiag = <String, String>{
      'Engine': rawDiag['Engine']?.toString() ?? 'Pass',
      'Brakes': rawDiag['Brakes']?.toString() ?? 'Pass',
      'Suspension': rawDiag['Suspension']?.toString() ?? 'Pass',
      'Tyres': rawDiag['Tyres']?.toString() ?? 'Pass',
      'Battery': rawDiag['Battery']?.toString() ?? 'Pass',
      'Electrical': rawDiag['Electrical']?.toString() ?? 'Pass',
      'AC': rawDiag['AC']?.toString() ?? 'Pass',
      'Transmission': rawDiag['Transmission']?.toString() ?? 'Pass',
    };
    final results = <String, String>{
      for (final p in _inspectionPoints) p: (tech['results'] is Map ? tech['results'][p]?.toString() : null) ?? '',
    };
    final obdCtrl = TextEditingController(text: walk['obdCodes']?.toString() ?? tech['obdCodes']?.toString() ?? '');
    final notesCtrl = TextEditingController(text: tech['notes']?.toString() ?? '');
    final hoursCtrl = TextEditingController(text: job['actualHours']?.toString() ?? '');
    String status = (job['status'] ?? 'BOOKED').toString();
    String assigned = (job['technician'] ?? '').toString();
    final candidateTechs = {..._technicians, if (assigned.isNotEmpty && assigned != 'Unassigned') assigned}.toList();
    candidateTechs.sort((a, b) {
      final countA = _jobs.where((j) {
        if (j['id']?.toString() == job['id']?.toString()) return false;
        final st = (j['status'] ?? '').toString().toUpperCase();
        if (st == 'COMPLETED' || st == 'CANCELLED') return false;
        return (j['technician'] ?? '').toString().toLowerCase().trim() == a.toLowerCase().trim();
      }).length;
      final countB = _jobs.where((j) {
        if (j['id']?.toString() == job['id']?.toString()) return false;
        final st = (j['status'] ?? '').toString().toUpperCase();
        if (st == 'COMPLETED' || st == 'CANCELLED') return false;
        return (j['technician'] ?? '').toString().toLowerCase().trim() == b.toLowerCase().trim();
      }).length;
      if (countA != countB) return countA.compareTo(countB);
      return a.compareTo(b);
    });
    final techOptions = ['Unassigned', ...candidateTechs];
    List<Map<String, dynamic>> sheetPhotos = (walk['securityPhotos'] is List)
        ? (walk['securityPhotos'] as List).whereType<Map>().map((p) => Map<String, dynamic>.from(p)).toList()
        : <Map<String, dynamic>>[];
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.9,
          maxChildSize: 0.97,
          builder: (_, scroll) => Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('${job['jobNumber'] ?? 'Job Card'} \u2022 ${job['vehicle']?['registrationNo'] ?? ''}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(width: 8),
                    _buildFuelTypePill((job['fuelType'] ?? job['vehicle']?['fuelType'] ?? 'Petrol').toString()),
                  ],
                ),
                Text('${job['vehicle']?['make'] ?? ''} ${job['vehicle']?['model'] ?? ''} \u2022 ${job['customer']?['name'] ?? ''}',
                    style: const TextStyle(color: Colors.black54)),
                const SizedBox(height: 4),
                Text('Work requested: ${job['workRequested'] ?? '-'}'),
                const SizedBox(height: 14),
                const Text('Repair Stage', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: (techMode
                          ? ['INSPECTION', 'IN_PROGRESS', 'WAITING', 'QUALITY_CHECK']
                          : ['BOOKED', 'INSPECTION', 'AWAITING_APPROVAL', 'IN_PROGRESS', 'WAITING', 'QUALITY_CHECK', 'READY', 'COMPLETED'])
                      .map((s) => ChoiceChip(
                            label: Text(_prettyStatus(s), style: const TextStyle(fontSize: 11)),
                            selected: status == s,
                            selectedColor: _statusColor(s).withOpacity(0.2),
                            onSelected: (_) => setSheet(() => status = s),
                          ))
                      .toList(),
                ),
                if (!techMode) ...[
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: techOptions.contains(assigned) ? assigned : (assigned.isEmpty ? 'Unassigned' : techOptions.first),
                    decoration: const InputDecoration(
                      labelText: 'Assign / Re-assign Technician',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.engineering_outlined),
                    ),
                    items: techOptions
                        .map((t) {
                          if (t == 'Unassigned') {
                            return const DropdownMenuItem<String>(
                              value: 'Unassigned',
                              child: Row(
                                children: [
                                  Icon(Icons.person_outline, size: 16, color: Colors.grey),
                                  SizedBox(width: 8),
                                  Text('Unassigned / Open Pool', style: TextStyle(color: Colors.grey, fontSize: 13)),
                                ],
                              ),
                            );
                          }
                          final activeCount = _jobs.where((j) {
                            if (j['id']?.toString() == job['id']?.toString()) return false;
                            final st = (j['status'] ?? '').toString().toUpperCase();
                            if (st == 'COMPLETED' || st == 'CANCELLED') return false;
                            return (j['technician'] ?? '').toString().toLowerCase().trim() == t.toLowerCase().trim();
                          }).length;

                          return DropdownMenuItem<String>(
                            value: t,
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: activeCount == 0
                                        ? Colors.green
                                        : (activeCount <= 2 ? Colors.orange : Colors.red),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(t, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: (activeCount == 0 ? Colors.green : Colors.orange).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: (activeCount == 0 ? Colors.green : Colors.orange).withValues(alpha: 0.4)),
                                  ),
                                  child: Text(
                                    activeCount == 0 ? '🟢 Available (0)' : '🟡 Assigned ($activeCount)',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: activeCount == 0 ? Colors.green.shade800 : Colors.orange.shade900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        })
                        .toList(),
                    selectedItemBuilder: (ctx) => techOptions.map((t) {
                      if (t == 'Unassigned' || t.isEmpty) {
                        return const Text('Unassigned / Open Pool', style: TextStyle(color: Colors.grey, fontSize: 13));
                      }
                      final activeCount = _jobs.where((j) {
                        if (j['id']?.toString() == job['id']?.toString()) return false;
                        final st = (j['status'] ?? '').toString().toUpperCase();
                        if (st == 'COMPLETED' || st == 'CANCELLED') return false;
                        return (j['technician'] ?? '').toString().toLowerCase().trim() == t.toLowerCase().trim();
                      }).length;
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: activeCount == 0 ? Colors.green : Colors.orange,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '$t (${activeCount == 0 ? "Available" : "$activeCount active"})',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                    onChanged: (v) => setSheet(() => assigned = (v == null || v == 'Unassigned') ? '' : v),
                  ),
                ],
                if (techMode) ...[
                  const SizedBox(height: 16),
                  const Text('Mechanical & OBD-II Inspection', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  ..._inspectionPoints.map((p) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(child: Text(p, style: const TextStyle(fontSize: 13.5))),
                            ...[
                              ['PASS', Colors.green],
                              ['ATTENTION', Colors.orange],
                              ['FAIL', Colors.red],
                            ].map((o) {
                              final sel = results[p] == o[0];
                              final c = o[1] as Color;
                              return Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: GestureDetector(
                                  onTap: () => setSheet(() => results[p] = o[0] as String),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: sel ? c : c.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      o[0] == 'ATTENTION' ? 'WARN' : o[0] as String,
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: sel ? Colors.white : c),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      )),
                  const SizedBox(height: 10),
                  TextField(
                    controller: obdCtrl,
                    decoration: const InputDecoration(labelText: 'OBD-II fault codes (e.g. P0300)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notesCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Findings / parts needed', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Estimated hrs', border: OutlineInputBorder()),
                          child: Text(job['estimatedHours']?.toString() ?? '-'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: hoursCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Actual hrs', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
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
                        spacing: 8,
                        runSpacing: 8,
                        children: sheetDiag.keys.map((sys) {
                          final currentVal = sheetDiag[sys] ?? 'Pass';
                          final chipColor = currentVal == 'Pass'
                              ? Colors.green
                              : currentVal == 'Attention'
                                  ? Colors.orange
                                  : Colors.red;
                          return InkWell(
                            onTap: () {
                              setSheet(() {
                                sheetDiag[sys] = currentVal == 'Pass'
                                    ? 'Attention'
                                    : currentVal == 'Attention'
                                        ? 'Fail'
                                        : 'Pass';
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: chipColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: chipColor.withValues(alpha: 0.5)),
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
                        controller: obdCtrl,
                        decoration: const InputDecoration(
                          labelText: 'OBD-II Fault Codes / Scanner Notes (e.g. P0300 Random Misfire, ABS C1201)',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // -------------------------------------------------------------
                // VEHICLE CONDITION & SECURITY PHOTOS (NEON S3 STORAGE)
                // -------------------------------------------------------------
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blueGrey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.shield_outlined, size: 17, color: Color(0xFF1E3A8A)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Security & Condition Photos (${sheetPhotos.length}) \u2022 Neon S3',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E3A8A),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(Icons.add_a_photo, size: 13),
                            label: const Text('Add Photo', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            onPressed: () async {
                              final reg = job['vehicle']?['registrationNo']?.toString() ?? '';
                              final uploaded = await VehiclePhotoService.pickAndUploadPhoto(
                                context: context,
                                baseUrl: _baseUrl,
                                registrationNo: reg,
                                jobCardId: job['id']?.toString(),
                              );
                              if (uploaded != null) {
                                setSheet(() {
                                  sheetPhotos.add(uploaded);
                                  walk['securityPhotos'] = sheetPhotos;
                                });
                                _fetchJobs();
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (sheetPhotos.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.photo_library_outlined, size: 28, color: Colors.blueGrey.shade300),
                                const SizedBox(height: 4),
                                const Text('No security photos uploaded yet', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.blueGrey)),
                                Text('Tap "Add Photo" to snap 4-side photos or scratches', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                              ],
                            ),
                          ),
                        )
                      else
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: sheetPhotos.map((photo) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: VehiclePhotoService.buildPhotoCard(
                                  photo: photo,
                                  baseUrl: _baseUrl,
                                  width: 110,
                                  height: 105,
                                  onTap: () {
                                    VehiclePhotoService.showFullPhotoDialog(
                                      context: context,
                                      baseUrl: _baseUrl,
                                      photo: photo,
                                      onDelete: () {
                                        setSheet(() {
                                          sheetPhotos.removeWhere((p) => p['id'] == photo['id'] || p['key'] == photo['key']);
                                          walk['securityPhotos'] = sheetPhotos;
                                        });
                                        http.delete(
                                          Uri.parse('$_baseUrl/vehicles/photos'),
                                          headers: {'Content-Type': 'application/json', ...AuthService.instance.authHeaders},
                                          body: json.encode({
                                            'key': photo['key'],
                                            'photoId': photo['id'],
                                            'jobCardId': job['id']?.toString(),
                                          }),
                                        );
                                      },
                                    );
                                  },
                                  onDelete: () {
                                    setSheet(() {
                                      sheetPhotos.removeWhere((p) => p['id'] == photo['id'] || p['key'] == photo['key']);
                                      walk['securityPhotos'] = sheetPhotos;
                                    });
                                    http.delete(
                                      Uri.parse('$_baseUrl/vehicles/photos'),
                                      headers: {'Content-Type': 'application/json', ...AuthService.instance.authHeaders},
                                      body: json.encode({
                                        'key': photo['key'],
                                        'photoId': photo['id'],
                                        'jobCardId': job['id']?.toString(),
                                      }),
                                    );
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                    ],
                  ),
                ),

                // -------------------------------------------------------------
                // TECHNICIAN DEFECT FINDINGS & RECOMMENDATIONS CARD
                // -------------------------------------------------------------
                Builder(builder: (_) {
                  final walkData = job['walkAroundData'] is Map ? (job['walkAroundData'] as Map) : {};
                  final recs = (walkData['recommendations'] is List)
                      ? (walkData['recommendations'] as List).whereType<Map>().map((r) => Map<String, dynamic>.from(r)).toList()
                      : <Map<String, dynamic>>[];

                  return Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: recs.isNotEmpty ? const Color(0xFFFFFBEB) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: recs.isNotEmpty ? const Color(0xFFFDE68A) : Colors.blueGrey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.lightbulb, color: recs.isNotEmpty ? const Color(0xFFB45309) : const Color(0xFF0F4C81), size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  'Technician Findings & Recommendations (${recs.length})',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: recs.isNotEmpty ? const Color(0xFF78350F) : const Color(0xFF0F4C81),
                                  ),
                                ),
                              ],
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0F4C81),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              icon: const Icon(Icons.add_circle_outline, size: 14),
                              label: const Text('Add Finding', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              onPressed: () => _showAddRecommendationSheet(job, setSheet),
                            ),
                          ],
                        ),
                        if (recs.isEmpty) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'No additional defects reported yet. Tap "+ Add Finding" if you discover issues while servicing this vehicle.',
                            style: TextStyle(fontSize: 11.5, color: Colors.black54),
                          ),
                        ] else ...[
                          const SizedBox(height: 10),
                          ...recs.map((rec) {
                            final sys = (rec['system'] ?? 'General').toString();
                            final issue = (rec['issue'] ?? '').toString();
                            final fix = (rec['recommendation'] ?? '').toString();
                            final urgency = (rec['urgency'] ?? 'RECOMMENDED').toString();
                            final tech = (rec['technicianName'] ?? 'Tech').toString();
                            final partsPrice = (rec['estimatedParts'] as num?)?.toDouble() ?? 0.0;
                            final labourPrice = (rec['estimatedLabour'] as num?)?.toDouble() ?? 0.0;
                            final total = partsPrice + labourPrice;

                            final isCritical = urgency == 'CRITICAL';
                            final badgeColor = isCritical ? Colors.red : (urgency == 'ADVISORY' ? Colors.blue : Colors.orange.shade800);

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.amber.shade300),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: badgeColor.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
                                        ),
                                        child: Text(
                                          '$sys \u2022 $urgency',
                                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: badgeColor),
                                        ),
                                      ),
                                      const Spacer(),
                                      Text('By $tech', style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text('Issue: $issue', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF1E293B))),
                                  Text('Recommended Fix: $fix', style: const TextStyle(fontSize: 12, color: Color(0xFF334155))),
                                  if (rec['partsNeeded'] != null && rec['partsNeeded'].toString().isNotEmpty)
                                    Text('Parts: ${rec['partsNeeded']}', style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade700)),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Labour: KES ${labourPrice.toStringAsFixed(0)} | Parts: KES ${partsPrice.toStringAsFixed(0)} (Total: KES ${total.toStringAsFixed(0)})',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: [
                                      OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          foregroundColor: Colors.green.shade800,
                                          side: BorderSide(color: Colors.green.shade600),
                                        ),
                                        icon: const Icon(Icons.chat_outlined, size: 13, color: Colors.green),
                                        label: const Text('WhatsApp Recommendation', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                                        onPressed: () {
                                          final custPhone = job['customer']?['phone']?.toString() ?? '';
                                          final custName = job['customer']?['name']?.toString() ?? 'Customer';
                                          final regNo = job['vehicle']?['registrationNo']?.toString() ?? 'vehicle';
                                          final makeModel = '${job['vehicle']?['make'] ?? ''} ${job['vehicle']?['model'] ?? ''}'.trim();
                                          final msg = 'Hello $custName, during inspection of your $makeModel ($regNo) at ${_workshopSettings['name'] ?? 'our workshop'}, our technician $tech identified an additional issue:\n\n• $sys Issue: $issue\n• Recommended Repair: $fix\n• Estimated Cost: KES ${total.toStringAsFixed(0)} (Labour: KES ${labourPrice.toStringAsFixed(0)}, Parts: KES ${partsPrice.toStringAsFixed(0)})\n\nWould you like us to add this to your estimate and proceed with repair?';
                                          _launchWhatsAppMessage(custPhone, msg);
                                        },
                                      ),
                                      OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          foregroundColor: const Color(0xFF2563EB),
                                          side: const BorderSide(color: Color(0xFF2563EB)),
                                        ),
                                        icon: const Icon(Icons.request_quote_outlined, size: 13),
                                        label: const Text('Open Quote Form', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
                                        onPressed: () {
                                          Navigator.pop(ctx);
                                          _openCreateEstimateModal(initialJobCardId: job['id']);
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 14),
                // -------------------------------------------------------------
                // PARTS & TOOL REQUISITIONS FOR THIS VEHICLE
                // -------------------------------------------------------------
                Builder(builder: (_) {
                  final reg = job['vehicle']?['registrationNo']?.toString();
                  final jId = job['id']?.toString();
                  final vReqs = _itemRequests.where((r) {
                    final reqJobId = r['jobCardId']?.toString();
                    final reqPlate = r['vehiclePlate']?.toString();
                    return (jId != null && reqJobId == jId) ||
                           (reg != null && reqPlate != null && reg.toUpperCase() == reqPlate.toUpperCase());
                  }).toList();

                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blueGrey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.inventory_2_outlined, color: Color(0xFF0F4C81), size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  'Parts & Supplies (${vReqs.length})',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F4C81)),
                                ),
                              ],
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0F4C81),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              icon: const Icon(Icons.add, size: 14),
                              label: const Text('Request Item', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              onPressed: () {
                                _showItemRequestDialog(
                                  preselectedJobId: job['id'].toString(),
                                  preselectedVehiclePlate: job['vehicle']?['registrationNo']?.toString(),
                                );
                              },
                            ),
                          ],
                        ),
                        if (vReqs.isEmpty) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'No parts requested for this vehicle yet. Tap "+ Request Item" to request from Storekeeper.',
                            style: TextStyle(fontSize: 11.5, color: Colors.black54),
                          ),
                        ] else ...[
                          const SizedBox(height: 10),
                          ...vReqs.map((vr) {
                            final status = (vr['status'] ?? 'PENDING').toString();
                            final ref = vr['reference'] ?? 'REQ';
                            final lines = (vr['lines'] as List<dynamic>?) ?? [];
                            final hasIssued = lines.any((l) => (l['qtyIssued'] ?? 0) > 0);
                            final ack = vr['acknowledgedAt'] != null;

                            Color sc = Colors.amber.shade800;
                            if (status == 'ORDERED') sc = Colors.indigo;
                            if (status == 'APPROVED') sc = Colors.green;
                            if (status == 'ISSUED') sc = Colors.blue;
                            if (status == 'REJECTED') sc = Colors.red;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(ref, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                                      const Spacer(),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(color: sc.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                                        child: Text(status.replaceAll('_', ' '), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: sc)),
                                      ),
                                    ],
                                  ),
                                  if (status == 'ORDERED') ...[
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(6)),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.local_shipping, size: 14, color: Colors.indigo),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              'Ordered: PO #${vr['poNumber'] ?? '-'} • ETA: ${vr['estimatedArrival'] ?? 'TBA'}',
                                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 4),
                                  ...lines.map((l) => Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 2),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '• ${l['description'] ?? 'Item'} (x${l['qtyRequested']})',
                                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                        Text(
                                          'Issued: ${l['qtyIssued'] ?? 0}',
                                          style: TextStyle(fontSize: 11, color: (l['qtyIssued'] ?? 0) > 0 ? Colors.green.shade800 : Colors.black54),
                                        ),
                                      ],
                                    ),
                                  )),
                                  if (hasIssued && !ack) ...[
                                    const SizedBox(height: 6),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 6),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        icon: const Icon(Icons.check_circle_outline, size: 14),
                                        label: const Text('Confirm Physical Receipt', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                        onPressed: () async {
                                          await _acknowledgeReceipt(vr['id'].toString());
                                          setSheet(() {});
                                        },
                                      ),
                                    ),
                                  ],
                                  if (ack) ...[
                                    const SizedBox(height: 4),
                                    Text('✓ Receipt confirmed by ${vr['acknowledgedBy'] ?? 'Tech'}', style: TextStyle(fontSize: 10.5, color: Colors.green.shade800, fontWeight: FontWeight.bold)),
                                  ],
                                ],
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 18),
                if (!techMode) ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.print_outlined, size: 15),
                          label: const Text('Customer Copy', style: TextStyle(fontSize: 12)),
                          onPressed: () => InvoicePdfService.showJobCardPreviewModal(
                            context: context,
                            workshopSettings: _workshopSettings,
                            job: job,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.request_quote_outlined, size: 15, color: Color(0xFF2563EB)),
                          label: const Text('Estimate', style: TextStyle(fontSize: 12, color: Color(0xFF2563EB), fontWeight: FontWeight.bold)),
                          onPressed: () {
                            Navigator.pop(context);
                            _openCreateEstimateModal(initialJobCardId: job['id']);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F4C81),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: saving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save),
                    label: const Text('Save Job Sheet Updates', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: saving
                        ? null
                        : () async {
                                setSheet(() => saving = true);
                                final body = <String, dynamic>{'status': status};
                                walk['diagnostics'] = sheetDiag;
                                walk['obdCodes'] = obdCtrl.text.trim();
                                if (techMode) {
                                  walk['techInspection'] = {
                                    'results': results,
                                    'obdCodes': obdCtrl.text.trim(),
                                    'notes': notesCtrl.text.trim(),
                                    'by': _techName,
                                    'updatedAt': DateTime.now().toIso8601String(),
                                  };
                                  final h = double.tryParse(hoursCtrl.text.trim());
                                  if (h != null) body['actualHours'] = h;
                                } else {
                                  body['technician'] = assigned;
                                }
                                walk['securityPhotos'] = sheetPhotos;
                                body['walkAroundData'] = walk;
                                final ok = await _putJob(job['id'].toString(), body);
                                if (ctx.mounted) Navigator.pop(ctx);
                                _toast(ok ? 'Job updated' : 'Failed to update job', color: ok ? Colors.green : Colors.red);
                                _fetchJobs();
                              },
                      ),
                    ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIntakeForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tap on the vehicle diagram to mark Dents (D), Scratches (S), or Cuts (C):',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          VehicleDamageMap(
            initialMarkers: _damageMarkers,
            initialBodyType: _selectedBodyType,
            onMarkersChanged: (markers) => _damageMarkers = markers,
            onBodyTypeChanged: (bt) => setState(() => _selectedBodyType = bt),
          ),
          const SizedBox(height: 20),
          // Registration Plate & Fast Auto-Lookup
          TextField(
            controller: _regController,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Registration No * (e.g. KDA 123A or GK A123B)',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.directions_car, color: Color(0xFF1E3A8A)),
              suffixIcon: _isLookingUpVehicle
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : null,
            ),
            onChanged: _onMobilePlateChanged,
          ),

          // Found in Workshop Registry Card
          if (_foundVehicleData != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF86EFAC)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${_foundVehicleData!['vehicle']?['registrationNo']} (${_foundVehicleData!['vehicle']?['make']} ${_foundVehicleData!['vehicle']?['model']})',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF14532D)),
                        ),
                      ),
                      _buildMobileCategoryBadge(_foundVehicleData!['vehicle']?['category'] ?? 'PERSONAL'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Owner: ${_foundVehicleData!['customer']?['name']} \u2022 Visits: ${_foundVehicleData!['totalJobsCount']} \u2022 Last Odo: ${_foundVehicleData!['vehicle']?['lastOdometer'] ?? '-'} km',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF15803D)),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          if (_foundVehicleData!['vehicle']?['id'] != null) {
                            _showMobileVehiclePassport(_foundVehicleData!['vehicle']['id'].toString());
                          }
                        },
                        icon: const Icon(Icons.history_edu, size: 15, color: Color(0xFF15803D)),
                        label: const Text('View Service Passport', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF15803D))),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),

          // Fleet & Client Category Selector
          DropdownButtonFormField<String>(
            isExpanded: true,
            value: _selectedCategory,
            decoration: const InputDecoration(labelText: 'Fleet / Client Category *', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'PERSONAL', child: Text('🚗 Personal Car (Private Owner)')),
              DropdownMenuItem(value: 'GOVERNMENT', child: Text('🏛️ Government Fleet (GK/CG/Police)')),
              DropdownMenuItem(value: 'SCHOOL', child: Text('🏫 School Fleet (Buses/Vans)')),
              DropdownMenuItem(value: 'ORGANIZATION', child: Text('🏢 Organization / NGO / Corporate')),
            ],
            onChanged: (val) => setState(() => _selectedCategory = val ?? 'PERSONAL'),
          ),
          const SizedBox(height: 12),

          // Fleet Unit & Driver Row
          Row(
            children: [
              Expanded(
                flex: 1,
                child: TextField(
                  controller: _fleetUnitController,
                  decoration: const InputDecoration(labelText: 'Unit # (BUS-04)', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _driverController,
                  decoration: const InputDecoration(labelText: 'Assigned Driver Name', border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _driverPhoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Driver Contact Phone', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),

          // Customer / Institutional Owner
          TextField(
            controller: _customerController,
            decoration: InputDecoration(
              labelText: 'Customer / Institution Name *',
              border: const OutlineInputBorder(),
              suffixIcon: _isLookingUpCustomer
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : null,
            ),
            onChanged: _onMobileCustomerInputChanged,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Customer / Owner Phone Number *',
              hintText: 'e.g. +254 712 345 678',
              prefixIcon: Icon(Icons.phone_outlined),
              border: OutlineInputBorder(),
            ),
            onChanged: _onMobileCustomerInputChanged,
          ),

          // Returning Owner Vehicles Selector
          if (_matchedCustomerVehicles.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF86EFAC)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.people_alt, color: Color(0xFF16A34A), size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${_matchedCustomerData?['name'] ?? 'Owner'} has ${_matchedCustomerVehicles.length} registered vehicle${_matchedCustomerVehicles.length > 1 ? 's' : ''}:',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF14532D)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ..._matchedCustomerVehicles.map((cv) {
                          final isSelected = _regController.text.trim().toUpperCase() == (cv['registrationNo'] ?? '').toString().toUpperCase();
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _regController.text = cv['registrationNo'] ?? '';
                                  _makeController.text = cv['make'] ?? '';
                                  _modelController.text = cv['model'] ?? '';
                                  if (cv['fuelType'] != null) _fuelType = cv['fuelType'].toString();
                                  if (cv['category'] != null) _selectedCategory = cv['category'].toString();
                                  if (cv['vinNumber'] != null) _memoDetails.vinNumber = cv['vinNumber'].toString();
                                  _selectedCustomerId = _matchedCustomerData?['id']?.toString();
                                  _foundVehicleData = {
                                    'vehicle': cv,
                                    'customer': _matchedCustomerData,
                                    'totalJobsCount': cv['jobCardsCount'] ?? 0,
                                  };
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isSelected ? const Color(0xFF16A34A) : Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: isSelected ? const Color(0xFF15803D) : const Color(0xFF86EFAC)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.directions_car, size: 14, color: isSelected ? Colors.white : const Color(0xFF16A34A)),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${cv['registrationNo']} (${cv['make']} ${cv['model']})',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: isSelected ? Colors.white : const Color(0xFF16A34A),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                        ActionChip(
                          avatar: const Icon(Icons.add, size: 14, color: Color(0xFF1D4ED8)),
                          label: const Text('Add Another Car', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF1D4ED8))),
                          backgroundColor: const Color(0xFFEFF6FF),
                          side: const BorderSide(color: Color(0xFF93C5FD)),
                          onPressed: () {
                            setState(() {
                              _regController.clear();
                              _makeController.clear();
                              _modelController.clear();
                              _memoDetails.vinNumber = '';
                              _foundVehicleData = null;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _makeController,
                  decoration: const InputDecoration(labelText: 'Make (e.g. Toyota)', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _modelController,
                  decoration: const InputDecoration(labelText: 'Model (e.g. Hilux)', border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _odometerController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Odometer (km)',
              border: const OutlineInputBorder(),
              hintText: _foundVehicleData != null && _foundVehicleData!['vehicle']?['lastOdometer'] != null
                  ? 'Previous: ${_foundVehicleData!['vehicle']['lastOdometer']} km'
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: ['Petrol', 'Diesel', 'Hybrid', 'Electric'].contains(_fuelType) ? _fuelType : 'Petrol',
                  decoration: const InputDecoration(
                    labelText: 'Fuel Type *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.local_gas_station, size: 18, color: Color(0xFF1E3A8A)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Petrol', child: Text('⛽ Petrol', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'Diesel', child: Text('🛢️ Diesel', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'Hybrid', child: Text('⚡ Hybrid', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'Electric', child: Text('🔌 Electric', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (val) => setState(() => _fuelType = val ?? 'Petrol'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: _fuelLevel,
                  decoration: const InputDecoration(labelText: 'Fuel Level', border: OutlineInputBorder()),
                  items: ['Empty', '1/4', 'Half', '3/4', 'Full']
                      .map((f) => DropdownMenuItem(value: f, child: Text(f, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (val) => setState(() => _fuelLevel = val ?? 'Half'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: _priority,
                  decoration: const InputDecoration(labelText: 'Priority', border: OutlineInputBorder()),
                  items: ['Low', 'Medium', 'High']
                      .map((p) => DropdownMenuItem(value: p, child: Text(p, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (val) => setState(() => _priority = val ?? 'Medium'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: _bayNumber,
                  decoration: const InputDecoration(labelText: 'Workshop Bay / Lift', border: OutlineInputBorder()),
                  items: ['Bay 1', 'Bay 2', 'Bay 3', 'Lift A', 'Lift B', 'Diagnostic Bay']
                      .map((b) => DropdownMenuItem(value: b, child: Text(b, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (val) => setState(() => _bayNumber = val ?? 'Bay 1'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _serviceController,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Work Requested / Customer Notes', border: OutlineInputBorder()),
          ),
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
                  children: _diagnostics.keys.map((sys) {
                    final currentVal = _diagnostics[sys] ?? 'Pass';
                    final chipColor = currentVal == 'Pass'
                        ? Colors.green
                        : currentVal == 'Attention'
                            ? Colors.orange
                            : Colors.red;
                    return InkWell(
                      onTap: () {
                        setState(() {
                          _diagnostics[sys] = currentVal == 'Pass'
                              ? 'Attention'
                              : currentVal == 'Attention'
                                  ? 'Fail'
                                  : 'Pass';
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: chipColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: chipColor.withValues(alpha: 0.5)),
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
                  controller: _obdController,
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
          WalkAroundChecklistWidget(
            details: _memoDetails,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              icon: Icon(_signatureCaptured ? Icons.check_circle : Icons.draw, color: _signatureCaptured ? Colors.green : null),
              label: Text(_signatureCaptured ? 'Customer Signature Captured' : 'Capture Customer Signature'),
              onPressed: _openSignatureModal,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F4C81),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.cloud_upload),
              label: _isSubmitting
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Submit Job Card to Workshop', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              onPressed: _isSubmitting ? null : _submitIntakeJobCard,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleView() {
    if (_isLoadingJobs) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _showMobileAppointmentDialog,
              icon: const Icon(Icons.calendar_month),
              label: const Text('+ Book Customer Appointment & Bay'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F4C81),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
        Expanded(
          child: _appointments.isEmpty
              ? const Center(
                  child: Text('No appointments scheduled yet.', style: TextStyle(color: Colors.grey)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _appointments.length,
                  itemBuilder: (context, index) {
                    final appt = _appointments[index];
                    final status = appt['status'] ?? 'SCHEDULED';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFF0F4C81),
                          child: Icon(Icons.event_available, color: Colors.white, size: 18),
                        ),
                        title: Text(
                          '${appt['registrationNo'] ?? 'Vehicle'} \u2022 ${appt['customerName'] ?? ''}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          'Service: ${appt['serviceType'] ?? '-'}\nBay: ${appt['bayNumber'] ?? 'Bay 1'} \u2022 Status: $status',
                        ),
                        isThreeLine: true,
                        trailing: TextButton(
                          onPressed: () {
                            setState(() {
                              _customerController.text = appt['customerName']?.toString() ?? '';
                              _phoneController.text = appt['customerPhone']?.toString() ?? '';
                              _regController.text = appt['registrationNo']?.toString() ?? '';
                              _serviceController.text = appt['serviceType']?.toString() ?? '';
                              _selectedIndex = 2;
                            });
                          },
                          child: const Text('Start Intake'),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showMobileAppointmentDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final regCtrl = TextEditingController();
    final serviceCtrl = TextEditingController(text: 'Periodic Maintenance Service');
    String bay = 'Bay 1';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Book Workshop Appointment'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Customer Name *')),
              const SizedBox(height: 8),
              TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Customer Phone')),
              const SizedBox(height: 8),
              TextField(controller: regCtrl, decoration: const InputDecoration(labelText: 'Vehicle Reg No *')),
              const SizedBox(height: 8),
              TextField(controller: serviceCtrl, decoration: const InputDecoration(labelText: 'Service Type')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                isExpanded: true,
                value: bay,
                decoration: const InputDecoration(labelText: 'Assign Bay / Lift'),
                items: ['Bay 1', 'Bay 2', 'Bay 3', 'Lift A', 'Lift B', 'Diagnostic Bay']
                    .map((b) => DropdownMenuItem(value: b, child: Text(b, overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (v) => bay = v ?? 'Bay 1',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty || regCtrl.text.trim().isEmpty) return;
              await http.post(
                Uri.parse('$_baseUrl/appointments'),
                headers: {'Content-Type': 'application/json'},
                body: json.encode({
                  'customerName': nameCtrl.text.trim(),
                  'customerPhone': phoneCtrl.text.trim(),
                  'registrationNo': regCtrl.text.trim().toUpperCase(),
                  'serviceType': serviceCtrl.text.trim(),
                  'bayNumber': bay,
                  'scheduledAt': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
                }),
              );
              if (mounted) Navigator.pop(ctx);
              _fetchJobs();
            },
            child: const Text('Book'),
          ),
        ],
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final List<Offset?> points;
  _SignaturePainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black87
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.5;

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ==========================================
// MOBILE DIGITAL VEHICLE PASSPORT BOTTOM SHEET
// ==========================================
class _MobileVehiclePassportSheet extends StatefulWidget {
  final String vehicleId;
  final String baseUrl;

  const _MobileVehiclePassportSheet({
    Key? key,
    required this.vehicleId,
    required this.baseUrl,
  }) : super(key: key);

  @override
  State<_MobileVehiclePassportSheet> createState() => _MobileVehiclePassportSheetState();
}

class _MobileVehiclePassportSheetState extends State<_MobileVehiclePassportSheet> {
  bool _isLoading = true;
  Map<String, dynamic>? _historyData;
  String? _error;
  int _activeTab = 0; // 0: Timeline, 1: Parts, 2: Diagnostics

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    try {
      final res = await http.get(
        Uri.parse('${widget.baseUrl}/vehicles/${widget.vehicleId}/history'),
        headers: {'Content-Type': 'application/json'},
      );
      if (res.statusCode == 200 && mounted) {
        setState(() {
          _historyData = json.decode(res.body);
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load vehicle history (${res.statusCode})';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error loading history: $e';
          _isLoading = false;
        });
      }
    }
  }

  String _formatDateShort(dynamic isoString) {
    if (isoString == null) return '-';
    try {
      final dt = DateTime.parse(isoString.toString()).toLocal();
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return isoString.toString();
    }
  }

  String _formatKes(dynamic amount) {
    if (amount == null) return 'KSH 0';
    final num val = amount is num ? amount : (num.tryParse(amount.toString()) ?? 0);
    return 'KSH ${val.toStringAsFixed(0)}';
  }

  void _shareViaWhatsApp() {
    final v = _historyData?['vehicle'] ?? {};
    final c = _historyData?['customer'] ?? {};
    final s = _historyData?['summary'] ?? {};
    final targetPhone = (v['driverPhone'] ?? c['phone'] ?? '').toString();

    final msg = '''*DIGITAL VEHICLE SERVICE PASSPORT*
Registration: ${v['registrationNo'] ?? '-'}
Vehicle: ${v['make'] ?? ''} ${v['model'] ?? ''} (${(v['bodyType'] ?? 'sedan').toString().toUpperCase()})
Category: ${v['category'] ?? 'PERSONAL'}
Owner: ${c['name'] ?? '-'}
${v['assignedDriver'] != null && v['assignedDriver'].toString().isNotEmpty ? 'Assigned Driver: ${v['assignedDriver']}\n' : ''}Odometer: ${s['currentOdometer'] ?? v['lastOdometer'] ?? '-'} km
Total Visits: ${s['totalVisits'] ?? 0}
Lifetime Spend: ${_formatKes(s['totalSpend'] ?? 0)}
Last Service: ${_formatDateShort(s['lastServiceDate'] ?? v['lastServiceDate'])}
Next Service Due: ${s['nextServiceMileage'] != null ? '${s['nextServiceMileage']} km' : 'TBA'}''';

    final clean = targetPhone.replaceAll(RegExp(r'[^0-9]'), '');
    final phone = clean.startsWith('0') && clean.length == 10 ? '254${clean.substring(1)}' : (clean.isEmpty ? '254700000000' : clean);
    PlatformLauncher.openUrl('https://wa.me/$phone?text=${Uri.encodeComponent(msg)}');
  }

  @override
  Widget build(BuildContext context) {
    final v = _historyData?['vehicle'] ?? {};
    final c = _historyData?['customer'] ?? {};
    final s = _historyData?['summary'] ?? {};
    final jobs = (_historyData?['jobCards'] as List<dynamic>?) ?? [];
    final parts = (_historyData?['partsReplaced'] as List<dynamic>?) ?? [];
    final diagnostics = (_historyData?['diagnosticHistory'] as List<dynamic>?) ?? [];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      builder: (_, scroll) => Column(
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 10),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF0F172A), width: 1.5),
                      ),
                      child: Text(
                        (v['registrationNo'] ?? 'PASSPORT').toString().toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF0F172A)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('${v['make'] ?? ''} ${v['model'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('Owner: ${c['name'] ?? '-'}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                if ((v['assignedDriver'] ?? '').toString().isNotEmpty) ...[
                  const Text(' \u2022 '),
                  Text('Driver: ${v['assignedDriver']}', style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700, fontWeight: FontWeight.bold)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Body
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                    : ListView(
                        controller: scroll,
                        padding: const EdgeInsets.all(14),
                        children: [
                          // KPI Strip
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _statBadge('Visits', '${s['totalVisits'] ?? jobs.length}', const Color(0xFF2563EB)),
                                _statBadge('Total Spend', _formatKes(s['totalSpend'] ?? 0), const Color(0xFF16A34A)),
                                _statBadge('Odometer', '${s['currentOdometer'] ?? v['lastOdometer'] ?? 0} km', const Color(0xFFD97706)),
                                _statBadge('Parts Fitted', '${parts.length}', const Color(0xFF7C3AED)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Tab Buttons
                          Row(
                            children: [
                              _tabPill('📋 Job Cards (${jobs.length})', 0),
                              const SizedBox(width: 6),
                              _tabPill('⚙️ Parts (${parts.length})', 1),
                              const SizedBox(width: 6),
                              _tabPill('🔍 OBD (${diagnostics.length})', 2),
                            ],
                          ),
                          const Divider(height: 20),

                          if (_activeTab == 0) ...[
                            if (jobs.isEmpty)
                              const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No job cards recorded yet.')))
                            else
                              ...jobs.map((j) => Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: ListTile(
                                      title: Text('${j['jobNumber'] ?? 'JC-'} \u2022 ${j['workRequested'] ?? 'Service'}',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Tech: ${j['technician'] ?? '-'} \u2022 Odometer: ${j['odometer'] ?? '-'} km'),
                                          Text('Date: ${_formatDateShort(j['createdAt'])} \u2022 Status: ${j['status'] ?? '-'}',
                                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                        ],
                                      ),
                                    ),
                                  )),
                          ] else if (_activeTab == 1) ...[
                            if (parts.isEmpty)
                              const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No parts replaced on this vehicle yet.')))
                            else
                              ...parts.map((p) => Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: ListTile(
                                      leading: const Icon(Icons.settings, color: Color(0xFF2563EB)),
                                      title: Text(p['partName'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                      subtitle: Text('Installed on ${_formatDateShort(p['date'])} \u2022 Job: ${p['jobNumber'] ?? '-'}'),
                                      trailing: Text(_formatKes(p['price'] ?? 0), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF16A34A))),
                                    ),
                                  )),
                          ] else ...[
                            if (diagnostics.isEmpty)
                              const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No diagnostic or OBD fault codes recorded.')))
                            else
                              ...diagnostics.map((d) {
                                final defects = (d['defects'] as List<dynamic>?) ?? [];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Job: ${d['jobNumber'] ?? '-'} \u2022 ${_formatDateShort(d['date'])}',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E3A8A))),
                                        if ((d['obdCodes'] ?? '').toString().isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(4)),
                                            child: Text('OBD Codes: ${d['obdCodes']}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
                                          ),
                                        ],
                                        if (defects.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text('Issues: ${defects.join(', ')}', style: const TextStyle(fontSize: 11, color: Colors.redAccent)),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              }),
                          ],

                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: _shareViaWhatsApp,
                            icon: const Icon(Icons.chat, color: Color(0xFF16A34A)),
                            label: const Text('Share Digital Passport via WhatsApp', style: TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _statBadge(String label, String val, Color color) {
    return Column(
      children: [
        Text(val, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _tabPill(String title, int idx) {
    final isSel = _activeTab == idx;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _activeTab = idx),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSel ? const Color(0xFF1E3A8A) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            title,
            style: TextStyle(fontSize: 11, fontWeight: isSel ? FontWeight.bold : FontWeight.w500, color: isSel ? Colors.white : Colors.black87),
          ),
        ),
      ),
    );
  }
}

