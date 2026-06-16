import 'package:flutter/material.dart';

import '../theme/frsky_palette.dart';
import 'app_motion.dart';
import 'global_kill_button.dart';

/// Side rail matching FrSky charcoal / olive theme.
class AppSideRail extends StatelessWidget {
  const AppSideRail({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.showKill = false,
    this.onKill,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final bool showKill;
  final VoidCallback? onKill;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: FrSkyPalette.bodyDark,
      child: Container(
        width: 92,
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: Color(0xFF0E1012), width: 2)),
        ),
        child: SafeArea(
          right: false,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _NavTile(
                        icon: Icons.home_rounded,
                        label: 'Home',
                        selected: selectedIndex == 0,
                        onTap: () => onDestinationSelected(0),
                      ),
                      const SizedBox(height: 8),
                      _NavTile(
                        icon: Icons.emergency_share_rounded,
                        label: 'E-Stop',
                        selected: selectedIndex == 7,
                        onTap: () => onDestinationSelected(7),
                        danger: true,
                      ),
                      const SizedBox(height: 8),
                      _NavTile(
                        icon: Icons.settings_remote_rounded,
                        label: 'Control',
                        selected: selectedIndex == 1,
                        onTap: () => onDestinationSelected(1),
                      ),
                      const SizedBox(height: 8),
                      _NavTile(
                        icon: Icons.linear_scale_rounded,
                        label: 'Manual',
                        selected: selectedIndex == 2,
                        onTap: () => onDestinationSelected(2),
                      ),
                      const SizedBox(height: 8),
                      _NavTile(
                        icon: Icons.tune_rounded,
                        label: 'Cal',
                        selected: selectedIndex == 3,
                        onTap: () => onDestinationSelected(3),
                      ),
                      const SizedBox(height: 8),
                      _NavTile(
                        icon: Icons.settings_suggest_rounded,
                        label: 'Tune',
                        selected: selectedIndex == 4,
                        onTap: () => onDestinationSelected(4),
                      ),
                      const SizedBox(height: 8),
                      _NavTile(
                        icon: Icons.map_rounded,
                        label: 'Map',
                        selected: selectedIndex == 5,
                        onTap: () => onDestinationSelected(5),
                      ),
                      const SizedBox(height: 8),
                      _NavTile(
                        icon: Icons.view_in_ar_rounded,
                        label: '3D',
                        selected: selectedIndex == 8,
                        onTap: () => onDestinationSelected(8),
                      ),
                      const SizedBox(height: 8),
                      _NavTile(
                        icon: Icons.terminal_rounded,
                        label: 'Serial',
                        selected: selectedIndex == 6,
                        onTap: () => onDestinationSelected(6),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'X10',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                          color: FrSkyPalette.bronze,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Always-visible instant kill (any tab) — separate from E-Stop page tab.
              if (showKill && onKill != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                  child: GlobalKillButton(
                    compact: true,
                    onKill: onKill!,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final iconColor = danger
        ? (selected ? const Color(0xFFFECACA) : const Color(0xFFEF4444))
        : (selected ? FrSkyPalette.bronzeHi : FrSkyPalette.labelDim);
    final labelColor = danger
        ? (selected ? const Color(0xFFFECACA) : const Color(0xFFEF4444))
        : (selected ? FrSkyPalette.label : FrSkyPalette.labelDim);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: PressScale(
        onTap: onTap,
        scale: 0.94,
        child: AnimatedContainer(
          duration: AppMotion.fastMs,
          curve: Curves.easeOutCubic,
          width: double.infinity,
          decoration: BoxDecoration(
            color: danger
                ? (selected ? const Color(0xFF7F1D1D) : const Color(0xFF3F1010))
                : (selected ? FrSkyPalette.faceplateShadow : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
            border: danger
                ? Border.all(
                    color: selected
                        ? const Color(0xFFFCA5A5)
                        : const Color(0xFFB91C1C).withValues(alpha: 0.6),
                  )
                : (selected
                    ? Border.all(color: FrSkyPalette.bronzeHi.withValues(alpha: 0.8))
                    : Border.all(color: Colors.transparent)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              AnimatedScale(
                scale: selected ? 1.08 : 1.0,
                duration: AppMotion.fastMs,
                curve: Curves.easeOutBack,
                child: Icon(icon, size: 22, color: iconColor),
              ),
              const SizedBox(height: 4),
              AnimatedDefaultTextStyle(
                duration: AppMotion.fastMs,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                  color: labelColor,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
