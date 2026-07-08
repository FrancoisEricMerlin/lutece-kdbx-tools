#!/usr/bin/env bash
# redmine.sh — appelle l'API REST Redmine en récupérant la clé API depuis un coffre KeePassXC.
#
# Usage :
#   redmine.sh <chemin_api> [args curl supplémentaires...]
#
# Exemples :
#   redmine.sh "projects.json?limit=100"
#   redmine.sh "issues.json?project_id=extendcomm&status_id=open&sort=updated_on:desc"
#   redmine.sh "issues/33002.json?include=journals"
#   redmine.sh "issues.json" -X POST -H "Content-Type: application/json" -d '{"issue":{...}}'
#
# Variables d'environnement (avec valeurs par défaut) :
#   KDBX_PASS       (REQUISE) passphrase du coffre — DOIT être exportée AVANT de lancer `claude`
#   REDMINE_KDBX    chemin du coffre           [~/.config/claude.kdbx]
#   REDMINE_ENTRY   nom de l'entrée dans le coffre [Redmine]
#   REDMINE_URL     URL de base du bugtracker  [https://dev.lutece.paris.fr/bugtracker]
#
# Notes :
#   - PAS de --noproxy : l'accès à dev.lutece.paris.fr DOIT passer par le proxy.
#   - La clé API n'est jamais affichée ni écrite sur disque.

set -euo pipefail

KDBX="${REDMINE_KDBX:-$HOME/.config/claude.kdbx}"
ENTRY="${REDMINE_ENTRY:-Redmine}"
BASE="${REDMINE_URL:-https://dev.lutece.paris.fr/bugtracker}"

if [ $# -lt 1 ]; then
  echo "Usage: redmine.sh <chemin_api> [args curl...]" >&2
  echo "  ex: redmine.sh 'projects.json?limit=100'" >&2
  exit 2
fi

if [ -z "${KDBX_PASS:-}" ]; then
  echo "ERREUR: KDBX_PASS non définie. Exporte-la AVANT de lancer claude :" >&2
  echo "  read -rs KDBX_PASS && export KDBX_PASS && claude --continue" >&2
  exit 1
fi

if [ ! -f "$KDBX" ]; then
  echo "ERREUR: coffre introuvable : $KDBX" >&2
  exit 1
fi

KEY=$(printf '%s' "$KDBX_PASS" | keepassxc-cli show -s -a Password -q "$KDBX" "$ENTRY")
if [ -z "$KEY" ]; then
  echo "ERREUR: clé API vide (mauvaise passphrase, ou entrée '$ENTRY' absente/sans mot de passe)." >&2
  exit 1
fi

path="$1"; shift
exec curl -ks --max-time 30 -H "X-Redmine-API-Key: $KEY" "$@" "$BASE/$path"
