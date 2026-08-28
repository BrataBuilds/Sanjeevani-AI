import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../app_state.dart';
import '../pick_file.dart';
import '../theme.dart';
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
  String? _newestId;
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

  /// Polls for new messages. [full] drops the cursor and re-reads the thread.
  Future<void> _refresh({bool full = false}) async {
    try {
      final out = await Api.instance.messages(
        widget.conversationId,
        after: full ? null : _newestAt,
        afterId: full ? null : _newestId,
      );
      if (!mounted) return;
      final incoming = (out['messages'] as List).cast<Map<String, dynamic>>();
      final wasThinking = _thinking;
      var grew = false;
      setState(() {
        _error = null;
        _loaded = true;
        _thinking = out['triage_pending'] == true;
        if (incoming.isNotEmpty) {
          // A poll tick and the refresh after a send can overlap and fetch the
          // same page twice, so drop anything already on screen. Built eagerly:
          // a lazy where() with a mutating predicate would filter differently on
          // a second read.
          final seen = full ? <Object?>{} : _messages.map((m) => m['id']).toSet();
          final fresh =
              incoming.where((m) => !seen.contains(m['id'])).toList(growable: false);
          grew = fresh.isNotEmpty;
          _messages = full ? incoming : [..._messages, ...fresh];
          _newestAt = incoming.last['created_at'] as String;
          _newestId = incoming.last['id'] as String;
          final status = _messages.lastWhere(
            (m) => m['kind'] == 'status',
            orElse: () => const {},
          );
          if (status.isNotEmpty) _latestStatus = status;
        }
      });
      // Only when something was actually appended — a duplicate-only poll must
      // not yank a patient who has scrolled up back to the bottom.
      if (grew) _scrollToEnd();
      // A triage transaction stamps its messages at BEGIN but they only become
      // visible at COMMIT, so one can land behind a cursor this screen already
      // moved past. Re-read the thread once when triage finishes rather than
      // risk silently losing the report and the queue token.
      if (wasThinking && !_thinking && !full) await _refresh(full: true);
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
                : Builder(
                    builder: (context) {
                      // An answered question is shown by the option staying lit on
                      // the card it was asked on. Repeating the choice back as a
                      // chat bubble says nothing the card does not already show,
                      // so the mcq_answer messages are read for their answers and
                      // never rendered. They still go to the server, and the AI
                      // side still reads them out of the transcript.
                      final visible = <Map<String, dynamic>>[];
                      final chosen = <String, Map>{};
                      for (final m in _messages) {
                        if (m['kind'] == 'mcq_answer') {
                          final payload = m['payload'] as Map?;
                          final askedId = payload?['in_reply_to'];
                          final answers = payload?['answers'];
                          if (askedId is String && answers is Map) chosen[askedId] = answers;
                          continue;
                        }
                        visible.add(m);
                      }

                      return ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(12),
                        itemCount: visible.length + (_thinking ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i == visible.length) return const _Thinking();
                          final m = visible[i];
                          return _MessageTile(
                            message: m,
                            answered: chosen[m['id']],
                            onAnswerMcq: _answerMcq,
                            busy: _sending,
                          );
                        },
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

class _Thinking extends StatefulWidget {
  const _Thinking();

  @override
  State<_Thinking> createState() => _ThinkingState();
}

class _ThinkingState extends State<_Thinking> with SingleTickerProviderStateMixin {
  late final _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(22),
            topRight: Radius.circular(22),
            bottomRight: Radius.circular(22),
            bottomLeft: Radius.circular(6),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 5),
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final t = (_controller.value + i * 0.18) % 1.0;
                  final bounce = t < 0.4 ? (1 - (t / 0.4 - 1).abs()) : 0.0;
                  return Transform.translate(
                    offset: Offset(0, -3 * bounce),
                    child: Opacity(
                      opacity: 0.22 + 0.78 * bounce,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(color: c.acc, shape: BoxShape.circle),
                      ),
                    ),
                  );
                },
              ),
            ],
            const SizedBox(width: 11),
            Text('Working on it…', style: TextStyle(fontSize: 15, color: c.ink2)),
          ],
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.payload});
  final Map? payload;

  @override
  Widget build(BuildContext context) {
    if (payload == null) return const SizedBox.shrink();
    final c = context.sc;
    final state = payload!['state'];

    // A token only exists once a doctor has asked the patient to come in. Until
    // then the card has to say what is actually happening, not go blank.
    if (payload!['token_no'] == null) {
      if (state == 'pending_review') {
        return _WaitingCard(
          tint: c.mid,
          title: 'A doctor is reviewing this',
          detail: [
            if (payload!['department'] != null) '${payload!['department']}',
            if (payload!['hospital'] != null) '${payload!['hospital']}',
          ].join(' · '),
          note: 'You will get a token here only if they ask you to come in.',
        );
      }
      if (state == 'chat') {
        return _WaitingCard(
          tint: c.acc,
          title: 'Your doctor will answer you here',
          detail: payload!['doctor'] == null ? '' : '${payload!['doctor']}',
          note: 'No hospital visit needed for now, so no token.',
        );
      }
      return const SizedBox.shrink();
    }
    final urgent = payload!['red_flag'] == true || payload!['urgency'] == 1;
    final bg = urgent ? c.dan : c.acc;
    final fg = urgent ? c.accInk : c.accInk;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(SanjeevaniRadius.lg)),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('TOKEN',
                  style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w500,
                      color: fg.withValues(alpha: 0.85))),
              Text('${payload!['token_no']}',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontSize: 36, height: 0.9, color: fg)),
            ],
          ),
          Container(
            width: 1,
            height: 34,
            margin: const EdgeInsets.symmetric(horizontal: 15),
            color: fg.withValues(alpha: 0.32),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${payload!['department'] ?? 'Front desk'}',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: fg)),
                Text(
                  [
                    if (payload!['doctor'] != null) '${payload!['doctor']}',
                    if (payload!['hospital'] != null) '${payload!['hospital']}',
                  ].join(' · '),
                  style: TextStyle(fontSize: 14, color: fg.withValues(alpha: 0.9)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The two states before a token exists. Same shape as the token card so the
/// thread does not jump around when one replaces the other.
class _WaitingCard extends StatelessWidget {
  const _WaitingCard({
    required this.tint,
    required this.title,
    required this.detail,
    required this.note,
  });

  final Color tint;
  final String title;
  final String detail;
  final String note;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(SanjeevaniRadius.lg),
        border: Border.all(color: tint.withValues(alpha: 0.45), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 6, right: 12),
            decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.ink)),
                if (detail.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(detail, style: TextStyle(fontSize: 14, color: c.ink2)),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(note, style: TextStyle(fontSize: 13, color: c.ink3)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({
    required this.message,
    required this.onAnswerMcq,
    required this.busy,
    this.answered,
  });

  final Map<String, dynamic> message;

  /// question id -> the option this patient picked, once they have answered.
  final Map? answered;
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
        content = _McqCard(
          message: message,
          onSubmit: onAnswerMcq,
          busy: busy,
          answered: answered,
        );
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
    final c = context.sc;
    final background = mine ? c.acc : (role == 'ai' ? c.surface : c.surface2);
    final foreground = mine ? c.accInk : c.ink;
    // AI bubble: bottom-left square (assistant, machine). Human/system bubble:
    // top-left square (a person, per the canvas's chat pattern).
    final radius = mine
        ? const BorderRadius.only(
            topLeft: Radius.circular(22),
            topRight: Radius.circular(22),
            bottomLeft: Radius.circular(22),
            bottomRight: Radius.circular(6),
          )
        : role == 'ai'
            ? const BorderRadius.only(
                topLeft: Radius.circular(22),
                topRight: Radius.circular(22),
                bottomRight: Radius.circular(22),
                bottomLeft: Radius.circular(6),
              )
            : const BorderRadius.only(
                topRight: Radius.circular(22),
                bottomRight: Radius.circular(22),
                bottomLeft: Radius.circular(22),
                topLeft: Radius.circular(6),
              );

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 14),
        decoration: BoxDecoration(
          color: background,
          borderRadius: radius,
          border: (!mine && role == 'ai') ? Border.all(color: c.line) : null,
        ),
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
  const _McqCard({
    required this.message,
    required this.onSubmit,
    required this.busy,
    this.answered,
  });

  final Map<String, dynamic> message;

  /// Set once the server has this card's answers, so a card stays answered
  /// across a reload rather than resetting to a fresh set of options.
  final Map? answered;
  final Future<void> Function(Map<String, dynamic>, Map<String, dynamic>) onSubmit;
  final bool busy;

  @override
  State<_McqCard> createState() => _McqCardState();
}

class _McqCardState extends State<_McqCard> {
  final Map<String, String> _answers = {};
  bool _submitted = false;

  /// A single-choice question answers itself the moment an option is tapped.
  /// Asking someone to pick one of four and then press Send is a second decision
  /// about the same thing; only a multi-question card needs the button.
  bool _sendsOnTap(List questions) =>
      questions.length == 1 && questions.first['multi'] != true;

  Future<void> _choose(Map question, String option, List questions) async {
    if (_submitted) return;
    setState(() => _answers[question['id'] as String] = option);
    if (!_sendsOnTap(questions)) return;
    setState(() => _submitted = true);
    await widget.onSubmit(widget.message, Map<String, dynamic>.from(_answers));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    final questions = ((widget.message['payload'] as Map?)?['questions'] as List?) ?? const [];
    final complete = questions.every((q) => _answers.containsKey(q['id']));

    // The server's record wins: it survives a reload, local state does not.
    final recorded = widget.answered;
    final locked = _submitted || recorded != null;
    final autoSend = _sendsOnTap(questions);
    String? pickedFor(Object? id) {
      final fromServer = recorded == null ? null : recorded[id];
      return fromServer is String ? fromServer : _answers[id];
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(SanjeevaniRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Only a multi-question card needs a heading of its own: a single
          // question is its own heading, and repeating it above the options is
          // the same sentence twice.
          if (questions.length > 1)
            Text('A few quick questions',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          for (final q in questions) ...[
            if (questions.length > 1) const SizedBox(height: SanjeevaniSpace.md),
            Text('${q['question']}',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.ink)),
            const SizedBox(height: SanjeevaniSpace.sm),
            for (final option in (q['options'] as List? ?? const []))
              Padding(
                padding: const EdgeInsets.only(bottom: SanjeevaniSpace.sm),
                child: _McqOption(
                  label: '$option',
                  selected: pickedFor(q['id']) == '$option',
                  disabled: locked || widget.busy,
                  onTap: () => _choose(q, '$option', questions),
                ),
              ),
          ],
          if (!autoSend) ...[
            const SizedBox(height: SanjeevaniSpace.sm),
            if (!locked)
              FilledButton(
                onPressed: (!complete || widget.busy)
                    ? null
                    : () async {
                        setState(() => _submitted = true);
                        await widget.onSubmit(widget.message, _answers);
                      },
                child: const Text('Send answer'),
              )
            else
              Row(
                children: [
                  Container(
                    width: 17,
                    height: 17,
                    alignment: Alignment.center,
                    decoration:
                        BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.ink3)),
                    child: Text('✓', style: TextStyle(fontSize: 10, color: c.ink3)),
                  ),
                  const SizedBox(width: SanjeevaniSpace.sm),
                  Text('Answer sent.', style: TextStyle(fontSize: 14, color: c.ink3)),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

class _McqOption extends StatelessWidget {
  const _McqOption({
    required this.label,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(SanjeevaniRadius.md),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          border: Border.all(color: selected ? c.acc : c.line, width: 1.5),
          borderRadius: BorderRadius.circular(SanjeevaniRadius.md),
          color: selected ? c.accSoft : c.bg,
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: selected ? c.acc : c.ink3, width: 2),
                color: selected ? c.acc : Colors.transparent,
              ),
            ),
            const SizedBox(width: SanjeevaniSpace.md),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: (disabled && !selected) ? c.ink3 : (selected ? c.acc : c.ink),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Plain-language version of the preliminary report. The clinical wording goes to
/// the doctor's dashboard, not here.
///
/// A red-flag payload takes over the whole card as a hazard-striped, full-bleed
/// warning (the canvas is explicit this must never be just a tinted badge). There
/// is deliberately no "call ambulance" / "alert staff" action button here: the app
/// has no dialer integration and no staff-alert endpoint, so a button that looked
/// actionable but did nothing would be worse than the plain text.
class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.payload});
  final Map payload;

  @override
  Widget build(BuildContext context) {
    final urgency = payload['urgency'] as int?;
    final redFlag = payload['red_flag'] == true;
    final c = context.sc;

    if (redFlag) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: c.dan, borderRadius: BorderRadius.circular(SanjeevaniRadius.xl)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: c.accInk, size: 22),
                const SizedBox(width: SanjeevaniSpace.sm),
                Text('POSSIBLE EMERGENCY',
                    style: TextStyle(
                        color: c.accInk,
                        fontSize: 13,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: SanjeevaniSpace.md),
            Text('Please get help now, not later',
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontSize: 26, color: c.accInk)),
            const SizedBox(height: SanjeevaniSpace.sm),
            Text(
              'What you described can be serious. Do not wait in the queue. Show this '
              'screen to any staff member at the entrance.',
              style: TextStyle(color: c.accInk, fontSize: 16, height: 1.5),
            ),
            if (payload['chief_complaint'] != null) ...[
              const SizedBox(height: SanjeevaniSpace.md),
              Container(
                padding: const EdgeInsets.only(left: SanjeevaniSpace.md),
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: c.accInk.withValues(alpha: 0.45), width: 2)),
                ),
                child: Text(
                  'Flagged because: ${payload['chief_complaint']}. This is a warning, not a diagnosis.',
                  style: TextStyle(color: c.accInk.withValues(alpha: 0.9), fontSize: 14, height: 1.4),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(SanjeevaniRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: c.accSoft,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('AI SUGGESTION',
                    style: TextStyle(
                        fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w500, color: c.acc)),
              ),
              const SizedBox(width: SanjeevaniSpace.sm),
              Expanded(
                child: Text('Preliminary summary',
                    style: Theme.of(context).textTheme.titleLarge),
              ),
            ],
          ),
          if (payload['chief_complaint'] != null) ...[
            const SizedBox(height: SanjeevaniSpace.lg),
            Text('CHIEF COMPLAINT', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 4),
            Text('${payload['chief_complaint']}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 22)),
          ],
          if (payload['summary'] != null) ...[
            const SizedBox(height: SanjeevaniSpace.md),
            Text('${payload['summary']}', style: TextStyle(fontSize: 16, color: c.ink, height: 1.5)),
          ],
          if (urgency != null) ...[
            const SizedBox(height: SanjeevaniSpace.lg),
            UrgencyScale(level: urgency),
          ],
          if (payload['specialty'] != null) ...[
            const SizedBox(height: SanjeevaniSpace.md),
            Text('SUGGESTED DEPARTMENT', style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 4),
            Text('${payload['specialty']}'.replaceAll('_', ' '),
                style: TextStyle(fontSize: 16, color: c.ink)),
          ],
          const SizedBox(height: SanjeevaniSpace.md),
          Text(
            'A suggestion for routing, not a diagnosis. The doctor decides and can change all of it.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Numeral, notch height and word each carry the urgency level — colour is a
/// fourth channel, never the only one. 1 is most urgent, 5 is least.
class UrgencyScale extends StatelessWidget {
  const UrgencyScale({super.key, required this.level});
  final int level;

  @override
  Widget build(BuildContext context) {
    final c = context.sc;
    final fg = UrgencyLevel.colorOf(c, level);
    final filled = 6 - level;

    return Row(
      children: [
        Text('$level',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontSize: 22, color: fg, height: 1)),
        const SizedBox(width: SanjeevaniSpace.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 1; i <= 5; i++)
              Padding(
                padding: const EdgeInsets.only(right: 3),
                child: Container(
                  width: 6,
                  height: (6 + i * 3).toDouble(),
                  decoration: BoxDecoration(
                    color: i <= filled ? fg : Colors.transparent,
                    border: Border.all(color: i <= filled ? fg : c.line),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: SanjeevaniSpace.md),
        Expanded(
          child: Text(UrgencyLevel.labelOf(level),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: fg)),
        ),
      ],
    );
  }
}

/// The canvas's hospital cards add a per-hospital queue-load bar and a "Choose
/// this hospital" button, but neither has a real counterpart here: the API
/// exposes no queue-length field on a suggestion and no endpoint to pick one
/// (picking a hospital happens by messaging the care team, on the Hospital
/// tab). This keeps the card language (radius, indent, type scale) without
/// fabricating either.
class _HospitalList extends StatelessWidget {
  const _HospitalList({required this.payload});
  final Map payload;

  @override
  Widget build(BuildContext context) {
    final hospitals = (payload['hospitals'] as List?) ?? const [];
    if (hospitals.isEmpty) return const SizedBox.shrink();
    final c = context.sc;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(SanjeevaniRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('WHERE YOU COULD GO', style: Theme.of(context).textTheme.labelSmall),
          for (final h in hospitals) ...[
            const SizedBox(height: SanjeevaniSpace.md),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: c.bg,
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(SanjeevaniRadius.lg),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text('${h['name']}',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                      ),
                      if (h['distance_km'] != null)
                        Text('${h['distance_km']} km', style: TextStyle(fontSize: 15, color: c.ink2)),
                    ],
                  ),
                  if (h['reason'] != null) ...[
                    const SizedBox(height: SanjeevaniSpace.sm),
                    Container(
                      padding: const EdgeInsets.only(left: SanjeevaniSpace.md),
                      decoration: BoxDecoration(
                        border: Border(left: BorderSide(color: c.line, width: 2)),
                      ),
                      child: Text('${h['reason']}',
                          style: TextStyle(fontSize: 15, color: c.ink2, height: 1.5)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
