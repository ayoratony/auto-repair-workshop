import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../models/pms_checklist_model.dart';
import '../../models/pms_checklist_templates.dart';
import '../../services/auth_service.dart';
import '../../services/pms_pdf_service.dart';

class PmsChecklistSheet extends StatefulWidget {
  final Map<String, dynamic> job;
  final String baseUrl;
  final VoidCallback onSubmitted;
  final Map<String, dynamic>? workshopSettings;
  final bool? readOnly;

  const PmsChecklistSheet({
    super.key,
    required this.job,
    required this.baseUrl,
    required this.onSubmitted,
    this.workshopSettings,
    this.readOnly,
  });

  static Future<void> show({
    required BuildContext context,
    required Map<String, dynamic> job,
    required String baseUrl,
    required VoidCallback onSubmitted,
    Map<String, dynamic>? workshopSettings,
    bool? readOnly,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PmsChecklistSheet(
        job: job,
        baseUrl: baseUrl,
        onSubmitted: onSubmitted,
        workshopSettings: workshopSettings,
        readOnly: readOnly,
      ),
    );
  }

  @override
  State<PmsChecklistSheet> createState() => _PmsChecklistSheetState();
}

class _PmsChecklistSheetState extends State<PmsChecklistSheet> {
  late PmsChecksheetData _checksheet;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isReadOnly = false;
  String _selectedCategoryFilter = 'ALL';
  late TextEditingController _techCommentsCtrl;
  late TextEditingController _complaintsCtrl;
  late TextEditingController _mileageCtrl;

  @override
  void initState() {
    super.initState();
    _techCommentsCtrl = TextEditingController();
    _complaintsCtrl = TextEditingController();
    _mileageCtrl = TextEditingController();
    _loadChecklist();
  }

  @override
  void dispose() {
    _techCommentsCtrl.dispose();
    _complaintsCtrl.dispose();
    _mileageCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadChecklist() async {
    final jobId = widget.job['id']?.toString() ?? '';
    final vehicle = widget.job['vehicle'] ?? {};
    final regNo = (vehicle['registrationNo'] ?? widget.job['registrationNo'] ?? '').toString();
    final vin = (vehicle['vinNumber'] ?? '').toString();
    final jobNo = (widget.job['jobNumber'] ?? jobId.substring(0, 8)).toString().toUpperCase();
    final odometer = widget.job['odometer'] is int ? widget.job['odometer'] as int : int.tryParse(widget.job['odometer']?.toString() ?? '');
    final techName = AuthService.instance.userName;

    try {
      final res = await http.get(
        Uri.parse('${widget.baseUrl}/jobs/$jobId/pms-checklist'),
        headers: AuthService.instance.authHeaders,
      );

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (data['pmsChecklist'] != null && data['pmsChecklist'] is Map) {
          _checksheet = PmsChecksheetData.fromJson(Map<String, dynamic>.from(data['pmsChecklist']));
        } else {
          // Initialize fresh checksheet with auto-detected template
          final def = PmsTemplates.autoDetect(
            vehicle['make']?.toString(),
            vehicle['model']?.toString(),
            vehicle['category']?.toString(),
          );
          _checksheet = PmsTemplates.createNewChecksheet(
            templateCode: def.code,
            registrationNumber: regNo,
            vinNumber: vin,
            jobCardNumber: jobNo,
            currentMileage: odometer,
            technicianName: techName,
          );
          _checksheet.customerComplaint = (widget.job['workRequested'] ?? '').toString();
        }
      } else {
        final def = PmsTemplates.autoDetect(
          vehicle['make']?.toString(),
          vehicle['model']?.toString(),
          vehicle['category']?.toString(),
        );
        _checksheet = PmsTemplates.createNewChecksheet(
          templateCode: def.code,
          registrationNumber: regNo,
          vinNumber: vin,
          jobCardNumber: jobNo,
          currentMileage: odometer,
          technicianName: techName,
        );
      }
    } catch (_) {
      final def = PmsTemplates.autoDetect(
        vehicle['make']?.toString(),
        vehicle['model']?.toString(),
        vehicle['category']?.toString(),
      );
      _checksheet = PmsTemplates.createNewChecksheet(
        templateCode: def.code,
        registrationNumber: regNo,
        vinNumber: vin,
        jobCardNumber: jobNo,
        currentMileage: odometer,
        technicianName: techName,
      );
    }

    _techCommentsCtrl.text = _checksheet.technicianComments;
    _complaintsCtrl.text = _checksheet.customerComplaint;
    _mileageCtrl.text = _checksheet.currentMileage?.toString() ?? '';

    final wad = widget.job['walkAroundData'] is Map ? (widget.job['walkAroundData'] as Map) : {};
    final pmsRaw = (wad['pmsChecklist'] is Map) ? (wad['pmsChecklist'] as Map) : null;
    final isLocked = _checksheet.isLocked ||
        _checksheet.status == 'SUBMITTED_TO_ADVISOR' ||
        _checksheet.status == 'COMPLETED' ||
        pmsRaw?['isLocked'] == true ||
        pmsRaw?['status'] == 'SUBMITTED_TO_ADVISOR' ||
        pmsRaw?['status'] == 'COMPLETED';

    final isSupervisor = AuthService.instance.isOwner ||
        AuthService.instance.isManager ||
        AuthService.instance.isAdvisor;

    _isReadOnly = widget.readOnly ?? (isLocked && !isSupervisor);

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _unlockChecksheet() async {
    final jobId = widget.job['id']?.toString() ?? '';
    setState(() => _isSaving = true);
    try {
      final res = await http.post(
        Uri.parse('${widget.baseUrl}/jobs/$jobId/pms-unlock'),
        headers: AuthService.instance.authHeaders,
        body: json.encode({
          'reason': 'Supervisor authorized re-evaluation',
        }),
      );
      if (res.statusCode == 200) {
        setState(() {
          _isReadOnly = false;
          _checksheet.status = 'DRAFT';
          _checksheet.isLocked = false;
        });
        widget.onSubmitted();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ Check Sheet unlocked for re-inspection.'),
              backgroundColor: Color(0xFF15803D),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Unlock failed: ${res.body}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _openPdfPreview() {
    try {
      PmsPdfService.showPdfPreviewModal(
        context: context,
        workshopSettings: widget.workshopSettings ?? widget.job['workshopSettings'] ?? {},
        job: widget.job,
        checksheet: _checksheet,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cannot render PDF: $e'), backgroundColor: Colors.red),
      );
    }
  }

  String _formatDateShort(dynamic iso) {
    if (iso == null || iso.toString().isEmpty) return '';
    try {
      final dt = DateTime.parse(iso.toString()).toLocal();
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return iso.toString();
    }
  }

  void _switchTemplate(String newCode) {
    final def = PmsTemplates.getByCode(newCode);
    final oldItems = {for (var i in _checksheet.items) i.itemNumber: i};
    final newItems = def.buildItems();

    // Preserve existing responses where possible
    for (var ni in newItems) {
      if (oldItems.containsKey(ni.itemNumber)) {
        final oi = oldItems[ni.itemNumber]!;
        ni.status = oi.status;
        ni.remarks = oi.remarks;
        ni.defectDescription = oi.defectDescription;
        ni.recommendedFix = oi.recommendedFix;
        ni.estimatedParts = oi.estimatedParts;
        ni.estimatedLabour = oi.estimatedLabour;
        ni.partsNeeded = oi.partsNeeded;
      }
    }

    setState(() {
      _checksheet.templateCode = def.code;
      _checksheet.templateTitle = def.title;
      if (!def.intervals.contains(_checksheet.selectedInterval)) {
        _checksheet.selectedInterval = def.intervals.first;
      }
      _checksheet.items = newItems;
      _checksheet.battery.is24VSystem = def.is24V;
    });
  }

  void _markAllRemainingAsOk() {
    setState(() {
      for (var item in _checksheet.items) {
        if (item.status == PmsItemStatus.notApplicable) continue;
        if (item.status == PmsItemStatus.ng || item.status == PmsItemStatus.caution) continue;
        if (item.category == 'Periodic Maintenance Items') {
          if (item.intervalStandard?.contains('R') == true) {
            item.status = PmsItemStatus.replace;
          } else if (item.intervalStandard?.contains('L') == true) {
            item.status = PmsItemStatus.grease;
          } else {
            item.status = PmsItemStatus.ok;
          }
        } else {
          item.status = PmsItemStatus.ok;
        }
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF15803D),
        content: Text('✓ Marked all standard items as Passed / Inspected & OK'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _saveChecklist({required bool submitToAdvisor}) async {
    setState(() => _isSaving = true);
    final jobId = widget.job['id']?.toString() ?? '';

    _checksheet.technicianComments = _techCommentsCtrl.text.trim();
    _checksheet.customerComplaint = _complaintsCtrl.text.trim();
    _checksheet.currentMileage = int.tryParse(_mileageCtrl.text.trim());
    _checksheet.technicianName = AuthService.instance.userName;

    try {
      final res = await http.post(
        Uri.parse('${widget.baseUrl}/jobs/$jobId/pms-checklist'),
        headers: AuthService.instance.authHeaders,
        body: json.encode({
          'checklist': _checksheet.toJson(),
          'submitToAdvisor': submitToAdvisor,
          'technicianName': AuthService.instance.userName,
        }),
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        if (mounted) {
          Navigator.pop(context);
          widget.onSubmitted();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: submitToAdvisor ? const Color(0xFF15803D) : const Color(0xFF1E3A8A),
              content: Text(
                submitToAdvisor
                    ? '✓ Diagnostic Checksheet & Recommendations submitted to Service Advisor!'
                    : '✓ PMS Checksheet draft saved successfully.',
              ),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: Colors.red, content: Text('Save failed: ${res.body}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Network error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _confirmSubmitToAdvisor() {
    final defects = _checksheet.defects;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFF1E3A8A).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.send_rounded, color: Color(0xFF1E3A8A)),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Submit Diagnosis to Service Advisor', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Vehicle: ${_checksheet.registrationNumber} • Mileage: ${_mileageCtrl.text} km',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 6),
              Text(
                'Checksheet: ${_checksheet.templateTitle} (${_checksheet.selectedInterval} Service)',
                style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
              ),
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statBadge('Pass / OK', _checksheet.okCount, Colors.green),
                  _statBadge('Caution (C)', _checksheet.cautionCount, Colors.orange),
                  _statBadge('Immediate (NG)', _checksheet.ngCount, Colors.red),
                ],
              ),
              const SizedBox(height: 14),
              if (defects.isNotEmpty) ...[
                Text(
                  'Identified Findings for Customer Recommendation (${defects.length}):',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Container(
                  constraints: const BoxConstraints(maxHeight: 180),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.shade200)),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: defects.length,
                    itemBuilder: (ctx, i) {
                      final d = defects[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: d.isImmediate ? Colors.red.shade100 : Colors.amber.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                d.status.code,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: d.isImmediate ? Colors.red.shade900 : Colors.amber.shade900,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '#${d.itemNumber} ${d.description}: ${(d.defectDescription ?? d.remarks).isNotEmpty ? (d.defectDescription ?? d.remarks) : "Requires attention"}',
                                style: const TextStyle(fontSize: 11.5, color: Color(0xFF1E293B)),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green.shade200)),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Clean Diagnosis! Zero defects found. Vehicle is in excellent operational condition.',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                'Submitting will notify the Service Advisor and advance this Job Card to "Awaiting Customer Approval".',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Back to Edit')),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF15803D), foregroundColor: Colors.white),
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Confirm & Send to Advisor', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () {
              Navigator.pop(ctx);
              _saveChecklist(submitToAdvisor: true);
            },
          ),
        ],
      ),
    );
  }

  Widget _statBadge(String label, int count, MaterialColor color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: color.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.shade200),
          ),
          child: Text(
            count.toString(),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color.shade900),
          ),
        ),
        const SizedBox(height: 3),
        Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: color.shade900)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        height: 400,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Loading PMS Diagnostic Check Sheet...'),
            ],
          ),
        ),
      );
    }

    final curDef = PmsTemplates.getByCode(_checksheet.templateCode);
    final displayedItems = _getFilteredItems();

    return DraggableScrollableSheet(
      initialChildSize: 0.94,
      minChildSize: 0.5,
      maxChildSize: 0.98,
      expand: false,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF8FAFC),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Top Drag Handle & Title
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E3A8A).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _checksheet.registrationNumber,
                          style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1E3A8A), fontSize: 14),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _checksheet.templateTitle,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'Job #${_checksheet.jobCardNumber} • ${_isReadOnly ? "Inspected by: ${_checksheet.technicianName.isNotEmpty ? _checksheet.technicianName : 'Tech'}" : "Tech: ${AuthService.instance.userName}"}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.print_outlined, color: Color(0xFF1E3A8A)),
                        tooltip: 'Print Customer PMS Report (PDF)',
                        onPressed: _openPdfPreview,
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            if (_isReadOnly)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: const BoxDecoration(
                  color: Color(0xFF064E3B),
                  border: Border(bottom: BorderSide(color: Color(0xFF34D399), width: 1.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified, color: Color(0xFF4ADE80), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'DIAGNOSTIC INSPECTION COMPLETE & LOCKED',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11),
                          ),
                          Text(
                            'Signed by ${_checksheet.technicianName.isNotEmpty ? _checksheet.technicianName : "Technician"}${_checksheet.submittedAt != null ? " on ${_formatDateShort(_checksheet.submittedAt)}" : ""} • Read-Only Security Mode',
                            style: const TextStyle(color: Color(0xFFA7F3D0), fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock, size: 11, color: Colors.white),
                          SizedBox(width: 3),
                          Text('Locked', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // Sticky Header: KPI score & Template Switcher
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: const Color(0xFF0F172A),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.green.shade400),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.check_circle, size: 12, color: Color(0xFF4ADE80)),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${_checksheet.okCount} OK',
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF86EFAC), fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.amber.shade400),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.warning_amber_rounded, size: 12, color: Color(0xFFFBBF24)),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${_checksheet.cautionCount} C',
                                      style: const TextStyle(fontSize: 11, color: Color(0xFFFDE68A), fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.red.shade400),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.cancel, size: 12, color: Color(0xFFF87171)),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${_checksheet.ngCount} NG',
                                      style: const TextStyle(fontSize: 11, color: Color(0xFFFCA5A5), fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Health: ${_checksheet.healthPercentage.toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: _checksheet.healthPercentage >= 90
                              ? const Color(0xFF4ADE80)
                              : (_checksheet.healthPercentage >= 75 ? const Color(0xFFFBBF24) : const Color(0xFFF87171)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Template & Interval Row
                  if (_isReadOnly)
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF334155)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.lock_outline, size: 13, color: Colors.white70),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _checksheet.templateTitle.replaceAll('PMS CHECK SHEET - ', ''),
                                    style: const TextStyle(fontSize: 11.5, color: Colors.white, fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF60A5FA)),
                          ),
                          child: Text(
                            'Interval: ${_checksheet.selectedInterval}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF93C5FD)),
                          ),
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        // Template Dropdown
                        Expanded(
                          flex: 3,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF334155)),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _checksheet.templateCode,
                                isExpanded: true,
                                isDense: true,
                                icon: const Icon(Icons.arrow_drop_down, color: Colors.white70, size: 18),
                                dropdownColor: const Color(0xFF1E293B),
                                style: const TextStyle(fontSize: 11.5, color: Colors.white, fontWeight: FontWeight.w600),
                                items: PmsTemplates.definitions
                                    .map((d) => DropdownMenuItem(
                                          value: d.code,
                                          child: Text(
                                            d.title.replaceAll('PMS CHECK SHEET - ', ''),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ))
                                    .toList(),
                                selectedItemBuilder: (ctx) => PmsTemplates.definitions
                                    .map((d) => Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            d.title.replaceAll('PMS CHECK SHEET - ', ''),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 11.5, color: Colors.white, fontWeight: FontWeight.w600),
                                          ),
                                        ))
                                    .toList(),
                                onChanged: (v) {
                                  if (v != null) _switchTemplate(v);
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Service Interval Chips
                        Expanded(
                          flex: 2,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: curDef.intervals.map((inv) {
                                final sel = _checksheet.selectedInterval == inv;
                                return Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: InkWell(
                                    onTap: () => setState(() => _checksheet.selectedInterval = inv),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: sel ? const Color(0xFF2563EB) : const Color(0xFF1E293B),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: sel ? const Color(0xFF60A5FA) : const Color(0xFF334155)),
                                      ),
                                      child: Text(
                                        inv,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.bold,
                                          color: sel ? Colors.white : Colors.grey.shade400,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),

            // Horizontal Filter Tabs
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _filterChip('ALL', 'All (${_checksheet.items.length})'),
                    _filterChip('DEFECTS', '⚠️ Defects Only (${_checksheet.defects.length})', isHighlight: _checksheet.defects.isNotEmpty),
                    _filterChip('Periodic Maintenance Items', '1. PMS Items (1-14)'),
                    _filterChip('Body', '2. Body (15-21)'),
                    _filterChip('Inside The Cabin', '3. Cabin (22-37)'),
                    _filterChip('Under the Cabin / Bonnet', '4. Under Bonnet (38-47)'),
                    _filterChip('Under The Vehicle & Chassis', '5. Chassis & Brakes (48-59)'),
                    _filterChip('Tyre Wheel', '6. Tyres & Wheels (60-64)'),
                    if (curDef.isBus) _filterChip('Bus Body', '7. Bus Body (65-70)'),
                    _filterChip('TYRE_TABLE', '📊 Tyre Pressure Table'),
                    _filterChip('SUMMARY', '📝 Diagnosis & Comments'),
                  ],
                ),
              ),
            ),

            // Main Content Area
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.all(12),
                children: [
                  // Fast Bulk Action Bar
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          _selectedCategoryFilter == 'DEFECTS'
                              ? 'Flagged Defects (${displayedItems.length})'
                              : 'Inspection Points (${displayedItems.length})',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (!_isReadOnly)
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            backgroundColor: const Color(0xFFF0FDF4),
                          ),
                          icon: const Icon(Icons.flash_on, size: 14, color: Color(0xFF16A34A)),
                          label: const Text('Mark Remaining as OK', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF15803D))),
                          onPressed: _markAllRemainingAsOk,
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFFA7F3D0)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.lock, size: 12, color: Color(0xFF059669)),
                              SizedBox(width: 4),
                              Text('Read-Only View', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF047857))),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (_selectedCategoryFilter == 'TYRE_TABLE')
                    _buildTyreTableWidget()
                  else if (_selectedCategoryFilter == 'SUMMARY')
                    _buildDiagnosisSummaryWidget()
                  else if (displayedItems.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                      child: const Center(
                        child: Text('No items match the selected filter.', style: TextStyle(color: Colors.grey)),
                      ),
                    )
                  else
                    ...displayedItems.map((item) => _buildChecklistItemCard(item)),

                  const SizedBox(height: 16),
                  _buildDiagnosisSummaryWidget(),
                  const SizedBox(height: 80),
                ],
              ),
            ),

            // Sticky Bottom Action Bar
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2)),
                ],
              ),
              child: SafeArea(
                child: _isReadOnly
                    ? Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF15803D),
                                side: const BorderSide(color: Color(0xFF86EFAC)),
                                backgroundColor: const Color(0xFFF0FDF4),
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: const Icon(Icons.print_outlined, size: 17, color: Color(0xFF15803D)),
                              label: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('Print / Preview PMS PDF', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF15803D))),
                              ),
                              onPressed: _openPdfPreview,
                            ),
                          ),
                          if (AuthService.instance.isOwner || AuthService.instance.isManager || AuthService.instance.isAdvisor) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFD97706),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 11),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                icon: _isSaving
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                    : const Icon(Icons.lock_open, size: 17),
                                label: const FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text('Unlock Sheet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                                ),
                                onPressed: _isSaving ? null : _unlockChecksheet,
                              ),
                            ),
                          ],
                          const SizedBox(width: 6),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                            tooltip: 'Close',
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: const Icon(Icons.save_outlined, size: 16),
                              label: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('Save Draft', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              ),
                              onPressed: _isSaving ? null : () => _saveChecklist(submitToAdvisor: false),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF15803D),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                elevation: 2,
                              ),
                              icon: _isSaving
                                  ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : const Icon(Icons.send_rounded, size: 16),
                              label: const FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text('Send to Advisor', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                              ),
                              onPressed: _isSaving ? null : _confirmSubmitToAdvisor,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String filterKey, String label, {bool isHighlight = false}) {
    final sel = _selectedCategoryFilter == filterKey;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: sel ? Colors.white : (isHighlight ? Colors.red.shade900 : Colors.black87))),
        selected: sel,
        selectedColor: isHighlight ? Colors.red.shade800 : const Color(0xFF1E3A8A),
        backgroundColor: isHighlight ? Colors.red.shade50 : const Color(0xFFF1F5F9),
        onSelected: (_) => setState(() => _selectedCategoryFilter = filterKey),
      ),
    );
  }

  List<PmsChecklistItem> _getFilteredItems() {
    if (_selectedCategoryFilter == 'ALL') {
      return _checksheet.items;
    }
    if (_selectedCategoryFilter == 'DEFECTS') {
      return _checksheet.defects;
    }
    return _checksheet.items.where((i) => i.category == _selectedCategoryFilter).toList();
  }

  Widget _buildChecklistItemCard(PmsChecklistItem item) {
    final isPeriodic = item.category == 'Periodic Maintenance Items';
    final hasDefect = item.isDefect;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: item.status == PmsItemStatus.ng
              ? Colors.red.shade300
              : (item.status == PmsItemStatus.caution ? Colors.amber.shade300 : const Color(0xFFE2E8F0)),
          width: hasDefect ? 1.5 : 1,
        ),
      ),
      color: item.status == PmsItemStatus.ng
          ? const Color(0xFFFEF2F2)
          : (item.status == PmsItemStatus.caution ? const Color(0xFFFFFBEB) : Colors.white),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Item Header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E3A8A).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '#${item.itemNumber}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFF1E3A8A)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.description,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                      ),
                      if (item.standardValue != null)
                        Text(
                          'Standard: ${item.standardValue}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Rating Buttons Bar
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // Standard OK / Pass button
                  _statusButton(
                    label: 'OK',
                    subtext: 'Checked & OK',
                    color: Colors.green,
                    isSelected: item.status == PmsItemStatus.ok,
                    onTap: () => setState(() => item.status = PmsItemStatus.ok),
                  ),
                  const SizedBox(width: 6),

                  // Caution button
                  _statusButton(
                    label: 'C',
                    subtext: 'Caution',
                    color: Colors.amber,
                    isSelected: item.status == PmsItemStatus.caution,
                    onTap: () => setState(() => item.status = PmsItemStatus.caution),
                  ),
                  const SizedBox(width: 6),

                  // Immediate NG button
                  _statusButton(
                    label: 'NG',
                    subtext: 'Immediate Defect',
                    color: Colors.red,
                    isSelected: item.status == PmsItemStatus.ng,
                    onTap: () => setState(() => item.status = PmsItemStatus.ng),
                  ),

                  // Periodic PMS specific actions
                  if (isPeriodic) ...[
                    const SizedBox(width: 6),
                    _statusButton(
                      label: 'R',
                      subtext: 'Replace',
                      color: Colors.blue,
                      isSelected: item.status == PmsItemStatus.replace,
                      onTap: () => setState(() => item.status = PmsItemStatus.replace),
                    ),
                    const SizedBox(width: 6),
                    _statusButton(
                      label: 'L',
                      subtext: 'Grease',
                      color: Colors.purple,
                      isSelected: item.status == PmsItemStatus.grease,
                      onTap: () => setState(() => item.status = PmsItemStatus.grease),
                    ),
                  ],
                ],
              ),
            ),

            // If Defect (NG or C), show diagnosis details input
            if (hasDefect) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: item.status == PmsItemStatus.ng ? Colors.red.shade200 : Colors.amber.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.status == PmsItemStatus.ng
                          ? '🔴 Immediate Attention Required (NG):'
                          : '🟡 Further Attention / Caution Noted (C):',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: item.status == PmsItemStatus.ng ? Colors.red.shade900 : Colors.amber.shade900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      initialValue: item.defectDescription ?? item.remarks,
                      readOnly: _isReadOnly,
                      decoration: InputDecoration(
                        labelText: 'Defect Observation / Failure Details *',
                        hintText: 'e.g. Lining worn below limit, leaking axle seal',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        item.defectDescription = v;
                        item.remarks = v;
                      },
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: item.recommendedFix,
                      readOnly: _isReadOnly,
                      decoration: const InputDecoration(
                        labelText: 'Recommended Repair / Action for Customer *',
                        hintText: 'e.g. Replace rear brake shoes, skim drum, replace hub seals',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => item.recommendedFix = v,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: item.partsNeeded,
                            readOnly: _isReadOnly,
                            decoration: const InputDecoration(
                              labelText: 'Parts Needed',
                              hintText: 'e.g. Brake shoe set',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (v) => item.partsNeeded = v,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            initialValue: item.estimatedParts > 0 ? item.estimatedParts.toStringAsFixed(0) : '',
                            readOnly: _isReadOnly,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Est. Parts (KES)',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (v) => item.estimatedParts = double.tryParse(v) ?? 0.0,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            initialValue: item.estimatedLabour > 0 ? item.estimatedLabour.toStringAsFixed(0) : '',
                            readOnly: _isReadOnly,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Est. Labour (KES)',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (v) => item.estimatedLabour = double.tryParse(v) ?? 0.0,
                          ),
                        ),
                      ],
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

  Widget _statusButton({
    required String label,
    required String subtext,
    required MaterialColor color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: _isReadOnly
          ? () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('🔒 Inspection is complete and locked. Altering status is restricted to prevent tampering.'),
                  duration: Duration(seconds: 2),
                  backgroundColor: Color(0xFF1E293B),
                ),
              );
            }
          : onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.shade700 : color.shade50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? color.shade800 : color.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isReadOnly && isSelected) ...[
              const Icon(Icons.check, size: 12, color: Colors.white),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: isSelected ? Colors.white : color.shade900,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              subtext,
              style: TextStyle(
                fontSize: 10,
                color: isSelected ? Colors.white.withValues(alpha: 0.9) : color.shade800,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTyreTableWidget() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.tire_repair, size: 18, color: Color(0xFF1E3A8A)),
                SizedBox(width: 6),
                Text(
                  'Tyre Pressure (PSI) & Tread Depth (mm) Table',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Limit: Pressure > 32 PSI (or placard) • Tread Depth > 2.0 mm (Wear Indicator Limit)',
              style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
            const Divider(height: 16),
            ..._checksheet.tyres.map((tyre) {
              final isUnderInflated = (tyre.pressurePsi ?? 35) < tyre.pressureLimitPsi;
              final isWornOut = (tyre.treadDepthMm ?? 6) < tyre.treadLimitMm;
              final hasIssue = isUnderInflated || isWornOut;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: hasIssue ? const Color(0xFFFEF2F2) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: hasIssue ? Colors.red.shade200 : const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          tyre.position,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: hasIssue ? Colors.red.shade900 : const Color(0xFF1E293B),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          initialValue: tyre.pressurePsi?.toString() ?? '',
                          readOnly: _isReadOnly,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'PSI',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) {
                            setState(() {
                              tyre.pressurePsi = double.tryParse(v);
                              if (tyre.pressurePsi != null && tyre.pressurePsi! < tyre.pressureLimitPsi) {
                                tyre.status = PmsItemStatus.caution;
                              }
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          initialValue: tyre.treadDepthMm?.toString() ?? '',
                          readOnly: _isReadOnly,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Tread mm',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) {
                            setState(() {
                              tyre.treadDepthMm = double.tryParse(v);
                              if (tyre.treadDepthMm != null && tyre.treadDepthMm! < tyre.treadLimitMm) {
                                tyre.status = PmsItemStatus.ng;
                              }
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosisSummaryWidget() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.assessment_outlined, size: 18, color: Color(0xFF1E3A8A)),
                SizedBox(width: 6),
                Text(
                  'Diagnostic Readings, Complaints & Summary',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                ),
              ],
            ),
            const Divider(height: 16),

            // Battery Voltages
            Text(
              'Battery Test (${_checksheet.battery.is24VSystem ? "24V Dual System" : "12V System"}):',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: _checksheet.battery.battery1Voltage?.toString() ?? '',
                    readOnly: _isReadOnly,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Batt 1 (V) [>11.5V]',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) {
                      _checksheet.battery.battery1Voltage = double.tryParse(v);
                      _updateTotalVoltage();
                    },
                  ),
                ),
                if (_checksheet.battery.is24VSystem) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      initialValue: _checksheet.battery.battery2Voltage?.toString() ?? '',
                      readOnly: _isReadOnly,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Batt 2 (V) [>11.5V]',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        _checksheet.battery.battery2Voltage = double.tryParse(v);
                        _updateTotalVoltage();
                      },
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: _checksheet.battery.totalVoltage?.toString() ?? '',
                    readOnly: _isReadOnly,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: _checksheet.battery.is24VSystem ? 'Total (V) [>23V]' : 'Total (V) [>12.4V]',
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) => _checksheet.battery.totalVoltage = double.tryParse(v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Odometer & Customer Complaints
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _mileageCtrl,
                    readOnly: _isReadOnly,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Current Mileage (km) *',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: ['Empty', '1/4', 'Half', '3/4', 'Full'].contains(_checksheet.fuelLevel)
                        ? _checksheet.fuelLevel
                        : 'Half',
                    decoration: const InputDecoration(
                      labelText: 'Fuel Level',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: ['Empty', '1/4', 'Half', '3/4', 'Full']
                        .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                        .toList(),
                    onChanged: _isReadOnly
                        ? null
                        : (v) {
                            if (v != null) _checksheet.fuelLevel = v;
                          },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _complaintsCtrl,
              readOnly: _isReadOnly,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Customer Complaints / Intake Requests',
                hintText: 'Customer reported symptoms or specific requested repairs',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),

            TextFormField(
              controller: _techCommentsCtrl,
              readOnly: _isReadOnly,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Technician Diagnostic Summary & Overall Comments *',
                hintText: 'e.g. Engine performance normal. Brakes require urgent overhaul.',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _updateTotalVoltage() {
    final b1 = _checksheet.battery.battery1Voltage ?? 0;
    final b2 = _checksheet.battery.battery2Voltage ?? 0;
    if (_checksheet.battery.is24VSystem) {
      if (b1 > 0 && b2 > 0) {
        setState(() {
          _checksheet.battery.totalVoltage = double.parse((b1 + b2).toStringAsFixed(1));
        });
      }
    } else {
      if (b1 > 0) {
        setState(() {
          _checksheet.battery.totalVoltage = b1;
        });
      }
    }
  }
}
