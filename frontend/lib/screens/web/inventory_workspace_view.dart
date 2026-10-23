import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'url_opener_stub.dart' if (dart.library.html) 'url_opener_web.dart';

class InventoryWorkspaceView extends StatefulWidget {
  final String activeUserRole;
  final String activeUserName;
  final VoidCallback onDataChanged;

  const InventoryWorkspaceView({
    Key? key,
    required this.activeUserRole,
    required this.activeUserName,
    required this.onDataChanged,
  }) : super(key: key);

  @override
  State<InventoryWorkspaceView> createState() => _InventoryWorkspaceViewState();
}

class _InventoryWorkspaceViewState extends State<InventoryWorkspaceView> with SingleTickerProviderStateMixin {
  static const String _baseUrl = 'https://auto.zksms.online/api';

  late TabController _tabController;
  bool _isLoading = false;

  // Data collections
  List<dynamic> _requests = [];
  List<dynamic> _parts = [];
  List<dynamic> _tools = [];
  List<dynamic> _consumables = [];
  List<dynamic> _returns = [];
  List<dynamic> _stockCounts = [];
  List<dynamic> _transactions = [];
  Map<String, dynamic> _summary = {};

  String _requestFilter = 'ALL';
  String _toolFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    _fetchAllInventoryData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'x-user-role': widget.activeUserRole,
        'x-user-name': widget.activeUserName,
      };

  Future<void> _fetchAllInventoryData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        http.get(Uri.parse('$_baseUrl/inventory/requests'), headers: _headers),
        http.get(Uri.parse('$_baseUrl/parts')),
        http.get(Uri.parse('$_baseUrl/inventory/assets'), headers: _headers),
        http.get(Uri.parse('$_baseUrl/inventory/items'), headers: _headers),
        http.get(Uri.parse('$_baseUrl/inventory/returns'), headers: _headers),
        http.get(Uri.parse('$_baseUrl/inventory/stockcounts'), headers: _headers),
        http.get(Uri.parse('$_baseUrl/inventory/reports/summary'), headers: _headers),
        http.get(Uri.parse('$_baseUrl/inventory/transactions?limit=100'), headers: _headers),
      ]);

      if (mounted) {
        setState(() {
          if (results[0].statusCode == 200) _requests = json.decode(results[0].body);
          if (results[1].statusCode == 200) _parts = json.decode(results[1].body);
          if (results[2].statusCode == 200) _tools = json.decode(results[2].body);
          if (results[3].statusCode == 200) _consumables = json.decode(results[3].body);
          if (results[4].statusCode == 200) _returns = json.decode(results[4].body);
          if (results[5].statusCode == 200) _stockCounts = json.decode(results[5].body);
          if (results[6].statusCode == 200) _summary = json.decode(results[6].body);
          if (results[7].statusCode == 200) _transactions = json.decode(results[7].body);
        });
      }
    } catch (e) {
      debugPrint('Error fetching inventory: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _toast(String msg, {Color color = Colors.green}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: color, content: Text(msg)));
  }

  void _downloadCsv(String reportType) {
    final url = '$_baseUrl/inventory/reports/export?report=$reportType';
    openUrlInNewTab(url);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row with Title, Refresh & CSV Export
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: Row(
              children: [
                const Icon(Icons.inventory_2, color: Color(0xFF0F4C81), size: 28),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Workshop Inventory & Storekeeper Hub', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                    Text(
                      'Distinguishing Spare Parts for Sale, Company Tools & Equipment, and Internal Consumables',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  tooltip: 'Export Inventory Reports (CSV)',
                  icon: const Icon(Icons.download, color: Color(0xFF0F4C81)),
                  onSelected: _downloadCsv,
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(value: 'transactions', child: Text('Export All Transactions (CSV)')),
                    const PopupMenuItem(value: 'balances', child: Text('Export Stock Balances (CSV)')),
                    const PopupMenuItem(value: 'partsByJob', child: Text('Export Spare Parts per Job (CSV)')),
                    const PopupMenuItem(value: 'consumables', child: Text('Export Consumables by Dept (CSV)')),
                    const PopupMenuItem(value: 'toolsAssigned', child: Text('Export Assigned Tools (CSV)')),
                  ],
                ),
                IconButton(
                  tooltip: 'Refresh Inventory',
                  icon: const Icon(Icons.refresh, color: Color(0xFF0F4C81)),
                  onPressed: _fetchAllInventoryData,
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: const Color(0xFF0F4C81),
            unselectedLabelColor: Colors.black54,
            indicatorColor: const Color(0xFF0F4C81),
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            tabs: [
              Tab(
                child: Row(
                  children: [
                    const Icon(Icons.assignment_turned_in_outlined, size: 16),
                    const SizedBox(width: 6),
                    Text('Item Requests (${_requests.where((r) => r['status'] == 'PENDING').length} pending)'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  children: [
                    const Icon(Icons.car_repair, size: 16),
                    const SizedBox(width: 6),
                    Text('Spare Parts (${_parts.length})'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  children: [
                    const Icon(Icons.build_circle_outlined, size: 16),
                    const SizedBox(width: 6),
                    Text('Tools & Equipment (${_tools.length})'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  children: [
                    const Icon(Icons.cleaning_services_outlined, size: 16),
                    const SizedBox(width: 6),
                    Text('Consumables (${_consumables.length})'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  children: [
                    const Icon(Icons.assignment_return_outlined, size: 16),
                    const SizedBox(width: 6),
                    Text('Returns & QC (${_returns.where((r) => r['status'] == 'PENDING_INSPECTION').length})'),
                  ],
                ),
              ),
              const Tab(
                child: Row(
                  children: [
                    Icon(Icons.fact_check_outlined, size: 16),
                    SizedBox(width: 6),
                    Text('Stocktaking'),
                  ],
                ),
              ),
              const Tab(
                child: Row(
                  children: [
                    Icon(Icons.history_edu_outlined, size: 16),
                    SizedBox(width: 6),
                    Text('Audit Ledger & Valuation'),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 1),
          if (_isLoading)
            const SizedBox(height: 300, child: Center(child: CircularProgressIndicator()))
          else
            SizedBox(
              height: 650,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildRequestsTab(),
                  _buildSparePartsTab(),
                  _buildToolsTab(),
                  _buildConsumablesTab(),
                  _buildReturnsTab(),
                  _buildStocktakeTab(),
                  _buildAuditLedgerTab(),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 1: STOREKEEPER ITEM REQUESTS & ISSUANCE
  // ===========================================================================
  Widget _buildRequestsTab() {
    final filtered = _requests.where((r) {
      if (_requestFilter == 'ALL') return true;
      return (r['status'] ?? '').toString().toUpperCase() == _requestFilter;
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Wrap(
                spacing: 8,
                children: ['ALL', 'PENDING', 'ORDERED', 'APPROVED', 'PARTIALLY_ISSUED', 'ISSUED', 'REJECTED']
                    .map((s) => ChoiceChip(
                          label: Text(s.replaceAll('_', ' '), style: const TextStyle(fontSize: 11)),
                          selected: _requestFilter == s,
                          onSelected: (_) => setState(() => _requestFilter = s),
                        ))
                    .toList(),
              ),
              const Spacer(),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F4C81),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New Vehicle Requisition'),
                onPressed: () => _showCreateRequisitionDialog(),
              ),
              const SizedBox(width: 12),
              Text('Showing ${filtered.length} requests', style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('No item requests matching the selected filter.', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _buildRequestCard(filtered[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(dynamic req) {
    final status = (req['status'] ?? 'PENDING').toString();
    final lines = (req['lines'] as List<dynamic>?) ?? [];
    final ref = req['reference'] ?? 'REQ';
    final tech = req['technicianName'] ?? 'Technician';
    final reason = req['reason'] ?? '-';
    final isPending = status == 'PENDING';
    final isApprovedOrPartial = status == 'APPROVED' || status == 'PARTIALLY_ISSUED';
    final isAcknowledged = req['acknowledgedAt'] != null;

    Color badgeColor = Colors.grey;
    if (status == 'PENDING') badgeColor = Colors.amber.shade800;
    if (status == 'ORDERED') badgeColor = Colors.indigo.shade700;
    if (status == 'APPROVED') badgeColor = Colors.blue.shade700;
    if (status == 'PARTIALLY_ISSUED') badgeColor = Colors.cyan.shade700;
    if (status == 'ISSUED') badgeColor = Colors.green.shade700;
    if (status == 'REJECTED') badgeColor = Colors.red.shade700;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(ref, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(color: badgeColor.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                child: Text(status.replaceAll('_', ' '), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: badgeColor)),
              ),
              const SizedBox(width: 10),
              Text('by $tech • ${req['department'] ?? 'Workshop'}', style: const TextStyle(color: Colors.black54, fontSize: 13)),
              const Spacer(),
              if (isPending) ...[
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  icon: const Icon(Icons.cancel, size: 16),
                  label: const Text('Reject'),
                  onPressed: () => _showDecisionDialog(req, isReject: true),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.amber.shade900),
                  icon: const Icon(Icons.shopping_cart, size: 16),
                  label: const Text('Order (PO Needed)'),
                  onPressed: () => _showOrderDialog(req),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F4C81), foregroundColor: Colors.white),
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text('Review & Approve'),
                  onPressed: () => _showDecisionDialog(req, isReject: false),
                ),
              ],
              if (status == 'ORDERED')
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade800, foregroundColor: Colors.white),
                  icon: const Icon(Icons.inventory_2_outlined, size: 16),
                  label: const Text('Mark Received in Store'),
                  onPressed: () => _showReceiveOrderDialog(req),
                ),
              if (isApprovedOrPartial)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
                  icon: const Icon(Icons.outbox, size: 16),
                  label: const Text('Physically Issue Items'),
                  onPressed: () => _showIssueItemsDialog(req),
                ),
            ],
          ),
          if (req['vehiclePlate'] != null || req['jobNumber'] != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.blueGrey.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.directions_car, size: 14, color: Color(0xFF0F4C81)),
                  const SizedBox(width: 6),
                  Text(
                    'Vehicle: ${req['vehiclePlate'] ?? 'N/A'}${req['vehicleDescription'] != null ? ' (${req['vehicleDescription']})' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF0F4C81)),
                  ),
                  if (req['jobNumber'] != null) ...[
                    const SizedBox(width: 8),
                    Text('• ${req['jobNumber']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.black87)),
                  ],
                ],
              ),
            ),
          ],
          if (status == 'ORDERED' && req['decisionNotes'] != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Row(
                children: [
                  const Icon(Icons.local_shipping, size: 16, color: Colors.brown),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Procurement / PO: ${req['decisionNotes']}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.brown),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text('Reason: $reason', style: const TextStyle(fontSize: 13)),
          if (req['jobCardId'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Linked to Job Card: ${req['jobCardId']}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ),
          const Divider(height: 20),
          const Text('Requested Lines:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 6),
          ...lines.map((l) {
            final cat = (l['category'] ?? 'SPARE_PART').toString();
            final desc = l['description'] ?? 'Item';
            final qReq = l['qtyRequested'] ?? 0;
            final qApp = l['qtyApproved'] ?? 0;
            final qIss = l['qtyIssued'] ?? 0;
            final qRet = l['qtyReturned'] ?? 0;

            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(6)),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: cat == 'TOOL_EQUIPMENT' ? Colors.purple.shade50 : cat == 'CONSUMABLE' ? Colors.teal.shade50 : Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      cat == 'TOOL_EQUIPMENT' ? 'TOOL' : cat == 'CONSUMABLE' ? 'CONSUMABLE' : 'SPARE PART',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: cat == 'TOOL_EQUIPMENT' ? Colors.purple.shade800 : cat == 'CONSUMABLE' ? Colors.teal.shade800 : Colors.blue.shade800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(desc, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                  Text('Requested: $qReq  |  Approved: $qApp  |  Issued: $qIss  |  Returned: $qRet', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                ],
              ),
            );
          }).toList(),
          if (isAcknowledged)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  const Icon(Icons.verified, size: 14, color: Colors.green),
                  const SizedBox(width: 4),
                  Text('Physical receipt confirmed by ${req['acknowledgedBy']} at ${req['acknowledgedAt']}', style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _showDecisionDialog(dynamic req, {required bool isReject}) {
    final notesCtrl = TextEditingController(text: isReject ? 'Not currently in stock' : 'Approved for workshop repair');
    final lines = (req['lines'] as List<dynamic>?) ?? [];
    final Map<String, TextEditingController> qtyCtrls = {
      for (final l in lines) l['id'].toString(): TextEditingController(text: (l['qtyRequested'] ?? 1).toString()),
    };

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isReject ? 'Reject Item Request (${req['reference']})' : 'Review & Approve Request (${req['reference']})'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isReject) ...[
                  const Text('Note: Approving does NOT deduct stock. Stock is deducted only during physical issuance.', style: TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  const Text('Adjust approved quantities if approving partially:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  ...lines.map((l) {
                    final lid = l['id'].toString();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(child: Text(l['description'] ?? '', style: const TextStyle(fontSize: 13))),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 100,
                            child: TextField(
                              controller: qtyCtrls[lid],
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(labelText: 'Approve (max ${l['qtyRequested']})', border: const OutlineInputBorder()),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Decision Notes *', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: isReject ? Colors.red : const Color(0xFF0F4C81), foregroundColor: Colors.white),
            onPressed: () async {
              try {
                final body = <String, dynamic>{
                  'action': isReject ? 'REJECT' : 'APPROVE',
                  'notes': notesCtrl.text.trim(),
                };
                if (!isReject) {
                  final partialLines = lines.map((l) {
                    final lid = l['id'].toString();
                    return {'lineId': lid, 'qtyApproved': int.tryParse(qtyCtrls[lid]?.text ?? '0') ?? 0};
                  }).toList();
                  body['action'] = 'PARTIAL';
                  body['lines'] = partialLines;
                }
                final res = await http.post(
                  Uri.parse('$_baseUrl/inventory/requests/${req['id']}/decision'),
                  headers: _headers,
                  body: json.encode(body),
                );
                if (res.statusCode == 200) {
                  if (ctx.mounted) Navigator.pop(ctx);
                  _toast(isReject ? 'Request rejected' : 'Request approved! Ready for physical store issuance.', color: Colors.green);
                  _fetchAllInventoryData();
                  widget.onDataChanged();
                } else {
                  final err = json.decode(res.body)['error'] ?? 'Decision failed';
                  _toast(err, color: Colors.red);
                }
              } catch (e) {
                _toast('Error: $e', color: Colors.red);
              }
            },
            child: Text(isReject ? 'Confirm Rejection' : 'Confirm Approval'),
          ),
        ],
      ),
    );
  }

  void _showOrderDialog(dynamic req) {
    final supplierCtrl = TextEditingController(text: 'AutoXpress / DT Dobie');
    final poCtrl = TextEditingController(text: 'PO-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}');
    final etaCtrl = TextEditingController(text: 'Tomorrow 10:00 AM');
    final costCtrl = TextEditingController(text: '0');
    final notesCtrl = TextEditingController(text: 'Out of stock in main store; ordered externally for vehicle');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.shopping_cart, color: Colors.amber),
            const SizedBox(width: 8),
            Expanded(child: Text('Order from Supplier (${req['reference']})')),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Target Vehicle: ${req['vehiclePlate'] ?? req['vehicleId'] ?? 'N/A'}${req['jobNumber'] != null ? ' (${req['jobNumber']})' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.brown),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Technician: ${req['technicianName']} • ${((req['lines'] as List?) ?? []).length} item(s) requested',
                        style: const TextStyle(fontSize: 12, color: Colors.black87),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: supplierCtrl,
                  decoration: const InputDecoration(labelText: 'Target Supplier * (e.g. AutoXpress, Toyopet Spares)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: poCtrl,
                        decoration: const InputDecoration(labelText: 'PO / Ref Number', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: etaCtrl,
                        decoration: const InputDecoration(labelText: 'Expected Delivery (ETA)', border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: costCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Estimated Total Cost (KES)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Procurement Notes', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade800, foregroundColor: Colors.white),
            icon: const Icon(Icons.send, size: 16),
            label: const Text('Initiate Supplier Order'),
            onPressed: () async {
              try {
                final res = await http.post(
                  Uri.parse('$_baseUrl/inventory/requests/${req['id']}/decision'),
                  headers: _headers,
                  body: json.encode({
                    'action': 'ORDER',
                    'supplierName': supplierCtrl.text.trim(),
                    'poNumber': poCtrl.text.trim(),
                    'expectedArrival': etaCtrl.text.trim(),
                    'estimatedCost': double.tryParse(costCtrl.text.trim()) ?? 0,
                    'notes': notesCtrl.text.trim(),
                  }),
                );
                if (res.statusCode == 200) {
                  if (ctx.mounted) Navigator.pop(ctx);
                  _toast('Order placed with ${supplierCtrl.text.trim()}! Technician & manager notified.', color: Colors.green);
                  _fetchAllInventoryData();
                  widget.onDataChanged();
                } else {
                  final err = json.decode(res.body)['error'] ?? 'Order failed';
                  _toast(err, color: Colors.red);
                }
              } catch (e) {
                _toast('Error: $e', color: Colors.red);
              }
            },
          ),
        ],
      ),
    );
  }

  void _showReceiveOrderDialog(dynamic req) {
    final notesCtrl = TextEditingController(text: 'Parts physically verified and received at Main Store. Ready for collection.');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Receive Ordered Parts (${req['reference']})'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Vehicle: ${req['vehiclePlate'] ?? 'N/A'}${req['jobNumber'] != null ? ' (${req['jobNumber']})' : ''}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text('Technician: ${req['technicianName']}'),
              const SizedBox(height: 8),
              if (req['decisionNotes'] != null)
                Text('Order Details: ${req['decisionNotes']}', style: const TextStyle(fontSize: 12, color: Colors.brown)),
              const SizedBox(height: 14),
              const Text(
                'Confirming receipt marks this requisition as APPROVED and notifies the technician to collect parts.',
                style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(labelText: 'Receiving Notes', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
            icon: const Icon(Icons.check_circle, size: 16),
            label: const Text('Confirm Received in Store'),
            onPressed: () async {
              try {
                final res = await http.post(
                  Uri.parse('$_baseUrl/inventory/requests/${req['id']}/decision'),
                  headers: _headers,
                  body: json.encode({
                    'action': 'RECEIVE_ORDER',
                    'notes': notesCtrl.text.trim(),
                  }),
                );
                if (res.statusCode == 200) {
                  if (ctx.mounted) Navigator.pop(ctx);
                  _toast('Parts received into store and approved for issuance!', color: Colors.green);
                  _fetchAllInventoryData();
                  widget.onDataChanged();
                } else {
                  final err = json.decode(res.body)['error'] ?? 'Receipt failed';
                  _toast(err, color: Colors.red);
                }
              } catch (e) {
                _toast('Error: $e', color: Colors.red);
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateRequisitionDialog({String? preselectedJobId, String? preselectedVehiclePlate}) async {
    List<dynamic> activeJobs = [];
    try {
      final res = await http.get(Uri.parse('$_baseUrl/jobs'), headers: _headers);
      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);
        if (decoded is List) activeJobs = decoded;
      }
    } catch (_) {}

    String? selectedJobId = preselectedJobId;
    bool isCustomItem = false;
    Map<String, dynamic>? selectedItem;
    List<dynamic> catalogResults = [];
    final customDescCtrl = TextEditingController();
    String customCategory = 'SPARE_PART';
    final qtyCtrl = TextEditingController(text: '1');
    final reasonCtrl = TextEditingController();
    final techNameCtrl = TextEditingController(text: widget.activeUserName.isNotEmpty ? widget.activeUserName : 'Technician');

    if (context.mounted) {
      showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setModalState) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.inventory_2_outlined, color: Color(0xFF0F4C81)),
                SizedBox(width: 8),
                Text('New Vehicle Part / Item Requisition'),
              ],
            ),
            content: SizedBox(
              width: 540,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedJobId,
                      decoration: const InputDecoration(
                        labelText: 'Assign to Vehicle / Job Card *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.directions_car),
                      ),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('-- General Workshop (No Vehicle Assigned) --')),
                        ...activeJobs.map((j) {
                          final plate = j['vehicle']?['registrationNo'] ?? j['vehiclePlate'] ?? 'Vehicle';
                          final make = j['vehicle']?['make'] ?? '';
                          final model = j['vehicle']?['model'] ?? '';
                          final jNo = j['jobNumber'] ?? j['id'].toString().substring(0, 8).toUpperCase();
                          return DropdownMenuItem<String>(
                            value: j['id'].toString(),
                            child: Text('$plate ${make.isNotEmpty ? "($make $model)" : ""} • $jNo', style: const TextStyle(fontSize: 13)),
                          );
                        }),
                      ],
                      onChanged: (v) => setModalState(() => selectedJobId = v),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: techNameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Technician / Requester Name *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setModalState(() => isCustomItem = false),
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
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: !isCustomItem ? Colors.white : Colors.black87),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            onTap: () => setModalState(() => isCustomItem = true),
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
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isCustomItem ? Colors.white : Colors.black87),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (!isCustomItem) ...[
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Search stock catalog by name or part #...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onChanged: (q) async {
                          if (q.length < 2) { setModalState(() => catalogResults = []); return; }
                          try {
                            final res = await http.get(Uri.parse('$_baseUrl/inventory/catalog?search=$q'), headers: _headers);
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
                                subtitle: Text('Stock: ${item['quantity'] ?? 0}  |  ${item['category']}  |  ${item['location'] ?? 'Main Store'}', style: const TextStyle(fontSize: 11)),
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
                          decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.green.shade200)),
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
                        decoration: const InputDecoration(labelText: 'Part / Supply Name * (e.g. Brake Caliper Kit)', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: customCategory,
                        decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 'SPARE_PART', child: Text('Spare Part (Vehicle Repair)')),
                          DropdownMenuItem(value: 'CONSUMABLE', child: Text('Workshop Consumable')),
                          DropdownMenuItem(value: 'TOOL_EQUIPMENT', child: Text('Tool / Special Equipment')),
                        ],
                        onChanged: (v) => setModalState(() => customCategory = v ?? 'SPARE_PART'),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: qtyCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Quantity Required *', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: reasonCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Reason for Request *',
                        hintText: 'e.g. Replacement needed during 50,000 km service',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F4C81), foregroundColor: Colors.white),
                icon: const Icon(Icons.send, size: 16),
                label: const Text('Submit Requisition'),
                onPressed: () async {
                  if (!isCustomItem && selectedItem == null) {
                    _toast('Please select an item from catalog or switch to Custom Item', color: Colors.orange);
                    return;
                  }
                  if (isCustomItem && customDescCtrl.text.trim().isEmpty) {
                    _toast('Please enter part description', color: Colors.orange);
                    return;
                  }
                  if (reasonCtrl.text.trim().isEmpty) {
                    _toast('Please provide a reason', color: Colors.orange);
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
                    'technicianName': techNameCtrl.text.trim(),
                    'lines': [line],
                  };
                  if (selectedJobId != null) body['jobCardId'] = selectedJobId;

                  try {
                    final res = await http.post(
                      Uri.parse('$_baseUrl/inventory/requests'),
                      headers: _headers,
                      body: json.encode(body),
                    );
                    if (res.statusCode == 201) {
                      if (ctx.mounted) Navigator.pop(ctx);
                      _toast('Requisition submitted successfully! Tracking under vehicle.', color: Colors.green);
                      _fetchAllInventoryData();
                      widget.onDataChanged();
                    } else {
                      final err = json.decode(res.body)['error'] ?? 'Submission failed';
                      _toast(err, color: Colors.red);
                    }
                  } catch (e) {
                    _toast('Error: $e', color: Colors.red);
                  }
                },
              ),
            ],
          ),
        ),
      );
    }
  }

  void _showIssueItemsDialog(dynamic req) {
    final lines = ((req['lines'] as List<dynamic>?) ?? []).where((l) => (l['qtyApproved'] ?? 0) > (l['qtyIssued'] ?? 0)).toList();
    final receiverCtrl = TextEditingController(text: req['technicianName'] ?? '');
    final notesCtrl = TextEditingController(text: 'Issued from Main Store');
    final Map<String, TextEditingController> issueCtrls = {
      for (final l in lines) l['id'].toString(): TextEditingController(text: ((l['qtyApproved'] ?? 1) - (l['qtyIssued'] ?? 0)).toString()),
    };

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Physically Issue Items (${req['reference']})'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Stock will be deducted atomically from inventory upon physical issuance.', style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(
                  controller: receiverCtrl,
                  decoration: const InputDecoration(labelText: 'Receiving Employee / Technician *', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 14),
                const Text('Items to Issue:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...lines.map((l) {
                  final lid = l['id'].toString();
                  final outstanding = (l['qtyApproved'] ?? 0) - (l['qtyIssued'] ?? 0);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(child: Text('${l['description']}\n(Approved: ${l['qtyApproved']}, Still out: $outstanding)', style: const TextStyle(fontSize: 12))),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 100,
                          child: TextField(
                            controller: issueCtrls[lid],
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(labelText: 'Qty to Issue', border: const OutlineInputBorder()),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Issuance Notes', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
            onPressed: () async {
              try {
                final issueLines = lines.map((l) {
                  final lid = l['id'].toString();
                  return {'lineId': lid, 'quantity': int.tryParse(issueCtrls[lid]?.text ?? '0') ?? 0};
                }).where((x) => (x['quantity'] as int) > 0).toList();

                if (issueLines.isEmpty) {
                  _toast('Specify quantity to issue', color: Colors.orange);
                  return;
                }

                final res = await http.post(
                  Uri.parse('$_baseUrl/inventory/requests/${req['id']}/issue'),
                  headers: _headers,
                  body: json.encode({
                    'receivedBy': receiverCtrl.text.trim(),
                    'notes': notesCtrl.text.trim(),
                    'lines': issueLines,
                  }),
                );
                if (res.statusCode == 200) {
                  if (ctx.mounted) Navigator.pop(ctx);
                  _toast('Items physically issued! Stock deducted and logged to immutable audit ledger.', color: Colors.green);
                  _fetchAllInventoryData();
                  widget.onDataChanged();
                } else {
                  final err = json.decode(res.body)['error'] ?? 'Issuance failed';
                  _toast(err, color: Colors.red);
                }
              } catch (e) {
                _toast('Error: $e', color: Colors.red);
              }
            },
            child: const Text('Confirm Physical Issuance'),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 2: SPARE PARTS (RESALE & REPAIRS)
  // ===========================================================================
  Widget _buildSparePartsTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${_parts.length} Spare Parts in Database (Resale / Customer Vehicle Repairs)', style: const TextStyle(fontWeight: FontWeight.bold)),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F4C81), foregroundColor: Colors.white),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Spare Part'),
                onPressed: _showAddPartDialog,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: SingleChildScrollView(
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Part #', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Description', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Cost Price', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Selling Price', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Available Stock', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Quarantine (QC)', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Location', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: _parts.map((p) {
                  final qty = p['stockQuantity'] ?? 0;
                  final reorder = p['reorderLevel'] ?? 5;
                  final isLow = qty <= reorder;

                  return DataRow(
                    cells: [
                      DataCell(Text(p['partNumber'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text('${p['description'] ?? ''} ${p['brand'] != null ? '(${p['brand']})' : ''}')),
                      DataCell(Text('KES ${(p['costPrice'] ?? 0).toString()}')),
                      DataCell(Text('KES ${(p['unitPrice'] ?? 0).toString()}')),
                      DataCell(
                        Row(
                          children: [
                            Text(qty.toString(), style: TextStyle(fontWeight: FontWeight.bold, color: isLow ? Colors.red : Colors.black87)),
                            if (isLow) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.warning_amber, size: 14, color: Colors.red),
                            ],
                          ],
                        ),
                      ),
                      DataCell(Text((p['quarantineQuantity'] ?? 0).toString())),
                      DataCell(Text(p['location'] ?? 'Main Store')),
                      DataCell(
                        IconButton(
                          tooltip: 'Receive Stock',
                          icon: const Icon(Icons.add_box_outlined, color: Colors.blue),
                          onPressed: () => _showReceiveStockDialog(p, isSparePart: true),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddPartDialog() {
    final partNumCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final brandCtrl = TextEditingController();
    final costCtrl = TextEditingController(text: '0');
    final priceCtrl = TextEditingController(text: '0');
    final qtyCtrl = TextEditingController(text: '10');
    final locationCtrl = TextEditingController(text: 'Main Store');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Spare Part (For Vehicle Repairs & Resale)'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: partNumCtrl, decoration: const InputDecoration(labelText: 'Part Number *')),
                const SizedBox(height: 8),
                TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Description *')),
                const SizedBox(height: 8),
                TextField(controller: brandCtrl, decoration: const InputDecoration(labelText: 'Brand (e.g. Bosch, Toyota)')),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: TextField(controller: costCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cost Price (KES)'))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Selling Price (KES) *'))),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Initial Stock'))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: locationCtrl, decoration: const InputDecoration(labelText: 'Storage Location'))),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (descCtrl.text.trim().isEmpty || priceCtrl.text.trim().isEmpty) return;
              await http.post(
                Uri.parse('$_baseUrl/parts'),
                headers: _headers,
                body: json.encode({
                  'partNumber': partNumCtrl.text.trim().isEmpty ? 'PART-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}' : partNumCtrl.text.trim(),
                  'description': descCtrl.text.trim(),
                  'brand': brandCtrl.text.trim(),
                  'costPrice': double.tryParse(costCtrl.text.trim()) ?? 0,
                  'unitPrice': double.tryParse(priceCtrl.text.trim()) ?? 0,
                  'stockQuantity': int.tryParse(qtyCtrl.text.trim()) ?? 0,
                  'location': locationCtrl.text.trim(),
                }),
              );
              if (ctx.mounted) Navigator.pop(ctx);
              _toast('Spare part registered!');
              _fetchAllInventoryData();
              widget.onDataChanged();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 3: TOOLS & EQUIPMENT (COMPANY ASSETS)
  // ===========================================================================
  Widget _buildToolsTab() {
    final filtered = _tools.where((t) {
      if (_toolFilter == 'ALL') return true;
      return (t['status'] ?? '').toString().toUpperCase() == _toolFilter;
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Wrap(
                spacing: 8,
                children: ['ALL', 'AVAILABLE', 'CHECKED_OUT', 'FIXED', 'DAMAGED', 'LOST']
                    .map((s) => ChoiceChip(
                          label: Text(s.replaceAll('_', ' '), style: const TextStyle(fontSize: 11)),
                          selected: _toolFilter == s,
                          onSelected: (_) => setState(() => _toolFilter = s),
                        ))
                    .toList(),
              ),
              const Spacer(),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F4C81), foregroundColor: Colors.white),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Register Tool / Equipment Asset'),
                onPressed: _showRegisterAssetDialog,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: SingleChildScrollView(
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Asset #', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Equipment Name', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Condition', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Location', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Assigned To', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Cost', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: filtered.map((t) {
                  final status = (t['status'] ?? 'AVAILABLE').toString();
                  Color statusColor = Colors.green;
                  if (status == 'CHECKED_OUT') statusColor = Colors.orange;
                  if (status == 'FIXED') statusColor = Colors.blue;
                  if (status == 'DAMAGED' || status == 'LOST') statusColor = Colors.red;

                  return DataRow(
                    cells: [
                      DataCell(Text(t['assetNumber'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text('${t['name'] ?? ''} ${t['serialNumber'] != null ? '(${t['serialNumber']})' : ''}')),
                      DataCell(Text(t['condition'] ?? 'GOOD')),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: statusColor.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                          child: Text(status.replaceAll('_', ' '), style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                      ),
                      DataCell(Text(t['location'] ?? 'Main Store')),
                      DataCell(Text(t['assignedTo'] ?? '-')),
                      DataCell(Text('KES ${(t['cost'] ?? 0).toString()}')),
                      DataCell(
                        Row(
                          children: [
                            if (status == 'AVAILABLE')
                              IconButton(
                                tooltip: 'Check Out Equipment',
                                icon: const Icon(Icons.outbox, size: 18, color: Colors.blue),
                                onPressed: () => _showCheckoutAssetDialog(t),
                              ),
                            if (status == 'CHECKED_OUT')
                              IconButton(
                                tooltip: 'Return / Report Damage',
                                icon: const Icon(Icons.assignment_return, size: 18, color: Colors.green),
                                onPressed: () => _showReturnAssetDialog(t),
                              ),
                            IconButton(
                              tooltip: 'Assign / Relocate',
                              icon: const Icon(Icons.edit_location_alt, size: 18, color: Colors.black54),
                              onPressed: () => _showAssignAssetDialog(t),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showRegisterAssetDialog() {
    final assetNumCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final serialCtrl = TextEditingController();
    final costCtrl = TextEditingController(text: '0');
    final locCtrl = TextEditingController(text: 'Main Store');
    bool isFixed = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Register Company-Owned Tool or Equipment'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: assetNumCtrl, decoration: const InputDecoration(labelText: 'Unique Asset # (e.g. ASSET-001) *')),
                  const SizedBox(height: 8),
                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Equipment Name (e.g. Hydraulic Jack) *')),
                  const SizedBox(height: 8),
                  TextField(controller: serialCtrl, decoration: const InputDecoration(labelText: 'Serial Number (if applicable)')),
                  const SizedBox(height: 8),
                  TextField(controller: costCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Purchase Cost (KES)')),
                  const SizedBox(height: 8),
                  TextField(controller: locCtrl, decoration: const InputDecoration(labelText: 'Storage Location (e.g. Bay 2 Rack B)')),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    title: const Text('Fixed Heavy Equipment', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    subtitle: const Text('Lifts, wheel alignment machines, compressors (assigned permanently, not checked out daily)', style: TextStyle(fontSize: 11)),
                    value: isFixed,
                    onChanged: (v) => setDlg(() => isFixed = v ?? false),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (assetNumCtrl.text.trim().isEmpty || nameCtrl.text.trim().isEmpty) return;
                await http.post(
                  Uri.parse('$_baseUrl/inventory/assets'),
                  headers: _headers,
                  body: json.encode({
                    'assetNumber': assetNumCtrl.text.trim(),
                    'name': nameCtrl.text.trim(),
                    'serialNumber': serialCtrl.text.trim(),
                    'cost': double.tryParse(costCtrl.text.trim()) ?? 0,
                    'location': locCtrl.text.trim(),
                    'isFixed': isFixed,
                  }),
                );
                if (ctx.mounted) Navigator.pop(ctx);
                _toast('Equipment asset registered!');
                _fetchAllInventoryData();
              },
              child: const Text('Register Asset'),
            ),
          ],
        ),
      ),
    );
  }

  void _showCheckoutAssetDialog(dynamic asset) {
    final empCtrl = TextEditingController();
    final usedAtCtrl = TextEditingController(text: 'Bay 1');
    final reasonCtrl = TextEditingController(text: 'Vehicle diagnosis / repair');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Checkout Equipment: ${asset['name']}'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: empCtrl, decoration: const InputDecoration(labelText: 'Borrowing Employee / Technician *')),
              const SizedBox(height: 8),
              TextField(controller: usedAtCtrl, decoration: const InputDecoration(labelText: 'Where being used (Bay / Pit)')),
              const SizedBox(height: 8),
              TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'Reason for checkout')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (empCtrl.text.trim().isEmpty) return;
              await http.post(
                Uri.parse('$_baseUrl/inventory/assets/${asset['id']}/checkout'),
                headers: _headers,
                body: json.encode({
                  'employee': empCtrl.text.trim(),
                  'usedAt': usedAtCtrl.text.trim(),
                  'reason': reasonCtrl.text.trim(),
                }),
              );
              if (ctx.mounted) Navigator.pop(ctx);
              _toast('Asset checked out to ${empCtrl.text.trim()}');
              _fetchAllInventoryData();
            },
            child: const Text('Confirm Checkout'),
          ),
        ],
      ),
    );
  }

  void _showReturnAssetDialog(dynamic asset) {
    String condition = 'GOOD';
    final notesCtrl = TextEditingController(text: 'Returned to store');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text('Return Equipment: ${asset['name']}'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: condition,
                  decoration: const InputDecoration(labelText: 'Condition Upon Return'),
                  items: ['GOOD', 'FAIR', 'DAMAGED', 'LOST'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (v) => setDlg(() => condition = v ?? 'GOOD'),
                ),
                const SizedBox(height: 8),
                TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Inspection Notes')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                await http.post(
                  Uri.parse('$_baseUrl/inventory/returns'),
                  headers: _headers,
                  body: json.encode({
                    'toolAssetId': asset['id'],
                    'kind': condition == 'DAMAGED' ? 'DAMAGED' : condition == 'LOST' ? 'LOST' : 'RETURN',
                    'condition': condition,
                    'notes': notesCtrl.text.trim(),
                  }),
                );
                if (ctx.mounted) Navigator.pop(ctx);
                _toast('Asset return recorded! Awaiting QC inspection.');
                _fetchAllInventoryData();
              },
              child: const Text('Record Return'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAssignAssetDialog(dynamic asset) {
    final locCtrl = TextEditingController(text: asset['location'] ?? 'Main Store');
    final deptCtrl = TextEditingController(text: asset['department'] ?? 'Mechanical');
    final assignedCtrl = TextEditingController(text: asset['assignedTo'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Assign / Relocate: ${asset['name']}'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: locCtrl, decoration: const InputDecoration(labelText: 'Permanent Location (Bay / Workshop)')),
              const SizedBox(height: 8),
              TextField(controller: deptCtrl, decoration: const InputDecoration(labelText: 'Department (e.g. Diagnostics, Body)')),
              const SizedBox(height: 8),
              TextField(controller: assignedCtrl, decoration: const InputDecoration(labelText: 'Custodian Employee (Optional)')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await http.post(
                Uri.parse('$_baseUrl/inventory/assets/${asset['id']}/assign'),
                headers: _headers,
                body: json.encode({
                  'location': locCtrl.text.trim(),
                  'department': deptCtrl.text.trim(),
                  'assignedTo': assignedCtrl.text.trim(),
                }),
              );
              if (ctx.mounted) Navigator.pop(ctx);
              _toast('Asset assignment updated!');
              _fetchAllInventoryData();
            },
            child: const Text('Save Assignment'),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 4: INTERNAL CONSUMABLES & SUPPLIES
  // ===========================================================================
  Widget _buildConsumablesTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${_consumables.length} Internal Consumables & Workshop Supplies (Non-Resale)', style: const TextStyle(fontWeight: FontWeight.bold)),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F4C81), foregroundColor: Colors.white),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Consumable Supply'),
                onPressed: _showAddConsumableDialog,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: SingleChildScrollView(
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('SKU', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Supply Name', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Unit', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('On Hand', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Unit Cost', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Location', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: _consumables.map((c) {
                  final qty = c['quantityOnHand'] ?? 0;
                  final reorder = c['reorderLevel'] ?? 5;
                  final isLow = qty <= reorder;

                  return DataRow(
                    cells: [
                      DataCell(Text(c['sku'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text(c['name'] ?? '')),
                      DataCell(Text(c['unit'] ?? 'pcs')),
                      DataCell(
                        Row(
                          children: [
                            Text(qty.toString(), style: TextStyle(fontWeight: FontWeight.bold, color: isLow ? Colors.red : Colors.black87)),
                            if (isLow) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.warning_amber, size: 14, color: Colors.red),
                            ],
                          ],
                        ),
                      ),
                      DataCell(Text('KES ${(c['unitCost'] ?? 0).toString()}')),
                      DataCell(Text(c['location'] ?? 'Main Store')),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Issue / Dispatch to Department',
                              icon: const Icon(Icons.outbox, color: Colors.green),
                              onPressed: () => _showDispatchConsumableDialog(c),
                            ),
                            IconButton(
                              tooltip: 'Receive Supply Stock',
                              icon: const Icon(Icons.add_box_outlined, color: Colors.blue),
                              onPressed: () => _showReceiveStockDialog(c, isSparePart: false),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDispatchConsumableDialog(dynamic item) {
    final qtyCtrl = TextEditingController(text: '1');
    final employeeCtrl = TextEditingController(text: 'Kamau Tech');
    final purposeCtrl = TextEditingController(text: 'Daily workshop operations');
    final notesCtrl = TextEditingController();
    final piecesPerBoxCtrl = TextEditingController(text: '100');
    String destinationType = 'INDIVIDUAL'; // 'INDIVIDUAL' or 'DEPARTMENT'
    String department = 'Mechanical Workshop';

    final currentUnit = (item['unit'] ?? 'pcs').toString().toLowerCase();
    final isBoxOrPack = ['box', 'pack', 'packet', 'drum', 'carton', 'tin'].contains(currentUnit);
    bool unpackFromBox = isBoxOrPack;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final int pPerBox = int.tryParse(piecesPerBoxCtrl.text.trim()) ?? 1;
          final int onHand = (item['quantityOnHand'] as num?)?.toInt() ?? 0;
          final int maxPieces = unpackFromBox ? onHand * pPerBox : onHand;

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.outbox, color: Color(0xFF0F4C81)),
                const SizedBox(width: 8),
                Expanded(child: Text('Issue Supply: ${item['name']}', overflow: TextOverflow.ellipsis)),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('SKU: ${item['sku']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text('Stock: $onHand ${item['unit'] ?? 'units'}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                            ],
                          ),
                          if (unpackFromBox && isBoxOrPack) ...[
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Total Pieces Available:', style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
                                Text('$maxPieces pcs', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo)),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    const Text('Destination Target:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setDlg(() => destinationType = 'INDIVIDUAL'),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                              decoration: BoxDecoration(
                                color: destinationType == 'INDIVIDUAL' ? Colors.purple.shade50 : Colors.grey.shade100,
                                border: Border.all(
                                  color: destinationType == 'INDIVIDUAL' ? Colors.purple : Colors.grey.shade300,
                                  width: destinationType == 'INDIVIDUAL' ? 2 : 1,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.person, size: 18, color: destinationType == 'INDIVIDUAL' ? Colors.purple : Colors.grey),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Individual Person',
                                    style: TextStyle(
                                      fontWeight: destinationType == 'INDIVIDUAL' ? FontWeight.bold : FontWeight.normal,
                                      color: destinationType == 'INDIVIDUAL' ? Colors.purple.shade900 : Colors.black87,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            onTap: () => setDlg(() => destinationType = 'DEPARTMENT'),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                              decoration: BoxDecoration(
                                color: destinationType == 'DEPARTMENT' ? Colors.teal.shade50 : Colors.grey.shade100,
                                border: Border.all(
                                  color: destinationType == 'DEPARTMENT' ? Colors.teal : Colors.grey.shade300,
                                  width: destinationType == 'DEPARTMENT' ? 2 : 1,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.business, size: 18, color: destinationType == 'DEPARTMENT' ? Colors.teal : Colors.grey),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Department / Bay',
                                    style: TextStyle(
                                      fontWeight: destinationType == 'DEPARTMENT' ? FontWeight.bold : FontWeight.normal,
                                      color: destinationType == 'DEPARTMENT' ? Colors.teal.shade900 : Colors.black87,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (destinationType == 'INDIVIDUAL') ...[
                      TextField(
                        controller: employeeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Receiving Employee / Technician * (e.g. Kamau Tech)',
                          prefixIcon: Icon(Icons.person_pin, size: 20),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Direct personal issue. Debited to this technician\'s personal custody & reports.',
                        style: TextStyle(fontSize: 11, color: Colors.purple.shade700, fontStyle: FontStyle.italic),
                      ),
                    ] else ...[
                      DropdownButtonFormField<String>(
                        value: department,
                        decoration: const InputDecoration(labelText: 'Receiving Department *', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 'Mechanical Workshop', child: Text('Mechanical Workshop')),
                          DropdownMenuItem(value: 'Bodyshop & Paint', child: Text('Bodyshop & Paint')),
                          DropdownMenuItem(value: 'Auto Electrical Bay', child: Text('Auto Electrical Bay')),
                          DropdownMenuItem(value: 'Car Wash & Detailing', child: Text('Car Wash & Detailing')),
                          DropdownMenuItem(value: 'Administrative Office', child: Text('Administrative Office')),
                        ],
                        onChanged: (v) => setDlg(() => department = v ?? 'Mechanical Workshop'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: employeeCtrl,
                        decoration: const InputDecoration(labelText: 'Issued to Lead / Supervisor (Optional)', border: OutlineInputBorder()),
                      ),
                    ],
                    const SizedBox(height: 14),

                    if (isBoxOrPack) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.content_cut, size: 18, color: Colors.brown),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text('Give in Individual Pieces (pcs)?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                ),
                                Switch(
                                  value: unpackFromBox,
                                  onChanged: (val) => setDlg(() => unpackFromBox = val),
                                ),
                              ],
                            ),
                            if (unpackFromBox) ...[
                              const Divider(height: 12),
                              Text(
                                'The supply will be opened and converted into loose pieces for individual distribution.',
                                style: TextStyle(fontSize: 11, color: Colors.amber.shade900),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: piecesPerBoxCtrl,
                                keyboardType: TextInputType.number,
                                onChanged: (_) => setDlg(() {}),
                                decoration: InputDecoration(
                                  labelText: 'Pieces per ${item['unit']} (e.g. 100 per box) *',
                                  isDense: true,
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    TextField(
                      controller: qtyCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: unpackFromBox && isBoxOrPack
                            ? 'Quantity to Issue in Loose Pieces (pcs) *'
                            : 'Quantity to Issue (${item['unit'] ?? 'units'}) *',
                        prefixIcon: const Icon(Icons.confirmation_number_outlined, size: 20),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),

                    TextField(
                      controller: purposeCtrl,
                      decoration: const InputDecoration(labelText: 'Purpose / Work Reference *', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 10),

                    TextField(
                      controller: notesCtrl,
                      decoration: const InputDecoration(labelText: 'Additional Notes (Optional)', border: OutlineInputBorder()),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F4C81),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: () async {
                  final qty = int.tryParse(qtyCtrl.text.trim()) ?? 0;
                  if (qty <= 0) {
                    _toast('Enter a valid quantity', color: Colors.orange);
                    return;
                  }
                  if (destinationType == 'INDIVIDUAL' && employeeCtrl.text.trim().isEmpty) {
                    _toast('Please enter the name of the recipient technician', color: Colors.orange);
                    return;
                  }

                  final int factor = int.tryParse(piecesPerBoxCtrl.text.trim()) ?? 1;
                  if (unpackFromBox && isBoxOrPack && factor <= 0) {
                    _toast('Enter valid pieces per ${item['unit']}', color: Colors.orange);
                    return;
                  }

                  final int avail = unpackFromBox && isBoxOrPack ? onHand * factor : onHand;
                  if (qty > avail) {
                    _toast('Cannot issue more than available stock ($avail ${unpackFromBox ? "pcs" : item['unit']})', color: Colors.red);
                    return;
                  }

                  try {
                    final res = await http.post(
                      Uri.parse('$_baseUrl/inventory/consume'),
                      headers: _headers,
                      body: json.encode({
                        'itemId': item['id'],
                        'quantity': qty,
                        'destinationType': destinationType,
                        'department': destinationType == 'INDIVIDUAL' ? 'Individual Issue' : department,
                        'issuedTo': employeeCtrl.text.trim(),
                        'purpose': purposeCtrl.text.trim(),
                        'notes': notesCtrl.text.trim(),
                        'unpackFromBox': unpackFromBox && isBoxOrPack,
                        'piecesPerBox': factor,
                      }),
                    );
                    if (res.statusCode == 200) {
                      if (ctx.mounted) Navigator.pop(ctx);
                      final recipientDisplay = destinationType == 'INDIVIDUAL' ? employeeCtrl.text.trim() : department;
                      final unitDisplay = unpackFromBox && isBoxOrPack ? 'pcs' : (item['unit'] ?? 'units');
                      _toast('Issued $qty $unitDisplay directly to $recipientDisplay! Logged in reports.', color: Colors.green);
                      _fetchAllInventoryData();
                      widget.onDataChanged();
                    } else {
                      final err = json.decode(res.body)['error'] ?? 'Dispatch failed';
                      _toast(err, color: Colors.red);
                    }
                  } catch (e) {
                    _toast('Error: $e', color: Colors.red);
                  }
                },
                child: const Text('Confirm Issuance'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddConsumableDialog() {
    final skuCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    String selectedUnit = 'pcs';
    final customUnitCtrl = TextEditingController();
    final costCtrl = TextEditingController(text: '0');
    final qtyCtrl = TextEditingController(text: '10');
    final locCtrl = TextEditingController(text: 'Supply Locker');

    final commonUnits = ['pcs', 'pair', 'bottle', 'L', 'box', 'pack', 'roll', 'set', 'Other'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Add Internal Workshop Supply / Consumable'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(controller: skuCtrl, decoration: const InputDecoration(labelText: 'SKU * (e.g. GLOVE-01)', border: OutlineInputBorder())),
                  const SizedBox(height: 10),
                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Supply Name * (e.g. Nitrile Gloves)', border: OutlineInputBorder())),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: selectedUnit,
                    decoration: const InputDecoration(labelText: 'Counting Unit *', border: OutlineInputBorder()),
                    items: commonUnits.map((u) {
                      String label = u;
                      if (u == 'pcs') label = 'Pieces (pcs) - Individual Units';
                      if (u == 'pair') label = 'Pairs (pair) - e.g. Gloves, Shoes';
                      if (u == 'bottle') label = 'Bottles / Cans (bottle)';
                      if (u == 'L') label = 'Litres (L)';
                      if (u == 'box') label = 'Box (box) - Bulk container';
                      if (u == 'pack') label = 'Pack (pack) - Multi-pack';
                      if (u == 'roll') label = 'Rolls (roll) - Tape, Wire';
                      if (u == 'set') label = 'Sets (set)';
                      if (u == 'Other') label = 'Other (Custom Unit)';
                      return DropdownMenuItem(value: u, child: Text(label));
                    }).toList(),
                    onChanged: (v) => setDlg(() => selectedUnit = v ?? 'pcs'),
                  ),
                  if (selectedUnit == 'Other') ...[
                    const SizedBox(height: 10),
                    TextField(controller: customUnitCtrl, decoration: const InputDecoration(labelText: 'Custom Unit Name * (e.g. kg, metre)', border: OutlineInputBorder())),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: costCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Unit Cost (KES)', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: qtyCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Initial Quantity', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: locCtrl, decoration: const InputDecoration(labelText: 'Storage Location', border: OutlineInputBorder())),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F4C81), foregroundColor: Colors.white),
              onPressed: () async {
                if (skuCtrl.text.trim().isEmpty || nameCtrl.text.trim().isEmpty) {
                  _toast('SKU and Name are required', color: Colors.orange);
                  return;
                }
                final finalUnit = selectedUnit == 'Other' ? (customUnitCtrl.text.trim().isNotEmpty ? customUnitCtrl.text.trim() : 'pcs') : selectedUnit;
                final res = await http.post(
                  Uri.parse('$_baseUrl/inventory/items'),
                  headers: _headers,
                  body: json.encode({
                    'sku': skuCtrl.text.trim(),
                    'name': nameCtrl.text.trim(),
                    'unit': finalUnit,
                    'unitCost': double.tryParse(costCtrl.text.trim()) ?? 0,
                    'quantity': int.tryParse(qtyCtrl.text.trim()) ?? 0,
                    'location': locCtrl.text.trim(),
                  }),
                );
                if (res.statusCode == 200 || res.statusCode == 201) {
                  if (ctx.mounted) Navigator.pop(ctx);
                  _toast('Consumable supply registered as "$finalUnit"!', color: Colors.green);
                  _fetchAllInventoryData();
                  widget.onDataChanged();
                } else {
                  final err = json.decode(res.body)['error'] ?? 'Registration failed';
                  _toast(err, color: Colors.red);
                }
              },
              child: const Text('Save Supply'),
            ),
          ],
        ),
      ),
    );
  }

  void _showReceiveStockDialog(dynamic item, {required bool isSparePart}) {
    final qtyCtrl = TextEditingController(text: '10');
    final costCtrl = TextEditingController(text: (item['costPrice'] ?? item['unitCost'] ?? 0).toString());
    final refCtrl = TextEditingController(text: 'PO-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Receive Stock: ${isSparePart ? item['description'] : item['name']}'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity Received *')),
              const SizedBox(height: 8),
              TextField(controller: costCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Purchase Unit Cost (KES)')),
              const SizedBox(height: 8),
              TextField(controller: refCtrl, decoration: const InputDecoration(labelText: 'Supplier Invoice / PO Reference')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final q = int.tryParse(qtyCtrl.text.trim()) ?? 0;
              if (q <= 0) return;
              await http.post(
                Uri.parse('$_baseUrl/inventory/receive'),
                headers: _headers,
                body: json.encode({
                  'category': isSparePart ? 'SPARE_PART' : 'CONSUMABLE',
                  'itemId': item['id'],
                  'quantity': q,
                  'unitCost': double.tryParse(costCtrl.text.trim()) ?? 0,
                  'reference': refCtrl.text.trim(),
                }),
              );
              if (ctx.mounted) Navigator.pop(ctx);
              _toast('Stock received and recorded in ledger!');
              _fetchAllInventoryData();
              widget.onDataChanged();
            },
            child: const Text('Receive Stock'),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 5: RETURNS & QC INSPECTIONS
  // ===========================================================================
  Widget _buildReturnsTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Returned Items Awaiting Inspection (QC Quarantine)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          const Text('Returned parts or tools must be inspected before being made available in stock or written off.', style: TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 14),
          Expanded(
            child: _returns.isEmpty
                ? const Center(child: Text('No returned items pending inspection.', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: _returns.length,
                    itemBuilder: (_, i) {
                      final ret = _returns[i];
                      final status = (ret['status'] ?? 'PENDING_INSPECTION').toString();
                      final isPending = status == 'PENDING_INSPECTION';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: isPending ? Colors.amber.shade100 : Colors.green.shade100,
                              child: Icon(isPending ? Icons.hourglass_top : Icons.check, color: isPending ? Colors.amber.shade900 : Colors.green.shade900, size: 20),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${ret['reference']} • ${ret['category']} (Qty: ${ret['quantity']})', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  Text('Returned by: ${ret['returnedBy']}  |  Condition: ${ret['condition'] ?? 'GOOD'}'),
                                  if (ret['notes'] != null) Text('Notes: ${ret['notes']}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                ],
                              ),
                            ),
                            if (isPending)
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F4C81), foregroundColor: Colors.white),
                                icon: const Icon(Icons.fact_check, size: 16),
                                label: const Text('Perform QC Inspection'),
                                onPressed: () => _showInspectDialog(ret),
                              )
                            else
                              Chip(label: Text(status.replaceAll('_', ' '), style: const TextStyle(fontSize: 11))),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _showInspectDialog(dynamic ret) {
    String outcome = 'RESTOCK';
    final notesCtrl = TextEditingController(text: 'Inspected and verified');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text('QC Inspection: ${ret['reference']}'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  value: outcome,
                  decoration: const InputDecoration(labelText: 'Inspection Outcome *'),
                  items: const [
                    DropdownMenuItem(value: 'RESTOCK', child: Text('RESTOCK (Restore to Available Inventory)')),
                    DropdownMenuItem(value: 'QUARANTINE', child: Text('QUARANTINE (Keep in QC Quarantine for Repair)')),
                    DropdownMenuItem(value: 'WRITE_OFF', child: Text('WRITE OFF (Damaged/Destroyed - Manager Auth)')),
                  ],
                  onChanged: (v) => setDlg(() => outcome = v ?? 'RESTOCK'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Inspection Report / QC Notes *', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F4C81), foregroundColor: Colors.white),
            onPressed: () async {
              final res = await http.post(
                Uri.parse('$_baseUrl/inventory/returns/${ret['id']}/inspect'),
                headers: _headers,
                body: json.encode({
                  'outcome': outcome,
                  'notes': notesCtrl.text.trim(),
                }),
              );
              if (res.statusCode == 200) {
                if (ctx.mounted) Navigator.pop(ctx);
                _toast('Inspection outcome processed and stock updated!', color: Colors.green);
                _fetchAllInventoryData();
                widget.onDataChanged();
              } else {
                final err = json.decode(res.body)['error'] ?? 'Inspection failed';
                _toast(err, color: Colors.red);
              }
            },
            child: const Text('Save Inspection Outcome'),
          ),
        ],
        ),
      ),
    );
  }

  // ===========================================================================
  // TAB 6: STOCKTAKING & COUNTS
  // ===========================================================================
  Widget _buildStocktakeTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Physical Stock Counts & Variance Approvals', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F4C81), foregroundColor: Colors.white),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Record Physical Stock Count'),
                onPressed: _showStockCountDialog,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: _stockCounts.isEmpty
                ? const Center(child: Text('No stock count entries recorded yet.', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: _stockCounts.length,
                    itemBuilder: (_, i) {
                      final sc = _stockCounts[i];
                      final variance = sc['variance'] ?? 0;
                      final isPending = sc['status'] == 'PENDING';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(sc['itemName'] ?? 'Item', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  Text('Recorded: ${sc['recordedQty']}  |  Counted: ${sc['countedQty']}  |  Variance: $variance',
                                      style: TextStyle(fontWeight: FontWeight.bold, color: variance == 0 ? Colors.green : Colors.red)),
                                  Text('Counted by: ${sc['countedBy']} • Status: ${sc['status']}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                ],
                              ),
                            ),
                            if (isPending)
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
                                onPressed: () async {
                                  final res = await http.post(
                                    Uri.parse('$_baseUrl/inventory/stockcounts/${sc['id']}/approve'),
                                    headers: _headers,
                                    body: json.encode({'approve': true}),
                                  );
                                  if (res.statusCode == 200) {
                                    _toast('Stock count variance approved and adjusted!', color: Colors.green);
                                    _fetchAllInventoryData();
                                    widget.onDataChanged();
                                  } else {
                                    final err = json.decode(res.body)['error'] ?? 'Approval failed';
                                    _toast(err, color: Colors.red);
                                  }
                                },
                                child: const Text('Approve Variance'),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _showStockCountDialog() {
    String category = 'SPARE_PART';
    String? itemId;
    final countCtrl = TextEditingController(text: '0');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final items = category == 'SPARE_PART' ? _parts : _consumables;
          return AlertDialog(
            title: const Text('Record Physical Count (Stocktake)'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: category,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: const [
                      DropdownMenuItem(value: 'SPARE_PART', child: Text('Spare Parts')),
                      DropdownMenuItem(value: 'CONSUMABLE', child: Text('Consumables')),
                    ],
                    onChanged: (v) => setDlg(() {
                      category = v ?? 'SPARE_PART';
                      itemId = null;
                    }),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: itemId,
                    decoration: const InputDecoration(labelText: 'Select Item to Count *'),
                    items: items.map<DropdownMenuItem<String>>((it) {
                      final name = category == 'SPARE_PART' ? it['description'] : it['name'];
                      return DropdownMenuItem(value: it['id'].toString(), child: Text(name.toString()));
                    }).toList(),
                    onChanged: (v) => setDlg(() => itemId = v),
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: countCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Actual Physical Count *')),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  if (itemId == null) return;
                  await http.post(
                    Uri.parse('$_baseUrl/inventory/stockcounts'),
                    headers: _headers,
                    body: json.encode({
                      'category': category,
                      'itemId': itemId,
                      'countedQty': int.tryParse(countCtrl.text.trim()) ?? 0,
                    }),
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  _toast('Stock count logged for manager review!');
                  _fetchAllInventoryData();
                },
                child: const Text('Submit Count'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ===========================================================================
  // TAB 7: AUDIT LEDGER & VALUATION
  // ===========================================================================
  Widget _buildAuditLedgerTab() {
    final val = _summary['valuation'] as Map<String, dynamic>?;
    final partsVal = val?['spareParts'] ?? 0;
    final consVal = val?['consumables'] ?? 0;
    final assetsVal = val?['assets'] ?? 0;
    final totalVal = val?['total'] ?? 0;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Financial Valuation Cards
          Wrap(
            spacing: 16,
            runSpacing: 10,
            children: [
              _metricTile('Spare Parts Valuation', 'KES ${partsVal.toStringAsFixed(0)}', Colors.blue),
              _metricTile('Consumables Valuation', 'KES ${consVal.toStringAsFixed(0)}', Colors.teal),
              _metricTile('Tools & Assets Valuation', 'KES ${assetsVal.toStringAsFixed(0)}', Colors.purple),
              _metricTile('Total Inventory Investment', 'KES ${totalVal.toStringAsFixed(0)}', Colors.green),
            ],
          ),
          const SizedBox(height: 18),
          const Text('Immutable Transaction Audit Ledger (Protected by PostgreSQL trigger)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 10),
          Expanded(
            child: SingleChildScrollView(
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Ref', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Action', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Category', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Item Name', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Stock Impact', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Actor', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Recipient', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Reason / Note', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: _transactions.map((tx) {
                  final qty = tx['quantity'] ?? 0;
                  return DataRow(
                    cells: [
                      DataCell(Text(tx['reference'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                      DataCell(Text(tx['type'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text(tx['category'] ?? '-')),
                      DataCell(Text(tx['itemName'] ?? '-')),
                      DataCell(Text(qty > 0 ? '+$qty' : qty < 0 ? '$qty' : '0', style: TextStyle(fontWeight: FontWeight.bold, color: qty > 0 ? Colors.green : qty < 0 ? Colors.red : Colors.grey))),
                      DataCell(Text('${tx['actorName']} (${tx['actorRole']})')),
                      DataCell(Text(tx['recipientName'] ?? '-')),
                      DataCell(Text(tx['reason'] ?? tx['notes'] ?? '-')),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricTile(String title, String value, Color color) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color)),
        ],
      ),
    );
  }
}
