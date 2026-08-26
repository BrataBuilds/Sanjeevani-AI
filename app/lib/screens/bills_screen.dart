import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
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
    final c = context.sc;

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
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(SanjeevaniSpace.xl),
                        decoration: BoxDecoration(
                          color: c.surface,
                          border: Border.all(color: c.line, width: 1.5, style: BorderStyle.solid),
                          borderRadius: BorderRadius.circular(SanjeevaniRadius.lg),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                border: Border.all(color: c.stub),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('NOT CONNECTED',
                                  style: TextStyle(
                                      fontSize: 11,
                                      letterSpacing: 1.4,
                                      fontWeight: FontWeight.w500,
                                      color: c.stub)),
                            ),
                            const SizedBox(height: SanjeevaniSpace.md),
                            Text('Billing is not available yet',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontSize: 19, fontWeight: FontWeight.w600)),
                            const SizedBox(height: SanjeevaniSpace.sm),
                            Text(
                              'This hospital has not connected billing to Sanjeevani. Ask at the '
                              'counter for any payment receipt. Your visit records below are complete.',
                              style: TextStyle(fontSize: 16, color: c.ink2, height: 1.6),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: SanjeevaniSpace.lg),
                    Text('VISITS', style: Theme.of(context).textTheme.labelSmall),
                    const SizedBox(height: SanjeevaniSpace.sm),
                    if (visits.isEmpty) const Text('No visits yet'),
                    for (final v in visits)
                      Container(
                        margin: const EdgeInsets.only(bottom: SanjeevaniSpace.sm),
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: c.surface,
                          border: Border.all(color: c.line),
                          borderRadius: BorderRadius.circular(SanjeevaniRadius.lg),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.confirmation_number_outlined, color: c.ink3, size: 20),
                            const SizedBox(width: SanjeevaniSpace.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('Token #${v['token_no']} · ${v['hospital_name']}',
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                  Text(
                                    [
                                      '${v['token_date']}',
                                      '${v['status']}'.replaceAll('_', ' '),
                                      if (v['department_name'] != null) '${v['department_name']}',
                                    ].join('  ·  '),
                                    style: TextStyle(fontSize: 14, color: c.ink2),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: SanjeevaniSpace.md),
                    Text('BILLS YOU UPLOADED', style: Theme.of(context).textTheme.labelSmall),
                    const SizedBox(height: SanjeevaniSpace.sm),
                    if (uploaded.isEmpty)
                      Text(
                        'None. Upload a bill from your profile and label it "bill" or '
                        '"receipt" and it will show up here.',
                        style: TextStyle(fontSize: 15, color: c.ink2),
                      ),
                    ...uploaded.map((d) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: '${d['mime']}'.startsWith('image/')
                              ? AuthedImage(path: '/files/${d['file_id']}', width: 40, height: 40)
                              : const Icon(Icons.picture_as_pdf_outlined),
                          title: Text('${d['label']}'),
                          subtitle: Text('${d['created_at']}'),
                        )),
                    const SizedBox(height: SanjeevaniSpace.xxl),
                  ],
                ),
    );
  }
}
