import 'package:flutter/material.dart';

import '../api.dart';
import 'chat_screen.dart';

/// The hospital-side chat list. Threads usually appear because a doctor opened
/// one from their dashboard; a patient can also start one with any hospital.
class CareTeamScreen extends StatefulWidget {
  const CareTeamScreen({super.key});

  @override
  State<CareTeamScreen> createState() => _CareTeamScreenState();
}

class _CareTeamScreenState extends State<CareTeamScreen> {
  List _threads = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await Api.instance.conversations();
      if (!mounted) return;
      setState(() {
        _threads = all.where((c) => c['kind'] == 'care_team').toList();
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

  Future<void> _startThread() async {
    try {
      final hospitals = await Api.instance.hospitals();
      if (!mounted) return;
      final chosen = await showModalBottomSheet<Map>(
        context: context,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('Message which hospital?')),
              for (final h in hospitals)
                ListTile(
                  leading: const Icon(Icons.local_hospital_outlined),
                  title: Text('${h['name']}'),
                  subtitle: Text([
                    if (h['city'] != null) '${h['city']}',
                    if (h['distance_km'] != null) '${h['distance_km']} km',
                    '${h['queue_length'] ?? 0} in queue',
                  ].join('  ·  ')),
                  onTap: () => Navigator.pop(context, h as Map),
                ),
            ],
          ),
        ),
      );
      if (chosen == null) return;
      final conv = await Api.instance.openCareTeamThread(chosen['id'] as String);
      if (!mounted) return;
      await _open(conv['id'] as String, '${chosen['name']}');
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _open(String conversationId, String title) => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            conversationId: conversationId,
            kind: 'care_team',
            title: title,
            subtitle: 'Hospital staff',
            showBackButton: true,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hospital'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startThread,
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('New'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _threads.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 80),
                            Icon(Icons.medical_services_outlined, size: 40),
                            SizedBox(height: 12),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 32),
                              child: Text(
                                'No hospital conversations yet. Staff will appear here once '
                                'they message you, or start one yourself.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          itemCount: _threads.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final t = _threads[i];
                            return ListTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.medical_services_outlined),
                              ),
                              title: Text('${t['hospital_name'] ?? t['title'] ?? 'Care team'}'),
                              subtitle: Text(
                                '${t['last_message'] ?? 'No messages yet'}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => _open(
                                t['id'] as String,
                                '${t['hospital_name'] ?? 'Care team'}',
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}
