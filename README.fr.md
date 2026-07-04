<p align="center">
  <img src="Assets/AVT_helper_readme_icon.png" alt="icône de l’application AVT_helper" width="128">
</p>

<h1 align="center">AVT_helper</h1>

<p align="center">
  <strong>Langue :</strong> <a href="README.md">EN</a> | <a href="README.ru.md">RU</a> | FR
</p>

<p align="center">
  <strong>conversion de sous-titres et tableaux DOCX de rôles pour macOS</strong>
</p>

<p align="center">
  <a href="https://github.com/boundlessend/AVT_helper/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/boundlessend/AVT_helper/actions/workflows/ci.yml/badge.svg"></a>
  <a href="https://github.com/boundlessend/AVT_helper/releases"><img alt="Latest release" src="https://img.shields.io/github/v/release/boundlessend/AVT_helper?color=2563eb"></a>
  <img alt="macOS" src="https://img.shields.io/badge/macOS-14%2B-111827">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5.9-f05138">
  <img alt="licence" src="https://img.shields.io/badge/license-BSD--3--Clause-2563eb">
</p>

`AVT_helper` est une application macOS native pour convertir des sous-titres et créer des tableaux DOCX de dialogues.

L’application importe `ASS`, `SSA`, `SRT`, `VTT` et `SRP`, exporte `ASS`, `SRT`, `VTT` et `DOCX`, et peut créer des DOCX de répartition des rôles avec les couleurs de surlignage Word.

L'encodage des fichiers d'entrée (UTF-8, UTF-16, Windows-1251) est détecté automatiquement, et le traitement s'exécute en arrière-plan pour garder la fenêtre réactive sur les gros fichiers.

## Installation

1. Téléchargez `AVT_helper.dmg` depuis la dernière release.
2. Ouvrez `AVT_helper.dmg`.
3. Glissez `AVT_helper.app` dans `Applications`.
4. Lancez `AVT_helper.app` depuis `Applications`.

Si macOS bloque le premier lancement, exécutez :

```bash
sudo xattr -rd com.apple.quarantine "/Applications/AVT_helper.app"
```

Ouvrez ensuite l’application à nouveau.

## Utilisation

> L'application démarre en russe par défaut. Changez la langue dans `Réglages` -> `Langue de l'application`.

1. Cliquez sur `Open subtitles` ou glissez un fichier de sous-titres dans la zone d’entrée.
2. Choisissez le dossier de sortie.
3. Sélectionnez un ou plusieurs formats : `ASS`, `SRT`, `VTT` ou `DOCX`.
4. Cliquez sur `Start`.
5. Pour créer un DOCX de répartition des rôles, chargez un fichier avec rôles et cliquez sur `Make role assignment`.

## DOCX

Les fichiers DOCX contiennent le nom du fichier, la liste des rôles détectés, un tableau timing/rôle/dialogue et les statistiques par rôle. Les DOCX de répartition listent aussi les voix assignées au-dessus du tableau et surlignent les rôles assignés avec les couleurs Word sélectionnées.

## Licence

BSD 3-Clause. Voir [LICENSE](LICENSE).
