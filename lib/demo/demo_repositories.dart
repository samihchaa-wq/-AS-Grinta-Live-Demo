import 'package:as_grinta/demo/demo_backend.dart';
import 'package:as_grinta/demo/demo_fixture.dart';
import 'package:as_grinta/features/match_live/data/match_live_repository.dart';
import 'package:as_grinta/features/match_live/domain/match_live_add_player_options.dart';
import 'package:as_grinta/features/match_live/domain/match_live_state_bundle.dart';
import 'package:as_grinta/features/match_live/domain/match_live_timeline.dart';
import 'package:as_grinta/features/sports_management/data/match_sport_report_repository.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:as_grinta/features/sports_management/domain/match_goal_action.dart';
import 'package:as_grinta/features/sports_management/domain/match_sport_report.dart';
import 'package:as_grinta/features/sports_management/domain/sport_match_finalization.dart';

/// Petit délai imitant un aller-retour réseau : les indicateurs de
/// chargement des écrans copiés apparaissent comme dans l'application.
const _latency = Duration(milliseconds: 120);

Future<T> _reply<T>(T Function() compute) async {
  await Future<void>.delayed(_latency);
  return compute();
}

/// Remplace SupabaseMatchLiveRepository : mêmes méthodes, mêmes réponses,
/// mais tout est calculé localement par [DemoBackend].
class DemoMatchLiveRepository implements MatchLiveRepository {
  DemoMatchLiveRepository(this._backend);

  final DemoBackend _backend;

  Future<MatchLiveStateBundle> _bundle(
    Map<String, dynamic> Function() action,
  ) =>
      _reply(() => MatchLiveStateBundle.fromRpc(action()));

  /// Écriture réservée au téléphone pilote, comme côté serveur.
  Future<MatchLiveStateBundle> _pilotWrite(
    Map<String, dynamic> Function() action,
  ) =>
      _bundle(() {
        _backend.requirePilot();
        return action();
      });

  @override
  Future<MatchLiveStateBundle> fetchLiveState(String matchId) =>
      _bundle(_backend.liveSnapshot);

  @override
  Future<MatchLiveTimeline?> fetchTimeline(String matchId) async => null;

  @override
  Future<MatchLiveAddPlayerOptions> fetchAddPlayerOptions(String matchId) =>
      _reply(
        () => MatchLiveAddPlayerOptions.fromRpc(_backend.addPlayerOptions()),
      );

  @override
  Future<MatchLiveStateBundle> claimPilot({
    required String matchId,
    int? plannedDurationMinutes,
  }) =>
      _bundle(() => _backend.claimPilot(plannedDurationMinutes));

  @override
  Future<MatchLiveStateBundle> takeOverPilot({required String matchId}) =>
      _bundle(_backend.takeOverPilot);

  @override
  Future<MatchLiveStateBundle> heartbeatPilot({required String matchId}) =>
      _bundle(_backend.heartbeatPilot);

  @override
  Future<MatchLiveStateBundle> releasePilot({required String matchId}) =>
      _bundle(_backend.releasePilot);

  @override
  Future<MatchLiveStateBundle> openWorkspace({
    required String matchId,
    int? plannedDurationMinutes,
  }) =>
      _pilotWrite(() => _backend.openWorkspace(plannedDurationMinutes));

  @override
  Future<MatchLiveStateBundle> confirmStart({
    required String matchId,
    String? reason,
  }) =>
      _pilotWrite(_backend.confirmStart);

  @override
  Future<MatchLiveStateBundle> setClockState({
    required String matchId,
    required String action,
    String? reason,
  }) =>
      _pilotWrite(() => _backend.setClockState(action));

  @override
  Future<MatchLiveStateBundle> adjustScore({
    required String matchId,
    required String team,
    required int delta,
    required String operationId,
    String? scorerParticipantId,
  }) =>
      _pilotWrite(
        () => _backend.adjustScore(
          team: team,
          delta: delta,
          operationId: operationId,
          scorerParticipantId: scorerParticipantId,
        ),
      );

  @override
  Future<MatchLiveStateBundle> addLivePlayers({
    required String matchId,
    required List<MatchLiveAddPlayerRequest> players,
    String? reason,
  }) =>
      _pilotWrite(
        () => _backend.addLivePlayers([
          for (final player in players) player.toRpcJson(),
        ]),
      );

  @override
  Future<MatchLiveStateBundle> saveLiveLineup({
    required String matchId,
    required List<Map<String, dynamic>> entries,
    required int expectedLineupRevision,
    List<({String playerIn, String playerOut})> substitutions = const [],
  }) =>
      _pilotWrite(
        () => _backend.saveLiveLineup(
          entries: entries,
          expectedLineupRevision: expectedLineupRevision,
          substitutions: substitutions,
        ),
      );

  @override
  Future<MatchLiveStateBundle> changeLiveFormation({
    required String matchId,
    required String formationCode,
    required List<Map<String, dynamic>> entries,
    required int expectedLineupRevision,
  }) =>
      _pilotWrite(
        () => _backend.changeLiveFormation(
          formationCode: formationCode,
          entries: entries,
          expectedLineupRevision: expectedLineupRevision,
        ),
      );

  @override
  Future<MatchLiveStateBundle> deleteEvent({
    required String matchId,
    required String eventId,
  }) =>
      _pilotWrite(() => _backend.deleteEvent(eventId));

  @override
  Future<MatchLiveStateBundle> setEventScorer({
    required String matchId,
    required String eventId,
    String? scorerParticipantId,
    bool isOpponentOwnGoal = false,
    String? assistParticipantId,
  }) =>
      _pilotWrite(
        () => _backend.setEventScorer(
          eventId: eventId,
          scorerParticipantId: scorerParticipantId,
          isOpponentOwnGoal: isOpponentOwnGoal,
          assistParticipantId: assistParticipantId,
        ),
      );

  @override
  Future<MatchLiveStateBundle> endMatch({
    required String matchId,
    String? reason,
  }) =>
      _pilotWrite(_backend.endMatch);

  @override
  Future<MatchLiveStateBundle> reopen({
    required String matchId,
    String? reason,
  }) =>
      _bundle(_backend.reopen);

  @override
  Future<MatchLiveStateBundle> restartSession({
    required String matchId,
    String? reason,
  }) =>
      _pilotWrite(_backend.restartSession);

  @override
  Future<SportMatchFinalization> publishRecap({
    required String matchId,
    required int scoreAsGrinta,
    required int scoreAdverse,
    required List<SportFinalParticipant> participants,
    String? reason,
  }) =>
      _reply(() => SportMatchFinalization.fromRpc(_backend.sportReport()));

  @override
  Stream<void> watchChanges(String matchId) => _backend.changes;
}

/// Remplace SupabaseMatchSportReportRepository pour l'écran « Compte rendu »
/// qui suit la fin du match.
class DemoMatchSportReportRepository implements MatchSportReportRepository {
  DemoMatchSportReportRepository(this._backend);

  final DemoBackend _backend;

  @override
  Future<MatchSportReport> fetch(String matchId) =>
      _reply(() => MatchSportReport.fromRpc(_backend.sportReport()));

  @override
  Future<List<MatchGoalAction>> fetchGoalActions(String matchId) => _reply(() {
        final rows = _backend.storedGoalActions();
        return [
          for (var index = 0; index < rows.length; index += 1)
            MatchGoalAction.fromJson(rows[index], index),
        ];
      });

  @override
  Future<MatchSportReport> submit({
    required String matchId,
    required int knownVersion,
    required int scoreAsGrinta,
    required int scoreAdverse,
    required MatchComposition lineup,
    required List<MatchGoalAction> goalActions,
    String? reason,
  }) =>
      _reply(
        () => MatchSportReport.fromRpc(
          _backend.submitReport(
            scoreAsGrinta: scoreAsGrinta,
            scoreAdverse: scoreAdverse,
            formationCode: lineup.formationCode ?? demoFormationCode,
            lineupEntries: [
              for (final entry in lineup.entries) entry.toRpcJson(),
            ],
            goalActions: [for (final goal in goalActions) goal.toRpcJson()],
          ),
        ),
      );

  @override
  Future<MatchSportReport> attachPlayer({
    required String matchId,
    String? seasonPlayerId,
    String? guestPlayerId,
    String? firstName,
    String? lastName,
    bool isGoalkeeper = false,
    String? reason,
  }) =>
      _reply(
        () => MatchSportReport.fromRpc(
          _backend.attachReportPlayer(
            seasonPlayerId: seasonPlayerId,
            guestPlayerId: guestPlayerId,
          ),
        ),
      );
}
