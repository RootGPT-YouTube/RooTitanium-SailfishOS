#!/bin/bash
# Sostituisce /home/rootitanium sul device con il bundle Qt 6.12 / Chromium 140
# (scratch/pkg-staging-qt612-<arch>/bundle). Solo per collaudo: launcher,
# .desktop e .service restano quelli dell'RPM installato.
# Backup dell'originale: va fatto PRIMA, a mano (es. ~/rootitanium-2.2-backup).
#   ARCH=aarch64 DEV=utente@indirizzo-del-telefono packaging/qt612/installa-poco.sh
set -euo pipefail
R=$(cd "$(dirname "$0")/../.." && pwd)
ARCH=${ARCH:-aarch64}
DEV=${DEV:?imposta DEV=utente@indirizzo-del-telefono}
S=$R/scratch/pkg-staging-qt612-$ARCH/bundle
[ -x "$S/webengine-smoke" ] || { echo "bundle non trovato: $S" >&2; exit 1; }
ssh "$DEV" 'test -d /home/defaultuser/rootitanium-2.2-backup' || { echo "manca il backup sul device" >&2; exit 1; }
# app ferma: scan /proc/*/exe (il kill per nome fallisce in silenzio)
ssh "$DEV" 'for p in /proc/[0-9]*; do case "$(readlink $p/exe 2>/dev/null)" in /home/rootitanium/*) kill -9 ${p#/proc/} 2>/dev/null;; esac; done; true'
tar -C "$S" -cf - . | ssh "$DEV" 'sudo rm -rf /home/rootitanium.new && sudo mkdir /home/rootitanium.new && sudo tar -C /home/rootitanium.new -xf - --no-same-owner'
ssh "$DEV" 'sudo cp -a /home/rootitanium/qt.conf /home/rootitanium.new/qt.conf \
  && sudo chown -R root:root /home/rootitanium.new \
  && sudo mv /home/rootitanium /home/rootitanium.old \
  && sudo mv /home/rootitanium.new /home/rootitanium \
  && sudo rm -rf /home/rootitanium.old \
  && du -sh /home/rootitanium && ls /home/rootitanium/lib | grep -c "WebEngineCore.so.6.140"'
