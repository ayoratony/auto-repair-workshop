import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../web/invoice_pdf_service.dart';
import 'vehicle_damage_map.dart';
import 'walk_around_checklist.dart';

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
  String _jobSearch = '';

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

  String _fuelLevel = 'Half';
  String _priority = 'Medium';
  String _bayNumber = 'Bay 1';
  VehicleBodyType _selectedBodyType = VehicleBodyType.sedan;
  List<DamageMarker> _damageMarkers = [];
  ReceivingMemoDetails _memoDetails = ReceivingMemoDetails();
  bool _signatureCaptured = false;

  @override
  void initState() {
    super.initState();
    _fetchJobs();
  }

  Future<void> _fetchJobs() async {
    setState(() => _isLoadingJobs = true);
    try {
      final effectiveTech = _techName == 'All' ? 'Kamau Tech' : _techName;
      final results = await Future.wait([
        http.get(Uri.parse('$_baseUrl/jobs')),
        http.get(Uri.parse('$_baseUrl/appointments')),
        http.get(Uri.parse('$_baseUrl/estimates')),
        http.get(Uri.parse('$_baseUrl/employees')),
        http.get(
          Uri.parse('$_baseUrl/inventory/requests'),
          headers: {'x-user-role': 'MECHANIC', 'x-user-name': effectiveTech},
        ),
      ]);
      if (mounted) {
        setState(() {
          if (results[0].statusCode == 200) _jobs = json.decode(results[0].body);
          if (results[1].statusCode == 200) _appointments = json.decode(results[1].body);
          if (results[2].statusCode == 200) _estimates = json.decode(results[2].body);
          if (results[3].statusCode == 200) {
            _technicians = (json.decode(results[3].body) as List)
                .where((u) => u['role'] == 'MECHANIC' || u['role'] == 'INSPECTOR')
                .map<String>((u) => u['name'].toString())
                .toList();
          }
          if (results[4].statusCode == 200) _itemRequests = json.decode(results[4].body);
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
          'customerName': _customerController.text.trim(),
          'phone': _phoneController.text.trim(),
          'registrationNo': _regController.text.trim(),
          'make': _makeController.text.trim(),
          'model': _modelController.text.trim(),
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
          },
          'walkAroundData': {
            'bodyType': _selectedBodyType.name,
            'markers': _damageMarkers.map((m) => m.toJson()).toList(),
            'memoDetails': _memoDetails.toJson(),
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
        setState(() {
          _damageMarkers = [];
          _memoDetails = ReceivingMemoDetails();
          _signatureCaptured = false;
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
      final r = await http.put(
        Uri.parse('$_baseUrl/jobs/$id'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      );
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void _switchRole(String role) {
    setState(() {
      _role = role;
      _selectedIndex = 0;
    });
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
              child: Text(
                'â€¢ $title',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white70),
                overflow: TextOverflow.ellipsis,
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
        ],
        bottom: PreferredSize(
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
        ),
      ),
      body: _isAdvisor ? _buildAdvisorBody() : _buildTechnicianBody(),
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
      ['Appointments', 'Bookings & bays', Icons.event_available, () => setState(() => _selectedIndex = 4)],
      ['Quotations', 'Estimates & approvals', Icons.request_quote, () => setState(() => _selectedIndex = 3)],
      ['Communications', 'Customer updates', Icons.chat_bubble, _showCommunicationsSheet],
      ['New Intake', '360Â° vehicle check-in', Icons.directions_car, () => setState(() => _selectedIndex = 2)],
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
              child: Text('Nothing pending â€” all caught up.', style: TextStyle(color: Colors.black54)),
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
                          subtitle: Text('${c['phone'] ?? 'No phone'} â€¢ ${jobs.length} visit(s)'),
                          children: jobs
                              .map<Widget>((j) => ListTile(
                                    dense: true,
                                    title: Text('${j['vehicle']?['registrationNo'] ?? ''} â€¢ ${j['workRequested'] ?? 'Service'}'),
                                    subtitle: Text('${j['jobNumber'] ?? ''} â€¢ ${_prettyStatus(j['status'] ?? '')}'),
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
                          title: Text('${j['customer']?['name'] ?? ''} â€¢ $reg'),
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

  Widget _buildQuotesView() {
    if (_isLoadingJobs) return const Center(child: CircularProgressIndicator());
    if (_estimates.isEmpty) {
      return const Center(child: Text('No quotations yet.', style: TextStyle(color: Colors.grey)));
    }
    return RefreshIndicator(
      onRefresh: _fetchJobs,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _estimates.length,
        itemBuilder: (_, i) {
          final e = _estimates[i];
          final status = (e['status'] ?? 'DRAFT').toString();
          final jc = e['jobCard'];
          final total = (e['total'] is num) ? (e['total'] as num).toStringAsFixed(0) : '0';
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${jc?['jobNumber'] ?? 'Job'} â€¢ ${jc?['customer']?['name'] ?? ''}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text('KES $total', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0F4C81))),
                  ],
                ),
                const SizedBox(height: 2),
                Text('${jc?['vehicle']?['registrationNo'] ?? ''} â€¢ ${(e['lineItems'] as List?)?.length ?? 0} item(s)',
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  children: ['DRAFT', 'SENT', 'APPROVED', 'REJECTED']
                      .map((s) => ChoiceChip(
                            label: Text(s, style: const TextStyle(fontSize: 11)),
                            selected: status == s,
                            onSelected: (_) async {
                              await http.put(
                                Uri.parse('$_baseUrl/estimates/${e['id']}/status'),
                                headers: {'Content-Type': 'application/json'},
                                body: json.encode({'status': s}),
                              );
                              _fetchJobs();
                            },
                          ))
                      .toList(),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('Approve only with documented customer authorisation.',
                      style: TextStyle(fontSize: 10.5, color: Colors.black45)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SHARED JOB CARD LIST / CARD
  // ---------------------------------------------------------------------------
  Widget _jobCard(dynamic job, {bool techMode = false}) {
    final jobNo = (job['jobNumber'] ?? job['id'].toString().substring(0, 8).toUpperCase()).toString();
    final customer = job['customer']?['name'] ?? 'Customer';
    final vehicle = '${job['vehicle']?['make'] ?? ''} ${job['vehicle']?['model'] ?? ''}'.trim();
    final reg = job['vehicle']?['registrationNo'] ?? '';
    final status = (job['status'] ?? 'IN_PROGRESS').toString();
    final color = _statusColor(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openJobSheet(Map<String, dynamic>.from(job), techMode: techMode),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(jobNo, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                    child: Text(_prettyStatus(status),
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text('$reg â€¢ $vehicle', style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(job['workRequested']?.toString() ?? 'Service',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black54, fontSize: 13)),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.person_outline, size: 15, color: Colors.black45),
                  const SizedBox(width: 4),
                  Expanded(child: Text(customer, style: const TextStyle(fontSize: 12))),
                  const Icon(Icons.build_outlined, size: 15, color: Colors.black45),
                  const SizedBox(width: 4),
                  Text(job['technician']?.toString().isNotEmpty == true ? job['technician'].toString() : 'Unassigned',
                      style: const TextStyle(fontSize: 12)),
                  if (job['bayNumber'] != null) ...[
                    const SizedBox(width: 10),
                    const Icon(Icons.garage_outlined, size: 15, color: Colors.black45),
                    const SizedBox(width: 4),
                    Text(job['bayNumber'].toString(), style: const TextStyle(fontSize: 12)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildJobsList() {
    if (_isLoadingJobs && _jobs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final q = _jobSearch.toLowerCase();
    final shown = _jobs.where((j) {
      if (q.isEmpty) return true;
      return '${j['jobNumber']} ${j['customer']?['name']} ${j['vehicle']?['registrationNo']} ${j['vehicle']?['make']} ${j['vehicle']?['model']}'
          .toLowerCase()
          .contains(q);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            onChanged: (v) => setState(() => _jobSearch = v),
            decoration: InputDecoration(
              hintText: 'Search job, plate, customerâ€¦',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.directions_car_outlined, size: 64, color: Colors.grey),
                      const SizedBox(height: 12),
                      const Text('No job cards found.', style: TextStyle(fontSize: 16, color: Colors.grey)),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
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
                    padding: const EdgeInsets.all(12),
                    itemCount: shown.length,
                    itemBuilder: (_, i) => _jobCard(shown[i]),
                  ),
                ),
        ),
      ],
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
    final mine = _jobs.where((j) {
      final done = j['status'] == 'COMPLETED';
      if (done != showCompleted) return false;
      if (!showCompleted && (j['status'] == 'BOOKED' || j['status'] == 'READY') && _techName != 'All') {
        // still visible if assigned to this technician
      }
      if (_techName == 'All') return true;
      return (j['technician'] ?? '').toString() == _techName;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: DropdownButtonFormField<String>(
            value: (_techName == 'All' || _technicians.contains(_techName)) ? _techName : 'All',
            decoration: InputDecoration(
              labelText: 'I am',
              prefixIcon: const Icon(Icons.badge_outlined),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
            items: ['All', ..._technicians].map((t) => DropdownMenuItem(value: t, child: Text(t == 'All' ? 'All technicians (bay view)' : t))).toList(),
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
            children: ['ALL', 'PENDING', 'APPROVED', 'PARTIALLY_ISSUED', 'ISSUED', 'REJECTED']
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
            const SizedBox(height: 6),
            Text('Reason: $reason', style: const TextStyle(fontSize: 13, color: Colors.black87)),
            if (req['jobCardId'] != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.directions_car, size: 14, color: Colors.black54),
                  const SizedBox(width: 4),
                  Text('Job Card: ${req['jobCardId'].toString().substring(0, 8).toUpperCase()}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
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
                value: condition,
                decoration: const InputDecoration(labelText: 'Condition', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'GOOD', child: Text('Good - Unused')),
                  DropdownMenuItem(value: 'DAMAGED', child: Text('Damaged')),
                  DropdownMenuItem(value: 'DEFECTIVE', child: Text('Defective / Faulty')),
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

  void _showItemRequestDialog() {
    String searchQuery = '';
    List<dynamic> catalogResults = [];
    Map<String, dynamic>? selectedItem;
    final qtyCtrl = TextEditingController(text: '1');
    final reasonCtrl = TextEditingController();
    String? linkedJobId;
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
                    searchQuery = q;
                    if (q.length < 2) { setSheet(() => catalogResults = []); return; }
                    try {
                      final catParam = category == 'ALL' ? '' : '&category=$category';
                      final res = await http.get(
                        Uri.parse('$_baseUrl/inventory/catalog?search=$q$catParam'),
                        headers: {'x-user-role': 'MECHANIC'},
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
                const SizedBox(height: 10),
                TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity *', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: reasonCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Reason for Request *', hintText: 'e.g. Brake pad replacement for KBA 123A', border: OutlineInputBorder())),
                const SizedBox(height: 10),
                // Link to job card
                DropdownButtonFormField<String>(
                  value: linkedJobId,
                  decoration: const InputDecoration(labelText: 'Link to Job Card (optional)', border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('-- No job card --')),
                    ..._jobs.where((j) => j['status'] != 'COMPLETED').map((j) {
                      final plate = j['vehiclePlate'] ?? '';
                      final id = j['id'].toString();
                      return DropdownMenuItem(value: id, child: Text('$plate - ${id.substring(0, 8).toUpperCase()}', style: const TextStyle(fontSize: 12)));
                    }),
                  ],
                  onChanged: (v) => setSheet(() => linkedJobId = v),
                ),
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
                    label: const Text('Submit Request', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    onPressed: () async {
                      if (selectedItem == null) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select an item'), backgroundColor: Colors.orange));
                        return;
                      }
                      if (reasonCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a reason'), backgroundColor: Colors.orange));
                        return;
                      }
                      final body = {
                        'reason': reasonCtrl.text.trim(),
                        'lines': [
                          {
                            'itemId': selectedItem!['id'],
                            'qtyRequested': int.tryParse(qtyCtrl.text) ?? 1,
                          }
                        ],
                      };
                      if (linkedJobId != null) body['jobCardId'] = linkedJobId!;
                      try {
                        final res = await http.post(
                          Uri.parse('$_baseUrl/inventory/requests'),
                          headers: {'Content-Type': 'application/json', 'x-user-role': 'MECHANIC', 'x-user-name': _techName},
                          body: json.encode(body),
                        );
                        if (res.statusCode == 201) {
                          if (ctx.mounted) Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Item request submitted!'), backgroundColor: Colors.green),
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

  void _openJobSheet(Map<String, dynamic> job, {required bool techMode}) {
    final walk = job['walkAroundData'] is Map ? Map<String, dynamic>.from(job['walkAroundData']) : <String, dynamic>{};
    final tech = walk['techInspection'] is Map ? Map<String, dynamic>.from(walk['techInspection']) : <String, dynamic>{};
    final results = <String, String>{
      for (final p in _inspectionPoints) p: (tech['results'] is Map ? tech['results'][p]?.toString() : null) ?? '',
    };
    final obdCtrl = TextEditingController(text: tech['obdCodes']?.toString() ?? '');
    final notesCtrl = TextEditingController(text: tech['notes']?.toString() ?? '');
    final hoursCtrl = TextEditingController(text: job['actualHours']?.toString() ?? '');
    String status = (job['status'] ?? 'BOOKED').toString();
    String assigned = (job['technician'] ?? '').toString();
    final techOptions = {..._technicians, if (assigned.isNotEmpty) assigned}.toList();
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
                Text('${job['jobNumber'] ?? 'Job Card'} â€¢ ${job['vehicle']?['registrationNo'] ?? ''}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                Text('${job['vehicle']?['make'] ?? ''} ${job['vehicle']?['model'] ?? ''} â€¢ ${job['customer']?['name'] ?? ''}',
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
                    value: techOptions.contains(assigned) ? assigned : null,
                    decoration: const InputDecoration(labelText: 'Assign Technician', border: OutlineInputBorder()),
                    items: techOptions.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                    onChanged: (v) => setSheet(() => assigned = v ?? ''),
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
                const SizedBox(height: 18),
                Row(
                  children: [
                    if (!techMode)
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.print_outlined),
                          label: const Text('Customer Copy'),
                          onPressed: () => InvoicePdfService.showJobCardPreviewModal(
                            context: context,
                            workshopSettings: const {},
                            job: job,
                          ),
                        ),
                      ),
                    if (!techMode) const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F4C81),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: saving
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save),
                        label: const Text('Save'),
                        onPressed: saving
                            ? null
                            : () async {
                                setSheet(() => saving = true);
                                final body = <String, dynamic>{'status': status};
                                if (techMode) {
                                  walk['techInspection'] = {
                                    'results': results,
                                    'obdCodes': obdCtrl.text.trim(),
                                    'notes': notesCtrl.text.trim(),
                                    'by': _techName,
                                    'updatedAt': DateTime.now().toIso8601String(),
                                  };
                                  body['walkAroundData'] = walk;
                                  final h = double.tryParse(hoursCtrl.text.trim());
                                  if (h != null) body['actualHours'] = h;
                                } else {
                                  body['technician'] = assigned;
                                }
                                final ok = await _putJob(job['id'].toString(), body);
                                if (ctx.mounted) Navigator.pop(ctx);
                                _toast(ok ? 'Job updated' : 'Failed to update job', color: ok ? Colors.green : Colors.red);
                                _fetchJobs();
                              },
                      ),
                    ),
                  ],
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
          TextField(
            controller: _customerController,
            decoration: const InputDecoration(labelText: 'Customer Name *', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Customer Phone', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _regController,
                  decoration: const InputDecoration(labelText: 'Registration No *', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _odometerController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Odometer (km)', border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _makeController,
                  decoration: const InputDecoration(labelText: 'Vehicle Make (e.g. Toyota)', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _modelController,
                  decoration: const InputDecoration(labelText: 'Vehicle Model (e.g. Hilux)', border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _fuelLevel,
                  decoration: const InputDecoration(labelText: 'Fuel Level', border: OutlineInputBorder()),
                  items: ['Empty', '1/4', 'Half', '3/4', 'Full']
                      .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                      .toList(),
                  onChanged: (val) => setState(() => _fuelLevel = val ?? 'Half'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _priority,
                  decoration: const InputDecoration(labelText: 'Priority', border: OutlineInputBorder()),
                  items: ['Low', 'Medium', 'High']
                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (val) => setState(() => _priority = val ?? 'Medium'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _bayNumber,
                  decoration: const InputDecoration(labelText: 'Workshop Bay / Lift', border: OutlineInputBorder()),
                  items: ['Bay 1', 'Bay 2', 'Bay 3', 'Lift A', 'Lift B', 'Diagnostic Bay']
                      .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                      .toList(),
                  onChanged: (val) => setState(() => _bayNumber = val ?? 'Bay 1'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _obdController,
                  decoration: const InputDecoration(labelText: 'OBD-II Codes (e.g. P0300)', border: OutlineInputBorder()),
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
                          '${appt['registrationNo'] ?? 'Vehicle'} â€¢ ${appt['customerName'] ?? ''}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          'Service: ${appt['serviceType'] ?? '-'}\nBay: ${appt['bayNumber'] ?? 'Bay 1'} â€¢ Status: $status',
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
                value: bay,
                decoration: const InputDecoration(labelText: 'Assign Bay / Lift'),
                items: ['Bay 1', 'Bay 2', 'Bay 3', 'Lift A', 'Lift B', 'Diagnostic Bay']
                    .map((b) => DropdownMenuItem(value: b, child: Text(b)))
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

