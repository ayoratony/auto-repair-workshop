import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'estimate_form.dart';
import 'invoice_pdf_service.dart';
import 'pdf_saver_stub.dart' if (dart.library.html) 'pdf_saver_web.dart';
import '../mobile/vehicle_damage_map.dart';
import '../mobile/walk_around_checklist.dart';
import 'inventory_workspace_view.dart';
import '../../services/auth_service.dart';
import '../../services/sync_service.dart';

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
  String _activeUserRole = 'OWNER';

  // Role-Based Access Control: what each role may open (nav:*) or do (other keys).
  static const Map<String, Set<String>> _rolePerms = {
    'OWNER': {
      'nav:Dashboard', 'nav:Job Cards', 'nav:Appointments', 'nav:Parts Catalog', 'nav:Estimates',
      'nav:Invoices', 'nav:Customers', 'nav:Vehicles & Fleets', 'nav:Employees', 'nav:Reports', 'nav:Settings', 'nav:Inventory',
      'job:create', 'job:edit', 'job:delete', 'part:edit', 'part:delete', 'stock:adjust',
      'estimate:edit', 'estimate:delete', 'payment:record', 'expense:record', 'appt:edit',
      'user:manage',
    },
    'SUPER_ADMIN': {
      'nav:Dashboard', 'nav:Job Cards', 'nav:Appointments', 'nav:Parts Catalog', 'nav:Estimates',
      'nav:Invoices', 'nav:Customers', 'nav:Vehicles & Fleets', 'nav:Employees', 'nav:Reports', 'nav:Settings', 'nav:Inventory',
      'job:create', 'job:edit', 'job:delete', 'part:edit', 'part:delete', 'stock:adjust',
      'estimate:edit', 'estimate:delete', 'payment:record', 'expense:record', 'appt:edit',
      'user:manage',
    },
    'ADMIN': {
      'nav:Dashboard', 'nav:Job Cards', 'nav:Appointments', 'nav:Parts Catalog', 'nav:Estimates',
      'nav:Invoices', 'nav:Customers', 'nav:Vehicles & Fleets', 'nav:Employees', 'nav:Reports', 'nav:Settings', 'nav:Inventory',
      'job:create', 'job:edit', 'job:delete', 'part:edit', 'part:delete', 'stock:adjust',
      'estimate:edit', 'estimate:delete', 'payment:record', 'expense:record', 'appt:edit',
      'user:manage',
    },
    'MANAGER': {
      'nav:Dashboard', 'nav:Job Cards', 'nav:Appointments', 'nav:Parts Catalog', 'nav:Estimates',
      'nav:Invoices', 'nav:Customers', 'nav:Vehicles & Fleets', 'nav:Employees', 'nav:Reports', 'nav:Inventory',
      'job:create', 'job:edit', 'job:delete', 'part:edit', 'part:delete', 'stock:adjust',
      'estimate:edit', 'estimate:delete', 'payment:record', 'expense:record', 'appt:edit',
    },
    'ADVISOR': {
      'nav:Dashboard', 'nav:Job Cards', 'nav:Appointments', 'nav:Estimates', 'nav:Invoices', 'nav:Customers', 'nav:Vehicles & Fleets',
      'job:create', 'job:edit', 'estimate:edit', 'appt:edit',
    },
    'MECHANIC': {
      'nav:Dashboard', 'nav:Job Cards', 'nav:Parts Catalog', 'nav:Vehicles & Fleets',
      'job:edit',
    },
    'STOREKEEPER': {
      'nav:Dashboard', 'nav:Parts Catalog', 'nav:Inventory', 'nav:Reports',
      'part:edit', 'stock:adjust',
    },
    'INVENTORY_MANAGER': {
      'nav:Dashboard', 'nav:Parts Catalog', 'nav:Inventory', 'nav:Reports',
      'part:edit', 'stock:adjust',
    },
    'ACCOUNTS': {
      'nav:Dashboard', 'nav:Job Cards', 'nav:Estimates', 'nav:Invoices', 'nav:Customers', 'nav:Vehicles & Fleets', 'nav:Reports', 'nav:Inventory',
      'payment:record', 'expense:record',
    },
    'CASHIER': {
      'nav:Dashboard', 'nav:Job Cards', 'nav:Estimates', 'nav:Invoices', 'nav:Customers', 'nav:Vehicles & Fleets', 'nav:Reports',
      'payment:record', 'expense:record',
    },
  };

  static const Map<String, String> _tabToNav = {
    'Current Job Cards': 'Job Cards',
    'Parts Catalog': 'Parts Catalog',
    'Estimates': 'Estimates',
    'Invoices': 'Invoices',
  };

  bool _can(String perm) {
    if (_activeUserRole == 'OWNER' || _activeUserRole == 'SUPER_ADMIN') return true;
    return _rolePerms[_activeUserRole]?.contains(perm) ?? false;
  }

  /// Returns true (and warns) when the active role is NOT allowed to do [perm].
  bool _deny(String perm, String action) {
    if (_can(perm)) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.orange,
        content: Text('Role Guard: $_activeUserRole is not allowed to $action.'),
      ),
    );
    return true;
  }

  String _firstAllowedTab() {
    for (final t in _tabToNav.keys) {
      if (_can('nav:${_tabToNav[t]}')) return t;
    }
    return 'Current Job Cards';
  }

  void _confirmSignOut() {
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

  void _changeRole(String role) {
    setState(() {
      _activeUserRole = role;
      _activeSidebar = 'Dashboard';
      _activeTab = _firstAllowedTab();
    });
    _refreshAllData();
  }

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
  List<dynamic> _vehicles = [];
  Map<String, dynamic> _vehicleCounts = {'all': 0, 'personal': 0, 'government': 0, 'school': 0, 'organization': 0};
  String _vehicleCategoryFilter = 'ALL';
  String _vehicleSearchQuery = '';
  List<dynamic> _employees = [];
  List<dynamic> _appointments = [];
  List<dynamic> _expenses = [];
  Map<String, dynamic> _workshopSettings = {};

  // Storekeeper / Inventory Manager Operations Reports Data
  Map<String, dynamic> _inventorySummary = {};
  List<dynamic> _inventoryReturns = [];
  List<dynamic> _inventoryTransactions = [];
  String _storeReportTab = 'Inventories'; // 'Inventories', 'Issued Items', 'Spoiled Items', 'Fast-Moving'
  String _inventoryCategoryFilter = 'ALL';
  String _issuedSubFilter = 'PARTS_JOB'; // 'PARTS_JOB', 'CONSUMABLES_DEPT', 'TOOLS_FIELD'
  String _inventorySearchQuery = '';

  bool _isLoading = true;
  bool _showEstimateCreator = false;
  String? _preselectedJobIdForEstimate;

  // Filters for Job Cards
  String _searchQuery = '';
  String _statusFilter = 'All';
  String _technicianFilter = 'All';
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _topSearchController = TextEditingController();
  StreamSubscription<SyncEvent>? _syncSubscription;

  @override
  void initState() {
    super.initState();
    _activeUserRole = AuthService.instance.role;
    if (_activeUserRole == 'STOREKEEPER' || _activeUserRole == 'INVENTORY_MANAGER') {
      _activeSidebar = 'Inventory';
    } else if (!_can('nav:Dashboard')) {
      _activeSidebar = _can('nav:Job Cards') ? 'Job Cards' : 'Dashboard';
    }
    _activeTab = _firstAllowedTab();
    _refreshAllData();

    // Start background auto-sync loop across all workshop terminals
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
              duration: const Duration(seconds: 6),
              behavior: SnackBarBehavior.floating,
              content: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '🔔 Alert from Technician ${evt.actorName}: $reg has $sys issue (Estimated: KES $cost)!',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ],
              ),
              action: SnackBarAction(
                label: 'REFRESH NOW',
                textColor: Colors.yellow,
                onPressed: _refreshAllData,
              ),
            ),
          );
        }
      }
    });
    SyncService.instance.addListener(_onSyncUpdate);
  }

  void _onSyncUpdate() {
    if (mounted) {
      _refreshAllDataSilently();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _topSearchController.dispose();
    _syncSubscription?.cancel();
    SyncService.instance.removeListener(_onSyncUpdate);
    super.dispose();
  }

  Future<void> _refreshAllDataSilently() async {
    try {
      final authHeaders = AuthService.instance.authHeaders;
      final responses = await Future.wait([
        http.get(Uri.parse('$_baseUrl/dashboard'), headers: authHeaders),
        http.get(Uri.parse('$_baseUrl/jobs'), headers: authHeaders),
        http.get(Uri.parse('$_baseUrl/parts'), headers: authHeaders),
        http.get(Uri.parse('$_baseUrl/estimates'), headers: authHeaders),
        http.get(Uri.parse('$_baseUrl/invoices'), headers: authHeaders),
        http.get(Uri.parse('$_baseUrl/customers'), headers: authHeaders),
        http.get(Uri.parse('$_baseUrl/users'), headers: authHeaders),
        http.get(Uri.parse('$_baseUrl/settings'), headers: authHeaders),
        http.get(Uri.parse('$_baseUrl/appointments'), headers: authHeaders),
        http.get(Uri.parse('$_baseUrl/expenses'), headers: authHeaders),
        http.get(Uri.parse('$_baseUrl/vehicles'), headers: authHeaders),
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
        if (responses[10].statusCode == 200) _vehicles = json.decode(responses[10].body);
      });
    } catch (_) {}
  }

  Future<void> _refreshAllData() async {
    setState(() => _isLoading = true);
    try {
      final authHeaders = AuthService.instance.authHeaders;
      final responses = await Future.wait([
        http.get(Uri.parse('$_baseUrl/dashboard'), headers: authHeaders),
        http.get(Uri.parse('$_baseUrl/jobs'), headers: authHeaders),
        http.get(Uri.parse('$_baseUrl/parts'), headers: authHeaders),
        http.get(Uri.parse('$_baseUrl/estimates'), headers: authHeaders),
        http.get(Uri.parse('$_baseUrl/invoices'), headers: authHeaders),
        http.get(Uri.parse('$_baseUrl/customers'), headers: authHeaders),
        http.get(Uri.parse('$_baseUrl/users'), headers: authHeaders),
        http.get(Uri.parse('$_baseUrl/settings'), headers: authHeaders),
        http.get(Uri.parse('$_baseUrl/appointments'), headers: authHeaders),
        http.get(Uri.parse('$_baseUrl/expenses'), headers: authHeaders),
        http.get(Uri.parse('$_baseUrl/vehicles'), headers: authHeaders),
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
        if (responses.length > 10 && responses[10].statusCode == 200) {
          final vData = json.decode(responses[10].body);
          if (vData is Map) {
            _vehicles = vData['vehicles'] ?? [];
            if (vData['counts'] is Map) {
              _vehicleCounts = Map<String, dynamic>.from(vData['counts']);
            }
          } else if (vData is List) {
            _vehicles = vData;
          }
        }
        _isLoading = false;
      });

      // Fetch dedicated inventory operational summary & returns
      try {
        final invHeaders = {
          'x-user-role': _activeUserRole,
          'x-user-name': 'Storekeeper',
        };
        final invResp = await Future.wait([
          http.get(Uri.parse('$_baseUrl/inventory/reports/summary'), headers: invHeaders),
          http.get(Uri.parse('$_baseUrl/inventory/returns'), headers: invHeaders),
          http.get(Uri.parse('$_baseUrl/inventory/transactions?limit=150'), headers: invHeaders),
        ]);
        if (mounted) {
          setState(() {
            if (invResp[0].statusCode == 200) _inventorySummary = json.decode(invResp[0].body);
            if (invResp[1].statusCode == 200) _inventoryReturns = json.decode(invResp[1].body);
            if (invResp[2].statusCode == 200) _inventoryTransactions = json.decode(invResp[2].body);
          });
        }
      } catch (ie) {
        debugPrint('Error fetching inventory summary: $ie');
      }
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

  List<Map<String, dynamic>> get _technicianEmployees {
    final filtered = _employees.where((e) {
      if (e is! Map) return false;
      final role = (e['role'] ?? '').toString().toUpperCase();
      const nonTechRoles = {
        'SUPER_ADMIN',
        'OWNER',
        'ADMIN',
        'MANAGER',
        'ADVISOR',
        'ACCOUNTS',
        'CASHIER',
        'STOREKEEPER',
        'INVENTORY_MANAGER',
      };
      if (role == 'MECHANIC' || role == 'INSPECTOR' || role.contains('TECH')) return true;
      final spec = (e['specialization'] ?? '').toString().trim();
      return spec.isNotEmpty && !nonTechRoles.contains(role);
    }).map((e) => Map<String, dynamic>.from(e as Map)).toList();

    if (filtered.isNotEmpty) return filtered;
    final nonAdmins = _employees.where((e) {
      if (e is! Map) return false;
      final role = (e['role'] ?? '').toString().toUpperCase();
      return role != 'SUPER_ADMIN' && role != 'ACCOUNTS' && role != 'CASHIER' && role != 'STOREKEEPER';
    }).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return nonAdmins.isNotEmpty ? nonAdmins : _employees.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  int _getTechnicianActiveJobsCount(String techName, {String? excludeJobId}) {
    if (techName.isEmpty || techName == 'Unassigned') return 0;
    final lowerTech = techName.toLowerCase().trim();
    return _jobs.where((j) {
      if (excludeJobId != null && j['id']?.toString() == excludeJobId) return false;
      final status = (j['status'] ?? '').toString().toUpperCase();
      if (status == 'COMPLETED' || status == 'CANCELLED') return false;
      final assigned = (j['technician'] ?? '').toString().toLowerCase().trim();
      return assigned == lowerTech;
    }).length;
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
    final isEdit = existingJob != null && existingJob['id'] != null;
    if (_deny(isEdit ? 'job:edit' : 'job:create', isEdit ? 'edit job cards' : 'create job cards')) return;
    final customerNameCtrl = TextEditingController(text: existingJob?['customer']?['name'] ?? '');
    final phoneCtrl = TextEditingController(text: existingJob?['customer']?['phone'] ?? '');
    final regCtrl = TextEditingController(text: existingJob?['vehicle']?['registrationNo'] ?? '');
    final makeCtrl = TextEditingController(text: existingJob?['vehicle']?['make'] ?? '');
    final modelCtrl = TextEditingController(text: existingJob?['vehicle']?['model'] ?? '');
    final fleetUnitCtrl = TextEditingController(text: existingJob?['vehicle']?['fleetUnitNumber'] ?? '');
    final assignedDriverCtrl = TextEditingController(text: existingJob?['vehicle']?['assignedDriver'] ?? '');
    final driverPhoneCtrl = TextEditingController(text: existingJob?['vehicle']?['driverPhone'] ?? '');
    String clientCategory = (existingJob?['vehicle']?['category'] ?? existingJob?['customer']?['category'] ?? 'PERSONAL').toString();
    Timer? regLookupTimer;
    bool isLookingUp = false;
    Map<String, dynamic>? lookupMatch;
    final serviceCtrl = TextEditingController(text: existingJob?['workRequested'] ?? '');
    final techCtrl = TextEditingController(text: existingJob?['technician'] ?? '');
    final odometerCtrl = TextEditingController(text: existingJob?['odometer']?.toString() ?? '');
    final nextMileageCtrl = TextEditingController(
      text: (existingJob?['nextServiceMileage'] ?? existingJob?['vehicle']?['nextServiceMileage'])?.toString() ?? '',
    );
    final estHoursCtrl = TextEditingController(text: (existingJob?['estimatedHours'] ?? 2.0).toString());
    final actualHoursCtrl = TextEditingController(text: (existingJob?['actualHours'] ?? 0.0).toString());
    final warrantyNotesCtrl = TextEditingController(text: existingJob?['warrantyNotes']?.toString() ?? '');

    String status = existingJob?['status'] ?? 'IN_PROGRESS';
    String priority = existingJob?['priority'] ?? 'Medium';
    String fuelType = (existingJob?['vehicle']?['fuelType'] ?? existingJob?['fuelType'] ?? 'Petrol').toString();
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
            void onRegPlateChanged(String text) {
              regLookupTimer?.cancel();
              final query = text.trim();
              if (query.length < 3) {
                if (lookupMatch != null) {
                  setModalState(() => lookupMatch = null);
                }
                return;
              }
              regLookupTimer = Timer(const Duration(milliseconds: 350), () async {
                setModalState(() => isLookingUp = true);
                try {
                  final res = await http.get(
                    Uri.parse('$_baseUrl/vehicles/lookup?q=${Uri.encodeComponent(query)}'),
                    headers: AuthService.instance.authHeaders,
                  );
                  if (res.statusCode == 200) {
                    final data = json.decode(res.body);
                    if (data['found'] == true) {
                      final v = data['vehicle'];
                      final c = data['customer'];
                      setModalState(() {
                        lookupMatch = data;
                        isLookingUp = false;
                        if (customerNameCtrl.text.trim().isEmpty) {
                          customerNameCtrl.text = c['name'] ?? '';
                        }
                        if (phoneCtrl.text.trim().isEmpty) {
                          phoneCtrl.text = c['phone'] ?? '';
                        }
                        if (makeCtrl.text.trim().isEmpty) {
                          makeCtrl.text = v['make'] ?? '';
                        }
                        if (modelCtrl.text.trim().isEmpty) {
                          modelCtrl.text = v['model'] ?? '';
                        }
                        if (memoDetails.vinNumber.isEmpty && (v['vinNumber'] ?? '').toString().isNotEmpty) {
                          memoDetails.vinNumber = v['vinNumber'].toString();
                        }
                        if (fleetUnitCtrl.text.trim().isEmpty && (v['fleetUnitNumber'] ?? '').toString().isNotEmpty) {
                          fleetUnitCtrl.text = v['fleetUnitNumber'].toString();
                        }
                        if (assignedDriverCtrl.text.trim().isEmpty && (v['assignedDriver'] ?? '').toString().isNotEmpty) {
                          assignedDriverCtrl.text = v['assignedDriver'].toString();
                        }
                        if (driverPhoneCtrl.text.trim().isEmpty && (v['driverPhone'] ?? '').toString().isNotEmpty) {
                          driverPhoneCtrl.text = v['driverPhone'].toString();
                        }
                        if (v['category'] != null) {
                          clientCategory = v['category'].toString();
                        }
                        if (v['fuelType'] != null && (v['fuelType'] as String).isNotEmpty) {
                          fuelType = v['fuelType'].toString();
                        }
                      });
                      return;
                    }
                  }
                } catch (_) {}
                setModalState(() {
                  lookupMatch = null;
                  isLookingUp = false;
                });
              });
            }

            final candidateTechnicians = _technicianEmployees;
            final currentTech = techCtrl.text.trim();
            final Set<String> techNameSet = {'Unassigned'};
            for (final emp in candidateTechnicians) {
              final n = emp['name']?.toString().trim() ?? '';
              if (n.isNotEmpty) techNameSet.add(n);
            }
            if (currentTech.isNotEmpty && currentTech != 'Unassigned') {
              techNameSet.add(currentTech);
            }
            final techList = techNameSet.toList()
              ..sort((a, b) {
                if (a == 'Unassigned') return -1;
                if (b == 'Unassigned') return 1;
                final countA = _getTechnicianActiveJobsCount(a, excludeJobId: existingJob?['id']?.toString());
                final countB = _getTechnicianActiveJobsCount(b, excludeJobId: existingJob?['id']?.toString());
                if (countA != countB) return countA.compareTo(countB);
                return a.compareTo(b);
              });

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
                      // Fast Plate Lookup & Category Row
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: regCtrl,
                              textCapitalization: TextCapitalization.characters,
                              decoration: InputDecoration(
                                labelText: 'Registration No. * (e.g. KDA 123A or GK A123B)',
                                border: const OutlineInputBorder(),
                                prefixIcon: const Icon(Icons.directions_car, color: Color(0xFF1E3A8A)),
                                suffixIcon: isLookingUp
                                    ? const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                      )
                                    : null,
                              ),
                              onChanged: onRegPlateChanged,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 3,
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              value: clientCategory,
                              decoration: const InputDecoration(labelText: 'Fleet / Client Category *', border: OutlineInputBorder()),
                              items: const [
                                DropdownMenuItem(value: 'PERSONAL', child: Text('🚗 Personal (Private Owner)')),
                                DropdownMenuItem(value: 'GOVERNMENT', child: Text('🏛️ Government Fleet (GK/CG)')),
                                DropdownMenuItem(value: 'SCHOOL', child: Text('🏫 School Fleet (Buses/Vans)')),
                                DropdownMenuItem(value: 'ORGANIZATION', child: Text('🏢 Corporate / NGO Fleet')),
                              ],
                              onChanged: (val) => setModalState(() => clientCategory = val ?? 'PERSONAL'),
                            ),
                          ),
                        ],
                      ),

                      // Recognition Banner if vehicle already exists in workshop registry
                      if (lookupMatch != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF86EFAC)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      spacing: 8,
                                      runSpacing: 4,
                                      children: [
                                        Text(
                                          'Registered Vehicle Match: ${lookupMatch!['vehicle']?['registrationNo']} (${lookupMatch!['vehicle']?['make']} ${lookupMatch!['vehicle']?['model']})',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF14532D)),
                                        ),
                                        _buildCategoryBadge(lookupMatch!['vehicle']?['category'] ?? 'PERSONAL'),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Owner: ${lookupMatch!['customer']?['name']} \u2022 Total Visits: ${lookupMatch!['totalJobsCount'] ?? 0} \u2022 Last Recorded: ${lookupMatch!['vehicle']?['lastOdometer'] ?? '-'} km (${_formatDateShort(lookupMatch!['vehicle']?['lastServiceDate'])})',
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF15803D)),
                                    ),
                                  ],
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () {
                                  if (lookupMatch!['vehicle']?['id'] != null) {
                                    _showVehicleHistoryDialog(lookupMatch!['vehicle']['id'].toString(), initialVehicle: lookupMatch!['vehicle']);
                                  }
                                },
                                icon: const Icon(Icons.history_edu, size: 15, color: Color(0xFF15803D)),
                                label: const Text('View Passport', style: TextStyle(fontSize: 12, color: Color(0xFF15803D), fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),

                      // Fleet Unit & Assigned Driver Row
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: fleetUnitCtrl,
                              decoration: const InputDecoration(labelText: 'Fleet Unit # (e.g. BUS-04, CAR-12)', border: OutlineInputBorder()),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: assignedDriverCtrl,
                              decoration: const InputDecoration(labelText: 'Assigned Driver / Pilot Name', border: OutlineInputBorder()),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: driverPhoneCtrl,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(labelText: 'Driver Phone Number', border: OutlineInputBorder()),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Customer / Institutional Owner Row
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: customerNameCtrl,
                              decoration: const InputDecoration(labelText: 'Customer / Institution Name *', border: OutlineInputBorder()),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: phoneCtrl,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'Owner / Contact Phone (WhatsApp) *',
                                hintText: 'e.g. +254 712 345 678',
                                prefixIcon: Icon(Icons.phone_outlined),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Vehicle Specs & Fuel Type Row
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: makeCtrl,
                              decoration: const InputDecoration(labelText: 'Vehicle Make (e.g. Toyota)', border: OutlineInputBorder()),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: modelCtrl,
                              decoration: const InputDecoration(labelText: 'Vehicle Model (e.g. Prado)', border: OutlineInputBorder()),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              value: ['Petrol', 'Diesel', 'Hybrid', 'Electric'].contains(fuelType) ? fuelType : 'Petrol',
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
                              onChanged: (val) => setModalState(() => fuelType = val ?? 'Petrol'),
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
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              value: techList.contains(techCtrl.text.trim())
                                  ? techCtrl.text.trim()
                                  : (techCtrl.text.trim().isEmpty ? 'Unassigned' : techList.first),
                              decoration: const InputDecoration(
                                labelText: 'Assigned Technician (Live Status)',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.engineering_outlined),
                              ),
                              items: techList.map((tName) {
                                if (tName == 'Unassigned') {
                                  return const DropdownMenuItem<String>(
                                    value: 'Unassigned',
                                    child: Row(
                                      children: [
                                        Icon(Icons.person_outline, size: 16, color: Colors.grey),
                                        SizedBox(width: 8),
                                        Text('Unassigned / Pool', style: TextStyle(color: Colors.grey, fontSize: 13)),
                                      ],
                                    ),
                                  );
                                }
                                final activeCount = _getTechnicianActiveJobsCount(tName, excludeJobId: existingJob?['id']?.toString());
                                final empMatch = candidateTechnicians.firstWhere((e) => e['name']?.toString() == tName, orElse: () => {});
                                final spec = (empMatch['specialization'] ?? '').toString().trim();

                                return DropdownMenuItem<String>(
                                  value: tName,
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: activeCount == 0
                                              ? const Color(0xFF10B981)
                                              : (activeCount <= 2 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444)),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(tName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis),
                                            if (spec.isNotEmpty)
                                              Text(spec, style: const TextStyle(fontSize: 10, color: Colors.grey), overflow: TextOverflow.ellipsis),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: activeCount == 0
                                              ? const Color(0xFFECFDF5)
                                              : const Color(0xFFFFFBEB),
                                          border: Border.all(
                                            color: activeCount == 0
                                                ? const Color(0xFFA7F3D0)
                                                : const Color(0xFFFDE68A),
                                          ),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          activeCount == 0 ? '🟢 Available (0 jobs)' : '🟡 Assigned ($activeCount active)',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: activeCount == 0 ? const Color(0xFF047857) : const Color(0xFFB45309),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                              selectedItemBuilder: (ctx) => techList.map((tName) {
                                if (tName == 'Unassigned' || tName.isEmpty) {
                                  return const Text('Unassigned / Pool', style: TextStyle(color: Colors.grey, fontSize: 13));
                                }
                                final activeCount = _getTechnicianActiveJobsCount(tName, excludeJobId: existingJob?['id']?.toString());
                                return Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: activeCount == 0 ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        '$tName (${activeCount == 0 ? "Available" : "$activeCount active"})',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                              onChanged: (val) {
                                setModalState(() {
                                  techCtrl.text = (val == null || val == 'Unassigned') ? '' : val;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 1,
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              value: bayOptions.contains(bayNumber) ? bayNumber : 'Bay 1',
                              decoration: const InputDecoration(labelText: 'Workshop Bay / Lift', border: OutlineInputBorder()),
                              items: bayOptions.map((b) => DropdownMenuItem(value: b, child: Text(b, overflow: TextOverflow.ellipsis))).toList(),
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
                              isExpanded: true,
                              value: status,
                              decoration: const InputDecoration(labelText: '7-Stage Workflow Status', border: OutlineInputBorder()),
                              items: const [
                                DropdownMenuItem(value: 'BOOKED', child: Text('1. Checked-In', overflow: TextOverflow.ellipsis)),
                                DropdownMenuItem(value: 'INSPECTION', child: Text('2. Inspection & OBD-II', overflow: TextOverflow.ellipsis)),
                                DropdownMenuItem(value: 'AWAITING_APPROVAL', child: Text('3. Awaiting Approval', overflow: TextOverflow.ellipsis)),
                                DropdownMenuItem(value: 'IN_PROGRESS', child: Text('4. In Repair', overflow: TextOverflow.ellipsis)),
                                DropdownMenuItem(value: 'WAITING', child: Text('5. Waiting Parts', overflow: TextOverflow.ellipsis)),
                                DropdownMenuItem(value: 'QUALITY_CHECK', child: Text('6. Quality Check (QC)', overflow: TextOverflow.ellipsis)),
                                DropdownMenuItem(value: 'READY', child: Text('7. Ready for Pickup', overflow: TextOverflow.ellipsis)),
                                DropdownMenuItem(value: 'COMPLETED', child: Text('Delivered / Closed', overflow: TextOverflow.ellipsis)),
                              ],
                              onChanged: (val) => setModalState(() => status = val ?? 'IN_PROGRESS'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              value: priority,
                              decoration: const InputDecoration(labelText: 'Priority', border: OutlineInputBorder()),
                              items: const [
                                DropdownMenuItem(value: 'Low', child: Text('Low', overflow: TextOverflow.ellipsis)),
                                DropdownMenuItem(value: 'Medium', child: Text('Medium', overflow: TextOverflow.ellipsis)),
                                DropdownMenuItem(value: 'High', child: Text('High', overflow: TextOverflow.ellipsis)),
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
                              isExpanded: true,
                              value: ['Empty', '1/4', 'Half', '3/4', 'Full'].contains(fuelLevel) ? fuelLevel : 'Half',
                              decoration: const InputDecoration(labelText: 'Fuel Level', border: OutlineInputBorder()),
                              items: ['Empty', '1/4', 'Half', '3/4', 'Full']
                                  .map((f) => DropdownMenuItem(value: f, child: Text(f, overflow: TextOverflow.ellipsis)))
                                  .toList(),
                              onChanged: (val) => setModalState(() => fuelLevel = val ?? 'Half'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: estHoursCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Est. Labour Hours',
                                prefixIcon: Icon(Icons.timer_outlined, size: 18),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: actualHoursCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Actual Labour Hours',
                                prefixIcon: Icon(Icons.history_toggle_off, size: 18),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isWarranty ? Colors.amber.shade50 : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: isWarranty ? Colors.amber.shade300 : Colors.grey.shade200),
                        ),
                        child: Wrap(
                          spacing: 20,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () => setModalState(() => isWarranty = !isWarranty),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Checkbox(
                                    value: isWarranty,
                                    onChanged: (v) => setModalState(() => isWarranty = v ?? false),
                                  ),
                                  const Text('Warranty / Comeback Rework Job', style: TextStyle(fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                            InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () => setModalState(() => qcPassed = !qcPassed),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Checkbox(
                                    value: qcPassed,
                                    activeColor: Colors.green,
                                    onChanged: (v) => setModalState(() => qcPassed = v ?? false),
                                  ),
                                  const Text('Quality Control (QC) Road-Test Passed', style: TextStyle(fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
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
                        '360\u00B0 Vehicle Walk-Around Inspection (Select Body Type, Angle & Tap to Mark Dents/Scratches/Cuts)',
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
                            if (_deny('job:delete', 'delete job cards')) return;
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
                          if (phoneCtrl.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(backgroundColor: Colors.orange, content: Text('Customer / Owner Phone Number is mandatory.')),
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
                              'category': clientCategory,
                              'fleetUnitNumber': fleetUnitCtrl.text.trim().isEmpty ? null : fleetUnitCtrl.text.trim(),
                              'assignedDriver': assignedDriverCtrl.text.trim().isEmpty ? null : assignedDriverCtrl.text.trim(),
                              'driverPhone': driverPhoneCtrl.text.trim().isEmpty ? null : driverPhoneCtrl.text.trim(),
                              'make': makeCtrl.text.trim(),
                              'model': modelCtrl.text.trim(),
                              'fuelType': fuelType,
                              'bodyType': bodyType.name,
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
                              'actualHours': double.tryParse(actualHoursCtrl.text.trim()) ?? 0.0,
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

  Future<void> _showAddWebRecommendationDialog(Map<String, dynamic> job, StateSetter setParentState) async {
    String selectedSystem = 'Engine';
    String urgency = 'RECOMMENDED';
    final issueCtrl = TextEditingController();
    final fixCtrl = TextEditingController();
    final partsCtrl = TextEditingController();
    final labourPriceCtrl = TextEditingController();
    final partsPriceCtrl = TextEditingController();
    bool isSubmitting = false;

    await showDialog(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (dCtx, setDlg) => AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.build_circle, color: Color(0xFFB45309), size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Add Technician Defect Finding & Recommendation', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedSystem,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Affected Vehicle System *', border: OutlineInputBorder(), isDense: true),
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
                    onChanged: (v) => setDlg(() => selectedSystem = v ?? 'Engine'),
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
                    onChanged: (v) => setDlg(() => urgency = v ?? 'RECOMMENDED'),
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
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(dCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
              icon: isSubmitting
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check, size: 16),
              label: Text(isSubmitting ? 'Saving...' : 'Add Recommendation'),
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
                      setDlg(() => isSubmitting = true);
                      try {
                        final authHeaders = AuthService.instance.authHeaders;
                        final techName = (job['technician'] != null && job['technician'].toString().isNotEmpty)
                            ? job['technician'].toString()
                            : AuthService.instance.userName;
                        final resp = await http.post(
                          Uri.parse('$_baseUrl/jobs/${job['id']}/recommendations'),
                          headers: {
                            'Content-Type': 'application/json',
                            ...authHeaders,
                            'x-user-name': AuthService.instance.userName,
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

                          setParentState(() {});
                          if (dCtx.mounted) Navigator.pop(dCtx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: Colors.green.shade700,
                              content: const Text('Recommendation added! It will now appear on Estimates automatically.'),
                            ),
                          );
                          SyncService.instance.triggerSync();
                          _refreshAllDataSilently();
                        } else {
                          throw Exception(resp.body);
                        }
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(backgroundColor: Colors.red, content: Text('Error adding recommendation: $e')),
                        );
                      } finally {
                        if (dCtx.mounted) setDlg(() => isSubmitting = false);
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showViewJobDialog(Map<String, dynamic> job) async {
    final jobNo = job['jobNumber'] ?? job['id'].toString().substring(0, 8).toUpperCase();
    final customer = job['customer'] ?? {};
    final vehicle = job['vehicle'] ?? {};
    final estimates = (job['estimates'] as List<dynamic>?) ?? [];
    List<dynamic> vehicleRequests = [];
    bool loadingReqs = true;

    try {
      final reqRes = await http.get(
        Uri.parse('$_baseUrl/inventory/requests?jobCardId=${job['id']}'),
        headers: {'Content-Type': 'application/json', 'x-user-role': _activeUserRole},
      );
      if (reqRes.statusCode == 200) {
        final decoded = json.decode(reqRes.body);
        if (decoded is List) vehicleRequests = decoded;
      }
    } catch (_) {}
    loadingReqs = false;

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
                  Expanded(child: Text('Job Card $jobNo \u2014 ${customer['name'] ?? ''}')),
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
                                  Row(
                                    children: [
                                      Text('Technician: ${job['technician'] ?? 'Unassigned'}  \u2022  Bay: ${job['bayNumber'] ?? 'Bay 1'}'),
                                      const SizedBox(width: 8),
                                      InkWell(
                                        onTap: () {
                                          Navigator.pop(ctx);
                                          _showJobCardDialog(existingJob: job);
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFEFF6FF),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: const Color(0xFFBFDBFE)),
                                          ),
                                          child: const Text('Re-assign', style: TextStyle(fontSize: 10.5, color: Color(0xFF2563EB), fontWeight: FontWeight.bold)),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text('Priority: ${job['priority'] ?? 'Medium'} \u2022 Due: ${_formatDateShort(job['dueDate'])}'),
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
                                  Text('Odometer: ${job['odometer'] != null ? '${job['odometer']} km' : 'Not recorded'}  \u2022  Next Service: ${job['nextServiceMileage'] != null ? '${job['nextServiceMileage']} km' : 'TBA'}'),
                                  Text('Fuel Level: ${job['fuelLevel'] ?? 'Not recorded'}  \u2022  QC Passed: ${qcPassed ? 'YES \u2713' : 'Pending'}'),
                                  if (obdCodes.isNotEmpty)
                                    Text('OBD-II Codes: $obdCodes', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // -------------------------------------------------------------
                      // TECHNICIAN DEFECT FINDINGS & RECOMMENDATIONS
                      // -------------------------------------------------------------
                      Builder(builder: (_) {
                        final walkData = job['walkAroundData'] is Map ? (job['walkAroundData'] as Map) : {};
                        final recs = (walkData['recommendations'] is List)
                            ? (walkData['recommendations'] as List).whereType<Map>().map((r) => Map<String, dynamic>.from(r)).toList()
                            : <Map<String, dynamic>>[];

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: recs.isNotEmpty ? const Color(0xFFFFFBEB) : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: recs.isNotEmpty ? const Color(0xFFFDE68A) : Colors.grey.shade300),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.build_circle, color: recs.isNotEmpty ? const Color(0xFFB45309) : const Color(0xFF1E3A8A), size: 18),
                                      const SizedBox(width: 8),
                                      Text(
                                        'TECHNICIAN FINDINGS & RECOMMENDATIONS (${recs.length})',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: recs.isNotEmpty ? const Color(0xFF78350F) : Colors.grey.shade800,
                                        ),
                                      ),
                                    ],
                                  ),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF2563EB),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    icon: const Icon(Icons.add, size: 14),
                                    label: const Text('Add Finding', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                    onPressed: () => _showAddWebRecommendationDialog(job, setModalState),
                                  ),
                                ],
                              ),
                              if (recs.isEmpty) ...[
                                const SizedBox(height: 6),
                                const Text(
                                  'No additional defects logged for this vehicle yet. Click "+ Add Finding" to record newly discovered issues or parts recommendations.',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ] else ...[
                                const SizedBox(height: 8),
                                ...recs.map((rec) {
                                  final sys = (rec['system'] ?? 'General').toString();
                                  final issue = (rec['issue'] ?? '').toString();
                                  final fix = (rec['recommendation'] ?? '').toString();
                                  final urgency = (rec['urgency'] ?? 'RECOMMENDED').toString();
                                  final tech = (rec['technicianName'] ?? 'Technician').toString();
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
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.amber.shade200),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: badgeColor.withValues(alpha: 0.1),
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
                                              ),
                                              child: Text(
                                                '$sys \u2022 $urgency',
                                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: badgeColor),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text('Discovered by $tech', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                            const Spacer(),
                                            Text(
                                              'Total: KES ${total.toStringAsFixed(0)} (Labour: ${labourPrice.toStringAsFixed(0)} | Parts: ${partsPrice.toStringAsFixed(0)})',
                                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text('Defect / Issue: $issue', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
                                        Text('Recommended Action: $fix', style: const TextStyle(fontSize: 12, color: Color(0xFF334155))),
                                        if (rec['partsNeeded'] != null && rec['partsNeeded'].toString().isNotEmpty)
                                          Text('Parts Required: ${rec['partsNeeded']}', style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade700)),
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
                                                foregroundColor: Colors.green.shade700,
                                                side: BorderSide(color: Colors.green.shade600),
                                              ),
                                              icon: const Icon(Icons.chat_outlined, size: 13, color: Colors.green),
                                              label: const Text('WhatsApp Customer Recommendation', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                              onPressed: () {
                                                final custPhone = customer['phone']?.toString() ?? '';
                                                final custName = customer['name']?.toString() ?? 'Customer';
                                                final regNo = vehicle['registrationNo']?.toString() ?? 'vehicle';
                                                final makeModel = '${vehicle['make'] ?? ''} ${vehicle['model'] ?? ''}'.trim();
                                                final msg = 'Hello $custName, during inspection of your $makeModel ($regNo) at ${_workshopSettings['name'] ?? 'our workshop'}, technician $tech identified an additional issue:\n\n• $sys Issue: $issue\n• Recommended Repair: $fix\n• Estimated Cost: KES ${total.toStringAsFixed(0)} (Labour: KES ${labourPrice.toStringAsFixed(0)}, Parts: KES ${partsPrice.toStringAsFixed(0)})\n\nWould you like us to add this to your estimate and proceed with repair?';
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
                                              icon: const Icon(Icons.receipt_long, size: 13),
                                              label: const Text('Create Estimate with this Finding', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                              onPressed: () {
                                                Navigator.pop(ctx);
                                                setState(() {
                                                  _activeSidebar = 'Estimates';
                                                  _activeTab = 'Estimates';
                                                  _showEstimateCreator = true;
                                                  _preselectedJobIdForEstimate = job['id'];
                                                });
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
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
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
                          OutlinedButton.icon(
                            onPressed: () {
                              final msg = 'Hello ${customer['name'] ?? 'Customer'}, your vehicle ${vehicle['registrationNo'] ?? ''} (Job Card $jobNo) at ${_workshopSettings['name'] ?? 'AutoKe'} is currently in stage: ${_statusLabel(job['status'] ?? 'IN_PROGRESS')}.';
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
                              subtitle: Text('Status: ${est['status']} \u2022 Subtotal: KSH ${(est['subtotal'] as num).toStringAsFixed(2)}'),
                            ),
                          );
                        }).toList(),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.inventory_2_outlined, color: Color(0xFF0F4C81), size: 18),
                              const SizedBox(width: 8),
                              Text('Vehicle Parts & Material Requisitions (${vehicleRequests.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            ],
                          ),
                          ElevatedButton.icon(
                            onPressed: () => _showRequestPartsForVehicleDialog(job, () async {
                              final reqRes = await http.get(
                                Uri.parse('$_baseUrl/inventory/requests?jobCardId=${job['id']}'),
                                headers: {'Content-Type': 'application/json', 'x-user-role': _activeUserRole},
                              );
                              if (reqRes.statusCode == 200) {
                                final decoded = json.decode(reqRes.body);
                                if (decoded is List) {
                                  setModalState(() => vehicleRequests = decoded);
                                }
                              }
                            }),
                            icon: const Icon(Icons.add_shopping_cart, size: 16),
                            label: const Text('Request Parts for this Vehicle'),
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F4C81), foregroundColor: Colors.white),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (loadingReqs)
                        const Padding(padding: EdgeInsets.all(8), child: Center(child: CircularProgressIndicator()))
                      else if (vehicleRequests.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
                          child: const Text('No parts or supplies requested for this vehicle yet. Click "+ Request Parts for this Vehicle" to submit a requisition to Storekeeper & Workshop Manager.', style: TextStyle(color: Colors.black54, fontSize: 13)),
                        )
                      else
                        ...vehicleRequests.map((vr) {
                          final status = (vr['status'] ?? 'PENDING').toString();
                          final ref = vr['reference'] ?? 'REQ';
                          final lines = (vr['lines'] as List<dynamic>?) ?? [];
                          final isAck = vr['acknowledgedAt'] != null;

                          Color sc = Colors.amber.shade800;
                          if (status == 'ORDERED') sc = Colors.indigo;
                          if (status == 'APPROVED') sc = Colors.blue;
                          if (status == 'ISSUED') sc = Colors.green;
                          if (status == 'REJECTED') sc = Colors.red;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(ref, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(color: sc.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                                        child: Text(status.replaceAll('_', ' '), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: sc)),
                                      ),
                                      const Spacer(),
                                      Text('by ${vr['technicianName'] ?? 'Technician'}', style: const TextStyle(color: Colors.black54, fontSize: 12)),
                                    ],
                                  ),
                                  if (status == 'ORDERED') ...[
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(6)),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.local_shipping, size: 15, color: Colors.indigo),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              'Ordered from Supplier • PO: ${vr['poNumber'] ?? '-'} • ETA: ${vr['estimatedArrival'] ?? 'TBA'}',
                                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.indigo),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 6),
                                  ...lines.map((l) => Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 2),
                                    child: Row(
                                      children: [
                                        Expanded(child: Text('• ${l['description'] ?? 'Item'} (x${l['qtyRequested'] ?? 1})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                                        Text('Approved: ${l['qtyApproved'] ?? 0}  |  Issued: ${l['qtyIssued'] ?? 0}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                      ],
                                    ),
                                  )),
                                  if (isAck) ...[
                                    const SizedBox(height: 4),
                                    Text('✓ Physical receipt confirmed by ${vr['acknowledgedBy'] ?? 'Technician'}', style: TextStyle(fontSize: 11, color: Colors.green.shade800, fontWeight: FontWeight.bold)),
                                  ],
                                ],
                              ),
                            ),
                          );
                        }),
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

  Future<void> _showRequestPartsForVehicleDialog(Map<String, dynamic> job, VoidCallback onSubmitted) async {
    bool isCustom = false;
    final customDescCtrl = TextEditingController();
    String customCategory = 'SPARE_PART';
    final qtyCtrl = TextEditingController(text: '1');
    final reasonCtrl = TextEditingController();
    Map<String, dynamic>? selectedItem;
    List<dynamic> catalogResults = [];
    final techCtrl = TextEditingController(text: (job['technician'] ?? '').toString().isNotEmpty ? job['technician'] : 'Technician');

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.add_shopping_cart, color: Color(0xFF0F4C81)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Request Parts for ${job['vehicle']?['registrationNo'] ?? 'Vehicle'} (${job['jobNumber'] ?? ''})'),
              ),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        const Icon(Icons.directions_car, color: Color(0xFF0F4C81), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Vehicle: ${job['vehicle']?['registrationNo'] ?? ''} ${job['vehicle']?['make'] ?? ''} ${job['vehicle']?['model'] ?? ''} • Job: ${job['jobNumber'] ?? ''}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF0F4C81)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: techCtrl,
                    decoration: const InputDecoration(labelText: 'Requesting Technician *', border: OutlineInputBorder(), prefixIcon: Icon(Icons.person_outline)),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => setModalState(() => isCustom = false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(color: !isCustom ? const Color(0xFF0F4C81) : Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
                            child: Center(child: Text('Catalog Stock', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: !isCustom ? Colors.white : Colors.black87))),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: InkWell(
                          onTap: () => setModalState(() => isCustom = true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(color: isCustom ? Colors.amber.shade800 : Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
                            child: Center(child: Text('Custom / Order Needed', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isCustom ? Colors.white : Colors.black87))),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (!isCustom) ...[
                    TextField(
                      decoration: const InputDecoration(hintText: 'Search parts catalog by name or part #...', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
                      onChanged: (q) async {
                        if (q.length < 2) { setModalState(() => catalogResults = []); return; }
                        try {
                          final res = await http.get(Uri.parse('$_baseUrl/inventory/catalog?search=$q'), headers: {'x-user-role': _activeUserRole});
                          if (res.statusCode == 200) {
                            setModalState(() => catalogResults = json.decode(res.body));
                          }
                        } catch (_) {}
                      },
                    ),
                    if (catalogResults.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 160),
                        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: catalogResults.length,
                          itemBuilder: (_, i) {
                            final item = catalogResults[i];
                            return ListTile(
                              dense: true,
                              title: Text(item['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              subtitle: Text('Stock: ${item['quantity'] ?? 0}  |  ${item['category']}', style: const TextStyle(fontSize: 11)),
                              selected: selectedItem?['id'] == item['id'],
                              selectedTileColor: Colors.blue.shade50,
                              onTap: () => setModalState(() {
                                selectedItem = Map<String, dynamic>.from(item);
                                catalogResults = [];
                              }),
                            );
                          },
                        ),
                      ),
                    ],
                    if (selectedItem != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(6)),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.green, size: 16),
                            const SizedBox(width: 8),
                            Expanded(child: Text('Selected: ${selectedItem!['name']} (Stock: ${selectedItem!['quantity'] ?? 0})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          ],
                        ),
                      ),
                    ],
                  ] else ...[
                    TextField(
                      controller: customDescCtrl,
                      decoration: const InputDecoration(labelText: 'Part / Item Name * (e.g. Brake Master Cylinder)', border: OutlineInputBorder()),
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
                      onChanged: (v) => setModalState(() => customCategory = v ?? 'SPARE_PART'),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity Required *', border: OutlineInputBorder())),
                  const SizedBox(height: 10),
                  TextField(controller: reasonCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Reason for Request *', hintText: 'e.g. Needed to complete brake overhaul', border: OutlineInputBorder())),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F4C81), foregroundColor: Colors.white),
              icon: const Icon(Icons.send, size: 16),
              label: const Text('Submit Request'),
              onPressed: () async {
                if (!isCustom && selectedItem == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a catalog item or switch to Custom Item'), backgroundColor: Colors.orange));
                  return;
                }
                if (isCustom && customDescCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter part description'), backgroundColor: Colors.orange));
                  return;
                }
                if (reasonCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a reason'), backgroundColor: Colors.orange));
                  return;
                }

                final qty = int.tryParse(qtyCtrl.text) ?? 1;
                final line = isCustom
                    ? {'category': customCategory, 'description': customDescCtrl.text.trim(), 'quantity': qty}
                    : {'category': selectedItem!['category'], 'itemId': selectedItem!['id'], 'description': selectedItem!['name'], 'quantity': qty};

                final body = <String, dynamic>{
                  'reason': reasonCtrl.text.trim(),
                  'technicianName': techCtrl.text.trim(),
                  'jobCardId': job['id'],
                  'lines': [line],
                };

                try {
                  final res = await http.post(
                    Uri.parse('$_baseUrl/inventory/requests'),
                    headers: {'Content-Type': 'application/json', 'x-user-role': _activeUserRole, 'x-user-name': techCtrl.text.trim()},
                    body: json.encode(body),
                  );
                  if (res.statusCode == 201) {
                    if (ctx.mounted) Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Requisition submitted! Visible to Storekeeper & Workshop Manager.'), backgroundColor: Colors.green),
                    );
                    onSubmitted();
                  } else {
                    final err = json.decode(res.body)['error'] ?? 'Submission failed';
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err), backgroundColor: Colors.red));
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // DIALOG: ADD / EDIT PART IN CATALOG + STOCK LEDGER
  // ==========================================
  Future<void> _showPartDialog({Map<String, dynamic>? existingPart}) async {
    if (_deny('part:edit', 'add or edit spare parts')) return;
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
    if (_deny('stock:adjust', 'adjust stock')) return;
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
              title: Text('Stock Ledger: ${part['partNumber']} \u2014 ${part['description']}'),
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
                              isExpanded: true,
                              value: moveType,
                              decoration: const InputDecoration(labelText: 'Movement Type', border: OutlineInputBorder()),
                              items: const [
                                DropdownMenuItem(value: 'RECEIVED', child: Text('Receive Stock (+ In)', overflow: TextOverflow.ellipsis)),
                                DropdownMenuItem(value: 'ISSUED', child: Text('Issue to Job (- Out)', overflow: TextOverflow.ellipsis)),
                                DropdownMenuItem(value: 'RETURNED', child: Text('Customer/Job Return (+ In)', overflow: TextOverflow.ellipsis)),
                                DropdownMenuItem(value: 'ADJUSTED', child: Text('Stocktake Set Exact (=)', overflow: TextOverflow.ellipsis)),
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
                              title: Text('${m['type']}: ${m['quantity']} units  \u2022  Ref: ${m['reference'] ?? '-'}',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                              subtitle: Text('Supplier: ${m['supplierName'] ?? '-'}  \u2022  ${_formatDateShort(m['createdAt'])}',
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
    if (_deny('payment:record', 'record payments')) return;
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
              title: Text('Record Payment / Deposit \u2014 INV-${inv['id'].toString().substring(0, 6).toUpperCase()}'),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Invoice Total: KSH ${total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('Already Paid: KSH ${alreadyPaid.toStringAsFixed(2)}  \u2022  Balance Due: KSH ${remaining.toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.blueGrey, fontSize: 13)),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: mode,
                      decoration: const InputDecoration(labelText: 'Payment Mode', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'MPESA', child: Text('M-Pesa (Paybill / Till)', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'CASH', child: Text('Cash', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'BANK TRANSFER', child: Text('Bank Transfer / Cheque', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'CARD', child: Text('POS Card', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'INVOICE CREDIT', child: Text('Pay Later / Corporate Credit', overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => setModalState(() => mode = v ?? 'MPESA'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Amount Received Now (KSH) \u2014 Enter Deposit or Full Balance',
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
              Text('Vehicle & Service History \u2014 ${customer['name'] ?? ''}'),
              OutlinedButton.icon(
                onPressed: () {
                  final firstReg = vehicles.isNotEmpty ? vehicles.first['registrationNo'] : 'your vehicle';
                  final msg = 'Hello ${customer['name']}, this is a courtesy reminder from ${_workshopSettings['name'] ?? 'AutoKe'} that $firstReg is due for its scheduled routine maintenance service.';
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
                  Text('Phone: ${customer['phone'] ?? '-'}  \u2022  Registered Vehicles: ${vehicles.length}  \u2022  Total Visits: ${jobs.length}',
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
                            '${j['jobNumber'] ?? 'Job'} \u2014 ${v['registrationNo'] ?? ''} (${v['make'] ?? ''} ${v['model'] ?? ''})',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Work: ${j['workRequested'] ?? '-'}  \u2022  Technician: ${j['technician'] ?? '-'}'),
                              Text('Odometer: ${j['odometer'] ?? '-'} km  \u2022  Date: ${_formatDateShort(j['createdAt'])}  \u2022  Estimates: ${ests.length}'),
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
    if (_deny('appt:edit', 'book appointments')) return;
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
                            isExpanded: true,
                            value: bay,
                            decoration: const InputDecoration(labelText: 'Assigned Bay', border: OutlineInputBorder()),
                            items: ['Bay 1', 'Bay 2', 'Bay 3', 'Lift 1', 'Lift 2']
                                .map((b) => DropdownMenuItem(value: b, child: Text(b, overflow: TextOverflow.ellipsis)))
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
    if (_deny('expense:record', 'record expenses')) return;
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
                      isExpanded: true,
                      value: category,
                      decoration: const InputDecoration(labelText: 'Expense Category', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'Workshop Consumables', child: Text('Workshop Consumables & Oils', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'Rent & Utilities', child: Text('Rent, Electricity & Water', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'Casual Labour & Allowances', child: Text('Casual Labour & Technician Allowances', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'Tools & Equipment', child: Text('Tools & Equipment Maintenance', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'Transport & Parts Delivery', child: Text('Transport & Parts Delivery', overflow: TextOverflow.ellipsis)),
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
                            isExpanded: true,
                            value: mode,
                            decoration: const InputDecoration(labelText: 'Paid Via', border: OutlineInputBorder()),
                            items: const [
                              DropdownMenuItem(value: 'CASH', child: Text('Cash', overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: 'MPESA', child: Text('M-Pesa', overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: 'BANK', child: Text('Bank', overflow: TextOverflow.ellipsis)),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  overflow: TextOverflow.ellipsis,
                  text: const TextSpan(
                    children: [
                      TextSpan(
                        text: 'Auto',
                        style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                      ),
                      TextSpan(
                        text: 'Ke',
                        style: TextStyle(color: Color(0xFF38BDF8), fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'WORKSHOP & GARAGE OS',
                  style: TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.9),
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
                  _sidebarItem(Icons.directions_car_filled, 'Vehicles & Fleets'),
                  _sidebarItem(Icons.badge, 'Employees'),
                  _sidebarItem(Icons.bar_chart, 'Reports'),
                  _sidebarItem(Icons.warehouse, 'Inventory'),
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
    if (!_can('nav:${title == 'Dashboard' ? 'Dashboard' : title}')) return const SizedBox.shrink();
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
            if (title == 'Dashboard') {
              _activeTab = _firstAllowedTab();
            } else if (tabTarget != null) {
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
            AnimatedBuilder(
              animation: SyncService.instance,
              builder: (_, __) {
                final isSyncing = SyncService.instance.isSyncing;
                final isLive = SyncService.instance.hasLiveConnection;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isLive ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isLive ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: isLive ? const Color(0xFF16A34A) : Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        isSyncing ? 'Syncing...' : 'Live Sync',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: isLive ? const Color(0xFF15803D) : Colors.red.shade800,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4, offset: const Offset(0, 1))
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: const Color(0xFF1E3A8A),
                    child: Text(
                      AuthService.instance.userName.isNotEmpty
                          ? AuthService.instance.userName[0].toUpperCase()
                          : 'U',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        AuthService.instance.userName.isNotEmpty
                            ? AuthService.instance.userName
                            : 'Workshop User',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _activeUserRole,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.circle, size: 7, color: Colors.green),
                          const SizedBox(width: 2),
                          const Text('Online', style: TextStyle(fontSize: 10, color: Colors.green)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Sign Out',
                    icon: const Icon(Icons.logout, size: 18, color: Colors.redAccent),
                    onPressed: _confirmSignOut,
                  ),
                ],
              ),
            ),
          ],
        )
      ],
    );
  }

  Widget _buildStatsRow() {
    final isInvRole = _activeUserRole == 'STOREKEEPER' || _activeUserRole == 'INVENTORY_MANAGER';
    if (isInvRole) {
      final balances = (_inventorySummary['balances'] as List<dynamic>?) ?? [];
      final lowStockList = (_inventorySummary['lowStock'] as List<dynamic>?) ?? [];
      final partsByJob = (_inventorySummary['partsByJob'] as List<dynamic>?) ?? [];
      final movementTotals = (_inventorySummary['movementTotalsByType'] as Map<String, dynamic>?) ?? {};
      final spoiledList = _inventoryReturns.where((r) =>
        r['kind'] == 'DAMAGED' || r['kind'] == 'LOST' || r['condition'] == 'DAMAGED' || r['condition'] == 'DEFECTIVE' || r['status'] == 'QUARANTINED' || r['status'] == 'WRITTEN_OFF'
      ).toList();
      final totalIssued = movementTotals['ISSUE'] ?? 0;
      final catalogCount = balances.isNotEmpty ? balances.length : _parts.length;
      final lowCount = lowStockList.isNotEmpty ? lowStockList.length : (_dashboard['lowStockCount'] ?? 0);

      return Row(
        children: [
          _statCard(
            'Stock Catalog',
            '$catalogCount Items',
            'Parts, Tools & Consumables',
            Colors.blue.shade800,
            Icons.inventory_2,
            Colors.blue,
            onPlusTap: () => setState(() => _activeSidebar = 'Inventory'),
          ),
          const SizedBox(width: 16),
          _statCard(
            'Issued Items',
            '$totalIssued Units',
            '${partsByJob.length} Repair Jobs Supplied',
            Colors.green.shade800,
            Icons.output,
            Colors.green,
            onPlusTap: () => setState(() => _activeSidebar = 'Reports'),
          ),
          const SizedBox(width: 16),
          _statCard(
            'Low Stock Alerts',
            '$lowCount Reorders',
            lowCount > 0 ? 'Requires Replenishment' : 'All Stock Healthy',
            lowCount > 0 ? Colors.orange.shade800 : Colors.green.shade800,
            Icons.warning_amber_rounded,
            Colors.orange,
            onPlusTap: () => setState(() => _activeSidebar = 'Reports'),
          ),
          const SizedBox(width: 16),
          _statCard(
            'Spoiled & Damaged',
            '${spoiledList.length} Items',
            '${_inventorySummary['pendingInspections'] ?? 0} Pending QC Inspection',
            spoiledList.isNotEmpty ? Colors.red.shade800 : Colors.teal.shade800,
            Icons.remove_circle_outline,
            Colors.red,
            onPlusTap: () => setState(() => _activeSidebar = 'Reports'),
          ),
        ],
      );
    }

    final rev = (_dashboard['totalRevenue'] as num?)?.toDouble() ?? 0.0;
    final activeJobs = _dashboard['activeJobsCount'] ?? 0;
    final pendingEst = _dashboard['pendingEstimatesCount'] ?? 0;
    final lowStock = _dashboard['lowStockCount'] ?? 0;

    return Row(
      children: [
        _statCard(
          'Total Revenue',
          'KSH ${rev.toStringAsFixed(2)}',
          '\u2191 Paid & Approved',
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
          '\u2191 Total Jobs: ${_dashboard['totalJobsCount'] ?? 0}',
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
    if (_activeSidebar == 'Vehicles & Fleets') return _buildVehiclesSection();
    if (_activeSidebar == 'Employees') return _buildEmployeesSection();
    if (_activeSidebar == 'Reports') return _buildReportsSection();
    if (_activeSidebar == 'Settings') return _buildSettingsSection();
    if (_activeSidebar == 'Inventory') return InventoryWorkspaceView(
      activeUserRole: _activeUserRole,
      activeUserName: 'Admin',
      onDataChanged: () => _refreshAllData(),
    );

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
          if (_activeTab == 'Current Job Cards' && _can('nav:Job Cards')) _buildJobCardsTabContent(),
          if (_activeTab == 'Parts Catalog' && _can('nav:Parts Catalog')) _buildPartsCatalogTabContent(),
          if (_activeTab == 'Estimates' && _can('nav:Estimates')) _buildEstimatesTabContent(),
          if (_activeTab == 'Invoices' && _can('nav:Invoices')) _buildInvoicesTabContent(),
          if (!_can('nav:${_tabToNav[_activeTab]}'))
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Your role ($_activeUserRole) has no access to this section.'),
            ),
        ],
      ),
    );
  }

  Widget _buildTabItem(String text) {
    if (!_can('nav:${_tabToNav[text]}')) return const SizedBox.shrink();
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
                    final fuelType = (job['fuelType'] ?? job['vehicle']?['fuelType'] ?? 'Petrol').toString();
                    final dueDateStr = _formatDateShort(job['dueDate'] ?? job['createdAt']);

                    return _buildJobDataRow(
                      job: Map<String, dynamic>.from(job),
                      id: jobNo,
                      customer: customerName,
                      vehicle: vehicleDisplay,
                      fuelType: fuelType,
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
    required String fuelType,
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
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(vehicle),
              const SizedBox(width: 6),
              _buildFuelBadge(fuelType),
            ],
          ),
        ),
        DataCell(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(service, overflow: TextOverflow.ellipsis),
              Builder(builder: (_) {
                final wad = job['walkAroundData'] is Map ? (job['walkAroundData'] as Map) : null;
                final recs = (wad != null && wad['recommendations'] is List) ? (wad['recommendations'] as List) : [];
                if (recs.isEmpty) return const SizedBox.shrink();
                return Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFFF59E0B), width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lightbulb, size: 10, color: Color(0xFFB45309)),
                      const SizedBox(width: 3),
                      Text(
                        '${recs.length} Tech Finding${recs.length > 1 ? "s" : ""}',
                        style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFFB45309)),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
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
                                    if (_deny('part:delete', 'delete spare parts')) return;
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
                      final phone = job['customer']?['phone']?.toString() ?? '';
                      final reg = job['vehicle']?['registrationNo'] ?? '';
                      final subtotal = (est['subtotal'] as num).toDouble();
                      final discRate = (est['discountRate'] as num).toDouble();
                      final afterDisc = subtotal * (1 - discRate / 100);
                      final vat = afterDisc * 0.16;
                      final total = (est['total'] as num).toDouble();
                      final hasInvoice = est['invoice'] != null;
                      final estStatus = (est['status'] ?? 'DRAFT').toString();

                      return DataRow(
                        cells: [
                          DataCell(Text('$customer ($reg)', style: const TextStyle(fontWeight: FontWeight.bold))),
                          DataCell(Text('KSH ${subtotal.toStringAsFixed(2)}')),
                          DataCell(Text('${discRate.toStringAsFixed(0)}%')),
                          DataCell(Text('KSH ${vat.toStringAsFixed(2)}')),
                          DataCell(Text('KSH ${total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)))),
                          DataCell(
                            DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: ['DRAFT', 'SENT', 'APPROVED', 'REJECTED'].contains(estStatus) ? estStatus : 'DRAFT',
                                isDense: true,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: estStatus == 'APPROVED'
                                      ? Colors.green.shade800
                                      : estStatus == 'REJECTED'
                                          ? Colors.red.shade800
                                          : Colors.blue.shade800,
                                ),
                                items: const [
                                  DropdownMenuItem(value: 'DRAFT', child: Text('DRAFT')),
                                  DropdownMenuItem(value: 'SENT', child: Text('SENT TO CUSTOMER')),
                                  DropdownMenuItem(value: 'APPROVED', child: Text('APPROVED \u2713')),
                                  DropdownMenuItem(value: 'REJECTED', child: Text('REJECTED \u2717')),
                                ],
                                onChanged: (newSt) async {
                                  if (newSt == null) return;
                                  await http.put(
                                    Uri.parse('$_baseUrl/estimates/${est['id']}/status'),
                                    headers: {'Content-Type': 'application/json'},
                                    body: json.encode({'status': newSt}),
                                  );
                                  _refreshAllData();
                                },
                              ),
                            ),
                          ),
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
                                  const Text('Invoiced \u2713', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: () => InvoicePdfService.showPreviewModal(
                                    context: context,
                                    workshopSettings: _workshopSettings,
                                    estimate: Map<String, dynamic>.from(est),
                                    isInvoice: false,
                                  ),
                                  icon: const Icon(Icons.picture_as_pdf, size: 15, color: Color(0xFF1D4ED8)),
                                  label: const Text('A4 Quotation PDF', style: TextStyle(fontSize: 12, color: Color(0xFF1D4ED8))),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  tooltip: 'Send Quotation on WhatsApp for Approval',
                                  icon: const Icon(Icons.chat_outlined, color: Colors.green, size: 18),
                                  onPressed: () {
                                    final msg = 'Hello $customer, your repair quotation for vehicle $reg at ${_workshopSettings['name'] ?? 'AutoKe'} is KSH ${total.toStringAsFixed(0)} (Incl. ${discRate.toStringAsFixed(0)}% discount & 16% VAT). Please reply APPROVED so we can proceed with the repair.';
                                    _launchWhatsAppMessage(phone, msg);
                                  },
                                ),
                                IconButton(
                                  tooltip: 'Delete Estimate',
                                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                                  onPressed: () async {
                                    if (_deny('estimate:delete', 'delete estimates')) return;
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
                            const Text('Paid in Full \u2713', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
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
                            label: const Text('Invoice A4', style: TextStyle(fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F172A),
                              foregroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 6),
                          OutlinedButton.icon(
                            onPressed: () => InvoicePdfService.showPaymentReceiptPreviewModal(
                              context: context,
                              workshopSettings: _workshopSettings,
                              invoice: Map<String, dynamic>.from(inv),
                            ),
                            icon: const Icon(Icons.verified_outlined, size: 15, color: Color(0xFF15803D)),
                            label: const Text('Receipt & Gate Pass', style: TextStyle(fontSize: 12, color: Color(0xFF15803D), fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 4),
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
                              final msg = 'Hello $customer, your invoice INV-${inv['id'].toString().substring(0, 6).toUpperCase()} for $reg at ${_workshopSettings['name'] ?? 'AutoKe'} is KSH ${total.toStringAsFixed(0)} (Paid: KSH ${paid.toStringAsFixed(0)}, Balance Due: KSH ${bal.toStringAsFixed(0)}). Thank you!';
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
  // SIDEBAR SECTIONS: APPOINTMENTS (MODULE 8), CUSTOMERS, EMPLOYEES (MODULE 7), REPORTS (MODULE 9), SETTINGS
  // ==========================================
  Widget _buildAppointmentsSection() {
    final reminders = (_dashboard['serviceReminders'] as List<dynamic>?) ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Block 1: Appointments & Bay Schedule
        Container(
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
                      DataColumn(label: Text('Customer & Phone', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Vehicle Reg', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Service Type', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Bay / Lift', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Booking Status', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                    rows: _appointments.map((a) {
                      final status = (a['status'] ?? 'SCHEDULED').toString();
                      final phone = (a['phone'] ?? a['customerPhone'] ?? '').toString();
                      final bay = (a['assignedBay'] ?? a['bayNumber'] ?? 'Bay 1').toString();
                      return DataRow(
                        cells: [
                          DataCell(Text(_formatDate(a['scheduledAt']))),
                          DataCell(
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(a['customerName'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                if (phone.isNotEmpty)
                                  Text(phone, style: const TextStyle(fontSize: 11, color: Colors.black54)),
                              ],
                            ),
                          ),
                          DataCell(Text(a['registrationNo'] ?? '-', style: const TextStyle(fontWeight: FontWeight.w600))),
                          DataCell(Text(a['serviceType'] ?? '-')),
                          DataCell(Chip(label: Text(bay, style: const TextStyle(fontSize: 11)))),
                          DataCell(
                            DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: ['SCHEDULED', 'ARRIVED', 'COMPLETED', 'MISSED'].contains(status) ? status : 'SCHEDULED',
                                isDense: true,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: status == 'ARRIVED' || status == 'COMPLETED'
                                      ? Colors.green.shade800
                                      : status == 'MISSED'
                                          ? Colors.red.shade800
                                          : Colors.blue.shade800,
                                ),
                                items: const [
                                  DropdownMenuItem(value: 'SCHEDULED', child: Text('SCHEDULED')),
                                  DropdownMenuItem(value: 'ARRIVED', child: Text('ARRIVED \u2713')),
                                  DropdownMenuItem(value: 'COMPLETED', child: Text('COMPLETED')),
                                  DropdownMenuItem(value: 'MISSED', child: Text('MISSED / NO-SHOW')),
                                ],
                                onChanged: (newStatus) async {
                                  if (newStatus == null) return;
                                  await http.put(
                                    Uri.parse('$_baseUrl/appointments/${a['id']}'),
                                    headers: {'Content-Type': 'application/json'},
                                    body: json.encode({'status': newStatus}),
                                  );
                                  _refreshAllData();
                                },
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
                                    _showJobCardDialog(existingJob: {
                                      'customer': {
                                        'name': a['customerName'],
                                        'phone': a['customerPhone'],
                                      },
                                      'vehicle': {
                                        'registrationNo': a['registrationNo'],
                                        'make': a['vehicleMake'],
                                        'model': a['vehicleModel'],
                                      },
                                      'workRequested': a['serviceType'],
                                      'bayNumber': a['assignedBay'] ?? a['bayNumber'],
                                      'technician': a['technician'] ?? a['assignedTech'],
                                    });
                                  },
                                  icon: const Icon(Icons.assignment_add, size: 15, color: Color(0xFF2563EB)),
                                  label: const Text('Convert to Job Card', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                                if (phone.isNotEmpty)
                                  IconButton(
                                    tooltip: 'WhatsApp Appointment Reminder',
                                    icon: const Icon(Icons.chat, size: 16, color: Color(0xFF16A34A)),
                                    onPressed: () {
                                      _launchWhatsAppMessage(
                                        phone,
                                        'Hello ${a['customerName']}, reminder of your ${a['serviceType']} appointment for ${a['registrationNo']} on ${_formatDate(a['scheduledAt'])} ($bay).',
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
        ),
        const SizedBox(height: 24),
        // Block 2: Module 8 Automated Next-Service Interval & Mileage Reminders
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.notifications_active_outlined, color: Color(0xFFEA580C)),
                  SizedBox(width: 10),
                  Text('Upcoming Vehicle Service Reminders (Mileage & Interval Alerts)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              const Divider(height: 20),
              if (reminders.isEmpty)
                const Text('No vehicle service reminders yet.', style: TextStyle(color: Colors.grey))
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Vehicle Reg & Make', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Customer', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Last Recorded Mileage', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Next Service Mileage', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Next Service Date', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('1-Click Customer Notification', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                    rows: reminders.map((r) {
                      return DataRow(
                        cells: [
                          DataCell(Text('${r['registrationNo']} (${r['makeModel']})', style: const TextStyle(fontWeight: FontWeight.bold))),
                          DataCell(Text('${r['customerName']} (${r['phone'] ?? '-'})')),
                          DataCell(Text('${r['currentOdometer'] ?? 0} km')),
                          DataCell(Text('${r['nextServiceMileage'] ?? 5000} km', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFEA580C)))),
                          DataCell(Text(_formatDate(r['nextServiceDate']))),
                          DataCell(
                            ElevatedButton.icon(
                              onPressed: () {
                                _launchWhatsAppMessage(
                                  (r['phone'] ?? '').toString(),
                                  'Hello ${r['customerName']}, service reminder from ${_workshopSettings['name'] ?? 'AutoKe'}: your vehicle ${r['registrationNo']} (${r['makeModel']}) is due for its next periodic service at ${r['nextServiceMileage']} km (${_formatDate(r['nextServiceDate'])}). Reply to book a bay!',
                                );
                              },
                              icon: const Icon(Icons.chat_outlined, size: 15),
                              label: const Text('Send WhatsApp Reminder', style: TextStyle(fontSize: 12)),
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16A34A), foregroundColor: Colors.white),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
      ],
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

  // ==========================================
  // VEHICLES & FLEET MANAGEMENT SECTION
  // ==========================================
  Widget _buildVehiclesSection() {
    final filteredVehicles = _vehicles.where((v) {
      if (_vehicleCategoryFilter != 'ALL' && (v['category'] ?? 'PERSONAL') != _vehicleCategoryFilter) {
        return false;
      }
      if (_vehicleSearchQuery.isNotEmpty) {
        final q = _vehicleSearchQuery.toLowerCase();
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

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Vehicles & Fleets Management', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                  const SizedBox(height: 4),
                  Text('Complete vehicle lifecycle tracking for Personal cars, Government fleets, Schools, and Corporate organizations.',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                ],
              ),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _refreshAllData,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Refresh Fleets'),
                    style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1E293B)),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: () => _showJobCardDialog(),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New Vehicle & Job Card'),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 5 KPI Category Summary Cards
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _buildFleetKpiCard('Total Tracked Fleets', '${_vehicleCounts['all'] ?? _vehicles.length}', Icons.directions_car, const Color(0xFF1E3A8A), 'Active in workshop registry', 'ALL'),
              _buildFleetKpiCard('Personal Vehicles', '${_vehicleCounts['personal'] ?? 0}', Icons.person, const Color(0xFF059669), 'Private car owners', 'PERSONAL'),
              _buildFleetKpiCard('Government Fleets', '${_vehicleCounts['government'] ?? 0}', Icons.account_balance, const Color(0xFF1D4ED8), 'GK / CG / Ministries / Police', 'GOVERNMENT'),
              _buildFleetKpiCard('School Fleets', '${_vehicleCounts['school'] ?? 0}', Icons.school, const Color(0xFFD97706), 'Buses, vans & shuttles', 'SCHOOL'),
              _buildFleetKpiCard('Corporate & NGOs', '${_vehicleCounts['organization'] ?? 0}', Icons.business, const Color(0xFF7C3AED), 'Company & NGO logistics', 'ORGANIZATION'),
            ],
          ),
          const SizedBox(height: 24),

          // Category Filter Pills & Search Bar
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFleetFilterChip('All Fleets (${_vehicleCounts['all'] ?? _vehicles.length})', 'ALL'),
                      const SizedBox(width: 8),
                      _buildFleetFilterChip('🚗 Personal (${_vehicleCounts['personal'] ?? 0})', 'PERSONAL'),
                      const SizedBox(width: 8),
                      _buildFleetFilterChip('🏛️ Government (${_vehicleCounts['government'] ?? 0})', 'GOVERNMENT'),
                      const SizedBox(width: 8),
                      _buildFleetFilterChip('🏫 Schools (${_vehicleCounts['school'] ?? 0})', 'SCHOOL'),
                      const SizedBox(width: 8),
                      _buildFleetFilterChip('🏢 Organizations (${_vehicleCounts['organization'] ?? 0})', 'ORGANIZATION'),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 280,
                child: TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search, size: 18),
                    hintText: 'Search plate, model, driver...',
                    hintStyle: const TextStyle(fontSize: 13),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (val) => setState(() => _vehicleSearchQuery = val),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Data Table
          if (filteredVehicles.isEmpty)
            Container(
              padding: const EdgeInsets.all(40),
              alignment: Alignment.center,
              child: Column(
                children: [
                  Icon(Icons.directions_car_outlined, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text('No vehicles found for the selected category.', style: TextStyle(fontSize: 15, color: Colors.grey.shade600)),
                  const SizedBox(height: 6),
                  const Text('Vehicles are automatically registered when creating a receiving memo or job card.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                dataRowMaxHeight: 64,
                columns: const [
                  DataColumn(label: Text('Registration Plate', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Fleet Category', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Vehicle Specs', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Driver / Unit #', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Client / Organization', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Mileage & Usage', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Last Service & Visits', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Actions & Digital Passport', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: filteredVehicles.map((v) {
                  final cat = (v['category'] ?? 'PERSONAL').toString();
                  final cust = v['customer'] ?? {};
                  final visits = v['jobCardsCount'] ?? 0;
                  final regNo = v['registrationNo'] ?? '-';
                  final lastOdo = v['lastOdometer'] ?? 0;
                  final daily = v['avgDailyMileage'];

                  return DataRow(
                    cells: [
                      DataCell(
                        _buildPlatePill(regNo),
                      ),
                      DataCell(
                        _buildCategoryBadge(cat),
                      ),
                      DataCell(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('${v['make'] ?? ''} ${v['model'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                const SizedBox(width: 6),
                                _buildFuelBadge((v['fuelType'] ?? 'Petrol').toString()),
                              ],
                            ),
                            Text('${v['year'] ?? '-'} \u2022 ${(v['bodyType'] ?? 'sedan').toString().toUpperCase()}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                      DataCell(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if ((v['fleetUnitNumber'] ?? '').toString().isNotEmpty)
                              Text('Unit: ${v['fleetUnitNumber']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E3A8A))),
                            Text(v['assignedDriver'] != null && v['assignedDriver'].toString().isNotEmpty
                                ? v['assignedDriver']
                                : 'No driver assigned',
                                style: const TextStyle(fontSize: 12)),
                            if ((v['driverPhone'] ?? '').toString().isNotEmpty)
                              Text('${v['driverPhone']}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                      DataCell(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(cust['name'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                            Text(cust['phone'] ?? '-', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                      DataCell(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (lastOdo != null && lastOdo > 0)
                              Text('$lastOdo km', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12))
                            else
                              Text('Not Recorded', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: Colors.grey.shade500)),
                            if (lastOdo != null && lastOdo > 0 && visits > 1 && daily != null && daily > 0)
                              Text('~$daily km/day', style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade600))
                            else if (lastOdo != null && lastOdo > 0)
                              Text('1st Visit Baseline', style: TextStyle(fontSize: 10, color: Colors.blueGrey.shade400))
                            else
                              Text('Awaiting intake', style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
                          ],
                        ),
                      ),
                      DataCell(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(_formatDateShort(v['lastServiceDate']), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4)),
                              child: Text('$visits visits', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
                            ),
                          ],
                        ),
                      ),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () => _showVehicleHistoryDialog(v['id'].toString(), initialVehicle: Map<String, dynamic>.from(v)),
                              icon: const Icon(Icons.history_edu, size: 15),
                              label: const Text('Digital Passport', style: TextStyle(fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1E3A8A),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                            ),
                            const SizedBox(width: 6),
                            if ((v['driverPhone'] ?? cust['phone'] ?? '').toString().isNotEmpty)
                              IconButton(
                                tooltip: 'WhatsApp Fleet Service Update',
                                icon: const Icon(Icons.chat, size: 17, color: Color(0xFF16A34A)),
                                onPressed: () {
                                  final targetPhone = (v['driverPhone'] ?? cust['phone']).toString();
                                  final msg = 'Hello, this is a courtesy update from ${_workshopSettings['name'] ?? 'AutoKe'} regarding vehicle ${v['registrationNo']} (${v['make']} ${v['model']}). Current recorded odometer is $lastOdo km. Please feel free to reach out for bookings or questions.';
                                  _launchWhatsAppMessage(targetPhone, msg);
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

  Widget _buildFleetKpiCard(String title, String count, IconData icon, Color color, String subtext, String categoryKey) {
    final isSelected = _vehicleCategoryFilter == categoryKey;
    return InkWell(
      onTap: () => setState(() => _vehicleCategoryFilter = categoryKey),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? color : Colors.grey.shade200, width: isSelected ? 2 : 1),
          boxShadow: isSelected ? [BoxShadow(color: color.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 2))] : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                Icon(icon, color: color, size: 18),
              ],
            ),
            const SizedBox(height: 8),
            Text(count, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(subtext, style: TextStyle(fontSize: 11, color: Colors.grey.shade500), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _buildFleetFilterChip(String label, String key) {
    final isSelected = _vehicleCategoryFilter == key;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? Colors.white : Colors.black87)),
      selected: isSelected,
      selectedColor: const Color(0xFF1E3A8A),
      backgroundColor: Colors.grey.shade100,
      onSelected: (_) => setState(() => _vehicleCategoryFilter = key),
    );
  }

  Widget _buildPlatePill(String plate) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF0F172A), width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(color: const Color(0xFF2563EB), borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 6),
          Text(
            plate.toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 0.6, color: Color(0xFF0F172A)),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBadge(String cat) {
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
        label = 'SCHOOL FLEET';
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildFuelBadge(String fuelType) {
    final clean = fuelType.trim();
    Color bg = const Color(0xFFEFF6FF);
    Color fg = const Color(0xFF1D4ED8);
    String icon = '⛽';
    if (clean.toLowerCase() == 'diesel') {
      bg = const Color(0xFFFEF3C7);
      fg = const Color(0xFFB45309);
      icon = '🛢️';
    } else if (clean.toLowerCase() == 'hybrid') {
      bg = const Color(0xFFECFDF5);
      fg = const Color(0xFF047857);
      icon = '⚡';
    } else if (clean.toLowerCase() == 'electric') {
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
          Text(clean.toUpperCase(), style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: fg)),
        ],
      ),
    );
  }

  Future<void> _showVehicleHistoryDialog(String vehicleId, {Map<String, dynamic>? initialVehicle}) async {
    await showDialog(
      context: context,
      builder: (ctx) {
        return _VehiclePassportDialog(
          vehicleId: vehicleId,
          initialVehicle: initialVehicle,
          baseUrl: _baseUrl,
          workshopSettings: _workshopSettings,
          onLaunchWhatsApp: _launchWhatsAppMessage,
        );
      },
    );
  }

  void _showAddUserDialog() {
    final nameCtrl = TextEditingController();
    final usernameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final passCtrl = TextEditingController(text: 'password123');
    final commCtrl = TextEditingController(text: '15');
    String selectedRole = 'MECHANIC';
    bool isSaving = false;
    String? errorMsg;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFF1E3A8A).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.person_add, color: Color(0xFF1E3A8A)),
              ),
              const SizedBox(width: 12),
              const Text('Create New Workshop User / Staff', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Create an account so staff can log in using their User ID/Username or Email and Password.', style: TextStyle(color: Colors.grey, fontSize: 13)),
                  const SizedBox(height: 16),
                  if (errorMsg != null)
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.shade200)),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text(errorMsg!, style: TextStyle(color: Colors.red.shade900, fontSize: 13))),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Full Name *',
                            hintText: 'e.g. Alex Kimani',
                            prefixIcon: Icon(Icons.badge),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: usernameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'User ID / Username',
                            hintText: 'e.g. alex_tech',
                            prefixIcon: Icon(Icons.alternate_email),
                            border: OutlineInputBorder(),
                            helperText: 'Used to log into the app',
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
                          controller: emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email Address *',
                            hintText: 'e.g. alex@autocare.com',
                            prefixIcon: Icon(Icons.email),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: phoneCtrl,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Phone Number',
                            hintText: 'e.g. 0712345678',
                            prefixIcon: Icon(Icons.phone),
                            border: OutlineInputBorder(),
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
                          isExpanded: true,
                          value: selectedRole,
                          decoration: const InputDecoration(
                            labelText: 'Assigned Role *',
                            prefixIcon: Icon(Icons.security),
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'OWNER', child: Text('OWNER (Full Admin Control)', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'MANAGER', child: Text('WORKSHOP MANAGER', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'ADVISOR', child: Text('SERVICE ADVISOR (Reception & Estimates)', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'MECHANIC', child: Text('MECHANIC (Technician & Parts Req)', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'STOREKEEPER', child: Text('STOREKEEPER (Store & Requisitions)', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'INVENTORY_MANAGER', child: Text('INVENTORY MANAGER (Stock & Audits)', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'CASHIER', child: Text('CASHIER (Invoices & POS)', overflow: TextOverflow.ellipsis)),
                            DropdownMenuItem(value: 'ACCOUNTS', child: Text('ACCOUNTANT (Financials)', overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (v) => setDlgState(() => selectedRole = v ?? 'MECHANIC'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: passCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Initial Password * (min 6 chars)',
                            prefixIcon: Icon(Icons.lock),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: commCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Commission %',
                            suffixText: '%',
                            border: const OutlineInputBorder(),
                            enabled: selectedRole == 'MECHANIC',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              icon: isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check),
              label: const Text('Create User Account'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
              onPressed: isSaving ? null : () async {
                final name = nameCtrl.text.trim();
                final email = emailCtrl.text.trim();
                final username = usernameCtrl.text.trim();
                final phone = phoneCtrl.text.trim();
                final password = passCtrl.text.trim();
                final comm = double.tryParse(commCtrl.text.trim()) ?? 15.0;

                if (name.isEmpty) {
                  setDlgState(() => errorMsg = 'Please enter user full name.');
                  return;
                }
                if (email.isEmpty) {
                  setDlgState(() => errorMsg = 'Please enter user email address.');
                  return;
                }
                if (password.length < 6) {
                  setDlgState(() => errorMsg = 'Password must be at least 6 characters.');
                  return;
                }

                setDlgState(() {
                  isSaving = true;
                  errorMsg = null;
                });

                try {
                  final resp = await http.post(
                    Uri.parse('$_baseUrl/users'),
                    headers: AuthService.instance.authHeaders,
                    body: json.encode({
                      'name': name,
                      'email': email,
                      if (username.isNotEmpty) 'username': username,
                      if (phone.isNotEmpty) 'phone': phone,
                      'role': selectedRole,
                      'password': password,
                      'commissionRate': comm,
                    }),
                  );
                  if (resp.statusCode == 201 || resp.statusCode == 200) {
                    if (context.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: Colors.green,
                          content: Text('User account created for $name ($selectedRole)! They can now log in.'),
                        ),
                      );
                      _refreshAllData();
                    }
                  } else {
                    final err = json.decode(resp.body);
                    setDlgState(() {
                      isSaving = false;
                      errorMsg = err['error'] ?? 'Failed to create user.';
                    });
                  }
                } catch (e) {
                  setDlgState(() {
                    isSaving = false;
                    errorMsg = 'Error creating user: $e';
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showResetPasswordDialog(Map<String, dynamic> user) {
    final passCtrl = TextEditingController();
    bool isSaving = false;
    String? errorMsg;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.lock_reset, color: Colors.orange),
              const SizedBox(width: 10),
              Expanded(child: Text('Reset Password: ${user['name']}', overflow: TextOverflow.ellipsis)),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('User: ${user['name']} (${user['username'] ?? user['email']})', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Enter a new password for this user (minimum 6 characters).', style: TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 16),
                if (errorMsg != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(errorMsg!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                  ),
                TextField(
                  controller: passCtrl,
                  decoration: const InputDecoration(
                    labelText: 'New Password *',
                    prefixIcon: Icon(Icons.vpn_key),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800, foregroundColor: Colors.white),
              onPressed: isSaving ? null : () async {
                final newPass = passCtrl.text.trim();
                if (newPass.length < 6) {
                  setDlgState(() => errorMsg = 'Password must be at least 6 characters.');
                  return;
                }
                setDlgState(() {
                  isSaving = true;
                  errorMsg = null;
                });
                try {
                  final resp = await http.post(
                    Uri.parse('$_baseUrl/users/${user['id']}/reset-password'),
                    headers: AuthService.instance.authHeaders,
                    body: json.encode({'newPassword': newPass}),
                  );
                  if (resp.statusCode == 200) {
                    if (context.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: Colors.green,
                          content: Text('Password updated for ${user['name']}.'),
                        ),
                      );
                    }
                  } else {
                    final err = json.decode(resp.body);
                    setDlgState(() {
                      isSaving = false;
                      errorMsg = err['error'] ?? 'Failed to reset password.';
                    });
                  }
                } catch (e) {
                  setDlgState(() {
                    isSaving = false;
                    errorMsg = 'Error resetting password: $e';
                  });
                }
              },
              child: const Text('Set New Password'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleUserActive(Map<String, dynamic> user) async {
    final bool currentActive = user['isActive'] ?? true;
    final bool newActive = !currentActive;
    try {
      final resp = await http.put(
        Uri.parse('$_baseUrl/users/${user['id']}'),
        headers: AuthService.instance.authHeaders,
        body: json.encode({'isActive': newActive}),
      );
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: newActive ? Colors.green : Colors.orange,
            content: Text('${user['name']} has been ${newActive ? 'activated' : 'deactivated'}.'),
          ),
        );
        _refreshAllData();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Error updating user: $e')),
      );
    }
  }

  Widget _buildEmployeesSection() {
    final mechProd = (_dashboard['mechanicProductivity'] as List<dynamic>?) ?? [];
    final canManageUsers = _can('user:manage') || _activeUserRole == 'OWNER' || _activeUserRole == 'SUPER_ADMIN' || _activeUserRole == 'ADMIN';

    return StatefulBuilder(
      builder: (context, setEmpState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Workshop Staff & User Management', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(
                            'Create staff accounts with User IDs and passwords so each team member can log in with their specific role.',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                          ),
                        ],
                      ),
                      if (canManageUsers)
                        ElevatedButton.icon(
                          onPressed: _showAddUserDialog,
                          icon: const Icon(Icons.person_add),
                          label: const Text('Add New User / Staff'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                    ],
                  ),
                  const Divider(height: 32),
                  if (_employees.isEmpty)
                    const Padding(padding: EdgeInsets.all(24), child: Text('No users found in database.'))
                  else
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Staff Member', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('User ID / Username', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Email & Phone', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Assigned Role', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Commission / Pay', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                        ],
                        rows: _employees.map((e) {
                          final role = (e['role'] ?? 'MECHANIC').toString();
                          final isActive = e['isActive'] ?? true;
                          final username = (e['username'] ?? '').toString();
                          final email = (e['email'] ?? '').toString();
                          final phone = (e['phone'] ?? '').toString();
                          final name = (e['name'] ?? 'Staff').toString();
                          final comm = (e['commissionRate'] as num?)?.toDouble() ?? 15.0;

                          Color roleColor;
                          switch (role) {
                            case 'OWNER':
                            case 'SUPER_ADMIN':
                              roleColor = Colors.purple;
                              break;
                            case 'MANAGER':
                              roleColor = Colors.indigo;
                              break;
                            case 'STOREKEEPER':
                              roleColor = Colors.teal;
                              break;
                            case 'INVENTORY_MANAGER':
                              roleColor = Colors.cyan.shade800;
                              break;
                            case 'ADVISOR':
                              roleColor = Colors.blue.shade700;
                              break;
                            case 'CASHIER':
                              roleColor = Colors.green.shade700;
                              break;
                            default:
                              roleColor = Colors.orange.shade800;
                          }

                          return DataRow(
                            cells: [
                              DataCell(
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 14,
                                      backgroundColor: roleColor.withOpacity(0.15),
                                      child: Text(
                                        name.isNotEmpty ? name[0].toUpperCase() : 'U',
                                        style: TextStyle(color: roleColor, fontWeight: FontWeight.bold, fontSize: 11),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                              DataCell(
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: Text(
                                    username.isNotEmpty ? username : '-',
                                    style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600, fontSize: 12),
                                  ),
                                ),
                              ),
                              DataCell(
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(email, style: const TextStyle(fontSize: 12)),
                                    if (phone.isNotEmpty) Text(phone, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                  ],
                                ),
                              ),
                              DataCell(
                                Chip(
                                  backgroundColor: roleColor.withOpacity(0.1),
                                  label: Text(role, style: TextStyle(color: roleColor, fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                              ),
                              DataCell(Text(role == 'MECHANIC' ? '$comm% Labour' : 'Standard')),
                              DataCell(
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isActive ? Colors.green.shade50 : Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    isActive ? 'Active' : 'Inactive',
                                    style: TextStyle(
                                      color: isActive ? Colors.green.shade800 : Colors.red.shade800,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (canManageUsers) ...[
                                      IconButton(
                                        tooltip: 'Reset Password',
                                        icon: const Icon(Icons.lock_reset, color: Colors.orange, size: 20),
                                        onPressed: () => _showResetPasswordDialog(Map<String, dynamic>.from(e)),
                                      ),
                                      IconButton(
                                        tooltip: isActive ? 'Deactivate User' : 'Activate User',
                                        icon: Icon(
                                          isActive ? Icons.block : Icons.check_circle_outline,
                                          color: isActive ? Colors.red.shade400 : Colors.green,
                                          size: 20,
                                        ),
                                        onPressed: () => _toggleUserActive(Map<String, dynamic>.from(e)),
                                      ),
                                    ],
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
            ),
            const SizedBox(height: 24),
            // Module 7: Mechanic Labour Hours, Turnaround & Commission Ledger
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Mechanic Labour Hours, Efficiency & 15% Commission Tracker', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const Divider(height: 20),
                  if (mechProd.isEmpty)
                    const Text('No mechanic job assignments yet.', style: TextStyle(color: Colors.grey))
                  else
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Technician', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Total Jobs', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Completed', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Est. vs Actual Hours', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Labour Value (KSH)', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Commission (15%)', style: TextStyle(fontWeight: FontWeight.bold))),
                        ],
                        rows: mechProd.map((m) {
                          final estH = (m['estimatedHours'] as num?)?.toDouble() ?? 0.0;
                          final actH = (m['actualHours'] as num?)?.toDouble() ?? 0.0;
                          final labVal = (m['labourGenerated'] as num?)?.toDouble() ?? (estH * 1500);
                          final comm = (m['commissionEarned'] as num?)?.toDouble() ?? (labVal * 0.15);
                          return DataRow(
                            cells: [
                              DataCell(Text((m['technician'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.bold))),
                              DataCell(Text('${m['totalJobs'] ?? 0}')),
                              DataCell(Text('${m['completedJobs'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green))),
                              DataCell(Text('${estH.toStringAsFixed(1)}h est / ${actH.toStringAsFixed(1)}h actual')),
                              DataCell(Text('KSH ${labVal.toStringAsFixed(0)}')),
                              DataCell(Text('KSH ${comm.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1D4ED8)))),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Module 7: Role-Based Access & Permissions Matrix
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Workshop Role-Based Access Control (RBAC) Matrix', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Divider(height: 20),
                  Text('\u2022 Owner / Admin: Full access to Job Cards, Parts, Quotations, Invoices, Staff, Expenses, and Net Profit Reports.', style: TextStyle(fontSize: 13, height: 1.6)),
                  Text('\u2022 Service Advisor: Create Job Cards, 360\u00B0 Walk-Around, Quotations, Appointments, and Customer WhatsApp Updates.', style: TextStyle(fontSize: 13, height: 1.6)),
                  Text('\u2022 Workshop Manager: Assign Bays & Technicians, Approve QC Road-Tests, Monitor Turnaround & Overdue Jobs.', style: TextStyle(fontSize: 13, height: 1.6)),
                  Text('\u2022 Mechanic: View Assigned Job Cards, Log OBD-II Diagnostics, Record Actual Hours & Request Parts.', style: TextStyle(fontSize: 13, height: 1.6)),
                  Text('\u2022 Storekeeper: Manage Spare Parts Catalog, Suppliers, Reorder Alerts, and Stock Movement Ledger.', style: TextStyle(fontSize: 13, height: 1.6)),
                  Text('\u2022 Cashier / Accounts: Convert Approved Estimates to Invoices, Record M-Pesa / Deposits, Issue Receipts & Gate Passes.', style: TextStyle(fontSize: 13, height: 1.6)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ==========================================
  // STOREKEEPER & INVENTORY MANAGER OPERATIONS REPORTS
  // (Inventories, Issued Items, Spoiled Items, Fast-Moving Items)
  // ==========================================
  Widget _buildStorekeeperReportsSection() {
    final balances = (_inventorySummary['balances'] as List<dynamic>?) ?? [];
    final lowStockList = (_inventorySummary['lowStock'] as List<dynamic>?) ?? [];
    final partsByJob = (_inventorySummary['partsByJob'] as List<dynamic>?) ?? [];
    final consumablesByDept = (_inventorySummary['consumablesByDepartment'] as List<dynamic>?) ?? [];
    final toolsAssigned = (_inventorySummary['toolsAssigned'] as List<dynamic>?) ?? [];
    final overdueTools = (_inventorySummary['overdueTools'] as List<dynamic>?) ?? [];
    final lostDamagedAssets = (_inventorySummary['lostDamagedAssets'] as List<dynamic>?) ?? [];
    final movementTotals = (_inventorySummary['movementTotalsByType'] as Map<String, dynamic>?) ?? {};
    final totalIssuedUnits = movementTotals['ISSUE'] ?? 0;
    final pendingQC = (_inventorySummary['pendingInspections'] as num?)?.toInt() ?? 0;
    final valuation = _inventorySummary['valuation'] as Map<String, dynamic>?;

    final spoiledReturns = _inventoryReturns.where((r) {
      final k = (r['kind'] ?? '').toString().toUpperCase();
      final c = (r['condition'] ?? '').toString().toUpperCase();
      final s = (r['status'] ?? '').toString().toUpperCase();
      return k == 'DAMAGED' || k == 'LOST' || c == 'DAMAGED' || c == 'DEFECTIVE' || s == 'QUARANTINED' || s == 'WRITTEN_OFF';
    }).toList();

    // Filter balances
    final filteredBalances = balances.where((b) {
      if (_inventoryCategoryFilter != 'ALL' && b['category'] != _inventoryCategoryFilter) {
        return false;
      }
      if (_inventorySearchQuery.isNotEmpty) {
        final q = _inventorySearchQuery.toLowerCase();
        final name = (b['name'] ?? '').toString().toLowerCase();
        final code = (b['code'] ?? '').toString().toLowerCase();
        final loc = (b['location'] ?? '').toString().toLowerCase();
        if (!name.contains(q) && !code.contains(q) && !loc.contains(q)) return false;
      }
      return true;
    }).toList();

    final partsCount = balances.where((b) => b['category'] == 'SPARE_PART').length;
    final consumablesCount = balances.where((b) => b['category'] == 'CONSUMABLE').length;
    final toolsCount = balances.where((b) => b['category'] == 'TOOL_EQUIPMENT').length;
    final topParts = (_dashboard['topParts'] as List<dynamic>?) ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Header Banner
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.warehouse, color: Color(0xFF1D4ED8), size: 28),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text('Store & Inventory Operations Reports', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.blue.shade200),
                                ),
                                child: Text(_activeUserRole, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          const Text('Real-time tracking of workshop stock balances, issued parts, and damaged/spoiled items.', style: TextStyle(fontSize: 13, color: Colors.black54)),
                        ],
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _refreshAllData,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Refresh'),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Export Reports as CSV',
                        onSelected: (val) {
                          final exportUrl = '$_baseUrl/inventory/reports/export?report=$val&role=$_activeUserRole';
                          openExternalUrlImpl(exportUrl);
                        },
                        itemBuilder: (ctx) => [
                          const PopupMenuItem(value: 'balances', child: Text('Export Stock Balances (CSV)')),
                          const PopupMenuItem(value: 'lowStock', child: Text('Export Low Stock Alerts (CSV)')),
                          const PopupMenuItem(value: 'partsByJob', child: Text('Export Spare Parts Issued to Jobs (CSV)')),
                          const PopupMenuItem(value: 'consumables', child: Text('Export Consumables Issued (CSV)')),
                          const PopupMenuItem(value: 'toolsAssigned', child: Text('Export Tools & Equipment (CSV)')),
                          const PopupMenuItem(value: 'lostDamaged', child: Text('Export Spoiled & Damaged Items (CSV)')),
                          const PopupMenuItem(value: 'transactions', child: Text('Export Full Stock Ledger (CSV)')),
                        ],
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F4C81),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.download, size: 16, color: Colors.white),
                              SizedBox(width: 6),
                              Text('Export Report (CSV)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                              SizedBox(width: 4),
                              Icon(Icons.arrow_drop_down, size: 16, color: Colors.white),
                            ],
                          ),
                        ),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A8A), foregroundColor: Colors.white),
                        onPressed: () => setState(() => _activeSidebar = 'Inventory'),
                        icon: const Icon(Icons.tune, size: 16),
                        label: const Text('Inventory Hub'),
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(height: 28),
              // KPI Cards Row
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _pnlCard(
                    'Total Stock Items',
                    '${balances.length} items',
                    '$partsCount Parts \u2022 $consumablesCount Supplies \u2022 $toolsCount Tools',
                    Colors.blue.shade800,
                    Colors.blue.shade50,
                  ),
                  _pnlCard(
                    'Issued / Dispatched Items',
                    '$totalIssuedUnits units',
                    '${partsByJob.length} repair jobs \u2022 ${consumablesByDept.length} departments',
                    Colors.teal.shade800,
                    Colors.teal.shade50,
                  ),
                  _pnlCard(
                    'Low-Stock Alerts',
                    '${lowStockList.length} items',
                    lowStockList.isNotEmpty ? 'Requires reorder replenishment' : 'All stock levels healthy',
                    lowStockList.isNotEmpty ? Colors.orange.shade800 : Colors.green.shade800,
                    lowStockList.isNotEmpty ? Colors.orange.shade50 : Colors.green.shade50,
                  ),
                  _pnlCard(
                    'Spoiled / Damaged Items',
                    '${spoiledReturns.length + lostDamagedAssets.length} items',
                    '$pendingQC returns pending QC inspection',
                    (spoiledReturns.length + lostDamagedAssets.length) > 0 ? Colors.red.shade800 : Colors.teal.shade800,
                    (spoiledReturns.length + lostDamagedAssets.length) > 0 ? Colors.red.shade50 : Colors.teal.shade50,
                  ),
                ],
              ),
              if (valuation != null && _activeUserRole == 'INVENTORY_MANAGER') ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.indigo.shade100),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Text('Stock Valuation (Cost): KSH ${((valuation['total'] ?? 0) as num).toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo.shade900)),
                      Text('Parts: KSH ${((valuation['spareParts'] ?? 0) as num).toStringAsFixed(0)}', style: TextStyle(color: Colors.indigo.shade800)),
                      Text('Parts Retail: KSH ${((valuation['sparePartsAtRetail'] ?? 0) as num).toStringAsFixed(0)}', style: TextStyle(color: Colors.indigo.shade800)),
                      Text('Consumables: KSH ${((valuation['consumables'] ?? 0) as num).toStringAsFixed(0)}', style: TextStyle(color: Colors.indigo.shade800)),
                      Text('Tools & Assets: KSH ${((valuation['assets'] ?? 0) as num).toStringAsFixed(0)}', style: TextStyle(color: Colors.indigo.shade800)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),

        // 2. Sub-Navigation Tabs
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              _buildStoreReportTabItem('Inventories', 'Inventories & Balances (${balances.length})', Icons.inventory),
              const SizedBox(width: 8),
              _buildStoreReportTabItem('Issued Items', 'Issued Items & Dispatches (${partsByJob.length + consumablesByDept.length})', Icons.output),
              const SizedBox(width: 8),
              _buildStoreReportTabItem('Spoiled Items', 'Spoiled & Damaged Items (${spoiledReturns.length + lostDamagedAssets.length})', Icons.broken_image),
              const SizedBox(width: 8),
              _buildStoreReportTabItem('Fast-Moving', 'Fast-Moving & Top Items (${topParts.length})', Icons.trending_up),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 3. Tab Content Section
        if (_storeReportTab == 'Inventories')
          _buildStoreInventoriesTab(filteredBalances, lowStockList, balances.length, partsCount, consumablesCount, toolsCount)
        else if (_storeReportTab == 'Issued Items')
          _buildStoreIssuedItemsTab(partsByJob, consumablesByDept, toolsAssigned, overdueTools)
        else if (_storeReportTab == 'Spoiled Items')
          _buildStoreSpoiledItemsTab(spoiledReturns, lostDamagedAssets, pendingQC)
        else
          _buildStoreFastMovingTab(topParts),
      ],
    );
  }

  Widget _buildStoreReportTabItem(String key, String label, IconData icon) {
    final active = _storeReportTab == key;
    return InkWell(
      onTap: () => setState(() => _storeReportTab = key),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF0F4C81) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: active ? Colors.white : Colors.black87),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: active ? FontWeight.bold : FontWeight.w500,
                color: active ? Colors.white : Colors.black87,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 1: INVENTORIES & STOCK BALANCES
  // ---------------------------------------------------------------------------
  Widget _buildStoreInventoriesTab(
    List<dynamic> filteredBalances,
    List<dynamic> lowStockList,
    int totalCount,
    int partsCount,
    int consumablesCount,
    int toolsCount,
  ) {
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Current Inventories & Stock Balances (${filteredBalances.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text('All ($totalCount)'),
                    selected: _inventoryCategoryFilter == 'ALL',
                    onSelected: (_) => setState(() => _inventoryCategoryFilter = 'ALL'),
                  ),
                  ChoiceChip(
                    label: Text('Spare Parts ($partsCount)'),
                    selected: _inventoryCategoryFilter == 'SPARE_PART',
                    onSelected: (_) => setState(() => _inventoryCategoryFilter = 'SPARE_PART'),
                  ),
                  ChoiceChip(
                    label: Text('Consumables ($consumablesCount)'),
                    selected: _inventoryCategoryFilter == 'CONSUMABLE',
                    onSelected: (_) => setState(() => _inventoryCategoryFilter = 'CONSUMABLE'),
                  ),
                  ChoiceChip(
                    label: Text('Tools ($toolsCount)'),
                    selected: _inventoryCategoryFilter == 'TOOL_EQUIPMENT',
                    onSelected: (_) => setState(() => _inventoryCategoryFilter = 'TOOL_EQUIPMENT'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              hintText: 'Search by part number, SKU, item name, or location...',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onChanged: (val) => setState(() => _inventorySearchQuery = val),
          ),
          if (lowStockList.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange.shade900, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Reorder Recommendation Alert: ${lowStockList.length} item(s) are at or below reorder threshold. Replenishment recommended.',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade900, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const Divider(height: 24),
          if (filteredBalances.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('No inventory items match the current filter.', style: TextStyle(color: Colors.grey))),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  const DataColumn(label: Text('Code / SKU', style: TextStyle(fontWeight: FontWeight.bold))),
                  const DataColumn(label: Text('Item Name & Description', style: TextStyle(fontWeight: FontWeight.bold))),
                  const DataColumn(label: Text('Category', style: TextStyle(fontWeight: FontWeight.bold))),
                  const DataColumn(label: Text('Location / Bin', style: TextStyle(fontWeight: FontWeight.bold))),
                  const DataColumn(label: Text('On Hand', style: TextStyle(fontWeight: FontWeight.bold))),
                  const DataColumn(label: Text('In QC / Quarantine', style: TextStyle(fontWeight: FontWeight.bold))),
                  const DataColumn(label: Text('Reorder Level', style: TextStyle(fontWeight: FontWeight.bold))),
                  const DataColumn(label: Text('Stock Status', style: TextStyle(fontWeight: FontWeight.bold))),
                  if (_activeUserRole == 'INVENTORY_MANAGER')
                    const DataColumn(label: Text('Unit Cost', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: filteredBalances.map((b) {
                  final cat = (b['category'] ?? '').toString();
                  final onHand = (b['onHand'] as num?)?.toInt() ?? 0;
                  final reorder = (b['reorderLevel'] as num?)?.toInt() ?? 0;
                  final qc = (b['quarantined'] as num?)?.toInt() ?? 0;
                  final isLow = cat != 'TOOL_EQUIPMENT' && onHand <= reorder;
                  final isOut = onHand == 0;

                  Color catBg;
                  Color catFg;
                  String catLabel;
                  if (cat == 'TOOL_EQUIPMENT') {
                    catBg = Colors.purple.shade50; catFg = Colors.purple.shade800; catLabel = 'TOOL';
                  } else if (cat == 'CONSUMABLE') {
                    catBg = Colors.teal.shade50; catFg = Colors.teal.shade800; catLabel = 'SUPPLY';
                  } else {
                    catBg = Colors.blue.shade50; catFg = Colors.blue.shade800; catLabel = 'PART';
                  }

                  return DataRow(
                    cells: [
                      DataCell(Text(b['code'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text(b['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600))),
                      DataCell(Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: catBg, borderRadius: BorderRadius.circular(4)),
                        child: Text(catLabel, style: TextStyle(color: catFg, fontWeight: FontWeight.bold, fontSize: 11)),
                      )),
                      DataCell(Text(b['location'] ?? 'Main Store')),
                      DataCell(Text(
                        '$onHand units',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isOut ? Colors.red : (isLow ? Colors.orange.shade900 : Colors.green.shade800),
                        ),
                      )),
                      DataCell(Text(qc > 0 ? '$qc units' : '-', style: TextStyle(color: qc > 0 ? Colors.red : Colors.grey))),
                      DataCell(Text('$reorder units')),
                      DataCell(Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isOut ? Colors.red.shade50 : (isLow ? Colors.orange.shade50 : Colors.green.shade50),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isOut ? 'OUT OF STOCK' : (isLow ? 'LOW STOCK' : 'IN STOCK'),
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: isOut ? Colors.red.shade800 : (isLow ? Colors.orange.shade900 : Colors.green.shade800),
                          ),
                        ),
                      )),
                      if (_activeUserRole == 'INVENTORY_MANAGER')
                        DataCell(Text('KSH ${((b['unitCost'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}')),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 2: ISSUED ITEMS & DISPATCHES
  // ---------------------------------------------------------------------------
  Widget _buildStoreIssuedItemsTab(
    List<dynamic> partsByJob,
    List<dynamic> consumablesByDept,
    List<dynamic> toolsAssigned,
    List<dynamic> overdueTools,
  ) {
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Item Issuance & Operational Dispatches Report', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text('Parts Issued to Jobs (${partsByJob.length})'),
                    selected: _issuedSubFilter == 'PARTS_JOB',
                    onSelected: (_) => setState(() => _issuedSubFilter = 'PARTS_JOB'),
                  ),
                  ChoiceChip(
                    label: Text('Consumables & Personal Issues (${consumablesByDept.length})'),
                    selected: _issuedSubFilter == 'CONSUMABLES_DEPT',
                    onSelected: (_) => setState(() => _issuedSubFilter = 'CONSUMABLES_DEPT'),
                  ),
                  ChoiceChip(
                    label: Text('Tools in Field (${toolsAssigned.length})'),
                    selected: _issuedSubFilter == 'TOOLS_FIELD',
                    onSelected: (_) => setState(() => _issuedSubFilter = 'TOOLS_FIELD'),
                  ),
                ],
              ),
            ],
          ),
          const Divider(height: 24),

          if (_issuedSubFilter == 'PARTS_JOB') ...[
            if (partsByJob.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No spare parts have been issued to job cards yet.', style: TextStyle(color: Colors.grey))),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    const DataColumn(label: Text('Job Card Ref', style: TextStyle(fontWeight: FontWeight.bold))),
                    const DataColumn(label: Text('Part Description', style: TextStyle(fontWeight: FontWeight.bold))),
                    const DataColumn(label: Text('Net Qty Issued', style: TextStyle(fontWeight: FontWeight.bold))),
                    if (_activeUserRole == 'INVENTORY_MANAGER')
                      const DataColumn(label: Text('Total Cost', style: TextStyle(fontWeight: FontWeight.bold))),
                    const DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                  rows: partsByJob.map((p) {
                    final jc = (p['jobCardId'] ?? '').toString();
                    final shortJc = jc.length >= 8 ? jc.substring(0, 8).toUpperCase() : jc;
                    final q = (p['netQty'] as num?)?.toInt() ?? 0;
                    return DataRow(
                      cells: [
                        DataCell(Text('JC-$shortJc', style: const TextStyle(fontWeight: FontWeight.bold))),
                        DataCell(Text(p['item'] ?? 'Part', style: const TextStyle(fontWeight: FontWeight.w600))),
                        DataCell(Text('$q units', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
                        if (_activeUserRole == 'INVENTORY_MANAGER')
                          DataCell(Text('KSH ${((p['cost'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}')),
                        const DataCell(Chip(label: Text('DISPATCHED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)))),
                      ],
                    );
                  }).toList(),
                ),
              ),
          ] else if (_issuedSubFilter == 'CONSUMABLES_DEPT') ...[
            if (consumablesByDept.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No internal consumables have been issued to departments yet.', style: TextStyle(color: Colors.grey))),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    const DataColumn(label: Text('Recipient (Dept / Person)', style: TextStyle(fontWeight: FontWeight.bold))),
                    const DataColumn(label: Text('Consumable Item', style: TextStyle(fontWeight: FontWeight.bold))),
                    const DataColumn(label: Text('Quantity Issued', style: TextStyle(fontWeight: FontWeight.bold))),
                    if (_activeUserRole == 'INVENTORY_MANAGER')
                      const DataColumn(label: Text('Cost Allocated', style: TextStyle(fontWeight: FontWeight.bold))),
                    const DataColumn(label: Text('Issuance Type', style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                  rows: consumablesByDept.map((c) {
                    final q = (c['quantity'] as num?)?.toInt() ?? 0;
                    final target = (c['department'] ?? 'Workshop').toString();
                    final isIndividual = target.toLowerCase().startsWith('individual');
                    return DataRow(
                      cells: [
                        DataCell(Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(isIndividual ? Icons.person : Icons.business, size: 16, color: isIndividual ? Colors.purple : Colors.teal),
                            const SizedBox(width: 6),
                            Text(target, style: TextStyle(fontWeight: FontWeight.bold, color: isIndividual ? Colors.purple.shade800 : Colors.black87)),
                          ],
                        )),
                        DataCell(Text(c['item'] ?? 'Consumable', style: const TextStyle(fontWeight: FontWeight.w600))),
                        DataCell(Text('$q units', style: TextStyle(fontWeight: FontWeight.bold, color: isIndividual ? Colors.purple : Colors.teal))),
                        if (_activeUserRole == 'INVENTORY_MANAGER')
                          DataCell(Text('KSH ${((c['cost'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}')),
                        DataCell(Chip(
                          backgroundColor: isIndividual ? Colors.purple.shade50 : Colors.teal.shade50,
                          label: Text(
                            isIndividual ? 'PERSONAL ISSUE' : 'DEPARTMENT USAGE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isIndividual ? Colors.purple.shade900 : Colors.teal.shade900,
                            ),
                          ),
                        )),
                      ],
                    );
                  }).toList(),
                ),
              ),
          ] else ...[
            if (toolsAssigned.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('All workshop tools are currently in the store (none checked out).', style: TextStyle(color: Colors.grey))),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Asset #', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Tool Name', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Assigned Technician', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Bay / Location', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Checked Out At', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Expected Return', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                  rows: toolsAssigned.map((t) {
                    final isOverdue = overdueTools.any((o) => o['id'] == t['id']);
                    return DataRow(
                      cells: [
                        DataCell(Text(t['assetNumber'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold))),
                        DataCell(Text(t['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600))),
                        DataCell(Text(t['assignedTo'] ?? 'Assigned')),
                        DataCell(Text(t['location'] ?? 'Workshop')),
                        DataCell(Text(_formatDate(t['checkedOutAt']))),
                        DataCell(Text(_formatDate(t['expectedReturnAt']))),
                        DataCell(Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isOverdue ? Colors.red.shade50 : Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isOverdue ? 'OVERDUE' : 'CHECKED OUT',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: isOverdue ? Colors.red.shade800 : Colors.blue.shade800,
                            ),
                          ),
                        )),
                      ],
                    );
                  }).toList(),
                ),
              ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 3: SPOILED, DAMAGED & DEFECTIVE ITEMS
  // ---------------------------------------------------------------------------
  Widget _buildStoreSpoiledItemsTab(List<dynamic> spoiledReturns, List<dynamic> lostDamagedAssets, int pendingQC) {
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Spoiled, Damaged & Defective Items (Returns & QC)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F4C81), foregroundColor: Colors.white),
                onPressed: () => setState(() => _activeSidebar = 'Inventory'),
                icon: const Icon(Icons.fact_check, size: 16),
                label: const Text('Open QC Inspection in Hub'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Defective components removed from customer vehicles, damaged returns, broken workshop tools, and items held in QC quarantine.',
            style: TextStyle(fontSize: 13, color: Colors.black54),
          ),
          const Divider(height: 24),

          if (spoiledReturns.isEmpty && lostDamagedAssets.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('Zero spoiled or damaged items recorded! All returns and tools are in good condition.', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              ),
            )
          else ...[
            if (spoiledReturns.isNotEmpty) ...[
              const Text('Damaged / Defective Returns Log:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Return Ref', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Item Name', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Category', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Condition', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('QC Status', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Reported By', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Damage / Defect Notes', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Date', style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                  rows: spoiledReturns.map((r) {
                    final status = (r['status'] ?? 'PENDING_INSPECTION').toString().toUpperCase();
                    final cond = (r['condition'] ?? 'DAMAGED').toString().toUpperCase();
                    Color statusBg; Color statusFg;
                    if (status == 'WRITTEN_OFF') {
                      statusBg = Colors.red.shade50; statusFg = Colors.red.shade800;
                    } else if (status == 'QUARANTINED') {
                      statusBg = Colors.orange.shade50; statusFg = Colors.orange.shade800;
                    } else {
                      statusBg = Colors.amber.shade50; statusFg = Colors.amber.shade900;
                    }

                    return DataRow(
                      cells: [
                        DataCell(Text(r['reference'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold))),
                        DataCell(Text(r['itemName'] ?? 'Item', style: const TextStyle(fontWeight: FontWeight.w600))),
                        DataCell(Text(r['category'] ?? 'SPARE_PART')),
                        DataCell(Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(4)),
                          child: Text(cond, style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.bold, fontSize: 11)),
                        )),
                        DataCell(Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(6)),
                          child: Text(status.replaceAll('_', ' '), style: TextStyle(color: statusFg, fontWeight: FontWeight.bold, fontSize: 10.5)),
                        )),
                        DataCell(Text(r['returnedBy'] ?? 'Technician')),
                        DataCell(Text(r['notes'] ?? r['reason'] ?? '-', style: const TextStyle(fontStyle: FontStyle.italic))),
                        DataCell(Text(_formatDate(r['createdAt']))),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],

            if (lostDamagedAssets.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text('Damaged or Lost Workshop Equipment:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    const DataColumn(label: Text('Asset #', style: TextStyle(fontWeight: FontWeight.bold))),
                    const DataColumn(label: Text('Tool Name', style: TextStyle(fontWeight: FontWeight.bold))),
                    const DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                    if (_activeUserRole == 'INVENTORY_MANAGER')
                      const DataColumn(label: Text('Cost Impact', style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                  rows: lostDamagedAssets.map((t) {
                    final status = (t['status'] ?? '').toString();
                    return DataRow(
                      cells: [
                        DataCell(Text(t['assetNumber'] ?? '-', style: const TextStyle(fontWeight: FontWeight.bold))),
                        DataCell(Text(t['name'] ?? '')),
                        DataCell(Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(4)),
                          child: Text(status, style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.bold, fontSize: 11)),
                        )),
                        if (_activeUserRole == 'INVENTORY_MANAGER')
                          DataCell(Text('KSH ${((t['cost'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}')),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 4: FAST-MOVING & TOP ITEMS
  // ---------------------------------------------------------------------------
  Widget _buildStoreFastMovingTab(List<dynamic> topParts) {
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
          const Text('Fast-Moving & High-Turnover Spare Parts', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Top items frequently requested and billed on repair jobs to guide warehouse restocking.', style: TextStyle(fontSize: 13, color: Colors.black54)),
          const Divider(height: 24),
          if (topParts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('No part issuance history recorded yet.', style: TextStyle(color: Colors.grey))),
            )
          else
            ...topParts.map((p) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFEFF6FF),
                    child: Icon(Icons.bolt, size: 18, color: Color(0xFF1D4ED8)),
                  ),
                  title: Text(p['description'] ?? 'Item', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('Total Units Dispatched: ${p['quantityUsed'] ?? 0} units'),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${p['quantityUsed'] ?? 0} sold',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade800, fontSize: 12),
                    ),
                  ),
                )),
        ],
      ),
    );
  }

  Widget _buildReportsSection() {
    if (_activeUserRole == 'STOREKEEPER' || _activeUserRole == 'INVENTORY_MANAGER') {
      return _buildStorekeeperReportsSection();
    }
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
    final topVehicles = (_dashboard['topVehicles'] as List<dynamic>?) ?? [];
    final topParts = (_dashboard['topParts'] as List<dynamic>?) ?? [];
    final debtorInvoices = _invoices.where((inv) => inv['paymentStatus'] != 'PAID').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Top Financial P&L Cards
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
                  _pnlCard('Outstanding Debtors', 'KSH ${outstanding.toStringAsFixed(0)}', '${debtorInvoices.length} Unpaid / Partial Invoices', Colors.purple.shade800, Colors.purple.shade50),
                ],
              ),
              const SizedBox(height: 24),
              _summaryRow('Labour Charges Revenue (Estimates & Repairs)', 'KSH ${labourRev.toStringAsFixed(2)}'),
              _summaryRow('Spare Parts Sales Revenue', 'KSH ${partsRev.toStringAsFixed(2)}'),
              _summaryRow('Inventory Stock Valuation (At Buying Cost)', 'KSH ${stockValCost.toStringAsFixed(2)}'),
              _summaryRow('Inventory Stock Valuation (At Retail Selling Price)', 'KSH ${stockValRetail.toStringAsFixed(2)}'),
              _summaryRow('Projected Inventory Gross Margin', 'KSH ${(stockValRetail - stockValCost).toStringAsFixed(2)}'),
              _summaryRow('Today / This Week / This Month Jobs', '${_dashboard['todayJobsCount'] ?? 0} Today \u2022 ${_dashboard['weekJobsCount'] ?? 0} Week \u2022 ${_dashboard['monthJobsCount'] ?? 0} Month'),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // 2. Customer Debtors & Outstanding Balances Table
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Customer Debtors & Unpaid / Partial Invoices (${debtorInvoices.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Divider(height: 20),
              if (debtorInvoices.isEmpty)
                const Text('All issued invoices are settled in full. Zero outstanding debtor balances!', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600))
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Invoice #', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Customer & Phone', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Vehicle Reg', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Total Billed', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Paid', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Balance Due', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Debtor Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                    rows: debtorInvoices.map((inv) {
                      final est = inv['estimate'] ?? {};
                      final job = est['jobCard'] ?? {};
                      final cust = job['customer']?['name'] ?? 'Customer';
                      final phone = job['customer']?['phone']?.toString() ?? '';
                      final reg = job['vehicle']?['registrationNo'] ?? '-';
                      final total = (est['total'] as num?)?.toDouble() ?? 0.0;
                      final paid = (inv['amountPaid'] as num?)?.toDouble() ?? 0.0;
                      final bal = (inv['balanceDue'] as num?)?.toDouble() ?? (total - paid).clamp(0.0, total);
                      return DataRow(
                        cells: [
                          DataCell(Text('INV-${inv['id'].toString().substring(0, 6).toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.bold))),
                          DataCell(Text('$cust ($phone)')),
                          DataCell(Text(reg)),
                          DataCell(Text('KSH ${total.toStringAsFixed(0)}')),
                          DataCell(Text('KSH ${paid.toStringAsFixed(0)}', style: const TextStyle(color: Colors.green))),
                          DataCell(Text('KSH ${bal.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red))),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () => _showRecordPaymentDialog(Map<String, dynamic>.from(inv)),
                                  icon: const Icon(Icons.payments_outlined, size: 14),
                                  label: const Text('Collect Balance', style: TextStyle(fontSize: 12)),
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
                                ),
                                const SizedBox(width: 6),
                                IconButton(
                                  tooltip: 'Send WhatsApp Balance Reminder',
                                  icon: const Icon(Icons.chat_outlined, color: Colors.green, size: 18),
                                  onPressed: () {
                                    _launchWhatsAppMessage(
                                      phone,
                                      'Hello $cust, polite reminder from ${_workshopSettings['name'] ?? 'AutoKe'} regarding outstanding balance of KSH ${bal.toStringAsFixed(0)} on Invoice INV-${inv['id'].toString().substring(0, 6).toUpperCase()} for vehicle $reg.',
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
        ),
        const SizedBox(height: 24),
        // 3. Top Serviced Vehicles & Most Used Spare Parts
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Top Serviced Vehicles', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const Divider(height: 20),
                    if (topVehicles.isEmpty)
                      const Text('No vehicle service records yet.', style: TextStyle(color: Colors.grey))
                    else
                      ...topVehicles.map((v) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const CircleAvatar(backgroundColor: Color(0xFFEFF6FF), child: Icon(Icons.directions_car, size: 16, color: Color(0xFF1D4ED8))),
                            title: Text('${v['registrationNo']} \u2014 ${v['makeModel']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('Owner: ${v['customerName']} \u2022 Last: ${v['lastService']}'),
                            trailing: Chip(label: Text('${v['jobsCount']} Visits', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                          )),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Most Used Spare Parts & Items', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const Divider(height: 20),
                    if (topParts.isEmpty)
                      const Text('No parts billed on estimates yet.', style: TextStyle(color: Colors.grey))
                    else
                      ...topParts.map((p) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const CircleAvatar(backgroundColor: Color(0xFFFEF3C7), child: Icon(Icons.build_circle_outlined, size: 16, color: Color(0xFFB45309))),
                            title: Text('${p['description']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text('Total Qty Billed: ${p['quantityUsed']} units'),
                            trailing: Text('KSH ${((p['revenueGenerated'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
                          )),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        // 4. Mechanic Productivity, Turnaround & Commission Table
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Mechanic Productivity, Turnaround & Commission Performance', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Divider(height: 20),
              if (mechProd.isEmpty)
                const Text('No technicians assigned to jobs yet.', style: TextStyle(color: Colors.grey))
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Technician', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Assigned Jobs', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Completed Jobs', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Est. vs Actual Hours', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Commission Earned (15%)', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                    rows: mechProd.map((m) {
                      final estH = (m['estimatedHours'] ?? m['totalEstimatedHours'] ?? 0);
                      final actH = (m['actualHours'] ?? 0);
                      final comm = (m['commissionEarned'] as num?)?.toDouble() ?? 0.0;
                      return DataRow(
                        cells: [
                          DataCell(Text((m['technician'] ?? m['name'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.bold))),
                          DataCell(Text('${m['totalJobs'] ?? m['assignedJobs'] ?? 0}')),
                          DataCell(Text('${m['completedJobs'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green))),
                          DataCell(Text('$estH hrs est / $actH hrs actual')),
                          DataCell(Text('KSH ${comm.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1D4ED8)))),
                        ],
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        // 5. Workshop Operating Expenses Ledger
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
                        '${part['partNumber'] ?? 'Part'} \u2022 ${part['description'] ?? ''} (${isOut ? '-' : '+'}${m['quantity'] ?? 0})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      subtitle: Text('Reason: ${m['reason'] ?? '-'} \u2022 Date: ${_formatDate(m['createdAt'])}'),
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
        if (_activeUserRole == 'STOREKEEPER' || _activeUserRole == 'INVENTORY_MANAGER')
          _rightPanelBox(
            'Store & Inventory Summary',
            Column(
              children: [
                _summaryRow('Catalog Items', '${((_inventorySummary['balances'] as List<dynamic>?)?.length ?? _parts.length)} Total'),
                _summaryRow('Dispatched / Issued', '${(_inventorySummary['movementTotalsByType'] as Map<String, dynamic>?)?['ISSUE'] ?? 0} Units'),
                _summaryRow('Low Stock Alerts', '${((_inventorySummary['lowStock'] as List<dynamic>?)?.length ?? (_dashboard['lowStockCount'] ?? 0))} Items'),
                _summaryRow('Damaged / Spoiled Returns', '${_inventoryReturns.where((r) => r['kind'] == 'DAMAGED' || r['condition'] == 'DAMAGED' || r['status'] == 'QUARANTINED' || r['status'] == 'WRITTEN_OFF').length} Items'),
                _summaryRow('Pending QC Inspection', '${_inventorySummary['pendingInspections'] ?? 0} Returns'),
                _summaryRow('Tools Checked Out', '${((_inventorySummary['toolsAssigned'] as List<dynamic>?)?.length ?? 0)} Active'),
                _summaryRow('Overdue Equipment', '${((_inventorySummary['overdueTools'] as List<dynamic>?)?.length ?? 0)} Tools'),
                if (_activeUserRole == 'INVENTORY_MANAGER' && _inventorySummary['valuation'] != null)
                  _summaryRow('Stock Valuation (Cost)', 'KSH ${((_inventorySummary['valuation']?['total'] ?? 0) as num).toStringAsFixed(0)}'),
              ],
            ),
          )
        else
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
          Expanded(
            child: Text(label, style: const TextStyle(color: Colors.black87), overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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

// ==========================================
// DIGITAL VEHICLE SERVICE PASSPORT DIALOG
// ==========================================
class _VehiclePassportDialog extends StatefulWidget {
  final String vehicleId;
  final Map<String, dynamic>? initialVehicle;
  final String baseUrl;
  final Map<String, dynamic> workshopSettings;
  final void Function(String phone, String text) onLaunchWhatsApp;

  const _VehiclePassportDialog({
    Key? key,
    required this.vehicleId,
    this.initialVehicle,
    required this.baseUrl,
    required this.workshopSettings,
    required this.onLaunchWhatsApp,
  }) : super(key: key);

  @override
  State<_VehiclePassportDialog> createState() => _VehiclePassportDialogState();
}

class _VehiclePassportDialogState extends State<_VehiclePassportDialog> {
  bool _isLoading = true;
  Map<String, dynamic>? _historyData;
  String? _error;
  int _activeTab = 0; // 0: Timeline, 1: Parts, 2: Diagnostics, 3: Mileage

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    try {
      final res = await http.get(
        Uri.parse('${widget.baseUrl}/vehicles/${widget.vehicleId}/history'),
        headers: AuthService.instance.authHeaders,
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

  void _sendWhatsAppPassport() {
    final v = _historyData?['vehicle'] ?? widget.initialVehicle ?? {};
    final c = _historyData?['customer'] ?? v['customer'] ?? {};
    final s = _historyData?['summary'] ?? {};
    final targetPhone = (v['driverPhone'] ?? c['phone'] ?? '').toString();

    final msg = '''*DIGITAL VEHICLE SERVICE PASSPORT*
Registration: ${v['registrationNo'] ?? '-'}
Vehicle: ${v['make'] ?? ''} ${v['model'] ?? ''} (${(v['bodyType'] ?? 'sedan').toString().toUpperCase()})
Category: ${v['category'] ?? 'PERSONAL'}
Owner / Client: ${c['name'] ?? '-'}
${v['assignedDriver'] != null && v['assignedDriver'].toString().isNotEmpty ? 'Assigned Driver: ${v['assignedDriver']}\n' : ''}Recorded Odometer: ${s['currentOdometer'] ?? v['lastOdometer'] ?? '-'} km
Total Workshop Visits: ${s['totalVisits'] ?? 0}
Total Lifetime Spend: ${_formatKes(s['totalSpend'] ?? 0)}
Last Service Date: ${_formatDateShort(s['lastServiceDate'] ?? v['lastServiceDate'])}
Next Service Due: ${s['nextServiceMileage'] != null ? '${s['nextServiceMileage']} km' : 'TBA'}

-- Verified by ${widget.workshopSettings['name'] ?? 'AutoKe Auto Workshop'}''';

    widget.onLaunchWhatsApp(targetPhone, msg);
  }

  @override
  Widget build(BuildContext context) {
    final v = _historyData?['vehicle'] ?? widget.initialVehicle ?? {};
    final c = _historyData?['customer'] ?? v['customer'] ?? {};
    final s = _historyData?['summary'] ?? {};
    final jobCards = (_historyData?['jobCards'] as List<dynamic>?) ?? [];
    final parts = (_historyData?['partsReplaced'] as List<dynamic>?) ?? [];
    final diagnostics = (_historyData?['diagnosticHistory'] as List<dynamic>?) ?? [];
    final mileageTimeline = (_historyData?['odometerTimeline'] as List<dynamic>?) ?? [];

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF0F172A), width: 1.5),
                    ),
                    child: Row(
                      children: [
                        Container(width: 4, height: 16, decoration: BoxDecoration(color: const Color(0xFF2563EB), borderRadius: BorderRadius.circular(2))),
                        const SizedBox(width: 8),
                        Text(
                          (v['registrationNo'] ?? 'VEHICLE').toString().toUpperCase(),
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.8, color: Color(0xFF0F172A)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('${v['make'] ?? ''} ${v['model'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: Colors.blueGrey.shade50, borderRadius: BorderRadius.circular(4)),
                    child: Text('${(v['bodyType'] ?? 'sedan').toString().toUpperCase()}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.blueGrey.shade800)),
                  ),
                ],
              ),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('Client: ${c['name'] ?? '-'}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
              if ((v['fleetUnitNumber'] ?? '').toString().isNotEmpty) ...[
                const Text(' \u2022 '),
                Text('Unit: ${v['fleetUnitNumber']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
              ],
              if ((v['assignedDriver'] ?? '').toString().isNotEmpty) ...[
                const Text(' \u2022 '),
                Text('Driver: ${v['assignedDriver']} (${v['driverPhone'] ?? '-'})', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              ],
            ],
          ),
        ],
      ),
      content: SizedBox(
        width: 800,
        height: 540,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // KPI Strip
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildStatItem('Total Visits', '${s['totalVisits'] ?? jobCards.length}', Icons.build_circle, const Color(0xFF2563EB)),
                            _buildStatItem('Total Spend', _formatKes(s['totalSpend'] ?? 0), Icons.receipt_long, const Color(0xFF16A34A)),
                            _buildStatItem('Recorded Odo', '${s['currentOdometer'] ?? v['lastOdometer'] ?? 0} km', Icons.speed, const Color(0xFFD97706)),
                            _buildStatItem('Replaced Parts', '${parts.length}', Icons.settings, const Color(0xFF7C3AED)),
                            _buildStatItem('Next Due', s['nextServiceMileage'] != null ? '${s['nextServiceMileage']} km' : 'TBA', Icons.event_available, const Color(0xFF475569)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Tabs Selector
                      Row(
                        children: [
                          _buildTabBtn('📋 Service History (${jobCards.length})', 0),
                          const SizedBox(width: 8),
                          _buildTabBtn('⚙️ Replaced Parts (${parts.length})', 1),
                          const SizedBox(width: 8),
                          _buildTabBtn('🔍 Diagnostics & OBD (${diagnostics.length})', 2),
                          const SizedBox(width: 8),
                          _buildTabBtn('📈 Mileage Log (${mileageTimeline.length})', 3),
                        ],
                      ),
                      const Divider(height: 16),

                      // Tab Content
                      Expanded(
                        child: _activeTab == 0
                            ? _buildJobCardsTimeline(jobCards)
                            : _activeTab == 1
                                ? _buildPartsLedger(parts)
                                : _activeTab == 2
                                    ? _buildDiagnosticsLog(diagnostics)
                                    : _buildMileageProgression(mileageTimeline),
                      ),
                    ],
                  ),
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: _sendWhatsAppPassport,
          icon: const Icon(Icons.chat, size: 16, color: Color(0xFF16A34A)),
          label: const Text('WhatsApp Fleet Report', style: TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.bold)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B), foregroundColor: Colors.white),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
          ],
        ),
        const SizedBox(height: 3),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _buildTabBtn(String title, int index) {
    final isSelected = _activeTab == index;
    return InkWell(
      onTap: () => setState(() => _activeTab = index),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1E3A8A) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          title,
          style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.w500, color: isSelected ? Colors.white : Colors.black87),
        ),
      ),
    );
  }

  Widget _buildJobCardsTimeline(List<dynamic> jobs) {
    if (jobs.isEmpty) {
      return const Center(child: Text('No service visits recorded for this vehicle yet.', style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      itemCount: jobs.length,
      itemBuilder: (context, i) {
        final j = jobs[i];
        final ests = (j['estimates'] as List<dynamic>?) ?? [];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade200)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: const Color(0xFFDBEAFE),
                  child: Text('${jobs.length - i}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E40AF), fontSize: 13)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${j['jobNumber'] ?? 'JC-'} \u2022 ${j['workRequested'] ?? 'General Service'}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4)),
                            child: Text(j['status'] ?? 'IN_PROGRESS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('Tech: ${j['technician'] ?? 'Unassigned'}  \u2022  Bay: ${j['bayNumber'] ?? 'Bay 1'}  \u2022  Odometer: ${j['odometer'] ?? '-'} km',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                      Text('Service Date: ${_formatDateShort(j['createdAt'])}  \u2022  Invoices / Estimates: ${ests.length}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPartsLedger(List<dynamic> parts) {
    if (parts.isEmpty) {
      return const Center(child: Text('No replaced parts recorded for this vehicle yet.', style: TextStyle(color: Colors.grey)));
    }
    return SingleChildScrollView(
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
        dataRowMaxHeight: 48,
        columns: const [
          DataColumn(label: Text('Part Description', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
          DataColumn(label: Text('Qty', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
          DataColumn(label: Text('Price', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
          DataColumn(label: Text('Installed On', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
          DataColumn(label: Text('Job #', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
        ],
        rows: parts.map((p) {
          return DataRow(
            cells: [
              DataCell(Text(p['partName'] ?? '-', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
              DataCell(Text('${p['quantity'] ?? 1}', style: const TextStyle(fontSize: 12))),
              DataCell(Text(_formatKes(p['price'] ?? 0), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
              DataCell(Text(_formatDateShort(p['date']), style: const TextStyle(fontSize: 11))),
              DataCell(Text(p['jobNumber'] ?? '-', style: const TextStyle(fontSize: 11, color: Color(0xFF2563EB)))),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDiagnosticsLog(List<dynamic> diagnostics) {
    if (diagnostics.isEmpty) {
      return const Center(child: Text('No OBD-II scanner codes or diagnostic defect records for this vehicle.', style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      itemCount: diagnostics.length,
      itemBuilder: (context, i) {
        final d = diagnostics[i];
        final defects = (d['defects'] as List<dynamic>?) ?? [];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Job Card: ${d['jobNumber'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E3A8A))),
                    Text(_formatDateShort(d['date']), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  ],
                ),
                if ((d['obdCodes'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.amber.shade300)),
                    child: Text('OBD Scanner Codes: ${d['obdCodes']}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
                  ),
                ],
                if (defects.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Issues / Defects: ${defects.join(', ')}', style: const TextStyle(fontSize: 12, color: Colors.redAccent)),
                ],
                if ((d['notes'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('Mechanic Notes: ${d['notes']}', style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontStyle: FontStyle.italic)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMileageProgression(List<dynamic> logs) {
    if (logs.isEmpty) {
      return const Center(child: Text('No odometer progression records found for this vehicle.', style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      itemCount: logs.length,
      itemBuilder: (context, i) {
        final entry = logs[i];
        return ListTile(
          dense: true,
          leading: const Icon(Icons.speed, color: Color(0xFF2563EB)),
          title: Text('${entry['odometer']} km', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          subtitle: Text('Recorded on ${_formatDateShort(entry['date'])}  \u2022  Job Card: ${entry['jobNumber']}'),
        );
      },
    );
  }
}

