import 'dart:io';
import 'dart:ui' as ui;

import 'package:as_grinta/core/providers/supabase_provider.dart';
import 'package:as_grinta/core/theme/app_theme.dart';
import 'package:as_grinta/core/widgets/grinta_accessibility_scope.dart';
import 'package:as_grinta/demo/demo_backend.dart';
import 'package:as_grinta/demo/demo_fixture.dart';
import 'package:as_grinta/demo/demo_match_page.dart';
import 'package:as_grinta/demo/demo_repositories.dart';
import 'package:as_grinta/features/auth/presentation/auth_state.dart';
import 'package:as_grinta/features/match_live/data/match_live_repository.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_pilot.dart';
import 'package:as_grinta/features/match_live/presentation/match_live_providers.dart';
import 'package:as_grinta/features/matches/presentation/widgets/upcoming_match_fixture_header.dart';
import 'package:as_grinta/features/sports_management/data/match_sport_report_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

// Ce fichier est exécuté deux fois par la CI de parité : une fois avec les
// écrans de la démo, une fois avec ceux de l'application (même faux serveur).
// Les captures doivent être identiques à l'octet près, et le scénario à deux
// téléphones doit passer dans les deux cas.

const _boundaryKey = ValueKey('live-snapshot-boundary');
const _francois = 'a699d053-420f-4ab2-b15f-27048f68d565';
const _allan = 'abe33132-6417-43f9-a67f-3325bd542878';
const _amine = 'a4e345f9-bfd0-44ea-bae6-c2b7106a6aae';
const _lulu = 'e41da6cf-245c-4057-be2f-059de3330cba';

const _someoneElsePilots = 'Quelqu’un d’autre pilote déjà le live';
const _nobodyPilots = 'Personne ne pilote le live';
const _startMatch = 'Démarrer le match';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Sans cela, les tests Flutter dessinent chaque lettre et chaque icône comme
  // un simple rectangle : deux textes différents de même longueur donneraient
  // la même image. Avec les vraies polices, la comparaison porte aussi sur
  // le texte et les icônes.
  setUpAll(_loadRealFonts);

  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.devicePixelRatio = 1;
    view.physicalSize = const Size(430, 1600);
  });

  group('captures', () {
    testWidgets('avant ouverture', (tester) async {
      await _capture(tester, '01_before_open', DemoBackend());
    });

    testWidgets('avant coup d’envoi, spectateur', (tester) async {
      final backend = DemoBackend()
        ..claimPilot(90)
        ..releasePilot();
      await _capture(tester, '02_pre_kickoff', backend);
    });

    testWidgets('mi-temps avec but et remplacements', (tester) async {
      final backend = _halftimeScenario()..releasePilot();
      await _capture(tester, '03_halftime_spectator', backend);
    });

    testWidgets('salves distinctes dans la même minute côté pilote',
        (tester) async {
      await _capture(
        tester,
        '04_same_minute_salvos_pilot',
        _halftimeScenario(),
        pilotTab: true,
      );
    });

    testWidgets('fin du match', (tester) async {
      final backend = _halftimeScenario()..endMatch();
      await _capture(tester, '05_finished', backend);
    });

    testWidgets('onglet Piloter, place libre', (tester) async {
      final backend = DemoBackend()
        ..claimPilot(90)
        ..releasePilot();
      await _capture(
        tester,
        '06_pilot_place_available',
        backend,
        pilotTab: true,
        expectText: _nobodyPilots,
      );
    });

    testWidgets('onglet Piloter, un autre téléphone pilote', (tester) async {
      final backend = DemoBackend()
        ..simulateOtherCoachPilot(active: true);
      await _capture(
        tester,
        '07_someone_else_pilots',
        backend,
        pilotTab: true,
        expectText: _someoneElsePilots,
      );
    });

    testWidgets('confirmation « Prendre la main ? »', (tester) async {
      final backend = DemoBackend()
        ..simulateOtherCoachPilot(active: true);
      await _capture(
        tester,
        '08_take_over_dialog',
        backend,
        pilotTab: true,
        beforeCapture: () async {
          await tester.tap(find.widgetWithText(OutlinedButton, 'Prendre la main'));
          await _settle(tester);
          expect(find.text('Prendre la main ?'), findsOneWidget);
        },
      );
    });

    testWidgets('préparation du coup d’envoi côté pilote', (tester) async {
      final backend = DemoBackend()..claimPilot(90);
      await _capture(
        tester,
        '09_pre_kickoff_pilot',
        backend,
        pilotTab: true,
        expectText: _startMatch,
      );
    });

    testWidgets('direct en pause côté pilote', (tester) async {
      final backend = DemoBackend()
        ..claimPilot(90)
        ..confirmStart()
        ..adjustScore(team: 'them', delta: 1, operationId: 'visual-them')
        ..setClockState('pause');
      await _capture(tester, '10_running_paused_pilot', backend, pilotTab: true);
    });

    testWidgets('vue d’un joueur pendant le match', (tester) async {
      final backend = _halftimeScenario()..releasePilot();
      await _capture(tester, '11_player_view', backend, asCoach: false);
    });
  });

  testWidgets(
      'deux téléphones : prise, perte, reprise de main, expiration, coup '
      'd’envoi et actions Live', (tester) async {
    var now = DateTime.utc(2026, 10, 5, 13);
    final backend = DemoBackend(clock: () => now);
    await tester.pumpWidget(_SnapshotApp(backend: backend));
    await _settle(tester);

    // Téléphone A : « Piloter » obtient la place auprès du serveur.
    await tester.tap(find.text('Piloter'));
    await _settle(tester);
    expect(backend.liveSnapshot()['pilot_is_me'], isTrue);
    expect(find.text(_startMatch), findsOneWidget);

    // Téléphone B prend la main : A perd immédiatement l'écran pilote…
    backend.simulateOtherCoachPilot(active: true);
    await _settle(tester);
    expect(find.text(_someoneElsePilots), findsOneWidget);
    expect(find.text(_startMatch), findsNothing);
    // … et le serveur refuse ses écritures.
    _expectRefused(backend.confirmStart);
    expect(backend.liveSnapshot()['state'], 'not_started');

    // A reprend la main, après confirmation.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Prendre la main'));
    await _settle(tester);
    expect(find.text('Prendre la main ?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Prendre la main'));
    await _settle(tester);
    expect(backend.otherCoachPilots, isFalse);
    expect(backend.liveSnapshot()['pilot_is_me'], isTrue);
    expect(find.text(_startMatch), findsOneWidget);

    // Signe de vie toutes les 15 secondes : la place tient.
    now = now.add(matchLivePilotHeartbeatInterval);
    await tester.pump(matchLivePilotHeartbeatInterval);
    await _settle(tester);
    expect(backend.liveSnapshot()['pilot_is_me'], isTrue);

    // Plus d'une minute sans signe de vie (coupure réseau) : la place expire.
    now = now.add(const Duration(seconds: 61));
    await tester.pump(matchLivePilotHeartbeatInterval);
    await _settle(tester);
    expect(backend.liveSnapshot()['pilot_active'], isFalse);
    expect(find.text(_nobodyPilots), findsOneWidget);
    _expectRefused(backend.confirmStart);

    // Reprise : un clic suffit.
    await tester.tap(find.text('Piloter le live'));
    await _settle(tester);
    expect(backend.liveSnapshot()['pilot_is_me'], isTrue);

    // Coup d'envoi par le pilote.
    await tester.ensureVisible(find.text(_startMatch));
    await _settle(tester);
    await tester.tap(find.text(_startMatch));
    await _settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Démarrer'));
    await _settle(tester);
    expect(backend.liveSnapshot()['state'], 'running');

    // Quelques actions Live acceptées tant que A pilote.
    backend
      ..adjustScore(team: 'us', delta: 1, operationId: 'two-phones-goal')
      ..setClockState('pause');
    await _settle(tester);
    expect(backend.liveSnapshot()['score_as_grinta'], 1);
    expect(backend.liveSnapshot()['state'], 'paused');

    // B reprend la main en plein match : A ne peut plus rien modifier.
    backend.simulateOtherCoachPilot(active: true);
    await _settle(tester);
    expect(find.text(_someoneElsePilots), findsOneWidget);
    _expectRefused(
      () => backend.adjustScore(team: 'us', delta: 1, operationId: 'refused'),
    );
    _expectRefused(() => backend.setClockState('resume'));
    _expectRefused(backend.endMatch);
    expect(backend.liveSnapshot()['score_as_grinta'], 1);
    expect(backend.liveSnapshot()['state'], 'paused');

    await _dispose(tester);
  });
}

Future<void> _loadRealFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null) {
    throw StateError('FLUTTER_ROOT est requis pour charger les polices.');
  }
  final fonts = Directory('$flutterRoot/bin/cache/artifacts/material_fonts');

  Future<void> load(String family, bool Function(String name) keep) async {
    final files = fonts
        .listSync()
        .whereType<File>()
        .where((file) => keep(file.uri.pathSegments.last))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    if (files.isEmpty) throw StateError('Police $family introuvable.');
    final loader = FontLoader(family);
    for (final file in files) {
      loader.addFont(
        file.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
      );
    }
    await loader.load();
  }

  bool roboto(String name) => name.startsWith('Roboto-');
  await load('Roboto', roboto);
  // Police par défaut des tests, utilisée quand un style ne nomme aucune
  // police (boutons du thème) : sur téléphone, c'est aussi Roboto.
  await load('FlutterTest', roboto);
  await load('MaterialIcons', (name) => name == 'MaterialIcons-Regular.otf');
}

void _expectRefused(Object? Function() write) {
  expect(
    write,
    throwsA(
      isA<PostgrestException>()
          .having((error) => error.code, 'code', '42501'),
    ),
  );
}

DemoBackend _halftimeScenario() {
  final backend = DemoBackend()
    ..claimPilot(90)
    ..confirmStart()
    ..setClockState('halftime')
    ..adjustScore(team: 'us', delta: 1, operationId: 'visual-goal');

  final events = backend.liveSnapshot()['events'] as List<dynamic>;
  final goal = Map<String, dynamic>.from(events.last as Map);
  backend.setEventScorer(
    eventId: goal['id'] as String,
    scorerParticipantId: _francois,
    assistParticipantId: _allan,
  );

  _substitute(backend, playerIn: _amine, playerOut: _francois);
  _substitute(backend, playerIn: _lulu, playerOut: _allan);
  return backend;
}

void _substitute(
  DemoBackend backend, {
  required String playerIn,
  required String playerOut,
}) {
  final snapshot = backend.compositionSnapshot();
  final entries = (snapshot['entries'] as List<dynamic>)
      .map((entry) => Map<String, dynamic>.from(entry as Map))
      .toList();
  final incoming = entries.firstWhere(
    (entry) => entry['participant_id'] == playerIn,
  );
  final outgoing = entries.firstWhere(
    (entry) => entry['participant_id'] == playerOut,
  );

  final incomingOrder = incoming['sort_order'];
  incoming
    ..['zone'] = 'field'
    ..['x'] = outgoing['x']
    ..['y'] = outgoing['y']
    ..['slot_label'] = outgoing['slot_label']
    ..['sort_order'] = outgoing['sort_order'];
  outgoing
    ..['zone'] = 'bench'
    ..['x'] = null
    ..['y'] = null
    ..['slot_label'] = null
    ..['sort_order'] = incomingOrder;

  backend.saveLiveLineup(
    entries: entries,
    expectedLineupRevision:
        backend.liveSnapshot()['lineup_revision'] as int,
    substitutions: [(playerIn: playerIn, playerOut: playerOut)],
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 250));
}

/// Démonte l'écran puis laisse partir les derniers appels (libération de la
/// place de pilote), pour qu'aucun minuteur ne reste en attente.
Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _capture(
  WidgetTester tester,
  String name,
  DemoBackend backend, {
  bool pilotTab = false,
  bool asCoach = true,
  String? expectText,
  Future<void> Function()? beforeCapture,
}) async {
  await tester.pumpWidget(
    _SnapshotApp(backend: backend, pilotTab: pilotTab, asCoach: asCoach),
  );
  await _settle(tester);
  if (expectText != null) expect(find.text(expectText), findsOneWidget);
  if (beforeCapture != null) await beforeCapture();

  expect(find.byKey(_boundaryKey), findsOneWidget);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundaryKey),
  );

  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('Impossible de générer la capture Live.');
      }

      final output = Platform.environment['SNAPSHOT_DIR'] ??
          '${Directory.current.path}/build/live_snapshots';
      final directory = Directory(output)..createSync(recursive: true);
      await File('${directory.path}/$name.png').writeAsBytes(
        data.buffer.asUint8List(),
        flush: true,
      );
    } finally {
      image.dispose();
    }
  });

  await _dispose(tester);
}

class _SnapshotApp extends StatelessWidget {
  const _SnapshotApp({
    required this.backend,
    this.pilotTab = false,
    this.asCoach = true,
  });

  final DemoBackend backend;
  final bool pilotTab;
  final bool asCoach;

  @override
  Widget build(BuildContext context) {
    final baseTheme = AppTheme.dark;
    return ProviderScope(
      overrides: [
        demoBackendProvider.overrideWithValue(backend),
        supabaseClientProvider.overrideWith(
          (ref) => throw UnsupportedError('Snapshot hors ligne.'),
        ),
        matchLiveRepositoryProvider.overrideWith(
          (ref) => DemoMatchLiveRepository(ref.watch(demoBackendProvider)),
        ),
        matchSportReportRepositoryProvider.overrideWith(
          (ref) =>
              DemoMatchSportReportRepository(ref.watch(demoBackendProvider)),
        ),
        isAdminViewProvider.overrideWith((ref) => false),
        isMatchCoachOrAdminProvider.overrideWith(
          (ref, matchId) async => asCoach,
        ),
        upcomingMatchFixtureProvider.overrideWith(
          (ref, matchId) async => UpcomingMatchFixtureData(
            status: 'a_venir',
            location: demoLocation,
            opponentName: demoOpponentName,
            kickoffAt: demoKickoffAt.toLocal(),
            address: demoAddress,
            matchType: demoMatchType,
          ),
        ),
        // Seul l'onglet affiché est imposé ici : la place de pilote, elle,
        // vient toujours de l'état renvoyé par le faux serveur.
        if (pilotTab)
          liveViewModeProvider(demoMatchId)
              .overrideWith((ref) => LiveViewMode.pilot),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('fr', 'FR'),
        supportedLocales: const [Locale('fr', 'FR')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: baseTheme,
        // La capture englobe le navigateur : les boîtes de dialogue y figurent.
        builder: (context, child) => MediaQuery(
          data: const MediaQueryData(
            size: Size(430, 1600),
            textScaler: TextScaler.linear(1.10),
          ),
          child: GrintaAccessibilityScope(
            child: RepaintBoundary(
              key: _boundaryKey,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
        home: const DemoMatchPage(),
      ),
    );
  }
}
