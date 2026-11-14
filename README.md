# Carte Fortnite

Lit tes replays Fortnite (lecture seule, rien n'est modifié dans le jeu) et te montre sur une carte : ton trajet, tes coffres, ton atterrissage,
les coffres ouverts par les autres et la chute des autres joueurs. Un petit compteur de coffres peut aussi s'afficher par-dessus le jeu.

**Outil de fan, non affilié à Epic Games.** « Fortnite » est une marque d'Epic Games.

## Installer

1. Va dans [Releases](../../releases/latest) et télécharge **CarteFortnite.exe**.
2. Mets-le où tu veux (le Bureau, par exemple) et double-clique dessus. Rien à installer : le .NET est déjà dedans.
3. Dans Fortnite : Paramètres > Jeu, active l'enregistrement des replays, puis joue une partie jusqu'au bout.

> Windows SmartScreen ou ton antivirus peuvent se méfier d'un programme récent et non signé (« Windows a protégé votre ordinateur » → *Informations complémentaires* → *Exécuter quand même*).
> Le code est entièrement public dans ce dépôt et l'exe est compilé par GitHub (voir `.github/workflows/publier.yml`). Tu peux comparer son empreinte SHA-256 avec le fichier `CarteFortnite.exe.sha256` de la Release.

## Mises à jour

Au lancement, le programme regarde s'il existe une version plus récente sur GitHub. Si oui, il te le propose (**Mettre à jour** / **Plus tard**) : il télécharge le nouvel exe, vérifie son empreinte SHA-256, se remplace et se relance. Rien n'est jamais mis à jour sans ton accord, ni pendant que Fortnite est ouvert.

## Règle anti-triche (importante)

- Ouvre Carte Fortnite **avant** de lancer Fortnite, et ne le relance pas pendant que le jeu tourne. Quand une ancienne version a été lancée pendant le jeu, Easy Anti-Cheat a fait planter Fortnite.
- Si Fortnite est déjà ouvert, le programme refuse de démarrer et te le dit.
- Le programme ne lance **aucun autre programme** : la lecture des replays tourne dans un fil du même programme, et le compteur est une fenêtre du même programme. Il n'interroge pas la liste des programmes de ton PC.
- La carte s'affiche dans le panneau avec le moteur web de Windows (WebView2, le même qu'Edge). Ce moteur n'est démarré que quand tu ouvres la carte **et** que Fortnite est fermé ; il s'arrête quand tu cliques sur « Retour », et la carte se ferme toute seule si Fortnite s'ouvre.
- Epic ne publie pas de liste d'outils autorisés. On ne peut pas garantir que l'anti-triche ne réagira jamais. En cas de doute, n'affiche pas le compteur : la carte seule suffit (elle ne s'ouvre que jeu fermé).

## Dans le panneau

- **Ouvrir la carte de mes parties** : lit tes replays puis affiche la carte (depuis ton PC : rien n'est envoyé sur internet). Si l'affichage intégré n'est pas possible, la carte s'ouvre dans ton navigateur.
- **Compteur par-dessus le jeu** : une petite plaque (un coffre + le nombre total), toujours au premier plan, en plein écran fenêtré. La souris passe à travers, le jeu garde le focus. Réglages : taille, déplacement, compter ou non les coffres tombés/cassés (estimation), coffres de l'équipe, mini-résumé de fin de partie. À la fin d'une partie, un « +N » vert montre les coffres de la partie.
- **Coffres déjà ouverts avant l'outil** : un nombre de départ, ajouté au total partout (panneau, compteur, carte).
- **Équipe** : tes coffres + ceux de tes équipiers. Les tiens sont exacts ; ceux des équipiers sont une *estimation* (le replay ne dit « début de fouille » que pour toi, donc on compte les coffres ouverts tout près d'un équipier), et c'est un minimum.

## Les mots

- « au total » : nombre de départ + tous les coffres ouverts dans toutes tes parties lues. « dernière partie » : la plus récente.
- Un coffre = un conteneur qui lâche une arme. Les caisses de munitions ne sont pas comptées.
- Les « coffres tombés / cassés » sont une estimation (sol cassé sous un coffre, coffre cassé à la pioche) ; la case du panneau permet de les retirer du total.

## Si la carte affiche 0 partout

- « Aucun replay trouvé » : Fortnite n'a rien enregistré chez toi. Les replays sont dans `%LOCALAPPDATA%\FortniteGame\Saved\Demos` (colle ce chemin dans l'explorateur de fichiers).
- Si ce dossier est vide : active les replays dans Fortnite et joue une partie jusqu'au bout.
- Ça ne marche que sur PC : Fortnite sur PS5, Xbox ou Switch ne stocke aucun replay sur le PC.

## Où sont mes données ?

Tout est dans `%LOCALAPPDATA%\CarteFortnite` (rien n'est écrit à côté de l'exe, rien n'est envoyé sur internet). Pour tout effacer : ferme le programme et supprime ce dossier.
Le programme n'écrit qu'un seul fichier à côté de lui, `CarteFortnite.exe.old`, le temps d'une mise à jour.

Le replay est enregistré de **ton** point de vue : les adversaires ne sont suivis que tant qu'ils sont près de toi, donc leur zone de chute est approximative.

## Pour les développeurs

- `app/` : l'application (WPF, .NET 10). `app/Lecteur.cs` lit les replays avec [FortniteReplayReader](https://github.com/xNocken/replay-reader).
- `carte.html`, `ressources/` : la page de la carte, embarquée dans l'exe.
- Compiler : `dotnet publish app/CarteFortnite.csproj -c Release` (Windows).
- **Publier une version** : onglet *Actions* > *Publier une version* > *Run workflow* (numéro, ex. `1.1.0`), ou `git tag v1.1.0 && git push origin v1.1.0`. Le workflow `publier.yml` compile l'exe et crée la Release avec `CarteFortnite.exe` et `CarteFortnite.exe.sha256` ; les programmes déjà installés proposent alors la mise à jour au prochain lancement.
