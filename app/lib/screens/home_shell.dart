import 'package:flutter/material.dart';

import '../api.dart';
import '../app_state.dart';
import 'care_team_screen.dart';
import 'chat_screen.dart';
import 'profile_screen.dart';

/// Two chat surfaces plus the profile. appfeature.md is explicit that the patient
/// must always be able to tell who they are talking to, so the assistant and the
/// hospital are separate tabs with separate iconography, never one merged inbox.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  String? _aiConversationId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _openAssistant();
  }

  Future<void> _openAssistant() async {
    try {
      final conv = await Api.instance.openAiThread();
      if (mounted) setState(() => _aiConversationId = conv['id'] as String);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final assistant = _error != null
        ? _Retry(message: _error!, onRetry: () {
            setState(() => _error = null);
            _openAssistant();
          })
        : _aiConversationId == null
            ? const Center(child: CircularProgressIndicator())
            : ChatScreen(
                conversationId: _aiConversationId!,
                kind: 'ai',
                title: 'Health assistant',
              );

    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          assistant,
          const CareTeamScreen(),
          const ProfileScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.smart_toy_outlined),
            selectedIcon: Icon(Icons.smart_toy),
            label: 'Assistant',
          ),
          NavigationDestination(
            icon: Icon(Icons.medical_services_outlined),
            selectedIcon: Icon(Icons.medical_services),
            label: 'Hospital',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
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
            const SizedBox(height: 8),
            Text('API: ${Api.baseUrl}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
            TextButton(
              onPressed: AppState.instance.signOut,
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }
}
