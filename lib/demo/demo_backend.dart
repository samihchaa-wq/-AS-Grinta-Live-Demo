import 'dart:async';

import 'package:as_grinta/demo/demo_fixture.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// Faux serveur de la démo : il tient en mémoire, dans la page, tout ce que
/// Supabase stocke pour le Live (session, composition, événements, compte
/// rendu) et applique les mêmes règles que les fonctions SQL de production
/// (`private.match_live_snapshot`, `private.save_match_live_lineup`, …).
///
/// Les réponses ont exactement la forme JSON renvoyée par ces fonctions : les
/// écrans copiés de l'application les lisent avec leurs propres décodeurs,
/// sans aucune adaptation. Rien n'est jamais envoyé sur le réseau et tout
/// repart de zéro au rechargement de la page.
class DemoBackend {
  /// [clock] sert uniquement aux tests, pour simuler l'expiration du pilote
  /// sans attendre une minute.
  DemoBackend({DateTime Function()? clock}) : _clock = clock ?? DateTime.now {
    reset();
  }

  final DateTime Function() _clock;

  final Map<String, _Participant> _participants = {};
  final List<_Event> _events = [];
  final Set<String> _scoreOperations = {};
  final StreamController<void> _changes = StreamController<void>.broadcast();

  late _Session? _session;
  late String _formationCode;
  late String _compositionStatus;
  late int _compositionVersion;
  late DateTime? _publishedAt;
  late DateTime _compositionModifiedAt;
  late _Report _report;
  int _nextId = 1;
  DateTime _lastEventAt = DateTime.utc(2000);

  Stream<void> get changes => _changes.stream;

  void reset() {
    _participants
      ..clear()
      ..addEntries(
        demoParticipants.map(
          (p) => MapEntry(
            p.participantId,
            _Participant(
              id: p.participantId,
              seasonPlayerId: p.seasonPlayerId,
              displayName: p.displayName,
              lastInitial: p.lastInitial,
              isGoalkeeper: p.isGoalkeeper,
              availabilityStatus: p.availabilityStatus,
              convocationStatus: p.convocationStatus,
              selectionStatus: p.selectionStatus,
              zone: p.zone,
              x: p.x,
              y: p.y,
              sortOrder: p.sortOrder,
            ),
          ),
        ),
      );
    _events.clear();
    _scoreOperations.clear();
    _session = null;
    _formationCode = demoFormationCode;
    _compositionStatus = 'published';
    _compositionVersion = 1;
    _publishedAt = DateTime.utc(2026, 9, 27, 14, 43, 10);
    _compositionModifiedAt = _publishedAt!;
    _report = _Report();
    _nextId = 1;
    _changes.add(null);
  }

  String _newId(String prefix) {
    final serial = (_nextId++).toRadixString(16).padLeft(12, '0');
    return '00000000-0000-4000-8000-$serial';
  }

  DateTime _now() => _clock().toUtc();

  /// Horodatage strictement croissant : l'ordre des événements en dépend,
  /// comme `created_at` côté serveur.
  DateTime _eventTime() {
    var now = _now();
    if (!now.isAfter(_lastEventAt)) {
      now = _lastEventAt.add(const Duration(microseconds: 1));
    }
    return _lastEventAt = now;
  }

  Never _fail(String message, [String code = '22023']) {
    throw PostgrestException(message: message, code: code);
  }

  // ---------------------------------------------------------------------------
  // Lectures
  // ---------------------------------------------------------------------------

  Map<String, dynamic> liveSnapshot() {
    final session = _session;
    if (session == null) {
      // Composition publiée visible avant l'ouverture du Live : les
      // spectateurs voient la composition prévue.
      return {
        'match_id': demoMatchId,
        'state': null,
        'session_exists': false,
        'lineup': compositionSnapshot(),
        'pilot_active': false,
        'pilot_is_me': false,
      };
    }
    final trueElapsed = _trueElapsed(session);
    final pilotActive = _pilotActive(session);
    return {
      'match_id': demoMatchId,
      'state': session.state,
      'planned_duration_minutes': session.plannedDurationMinutes,
      'half': session.half,
      'elapsed_seconds': session.elapsedSeconds,
      'running_since': session.runningSince?.toIso8601String(),
      'score_as_grinta': session.scoreAsGrinta,
      'score_adverse': session.scoreAdverse,
      'started_at': session.startedAt?.toIso8601String(),
      'finished_at': session.finishedAt?.toIso8601String(),
      'exported': session.exported,
      'exported_at': null,
      'lineup_revision': session.lineupRevision,
      'true_elapsed_seconds': trueElapsed,
      'display_minute': trueElapsed ~/ 60 + 1,
      'session_exists': true,
      'lineup': compositionSnapshot(),
      'events': [for (final event in _sortedEvents()) _eventJson(event)],
      'substitute_counts': _substituteCounts(session),
      'pilot_active': pilotActive,
      'pilot_is_me': pilotActive && session.pilot == _PilotHolder.me,
    };
  }

  /// Même règle que `public.get_match_live_state` : un pilote compte tant que
  /// le match n'est pas terminé et qu'il a donné signe de vie depuis moins
  /// d'une minute. L'autre coach simulé reste actif jusqu'à ce que le menu
  /// le retire.
  bool _pilotActive(_Session session) {
    if (session.state == 'finished') return false;
    switch (session.pilot) {
      case _PilotHolder.nobody:
        return false;
      case _PilotHolder.other:
        return true;
      case _PilotHolder.me:
        final heartbeat = session.pilotHeartbeatAt;
        return heartbeat != null &&
            !heartbeat.isBefore(_now().subtract(_pilotExpiry));
    }
  }

  int _trueElapsed(_Session session) {
    var elapsed = session.elapsedSeconds;
    if (session.state == 'running' && session.runningSince != null) {
      final extra = _now().difference(session.runningSince!).inSeconds;
      elapsed += extra < 0 ? 0 : extra;
    }
    return elapsed;
  }

  int _currentMinute(_Session session) => _trueElapsed(session) ~/ 60 + 1;

  /// Ordre d'enregistrement ; à heure égale (même validation), ordre de
  /// création, les identifiants étant attribués dans l'ordre.
  List<_Event> _sortedEvents() => [..._events]..sort((a, b) {
        final byTime = a.createdAt.compareTo(b.createdAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });

  Map<String, dynamic> _eventJson(_Event event) {
    return {
      'id': event.id,
      'event_type': event.type,
      'minute': event.minute,
      'half': event.half,
      'scorer_participant_id': event.scorerId,
      'scorer_name': _eventName(event.scorerId),
      'assist_participant_id': event.assistId,
      'assist_name': _eventName(event.assistId),
      'score_as_grinta_after': event.scoreAsGrintaAfter,
      'score_adverse_after': event.scoreAdverseAfter,
      'player_in_participant_id': event.playerInId,
      'player_in_name': _eventName(event.playerInId),
      'player_out_participant_id': event.playerOutId,
      'player_out_name': _eventName(event.playerOutId),
      'is_opponent_own_goal': event.isOpponentOwnGoal,
      'created_at': event.createdAt.toIso8601String(),
    };
  }

  /// Nom affiché dans le journal : un invité ne porte que son prénom.
  String? _eventName(String? participantId) {
    final participant = participantId == null
        ? null
        : _participants[participantId];
    if (participant == null) return null;
    if (participant.isGuest) return '${participant.guestFirstName} (Invité)';
    return participant.displayName;
  }

  Map<String, int> _substituteCounts(_Session session) {
    final counts = <String, int>{};
    for (final participant in _participants.values) {
      if (!participant.isEligible &&
          participant.finalPresenceStatus == 'pending') {
        continue;
      }
      var times = session.startingZones?[participant.id] == 'bench' ? 1 : 0;
      times += _events
          .where(
            (e) => e.type == 'substitution' && e.playerOutId == participant.id,
          )
          .length;
      if (times > 0) counts[participant.id] = times;
    }
    return counts;
  }

  Map<String, dynamic> compositionSnapshot() {
    final placed = _participants.values.where((p) => p.zone != null).toList()
      ..sort(_compositionOrder);
    int count(String zone) => placed.where((p) => p.zone == zone).length;
    return {
      'match_id': demoMatchId,
      'formation_code': _formationCode,
      'status': _compositionStatus,
      'version': _compositionVersion,
      'has_unpublished_changes': false,
      'squad_size_exception_approved': false,
      'published_at': _publishedAt?.toIso8601String(),
      'last_modified_at': _compositionModifiedAt.toIso8601String(),
      'field_count': count('field'),
      'bench_count': count('bench'),
      'not_selected_count': count('not_selected'),
      'available_count': count('available'),
      'has_goalkeeper_warning':
          !placed.any((p) => p.zone == 'field' && p.isGoalkeeper),
      'entries': [
        for (final participant in placed)
          {
            ..._identityJson(participant),
            'zone': participant.zone,
            'x': participant.x,
            'y': participant.y,
            'slot_label': participant.slotLabel,
            'sort_order': participant.sortOrder,
            'availability_status': participant.availabilityStatus,
            'convocation_status': participant.convocationStatus,
            'selection_status': participant.selectionStatus,
          },
      ],
    };
  }

  static int _zoneRank(String? zone) => switch (zone) {
        'field' => 1,
        'bench' => 2,
        'available' => 3,
        _ => 4,
      };

  static int _compositionOrder(_Participant a, _Participant b) {
    final byZone = _zoneRank(a.zone).compareTo(_zoneRank(b.zone));
    if (byZone != 0) return byZone;
    final byOrder = a.sortOrder.compareTo(b.sortOrder);
    if (byOrder != 0) return byOrder;
    final byName = a.sortName.compareTo(b.sortName);
    if (byName != 0) return byName;
    return a.id.compareTo(b.id);
  }

  Map<String, dynamic> _identityJson(_Participant participant) => {
        'participant_id': participant.id,
        'season_player_id': participant.seasonPlayerId,
        'guest_player_id': participant.guestPlayerId,
        'display_name': participant.displayName,
        'last_initial': participant.lastInitial,
        'photo_url': null,
        'is_guest': participant.isGuest,
        'is_goalkeeper': participant.isGoalkeeper,
      };

  Map<String, dynamic> addPlayerOptions() {
    final session = _requireSession(
      'Open the live workspace before adding a player',
    );
    if (!const {'not_started', 'running', 'paused', 'halftime'}
        .contains(session.state)) {
      _fail('Players can only be added while the live session is open');
    }
    bool onSheet(_Participant? p) =>
        p != null && (p.zone == 'field' || p.zone == 'bench');

    final roster = _participants.values
        .where((p) => !p.isGuest && !onSheet(p))
        .toList()
      ..sort((a, b) {
        final byName = a.sortName.compareTo(b.sortName);
        return byName != 0 ? byName : a.seasonPlayerId!.compareTo(b.seasonPlayerId!);
      });

    final guests = <Map<String, dynamic>>[];
    for (final guest in demoGuests) {
      final participant = _guestParticipant(guest.guestPlayerId);
      if (onSheet(participant)) continue;
      guests.add({
        'participant_id': participant?.id,
        'guest_player_id': guest.guestPlayerId,
        'display_name': '${_joinName(guest.firstName, guest.lastName)} (Invité)',
        'last_initial': _initial(guest.lastName),
        'photo_url': null,
        'is_goalkeeper': guest.isGoalkeeper,
        'is_guest': true,
      });
    }
    for (final participant in _participants.values) {
      if (!participant.isGuest || !participant.createdInDemo) continue;
      if (onSheet(participant)) continue;
      guests.add({
        'participant_id': participant.id,
        'guest_player_id': participant.guestPlayerId,
        'display_name': participant.displayName,
        'last_initial': participant.lastInitial,
        'photo_url': null,
        'is_goalkeeper': participant.isGoalkeeper,
        'is_guest': true,
      });
    }
    guests.sort(
      (a, b) => (a['display_name'] as String)
          .toLowerCase()
          .compareTo((b['display_name'] as String).toLowerCase()),
    );

    return {
      'match_id': demoMatchId,
      'session_state': session.state,
      'roster': [
        for (final participant in roster)
          {
            'participant_id': participant.id,
            'season_player_id': participant.seasonPlayerId,
            'display_name': participant.displayName,
            'last_initial': participant.lastInitial,
            'photo_url': null,
            'is_goalkeeper': participant.isGoalkeeper,
            'is_guest': false,
          },
      ],
      'guests': guests,
    };
  }

  _Participant? _guestParticipant(String guestPlayerId) {
    for (final participant in _participants.values) {
      if (participant.guestPlayerId == guestPlayerId) return participant;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Écritures du Live
  // ---------------------------------------------------------------------------

  _Session _requireSession([String message = 'No live session for this match']) {
    final session = _session;
    if (session == null) _fail(message, 'P0002');
    return session;
  }

  Map<String, dynamic> _changed() {
    _changes.add(null);
    return liveSnapshot();
  }

  static int _clampDuration(int value) => value < 1 ? 1 : (value > 200 ? 200 : value);

  // ---------------------------------------------------------------------------
  // Place de pilote (`claim_match_live_pilot`, `take_over_match_live_pilot`,
  // `heartbeat_match_live_pilot`, `release_match_live_pilot`)
  // ---------------------------------------------------------------------------

  static const Duration _pilotExpiry = Duration(seconds: 60);

  /// Même garde que `private.require_match_live_pilot` : toute écriture du
  /// Live est refusée si ce téléphone n'est pas le pilote actif.
  void _requirePilot() {
    final session = _session;
    if (session == null) {
      _fail('Prends la place de pilote avant de modifier le Live.', '42501');
    }
    final heartbeat = session.pilotHeartbeatAt;
    if (session.pilot != _PilotHolder.me ||
        heartbeat == null ||
        heartbeat.isBefore(_now().subtract(_pilotExpiry))) {
      _fail('Tu ne pilotes pas ce Live.', '42501');
    }
  }

  void _takePilotPlace(_Session session) {
    session
      ..pilot = _PilotHolder.me
      ..pilotHeartbeatAt = _now();
  }

  /// Le premier coach qui ouvre « Piloter » crée l'espace de travail puis
  /// prend la place. Si un autre coach la tient encore, l'état est renvoyé
  /// tel quel : l'écran propose alors « Prendre la main ».
  Map<String, dynamic> claimPilot(int? plannedDurationMinutes) {
    final session = _session ?? _createWorkspace(plannedDurationMinutes);
    if (session.pilot == _PilotHolder.other && _pilotActive(session)) {
      return liveSnapshot();
    }
    _takePilotPlace(session);
    return _changed();
  }

  /// Prise de main volontaire, après confirmation dans l'écran.
  Map<String, dynamic> takeOverPilot() {
    final session = _session ?? _createWorkspace(null);
    _takePilotPlace(session);
    return _changed();
  }

  /// Signe de vie du pilote. Sans effet si la place a déjà expiré ou a été
  /// reprise par un autre coach.
  Map<String, dynamic> heartbeatPilot() {
    final session = _session;
    if (session != null &&
        session.pilot == _PilotHolder.me &&
        _pilotActive(session)) {
      session.pilotHeartbeatAt = _now();
    }
    return liveSnapshot();
  }

  /// Libère la place si ce téléphone la détient encore.
  Map<String, dynamic> releasePilot() {
    final session = _session;
    if (session == null || session.pilot != _PilotHolder.me) {
      return liveSnapshot();
    }
    session
      ..pilot = _PilotHolder.nobody
      ..pilotHeartbeatAt = null;
    return _changed();
  }

  /// Démo uniquement : un autre coach prend ou rend la place. Prendre la
  /// place retire immédiatement la main à ce téléphone, comme une prise de
  /// main depuis un second téléphone.
  bool get otherCoachPilots {
    final session = _session;
    return session != null &&
        session.pilot == _PilotHolder.other &&
        _pilotActive(session);
  }

  void simulateOtherCoachPilot({required bool active}) {
    if (active) {
      final session = _session ?? _createWorkspace(null);
      session
        ..pilot = _PilotHolder.other
        ..pilotHeartbeatAt = _now();
    } else {
      final session = _session;
      if (session == null || session.pilot != _PilotHolder.other) return;
      session
        ..pilot = _PilotHolder.nobody
        ..pilotHeartbeatAt = null;
    }
    _changes.add(null);
  }

  _Session _createWorkspace(int? plannedDurationMinutes) {
    final session = _Session(
      plannedDurationMinutes: _clampDuration(
        plannedDurationMinutes ?? demoPlannedDurationMinutes,
      ),
    );
    _session = session;
    _compositionModifiedAt = _now();
    return session;
  }

  Map<String, dynamic> openWorkspace(int? plannedDurationMinutes) {
    // La place de pilote garantit qu'une session existe déjà : c'est
    // claimPilot qui l'a créée.
    _requirePilot();
    final existing = _session!;
    if (existing.state != 'not_started') {
      return liveSnapshot();
    }
    existing.plannedDurationMinutes = _clampDuration(
      plannedDurationMinutes ?? existing.plannedDurationMinutes,
    );
    return _changed();
  }

  Map<String, dynamic> confirmStart() {
    _requirePilot();
    final session = _requireSession(
      'Open the live workspace before starting the match',
    );
    if (session.state != 'not_started') {
      _fail('The match has already been started');
    }
    final onSheet = _participants.values
        .where((p) => p.zone == 'field' || p.zone == 'bench');
    if (onSheet.any((p) => p.convocationStatus != 'convoked')) {
      _fail('Live lineup is stale after a convocation change');
    }
    final fieldCount = _participants.values.where((p) => p.zone == 'field').length;
    if (fieldCount > 11) {
      _fail('A lineup cannot contain more than 11 starters');
    }

    // Le coup d'envoi publie l'équipe réellement alignée.
    _compositionVersion += 1;
    _compositionStatus = 'published';
    _publishedAt = _now();
    _compositionModifiedAt = _publishedAt!;

    final now = _now();
    session
      ..state = 'running'
      ..startedAt = now
      ..runningSince = now
      ..elapsedSeconds = 0
      ..half = 1
      ..startingZones = {for (final p in onSheet) p.id: p.zone!}
      ..startingEntries = {for (final p in onSheet) p.id: p.snapshotEntry()}
      ..startingFormationCode = _formationCode;
    return _changed();
  }

  Map<String, dynamic> setClockState(String action) {
    _requirePilot();
    if (!const {'pause', 'resume', 'halftime', 'resume_second_half'}
        .contains(action)) {
      _fail('Invalid clock action');
    }
    final session = _requireSession();
    final now = _now();
    switch (action) {
      case 'pause':
        if (session.state != 'running') _fail('The clock is not running');
        session
          ..elapsedSeconds = _trueElapsed(session)
          ..state = 'paused'
          ..runningSince = null;
      case 'resume':
        if (session.state != 'paused') _fail('The clock is not paused');
        session
          ..state = 'running'
          ..runningSince = now;
      case 'halftime':
        if (!const {'running', 'paused'}.contains(session.state) ||
            session.half != 1) {
          _fail('Half-time is only available during the first half');
        }
        // La mi-temps cale le chrono sur la moitié du temps de jeu saisi.
        session
          ..state = 'halftime'
          ..elapsedSeconds = session.plannedDurationMinutes * 30
          ..runningSince = null;
      case 'resume_second_half':
        if (session.state != 'halftime') {
          _fail('The match is not at half-time');
        }
        session
          ..state = 'running'
          ..half = 2
          ..runningSince = now;
    }
    return _changed();
  }

  Map<String, dynamic> adjustScore({
    required String team,
    required int delta,
    required String operationId,
    String? scorerParticipantId,
  }) {
    _requirePilot();
    if (team != 'us' && team != 'them') _fail('Invalid team');
    if (delta != 1 && delta != -1) _fail('Score delta must be -1 or 1');
    // Même garde-fou que le registre serveur : un renvoi de la même
    // opération ne compte pas deux fois.
    if (!_scoreOperations.add(operationId)) return liveSnapshot();

    final session = _session;
    if (session == null ||
        !const {'running', 'paused', 'halftime'}.contains(session.state)) {
      _fail('The match is not currently live');
    }
    final minute = _currentMinute(session);

    if (team == 'us' && delta == 1) {
      if (scorerParticipantId != null &&
          !_participants.containsKey(scorerParticipantId)) {
        _fail('Unknown scorer for this match');
      }
      session.scoreAsGrinta = _clampScore(session.scoreAsGrinta + 1);
      _events.add(
        _Event(
          id: _newId('event'),
          type: 'goal_us',
          minute: minute,
          half: session.half,
          createdAt: _eventTime(),
          scorerId: scorerParticipantId,
          scoreAsGrintaAfter: session.scoreAsGrinta,
        ),
      );
    } else if (team == 'us') {
      _removeLatest('goal_us');
      session.scoreAsGrinta = _floorScore(session.scoreAsGrinta - 1);
    } else if (delta == 1) {
      session.scoreAdverse = _clampScore(session.scoreAdverse + 1);
      _events.add(
        _Event(
          id: _newId('event'),
          type: 'goal_them',
          minute: minute,
          half: session.half,
          createdAt: _eventTime(),
          scoreAdverseAfter: session.scoreAdverse,
        ),
      );
    } else {
      _removeLatest('goal_them');
      session.scoreAdverse = _floorScore(session.scoreAdverse - 1);
    }
    return _changed();
  }

  static int _clampScore(int value) => value > 99 ? 99 : value;
  static int _floorScore(int value) => value < 0 ? 0 : value;

  void _removeLatest(String type) {
    final matching = _sortedEvents().where((e) => e.type == type).toList();
    if (matching.isNotEmpty) _events.remove(matching.last);
  }

  Map<String, dynamic> addLivePlayers(List<Map<String, dynamic>> players) {
    _requirePilot();
    if (players.isEmpty || players.length > 30) {
      _fail('Players must be a non-empty JSON array of at most 30 items');
    }
    final session = _requireSession(
      'Open the live workspace before adding a player',
    );
    if (!const {'not_started', 'running', 'paused', 'halftime'}
        .contains(session.state)) {
      _fail('Players can only be added while the live session is open');
    }

    var benchOrder = _participants.values
            .where((p) => p.zone == 'bench')
            .fold<int>(-1, (max, p) => p.sortOrder > max ? p.sortOrder : max) +
        1;

    for (final item in players) {
      final kind = (item['kind'] ?? '').toString().trim().toLowerCase();
      final isGoalkeeper = item['is_goalkeeper'] == true;
      _Participant participant;

      if (kind == 'roster') {
        final seasonPlayerId = item['season_player_id']?.toString();
        if (seasonPlayerId == null || seasonPlayerId.isEmpty) {
          _fail('Roster player identifier is required');
        }
        final found = _participants.values
            .where((p) => p.seasonPlayerId == seasonPlayerId);
        if (found.isEmpty) {
          _fail('Roster player is not active for this match season');
        }
        participant = found.first;
      } else if (kind == 'guest' || kind == 'new_guest') {
        String guestPlayerId;
        String firstName;
        String? lastName;
        var guestIsGoalkeeper = isGoalkeeper;
        if (kind == 'guest') {
          final id = item['guest_player_id']?.toString();
          final known = demoGuests.where((g) => g.guestPlayerId == id);
          final existing = _participants.values
              .where((p) => p.isGuest && p.guestPlayerId == id);
          if (known.isEmpty && existing.isEmpty) {
            _fail('Guest player is unavailable or archived');
          }
          guestPlayerId = id!;
          if (known.isNotEmpty) {
            firstName = known.first.firstName;
            lastName = known.first.lastName;
            guestIsGoalkeeper = known.first.isGoalkeeper;
          } else {
            firstName = existing.first.guestFirstName!;
            lastName = existing.first.guestLastName;
            guestIsGoalkeeper = existing.first.isGoalkeeper;
          }
        } else {
          firstName = (item['first_name'] ?? '').toString().trim();
          final rawLast = (item['last_name'] ?? '').toString().trim();
          lastName = rawLast.isEmpty ? null : rawLast;
          if (firstName.isEmpty) _fail('Guest first name is required');
          if (firstName.length > 80 || (lastName?.length ?? 0) > 80) {
            _fail('Guest name cannot exceed 80 characters per field');
          }
          final sameGuest = demoGuests.where(
            (g) =>
                g.firstName.toLowerCase() == firstName.toLowerCase() &&
                (g.lastName ?? '').toLowerCase() ==
                    (lastName ?? '').toLowerCase() &&
                g.isGoalkeeper == isGoalkeeper,
          );
          guestPlayerId = sameGuest.isNotEmpty
              ? sameGuest.first.guestPlayerId
              : _newId('guest');
        }
        final existingGuest = _guestParticipant(guestPlayerId);
        if (existingGuest != null) {
          participant = existingGuest;
        } else {
          final id = _newId('participant');
          participant = _participants[id] = _Participant.guest(
            id: id,
            guestPlayerId: guestPlayerId,
            firstName: firstName,
            lastName: lastName,
            isGoalkeeper: guestIsGoalkeeper,
            createdInDemo: !demoGuests.any(
              (g) => g.guestPlayerId == guestPlayerId,
            ),
          );
        }
      } else {
        _fail('Player kind must be roster, guest or new_guest');
      }

      if (participant.zone == 'field' || participant.zone == 'bench') {
        _fail('A selected player is already present in the live lineup');
      }
      participant
        ..isEligible = true
        ..availabilityStatus =
            participant.isGuest ? 'not_applicable' : 'available'
        ..convocationStatus = 'convoked'
        ..selectionStatus = 'substitute'
        ..finalPresenceStatus = 'present'
        ..zone = 'bench'
        ..x = null
        ..y = null
        ..slotLabel = null
        ..sortOrder = benchOrder++;
    }

    _compositionModifiedAt = _now();
    session.lineupRevision += 1;
    return _changed();
  }

  Map<String, dynamic> saveLiveLineup({
    required List<Map<String, dynamic>> entries,
    required int expectedLineupRevision,
    List<({String playerIn, String playerOut})> substitutions = const [],
    String? formationCode,
  }) {
    _requirePilot();
    final session = _requireSession('Live session not found');
    if (expectedLineupRevision < 0) {
      _fail('Expected lineup revision is required');
    }
    if (session.lineupRevision != expectedLineupRevision) {
      _fail(
        'La composition Live a été modifiée par un autre coach. '
        'Recharge l\'état avant d\'enregistrer.',
        '40001',
      );
    }
    if (!const {'not_started', 'running', 'paused', 'halftime'}
        .contains(session.state)) {
      _fail('The lineup can only be edited while the live session is open');
    }

    final input = <String, _EntryInput>{};
    for (final item in entries) {
      final id = item['participant_id']?.toString();
      final zone = item['zone']?.toString();
      if (id == null || zone == null) _fail('Invalid lineup entry');
      if (input.containsKey(id)) _fail('A participant can appear only once');
      input[id] = _EntryInput(
        zone: zone,
        x: (item['x'] as num?)?.toDouble(),
        y: (item['y'] as num?)?.toDouble(),
        slotLabel: _blankToNull(item['slot_label']?.toString()),
        sortOrder: _nonNegative((item['sort_order'] as num?)?.toInt() ?? 0),
      );
    }
    if (input.values.any((e) => e.zone == 'available')) {
      _fail('Live lineup entries cannot use the available zone');
    }
    final expected = _participants.values
        .where((p) => p.isEligible || p.finalPresenceStatus != 'pending')
        .length;
    if (input.length != expected) {
      _fail('Every eligible participant must appear exactly once');
    }
    for (final entry in input.entries) {
      final value = entry.value;
      final invalid = !_participants.containsKey(entry.key) ||
          (value.zone == 'field' &&
              (value.x == null ||
                  value.y == null ||
                  value.x! < 0 ||
                  value.x! > 1 ||
                  value.y! < 0 ||
                  value.y! > 1)) ||
          (value.zone != 'field' && (value.x != null || value.y != null));
      if (invalid) _fail('Invalid lineup zone or coordinates');
    }
    if (input.values.where((e) => e.zone == 'field').length > 11) {
      _fail('A lineup cannot contain more than 11 starters');
    }

    if (substitutions.isNotEmpty) {
      if (substitutions.any((s) => s.playerIn == s.playerOut)) {
        _fail('Invalid substitution payload');
      }
      final involved = [
        for (final s in substitutions) ...[s.playerIn, s.playerOut],
      ];
      if (involved.toSet().length != involved.length) {
        _fail('A player cannot appear twice in the same substitution batch');
      }
      for (final s in substitutions) {
        final before = _participants[s.playerIn]?.zone ?? 'not_selected';
        final outBefore = _participants[s.playerOut]?.zone ?? 'not_selected';
        if (before == 'field' || outBefore != 'field') {
          _fail(
            'Substitution must bring in a non-field player and remove a field player',
          );
        }
        final after = input[s.playerIn]?.zone ?? 'not_selected';
        final outAfter = input[s.playerOut]?.zone ?? 'not_selected';
        if (after != 'field' || outAfter == 'field') {
          _fail('The incoming player must end up on the field');
        }
      }
    }

    // Avant le coup d'envoi, échanger un titulaire et un remplaçant est une
    // simple correction de composition ; ensuite, tout passage terrain/banc
    // doit être déclaré comme remplacement.
    if (session.state != 'not_started') {
      final declared = {
        for (final s in substitutions) ...{s.playerIn, s.playerOut},
      };
      for (final entry in input.entries) {
        final old = _participants[entry.key]!.zone;
        if (old == null) continue;
        if ((old == 'field') != (entry.value.zone == 'field') &&
            !declared.contains(entry.key)) {
          _fail('A field/bench change was not declared as a substitution');
        }
      }
    }

    for (final participant in _participants.values) {
      final value = input[participant.id];
      if (value == null) {
        participant.zone = null;
        continue;
      }
      participant
        ..zone = value.zone
        ..x = value.x
        ..y = value.y
        ..slotLabel = value.slotLabel
        ..sortOrder = value.sortOrder
        ..selectionStatus = switch (value.zone) {
          'field' => 'starter',
          'bench' => 'substitute',
          _ => 'not_selected',
        };
    }
    _compositionModifiedAt = _now();
    if (formationCode != null) _formationCode = formationCode;

    if (substitutions.isNotEmpty) {
      final minute = _currentMinute(session);
      // Comme côté serveur (une seule insertion, `now()` de la transaction),
      // les changements validés ensemble partagent la même heure : c'est ce
      // qui les regroupe en une salve.
      final validatedAt = _eventTime();
      for (final s in substitutions) {
        _events.add(
          _Event(
            id: _newId('event'),
            type: 'substitution',
            minute: minute,
            half: session.half,
            createdAt: validatedAt,
            playerInId: s.playerIn,
            playerOutId: s.playerOut,
          ),
        );
      }
    }

    session.lineupRevision += 1;
    return _changed();
  }

  Map<String, dynamic> changeLiveFormation({
    required String formationCode,
    required List<Map<String, dynamic>> entries,
    required int expectedLineupRevision,
  }) {
    _requirePilot();
    final code = formationCode.trim();
    if (code.isEmpty || code.length > 32) _fail('Invalid formation code');
    return saveLiveLineup(
      entries: entries,
      expectedLineupRevision: expectedLineupRevision,
      formationCode: code,
    );
  }

  Map<String, dynamic> deleteEvent(String eventId) {
    _requirePilot();
    final session = _session;
    if (session == null ||
        !const {'running', 'paused', 'halftime', 'finished'}
            .contains(session.state)) {
      _fail('The match is not currently live');
    }
    if (session.exported) _fail('This match has already been exported');
    final found = _events.where((e) => e.id == eventId);
    if (found.isEmpty) _fail('Event not found', 'P0002');
    final event = found.first;
    _events.remove(event);

    if (event.type == 'goal_us') {
      for (final later in _events) {
        if (later.type == 'goal_us' && later.createdAt.isAfter(event.createdAt)) {
          later.scoreAsGrintaAfter = (later.scoreAsGrintaAfter ?? 1) - 1;
        }
      }
      session.scoreAsGrinta = _floorScore(session.scoreAsGrinta - 1);
    } else if (event.type == 'goal_them') {
      for (final later in _events) {
        if (later.type == 'goal_them' &&
            later.createdAt.isAfter(event.createdAt)) {
          later.scoreAdverseAfter = (later.scoreAdverseAfter ?? 1) - 1;
        }
      }
      session.scoreAdverse = _floorScore(session.scoreAdverse - 1);
    }
    return _changed();
  }

  Map<String, dynamic> setEventScorer({
    required String eventId,
    String? scorerParticipantId,
    bool isOpponentOwnGoal = false,
    String? assistParticipantId,
  }) {
    _requirePilot();
    if (isOpponentOwnGoal && scorerParticipantId != null) {
      _fail('An own goal cannot be credited to a player');
    }
    if (assistParticipantId != null) {
      if (isOpponentOwnGoal) _fail('An own goal cannot have an assist');
      if (scorerParticipantId == null) _fail('An assist requires a scorer');
      if (assistParticipantId == scorerParticipantId) {
        _fail('The assist cannot be credited to the scorer');
      }
    }
    final session = _session;
    if (session == null ||
        !const {'running', 'paused', 'halftime', 'finished'}
            .contains(session.state)) {
      _fail('The match is not currently live');
    }
    if (session.exported) _fail('This match has already been exported');
    final found = _events.where((e) => e.id == eventId);
    if (found.isEmpty) _fail('Event not found', 'P0002');
    final event = found.first;
    if (event.type != 'goal_us') {
      _fail('Only an AS Grinta goal can have a scorer');
    }
    if (scorerParticipantId != null &&
        !_participants.containsKey(scorerParticipantId)) {
      _fail('Unknown scorer for this match');
    }
    if (assistParticipantId != null &&
        !_participants.containsKey(assistParticipantId)) {
      _fail('Unknown assist provider for this match');
    }
    event
      ..scorerId = scorerParticipantId
      ..isOpponentOwnGoal = isOpponentOwnGoal
      ..assistId = assistParticipantId;
    return _changed();
  }

  Map<String, dynamic> endMatch() {
    _requirePilot();
    final session = _session;
    if (session == null ||
        !const {'running', 'paused', 'halftime'}.contains(session.state)) {
      _fail('The match is not currently live');
    }
    session
      ..elapsedSeconds = _trueElapsed(session)
      ..state = 'finished'
      ..runningSince = null
      ..finishedAt = _now();
    return _changed();
  }

  Map<String, dynamic> reopen() {
    final session = _session;
    if (session == null || session.state != 'finished') {
      _fail('Only a finished (not yet exported) match can be reopened');
    }
    if (session.exported) {
      _fail('This match has already been exported and cannot be reopened');
    }
    session
      ..state = 'paused'
      ..finishedAt = null;
    return _changed();
  }

  Map<String, dynamic> restartSession() {
    _requirePilot();
    final session = _requireSession();
    if (session.exported) _fail('This match has already been exported');
    if (session.state == 'not_started') {
      _fail('The match has not been started yet');
    }

    // Annule les remplacements du plus récent au plus ancien pour retrouver
    // la composition du coup d'envoi.
    final substitutions = _sortedEvents()
        .where((e) => e.type == 'substitution')
        .toList()
        .reversed;
    for (final substitution in substitutions) {
      final playerIn = _participants[substitution.playerInId];
      final playerOut = _participants[substitution.playerOutId];
      if (playerIn == null || playerOut == null || playerIn.zone != 'field') {
        continue;
      }
      final x = playerIn.x;
      final y = playerIn.y;
      final slot = playerIn.slotLabel;
      final inOrder = playerIn.sortOrder;
      playerIn
        ..zone = 'bench'
        ..x = null
        ..y = null
        ..slotLabel = null
        ..sortOrder = playerOut.sortOrder;
      playerOut
        ..zone = 'field'
        ..x = x
        ..y = y
        ..slotLabel = slot
        ..sortOrder = inOrder;
    }
    _events.clear();
    session
      ..state = 'not_started'
      ..half = 1
      ..elapsedSeconds = 0
      ..runningSince = null
      ..scoreAsGrinta = 0
      ..scoreAdverse = 0
      ..startedAt = null
      ..finishedAt = null
      ..startingZones = null
      ..startingEntries = null
      ..startingFormationCode = null
      ..lineupRevision += 1;
    return _changed();
  }

  // ---------------------------------------------------------------------------
  // Compte rendu (écran affiché une fois le match terminé)
  // ---------------------------------------------------------------------------

  Map<String, dynamic> sportReport() {
    final session = _session;
    final report = _report;
    final validated = report.isValidated;
    final liveFinished = session?.state == 'finished';

    var scoreAsGrinta = report.scoreAsGrinta;
    var scoreAdverse = report.scoreAdverse;
    List<Map<String, dynamic>> goalActions = [
      for (final goal in report.goalActions) _storedGoalJson(goal),
    ];
    if (!validated && liveFinished && !(session?.exported ?? false)) {
      scoreAsGrinta = session!.scoreAsGrinta;
      scoreAdverse = session.scoreAdverse;
      goalActions = _liveGoalActions();
    }

    final eligible = _participants.values
        .where((p) => p.isEligible || p.finalPresenceStatus != 'pending')
        .toList();

    return {
      'match_id': demoMatchId,
      'opponent_name': demoOpponentName,
      'is_home': demoLocation == 'domicile',
      'kickoff_at': demoKickoffAt.toIso8601String(),
      'match_status': validated ? 'termine' : 'a_venir',
      'is_validated': validated,
      'version': report.version,
      'score_as_grinta': scoreAsGrinta,
      'score_adverse': scoreAdverse,
      'composition_version': _compositionVersion,
      'presence_state': validated ? 'confirmed' : 'pending',
      'vote_state': validated ? 'open' : 'unavailable',
      'validated_at': report.validatedAt?.toIso8601String(),
      'corrected_at': report.correctedAt?.toIso8601String(),
      'goal_actions': goalActions,
      'participants': [
        for (final participant in eligible) _finalParticipantJson(participant),
      ],
      'lineup': _reportLineup(),
      'is_correction': validated,
      'correction_closes_at': null,
      'is_editable': true,
      'live_state': session?.state,
      'live_exported': session?.exported ?? false,
      'live_finished': liveFinished,
      'add_player_options': {
        'roster': <Map<String, dynamic>>[],
        'guests': [
          for (final guest in demoGuests)
            if (_guestParticipant(guest.guestPlayerId) == null)
              {
                'guest_player_id': guest.guestPlayerId,
                'display_name': _joinName(guest.firstName, guest.lastName),
                'photo_url': null,
                'is_goalkeeper': guest.isGoalkeeper,
                'is_guest': true,
              },
        ],
      },
    };
  }

  Map<String, dynamic> _finalParticipantJson(_Participant participant) {
    final validated = _report.isValidated;
    final planned = participant.plannedZone;
    return {
      ..._identityJson(participant),
      'planned_zone': planned,
      'present': validated
          ? participant.finalPresenceStatus == 'present'
          : (planned == 'field' || planned == 'bench'),
      'final_presence_status': participant.finalPresenceStatus,
      'final_selection_status': validated
          ? participant.finalSelectionStatus
          : switch (planned) {
              'field' => 'starter',
              'bench' => 'substitute',
              _ => 'not_selected',
            },
      'goals': participant.finalGoals,
      'assists': participant.finalAssists,
      'clean_sheet': participant.finalCleanSheet,
      'is_motm': false,
    };
  }

  List<Map<String, dynamic>> _liveGoalActions() {
    final goals = _events
        .where((e) => e.type == 'goal_us' || e.type == 'goal_them')
        .toList()
      ..sort((a, b) {
        final byHalf = a.half.compareTo(b.half);
        if (byHalf != 0) return byHalf;
        final byMinute = a.minute.compareTo(b.minute);
        if (byMinute != 0) return byMinute;
        final byTime = a.createdAt.compareTo(b.createdAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
    return [
      for (var index = 0; index < goals.length; index += 1)
        _liveGoalJson(goals[index], index),
    ];
  }

  Map<String, dynamic> _liveGoalJson(_Event event, int ordinal) {
    final isUs = event.type == 'goal_us';
    final ownGoal = isUs && event.isOpponentOwnGoal;
    final scorer = isUs && !ownGoal ? event.scorerId : null;
    final assist = scorer == null ? null : event.assistId;
    return {
      'id': null,
      'ordinal': ordinal,
      'minute': event.minute.clamp(0, 90),
      'team_side': isUs ? 'as_grinta' : 'opponent',
      'scorer_participant_id': scorer,
      'scorer_name': _eventName(scorer),
      'assist_participant_id': assist,
      'assist_kind': !isUs || ownGoal
          ? 'none'
          : scorer == null
              ? 'unknown'
              : assist != null
                  ? 'player'
                  : 'unknown',
      'assist_name': _eventName(assist),
      'is_own_goal': ownGoal,
      'source': 'live',
      'source_live_event_id': event.id,
    };
  }

  Map<String, dynamic> _storedGoalJson(_StoredGoal goal) => {
        'id': goal.id,
        'ordinal': goal.ordinal,
        'minute': goal.minute,
        'team_side': goal.teamSide,
        'scorer_participant_id': goal.scorerId,
        'scorer_name': _eventName(goal.scorerId),
        'assist_participant_id': goal.assistId,
        'assist_kind': goal.assistKind,
        'assist_name': _eventName(goal.assistId),
        'is_own_goal': goal.isOwnGoal,
        'source': goal.source,
        'source_live_event_id': goal.sourceLiveEventId,
      };

  /// Reprend `private.match_sport_report_lineup` : avant validation, chaque
  /// joueur est remis à sa place du coup d'envoi ; après, à sa place finale.
  Map<String, dynamic> _reportLineup() {
    final session = _session;
    final validated = _report.isValidated;
    final startEntries = session?.startingEntries;
    final startZones = session?.startingZones;
    final liveStarted = session?.startedAt != null;
    final hasPlacement = _participants.values
        .any((p) => p.zone == 'field' || p.zone == 'bench');

    final rows = <({_Participant p, String zone, bool kickoff})>[];
    for (final participant in _participants.values) {
      if (!participant.isEligible &&
          participant.finalPresenceStatus == 'pending') {
        continue;
      }
      String zone;
      var kickoff = false;
      if (validated) {
        zone = participant.finalPresenceStatus == 'pending'
            ? 'bench'
            : participant.finalPresenceStatus != 'present'
                ? 'not_selected'
                : participant.finalSelectionStatus == 'starter'
                    ? 'field'
                    : 'bench';
      } else if (startEntries != null &&
          startEntries.containsKey(participant.id)) {
        zone = startEntries[participant.id]!['zone'] as String;
        kickoff = true;
      } else if (startZones != null && startZones.containsKey(participant.id)) {
        zone = startZones[participant.id]!;
      } else if (liveStarted) {
        zone = participant.zone == 'field' || participant.zone == 'bench'
            ? 'bench'
            : 'not_selected';
      } else if (hasPlacement) {
        zone = participant.zone ?? 'not_selected';
      } else {
        zone = 'bench';
      }
      rows.add((p: participant, zone: zone, kickoff: kickoff));
    }

    int currentSort(_Participant p) => p.zone == null ? 900 : p.sortOrder;
    rows.sort((a, b) {
      int rank(String zone) => zone == 'field' ? 1 : (zone == 'bench' ? 2 : 3);
      final byZone = rank(a.zone).compareTo(rank(b.zone));
      if (byZone != 0) return byZone;
      final bySort = currentSort(a.p).compareTo(currentSort(b.p));
      if (bySort != 0) return bySort;
      final byName = a.p.sortName.compareTo(b.p.sortName);
      return byName != 0 ? byName : a.p.id.compareTo(b.p.id);
    });

    final formation = validated
        ? _formationCode
        : (session?.startingFormationCode ?? _formationCode);

    return {
      'match_id': demoMatchId,
      'formation_code': formation,
      'status': 'draft',
      'version': 0,
      'has_unpublished_changes': true,
      'squad_size_exception_approved': false,
      'entries': [
        for (final row in rows) _reportEntryJson(row.p, row.zone, row.kickoff),
      ],
    };
  }

  Map<String, dynamic> _reportEntryJson(
    _Participant participant,
    String zone,
    bool kickoff,
  ) {
    final start =
        kickoff ? (_session?.startingEntries?[participant.id]) : null;
    final useFinal = _report.isValidated;
    double? x;
    double? y;
    if (zone == 'field') {
      if (useFinal && participant.finalX != null) {
        x = participant.finalX;
        y = participant.finalY;
      } else {
        x = (start?['x'] as double?) ?? participant.x;
        y = (start?['y'] as double?) ?? participant.y;
      }
    }
    return {
      ..._identityJson(participant),
      'zone': zone,
      'x': x,
      'y': y,
      'slot_label': start?['slot_label'] ?? participant.slotLabel,
      'sort_order': useFinal
          ? participant.finalSortOrder ?? participant.sortOrder
          : (start?['sort_order'] as int?) ??
              (participant.zone == null ? 900 : participant.sortOrder),
      'availability_status': participant.availabilityStatus,
      'convocation_status': participant.convocationStatus,
      'selection_status': participant.selectionStatus,
    };
  }

  Map<String, dynamic> submitReport({
    required int scoreAsGrinta,
    required int scoreAdverse,
    required List<Map<String, dynamic>> lineupEntries,
    required String formationCode,
    required List<Map<String, dynamic>> goalActions,
  }) {
    if (scoreAsGrinta < 0 || scoreAdverse < 0) {
      _fail('negative statistics');
    }
    final zones = {
      for (final entry in lineupEntries)
        entry['participant_id'].toString(): entry,
    };
    final goals = <_StoredGoal>[];
    for (var index = 0; index < goalActions.length; index += 1) {
      final goal = goalActions[index];
      goals.add(
        _StoredGoal(
          id: _newId('goal'),
          ordinal: index,
          minute: (goal['minute'] as num?)?.toInt(),
          teamSide: (goal['team_side'] ?? 'as_grinta').toString(),
          scorerId: goal['scorer_participant_id']?.toString(),
          assistId: goal['assist_participant_id']?.toString(),
          assistKind: (goal['assist_kind'] ?? 'unknown').toString(),
          isOwnGoal: goal['is_own_goal'] == true,
          source: (goal['source'] ?? 'manual').toString(),
          sourceLiveEventId: goal['source_live_event_id']?.toString(),
        ),
      );
    }

    for (final participant in _participants.values) {
      final entry = zones[participant.id];
      final zone = entry?['zone']?.toString();
      participant
        ..finalPresenceStatus =
            zone == 'field' || zone == 'bench' ? 'present' : 'absent'
        ..finalSelectionStatus = switch (zone) {
          'field' => 'starter',
          'bench' => 'substitute',
          _ => 'not_selected',
        }
        ..finalX = (entry?['x'] as num?)?.toDouble()
        ..finalY = (entry?['y'] as num?)?.toDouble()
        ..finalSortOrder = (entry?['sort_order'] as num?)?.toInt()
        ..finalGoals = goals
            .where((g) => g.teamSide == 'as_grinta' && g.scorerId == participant.id)
            .length
        ..finalAssists =
            goals.where((g) => g.assistId == participant.id).length
        ..finalCleanSheet = participant.isGoalkeeper &&
            zone == 'field' &&
            scoreAdverse == 0;
    }

    final now = _now();
    _report
      ..scoreAsGrinta = scoreAsGrinta
      ..scoreAdverse = scoreAdverse
      ..goalActions = goals
      ..version += 1
      ..validatedAt ??= now
      ..correctedAt = _report.version > 1 ? now : null;
    _formationCode = formationCode;
    _session?.exported = true;
    _changes.add(null);
    return sportReport();
  }

  Map<String, dynamic> attachReportPlayer({
    String? seasonPlayerId,
    String? guestPlayerId,
  }) {
    if (guestPlayerId != null) {
      final guest = demoGuests.where((g) => g.guestPlayerId == guestPlayerId);
      if (guest.isEmpty) _fail('Guest player is unavailable or archived');
      if (_guestParticipant(guestPlayerId) == null) {
        final id = _newId('participant');
        _participants[id] = _Participant.guest(
          id: id,
          guestPlayerId: guestPlayerId,
          firstName: guest.first.firstName,
          lastName: guest.first.lastName,
          isGoalkeeper: guest.first.isGoalkeeper,
        )
          ..isEligible = true
          ..availabilityStatus = 'not_applicable'
          ..convocationStatus = 'convoked'
          ..selectionStatus = 'substitute';
      }
    }
    return sportReport();
  }

  List<Map<String, dynamic>> storedGoalActions() => [
        for (final goal in _report.goalActions) _storedGoalJson(goal),
      ];
}

String _joinName(String first, String? last) =>
    [first.trim(), if (last != null && last.trim().isNotEmpty) last.trim()]
        .join(' ');

String? _initial(String? lastName) {
  final text = lastName?.trim() ?? '';
  return text.isEmpty ? null : text.substring(0, 1).toUpperCase();
}

String? _blankToNull(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? null : text;
}

int _nonNegative(int value) => value < 0 ? 0 : value;

/// Qui tient la place de pilote (`match_live_sessions.pilot_*` en production).
/// La démo ne connaît qu'un téléphone : celui-ci, ou un autre coach simulé
/// depuis le menu du bandeau.
enum _PilotHolder { nobody, me, other }

class _Session {
  _Session({required this.plannedDurationMinutes});

  _PilotHolder pilot = _PilotHolder.nobody;
  DateTime? pilotHeartbeatAt;
  String state = 'not_started';
  int plannedDurationMinutes;
  int half = 1;
  int elapsedSeconds = 0;
  DateTime? runningSince;
  int scoreAsGrinta = 0;
  int scoreAdverse = 0;
  DateTime? startedAt;
  DateTime? finishedAt;
  bool exported = false;
  int lineupRevision = 0;
  Map<String, String>? startingZones;
  Map<String, Map<String, dynamic>>? startingEntries;
  String? startingFormationCode;
}

class _Participant {
  _Participant({
    required this.id,
    required this.displayName,
    required this.isGoalkeeper,
    required this.availabilityStatus,
    required this.convocationStatus,
    required this.selectionStatus,
    required this.sortOrder,
    this.seasonPlayerId,
    this.guestPlayerId,
    this.guestFirstName,
    this.guestLastName,
    this.lastInitial,
    this.zone,
    this.x,
    this.y,
    this.createdInDemo = false,
  }) : _initialZone = zone;

  factory _Participant.guest({
    required String id,
    required String guestPlayerId,
    required String firstName,
    String? lastName,
    bool isGoalkeeper = false,
    bool createdInDemo = false,
  }) {
    return _Participant(
      id: id,
      guestPlayerId: guestPlayerId,
      guestFirstName: firstName,
      guestLastName: lastName,
      displayName: '${_joinName(firstName, lastName)} (Invité)',
      lastInitial: _initial(lastName),
      isGoalkeeper: isGoalkeeper,
      availabilityStatus: 'not_applicable',
      convocationStatus: 'convoked',
      selectionStatus: 'substitute',
      sortOrder: 0,
      createdInDemo: createdInDemo,
    )..finalPresenceStatus = 'present';
  }

  final String id;
  final String? seasonPlayerId;
  final String? guestPlayerId;
  final String? guestFirstName;
  final String? guestLastName;
  final String displayName;
  final String? lastInitial;
  final bool isGoalkeeper;
  final bool createdInDemo;
  final String? _initialZone;

  bool isEligible = true;
  String availabilityStatus;
  String convocationStatus;
  String selectionStatus;
  String finalPresenceStatus = 'pending';
  String finalSelectionStatus = 'not_selected';
  int finalGoals = 0;
  int finalAssists = 0;
  bool finalCleanSheet = false;
  double? finalX;
  double? finalY;
  int? finalSortOrder;

  String? zone;
  double? x;
  double? y;
  String? slotLabel;
  int sortOrder;

  bool get isGuest => guestPlayerId != null;
  String get sortName => (guestFirstName ?? displayName).toLowerCase();

  /// Zone de la dernière composition publiée (avant tout changement Live).
  String get plannedZone => switch (_initialZone) {
        'field' || 'bench' || 'not_selected' => _initialZone!,
        _ => switch (selectionStatus) {
            'starter' => 'field',
            'substitute' => 'bench',
            'not_selected' => 'not_selected',
            _ => 'available',
          },
      };

  Map<String, dynamic> snapshotEntry() => {
        'zone': zone,
        'x': x,
        'y': y,
        'slot_label': slotLabel,
        'sort_order': sortOrder,
      };
}

class _EntryInput {
  const _EntryInput({
    required this.zone,
    required this.sortOrder,
    this.x,
    this.y,
    this.slotLabel,
  });

  final String zone;
  final double? x;
  final double? y;
  final String? slotLabel;
  final int sortOrder;
}

class _Event {
  _Event({
    required this.id,
    required this.type,
    required this.minute,
    required this.half,
    required this.createdAt,
    this.scorerId,
    this.playerInId,
    this.playerOutId,
    this.scoreAsGrintaAfter,
    this.scoreAdverseAfter,
  });

  final String id;
  final String type;
  final int minute;
  final int half;
  final DateTime createdAt;
  final String? playerInId;
  final String? playerOutId;
  String? scorerId;
  String? assistId;
  bool isOpponentOwnGoal = false;
  int? scoreAsGrintaAfter;
  int? scoreAdverseAfter;
}

class _StoredGoal {
  const _StoredGoal({
    required this.id,
    required this.ordinal,
    required this.teamSide,
    required this.assistKind,
    required this.isOwnGoal,
    required this.source,
    this.minute,
    this.scorerId,
    this.assistId,
    this.sourceLiveEventId,
  });

  final String id;
  final int ordinal;
  final int? minute;
  final String teamSide;
  final String? scorerId;
  final String? assistId;
  final String assistKind;
  final bool isOwnGoal;
  final String source;
  final String? sourceLiveEventId;
}

class _Report {
  bool get isValidated => version > 0;
  int version = 0;
  int scoreAsGrinta = 0;
  int scoreAdverse = 0;
  List<_StoredGoal> goalActions = const [];
  DateTime? validatedAt;
  DateTime? correctedAt;
}
