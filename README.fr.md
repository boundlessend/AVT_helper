![icône AVT_helper](Assets/AVT_helper_icon.png)

Langue : [EN](README.md) | [RU](README.ru.md) | FR

# AVT_helper

[![CI](https://github.com/boundlessend/AVT_helper/actions/workflows/ci.yml/badge.svg)](https://github.com/boundlessend/AVT_helper/actions/workflows/ci.yml)
[![Release DMG](https://github.com/boundlessend/AVT_helper/actions/workflows/release.yml/badge.svg)](https://github.com/boundlessend/AVT_helper/actions/workflows/release.yml)
![macOS](https://img.shields.io/badge/macOS-13%2B-blue)
![License](https://img.shields.io/badge/License-BSD--3--Clause-green)

`AVT_helper` est une application macOS native pour convertir des sous-titres et créer des tableaux DOCX de dialogues.

L’application importe `ASS`, `SSA`, `SRT`, `VTT` et `SRP`, exporte `ASS`, `SRT`, `VTT` et `DOCX`, et peut créer des DOCX de répartition des rôles avec les couleurs de surlignage Word.

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

1. Cliquez sur `Open subtitles` ou glissez un fichier de sous-titres dans la zone d’entrée.
2. Choisissez le dossier de sortie.
3. Sélectionnez un ou plusieurs formats : `ASS`, `SRT`, `VTT` ou `DOCX`.
4. Cliquez sur `Start`.
5. Pour créer un DOCX de répartition des rôles, chargez un fichier avec rôles et cliquez sur `Make role assignment`.

## DOCX

Les fichiers DOCX contiennent le nom du fichier, la liste des rôles détectés, un tableau timing/rôle/dialogue et les statistiques par rôle. Les DOCX de répartition listent aussi les voix assignées au-dessus du tableau et surlignent les rôles assignés avec les couleurs Word sélectionnées.

## Licence

BSD 3-Clause. Voir [LICENSE](LICENSE).
