# AS Grinta · démo d'entraînement du Live

Copie du module Live de l'application AS Grinta, pour que le coach puisse
s'entraîner sans rien toucher.

- **Aucune connexion à Supabase.** Les écrans du Live sont copiés à
  l'identique depuis l'application (`lib/features`, `lib/core`), mais les
  données passent par un faux serveur local (`lib/demo/demo_backend.dart`) qui
  reproduit les règles des fonctions SQL du Live. La page interdit en plus tout
  appel réseau vers Supabase (Content-Security-Policy de `web/index.html`).
- **Rien n'est enregistré.** Tout repart de zéro au rechargement de la page ou
  avec le bouton « Recommencer » du bandeau jaune.
- **Place de pilote** : comme dans l'application, un seul téléphone pilote à
  la fois et c'est le faux serveur qui tient la place (libérée en quittant
  « Piloter », en fin de match, ou après une minute sans signe de vie). Le
  menu « Un autre coach pilote » du bandeau jaune simule un second téléphone.
- **Joueurs** : effectif et composition publiée du match AS Grinta –
  Toulouse Métropole du 28/09/2026 (`lib/demo/demo_fixture.dart`), sans les
  photos de profil (privées).

Mettre à jour les écrans : recopier les fichiers depuis l'application, sans les
modifier. Seuls `lib/main.dart` et `lib/demo/` sont propres à la démo.
