import 'package:as_grinta/features/match_live/domain/match_live_event.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';

/// Nombre de joueurs de champ signalés comme étant sur le terrain depuis le
/// plus longtemps.
const longestOnFieldCount = 3;

/// Joueurs de champ sur le terrain depuis le plus longtemps, à titre
/// informatif pour le coach.
///
/// Le repère n'apparaît qu'à partir du moment où il ne reste plus que
/// [longestOnFieldCount] joueurs de champ sur le terrain (ou moins) à n'être
/// jamais passés par le banc : avant, tous les titulaires encore là sont à
/// égalité. Le gardien n'est jamais compté.
///
/// L'ancienneté se mesure depuis la dernière entrée en jeu (le coup d'envoi
/// pour un titulaire jamais sorti). Les joueurs entrés dans la même salve
/// sont à égalité : s'ils se disputent la dernière place, tous sont signalés.
Set<String> longestOnFieldParticipants({
  required Iterable<MatchCompositionEntry> field,
  required Iterable<MatchLiveEvent> events,
  required Map<String, int> substituteCounts,
}) {
  final outfield = field.where((entry) => !entry.isGoalkeeper).toList();
  final neverRested = outfield
      .where((entry) => (substituteCounts[entry.participantId] ?? 0) == 0)
      .length;
  if (neverRested > longestOnFieldCount) return const {};

  // Rang d'entrée en jeu : 0 pour le coup d'envoi, puis une valeur croissante
  // par validation, dans l'ordre chronologique.
  final substitutions = events
      .where((event) => event.type == MatchLiveEventType.substitution)
      .toList();
  final indexed = [
    for (var i = 0; i < substitutions.length; i++) (i, substitutions[i]),
  ]..sort((a, b) {
      final byHalf = a.$2.half.compareTo(b.$2.half);
      if (byHalf != 0) return byHalf;
      final byMinute = a.$2.minute.compareTo(b.$2.minute);
      if (byMinute != 0) return byMinute;
      final aAt = a.$2.createdAt;
      final bAt = b.$2.createdAt;
      if (aAt != null && bAt != null) {
        final byTime = aAt.compareTo(bAt);
        if (byTime != 0) return byTime;
      }
      return a.$1.compareTo(b.$1);
    });
  final entryRank = <String, int>{};
  var rank = 0;
  (int, int, DateTime?)? previous;
  for (final (_, event) in indexed) {
    final key = (event.half, event.minute, event.createdAt);
    if (key != previous) {
      rank += 1;
      previous = key;
    }
    final inId = event.playerInParticipantId;
    if (inId != null) entryRank[inId] = rank;
  }

  final ranked = [
    for (final entry in outfield)
      (entry.participantId, entryRank[entry.participantId] ?? 0),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  if (ranked.length <= longestOnFieldCount) {
    return {for (final (id, _) in ranked) id};
  }
  final threshold = ranked[longestOnFieldCount - 1].$2;
  return {
    for (final (id, entered) in ranked)
      if (entered <= threshold) id,
  };
}
