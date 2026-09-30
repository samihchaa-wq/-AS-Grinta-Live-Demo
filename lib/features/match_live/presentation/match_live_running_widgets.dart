part of 'match_live_running_page.dart';

/// Bandeau du direct sur une seule ligne : chrono, commandes du match (en
/// icônes) et tableau d'affichage.
class _LiveHeaderBar extends ConsumerWidget {
  const _LiveHeaderBar({
    required this.bundle,
    required this.canEdit,
    required this.onPause,
    required this.onResume,
    required this.onResumeSecondHalf,
    required this.onHalftime,
    required this.onRestart,
    required this.onEndMatch,
  });

  final MatchLiveStateBundle bundle;
  final bool canEdit;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onResumeSecondHalf;
  final VoidCallback onHalftime;
  final VoidCallback onRestart;
  final VoidCallback onEndMatch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = bundle.session;
    final matchId = session.matchId;
    final controller = ref.read(matchLiveStateProvider(matchId).notifier);
    final fixture =
        ref.watch(upcomingMatchFixtureProvider(matchId)).valueOrNull;
    final opponentName = fixture?.opponentName ?? 'Adversaire';
    final grintaIsHome = fixture?.grintaIsHome ?? true;

    _LiveScore team(bool grinta) => _LiveScore(
          shortName: grinta ? 'ASG' : _shortName(opponentName),
          fullName: grinta ? 'AS Grinta' : opponentName,
          score: grinta ? session.scoreAsGrinta : session.scoreAdverse,
          canEdit: canEdit,
          onIncrement: () =>
              controller.adjustScore(team: grinta ? 'us' : 'them', delta: 1),
          onDecrement: () =>
              controller.adjustScore(team: grinta ? 'us' : 'them', delta: -1),
        );

    final firstAction = switch (session.state) {
      MatchLiveState.running => (
          tooltip: 'Pause',
          icon: Icons.pause_rounded,
          callback: onPause as VoidCallback?,
          filled: false,
        ),
      MatchLiveState.paused => (
          tooltip: 'Reprendre',
          icon: Icons.play_arrow_rounded,
          callback: onResume as VoidCallback?,
          filled: false,
        ),
      MatchLiveState.halftime => (
          tooltip: 'Reprendre la 2e mi-temps',
          icon: Icons.play_arrow_rounded,
          callback: onResumeSecondHalf as VoidCallback?,
          filled: true,
        ),
      _ => (
          tooltip: 'Pause',
          icon: Icons.pause_rounded,
          callback: null,
          filled: false,
        ),
    };
    final canGoHalftime =
        session.half == 1 && session.state != MatchLiveState.halftime;

    Widget action({
      required String tooltip,
      required IconData icon,
      required VoidCallback? onPressed,
      bool filled = false,
      bool danger = false,
    }) {
      final scheme = Theme.of(context).colorScheme;
      const size = BoxConstraints.tightFor(width: 36, height: 36);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1.5),
        child: filled
            ? IconButton.filled(
                tooltip: tooltip,
                onPressed: onPressed,
                constraints: size,
                padding: EdgeInsets.zero,
                iconSize: 20,
                icon: Icon(icon),
              )
            : IconButton.outlined(
                tooltip: tooltip,
                onPressed: onPressed,
                constraints: size,
                padding: EdgeInsets.zero,
                iconSize: 20,
                color: danger ? scheme.error : null,
                icon: Icon(icon),
              ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        // Sur un écran étroit, la ligne se réduit d'un bloc plutôt que de
        // passer sur deux lignes.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 72,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: MatchLiveClock(session: session, compact: true),
                ),
              ),
              const SizedBox(width: 4),
              if (canEdit) ...[
                action(
                  tooltip: firstAction.tooltip,
                  icon: firstAction.icon,
                  onPressed: firstAction.callback,
                  filled: firstAction.filled,
                ),
                action(
                  tooltip: 'Mi-temps',
                  icon: Icons.sports_rounded,
                  onPressed: canGoHalftime ? onHalftime : null,
                ),
                action(
                  tooltip: 'Recommencer',
                  icon: Icons.restart_alt_rounded,
                  onPressed: onRestart,
                ),
                action(
                  tooltip: 'Fin du match',
                  icon: Icons.flag_rounded,
                  onPressed: onEndMatch,
                  danger: true,
                ),
                const SizedBox(width: 8),
              ],
              team(grintaIsHome),
              // Le tiret s'aligne sur les scores, sous la ligne des sigles.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(' ', style: Theme.of(context).textTheme.labelSmall),
                    Text(
                      '–',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ],
                ),
              ),
              team(!grintaIsHome),
            ],
          ),
        ),
      ),
    );
  }
}

/// Trois premières lettres du nom, en capitales (« TOU » pour Toulouse).
String _shortName(String name) {
  final letters = name.replaceAll(RegExp(r'[^A-Za-zÀ-ÿ]'), '');
  if (letters.isEmpty) return 'ADV';
  return letters
      .substring(0, letters.length < 3 ? letters.length : 3)
      .toUpperCase();
}

/// Score d'une équipe dans le bandeau : sigle, score et « + ». Un appui sur
/// le score propose de retirer un but.
class _LiveScore extends StatelessWidget {
  const _LiveScore({
    required this.shortName,
    required this.fullName,
    required this.score,
    required this.canEdit,
    required this.onIncrement,
    required this.onDecrement,
  });

  final String shortName;
  final String fullName;
  final int score;
  final bool canEdit;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final number = Text(
      '$score',
      style: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w500,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          shortName,
          style: theme.textTheme.labelSmall?.copyWith(letterSpacing: .5),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canEdit && score > 0)
              PopupMenuButton<void>(
                tooltip: 'Score de $fullName',
                padding: EdgeInsets.zero,
                itemBuilder: (_) => [
                  PopupMenuItem<void>(
                    onTap: onDecrement,
                    child: Text('Retirer un but à $fullName'),
                  ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: number,
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: number,
              ),
            if (canEdit)
              IconButton(
                tooltip: 'Ajouter un but à $fullName',
                onPressed: onIncrement,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints.tightFor(width: 30, height: 30),
                iconSize: 22,
                icon: const Icon(Icons.add_circle_outline_rounded),
              ),
          ],
        ),
      ],
    );
  }
}

const double _benchGap = AppSpacing.contentGap;
const double _benchColumnMargin = AppSpacing.compactCardPadding;

FormationMarkerMetrics benchAndPitchMetrics(double availableWidth) {
  final pitchWidth =
      (availableWidth - _benchGap - _benchColumnMargin) * 5.6 / 6.6;
  return FormationMarkerMetrics.forPitch(pitchWidth);
}

double benchColumnWidth(FormationMarkerMetrics metrics) =>
    metrics.width + _benchColumnMargin;

class _BenchColumn extends StatelessWidget {
  const _BenchColumn({
    required this.bench,
    required this.bundle,
    required this.canEdit,
    required this.metrics,
    required this.pendingOutIds,
    required this.onFieldPlayerDropped,
  });

  final List<MatchCompositionEntry> bench;
  final MatchLiveStateBundle bundle;
  final bool canEdit;
  final FormationMarkerMetrics metrics;
  final Set<String> pendingOutIds;
  final void Function(MatchCompositionEntry, MatchCompositionEntry)
      onFieldPlayerDropped;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lastExits = lastExitMarksByParticipant(bundle.events);
    return SizedBox(
      width: metrics.width + _benchColumnMargin,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: _benchColumnMargin / 2,
            vertical: 10,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Banc (${bench.length})',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: AppSpacing.contentGap),
              if (bench.isEmpty)
                Text(
                  'Personne',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                )
              else
                for (final entry in bench)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: DragTarget<MatchCompositionEntry>(
                      onWillAcceptWithDetails: (details) =>
                          canEdit &&
                          details.data.zone == MatchCompositionZone.field,
                      onAcceptWithDetails: (details) =>
                          onFieldPlayerDropped(details.data, entry),
                      builder: (context, candidates, rejected) {
                        final isPendingOut = pendingOutIds.contains(
                          entry.participantId,
                        );
                        return DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: candidates.isNotEmpty
                                  ? theme.colorScheme.primary
                                  : isPendingOut
                                      ? theme.colorScheme.error
                                      : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: LiveBenchTile(
                            entry: entry,
                            draggable: canEdit,
                            metrics: metrics,
                            timesBenched: bundle.timesBenched(
                              entry.participantId,
                            ),
                            lastExit: lastExits[entry.participantId],
                          ),
                        );
                      },
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PendingSubstitutions extends StatelessWidget {
  const _PendingSubstitutions({
    required this.pending,
    required this.nameOf,
    required this.busy,
    required this.onRemove,
    required this.onClear,
    required this.onValidate,
  });

  final List<PendingSubstitution> pending;
  final String Function(String participantId) nameOf;
  final bool busy;
  final ValueChanged<PendingSubstitution> onRemove;
  final VoidCallback onClear;
  final VoidCallback onValidate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.compactCardPadding,
          10,
          AppSpacing.compactCardPadding,
          10,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.swap_horiz_rounded,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: AppSpacing.contentGap),
                Expanded(
                  child: Text(
                    pending.length == 1
                        ? 'Changement en attente'
                        : '${pending.length} changements en attente',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w400,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final pair in pending)
              Row(
                children: [
                  Expanded(
                    child: LiveSubstitutionLine(
                      playerInName: nameOf(pair.playerIn),
                      playerOutName: nameOf(pair.playerOut),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Annuler ce changement',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.undo_rounded),
                    onPressed: busy ? null : () => onRemove(pair),
                  ),
                ],
              ),
            const SizedBox(height: AppSpacing.microGap),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : onClear,
                    child: const Text('Annuler'),
                  ),
                ),
                const SizedBox(width: AppSpacing.contentGap),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: busy ? null : onValidate,
                    icon: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: GrintaProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(
                      pending.length == 1
                          ? 'Valider'
                          : 'Valider (${pending.length})',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _JournalAction { scorer, assist, delete }

class _LiveJournal extends StatelessWidget {
  const _LiveJournal({
    super.key,
    required this.events,
    required this.expanded,
    required this.canEdit,
    required this.onExpandedChanged,
    required this.onEditScorer,
    required this.onEditAssist,
    required this.onDelete,
  });

  final List<MatchLiveEvent> events;
  final bool expanded;
  final bool canEdit;
  final ValueChanged<bool> onExpandedChanged;
  final ValueChanged<MatchLiveEvent> onEditScorer;
  final ValueChanged<MatchLiveEvent> onEditAssist;
  final ValueChanged<MatchLiveEvent> onDelete;

  @override
  Widget build(BuildContext context) {
    final ordered = events.reversed.toList();
    final latest = ordered.isEmpty ? null : ordered.first;
    final salvos = substitutionSalvosByEvent(events);
    final marks = substitutionExitMarksByEvent(events);

    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            onTap: () => onExpandedChanged(!expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.cardPadding,
                vertical: AppSpacing.compactCardPadding,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.receipt_long_rounded),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Journal du match',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w400,
                          ),
                    ),
                  ),
                  if (events.isNotEmpty)
                    Text(
                      '${events.length}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  const SizedBox(width: AppSpacing.microGap),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                  ),
                ],
              ),
            ),
          ),
          if (latest == null)
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.cardPadding,
                0,
                AppSpacing.cardPadding,
                AppSpacing.cardPadding,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Aucun événement pour le moment.'),
              ),
            )
          else if (!expanded) ...[
            const Divider(height: 1),
            _framed(
              salvos[latest],
              _JournalEventRow(
                event: latest,
                mark: marks[latest],
                canEdit: false,
                canEditScorer: canEdit,
                onEditScorer: onEditScorer,
                onEditAssist: onEditAssist,
                onDelete: onDelete,
              ),
            ),
          ] else ...[
            const Divider(height: 1),
            ..._expandedRows(ordered, salvos, marks),
          ],
        ],
      ),
    );
  }

  Widget _framed(SubstitutionSalvo? salvo, Widget child) => salvo == null
      ? child
      : SubstitutionSalvoFrame(
          salvo: salvo,
          margin: const EdgeInsets.fromLTRB(4, 4, 4, 4),
          child: child,
        );

  /// Liste dépliée : les remplacements consécutifs d'une même salve partagent
  /// un encadré coloré, les autres lignes restent séparées par un trait.
  List<Widget> _expandedRows(
    List<MatchLiveEvent> ordered,
    Map<MatchLiveEvent, SubstitutionSalvo> salvos,
    Map<MatchLiveEvent, SubstitutionExitMark> marks,
  ) {
    Widget row(MatchLiveEvent event) => _JournalEventRow(
          event: event,
          mark: marks[event],
          canEdit: canEdit,
          canEditScorer: canEdit,
          onEditScorer: onEditScorer,
          onEditAssist: onEditAssist,
          onDelete: onDelete,
        );

    final widgets = <Widget>[];
    var index = 0;
    while (index < ordered.length) {
      if (widgets.isNotEmpty) {
        widgets.add(const Divider(height: 1, indent: 48));
      }
      final salvo = salvos[ordered[index]];
      if (salvo == null) {
        widgets.add(row(ordered[index]));
        index += 1;
        continue;
      }
      final group = <Widget>[];
      while (
          index < ordered.length && identical(salvos[ordered[index]], salvo)) {
        group.add(row(ordered[index]));
        index += 1;
      }
      widgets.add(_framed(salvo, Column(children: group)));
    }
    return widgets;
  }
}

class _JournalEventRow extends StatelessWidget {
  const _JournalEventRow({
    required this.event,
    this.mark,
    required this.canEdit,
    required this.canEditScorer,
    required this.onEditScorer,
    required this.onEditAssist,
    required this.onDelete,
  });

  final MatchLiveEvent event;

  /// Repère du joueur qui sort : il remplace l'icône. `null` sur un but.
  final SubstitutionExitMark? mark;
  final bool canEdit;
  final bool canEditScorer;
  final ValueChanged<MatchLiveEvent> onEditScorer;
  final ValueChanged<MatchLiveEvent> onEditAssist;
  final ValueChanged<MatchLiveEvent> onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color, label) = switch (event.type) {
      MatchLiveEventType.goalUs => (
          Icons.sports_soccer_rounded,
          theme.colorScheme.primary,
          event.isOpponentOwnGoal
              ? 'But AS Grinta · CSC adverse'
              : 'But AS Grinta · ${event.scorerName ?? 'Buteur à désigner'}'
                  '${event.assistName == null ? '' : ' · passe ${event.assistName}'}',
        ),
      MatchLiveEventType.goalThem => (
          Icons.sports_soccer_outlined,
          theme.colorScheme.error,
          'But adverse',
        ),
      MatchLiveEventType.substitution => (
          Icons.swap_horiz_rounded,
          theme.colorScheme.secondary,
          '${event.playerInName ?? '?'} entre · '
              '${event.playerOutName ?? '?'} sort',
        ),
    };
    final hasScore =
        event.scoreAsGrintaAfter != null && event.scoreAdverseAfter != null;
    final canChooseScorer = canEditScorer &&
        event.type == MatchLiveEventType.goalUs &&
        event.needsScorer;
    final isSubstitution = event.type == MatchLiveEventType.substitution;
    final isOpponentGoal = event.type == MatchLiveEventType.goalThem;
    final goalIndent =
        (MediaQuery.sizeOf(context).width * .12).clamp(36.0, 64.0).toDouble();

    Widget actions() => PopupMenuButton<_JournalAction>(
          tooltip: 'Corriger',
          onSelected: (action) {
            switch (action) {
              case _JournalAction.scorer:
                onEditScorer(event);
              case _JournalAction.assist:
                onEditAssist(event);
              case _JournalAction.delete:
                onDelete(event);
            }
          },
          itemBuilder: (context) => [
            if (event.type == MatchLiveEventType.goalUs)
              PopupMenuItem(
                value: _JournalAction.scorer,
                child: Row(
                  children: [
                    const Icon(Icons.person_search_rounded),
                    const SizedBox(width: AppSpacing.contentGap),
                    Text(
                      event.needsScorer
                          ? 'Choisir le buteur'
                          : 'Corriger le buteur',
                    ),
                  ],
                ),
              ),
            if (event.type == MatchLiveEventType.goalUs &&
                event.scorerParticipantId != null)
              PopupMenuItem(
                value: _JournalAction.assist,
                child: Row(
                  children: [
                    const Icon(Icons.emoji_events_outlined),
                    const SizedBox(width: AppSpacing.contentGap),
                    Text(
                      event.assistName == null
                          ? 'Ajouter la passe décisive'
                          : 'Corriger la passe décisive',
                    ),
                  ],
                ),
              ),
            const PopupMenuItem(
              value: _JournalAction.delete,
              child: Row(
                children: [
                  Icon(Icons.delete_outline_rounded),
                  SizedBox(width: AppSpacing.contentGap),
                  Text('Retirer'),
                ],
              ),
            ),
          ],
        );

    if (isSubstitution) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 32,
              child: mark == null ? null : SubstitutionExitBadge(mark: mark!),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: LiveSubstitutionLine(
                playerInName: event.playerInName ?? '?',
                playerOutName: event.playerOutName ?? '?',
              ),
            ),
            const SizedBox(width: 4),
            Text(
              "${event.minute}'",
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w400,
              ),
            ),
            if (canEdit) ...[
              const SizedBox(width: 2),
              actions(),
            ],
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Align(
                  alignment: isOpponentGoal
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: isOpponentGoal ? 0 : goalIndent,
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: canChooseScorer ? () => onEditScorer(event) : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(icon, size: 20, color: color),
                            const SizedBox(width: 8),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: constraints.maxWidth * .52,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: isOpponentGoal
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    label,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: isOpponentGoal
                                        ? TextAlign.right
                                        : TextAlign.left,
                                    style: canChooseScorer
                                        ? theme.textTheme.bodyMedium?.copyWith(
                                            color: theme.colorScheme.primary,
                                            fontWeight: FontWeight.w400,
                                            decoration:
                                                TextDecoration.underline,
                                          )
                                        : theme.textTheme.bodyMedium,
                                  ),
                                  if (hasScore)
                                    Text(
                                      '${event.scoreAsGrintaAfter}-'
                                      '${event.scoreAdverseAfter}',
                                      textAlign: isOpponentGoal
                                          ? TextAlign.right
                                          : TextAlign.left,
                                      style:
                                          theme.textTheme.labelMedium?.copyWith(
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                "${event.minute}'",
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w400,
                ),
              ),
              if (canEdit) ...[
                const SizedBox(width: 2),
                actions(),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
