#!/usr/bin/env bash
# fork.sh — crée (si possible) et clone un fork GitHub d'un dépôt lutece-platform
# dans ~/.lutece-forks/, avec les remotes origin=fork et upstream=dépôt d'origine.
#
# Le token est extrait du coffre KeePassXC à la volée et n'est JAMAIS affiché ni
# passé en argument (invisible dans `ps`). Le répertoire des forks est créé s'il
# n'existe pas.
#
# Usage :
#   fork.sh <owner/repo | URL> [--dir <chemin>] [--no-clone]
#
# Options :
#   --dir <chemin>   répertoire cible du clone      [$FORKS_DIR/<repo>]
#   --no-clone       créer/vérifier le fork sans cloner
#   -h, --help       afficher cette aide
#
# Variables d'environnement :
#   KDBX_PASS   (REQUISE) passphrase du coffre — exportée AVANT `claude`
#   PR_KDBX     chemin du coffre                 [~/.config/claude.kdbx]
#   GH_ENTRY    entrée du token GitHub           [Github]
#   FORKS_DIR   racine des forks                 [~/.lutece-forks]

set -euo pipefail

KDBX="${PR_KDBX:-$HOME/.config/claude.kdbx}"
GH_ENTRY_SET="${GH_ENTRY:+1}"   # 1 si l'utilisateur a fixé GH_ENTRY explicitement
GH_ENTRY="${GH_ENTRY:-}"
FORKS_DIR="${FORKS_DIR:-$HOME/.lutece-forks}"

target=""; dir=""; do_clone=1
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) dir="$2"; shift 2;;
    --no-clone) do_clone=0; shift;;
    -h|--help) sed -n '2,20p' "$0"; exit 0;;
    -*) echo "Option inconnue: $1" >&2; exit 2;;
    *) target="$1"; shift;;
  esac
done

# --- Prérequis ---
[ -n "$target" ] || { echo "ERREUR: dépôt upstream requis (owner/repo ou URL)." >&2; exit 2; }
if [ -z "${KDBX_PASS:-}" ]; then
  echo "ERREUR: KDBX_PASS non définie. Exporte-la AVANT de lancer claude :" >&2
  echo "  read -rs KDBX_PASS && export KDBX_PASS && claude --continue" >&2
  exit 1
fi
[ -f "$KDBX" ] || { echo "ERREUR: coffre introuvable : $KDBX" >&2; exit 1; }

# Normaliser vers owner/repo (accepte https://host/owner/repo(.git) ou git@host:owner/repo(.git))
slug=$(printf '%s' "$target" | sed -E 's#^[a-z]+://[^/]+/##; s#^[^@]*@[^:]+:##; s#\.git$##')
repo=$(printf '%s' "$slug" | cut -d/ -f2)
case "$slug" in */*) : ;; *) echo "ERREUR: format attendu owner/repo, reçu: $target" >&2; exit 2;; esac
[ -n "$repo" ] || { echo "ERREUR: nom de dépôt introuvable dans: $target" >&2; exit 2; }

# Entrée GitHub : respecte un GH_ENTRY explicite ; sinon préfère GithubClassic
# (classic PAT, seul capable de forker une orga tierce), repli sur Github (fine-grained).
if [ -z "$GH_ENTRY_SET" ]; then
  if printf '%s' "$KDBX_PASS" | keepassxc-cli show -q "$KDBX" GithubClassic >/dev/null 2>&1; then
    GH_ENTRY="GithubClassic"
  else
    GH_ENTRY="Github"
  fi
fi
echo ">> Entrée token GitHub : $GH_ENTRY"
TOKEN=$(printf '%s' "$KDBX_PASS" | keepassxc-cli show -s -a Password -q "$KDBX" "$GH_ENTRY")
[ -n "$TOKEN" ] || { echo "ERREUR: token GitHub vide (entrée '$GH_ENTRY')." >&2; exit 1; }

me=$(GH_TOKEN="$TOKEN" gh api user -q .login)
fork_slug="$me/$repo"

# --- Fork : existant ? sinon on tente de le créer ---
if GH_TOKEN="$TOKEN" gh repo view "$fork_slug" --json nameWithOwner >/dev/null 2>&1; then
  echo ">> Fork déjà présent : $fork_slug"
else
  echo ">> Création du fork de $slug ..."
  err=$(mktemp)
  if ! GH_TOKEN="$TOKEN" gh repo fork "$slug" --clone=false 2>"$err"; then
    echo "ERREUR: création du fork impossible :" >&2
    sed 's/^/   /' "$err" >&2; rm -f "$err"
    echo "   → Un fine-grained PAT ne peut pas forker un dépôt d'orga tierce." >&2
    echo "     Forkez via l'UI, puis relancez : https://github.com/$slug/fork" >&2
    exit 1
  fi
  rm -f "$err"
fi

[ "$do_clone" = 1 ] || { echo ">> --no-clone : fin (fork prêt)."; exit 0; }

# --- Répertoire cible : $FORKS_DIR/<catégorie>/<repo> ---
# Catégorie = 1er segment après "lutece-" (ex. lutece-extends-module-... -> extends).
# Sans --dir et sans catégorie détectable, on retombe sur $FORKS_DIR/<repo>.
category=""
case "$repo" in
  lutece-*-*) category=$(printf '%s' "$repo" | sed -E 's/^lutece-([^-]+)-.*/\1/');;
esac
if [ -n "$dir" ]; then
  dest="$dir"
elif [ -n "$category" ]; then
  dest="$FORKS_DIR/$category/$repo"
else
  dest="$FORKS_DIR/$repo"
fi
mkdir -p "$(dirname "$dest")"
export GIT_ASKPASS_TOKEN="$TOKEN"
cred='!f(){ echo username=x-access-token; echo "password=$GIT_ASKPASS_TOKEN"; };f'

if [ -d "$dest/.git" ]; then
  echo ">> Clone déjà présent : $dest"
else
  echo ">> Clone du fork dans $dest ..."
  git -c credential.helper="$cred" clone "https://github.com/$fork_slug.git" "$dest"
fi

# --- Remotes : origin = fork, upstream = dépôt d'origine ---
if git -C "$dest" remote get-url upstream >/dev/null 2>&1; then
  git -C "$dest" remote set-url upstream "https://github.com/$slug.git"
else
  git -C "$dest" remote add upstream "https://github.com/$slug.git"
fi

echo ">> Remotes :"
git -C "$dest" remote -v | sed 's/^/   /'
echo ">> OK : $dest"
