#!/bin/sh
# Copie le jeu (même fichier que l'appli Android) dans le projet iOS.
# Usage : ./scripts/sync-web.sh /chemin/vers/EcranBleuAndroid/app/src/main/assets
set -e
SRC=${1:-../EcranBleuAndroid/app/src/main/assets}
DST="$(dirname "$0")/../BlueScreen/www"
mkdir -p "$DST/music"
cp "$SRC/index.html" "$SRC/cyberlogic_logo.png" "$DST/"
cp "$SRC"/music/*.mp3 "$DST/music/"
echo "Jeu copié dans $DST"
