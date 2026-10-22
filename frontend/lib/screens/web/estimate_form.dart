import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class EstimateForm extends StatefulWidget {
  final String? initialJobCardId;
  final VoidCallback? onSaved;

  const EstimateForm({Key? key, this.initialJobCardId, this.onSaved}) : super(key: key);

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
      final results = await Future.wait([
        http.get(Uri.parse('$_baseUrl/jobs')),
        http.get(Uri.parse('$_baseUrl/parts')),
      ]);

      if (mounted) {
        setState(() {
          if (results[0].statusCode == 200) {
            _jobs = json.decode(results[0].body);
            if (_selectedJobCardId == null && _jobs.isNotEmpty) {
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
    if (_descController.text.trim().isNotEmpty &&
        _qtyController.text.trim().isNotEmpty &&
        _priceController.text.trim().isNotEmpty) {
      setState(() {
        _items.add({
          'description': _descController.text.trim(),
          'quantity': int.tryParse(_qtyController.text.trim()) ?? 1,
          'unitPrice': double.tryParse(_priceController.text.trim()) ?? 0.0,
        });
        _descController.clear();
        _qtyController.text = '1';
        _priceController.clear();
        _selectedPart = null;
      });
    }
  }

  double get _subtotal {
    return _items.fold(0.0, (sum, item) => sum + (item['quantity'] * item['unitPrice']));
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
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'jobCardId': _selectedJobCardId,
          'items': _items,
          'discountRate': _discountRate,
          'taxRate': 16,
          'status': 'SENT',
        }),
      );

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.green,
            content: Text('Estimate Saved! Final Total (incl. 16% VAT): KSH ${(data['total'] as num).toStringAsFixed(2)}'),
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
          backgroundColor: Colors.red,
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

    return Container(
      padding: const EdgeInsets.all(24.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Create Official Estimate', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          // Select Job Card & Discount Rate Row
          Row(
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String>(
                  value: _jobs.any((j) => j['id'] == _selectedJobCardId) ? _selectedJobCardId : null,
                  decoration: const InputDecoration(
                    labelText: 'Select Job Card (Customer & Vehicle)',
                    border: OutlineInputBorder(),
                  ),
                  items: _jobs.map<DropdownMenuItem<String>>((job) {
                    final jobNo = job['jobNumber'] ?? job['id'].toString().substring(0, 8).toUpperCase();
                    final customer = job['customer']?['name'] ?? 'Customer';
                    final vehicle = '${job['vehicle']?['make'] ?? ''} ${job['vehicle']?['model'] ?? ''} (${job['vehicle']?['registrationNo'] ?? ''})';
                    return DropdownMenuItem<String>(
                      value: job['id'],
                      child: Text('$jobNo - $customer - $vehicle'),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedJobCardId = val),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 1,
                child: TextField(
                  controller: _discountController,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Discount (%)',
                    suffixText: '%',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Optional Quick Fill from Parts Catalog
          if (_parts.isNotEmpty) ...[
            DropdownButtonFormField<Map<String, dynamic>>(
              value: _selectedPart,
              decoration: const InputDecoration(
                labelText: 'Quick-Pick from Parts Catalog (Optional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.inventory_2_outlined),
              ),
              items: _parts.map<DropdownMenuItem<Map<String, dynamic>>>((part) {
                return DropdownMenuItem<Map<String, dynamic>>(
                  value: part,
                  child: Text('${part['partNumber']} - ${part['description']} (KSH ${part['unitPrice']}) [Stock: ${part['stockQuantity']}]'),
                );
              }).toList(),
              onChanged: (part) {
                if (part != null) {
                  setState(() {
                    _selectedPart = part;
                    _descController.text = '${part['partNumber']} - ${part['description']}';
                    _priceController.text = part['unitPrice'].toString();
                  });
                }
              },
            ),
            const SizedBox(height: 16),
          ],

          // Form Row to Add Line Item
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _descController,
                  decoration: const InputDecoration(labelText: 'Part / Labor Description', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 1,
                child: TextField(
                  controller: _qtyController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Qty', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 1,
                child: TextField(
                  controller: _priceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Unit Price (KSH)', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _addItem,
                icon: const Icon(Icons.add),
                label: const Text('Add Line'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                  backgroundColor: const Color(0xFF1E2329),
                  foregroundColor: Colors.white,
                ),
              )
            ],
          ),

          const SizedBox(height: 20),
          const Text('Line Items', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const Divider(),

          if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20.0),
              child: Center(child: Text('No line items added yet. Add parts or labor above.', style: TextStyle(color: Colors.grey))),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = _items[index];
                final total = (item['quantity'] as num) * (item['unitPrice'] as num);
                return ListTile(
                  dense: true,
                  title: Text(item['description'], style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('Qty: ${item['quantity']}  ×  KSH ${(item['unitPrice'] as num).toStringAsFixed(2)}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('KSH ${total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                        onPressed: () => setState(() => _items.removeAt(index)),
                      ),
                    ],
                  ),
                );
              },
            ),

          const Divider(height: 24),
          // Live Calculation Breakdown
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                _calcRow('Parts & Labor Subtotal:', 'KSH ${_subtotal.toStringAsFixed(2)}'),
                const SizedBox(height: 6),
                _calcRow('Discount (${_discountRate.toStringAsFixed(0)}%):', '- KSH ${_discountAmount.toStringAsFixed(2)}', color: Colors.orange.shade800),
                const SizedBox(height: 6),
                _calcRow('Subtotal After Discount:', 'KSH ${_subtotalAfterDiscount.toStringAsFixed(2)}'),
                const SizedBox(height: 6),
                _calcRow('VAT (16%):', '+ KSH ${_vatAmount.toStringAsFixed(2)}'),
                const Divider(),
                _calcRow('Final Total:', 'KSH ${_grandTotal.toStringAsFixed(2)}', isBold: true, fontSize: 18, color: const Color(0xFF1E3A8A)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _submitEstimate,
              icon: const Icon(Icons.check_circle_outline),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
              label: _isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Save Official Estimate to Database', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }

  Widget _calcRow(String label, String value, {bool isBold = false, double fontSize = 14, Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: fontSize, fontWeight: isBold ? FontWeight.bold : FontWeight.w500)),
        Text(value, style: TextStyle(fontSize: fontSize, fontWeight: isBold ? FontWeight.bold : FontWeight.w600, color: color)),
      ],
    );
  }
}
