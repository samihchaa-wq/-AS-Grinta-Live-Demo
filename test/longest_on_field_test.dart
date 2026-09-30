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

var _serial = 0;
MatchLiveEvent change(String inP, String outP, int minute) => MatchLiveEvent(
      id: 'e${_serial++}',
      type: MatchLiveEventType.substitution,
      minute: minute,
      half: 1,
      playerInParticipantId: inP,
      playerOutParticipantId: outP,
      createdAt: DateTime.utc(2026, 9, 28, 19, minute),
    );

void main() {
  final starters = [for (var i = 1; i <= 10; i++) 'T$i'];

  test('10 titulaires jamais sortis pour 3 remplaçants : personne', () {
    expect(
      longestOnFieldParticipants(
        field: [
          player('G', goalkeeper: true),
          for (final t in starters) player(t)
        ],
        events: const [],
        substituteCounts: const {},
        benchCount: 3,
      ),
      isEmpty,
    );
  });

  test('les 3 plus petits repères quand la coupure est nette', () {
    // Terrain : T1 jamais sorti (0.0), R1 et R2 entrés du banc (1.0),
    // T2..T4 sortis puis revenus (1.1), le reste à 1.2.
    final events = [
      change('R1', 'T2', 5),
      change('R2', 'T3', 5),
      change('R3', 'T4', 5),
      change('T2', 'T5', 10),
      change('T3', 'T6', 10),
      change('T4', 'T7', 10),
      change('T5', 'R3', 15),
      change('T6', 'T8', 15),
      change('T7', 'T9', 15),
    ];
    final field = [
      player('G', goalkeeper: true),
      for (final id in [
        'T1',
        'R1',
        'R2',
        'T2',
        'T3',
        'T4',
        'T5',
        'T6',
        'T7',
        'T10'
      ])
        player(id),
    ];
    final counts = {
      'R1': 1, 'R2': 1, 'R3': 2, //
      for (final t in ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'T8', 'T9']) t: 1,
    };
    // T10 jamais sorti : 0.0 comme T1. Plus petits : T1, T10 (0.0) puis R1,
    // R2 (1.0) : la 3e place est disputée par R1 et R2, personne n'est signalé.
    expect(
      longestOnFieldParticipants(
        field: field,
        events: events,
        substituteCounts: counts,
        benchCount: 3,
      ),
      isEmpty,
    );
    // Avec 4 remplaçants, la coupure passe après R1 et R2 : les 4 sont signalés.
    expect(
      longestOnFieldParticipants(
        field: field,
        events: events,
        substituteCounts: counts,
        benchCount: 4,
      ),
      {'T1', 'T10', 'R1', 'R2'},
    );
  });

  test('le gardien jamais sorti n\'est jamais signalé', () {
    final field = [
      player('G', goalkeeper: true),
      player('A'),
      player('B'),
    ];
    expect(
      longestOnFieldParticipants(
        field: field,
        events: [change('A', 'X', 5)],
        substituteCounts: const {'X': 1, 'A': 1},
        benchCount: 1,
      ),
      {'B'},
    );
  });
}
