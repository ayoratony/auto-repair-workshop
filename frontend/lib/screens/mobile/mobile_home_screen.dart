import 'package:flutter/material.dart';
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

  int _selectedIndex = 1;
  List<dynamic> _jobs = [];
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

  String _fuelLevel = 'Half';
  String _priority = 'Medium';
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
      final response = await http.get(Uri.parse('$_baseUrl/jobs'));
      if (response.statusCode == 200 && mounted) {
        setState(() {
          _jobs = json.decode(response.body);
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
          'service': _serviceController.text.trim().isEmpty
              ? _memoDetails.selectedCategories.join(', ')
              : _serviceController.text.trim(),
          'status': 'BOOKED',
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
        setState(() {
          _damageMarkers = [];
          _memoDetails = ReceivingMemoDetails();
          _signatureCaptured = false;
          _selectedIndex = 0; // Switch to Home list to see it
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedIndex == 0
            ? 'Active Workshop Jobs'
            : _selectedIndex == 1
                ? 'Digital Vehicle Intake'
                : 'Workshop Schedule'),
        backgroundColor: const Color(0xFF0F4C81),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchJobs),
        ],
      ),
      body: _selectedIndex == 1 ? _buildIntakeForm() : _buildJobsList(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF0F4C81),
        onTap: (index) {
          setState(() => _selectedIndex = index);
          if (index != 1) _fetchJobs();
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'Active Jobs'),
          BottomNavigationBarItem(icon: Icon(Icons.add_circle_outline), label: 'New Intake'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_today), label: 'Schedule'),
        ],
      ),
    );
  }

  Widget _buildJobsList() {
    if (_isLoadingJobs) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_jobs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.directions_car_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('No Job Cards in Database yet.', style: TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => setState(() => _selectedIndex = 1),
              icon: const Icon(Icons.add),
              label: const Text('Create First Intake Job Card'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _jobs.length,
      itemBuilder: (context, index) {
        final job = _jobs[index];
        final jobNo = job['jobNumber'] ?? job['id'].toString().substring(0, 8).toUpperCase();
        final customer = job['customer']?['name'] ?? 'Customer';
        final vehicle = '${job['vehicle']?['make'] ?? ''} ${job['vehicle']?['model'] ?? ''} (${job['vehicle']?['registrationNo'] ?? ''})';
        final status = job['status'] ?? 'IN_PROGRESS';

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            onTap: () => InvoicePdfService.showJobCardPreviewModal(
              context: context,
              workshopSettings: const {},
              job: Map<String, dynamic>.from(job),
            ),
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF0F4C81),
              child: Text(jobNo.substring(0, 2), style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
            title: Text('$jobNo • $customer', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('$vehicle\nService: ${job['workRequested'] ?? 'Service'} • Tech: ${job['technician'] ?? 'Unassigned'}'),
            isThreeLine: true,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Print / PDF Customer Copy',
                  icon: const Icon(Icons.print_outlined, color: Color(0xFF1D4ED8)),
                  onPressed: () => InvoicePdfService.showJobCardPreviewModal(
                    context: context,
                    workshopSettings: const {},
                    job: Map<String, dynamic>.from(job),
                  ),
                ),
                Chip(
                  label: Text(status, style: const TextStyle(fontSize: 11)),
                  backgroundColor: Colors.blue.shade50,
                ),
              ],
            ),
          ),
        );
      },
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
