import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../app_state.dart';
import '../location.dart';
import '../pick_file.dart';
import '../theme.dart';
import '../widgets/authed_image.dart';

/// The one-time profile setup from appfeature.md 1.2, reused as the edit screen
/// (`setup: false`) so there is only one place that knows the field list.
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key, this.setup = true});

  final bool setup;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

const _genders = ['male', 'female', 'other', 'prefer_not_to_say'];
const _bloodTypes = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
const _conditionKinds = ['disease', 'allergy', 'genetic'];
const _relations = ['guardian', 'parent', 'spouse', 'sibling', 'child', 'other'];

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _insurer = TextEditingController();
  final _policy = TextEditingController();

  DateTime? _dob;
  String? _gender;
  String? _bloodType;
  double? _lat;
  double? _lng;
  String? _photoPath;

  Map<String, dynamic>? _profile;
  List _conditions = [];
  List _relatives = [];
  List _documents = [];
  List _hospitals = [];
  Set<String> _preferred = {};

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _insurer.dispose();
    _policy.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await Api.instance.profile();
      final hospitals = await Api.instance.hospitals();
      if (!mounted) return;
      setState(() {
        _profile = p;
        _name.text = (p['full_name'] as String?) ?? '';
        _phone.text = (p['phone'] as String?) ?? '';
        _address.text = (p['address'] as String?) ?? '';
        _insurer.text = (p['insurance_provider'] as String?) ?? '';
        _policy.text = (p['policy_number'] as String?) ?? '';
        _dob = p['dob'] == null ? null : DateTime.tryParse(p['dob'] as String);
        _gender = _genders.contains(p['gender']) ? p['gender'] as String : null;
        _bloodType = _bloodTypes.contains(p['blood_type']) ? p['blood_type'] as String : null;
        _lat = (p['lat'] as num?)?.toDouble();
        _lng = (p['lng'] as num?)?.toDouble();
        _photoPath = p['profile_file_id'] == null ? null : '/files/${p['profile_file_id']}';
        _conditions = p['conditions'] as List? ?? [];
        _relatives = p['relatives'] as List? ?? [];
        _preferred = ((p['preferred_hospitals'] as List?) ?? [])
            .map((h) => h['id'] as String)
            .toSet();
        _hospitals = hospitals;
        _loading = false;
      });
      final docs = await Api.instance.documents();
      if (mounted) setState(() => _documents = docs);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on ApiException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_dob == null) {
      _toast('Date of birth is needed so the hospital knows your age.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Api.instance.saveProfile({
        'full_name': _name.text.trim(),
        'dob': _dob!.toIso8601String().split('T').first,
        'gender': _gender,
        'blood_type': _bloodType,
        'phone': _phone.text.trim(),
        'address': _address.text.trim(),
        'insurance_provider': _insurer.text.trim(),
        'policy_number': _policy.text.trim(),
        if (_lat != null) 'lat': _lat,
        if (_lng != null) 'lng': _lng,
        'profile_complete': true,
      });
      await Api.instance.setPreferredHospitals(_preferred.toList());
      await AppState.instance.refresh();
      if (!mounted) return;
      if (widget.setup) {
        // The gate in main.dart swaps to the home shell once profile_complete flips.
      } else {
        Navigator.of(context).pop();
      }
      _toast('Profile saved.');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.setup ? 'Set up your profile' : 'Edit profile'),
        actions: [
          if (widget.setup)
            TextButton(
              onPressed: AppState.instance.signOut,
              child: const Text('Sign out'),
            ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.setup)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'This is filled in once. On every later visit, registration takes '
                    'seconds because the hospital already has all of it.',
                  ),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),

            _section('Photo and name'),
            Row(
              children: [
                _photoPath == null
                    ? Container(
                        width: 64,
                        height: 64,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: context.sc.surface2,
                          border: Border.all(color: context.sc.line),
                          borderRadius: BorderRadius.circular(SanjeevaniRadius.md),
                        ),
                        child: Icon(Icons.person_outline, color: context.sc.ink3),
                      )
                    : AuthedImage(
                        path: _photoPath!,
                        width: 64,
                        height: 64,
                        borderRadius: SanjeevaniRadius.md,
                      ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _pickPhoto,
                  icon: const Icon(Icons.photo_outlined),
                  label: Text(_photoPath == null ? 'Add photo' : 'Change photo'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Full name'),
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Email'),
              subtitle: Text('${_profile?['email'] ?? ''}'),
            ),

            _section('Basic details'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date of birth'),
              subtitle: Text(_dob == null
                  ? 'Not set'
                  : '${_dob!.toIso8601String().split('T').first}'
                      '${_profile?['age'] == null ? '' : '  ·  age ${_ageOf(_dob!)}'}'),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: _pickDob,
            ),
            DropdownButtonFormField<String>(
              initialValue: _gender,
              decoration: const InputDecoration(labelText: 'Gender'),
              items: _genders
                  .map((g) => DropdownMenuItem(value: g, child: Text(g.replaceAll('_', ' '))))
                  .toList(),
              onChanged: (v) => setState(() => _gender = v),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _bloodType,
              decoration: const InputDecoration(labelText: 'Blood type'),
              items: _bloodTypes.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
              onChanged: (v) => setState(() => _bloodType = v),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _phone,
              decoration: const InputDecoration(labelText: 'Phone'),
              keyboardType: TextInputType.phone,
              validator: (v) => (v == null || v.trim().length < 6) ? 'Required' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _address,
              decoration: const InputDecoration(labelText: 'Address'),
              maxLines: 2,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),

            _section('Location'),
            Text(
              _lat == null
                  ? 'Not shared. Used only to sort hospitals by distance.'
                  : 'Saved: ${_lat!.toStringAsFixed(4)}, ${_lng!.toStringAsFixed(4)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _useMyLocation,
              icon: const Icon(Icons.my_location_outlined),
              label: const Text('Use my current location'),
            ),

            _section('Insurance (optional)'),
            TextFormField(
              controller: _insurer,
              decoration: const InputDecoration(labelText: 'Insurance provider'),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _policy,
              decoration: const InputDecoration(labelText: 'Policy number'),
            ),

            _section('Preferred hospitals (optional)'),
            ..._hospitals.map((h) => CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _preferred.contains(h['id']),
                  title: Text('${h['name']}'),
                  subtitle: Text([
                    if (h['city'] != null) '${h['city']}',
                    if (h['distance_km'] != null) '${h['distance_km']} km',
                  ].join('  ·  ')),
                  onChanged: (on) => setState(() {
                    on == true ? _preferred.add(h['id'] as String) : _preferred.remove(h['id']);
                  }),
                )),

            _section('Known conditions, allergies, genetic disorders'),
            ..._conditions.map((c) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Chip(label: Text('${c['kind']}')),
                  title: Text('${c['label']}'),
                  subtitle: c['notes'] == null ? null : Text('${c['notes']}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _guard(() async {
                      await Api.instance.deleteCondition(c['id'] as String);
                      setState(() => _conditions.remove(c));
                    }),
                  ),
                )),
            OutlinedButton.icon(
              onPressed: _addCondition,
              icon: const Icon(Icons.add),
              label: const Text('Add a condition'),
            ),

            _section('People to inform if you are admitted'),
            if (_relatives.isEmpty)
              Text(
                'Please add at least one. If you cannot speak for yourself, this is who '
                'the hospital calls.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ..._relatives.map((r) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.person_outline),
                  title: Text('${r['name']}  ·  ${r['relation']}'),
                  subtitle: Text('${r['contact']}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _guard(() async {
                      await Api.instance.deleteRelative(r['id'] as String);
                      setState(() => _relatives.remove(r));
                    }),
                  ),
                )),
            OutlinedButton.icon(
              onPressed: _addRelative,
              icon: const Icon(Icons.add),
              label: const Text('Add a contact'),
            ),

            _section('Medical history'),
            Text(
              'Photos or scanned PDFs of reports, blood tests, x-rays, prescriptions.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            ..._documents.map((d) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: '${d['mime']}'.startsWith('image/')
                      ? AuthedImage(path: '/files/${d['file_id']}', width: 40, height: 40)
                      : const Icon(Icons.picture_as_pdf_outlined),
                  title: Text('${d['label']}'),
                  subtitle: Text('${d['description'] ?? ''}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _guard(() async {
                      await Api.instance.deleteDocument(d['id'] as String);
                      setState(() => _documents.remove(d));
                    }),
                  ),
                )),
            OutlinedButton.icon(
              onPressed: _addDocument,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Upload a document'),
            ),

            _section('Security and identity (optional)'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_outline),
              title: const Text('App PIN'),
              subtitle: Text(AppState.instance.appLockSet ? 'Set' : 'Not set'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _setPin,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.badge_outlined),
              title: const Text('Aadhaar'),
              subtitle: Text(_profile?['aadhaar_verified'] == true
                  ? 'Linked, ending ${_profile?['aadhaar_last4']}'
                  : 'Not linked'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _linkAadhaar,
            ),

            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving
                  ? 'Saving…'
                  : (widget.setup ? 'Finish and continue' : 'Save changes')),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Text(
          title.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall,
        ),
      );

  static int _ageOf(DateTime dob) {
    final now = DateTime.now();
    var age = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) age--;
    return age;
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 30),
      firstDate: DateTime(now.year - 120),
      lastDate: now,
      helpText: 'Date of birth',
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _useMyLocation() async {
    final at = await currentLatLng();
    if (at == null) {
      _toast('Could not get a location. You can still continue without it.');
      return;
    }
    setState(() {
      _lat = at.lat;
      _lng = at.lng;
    });
    final hospitals = await Api.instance.hospitals(lat: at.lat, lng: at.lng);
    if (mounted) setState(() => _hospitals = hospitals);
  }

  Future<void> _pickPhoto() async {
    final picked = await pickAttachment(imagesOnly: true);
    if (picked == null) return;
    await _guard(() async {
      final file = await Api.instance.uploadProfilePhoto(picked.bytes, picked.name);
      setState(() => _photoPath = '/files/${file['id']}');
    });
  }

  Future<void> _addCondition() async {
    var kind = _conditionKinds.first;
    final label = TextEditingController();
    final notes = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          title: const Text('Add a condition'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: kind,
                decoration: const InputDecoration(labelText: 'Type'),
                items: _conditionKinds
                    .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                    .toList(),
                onChanged: (v) => setInner(() => kind = v ?? kind),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: label,
                decoration: const InputDecoration(labelText: 'Name, e.g. Penicillin'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: notes,
                decoration: const InputDecoration(labelText: 'Notes (optional)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
          ],
        ),
      ),
    );

    if (ok == true && label.text.trim().isNotEmpty) {
      await _guard(() async {
        await Api.instance.addCondition(
          kind,
          label.text.trim(),
          notes.text.trim().isEmpty ? null : notes.text.trim(),
        );
        final fresh = await Api.instance.conditions();
        setState(() => _conditions = fresh);
      });
    }
  }

  Future<void> _addRelative() async {
    var relation = _relations.first;
    final name = TextEditingController();
    final contact = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInner) => AlertDialog(
          title: const Text('Add a contact'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 8),
              TextField(
                controller: contact,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: relation,
                decoration: const InputDecoration(labelText: 'Relation'),
                items: _relations
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) => setInner(() => relation = v ?? relation),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
          ],
        ),
      ),
    );

    if (ok == true && name.text.trim().isNotEmpty && contact.text.trim().isNotEmpty) {
      await _guard(() async {
        await Api.instance.addRelative(name.text.trim(), contact.text.trim(), relation);
        final fresh = await Api.instance.relatives();
        setState(() => _relatives = fresh);
      });
    }
  }

  Future<void> _addDocument() async {
    final picked = await pickAttachment();
    if (picked == null) return;
    if (!mounted) return;

    final label = TextEditingController();
    final description = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Describe this document'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(picked.name, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            TextField(
              controller: label,
              decoration: const InputDecoration(
                labelText: 'What is it?',
                hintText: 'blood test, x-ray, prescription…',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: description,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Upload')),
        ],
      ),
    );

    if (ok == true && label.text.trim().isNotEmpty) {
      await _guard(() async {
        await Api.instance.uploadDocument(
          picked.bytes,
          picked.name,
          label.text.trim(),
          description.text.trim().isEmpty ? null : description.text.trim(),
        );
        final fresh = await Api.instance.documents();
        setState(() => _documents = fresh);
      });
    }
  }

  Future<void> _setPin() async {
    final pin = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('App PIN'),
        content: TextField(
          controller: pin,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: '4 to 12 digits'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) {
      await _guard(() async {
        await Api.instance.setAppLock(pin.text);
        await AppState.instance.refresh();
        _toast('PIN saved.');
      });
    }
  }

  Future<void> _linkAadhaar() async {
    final number = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Link Aadhaar'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Demo only: nothing is sent to UIDAI and nothing is verified. Only the '
              'last four digits are stored, for display.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: number,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: '12-digit number'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Link')),
        ],
      ),
    );
    if (ok == true) {
      await _guard(() async {
        final out = await Api.instance.verifyAadhaar(number.text);
        setState(() {
          _profile?['aadhaar_verified'] = true;
          _profile?['aadhaar_last4'] = out['aadhaar_last4'];
        });
      });
    }
  }
}
