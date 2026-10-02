import 'package:as_grinta/demo/demo_backend.dart';
import 'package:as_grinta/demo/demo_repositories.dart';
import 'package:as_grinta/demo/demo_fixture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// La démo reproduit le verrou serveur « un seul pilote » de l'application
/// (supabase/tests/database/live_single_pilot_and_kickoff.test.sql).
void main() {
  test('un seul téléphone pilote, comme côté serveur', () async {
    final backend = DemoBackend();
    final repository = DemoMatchLiveRepository(backend);

    // Sans place de pilote, aucune écriture n'est acceptée.
    await expectLater(
      repository.openWorkspace(matchId: demoMatchId),
      throwsA(isA<PostgrestException>()),
    );

    var bundle = await repository.claimPilot(matchId: demoMatchId);
    expect(bundle.session.sessionExists, isTrue);
    expect(bundle.session.pilotIsMe, isTrue);
    await repository.confirmStart(matchId: demoMatchId);

    // Un autre téléphone prend la main : ce téléphone ne peut plus modifier.
    backend.simulateOtherPilot(true);
    bundle = await repository.fetchLiveState(demoMatchId);
    expect(bundle.session.pilotActive, isTrue);
    expect(bundle.session.pilotIsMe, isFalse);
    await expectLater(
      repository.setClockState(matchId: demoMatchId, action: 'pause'),
      throwsA(
        isA<PostgrestException>()
            .having((e) => e.message, 'message', 'Tu ne pilotes pas ce Live.'),
      ),
    );

    // Piloter n'arrache pas la place ; « Prendre la main » si.
    bundle = await repository.claimPilot(matchId: demoMatchId);
    expect(bundle.session.pilotIsMe, isFalse);
    bundle = await repository.takeOverPilot(matchId: demoMatchId);
    expect(bundle.session.pilotIsMe, isTrue);
    expect(backend.otherPilotSimulated, isFalse);

    // Quitter libère la place ; la fin du match aussi.
    bundle = await repository.releasePilot(matchId: demoMatchId);
    expect(bundle.session.pilotActive, isFalse);
    await repository.claimPilot(matchId: demoMatchId);
    bundle = await repository.endMatch(matchId: demoMatchId);
    expect(bundle.session.pilotActive, isFalse);
  });
}
