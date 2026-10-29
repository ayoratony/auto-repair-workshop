import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../services/auth_service.dart';

class EstimateForm extends StatefulWidget {
  final String? initialJobCardId;
  final VoidCallback? onSaved;
  final VoidCallback? onCancel;
  final bool isModal;

  const EstimateForm({
    Key? key,
    this.initialJobCardId,
    this.onSaved,
    this.onCancel,
    this.isModal = false,
  }) : super(key: key);

  @override
  State<EstimateForm> createState() => _EstimateFormState();
}

class _EstimateFormState extends State<EstimateForm> {
  static const String _baseUrl = 'https://auto.zksms.online/api';

  final List<Map<String, dynamic>> _items = [];
  List<dynamic> _jobs = [];
  List<dynamic> _parts = [];
  String? _selectedJobCardId;
  Map<String, dynamic>? _selectedPart;
  String _selectedItemType = 'PART';

  final TextEditingController _descController = TextEditingController();
  final TextEditingController _qtyController = TextEditingController(text: '1');
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _discountController = TextEditingController(text: '20');

  bool _isLoading = false;
  bool _isFetchingData = true;

  @override
  void initState() {
    super.initState();
    _selectedJobCardId = widget.initialJobCardId;
    _loadJobsAndParts();
  }

  Future<void> _loadJobsAndParts() async {
    try {
      final headers = AuthService.instance.authHeaders;
      final results = await Future.wait([
        http.get(Uri.parse('$_baseUrl/jobs'), headers: headers),
        http.get(Uri.parse('$_baseUrl/parts'), headers: headers),
      ]);

      if (mounted) {
        setState(() {
          if (results[0].statusCode == 200) {
            _jobs = json.decode(results[0].body);
            if (widget.initialJobCardId != null &&
                _jobs.any((j) => j['id'] == widget.initialJobCardId)) {
              _selectedJobCardId = widget.initialJobCardId;
            } else if (_selectedJobCardId == null && _jobs.isNotEmpty) {
              _selectedJobCardId = _jobs.first['id'];
            }
          }
          if (results[1].statusCode == 200) {
            _parts = json.decode(results[1].body);
          }
          _isFetchingData = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isFetchingData = false);
      }
    }
  }

  void _addItem() {
    final desc = _descController.text.trim();
    final qty = int.tryParse(_qtyController.text.trim()) ?? 1;
    final price = double.tryParse(_priceController.text.trim()) ?? 0.0;

    if (desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.orange,
          content: Text('Please enter an item description.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.orange,
          content: Text('Please enter a valid price/rate greater than 0.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _items.add({
        'description': desc,
        'itemType': _selectedItemType,
        'partId': (_selectedItemType == 'PART' && _selectedPart != null) ? _selectedPart!['id'] : null,
        'quantity': qty > 0 ? qty : 1,
        'unitPrice': price,
      });
      _descController.clear();
      _qtyController.text = '1';
      _priceController.clear();
      _selectedPart = null;
    });
  }

  List<Map<String, dynamic>> get _selectedJobRecommendations {
    if (_selectedJobCardId == null) return [];
    try {
      final job = _jobs.firstWhere(
        (j) => j['id'] == _selectedJobCardId,
        orElse: () => null,
      );
      if (job == null) return [];
      final walk = job['walkAroundData'];
      if (walk is Map && walk['recommendations'] is List) {
        return (walk['recommendations'] as List)
            .whereType<Map>()
            .map((r) => Map<String, dynamic>.from(r))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  void _addRecommendationToEstimate(Map<String, dynamic> rec) {
    final system = rec['system'] ?? 'General';
    final issue = rec['issue'] ?? '';
    final fix = rec['recommendation'] ?? '';
    final partsNeeded = (rec['partsNeeded'] ?? '').toString().trim();
    final partsPrice = (rec['estimatedParts'] as num?)?.toDouble() ?? 0.0;
    final labourPrice = (rec['estimatedLabour'] as num?)?.toDouble() ?? 0.0;

    setState(() {
      // Add Parts if cost > 0 or parts needed specified
      if (partsPrice > 0 || partsNeeded.isNotEmpty) {
        _items.add({
          'description': partsNeeded.isNotEmpty
              ? '$partsNeeded ($system - $issue)'
              : '$system Replacement Parts: $fix',
          'itemType': 'PART',
          'partId': null,
          'quantity': 1,
          'unitPrice': partsPrice > 0 ? partsPrice : 0.0,
        });
      }

      // Add Labour if cost > 0 or fix specified
      if (labourPrice > 0 || fix.isNotEmpty) {
        _items.add({
          'description': 'Labour: $fix ($system)',
          'itemType': 'LABOUR',
          'partId': null,
          'quantity': 1,
          'unitPrice': labourPrice > 0 ? labourPrice : 0.0,
        });
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF166534),
        content: Text('Imported "$system: $fix" into estimate line items!'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _addAllRecommendationsToEstimate(List<Map<String, dynamic>> recs) {
    for (final r in recs) {
      _addRecommendationToEstimate(r);
    }
  }

  double get _partsSubtotal {
    return _items
        .where((i) => (i['itemType'] ?? 'PART') == 'PART')
        .fold(0.0, (sum, item) => sum + ((item['quantity'] as num) * (item['unitPrice'] as num)));
  }

  double get _labourSubtotal {
    return _items
        .where((i) => (i['itemType'] ?? 'PART') == 'LABOUR')
        .fold(0.0, (sum, item) => sum + ((item['quantity'] as num) * (item['unitPrice'] as num)));
  }

  double get _subtotal {
    return _items.fold(0.0, (sum, item) => sum + ((item['quantity'] as num) * (item['unitPrice'] as num)));
  }

  double get _discountRate {
    return double.tryParse(_discountController.text.trim()) ?? 0.0;
  }

  double get _discountAmount {
    return _subtotal * (_discountRate / 100.0);
  }

  double get _subtotalAfterDiscount {
    return _subtotal - _discountAmount;
  }

  double get _vatAmount {
    return _subtotalAfterDiscount * 0.16;
  }

  double get _grandTotal {
    return _subtotalAfterDiscount + _vatAmount;
  }

  Future<void> _submitEstimate() async {
    if (_selectedJobCardId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: Colors.orange, content: Text('Please select a Job Card first.')),
      );
      return;
    }
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: Colors.orange, content: Text('Please add at least one line item.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/estimates'),
        headers: {
          'Content-Type': 'application/json',
          ...AuthService.instance.authHeaders,
        },
        body: json.encode({
          'jobCardId': _selectedJobCardId,
          'items': _items,
          'discountRate': _discountRate,
          'taxRate': 16,
          'status': 'SENT',
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.green.shade700,
            content: Text('Estimate Saved! Total (incl. 16% VAT): KES ${(data['total'] as num).toStringAsFixed(2)}'),
          ));
          setState(() => _items.clear());
          widget.onSaved?.call();
        }
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red.shade700,
          content: Text('Failed to save estimate: $e'),
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isFetchingData) {
      return const Center(child: Padding(padding: EdgeInsets.all(32.0), child: CircularProgressIndicator()));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 650;

        return Container(
          padding: EdgeInsets.all(isMobile ? 14.0 : 22.0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.request_quote_rounded, color: Color(0xFF2563EB), size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Create Official Estimate',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Official quotation for vehicle repairs, spare parts & labour',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (widget.onCancel != null || widget.isModal)
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Close',
                      onPressed: () {
                        if (widget.onCancel != null) {
                          widget.onCancel!();
                        } else if (Navigator.canPop(context)) {
                          Navigator.pop(context);
                        }
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // Job Card Selection
              DropdownButtonFormField<String>(
                isExpanded: true,
                value: _jobs.any((j) => j['id'] == _selectedJobCardId) ? _selectedJobCardId : null,
                decoration: InputDecoration(
                  labelText: 'Select Job Card (Vehicle & Customer)',
                  prefixIcon: const Icon(Icons.directions_car_outlined, size: 18),
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                items: _jobs.map<DropdownMenuItem<String>>((job) {
                  final jobNo = (job['jobNumber'] ?? job['id'].toString().substring(0, 8).toUpperCase()).toString();
                  final customer = (job['customer']?['name'] ?? 'Customer').toString();
                  final regNo = (job['vehicle']?['registrationNo'] ?? '').toString().toUpperCase();
                  final makeModel = '${job['vehicle']?['make'] ?? ''} ${job['vehicle']?['model'] ?? ''}'.trim();
                  return DropdownMenuItem<String>(
                    value: job['id'],
                    child: Text(
                      '$jobNo \u2022 ${regNo.isNotEmpty ? regNo : "No Plate"} ($makeModel) \u2022 $customer',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _selectedJobCardId = val),
              ),
              const SizedBox(height: 12),

              // -------------------------------------------------------------
              // TECHNICIAN RECOMMENDATIONS & FINDINGS BANNER
              // -------------------------------------------------------------
              if (_selectedJobRecommendations.isNotEmpty) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFF59E0B)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                const Icon(Icons.build_circle, color: Color(0xFFB45309), size: 20),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    'Technician Recommendations & Findings (${_selectedJobRecommendations.length})',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF78350F)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFB45309),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(Icons.playlist_add_check, size: 15),
                            label: const Text('Import All', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            onPressed: () => _addAllRecommendationsToEstimate(_selectedJobRecommendations),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ..._selectedJobRecommendations.map((rec) {
                        final system = (rec['system'] ?? 'General').toString();
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
                          margin: const EdgeInsets.only(top: 6),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.shade300),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: badgeColor.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
                                          ),
                                          child: Text(
                                            '$system \u2022 $urgency',
                                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: badgeColor),
                                          ),
                                        ),
                                        Text('Reported by $tech', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text('Issue: $issue', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF1E293B))),
                                    Text('Recommended Action: $fix', style: const TextStyle(fontSize: 12, color: Color(0xFF334155))),
                                    if (rec['partsNeeded'] != null && rec['partsNeeded'].toString().isNotEmpty)
                                      Text('Parts Needed: ${rec['partsNeeded']}', style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade700)),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Estimated Pricing: Labour KES ${labourPrice.toStringAsFixed(0)} | Parts KES ${partsPrice.toStringAsFixed(0)} (Total: KES ${total.toStringAsFixed(0)})',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF166534)),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  foregroundColor: const Color(0xFFB45309),
                                  side: const BorderSide(color: Color(0xFFB45309)),
                                ),
                                icon: const Icon(Icons.add_shopping_cart, size: 14),
                                label: const Text('Add to Quote', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                onPressed: () => _addRecommendationToEstimate(rec),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],

              // Discount & Tax Settings Row
              Row(
                children: [
                  Expanded(
                    flex: isMobile ? 1 : 2,
                    child: TextField(
                      controller: _discountController,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Discount Rate',
                        prefixIcon: Icon(Icons.percent, size: 16),
                        suffixText: '%',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.receipt_long, size: 16, color: Color(0xFF475569)),
                        SizedBox(width: 6),
                        Text(
                          'VAT: 16% (Auto)',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Optional Quick Pick from Spare Parts Catalog
              if (_parts.isNotEmpty) ...[
                DropdownButtonFormField<Map<String, dynamic>>(
                  isExpanded: true,
                  value: _selectedPart,
                  decoration: InputDecoration(
                    labelText: 'Quick-Pick Spare Part from Catalog (Auto-fill)',
                    prefixIcon: const Icon(Icons.inventory_2_outlined, size: 18),
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  items: _parts.map<DropdownMenuItem<Map<String, dynamic>>>((part) {
                    final brand = (part['brand'] != null && part['brand'].toString().isNotEmpty) ? ' [${part['brand']}]' : '';
                    final stock = part['stockQuantity'] ?? 0;
                    return DropdownMenuItem<Map<String, dynamic>>(
                      value: part,
                      child: Text(
                        '${part['partNumber']} \u2014 ${part['description']}$brand (KES ${part['unitPrice']}) [Stock: $stock]',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    );
                  }).toList(),
                  onChanged: (part) {
                    if (part != null) {
                      setState(() {
                        _selectedPart = part;
                        _selectedItemType = 'PART';
                        _descController.text = '${part['partNumber']} - ${part['description']}';
                        _priceController.text = part['unitPrice'].toString();
                      });
                    }
                  },
                ),
                const SizedBox(height: 14),
              ],

              // Line Item Adder Card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Add Line Item',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                    ),
                    const SizedBox(height: 8),

                    // Type Selector Tabs
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _selectedItemType = 'PART'),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: _selectedItemType == 'PART' ? const Color(0xFF2563EB) : Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _selectedItemType == 'PART' ? const Color(0xFF2563EB) : Colors.grey.shade300,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.build_circle_outlined,
                                    size: 15,
                                    color: _selectedItemType == 'PART' ? Colors.white : Colors.grey.shade700,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Spare Part',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: _selectedItemType == 'PART' ? Colors.white : Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _selectedItemType = 'LABOUR';
                                _selectedPart = null;
                              });
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: _selectedItemType == 'LABOUR' ? const Color(0xFF7C3AED) : Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _selectedItemType == 'LABOUR' ? const Color(0xFF7C3AED) : Colors.grey.shade300,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.handyman_outlined,
                                    size: 15,
                                    color: _selectedItemType == 'LABOUR' ? Colors.white : Colors.grey.shade700,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Labour / Service',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: _selectedItemType == 'LABOUR' ? Colors.white : Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Description Input
                    TextField(
                      controller: _descController,
                      decoration: InputDecoration(
                        labelText: _selectedItemType == 'LABOUR' ? 'Labour Task Description' : 'Spare Part Description',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Qty & Price Row
                    Row(
                      children: [
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: _qtyController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: _selectedItemType == 'LABOUR' ? 'Hours / Qty' : 'Quantity',
                              border: const OutlineInputBorder(),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              isDense: true,
                              filled: true,
                              fillColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _priceController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: _selectedItemType == 'LABOUR' ? 'Rate per Hour (KES)' : 'Unit Price (KES)',
                              border: const OutlineInputBorder(),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              isDense: true,
                              filled: true,
                              fillColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Add Line Item Button
                    SizedBox(
                      width: double.infinity,
                      height: 42,
                      child: ElevatedButton.icon(
                        onPressed: _addItem,
                        icon: const Icon(Icons.add_circle_outline, size: 16),
                        label: const Text('Add Line Item to Estimate', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F172A),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Estimate Line Items', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  Text('${_items.length} item(s)', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
              const Divider(height: 14),

              if (_items.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200, style: BorderStyle.solid),
                  ),
                  child: const Center(
                    child: Text(
                      'No line items added yet.\nAdd spare parts or labour tasks above to build the estimate.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 12, height: 1.4),
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    final isLabour = (item['itemType'] ?? 'PART') == 'LABOUR';
                    final qty = (item['quantity'] as num);
                    final unit = (item['unitPrice'] as num);
                    final total = qty * unit;
                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: isLabour ? const Color(0xFFF3E8FF) : const Color(0xFFDBEAFE),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isLabour ? const Color(0xFFC084FC) : const Color(0xFF93C5FD),
                              ),
                            ),
                            child: Text(
                              isLabour ? 'LABOUR' : 'PART',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: isLabour ? const Color(0xFF7E22CE) : const Color(0xFF1D4ED8),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['description'] ?? '',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  'Qty: $qty  \u00D7  KES ${unit.toStringAsFixed(2)}',
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'KES ${total.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                            padding: const EdgeInsets.only(left: 6),
                            constraints: const BoxConstraints(),
                            tooltip: 'Remove',
                            onPressed: () => setState(() => _items.removeAt(index)),
                          ),
                        ],
                      ),
                    );
                  },
                ),

              const SizedBox(height: 16),

              // Live Calculation Summary Breakdown Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    if (_partsSubtotal > 0 || _labourSubtotal > 0) ...[
                      _calcRow('Spare Parts Subtotal:', 'KES ${_partsSubtotal.toStringAsFixed(2)}', color: Colors.blueGrey.shade700),
                      const SizedBox(height: 4),
                      _calcRow('Workshop Labour Subtotal:', 'KES ${_labourSubtotal.toStringAsFixed(2)}', color: Colors.blueGrey.shade700),
                      const Divider(height: 14),
                    ],
                    _calcRow('Gross Subtotal:', 'KES ${_subtotal.toStringAsFixed(2)}'),
                    const SizedBox(height: 6),
                    _calcRow(
                      'Discount (${_discountRate.toStringAsFixed(0)}%):',
                      '- KES ${_discountAmount.toStringAsFixed(2)}',
                      color: Colors.orange.shade800,
                    ),
                    const SizedBox(height: 6),
                    _calcRow('Subtotal After Discount:', 'KES ${_subtotalAfterDiscount.toStringAsFixed(2)}'),
                    const SizedBox(height: 6),
                    _calcRow('VAT (16%):', '+ KES ${_vatAmount.toStringAsFixed(2)}'),
                    const Divider(height: 16),
                    _calcRow('Grand Total (KES):', 'KES ${_grandTotal.toStringAsFixed(2)}', isBold: true, fontSize: 16, color: const Color(0xFF1E3A8A)),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Action Buttons
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _submitEstimate,
                  icon: _isLoading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.check_circle_outline, size: 18),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  label: Text(
                    _isLoading ? 'Saving Estimate...' : 'Save & Issue Official Estimate',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _calcRow(String label, String value, {bool isBold = false, double fontSize = 13, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            color: isBold ? const Color(0xFF0F172A) : const Color(0xFF475569),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: color ?? const Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }
}
