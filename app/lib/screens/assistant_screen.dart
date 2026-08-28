import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';
import 'chat_screen.dart';

/// The list of assistant consultations.
///
/// One thread per problem, not one thread forever. The assistant reads the whole
/// transcript back on every turn, so a rash from March sitting above today's
/// chest pain does not just look untidy — it is context the triage has to work
/// around. Keeping them apart is what makes each consultation legible to the
/// doctor who later reads it.
class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  List _threads = [];
  bool _loading = true;
  bool _starting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final threads = await Api.instance.conversations(kind: 'ai');
      if (!mounted) return;
      setState(() {
        _threads = threads;
        _loading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _start() async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      // force_new only once the list already has something in it: on a first run
      // the server's untouched thread is exactly the one to open.
      final conv = await Api.instance.openAiThread(forceNew: _threads.isNotEmpty);
      if (!mounted) return;
      await _open(conv['id'] as String, _titleOf(conv));
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  /// A thread is named after the complaint that opened it, but it has no name
  /// until the patient has actually said something.
  String _titleOf(Map thread) {
    final title = '${thread['title'] ?? ''}'.trim();
    if (title.isEmpty || title == 'Triage assistant') return 'New consultation';
    return title;
  }

  Future<void> _open(String conversationId, String title) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          conversationId: conversationId,
          kind: 'ai',
          title: title,
          subtitle: 'Health assistant',
          showBackButton: true,
        ),
      ),
    );
    // The title is set server-side from the first thing the patient says, so the
    // list is stale the moment a new consultation has been used.
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assistant'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _starting ? null : _start,
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('New consultation'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _Retry(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _threads.isEmpty
                      ? ListView(
                          children: [
                            const SizedBox(height: 80),
                            Icon(Icons.smart_toy_outlined, size: 40, color: c.ink3),
                            const SizedBox(height: 12),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 32),
                              child: Text(
                                'No consultations yet. Start one and describe what is '
                                'bothering you — keep a separate one for each problem.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: c.ink2),
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 88),
                          itemCount: _threads.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final t = _threads[i] as Map;
                            final unused = (t['patient_messages'] as int? ?? 0) == 0;
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: unused ? c.surface2 : c.accSoft,
                                child: Icon(
                                  unused ? Icons.add_comment_outlined : Icons.smart_toy_outlined,
                                  color: unused ? c.ink3 : c.acc,
                                ),
                              ),
                              title: Text(
                                _titleOf(t),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: unused ? c.ink2 : c.ink,
                                ),
                              ),
                              subtitle: Text(
                                t['triage_pending'] == true
                                    ? 'The assistant is thinking…'
                                    : '${t['last_message'] ?? 'Not started yet'}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => _open(t['id'] as String, _titleOf(t)),
                            );
                          },
                        ),
                ),
    );
  }
}

class _Retry extends StatelessWidget {
  const _Retry({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
