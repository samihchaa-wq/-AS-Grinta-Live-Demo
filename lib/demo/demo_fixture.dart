/// Données figées du match de démonstration.
///
/// Copie en lecture seule du match AS Grinta – Toulouse Métropole du
/// 28/09/2026 : effectif enregistré, composition publiée (4-2-1-3) et
/// positions exactes des joueurs. Les photos de profil ne sont pas reprises :
/// elles sont privées et la démo n'accède jamais à Supabase.
library;

const demoMatchId = '3867833c-b2be-4acd-83d5-f62a68e65ca0';
const demoSeasonId = 'demo-season';
const demoOpponentName = 'Toulouse Métropole';
const demoLocation = 'exterieur';
const demoMatchType = 'amical';
const demoAddress =
    'Stade Pierre Cahuzac - 29 rue de Rabastens - 31500 Toulouse';
const demoPlannedDurationMinutes = 90;
const demoFormationCode = '4-2-1-3';
final demoKickoffAt = DateTime.utc(2026, 9, 28, 19);

class DemoParticipant {
  const DemoParticipant({
    required this.participantId,
    required this.seasonPlayerId,
    required this.displayName,
    required this.lastInitial,
    required this.zone,
    required this.sortOrder,
    required this.availabilityStatus,
    required this.convocationStatus,
    required this.selectionStatus,
    this.isGoalkeeper = false,
    this.x,
    this.y,
  });

  final String participantId;
  final String seasonPlayerId;
  final String displayName;
  final String lastInitial;
  final String zone;
  final int sortOrder;
  final String availabilityStatus;
  final String convocationStatus;
  final String selectionStatus;
  final bool isGoalkeeper;
  final double? x;
  final double? y;
}

DemoParticipant _starter(
  String participantId,
  String seasonPlayerId,
  String name,
  String initial,
  int order,
  double x,
  double y, {
  bool goalkeeper = false,
}) =>
    DemoParticipant(
      participantId: participantId,
      seasonPlayerId: seasonPlayerId,
      displayName: name,
      lastInitial: initial,
      zone: 'field',
      sortOrder: order,
      x: x,
      y: y,
      isGoalkeeper: goalkeeper,
      availabilityStatus: 'available',
      convocationStatus: 'convoked',
      selectionStatus: 'starter',
    );

DemoParticipant _substitute(
  String participantId,
  String seasonPlayerId,
  String name,
  String initial,
  int order,
) =>
    DemoParticipant(
      participantId: participantId,
      seasonPlayerId: seasonPlayerId,
      displayName: name,
      lastInitial: initial,
      zone: 'bench',
      sortOrder: order,
      availabilityStatus: 'available',
      convocationStatus: 'convoked',
      selectionStatus: 'substitute',
    );

DemoParticipant _notSelected(
  String participantId,
  String seasonPlayerId,
  String name,
  String initial,
  int order, {
  required String availability,
  required String convocation,
}) =>
    DemoParticipant(
      participantId: participantId,
      seasonPlayerId: seasonPlayerId,
      displayName: name,
      lastInitial: initial,
      zone: 'not_selected',
      sortOrder: order,
      availabilityStatus: availability,
      convocationStatus: convocation,
      selectionStatus: 'not_selected',
    );

/// Participants du match, dans l'ordre de la composition publiée.
final demoParticipants = <DemoParticipant>[
  _starter('a699d053-420f-4ab2-b15f-27048f68d565',
      '6ebab582-8751-491e-9be9-f994a3cf59d0', 'Francois', 'D', 0, .12, .22),
  _starter('d63fd982-bfa7-47a1-bd70-179eaaf11524',
      '5c3d9b87-b616-4d70-bc84-4dc344593cbe', 'Poulain', 'M', 1, .68, .70),
  _starter('58eb6b3a-534b-4994-9d77-af97fd7e1de2',
      'aad5b9ad-62e8-4eaa-913c-0f8acccb1828', 'Julien', 'C', 2, .32, .70),
  _starter('87d00114-ebf6-4ff1-ba0e-86b98d0d4cce',
      '479c6a8c-b5c8-435e-8ef7-ad6b5588e1ce', 'Alyoun', 'C', 4, .10, .65),
  _starter('0fb20cd1-0dbb-4c9d-80d7-fcfef896775f',
      '00fee3d8-9911-4606-9845-7d466cc8c7ed', 'Romain', 'S', 5, .70, .50),
  _starter('d7343bc0-cc79-43f5-b1a4-a2aa649ac5c1',
      '8695a831-e7b0-43e0-999d-76e0f41cfa6f', 'Samih', 'C', 6, .50, .85,
      goalkeeper: true),
  _starter('3df9e913-86d3-4dfc-bcc2-d55990e16f1c',
      '648a1485-1838-498d-b255-1049d07bcffa', 'Samuel', 'G', 7, .90, .65),
  _starter('1b4b42af-1460-4930-806e-d1abb6f6efac',
      'ab22336e-ce33-467e-8405-06254599468c', 'Alban', 'R', 8, .50, .27),
  _starter('abe33132-6417-43f9-a67f-3325bd542878',
      'abbb7e72-4c5c-4499-b662-1cf062b6d019', 'Allan', 'B', 10, .88, .22),
  _starter('0158cea0-2f08-43aa-a54a-47d35fa4b232',
      '3dae29d0-6a5d-49f0-92bf-9d9121b89744', 'Flo', 'A', 12, .30, .50),
  _starter('56b8af56-8848-4a60-a84f-05cd29e2c0d1',
      '91816d29-e80a-4a13-a6d5-b0df8f62b93c', 'Pipo', 'C', 13, .50, .08),
  _substitute('a4e345f9-bfd0-44ea-bae6-c2b7106a6aae',
      'c1a76171-bd82-4a8c-8908-f002e2842bcb', 'Amine', 'S', 0),
  _substitute('e41da6cf-245c-4057-be2f-059de3330cba',
      '301ec133-f579-4a21-966b-78e80ff77a7a', 'Lulu', 'B', 1),
  _substitute('44b104b2-2a5c-4740-9936-714420f273eb',
      'ac636fc5-05d3-45cf-a184-716a75806b55', 'Steph', 'F', 2),
  _notSelected('1ff69517-ab57-490e-91a6-7ed52d0397b1',
      '79bc0b63-c02c-4c2e-b93e-a8d46bbfeb74', 'Simon', 'R', 14,
      availability: 'available', convocation: 'not_convoked'),
  _notSelected('8f47d18a-51ac-49b6-8158-923bbfc34cfc',
      '1265847d-af05-49d0-b570-6498038952f0', 'Nicolas', 'B', 15,
      availability: 'no_response', convocation: 'not_applicable'),
  _notSelected('019b6d8f-566b-45d4-a8db-019dcf5202d7',
      '97dc77b0-9e21-4c83-95a0-9c0fad9da1a0', 'Hakim', 'C', 16,
      availability: 'absent', convocation: 'not_applicable'),
  _notSelected('4bfb0c30-61af-49e9-8700-786245d7a8a4',
      'bca1600f-81bd-416f-9718-a92be6c91722', 'Aki', 'S', 17,
      availability: 'absent', convocation: 'not_applicable'),
  _notSelected('ecd0e735-4e9a-47d8-8146-d172278b33aa',
      'feab7573-9f7b-4922-8d7c-c4f487ebcbd7', 'Julio', 'V', 18,
      availability: 'absent', convocation: 'not_applicable'),
];

class DemoGuest {
  const DemoGuest({
    required this.guestPlayerId,
    required this.firstName,
    this.lastName,
    this.isGoalkeeper = false,
  });

  final String guestPlayerId;
  final String firstName;
  final String? lastName;
  final bool isGoalkeeper;
}

/// Invités réutilisables proposés par « Ajouter un joueur ».
const demoGuests = <DemoGuest>[
  DemoGuest(
    guestPlayerId: '9d42abee-2926-4726-b06d-3ab1340d041e',
    firstName: 'Roman',
  ),
  DemoGuest(
    guestPlayerId: '2e26c5f6-241d-47b5-af11-25e6e1901b80',
    firstName: 'Roman',
    lastName: 'Yassinski',
  ),
];
