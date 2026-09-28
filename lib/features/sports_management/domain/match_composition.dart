enum MatchCompositionZone {
  available,
  field,
  bench,
  notSelected;

  String get wireValue => switch (this) {
        MatchCompositionZone.available => 'available',
        MatchCompositionZone.field => 'field',
        MatchCompositionZone.bench => 'bench',
        MatchCompositionZone.notSelected => 'not_selected',
      };
}

class MatchCompositionEntry {
  const MatchCompositionEntry({
    required this.participantId,
    required this.seasonPlayerId,
    required this.displayName,
    required this.isGoalkeeper,
    required this.zone,
    this.lastInitial,
    this.guestPlayerId,
    this.isGuest = false,
    this.x,
    this.y,
    this.slotLabel,
    this.photoUrl,
    this.goals = 0,
    this.assists = 0,
    this.isMotm = false,
    this.isVacant = false,
    required this.sortOrder,
    this.availabilityStatus = 'available',
    this.convocationStatus = 'convoked',
    this.selectionStatus = 'starter',
  });

  final String participantId;
  final String seasonPlayerId;
  final String? guestPlayerId;
  final String displayName;
  final String? lastInitial;
  final bool isGuest;
  final bool isGoalkeeper;
  final MatchCompositionZone zone;
  final double? x;
  final double? y;
  final String? slotLabel;
  final String? photoUrl;
  final int goals;
  final int assists;
  final bool isMotm;
  final bool isVacant;
  final int sortOrder;
  final String availabilityStatus;
  final String convocationStatus;
  final String selectionStatus;

  bool get canBeSelected => convocationStatus == 'convoked';

  MatchCompositionEntry copyWith({
    String? slotLabel,
    String? photoUrl,
    int? goals,
    int? assists,
    bool? isMotm,
    int? sortOrder,
  }) {
    return MatchCompositionEntry(
      participantId: participantId,
      seasonPlayerId: seasonPlayerId,
      guestPlayerId: guestPlayerId,
      displayName: displayName,
      lastInitial: lastInitial,
      isGuest: isGuest,
      isGoalkeeper: isGoalkeeper,
      zone: zone,
      x: x,
      y: y,
      slotLabel: slotLabel ?? this.slotLabel,
      photoUrl: photoUrl ?? this.photoUrl,
      goals: goals ?? this.goals,
      assists: assists ?? this.assists,
      isMotm: isMotm ?? this.isMotm,
      isVacant: isVacant,
      sortOrder: sortOrder ?? this.sortOrder,
      availabilityStatus: availabilityStatus,
      convocationStatus: convocationStatus,
      selectionStatus: selectionStatus,
    );
  }

  MatchCompositionEntry moveTo(
    MatchCompositionZone nextZone, {
    double? x,
    double? y,
    int? sortOrder,
  }) {
    final isField = nextZone == MatchCompositionZone.field;
    return MatchCompositionEntry(
      participantId: participantId,
      seasonPlayerId: seasonPlayerId,
      guestPlayerId: guestPlayerId,
      displayName: displayName,
      lastInitial: lastInitial,
      isGuest: isGuest,
      isGoalkeeper: isGoalkeeper,
      zone: nextZone,
      x: isField ? x : null,
      y: isField ? y : null,
      slotLabel: slotLabel,
      photoUrl: photoUrl,
      goals: goals,
      assists: assists,
      isMotm: isMotm,
      isVacant: isVacant,
      sortOrder: sortOrder ?? this.sortOrder,
      availabilityStatus: availabilityStatus,
      convocationStatus: convocationStatus,
      selectionStatus: switch (nextZone) {
        MatchCompositionZone.field => 'starter',
        MatchCompositionZone.bench => 'substitute',
        MatchCompositionZone.notSelected => 'not_selected',
        MatchCompositionZone.available => 'undecided',
      },
    );
  }

  Map<String, dynamic> toRpcJson() => {
        'participant_id': participantId,
        'zone': zone.wireValue,
        'x': zone == MatchCompositionZone.field ? x : null,
        'y': zone == MatchCompositionZone.field ? y : null,
        'slot_label': slotLabel,
        'sort_order': sortOrder,
      };
}

class MatchComposition {
  const MatchComposition({
    required this.matchId,
    required this.formationCode,
    required this.status,
    required this.version,
    required this.hasUnpublishedChanges,
    required this.squadSizeExceptionApproved,
    required this.entries,
  });

  final String matchId;
  final String? formationCode;
  final String status;
  final int version;
  final bool hasUnpublishedChanges;
  final bool squadSizeExceptionApproved;
  final List<MatchCompositionEntry> entries;

  List<MatchCompositionEntry> entriesFor(MatchCompositionZone zone) {
    final result = entries.where((entry) => entry.zone == zone).toList();
    result.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      if (byOrder != 0) return byOrder;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return result;
  }

  MatchComposition copyWith({
    String? formationCode,
    List<MatchCompositionEntry>? entries,
  }) {
    return MatchComposition(
      matchId: matchId,
      formationCode: formationCode ?? this.formationCode,
      status: status,
      version: version,
      hasUnpublishedChanges: hasUnpublishedChanges,
      squadSizeExceptionApproved: squadSizeExceptionApproved,
      entries: entries ?? this.entries,
    );
  }
}
