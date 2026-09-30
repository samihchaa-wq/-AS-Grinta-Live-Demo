import 'dart:ui';

import 'package:as_grinta/core/theme/app_spacing.dart';
import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/widgets/grinta_app_bar.dart';
import 'package:as_grinta/demo/demo_backend.dart';
import 'package:as_grinta/demo/demo_fixture.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_pilot.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_providers.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_tab.dart';
import 'package:as_grinta/features/matches/presentation/widgets/upcoming_match_fixture_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final demoBackendProvider = Provider<DemoBackend>((ref) => DemoBackend());

/// Démo : voir l'écran comme un coach (pilote possible) ou comme un joueur
/// (spectateur uniquement).
final demoViewAsCoachProvider = StateProvider<bool>((ref) => true);

/// Incrémenté à chaque « Recommencer » : l'onglet Live est reconstruit à neuf,
/// sans garder l'état local de l'écran précédent.
final _demoRunProvider = StateProvider<int>((ref) => 0);

/// Reproduit l'écran « Fiche du match » d'un coach à partir de T-15
/// (lib/app/shell/app_shell.dart + MatchLineupPage) avec l'onglet Live
/// sélectionné. Seul le Live est fonctionnel ; les autres onglets et la barre
/// de navigation sont présents pour que l'écran soit identique à l'application.
class DemoMatchPage extends ConsumerWidget {
  const DemoMatchPage({super.key});

  static const matchId = demoMatchId;

  void _unavailable(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Démo : seul l’onglet Live est disponible.'),
        ),
      );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Recommencer la démo ?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Recommencer'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    ref.read(demoBackendProvider).reset();
    ref.invalidate(matchLiveStateProvider(matchId));
    ref
      ..invalidate(livePilotProvider(matchId))
      ..invalidate(liveViewModeProvider(matchId));
    ref.read(_demoRunProvider.notifier).state++;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = Scaffold(
      appBar: GrintaAppBar(title: const Text('Fiche du match')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(upcomingMatchFixtureProvider(matchId));
          await ref.read(upcomingMatchFixtureProvider(matchId).future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.sectionGap,
            AppSpacing.screenGutter,
            40,
          ),
          children: [
            // Onglet Live : pas d'encadré du match en haut, pour laisser la
            // place au direct (les autres onglets le gardent dans l'appli).
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'info', label: Text('Info')),
                ButtonSegment(value: 'effectif', label: Text('Effectif')),
                ButtonSegment(value: 'composition', label: Text('Compo')),
                ButtonSegment(value: 'live', label: Text('Live')),
              ],
              selected: const {'live'},
              onSelectionChanged: (_) => _unavailable(context),
            ),
            const SizedBox(height: AppSpacing.sectionGap),
            MatchLiveTab(
              key: ValueKey(ref.watch(_demoRunProvider)),
              matchId: matchId,
            ),
          ],
        ),
      ),
    );

    // Coquille de l'application (AppShell) en largeur téléphone : la page
    // occupe le contenu et la barre de navigation reste en bas.
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            _DemoBanner(
              onReset: () => _confirmReset(context, ref),
              simulation: const _DemoSimulationMenu(),
            ),
            Expanded(child: page),
          ],
        ),
      ),
      bottomNavigationBar: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: NavigationBar(
            selectedIndex: 0,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            onDestinationSelected: (_) => _unavailable(context),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.calendar_month_outlined),
                selectedIcon: Icon(Icons.calendar_month_rounded),
                label: 'Calendrier',
              ),
              NavigationDestination(
                icon: Icon(Icons.leaderboard_outlined),
                selectedIcon: Icon(Icons.leaderboard_rounded),
                label: 'Statistiques',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Seul ajout visible par rapport à l'application : un rappel qu'on est dans
/// la démo, et le bouton pour tout remettre à zéro.
class _DemoBanner extends StatelessWidget {
  const _DemoBanner({required this.onReset, required this.simulation});

  final VoidCallback onReset;
  final Widget simulation;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.accent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
        child: Row(
          children: [
            const Icon(Icons.school_rounded, size: 18, color: Colors.black87),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Démo · rien n’est enregistré',
                style: TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            simulation,
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Colors.black87,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: onReset,
              child: const Text('Recommencer'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Démo : simuler un autre coach ou la vue d'un joueur, impossibles à
/// reproduire autrement sur un seul téléphone.
class _DemoSimulationMenu extends ConsumerWidget {
  const _DemoSimulationMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const matchId = DemoMatchPage.matchId;
    final otherPilots =
        ref.watch(livePilotProvider(matchId)) == LivePilot.other;
    final asCoach = ref.watch(demoViewAsCoachProvider);
    return PopupMenuButton<String>(
      tooltip: 'Simulation',
      icon: const Icon(Icons.groups_rounded, color: Colors.black87),
      onSelected: (value) {
        switch (value) {
          case 'other':
            ref.read(livePilotProvider(matchId).notifier).state =
                otherPilots ? LivePilot.nobody : LivePilot.other;
          case 'player':
            ref.read(demoViewAsCoachProvider.notifier).state = !asCoach;
        }
      },
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          value: 'other',
          checked: otherPilots,
          child: const Text('Un autre coach pilote'),
        ),
        CheckedPopupMenuItem(
          value: 'player',
          checked: !asCoach,
          child: const Text('Voir comme un joueur'),
        ),
      ],
    );
  }
}
