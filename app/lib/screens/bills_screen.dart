import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets/authed_image.dart';

/// appfeature.md 1.4 asks for a place to see collected bills and visit info.
/// Billing itself is Phase 2 in Design_doc.md §6, so the server has no bill table
/// yet — this shows the visit ledger and any bill the patient uploaded, and says
/// plainly that hospital billing is not connected.
class BillsScreen extends StatefulWidget {
  const BillsScreen({super.key});

  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final out = await Api.instance.bills();
      if (mounted) {
        setState(() {
          _data = out;
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visits = (_data?['visits'] as List?) ?? const [];
    final uploaded = (_data?['uploaded_bills'] as List?) ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('Bills and records')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_data?['billing_enabled'] != true)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            'Hospital billing is not connected yet, so nothing is charged or '
                            'settled here. Your visits and any bills you uploaded yourself '
                            'are listed below.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),

                    const SizedBox(height: 12),
                    Text('Visits', style: Theme.of(context).textTheme.titleSmall),
                    if (visits.isEmpty) const Text('No visits yet'),
                    ...visits.map((v) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.confirmation_number_outlined),
                          title: Text('Token #${v['token_no']} · ${v['hospital_name']}'),
                          subtitle: Text([
                            '${v['token_date']}',
                            '${v['status']}'.replaceAll('_', ' '),
                            if (v['department_name'] != null) '${v['department_name']}',
                          ].join('  ·  ')),
                        )),

                    const SizedBox(height: 20),
                    Text('Bills you uploaded', style: Theme.of(context).textTheme.titleSmall),
                    if (uploaded.isEmpty)
                      const Text(
                        'None. Upload a bill from your profile and label it "bill" or '
                        '"receipt" and it will show up here.',
                      ),
                    ...uploaded.map((d) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: '${d['mime']}'.startsWith('image/')
                              ? AuthedImage(path: '/files/${d['file_id']}', width: 40, height: 40)
                              : const Icon(Icons.picture_as_pdf_outlined),
                          title: Text('${d['label']}'),
                          subtitle: Text('${d['created_at']}'),
                        )),
                    const SizedBox(height: 32),
                  ],
                ),
    );
  }
}
