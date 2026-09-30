import 'package:as_grinta/core/utils/app_errors.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/match_live/domain/match_live_session.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_pre_kickoff_page.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_providers.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_running_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Point d'entrée de l'onglet "Tableau blanc" dans la fiche du match :
/// aiguille vers l'écran de préparation, le direct ou le récapitulatif selon
/// l'état de la session live, et vers une vue lecture seule pour les
/// spectateurs qui ne sont ni admin ni coach de la saison.
class MatchLiveTab extends ConsumerWidget {
  const MatchLiveTab({super.key, required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<String?>(matchLiveActionMessageProvider(matchId), (
      previous,
      next,
    ) {
      if (next == null || next == previous) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(next)));
      ref.read(matchLiveActionMessageProvider(matchId).notifier).state = null;
    });

    final canEditAsync = ref.watch(isMatchCoachOrAdminProvider(matchId));
    final stateAsync = ref.watch(matchLiveStateProvider(matchId));

    return stateAsync.when(
      loading: () => const Center(
        child: GrintaLoader.page(
          message: 'Le Tableau Blanc se prépare…',
          semanticLabel: 'Chargement du Tableau Blanc',
        ),
      ),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(humanizeError(error), textAlign: TextAlign.center),
        ),
      ),
      data: (bundle) {
        final canEdit = canEditAsync.valueOrNull ?? false;

        try {
          if (!bundle.session.sessionExists) {
            if (!canEdit) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Le match n’a pas encore démarré.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return MatchLivePreKickoffPage(
              matchId: matchId,
              bundle: bundle,
              canEdit: true,
            );
          }

          if (bundle.session.state == MatchLiveState.notStarted) {
            final page = MatchLivePreKickoffPage(
              matchId: matchId,
              bundle: bundle,
              canEdit: canEdit,
            );
            return canEdit
                ? _LiveRealtimeBoundary(matchId: matchId, child: page)
                : page;
          }

          // Match en cours, côté coach : il se pilote en mode match plein
          // écran, ouvert automatiquement ; la fiche garde un raccourci.
          if (canEdit && bundle.session.state != MatchLiveState.finished) {
            return _LiveRealtimeBoundary(
              matchId: matchId,
              child: _MatchModeLauncher(matchId: matchId),
            );
          }

          final page = MatchLiveRunningPage(
            matchId: matchId,
            bundle: bundle,
            canEdit: canEdit,
          );
          if (!canEdit) return page;
          return _LiveRealtimeBoundary(matchId: matchId, child: page);
        } catch (error, stackTrace) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'match_live',
              context: ErrorDescription('construction du Tableau Blanc'),
            ),
          );
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Impossible d’afficher le Live pour le moment. Réessaie.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
      },
    );
  }
}

/// Raccourci vers le mode match dans la fiche. Il s'ouvre tout seul la
/// première fois (au coup d'envoi, ou en arrivant sur un match en cours).
class _MatchModeLauncher extends StatefulWidget {
  const _MatchModeLauncher({required this.matchId});

  final String matchId;

  @override
  State<_MatchModeLauncher> createState() => _MatchModeLauncherState();
}

class _MatchModeLauncherState extends State<_MatchModeLauncher> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _open();
    });
  }

  void _open() {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => MatchLiveMatchMode(matchId: widget.matchId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'Match en cours',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _open,
              icon: const Icon(Icons.fullscreen_rounded),
              label: const Text('Ouvrir le mode match'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mode match : le direct en plein écran. Il se referme de lui-même quand le
/// match n'est plus en cours (fin du match, retour avant le coup d'envoi).
class MatchLiveMatchMode extends ConsumerStatefulWidget {
  const MatchLiveMatchMode({super.key, required this.matchId});

  final String matchId;

  @override
  ConsumerState<MatchLiveMatchMode> createState() => _MatchLiveMatchModeState();
}

class _MatchLiveMatchModeState extends ConsumerState<MatchLiveMatchMode> {
  bool _closing = false;

  static const _live = {
    MatchLiveState.running,
    MatchLiveState.paused,
    MatchLiveState.halftime,
  };

  @override
  Widget build(BuildContext context) {
    final bundle =
        ref.watch(matchLiveStateProvider(widget.matchId)).valueOrNull;
    final canEdit =
        ref.watch(isMatchCoachOrAdminProvider(widget.matchId)).valueOrNull ??
            false;
    final live = bundle != null &&
        bundle.session.sessionExists &&
        _live.contains(bundle.session.state);

    if (!live && bundle != null && !_closing) {
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }

    return Scaffold(
      body: SafeArea(
        child: bundle == null || !live
            ? const SizedBox.shrink()
            : MatchLiveRunningPage(
                matchId: widget.matchId,
                bundle: bundle,
                canEdit: canEdit,
                fullScreen: true,
              ),
      ),
    );
  }
}

class _LiveRealtimeBoundary extends ConsumerWidget {
  const _LiveRealtimeBoundary({required this.matchId, required this.child});

  final String matchId;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final realtimeDegraded = ref.watch(
      matchLiveRealtimeDegradedProvider(matchId),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (realtimeDegraded)
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 6, 12, 2),
            child: _RealtimeFallbackNotice(),
          ),
        child,
      ],
    );
  }
}

class _RealtimeFallbackNotice extends StatelessWidget {
  const _RealtimeFallbackNotice();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      label:
          'Connexion temps réel interrompue. Synchronisation de secours active.',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.errorContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.sync_problem_rounded, color: colors.onErrorContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Temps réel interrompu. Synchronisation de secours active.',
                  style: TextStyle(color: colors.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
