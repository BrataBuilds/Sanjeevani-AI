import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../app_state.dart';
import '../pick_file.dart';
import '../widgets/authed_image.dart';

/// One chat widget for both surfaces.
///  kind == 'ai'        -> the triage assistant. Replies arrive from the AI seam,
///                         which may take a moment, so we poll.
///  kind == 'care_team' -> real hospital staff.
///
/// The two look deliberately different (icons, labels, colour) so a patient never
/// mistakes the assistant for a doctor.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.kind,
    required this.title,
    this.subtitle,
    this.showBackButton = false,
  });

  final String conversationId;
  final String kind;
  final String title;
  final String? subtitle;
  final bool showBackButton;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

/// Codes match nothing on the server yet — the assistant is told which language
/// the patient picked and the AI layer decides what to do with it.
const _languages = {
  'en': 'English',
  'hi': 'हिन्दी',
  'or': 'ଓଡ଼ିଆ',
  'bn': 'বাংলা',
  'ta': 'தமிழ்',
  'te': 'తెలుగు',
  'mr': 'मराठी',
  'gu': 'ગુજરાતી',
  'kn': 'ಕನ್ನಡ',
  'ml': 'മലയാളം',
  'pa': 'ਪੰਜਾਬੀ',
  'ur': 'اردو',
};

class _ChatScreenState extends State<ChatScreen> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();

  List<Map<String, dynamic>> _messages = [];
  Map<String, dynamic>? _latestStatus;
  bool _thinking = false;
  bool _sending = false;
  bool _loaded = false;
  String? _error;
  String? _newestAt;
  Timer? _poll;

  bool get _isAi => widget.kind == 'ai';

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final out = await Api.instance.messages(widget.conversationId, after: _newestAt);
      if (!mounted) return;
      final incoming = (out['messages'] as List).cast<Map<String, dynamic>>();
      setState(() {
        _error = null;
        _loaded = true;
        _thinking = out['triage_pending'] == true;
        if (incoming.isNotEmpty) {
          _messages = [..._messages, ...incoming];
          _newestAt = incoming.last['created_at'] as String;
          final status = _messages.lastWhere(
            (m) => m['kind'] == 'status',
            orElse: () => const {},
          );
          if (status.isNotEmpty) _latestStatus = status;
        }
      });
      if (incoming.isNotEmpty) _scrollToEnd();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _guard(Future<void> Function() action) async {
    setState(() => _sending = true);
    try {
      await action();
      await _refresh();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    _composer.clear();
    await _guard(() async {
      await Api.instance.sendMessage(
        widget.conversationId,
        text,
        language: _isAi ? AppState.instance.language : null,
      );
      if (_isAi && mounted) setState(() => _thinking = true);
    });
  }

  Future<void> _sendImage() async {
    final picked = await pickAttachment(imagesOnly: true);
    if (picked == null) return;
    await _guard(() => Api.instance
        .sendAttachment(widget.conversationId, picked.bytes, picked.name)
        .then((_) {}));
  }

  Future<void> _answerMcq(Map<String, dynamic> message, Map<String, dynamic> answers) =>
      _guard(() async {
        await Api.instance.answerMcq(widget.conversationId, message['id'] as String, answers);
        if (mounted) setState(() => _thinking = true);
      });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: widget.showBackButton,
        title: Row(
          children: [
            Icon(_isAi ? Icons.smart_toy : Icons.medical_services, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
                  if (widget.subtitle != null)
                    Text(widget.subtitle!, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_isAi)
            ListenableBuilder(
              listenable: AppState.instance,
              builder: (context, _) => PopupMenuButton<String>(
                icon: const Icon(Icons.translate),
                tooltip: 'Language',
                initialValue: AppState.instance.language,
                onSelected: (code) => AppState.instance.setLanguage(code),
                itemBuilder: (context) => _languages.entries
                    .map((e) => PopupMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_isAi)
            Container(
              width: double.infinity,
              color: scheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                'This assistant decides which doctor to send you to. It does not diagnose.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),

          // The hospital status bar appfeature.md asks for: token, department, doctor.
          if (_latestStatus != null) _StatusBar(payload: _latestStatus!['payload'] as Map?),

          if (_error != null)
            Container(
              width: double.infinity,
              color: scheme.errorContainer,
              padding: const EdgeInsets.all(8),
              child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer)),
            ),

          Expanded(
            child: !_loaded
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length + (_thinking ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i == _messages.length) return const _Thinking();
                      return _MessageTile(
                        message: _messages[i],
                        onAnswerMcq: _answerMcq,
                        busy: _sending,
                      );
                    },
                  ),
          ),

          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Send a photo',
                    onPressed: _sending ? null : _sendImage,
                    icon: const Icon(Icons.image_outlined),
                  ),
                  IconButton(
                    tooltip: 'Voice input',
                    // Mock, per appfeature.md 1.2. The backend already accepts audio
                    // attachments, so wiring real speech-to-text needs no API change.
                    onPressed: _sending
                        ? null
                        : () => ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Voice input is not wired up yet.'),
                              ),
                            ),
                    icon: const Icon(Icons.mic_none_outlined),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _composer,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: _isAi
                            ? 'Describe what is bothering you'
                            : 'Message the hospital',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text('Working on it…', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.payload});
  final Map? payload;

  @override
  Widget build(BuildContext context) {
    if (payload == null || payload!['token_no'] == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final urgent = payload!['red_flag'] == true || payload!['urgency'] == 1;

    return Container(
      width: double.infinity,
      color: urgent ? scheme.errorContainer : scheme.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(urgent ? Icons.priority_high : Icons.confirmation_number_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Token #${payload!['token_no']} · ${payload!['department'] ?? 'Front desk'}'
              '${payload!['doctor'] == null ? '' : ' · ${payload!['doctor']}'}'
              '\n${payload!['hospital'] ?? ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({required this.message, required this.onAnswerMcq, required this.busy});

  final Map<String, dynamic> message;
  final Future<void> Function(Map<String, dynamic>, Map<String, dynamic>) onAnswerMcq;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final role = message['sender_role'] as String;
    final kind = message['kind'] as String;
    final mine = role == 'patient';
    final scheme = Theme.of(context).colorScheme;

    if (kind == 'status') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Text(
            '${message['body'] ?? ''}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }

    Widget content;
    switch (kind) {
      case 'mcq':
        content = _McqCard(message: message, onSubmit: onAnswerMcq, busy: busy);
        break;
      case 'report':
        content = _ReportCard(payload: message['payload'] as Map? ?? const {});
        break;
      case 'hospital_suggestion':
        content = _HospitalList(payload: message['payload'] as Map? ?? const {});
        break;
      default:
        content = _Bubble(
          mine: mine,
          role: role,
          body: message['body'] as String?,
          filePath: message['file_url'] as String?,
          isAudio: kind == 'audio',
        );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!mine) ...[
                Icon(_iconFor(role), size: 14, color: scheme.outline),
                const SizedBox(width: 4),
              ],
              Text(_labelFor(role, message['sender_name'] as String?),
                  style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
          const SizedBox(height: 2),
          content,
        ],
      ),
    );
  }

  static IconData _iconFor(String role) => switch (role) {
        'ai' => Icons.smart_toy,
        'doctor' => Icons.medical_services,
        'system' => Icons.info_outline,
        _ => Icons.person,
      };

  static String _labelFor(String role, String? name) => switch (role) {
        'ai' => 'Assistant',
        'doctor' => name ?? 'Care team',
        'system' => 'Hospital',
        _ => 'You',
      };
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.mine,
    required this.role,
    this.body,
    this.filePath,
    this.isAudio = false,
  });

  final bool mine;
  final String role;
  final String? body;
  final String? filePath;
  final bool isAudio;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = mine
        ? scheme.primary
        : role == 'ai'
            ? scheme.surfaceContainerHighest
            : scheme.secondaryContainer;
    final foreground = mine ? scheme.onPrimary : scheme.onSurface;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (filePath != null && !isAudio)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: AuthedImage(path: filePath!, width: 180, height: 180),
              ),
            if (filePath != null && isAudio)
              Row(
                children: [
                  Icon(Icons.graphic_eq, size: 16, color: foreground),
                  const SizedBox(width: 6),
                  Text('Voice note', style: TextStyle(color: foreground)),
                ],
              ),
            if (body != null && body!.isNotEmpty)
              Text(body!, style: TextStyle(color: foreground)),
          ],
        ),
      ),
    );
  }
}

/// The MCQ UI from appfeature.md — the assistant asks, the patient taps.
class _McqCard extends StatefulWidget {
  const _McqCard({required this.message, required this.onSubmit, required this.busy});

  final Map<String, dynamic> message;
  final Future<void> Function(Map<String, dynamic>, Map<String, dynamic>) onSubmit;
  final bool busy;

  @override
  State<_McqCard> createState() => _McqCardState();
}

class _McqCardState extends State<_McqCard> {
  final Map<String, String> _answers = {};
  bool _submitted = false;

  @override
  Widget build(BuildContext context) {
    final questions = ((widget.message['payload'] as Map?)?['questions'] as List?) ?? const [];
    final complete = questions.every((q) => _answers.containsKey(q['id']));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('A few quick questions', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            for (final q in questions) ...[
              const SizedBox(height: 8),
              Text('${q['question']}'),
              Wrap(
                spacing: 6,
                children: [
                  for (final option in (q['options'] as List? ?? const []))
                    ChoiceChip(
                      label: Text('$option'),
                      selected: _answers[q['id']] == option,
                      onSelected: _submitted
                          ? null
                          : (_) => setState(() => _answers[q['id'] as String] = '$option'),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: (!complete || _submitted || widget.busy)
                  ? null
                  : () async {
                      setState(() => _submitted = true);
                      await widget.onSubmit(widget.message, _answers);
                    },
              child: Text(_submitted ? 'Sent' : 'Send answers'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Plain-language version of the preliminary report. The clinical wording goes to
/// the doctor's dashboard, not here.
class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.payload});
  final Map payload;

  @override
  Widget build(BuildContext context) {
    final urgency = payload['urgency'] as int?;
    final redFlag = payload['red_flag'] == true;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      color: redFlag ? scheme.errorContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(redFlag ? Icons.warning_amber : Icons.assignment_outlined, size: 18),
                const SizedBox(width: 6),
                Text(redFlag ? 'Go to emergency now' : 'Preliminary summary',
                    style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            if (payload['chief_complaint'] != null) ...[
              const SizedBox(height: 8),
              Text('What you told us: ${payload['chief_complaint']}'),
            ],
            if (payload['summary'] != null) ...[
              const SizedBox(height: 8),
              Text('${payload['summary']}'),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (payload['specialty'] != null)
                  Chip(label: Text('${payload['specialty']}'.replaceAll('_', ' '))),
                if (urgency != null) Chip(label: Text(_urgencyWords(urgency))),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'A doctor reviews this before you are seen. It is not a diagnosis.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  static String _urgencyWords(int u) => switch (u) {
        1 => 'Needs care immediately',
        2 => 'Needs care very soon',
        3 => 'Should be seen today',
        4 => 'Routine appointment',
        _ => 'Not urgent',
      };
}

class _HospitalList extends StatelessWidget {
  const _HospitalList({required this.payload});
  final Map payload;

  @override
  Widget build(BuildContext context) {
    final hospitals = (payload['hospitals'] as List?) ?? const [];
    if (hospitals.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Where you could go', style: Theme.of(context).textTheme.titleSmall),
            for (final h in hospitals)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.local_hospital_outlined),
                title: Text('${h['name']}'),
                subtitle: Text([
                  if (h['distance_km'] != null) '${h['distance_km']} km away',
                  if (h['reason'] != null) '${h['reason']}',
                ].join('\n')),
              ),
          ],
        ),
      ),
    );
  }
}
