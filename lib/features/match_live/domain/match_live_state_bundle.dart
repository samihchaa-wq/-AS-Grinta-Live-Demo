import 'package:as_grinta/features/match_live/domain/match_live_event.dart';
import 'package:as_grinta/features/match_live/domain/match_live_session.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';

/// Bundle local de la démo. Même surface utile que le vrai Live, sans parsing RPC.
class MatchLiveStateBundle {
  const MatchLiveStateBundle({
    required this.session,
    required this.lineup,
    required this.events,
    required this.substituteCounts,
  });

  final MatchLiveSession session;
  final MatchComposition? lineup;
  final List<MatchLiveEvent> events;

  /// participantId -> nombre de fois sur le banc.
  final Map<String, int> substituteCounts;

  List<MatchLiveEvent> get substitutions =>
      events.where((e) => e.type == MatchLiveEventType.substitution).toList();

  List<MatchLiveEvent> get ownGoals =>
      events.where((e) => e.type == MatchLiveEventType.goalUs).toList();

  List<MatchLiveEvent> get opponentGoals =>
      events.where((e) => e.type == MatchLiveEventType.goalThem).toList();

  int timesBenched(String participantId) =>
      substituteCounts[participantId] ?? 0;
}
