import 'package:as_grinta/features/match_live/domain/match_live_event.dart';
import 'package:as_grinta/features/match_live/domain/substitution_salvos.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';

/// Joueurs de champ à faire souffler en priorité, à titre informatif pour le
/// coach.
///
/// On retient autant de joueurs du terrain qu'il y a de remplaçants sur le
/// banc ([benchCount]) : ceux dont le repère « passage.série » est le plus
/// petit. Un titulaire jamais sorti passe avant tout le monde (« 0.0 »), un
/// joueur entré du banc sans en être ressorti vaut « 1.0 ». Le gardien n'est
/// jamais compté.
///
/// Si des joueurs à égalité se disputent la dernière place (par exemple 8
/// joueurs à « 1.1 » pour 3 remplaçants), personne n'est signalé : le choix
/// ne peut pas être fait à leur place.
Set<String> longestOnFieldParticipants({
  required Iterable<MatchCompositionEntry> field,
  required Iterable<MatchLiveEvent> events,
  required Map<String, int> substituteCounts,
  required int benchCount,
}) {
  final outfield = field.where((entry) => !entry.isGoalkeeper).toList();
  if (benchCount <= 0 || outfield.length < benchCount) return const {};

  final lastExits = lastExitMarksByParticipant(events);
  (int, int) markOf(String participantId) {
    final exit = lastExits[participantId];
    if (exit != null) return (exit.rest, exit.rank);
    return (substituteCounts[participantId] ?? 0, 0);
  }

  int compare((int, int) a, (int, int) b) {
    final byRest = a.$1.compareTo(b.$1);
    return byRest != 0 ? byRest : a.$2.compareTo(b.$2);
  }

  final ranked = [
    for (final entry in outfield)
      (entry.participantId, markOf(entry.participantId)),
  ]..sort((a, b) => compare(a.$2, b.$2));

  // La coupure ne doit pas séparer deux joueurs au même repère.
  if (ranked.length > benchCount &&
      compare(ranked[benchCount - 1].$2, ranked[benchCount].$2) == 0) {
    return const {};
  }
  return {for (final (id, _) in ranked.take(benchCount)) id};
}
