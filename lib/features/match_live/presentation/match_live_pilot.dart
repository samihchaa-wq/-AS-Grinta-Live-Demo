import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Qui pilote le Live d'un match.
///
/// Une seule personne à la fois peut piloter ; tous les autres suivent le
/// match en spectateur. Dans la démo, cet état reste sur le téléphone (un
/// menu permet de simuler un autre coach). Dans l'application, il sera tenu
/// par le serveur : place libérée quand le pilote quitte le mode match ou
/// ne donne plus signe de vie, et actions refusées à qui ne pilote pas.
enum LivePilot {
  /// Personne ne pilote : un coach peut prendre la place.
  nobody,

  /// Ce téléphone pilote.
  me,

  /// Un autre coach pilote.
  other,
}

final livePilotProvider = StateProvider.family<LivePilot, String>(
  (ref, matchId) => LivePilot.nobody,
);

/// Le coach a choisi de suivre le match en spectateur alors que personne ne
/// pilote : l'écran de choix ne lui est plus proposé.
final liveSpectatorChoiceProvider = StateProvider.family<bool, String>(
  (ref, matchId) => false,
);
