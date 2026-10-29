# Passages 🚋

Appli iPhone (SwiftUI) des prochains passages **en temps réel** en Île-de-France :
bus, tram, métro, RER, autour de ta position.

- **À proximité** : les 3 arrêts les plus proches avec leurs passages en direct (rafraîchis toutes les 30 s), puis les autres arrêts autour de toi.
- **Favoris** : tes arrêts favoris avec leurs passages en direct, réordonnables.
- **Carte** : tous les arrêts sur la carte Apple, touche un arrêt pour voir ses passages.
- **Rechercher** : par nom d'arrêt, de gare ou de commune.
- Couleurs officielles des lignes, itinéraire à pied dans Plans, mode sombre.

Données : [PRIM – Île-de-France Mobilités](https://prim.iledefrance-mobilites.fr) (temps réel) et open data IDFM (arrêts, lignes, licence ODbL).

---

## 1. Mettre le projet sur GitHub

1. Crée un dépôt vide sur github.com (public ou privé).
2. Envoie **tout** le contenu de ce dossier, y compris le dossier caché `.github/`.
   - Avec Git :
     ```bash
     git init && git add . && git commit -m "Passages"
     git branch -M main
     git remote add origin https://github.com/TON-PSEUDO/passages.git
     git push -u origin main
     ```
   - Avec le site web (« Add file → Upload files ») : sur Mac, le Finder cache `.github`.
     Appuie sur **Cmd + Maj + .** pour afficher les fichiers cachés avant de glisser le dossier.
     Sinon, crée le fichier à la main sur GitHub : `.github/workflows/build.yml` et colle son contenu.

## 2. Récupérer le .ipa

GitHub compile l'appli tout seul sur un Mac (onglet **Actions**, ~5–8 min).
Ensuite, le fichier `Passages.ipa` apparaît dans **Releases → latest**.
Il est aussi joint à chaque exécution dans l'onglet Actions.

L'appli est recompilée automatiquement à chaque modification et chaque lundi, pour mettre à jour les arrêts.

## 3. Installer avec iLoader

Ouvre iLoader, branche l'iPhone, choisis **Install IPA** puis `Passages.ipa`.

> Avec un identifiant Apple gratuit, l'appli doit être réinstallée (ou rafraîchie avec SideStore) tous les 7 jours.

## 4. Clé API (gratuite)

Au premier lancement, l'appli demande une clé :

1. Crée un compte sur <https://prim.iledefrance-mobilites.fr>.
2. Va dans **Mon compte → Mes jetons d'authentification → Générer**.
3. Copie la clé et colle-la dans l'appli. Elle reste uniquement sur ton iPhone.

---

### Structure

```
project.yml                 # projet Xcode (généré par XcodeGen)
scripts/build_data.py       # télécharge arrêts + lignes IDFM -> JSON embarqué
Passages/                   # code SwiftUI (iOS 17+)
.github/workflows/build.yml # compilation + .ipa + release
```

Pour compiler sur un Mac : `brew install xcodegen && python3 scripts/build_data.py && xcodegen generate && open Passages.xcodeproj`.
