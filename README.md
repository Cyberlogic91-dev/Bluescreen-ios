# BlueScreen pour iPhone — guide CYBERLOGIC

Ce dossier contient l'appli iOS native de BlueScreen : le même jeu que sur Android, dans une WKWebView,
avec le même pont natif (voix, appareil photo, vibrations, partage, connexion Discord, **partie Wi-Fi en hôte**).

> ⚠️ Ce projet n'a pas pu être compilé ici (il faut macOS et Xcode). Le code a été écrit pour iOS 16+
> et la partie JavaScript du pont a été testée en simulation ; prévoir une première compilation sur Mac
> (ou via GitHub Actions, voir plus bas) pour corriger d'éventuelles erreurs de compilation.

## 1. Compiler

Sur un Mac avec Xcode 15 ou plus :

```sh
brew install xcodegen
./scripts/sync-web.sh ../EcranBleuAndroid/app/src/main/assets   # copie le jeu à jour
xcodegen generate                                                # crée BlueScreen.xcodeproj
open BlueScreen.xcodeproj
```

Dans `project.yml` (ou dans Xcode > Signing), remplace `XXXXXXXXXX` par ton **Team ID** Apple.
Branche un iPhone et lance : le jeu tourne directement sur ton téléphone (avec un compte développeur
gratuit, l'appli expire au bout de 7 jours ; avec le compte payant, 1 an).

**Sans Mac :** le fichier `.github/workflows/release.yml` compile et envoie l'appli vers App Store Connect
depuis GitHub (machines macOS fournies par GitHub). Il faut créer une clé API App Store Connect et
renseigner les secrets indiqués en tête du fichier.

## 2. Ce qui est identique à Android

| Fonction | iOS |
|---|---|
| Jeu complet, 2D/3D, mode histoire, musique | WKWebView, fichiers embarqués (hors ligne) |
| Voix des personnages | AVSpeechSynthesizer (voix française du téléphone) |
| Photo pour l'avatar | appareil photo frontal (UIImagePickerController) |
| Partie Wi-Fi en hôte | serveur HTTP local (Network.framework), port 8642 |
| Connexion Discord | Safari puis retour par `fr.cyberlogic.ecranbleu:/oauth` |
| Vibrations, partage du Défi du jour | retour haptique, feuille de partage iOS |

iOS demandera l'autorisation **Réseau local** au premier lancement d'une partie Wi-Fi, et **Appareil photo**
à la première photo.

## 3. Distribuer hors App Store (Union européenne)

Dans tous les cas : **Apple Developer Program** (99 $/an) et **notarisation** de chaque version par Apple
(contrôle de sécurité, pas de revue éditoriale). Depuis le 1er octobre 2026, les conditions UE sont dans
l'annexe 14 du contrat développeur ; la commission de 5 % (« Core Technology Commission ») ne porte que
sur les **ventes numériques** : BlueScreen étant gratuit et sans achat intégré, il n'y a rien à reverser.

### Option A — boutique alternative AltStore PAL (accessible à un indépendant)
1. App Store Connect : accepter les conditions UE, créer l'app `fr.cyberlogic.bluescreen`.
2. S'enregistrer comme développeur auprès d'AltStore, puis autoriser la boutique dans App Store Connect
   (Utilisateurs et accès > Intégrations > Marketplaces).
3. Envoyer la version (Xcode ou GitHub Actions) puis demander la **notarisation** (et non la revue App Store).
4. Télécharger le paquet de distribution (manifest.json, signature, .ipa) et le déposer tel quel sur
   `https://jeu.cyberlogic.fr/ios/…` (`.ipa` servi en `application/octet-stream`).
5. Compléter `distribution/source.json` (Apple ID de l'app, URL du manifest, taille) et le publier.
6. Les joueurs : installer AltStore PAL puis toucher le lien `altstore://source?url=…/source.json`
   (page prête : `distribution/installer.html`).

### Option B — depuis ton propre site (« Web Distribution »)
Apple n'autorise ce mode qu'aux développeurs qui remplissent **un** de ces critères : note Dun & Bradstreet
« Low Risk » ou « Below Average Risk », société cotée, financement par un fonds reconnu, lettre de crédit
de 1 M$, audit financier certifié, ou 2 ans d'ancienneté + une app à plus d'un million d'installations.
CYBERLOGIC a un numéro DUNS : la piste la plus réaliste est de demander sa **note D&B (Global Business
Ranking)** et, si elle est dans la bonne catégorie, de déposer la demande dans App Store Connect.
Ensuite : enregistrer le domaine cyberlogic.fr dans App Store Connect, notariser, télécharger les fichiers
signés et les héberger sur le site. Les joueurs autorisent une fois les installations depuis le Web
dans les Réglages (iOS 17.5 ou plus).

### En attendant : la version web
En ligne sur **https://jeu.cyberlogic.fr** (GitHub Pages, dossier `docs/`, domaine via un CNAME OVH). Le dossier `BlueScreen-web` (livré à côté) s'installe sur l'écran d'accueil de n'importe quel iPhone,
sans Apple, sans frais, partout dans le monde. Seule limite : un iPhone ne peut pas **héberger** une partie
Wi-Fi en version web (il peut rejoindre une partie créée par un téléphone Android ou par l'appli iOS).

## 4. Version gratuite actuelle (sans compte payant)
- **Web** : https://jeu.cyberlogic.fr (proposition d'installation automatique iPhone / Android).
- **AltStore Classic** : source `https://jeu.cyberlogic.fr/altstore/source.json`
  (lien : `altstore://source?url=https://jeu.cyberlogic.fr/altstore/source.json`), mise à jour automatique à chaque compilation.
