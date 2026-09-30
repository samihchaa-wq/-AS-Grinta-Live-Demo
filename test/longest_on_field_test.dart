import 'package:as_grinta/features/match_live/domain/longest_on_field.dart';
import 'package:as_grinta/features/match_live/domain/match_live_event.dart';
import 'package:as_grinta/features/sports_management/domain/match_composition.dart';
import 'package:flutter_test/flutter_test.dart';

MatchCompositionEntry player(String id, {bool goalkeeper = false}) =>
    MatchCompositionEntry(
      participantId: id,
      seasonPlayerId: id,
      displayName: id,
      isGoalkeeper: goalkeeper,
      zone: MatchCompositionZone.field,
      sortOrder: 0,
      availabilityStatus: 'available',
      convocationStatus: 'convoked',
      selectionStatus: 'starter',
    );

MatchLiveEvent change(String id, String inP, String outP, int minute) =>
    MatchLiveEvent(
      id: id,
      type: MatchLiveEventType.substitution,
      minute: minute,
      half: 1,
      playerInParticipantId: inP,
      playerOutParticipantId: outP,
      createdAt: DateTime.utc(2026, 9, 28, 19, minute),
    );

void main() {
  test('rien tant que plus de 3 titulaires de champ ne sont jamais sortis', () {
    final field = [
      player('G', goalkeeper: true),
      for (var i = 1; i <= 10; i++) player('T$i'),
    ];
    expect(
      longestOnFieldParticipants(
        field: field,
        events: const [],
        substituteCounts: const {},
      ),
      isEmpty,
    );
  });

  test('les 3 plus anciens sur le terrain, gardien exclu', () {
    // Sur le terrain : T1, T2 jamais sortis ; R1 entré à la 10e, R2 et R3
    // entrés ensemble à la 20e, R4 à la 30e. Tous les autres se sont reposés.
    final field = [
      player('G', goalkeeper: true),
      player('T1'),
      player('T2'),
      player('R1'),
      player('R2'),
      player('R3'),
      player('R4'),
    ];
    final events = [
      change('a', 'R1', 'T3', 10),
      change('b', 'R2', 'T4', 20),
      change('c', 'R3', 'T5', 20),
      change('d', 'R4', 'T6', 30),
    ];
    final counts = {'R1': 1, 'R2': 1, 'R3': 1, 'R4': 1};
    expect(
      longestOnFieldParticipants(
        field: field,
        events: events,
        substituteCounts: counts,
      ),
      {'T1', 'T2', 'R1'},
    );

    // T1 sort à la 40e : R2 et R3, entrés ensemble, sont ex æquo pour la
    // dernière place et sont tous deux signalés.
    final later = [...events, change('e', 'T3', 'T1', 40)];
    expect(
      longestOnFieldParticipants(
        field: [
          for (final p in field)
            if (p.participantId != 'T1') p,
          player('T3'),
        ],
        events: later,
        substituteCounts: {...counts, 'T1': 1, 'T3': 1},
      ),
      {'T2', 'R1', 'R2', 'R3'},
    );
  });
}
