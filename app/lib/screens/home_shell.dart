import 'package:flutter/material.dart';

import 'assistant_screen.dart';
import 'care_team_screen.dart';
import 'profile_screen.dart';

/// Two chat surfaces plus the profile. appfeature.md is explicit that the patient
/// must always be able to tell who they are talking to, so the assistant and the
/// hospital are separate tabs with separate iconography, never one merged inbox.
///
/// The assistant tab is a list of consultations rather than a single thread: one
/// per problem, opened from AssistantScreen.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [
          AssistantScreen(),
          CareTeamScreen(),
          ProfileScreen(),
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
