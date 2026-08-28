import 'package:flutter/material.dart';

import '../api.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets/authed_image.dart';
import 'bills_screen.dart';
import 'profile_setup_screen.dart';

/// Read-only view of everything collected at registration, plus the edit and
/// bills entry points appfeature.md 1.4 asks for.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile;
  List _documents = [];
  List _visits = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await Api.instance.profile();
      final docs = await Api.instance.documents();
      final visits = await Api.instance.visits();
      if (!mounted) return;
      setState(() {
        _profile = p;
        _documents = docs;
        _visits = visits;
        _loading = false;
        _error = null;
      });
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
    final p = _profile;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const ProfileSetupScreen(setup: false),
                ),
              );
              _load();
            },
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: AppState.instance.signOut,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Row(
                        children: [
                          p?['profile_file_id'] == null
                              ? Container(
                                  width: 66,
                                  height: 66,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: context.sc.surface2,
                                    borderRadius: BorderRadius.circular(SanjeevaniRadius.lg),
                                  ),
                                  child: Text(_initialsOf(p?['full_name'] as String?),
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                          ?.copyWith(fontSize: 24, color: context.sc.ink2)),
                                )
                              : AuthedImage(
                                  path: '/files/${p!['profile_file_id']}',
                                  width: 66,
                                  height: 66,
                                  borderRadius: SanjeevaniRadius.lg,
                                ),
                          const SizedBox(width: SanjeevaniSpace.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${p?['full_name'] ?? ''}',
                                    style: Theme.of(context).textTheme.titleLarge),
                                Text('${p?['email'] ?? ''}',
                                    style: Theme.of(context).textTheme.bodySmall),
                                if (p?['aadhaar_verified'] == true)
                                  Text('Aadhaar •••• ${p?['aadhaar_last4']}',
                                      style: Theme.of(context).textTheme.bodySmall),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (context) => const BillsScreen()),
                        ),
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: const Text('Bills and visit records'),
                      ),

                      _heading('Details'),
                      _kv('Age', p?['age'] == null ? '—' : '${p?['age']}'),
                      _kv('Date of birth', '${p?['dob'] ?? '—'}'),
                      _kv('Gender', '${p?['gender'] ?? '—'}'.replaceAll('_', ' ')),
                      _kv('Blood type', '${p?['blood_type'] ?? '—'}'),
                      _kv('Phone', '${p?['phone'] ?? '—'}'),
                      _kv('Address', '${p?['address'] ?? '—'}'),
                      _kv(
                        'Location shared',
                        p?['lat'] == null ? 'No' : 'Yes',
                      ),
                      _kv('Language', '${p?['language'] ?? 'en'}'),
                      _kv('App PIN', AppState.instance.appLockSet ? 'Set' : 'Not set'),

                      _heading('Insurance'),
                      _kv('Provider', '${p?['insurance_provider'] ?? '—'}'),
                      _kv('Policy number', '${p?['policy_number'] ?? '—'}'),

                      _heading('Preferred hospitals'),
                      if ((p?['preferred_hospitals'] as List?)?.isEmpty ?? true)
                        const Text('None chosen')
                      else
                        ...((p!['preferred_hospitals'] as List).map(
                          (h) => Text('• ${h['name']}'),
                        )),

                      _heading('Conditions, allergies, genetic disorders'),
                      if ((p?['conditions'] as List?)?.isEmpty ?? true)
                        const Text('None recorded')
                      else
                        ...((p!['conditions'] as List).map((c) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              leading: Chip(label: Text('${c['kind']}')),
                              title: Text('${c['label']}'),
                              subtitle: c['notes'] == null ? null : Text('${c['notes']}'),
                            ))),

                      _heading('People to inform'),
                      if ((p?['relatives'] as List?)?.isEmpty ?? true)
                        const Text('None on file — please add at least one')
                      else
                        ...((p!['relatives'] as List).map((r) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              leading: const Icon(Icons.person_outline),
                              title: Text('${r['name']}  ·  ${r['relation']}'),
                              subtitle: Text('${r['contact']}'),
                            ))),

                      _heading('Medical history (${_documents.length})'),
                      if (_documents.isEmpty)
                        const Text('Nothing uploaded yet')
                      else
                        ..._documents.map((d) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              leading: '${d['mime']}'.startsWith('image/')
                                  ? AuthedImage(
                                      path: '/files/${d['file_id']}', width: 40, height: 40)
                                  : const Icon(Icons.picture_as_pdf_outlined),
                              title: Text('${d['label']}'),
                              subtitle: Text('${d['description'] ?? ''}'),
                            )),

                      _heading('Recent visits (${_visits.length})'),
                      if (_visits.isEmpty)
                        const Text('No visits yet')
                      else
                        ..._visits.take(5).map((v) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              leading: const Icon(Icons.confirmation_number_outlined),
                              title: Text(visitHeadline(v)),
                              subtitle: Text([
                                '${v['token_date']}',
                                '${v['status']}'.replaceAll('_', ' '),
                                if (v['department_name'] != null) '${v['department_name']}',
                              ].join('  ·  ')),
                            )),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
    );
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 6),
        child: Text(text.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
      );

  static String _initialsOf(String? name) {
    final parts = (name ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final initials = parts.length == 1 ? parts[0][0] : '${parts.first[0]}${parts.last[0]}';
    return initials.toUpperCase();
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 140,
              child: Text(k, style: Theme.of(context).textTheme.bodySmall),
            ),
            Expanded(child: Text(v)),
          ],
        ),
      );
}
