# Mizwala — Application de prière pour Marrakech

Application Flutter (Android + iOS) affichant les horaires de prière calculés
localement pour Marrakech, sans API ni connexion réseau.

## ✨ Fonctionnalités

- Cadran astrolabe animé (aiguille 24h, couronne des prières)
- Calcul 100% local (formule astronomique, aucune API)
- Notifications locales avant chaque prière (délai configurable)
- Sélection de date manuelle + retour automatique
- Typographie Cinzel / Cormorant Garamond

## 🚀 Obtenir l'APK (sans installer Flutter)

### Via GitHub Actions

1. Créer un repo GitHub public ou privé
2. Pousser ce dossier :
   ```bash
   git init
   git add .
   git commit -m "Initial commit"
   git remote add origin https://github.com/VOTRE_USERNAME/mizwala.git
   git push -u origin main
   ```
3. Aller sur `github.com/VOTRE_USERNAME/mizwala` → onglet **Actions**
4. Le build se lance automatiquement → télécharger l'APK depuis **Artifacts**

> Le premier build prend ~5 minutes (téléchargement du SDK Flutter sur les
> serveurs de GitHub).

## 🛠 Développement local (si Flutter installé)

```bash
flutter pub get
dart run flutter_launcher_icons
dart run flutter_native_splash:create
flutter run
```

## 📦 Build manuel

```bash
flutter build apk --release
# APK disponible dans build/app/outputs/flutter-apk/app-release.apk
```

## 🎨 Direction artistique

| Couleur     | Hex       | Usage                    |
|-------------|-----------|--------------------------|
| Indigo nuit | `#10141B` | Fond général             |
| Laiton      | `#C9A24B` | Accents, cadran, prières |
| Ocre rouge  | `#A3402C` | Contre-aiguille, points  |
| Parchemin   | `#ECE3D0` | Textes principaux        |

## ⚠️ Note sur la précision

Les angles Fajr 19° / Icha 17° et la méthode malikite pour l'Asr donnent
des horaires généralement fiables à quelques minutes près pour Marrakech,
mais ne remplacent pas une source officielle (Ministère des Habous, Muwaqqit)
pour un usage religieux réel.
