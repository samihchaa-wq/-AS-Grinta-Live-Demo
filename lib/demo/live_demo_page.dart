import 'package:as_grinta/core/theme/app_spacing.dart';
import 'package:as_grinta/core/utils/app_formats.dart';
import 'package:as_grinta/core/widgets/grinta_loader.dart';
import 'package:as_grinta/features/match_live/domain/match_live_event.dart';
import 'package:as_grinta/features/match_live/domain/match_live_formation.dart';
import 'package:as_grinta/features/match_live/domain/match_live_session.dart';
import 'package:as_grinta/features/match_live/domain/match_live_state_bundle.dart';
import 'package:as_grinta/features/match_live/presentation/widgets/live_bench_tile.dart';
import 'package:as_grinta/features/match_live/presentation/widgets/live_substitution_line.dart';
import 'package:as_grinta/features/match_live/presentation/widgets/match_live_clock.dart';
import 'package:as_grinta/features/match_live/presentation/widgets/match_live_scorer_picker_dialog.dart';
import 'package:as_grinta/features/sports_management/domain/football_formation.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/domain/match_squad_editing.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/formation_pitch_editor.dart';
import 'package:as_grinta/features/sports_management/presentation/widgets/match_squad_editor.dart';
import 'package:flutter/material.dart';

part 'live_demo_widgets.dart';

typedef PendingSubstitution = ({String playerIn, String playerOut});

class LiveDemoPage extends StatefulWidget {
  const LiveDemoPage({super.key});

  @override
  State<LiveDemoPage> createState() => _LiveDemoPageState();
}

class _LiveDemoPageState extends State<LiveDemoPage> {
  static const _matchId = 'demo-match';
  static const _opponentName = 'Toulouse Métropole';
  static const _grintaIsHome = false;

  late MatchComposition _lineup = _initialLineup();
  MatchComposition? _kickoffLineup;
  late MatchLiveSession _session = _notStartedSession();
  final List<MatchLiveEvent> _events = [];
  final List<PendingSubstitution> _pending = [];
  final Map<String, int> _substituteCounts = {};
  final TextEditingController _durationController =
      TextEditingController(text: '90');

  bool _journalExpanded = false;
  bool _reportFacts = false;
  int _nextEventId = 1;

  MatchLiveStateBundle get _bundle => MatchLiveStateBundle(
        session: _session,
        lineup: _lineup,
        events: List.unmodifiable(_events),
        substituteCounts: Map.unmodifiable(_substituteCounts),
      );

  @override
  void dispose() {
    _durationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF041224),
      appBar: AppBar(
        title: const Text('Tableau Blanc'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: _session.state == MatchLiveState.notStarted
              ? _buildPreKickoff()
              : _session.state == MatchLiveState.finished
                  ? _buildReport()
                  : _buildRunning(),
        ),
      ),
    );
  }

  Widget _buildPreKickoff() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        MatchSquadEditor(
          lineup: _lineup,
          editable: true,
          header: _buildPreControls(),
          onDroppedOnSlot: (moving, slot) {
            setState(() => _lineup = placeEntryOnSlot(_lineup, moving, slot));
          },
          onMoveToBench: (entry) {
            setState(() => _lineup = moveEntryToBench(_lineup, entry));
          },
          onFormationChanged: null,
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _confirmAndStart,
          icon: const Icon(Icons.play_circle_fill_rounded),
          label: const Text('Démarrer le match'),
        ),
      ],
    );
  }

  Widget _buildPreControls() {
    final formation = formationForCode(_lineup.formationCode);
    return Row(
      key: const ValueKey('live-pre-kickoff-controls'),
      children: [
        Expanded(
          child: TextField(
            controller: _durationController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Temps de jeu',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 16,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<String>(
            key: ValueKey('squad-formation-${_lineup.formationCode}'),
            initialValue: formation.code,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Dispositif',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 16,
              ),
            ),
            items: [
              for (final item in footballFormations)
                DropdownMenuItem(value: item.code, child: Text(item.code)),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _lineup = repositionForFormation(_lineup, value));
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: 56,
            child: OutlinedButton(
              onPressed: _showAddPlayerSheet,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('Ajouter un joueur'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRunning() {
    final previewLineup = _previewLineup(_lineup);
    final field = previewLineup.entriesFor(MatchCompositionZone.field);
    final bench = previewLineup.entriesFor(MatchCompositionZone.bench);
    final pendingOutIds = {for (final pair in _pending) pair.playerOut};
    final setupDisabled = _pending.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.liveScreenGutter,
        AppSpacing.sectionGap,
        AppSpacing.liveScreenGutter,
        32,
      ),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _LiveTopBar(
          session: _session,
          canEdit: true,
          onPause: _pause,
          onResume: _resume,
          onResumeSecondHalf: _resumeSecondHalf,
          onHalftime: _confirmHalftime,
          onRestart: _confirmRestart,
          onEndMatch: _confirmEndMatch,
        ),
        const SizedBox(height: 10),
        _ScoreCard(
          bundle: _bundle,
          canEdit: true,
          opponentName: _opponentName,
          grintaIsHome: _grintaIsHome,
          onUsIncrement: () => _adjustScore('us', 1),
          onUsDecrement: () => _adjustScore('us', -1),
          onThemIncrement: () => _adjustScore('them', 1),
          onThemDecrement: () => _adjustScore('them', -1),
        ),
        if (_pending.isNotEmpty) ...[
          const SizedBox(height: 10),
          _PendingSubstitutions(
            pending: _pending,
            nameOf: _nameOf,
            busy: false,
            onRemove: (pair) => setState(() => _pending.remove(pair)),
            onClear: () => setState(_pending.clear),
            onValidate: _validatePending,
          ),
        ],
        const SizedBox(height: 10),
        Row(
          key: const ValueKey('live-running-controls'),
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey('live-formation-${_lineup.formationCode}'),
                initialValue: formationForCode(_lineup.formationCode).code,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Dispositif',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 16,
                  ),
                ),
                items: [
                  for (final formation in footballFormations)
                    DropdownMenuItem(
                      value: formation.code,
                      child: Text(formation.code),
                    ),
                ],
                onChanged: setupDisabled
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() {
                          _lineup =
                              repositionLiveLineupForFormation(_lineup, value);
                        });
                        _showMessage('Dispositif $value appliqué.');
                      },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 56,
                child: OutlinedButton(
                  onPressed: setupDisabled ? null : _showAddPlayerSheet,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Ajouter un joueur'),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_pending.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Valide ou annule les remplacements en attente avant de '
              'changer de dispositif ou d’ajouter un joueur.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: AppSpacing.sectionGap),
        LayoutBuilder(
          builder: (context, constraints) {
            final metrics = benchAndPitchMetrics(constraints.maxWidth);
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BenchColumn(
                    bench: bench,
                    bundle: _bundle,
                    canEdit: true,
                    metrics: metrics,
                    pendingOutIds: pendingOutIds,
                    onFieldPlayerDropped: (playerOut, playerIn) =>
                        _stage(playerIn: playerIn, playerOut: playerOut),
                  ),
                  const SizedBox(width: _benchGap),
                  Expanded(
                    child: FormationPitchEditor(
                      slots:
                          formationForCode(_lineup.formationCode).slots,
                      entries: field,
                      editable: true,
                      finishedBenchCounts: _substituteCounts,
                      markerMetrics: metrics,
                      onDroppedOnSlot: (moving, slot) =>
                          _handlePitchDrop(moving, slot),
                      onRemoveFromField: (_) => _showMessage(
                        'Glisse ce joueur sur le remplaçant qui entre, '
                        'à gauche du terrain.',
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.sectionGap),
        _LiveJournal(
          events: _events,
          expanded: _journalExpanded,
          canEdit: true,
          onExpandedChanged: (value) =>
              setState(() => _journalExpanded = value),
          onEditScorer: _pickGoalScorer,
          onEditAssist: _pickGoalAssist,
          onDelete: _confirmDeleteEvent,
        ),
      ],
    );
  }

  Widget _buildReport() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _reportScoreLine(
                  'AS Grinta',
                  _session.scoreAsGrinta,
                  () => _adjustScore('us', -1, allowFinished: true),
                  () => _adjustScore('us', 1, allowFinished: true),
                ),
                const Divider(height: 16),
                _reportScoreLine(
                  _opponentName,
                  _session.scoreAdverse,
                  () => _adjustScore('them', -1, allowFinished: true),
                  () => _adjustScore('them', 1, allowFinished: true),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Effectif')),
            ButtonSegment(value: true, label: Text('Faits du match')),
          ],
          selected: {_reportFacts},
          onSelectionChanged: (value) =>
              setState(() => _reportFacts = value.first),
        ),
        const SizedBox(height: 12),
        if (!_reportFacts)
          MatchSquadEditor(
            lineup: _lineup,
            editable: false,
            timesBenched: _substituteCounts,
            onDroppedOnSlot: (_, __) {},
            onMoveToBench: (_) {},
          )
        else
          Card(
            child: Column(
              children: [
                if (_events.where((e) =>
                    e.type == MatchLiveEventType.goalUs ||
                    e.type == MatchLiveEventType.goalThem).isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Aucun but enregistré.'),
                    ),
                  )
                else
                  for (final event in _events.reversed.where((e) =>
                      e.type == MatchLiveEventType.goalUs ||
                      e.type == MatchLiveEventType.goalThem))
                    _JournalEventRow(
                      event: event,
                      canEdit: true,
                      canEditScorer: true,
                      onEditScorer: _pickGoalScorer,
                      onEditAssist: _pickGoalAssist,
                      onDelete: _confirmDeleteEvent,
                    ),
              ],
            ),
          ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () =>
              _showMessage('Compte rendu validé et statistiques synchronisées.'),
          icon: const Icon(Icons.check_circle_outline_rounded),
          label: const Text('Valider le compte rendu'),
        ),
      ],
    );
  }

  Widget _reportScoreLine(
    String label,
    int score,
    VoidCallback onMinus,
    VoidCallback onPlus,
  ) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          onPressed: score > 0 ? onMinus : null,
          icon: const Icon(Icons.remove_circle_outline_rounded),
        ),
        SizedBox(
          width: 36,
          child: Text(
            '$score',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        IconButton(
          onPressed: onPlus,
          icon: const Icon(Icons.add_circle_outline_rounded),
        ),
      ],
    );
  }

  Future<void> _confirmAndStart() async {
    final minutes = int.tryParse(_durationController.text.trim());
    if (minutes == null || minutes < 1) {
      _showMessage('Entre un temps de jeu valide.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Vérifiez que la composition est bonne'),
        content: const Text(
          'Une fois le match démarré, le chronomètre se lance pour tout le '
          'monde et cette composition devient celle que voient les joueurs.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Corriger'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Démarrer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _kickoffLineup = _lineup.copyWith(entries: [..._lineup.entries]);
      _substituteCounts
        ..clear()
        ..addEntries(
          _lineup.entriesFor(MatchCompositionZone.bench).map(
                (entry) => MapEntry(entry.participantId, 1),
              ),
        );
      _session = MatchLiveSession(
        matchId: _matchId,
        sessionExists: true,
        state: MatchLiveState.running,
        planPlannedDurationMinutes: minutes,
        half: 1,
        elapsedSeconds: 0,
        runningSince: DateTime.now(),
        scoreAsGrinta: 0,
        scoreAdverse: 0,
        startedAt: DateTime.now(),
        exported: false,
        lineupRevision: 1,
      );
    });
  }

  void _pause() {
    final elapsed = _elapsedSeconds();
    setState(() {
      _session = _copySession(
        state: MatchLiveState.paused,
        elapsedSeconds: elapsed,
        clearRunningSince: true,
      );
    });
  }

  void _resume() {
    setState(() {
      _session = _copySession(
        state: MatchLiveState.running,
        runningSince: DateTime.now(),
      );
    });
  }

  void _resumeSecondHalf() {
    setState(() {
      _session = _copySession(
        state: MatchLiveState.running,
        half: 2,
        runningSince: DateTime.now(),
      );
    });
  }

  Future<void> _confirmHalftime() async {
    final planned = _session.planPlannedDurationMinutes;
    final target = Duration(seconds: planned * 30);
    final minutes = target.inMinutes.toString().padLeft(2, '0');
    final seconds = (target.inSeconds % 60).toString().padLeft(2, '0');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Passer à la mi-temps ?'),
        content: Text(
          'Le chronomètre sera calé sur $minutes:$seconds — la moitié des '
          '$planned minutes de jeu prévues — puis mis en pause.\n\n'
          'Le temps affiché actuellement sera donc remplacé.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Oui, mi-temps'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _session = _copySession(
        state: MatchLiveState.halftime,
        elapsedSeconds: planned * 30,
        clearRunningSince: true,
      );
    });
  }

  Future<void> _confirmEndMatch() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Fin du match'),
        content: const Text('Êtes-vous sûr de vouloir finir le match ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Oui, terminer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _session = _copySession(
        state: MatchLiveState.finished,
        elapsedSeconds: _elapsedSeconds(),
        clearRunningSince: true,
        finishedAt: DateTime.now(),
      );
    });
  }

  Future<void> _confirmRestart() async {
    final goals = _events.where((event) =>
        event.type == MatchLiveEventType.goalUs ||
        event.type == MatchLiveEventType.goalThem).length;
    final substitutions = _events
        .where((event) => event.type == MatchLiveEventType.substitution)
        .length;
    final details = [
      if (goals > 0) goals == 1 ? '1 but' : '$goals buts',
      if (substitutions > 0)
        substitutions == 1
            ? '1 remplacement'
            : '$substitutions remplacements',
    ];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Recommencer le match ?'),
        content: Text(
          details.isEmpty
              ? 'Le chronomètre et le score repartent à zéro, et la '
                  'composition redevient celle du coup d’envoi.\n\n'
                  'Cette action est définitive.'
              : 'Tout ce qui a été saisi sera effacé : ${details.join(' et ')}, '
                  'le chronomètre et le score.\n\n'
                  'La composition redevient celle du coup d’envoi et tu '
                  'reviens à l’écran de préparation.\n\n'
                  'Cette action est définitive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Tout effacer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _pending.clear();
      _events.clear();
      _substituteCounts.clear();
      _lineup = _kickoffLineup ?? _initialLineup();
      _session = _notStartedSession(
        plannedDuration:
            int.tryParse(_durationController.text.trim()) ?? 90,
      );
      _journalExpanded = false;
    });
  }

  void _adjustScore(
    String team,
    int delta, {
    bool allowFinished = false,
  }) {
    if (!allowFinished &&
        !{
          MatchLiveState.running,
          MatchLiveState.paused,
          MatchLiveState.halftime,
        }.contains(_session.state)) {
      return;
    }

    final isUs = team == 'us';
    final current = isUs ? _session.scoreAsGrinta : _session.scoreAdverse;
    if (delta > 0 && current >= 99) return;
    if (delta < 0 && current <= 0) return;

    if (delta > 0) {
      final next = current + 1;
      final minute = _session.displayMinuteAt(DateTime.now());
      final event = MatchLiveEvent(
        id: 'event-${_nextEventId++}',
        type: isUs ? MatchLiveEventType.goalUs : MatchLiveEventType.goalThem,
        minute: minute,
        half: _session.half,
        scoreAsGrintaAfter: isUs ? next : null,
        scoreAdverseAfter: isUs ? null : next,
      );
      setState(() {
        _events.add(event);
        _session = _copySession(
          scoreAsGrinta: isUs ? next : _session.scoreAsGrinta,
          scoreAdverse: isUs ? _session.scoreAdverse : next,
        );
      });
      return;
    }

    MatchLiveEvent? last;
    for (final event in _events.reversed) {
      if ((isUs && event.type == MatchLiveEventType.goalUs) ||
          (!isUs && event.type == MatchLiveEventType.goalThem)) {
        last = event;
        break;
      }
    }

    setState(() {
      if (last != null) _events.remove(last);
      final next = current - 1;
      _session = _copySession(
        scoreAsGrinta: isUs ? next : _session.scoreAsGrinta,
        scoreAdverse: isUs ? _session.scoreAdverse : next,
      );
    });
  }

  MatchComposition _previewLineup(MatchComposition lineup) {
    if (_pending.isEmpty) return lineup;

    final positions = {
      for (final entry in lineup.entriesFor(MatchCompositionZone.field))
        entry.participantId: Offset(entry.x ?? .5, entry.y ?? .5),
    };
    final incomingOf = {
      for (final pair in _pending) pair.playerIn: pair.playerOut,
    };
    final outgoing = {for (final pair in _pending) pair.playerOut};
    var benchOrder = lineup.entriesFor(MatchCompositionZone.bench).length;

    return lineup.copyWith(
      entries: [
        for (final entry in lineup.entries)
          if (incomingOf.containsKey(entry.participantId))
            entry.moveTo(
              MatchCompositionZone.field,
              x: positions[incomingOf[entry.participantId]]?.dx ?? .5,
              y: positions[incomingOf[entry.participantId]]?.dy ?? .5,
            )
          else if (outgoing.contains(entry.participantId))
            entry.moveTo(
              MatchCompositionZone.bench,
              sortOrder: benchOrder++,
            )
          else
            entry,
      ],
    );
  }

  bool _isPendingParticipant(String participantId) => _pending.any(
        (pair) =>
            pair.playerIn == participantId ||
            pair.playerOut == participantId,
      );

  void _stage({
    required MatchCompositionEntry playerIn,
    required MatchCompositionEntry playerOut,
  }) {
    final alreadyUsed = _pending.any(
      (pair) =>
          pair.playerIn == playerIn.participantId ||
          pair.playerOut == playerIn.participantId ||
          pair.playerIn == playerOut.participantId ||
          pair.playerOut == playerOut.participantId,
    );
    if (alreadyUsed) {
      _showMessage('Ce joueur fait déjà partie des changements en attente.');
      return;
    }
    setState(() {
      _pending.add((
        playerIn: playerIn.participantId,
        playerOut: playerOut.participantId,
      ));
    });
  }

  void _handlePitchDrop(
    MatchCompositionEntry moving,
    FootballFormationSlot slot,
  ) {
    if (_isPendingParticipant(moving.participantId)) {
      _showMessage(
        'Valide ou annule ce changement avant de déplacer ce joueur.',
      );
      return;
    }

    MatchCompositionEntry? currentAtSlot;
    for (final entry in _lineup.entriesFor(MatchCompositionZone.field)) {
      if ((Offset(entry.x ?? .5, entry.y ?? .5) - slot.position).distance <
          .12) {
        currentAtSlot = entry;
        break;
      }
    }

    if (currentAtSlot != null &&
        _isPendingParticipant(currentAtSlot.participantId)) {
      _showMessage(
        'Cette position fait déjà partie d’un changement en attente.',
      );
      return;
    }

    if (moving.zone != MatchCompositionZone.field) {
      if (currentAtSlot == null) {
        _showMessage(
          'Dépose ce joueur sur un titulaire déjà sur le terrain pour '
          'faire une entrée.',
        );
        return;
      }
      _stage(playerIn: moving, playerOut: currentAtSlot);
      return;
    }

    final oldPosition = Offset(moving.x ?? .5, moving.y ?? .5);
    setState(() {
      _lineup = _lineup.copyWith(
        entries: [
          for (final entry in _lineup.entries)
            if (entry.participantId == moving.participantId)
              entry.moveTo(
                MatchCompositionZone.field,
                x: slot.position.dx,
                y: slot.position.dy,
              )
            else if (currentAtSlot != null &&
                entry.participantId == currentAtSlot.participantId)
              entry.moveTo(
                MatchCompositionZone.field,
                x: oldPosition.dx,
                y: oldPosition.dy,
              )
            else
              entry,
        ],
      );
    });
  }

  void _validatePending() {
    if (_pending.isEmpty) return;
    final pairs = [..._pending];
    final positions = {
      for (final entry in _lineup.entriesFor(MatchCompositionZone.field))
        entry.participantId: Offset(entry.x ?? .5, entry.y ?? .5),
    };
    final incomingOf = {for (final pair in pairs) pair.playerIn: pair.playerOut};
    final outgoing = {for (final pair in pairs) pair.playerOut};
    var benchOrder = _lineup.entriesFor(MatchCompositionZone.bench).length;
    final minute = _session.displayMinuteAt(DateTime.now());

    setState(() {
      _lineup = _lineup.copyWith(
        entries: [
          for (final entry in _lineup.entries)
            if (incomingOf.containsKey(entry.participantId))
              entry.moveTo(
                MatchCompositionZone.field,
                x: positions[incomingOf[entry.participantId]]?.dx ?? .5,
                y: positions[incomingOf[entry.participantId]]?.dy ?? .5,
              )
            else if (outgoing.contains(entry.participantId))
              entry.moveTo(
                MatchCompositionZone.bench,
                sortOrder: benchOrder++,
              )
            else
              entry,
        ],
      );

      for (final pair in pairs) {
        _substituteCounts[pair.playerOut] =
            (_substituteCounts[pair.playerOut] ?? 0) + 1;
        _events.add(
          MatchLiveEvent(
            id: 'event-${_nextEventId++}',
            type: MatchLiveEventType.substitution,
            minute: minute,
            half: _session.half,
            playerInParticipantId: pair.playerIn,
            playerInName: _nameOf(pair.playerIn),
            playerOutParticipantId: pair.playerOut,
            playerOutName: _nameOf(pair.playerOut),
          ),
        );
      }
      _pending.clear();
    });
  }

  Future<void> _pickGoalScorer(MatchLiveEvent event) async {
    final candidates = [
      ..._lineup.entriesFor(MatchCompositionZone.field),
      ..._lineup.entriesFor(MatchCompositionZone.bench),
    ];
    final choice = await pickMatchLiveScorer(
      context,
      candidates: candidates,
      title:
          'Qui a marqué à la ${AppFormats.ordinalFeminine(event.minute)} minute ?',
      extraChoiceLabel: 'CSC adverse',
      extraChoiceIcon: Icons.shield_moon_outlined,
      clearChoiceLabel:
          event.needsScorer ? null : 'Effacer · buteur à désigner plus tard',
    );
    if (choice == null || !mounted) return;

    if (choice == kMatchLiveExtraChoiceId) {
      _replaceEvent(
        event,
        MatchLiveEvent(
          id: event.id,
          type: event.type,
          minute: event.minute,
          half: event.half,
          scoreAsGrintaAfter: event.scoreAsGrintaAfter,
          scoreAdverseAfter: event.scoreAdverseAfter,
          isOpponentOwnGoal: true,
        ),
      );
      return;
    }

    if (choice == kMatchLiveClearChoiceId) {
      _replaceEvent(
        event,
        MatchLiveEvent(
          id: event.id,
          type: event.type,
          minute: event.minute,
          half: event.half,
          scoreAsGrintaAfter: event.scoreAsGrintaAfter,
          scoreAdverseAfter: event.scoreAdverseAfter,
        ),
      );
      return;
    }

    final scorer = _lineup.entries.firstWhere(
      (entry) => entry.participantId == choice,
    );
    final assist = await _askAssist(
      scorerParticipantId: choice,
      minute: event.minute,
      candidates: candidates,
    );
    if (!mounted) return;

    final assistId = assist.answered
        ? assist.participantId
        : (choice == event.scorerParticipantId
            ? event.assistParticipantId
            : null);
    final assistName = assistId == null ? null : _nameOf(assistId);

    _replaceEvent(
      event,
      MatchLiveEvent(
        id: event.id,
        type: event.type,
        minute: event.minute,
        half: event.half,
        scorerParticipantId: choice,
        scorerName: scorer.displayName,
        assistParticipantId: assistId,
        assistName: assistName,
        scoreAsGrintaAfter: event.scoreAsGrintaAfter,
        scoreAdverseAfter: event.scoreAdverseAfter,
      ),
    );
  }

  Future<void> _pickGoalAssist(MatchLiveEvent event) async {
    final scorer = event.scorerParticipantId;
    if (scorer == null) return;
    final candidates = [
      ..._lineup.entriesFor(MatchCompositionZone.field),
      ..._lineup.entriesFor(MatchCompositionZone.bench),
    ];
    final assist = await _askAssist(
      scorerParticipantId: scorer,
      minute: event.minute,
      candidates: candidates,
    );
    if (!assist.answered || !mounted) return;

    _replaceEvent(
      event,
      MatchLiveEvent(
        id: event.id,
        type: event.type,
        minute: event.minute,
        half: event.half,
        scorerParticipantId: scorer,
        scorerName: event.scorerName,
        assistParticipantId: assist.participantId,
        assistName:
            assist.participantId == null ? null : _nameOf(assist.participantId!),
        scoreAsGrintaAfter: event.scoreAsGrintaAfter,
        scoreAdverseAfter: event.scoreAdverseAfter,
      ),
    );
  }

  Future<({bool answered, String? participantId})> _askAssist({
    required List<MatchCompositionEntry> candidates,
    required String scorerParticipantId,
    required int minute,
  }) async {
    final choice = await pickMatchLiveScorer(
      context,
      candidates: [
        for (final entry in candidates)
          if (entry.participantId != scorerParticipantId) entry,
      ],
      title: 'Passe décisive sur le but de la '
          '${AppFormats.ordinalFeminine(minute)} minute ?',
      icon: Icons.emoji_events_outlined,
      extraChoiceLabel: 'Aucune passe décisive',
      extraChoiceIcon: Icons.block_outlined,
    );
    if (choice == null) return (answered: false, participantId: null);
    if (choice == kMatchLiveExtraChoiceId) {
      return (answered: true, participantId: null);
    }
    return (answered: true, participantId: choice);
  }

  Future<void> _confirmDeleteEvent(MatchLiveEvent event) async {
    final description = switch (event.type) {
      MatchLiveEventType.goalUs => event.isOpponentOwnGoal
          ? "But AS Grinta (CSC adverse) · ${event.minute}'"
          : "But AS Grinta · ${event.scorerName ?? 'buteur à désigner'} · "
              "${event.minute}'",
      MatchLiveEventType.goalThem => "But adverse · ${event.minute}'",
      MatchLiveEventType.substitution => '${event.playerInName ?? '?'} entre · '
          '${event.playerOutName ?? '?'} sort · ${event.minute}\'',
    };
    final title = event.type == MatchLiveEventType.substitution
        ? 'Retirer ce remplacement ?'
        : 'Retirer ce but ?';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(description),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Retirer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _events.removeWhere((item) => item.id == event.id);
      if (event.type == MatchLiveEventType.goalUs) {
        _session = _copySession(
          scoreAsGrinta: (_session.scoreAsGrinta - 1).clamp(0, 99),
        );
      } else if (event.type == MatchLiveEventType.goalThem) {
        _session = _copySession(
          scoreAdverse: (_session.scoreAdverse - 1).clamp(0, 99),
        );
      } else if (event.playerOutParticipantId != null) {
        final id = event.playerOutParticipantId!;
        _substituteCounts[id] =
            ((_substituteCounts[id] ?? 0) - 1).clamp(0, 999);
      }
    });
  }

  void _replaceEvent(MatchLiveEvent oldEvent, MatchLiveEvent next) {
    final index = _events.indexWhere((event) => event.id == oldEvent.id);
    if (index < 0) return;
    setState(() => _events[index] = next);
  }

  void _showAddPlayerSheet() {
    const roster = ['Aki', 'Hakim', 'Julio', 'Nicolas', 'Simon'];
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return _LocalAddPlayerSheet(
          roster: roster,
          onAdd: (name, goalkeeper) {
            Navigator.of(sheetContext).pop();
            _addBenchPlayer(name, goalkeeper: goalkeeper);
          },
        );
      },
    );
  }

  void _addBenchPlayer(String name, {bool goalkeeper = false}) {
    final id = 'added-${name.toLowerCase().replaceAll(' ', '-')}-$_nextEventId';
    final entry = MatchCompositionEntry(
      participantId: id,
      seasonPlayerId: id,
      displayName: name,
      isGoalkeeper: goalkeeper,
      zone: MatchCompositionZone.bench,
      sortOrder: _lineup.entriesFor(MatchCompositionZone.bench).length,
      availabilityStatus: 'available',
      convocationStatus: 'convoked',
      selectionStatus: 'substitute',
    );
    setState(() {
      _lineup = _lineup.copyWith(entries: [..._lineup.entries, entry]);
      if (_session.state != MatchLiveState.notStarted) {
        _substituteCounts[id] = 1;
        final kickoff = _kickoffLineup;
        if (kickoff != null) {
          _kickoffLineup = kickoff.copyWith(
            entries: [...kickoff.entries, entry],
          );
        }
      }
    });
    _showMessage('Joueur ajouté directement sur le banc.');
  }

  int _elapsedSeconds() =>
      _session.elapsedAt(DateTime.now()).inSeconds;

  MatchLiveSession _copySession({
    MatchLiveState? state,
    int? half,
    int? elapsedSeconds,
    DateTime? runningSince,
    bool clearRunningSince = false,
    int? scoreAsGrinta,
    int? scoreAdverse,
    DateTime? finishedAt,
  }) {
    return MatchLiveSession(
      matchId: _session.matchId,
      sessionExists: _session.sessionExists,
      state: state ?? _session.state,
      planPlannedDurationMinutes: _session.planPlannedDurationMinutes,
      half: half ?? _session.half,
      elapsedSeconds: elapsedSeconds ?? _session.elapsedSeconds,
      runningSince:
          clearRunningSince ? null : (runningSince ?? _session.runningSince),
      scoreAsGrinta: scoreAsGrinta ?? _session.scoreAsGrinta,
      scoreAdverse: scoreAdverse ?? _session.scoreAdverse,
      startedAt: _session.startedAt,
      finishedAt: finishedAt ?? _session.finishedAt,
      exported: false,
      lineupRevision: _session.lineupRevision + 1,
    );
  }

  String _nameOf(String participantId) {
    for (final entry in _lineup.entries) {
      if (entry.participantId == participantId) return entry.displayName;
    }
    return '?';
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  static MatchLiveSession _notStartedSession({int plannedDuration = 90}) {
    return MatchLiveSession(
      matchId: _matchId,
      sessionExists: true,
      state: MatchLiveState.notStarted,
      planPlannedDurationMinutes: plannedDuration,
      half: 1,
      elapsedSeconds: 0,
      scoreAsGrinta: 0,
      scoreAdverse: 0,
      exported: false,
      lineupRevision: 0,
    );
  }

  static MatchComposition _initialLineup() {
    MatchCompositionEntry player(
      String id,
      String name,
      MatchCompositionZone zone,
      int order, {
      bool goalkeeper = false,
      double? x,
      double? y,
    }) {
      return MatchCompositionEntry(
        participantId: id,
        seasonPlayerId: id,
        displayName: name,
        isGoalkeeper: goalkeeper,
        zone: zone,
        sortOrder: order,
        x: x,
        y: y,
        availabilityStatus: 'available',
        convocationStatus: 'convoked',
        selectionStatus:
            zone == MatchCompositionZone.field ? 'starter' : 'substitute',
      );
    }

    return MatchComposition(
      matchId: _matchId,
      formationCode: '4-2-1-3',
      status: 'published',
      version: 1,
      hasUnpublishedChanges: false,
      squadSizeExceptionApproved: false,
      entries: [
        player('francois', 'Francois', MatchCompositionZone.field, 0,
            x: .12, y: .22),
        player('poulain', 'Poulain', MatchCompositionZone.field, 1,
            x: .68, y: .70),
        player('julien', 'Julien', MatchCompositionZone.field, 2,
            x: .32, y: .70),
        player('alyoun', 'Alyoun', MatchCompositionZone.field, 4,
            x: .10, y: .65),
        player('romain', 'Romain', MatchCompositionZone.field, 5,
            x: .70, y: .50),
        player('samih', 'Samih', MatchCompositionZone.field, 6,
            goalkeeper: true, x: .50, y: .85),
        player('samuel', 'Samuel', MatchCompositionZone.field, 7,
            x: .90, y: .65),
        player('alban', 'Alban', MatchCompositionZone.field, 8,
            x: .50, y: .27),
        player('allan', 'Allan', MatchCompositionZone.field, 10,
            x: .88, y: .22),
        player('flo', 'Flo', MatchCompositionZone.field, 12,
            x: .30, y: .50),
        player('pipo', 'Pipo', MatchCompositionZone.field, 13,
            x: .50, y: .08),
        player('amine', 'Amine', MatchCompositionZone.bench, 0),
        player('lulu', 'Lulu', MatchCompositionZone.bench, 1),
        player('steph', 'Steph', MatchCompositionZone.bench, 2),
      ],
    );
  }
}

class _LocalAddPlayerSheet extends StatefulWidget {
  const _LocalAddPlayerSheet({
    required this.roster,
    required this.onAdd,
  });

  final List<String> roster;
  final void Function(String name, bool goalkeeper) onAdd;

  @override
  State<_LocalAddPlayerSheet> createState() => _LocalAddPlayerSheetState();
}

class _LocalAddPlayerSheetState extends State<_LocalAddPlayerSheet> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  bool _goalkeeper = false;
  bool _guest = false;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Ajouter un joueur',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 4),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Tout joueur ajouté ici arrive directement sur le banc.',
            ),
          ),
          const SizedBox(height: 14),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                icon: Icon(Icons.groups_rounded),
                label: Text('Effectif'),
              ),
              ButtonSegment(
                value: true,
                icon: Icon(Icons.person_add_alt_1_rounded),
                label: Text('Invité'),
              ),
            ],
            selected: {_guest},
            onSelectionChanged: (value) =>
                setState(() => _guest = value.first),
          ),
          const SizedBox(height: 12),
          if (!_guest)
            ...widget.roster.map(
              (name) => ListTile(
                title: Text(name),
                leading: const Icon(Icons.person_outline_rounded),
                onTap: () => widget.onAdd(name, false),
              ),
            )
          else ...[
            TextField(
              controller: _firstName,
              decoration: const InputDecoration(labelText: 'Prénom'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _lastName,
              decoration: const InputDecoration(labelText: 'Nom (optionnel)'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Gardien'),
              value: _goalkeeper,
              onChanged: (value) => setState(() => _goalkeeper = value),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () {
                final first = _firstName.text.trim();
                if (first.isEmpty) return;
                final last = _lastName.text.trim();
                final name = [
                  first,
                  if (last.isNotEmpty) last,
                  '(Invité)',
                ].join(' ');
                widget.onAdd(name, _goalkeeper);
              },
              child: const Text('Ajouter au banc'),
            ),
          ],
        ],
      ),
    );
  }
}
