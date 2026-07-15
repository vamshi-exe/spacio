import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';
import 'projects_screen.dart';
import 'settings_screen.dart';
import 'clients_screen.dart';
import 'capture_screen.dart';

/// Holds the persistent bottom navigation and swaps the active tab.
/// The center "Scan" item launches the capture → tiles → result flow, then
/// refreshes the dashboard so a newly-saved visualization shows up.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _scanIndex = 2;

  final _homeKey = GlobalKey<HomeScreenState>();
  final _projectsKey = GlobalKey<ProjectsScreenState>();
  final _clientsKey = GlobalKey<ClientsScreenState>();

  late final List<Widget> _pages = [
    HomeScreen(key: _homeKey, onScan: () => _onTap(_scanIndex)),
    ProjectsScreen(key: _projectsKey),
    const SizedBox.shrink(), // Scan — handled as an action, never shown.
    ClientsScreen(key: _clientsKey),
    const SettingsScreen(),
  ];

  Future<void> _onTap(int i) async {
    if (i == _scanIndex) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const CaptureScreen()),
      );
      // A visualization may have been saved — refresh data and show Home.
      _homeKey.currentState?.refresh();
      _projectsKey.currentState?.refresh();
      _clientsKey.currentState?.refresh();
      if (mounted) setState(() => _index = 0);
      return;
    }
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: _BottomBar(current: _index, onTap: _onTap),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int current;
  final ValueChanged<int> onTap;

  const _BottomBar({required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              _NavItem(
                icon: Icons.home_outlined,
                activeIcon: Icons.home_rounded,
                label: 'Home',
                selected: current == 0,
                onTap: () => onTap(0),
              ),
              _NavItem(
                icon: Icons.folder_outlined,
                activeIcon: Icons.folder_rounded,
                label: 'Projects',
                selected: current == 1,
                onTap: () => onTap(1),
              ),
              _ScanButton(onTap: () => onTap(2)),
              _NavItem(
                icon: Icons.people_outline_rounded,
                activeIcon: Icons.people_rounded,
                label: 'Clients',
                selected: current == 3,
                onTap: () => onTap(3),
              ),
              _NavItem(
                icon: Icons.settings_outlined,
                activeIcon: Icons.settings_rounded,
                label: 'Settings',
                selected: current == 4,
                onTap: () => onTap(4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.textPrimary : AppColors.textMuted;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? activeIcon : icon, size: 22, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The center scan action.
class _ScanButton extends StatelessWidget {
  final VoidCallback onTap;

  const _ScanButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.cream,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: AppColors.cream.withValues(alpha: 0.18),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Icon(
              Icons.center_focus_strong_rounded,
              color: AppColors.onCream,
              size: 26,
            ),
          ),
        ),
      ),
    );
  }
}
