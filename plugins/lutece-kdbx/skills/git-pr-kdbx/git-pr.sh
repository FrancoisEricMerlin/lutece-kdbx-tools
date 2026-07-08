#!/usr/bin/env bash
# git-pr.sh — crée une Pull Request (GitHub) ou Merge Request (GitLab) en récupérant
# le token depuis un coffre KeePassXC. Détecte la plateforme via le remote de push.
#
# Modèle FORK (simple utilisateur) : on POUSSE la branche sur ton fork (remote `origin`
# par défaut) et on OUVRE la PR/MR vers l'upstream (remote `upstream` s'il existe).
#
# Le token n'est JAMAIS affiché, ni passé en argument (invisible dans `ps`) :
#  - injecté dans GH_TOKEN / GITLAB_TOKEN de l'outil (gh/glab) ;
#  - pour le push HTTPS, via un credential helper éphémère lisant l'env.
#
# Usage :
#   git-pr.sh [options] [-- args supplémentaires passés à gh/glab]
#
# Convention lutece-platform : titre et branche = "LUT-<ticket>[-v<version>] : <description>"
# (le <ticket> est l'ID du ticket Redmine du bugtracker).
#
# Options :
#   -C <dir>          répertoire du dépôt git         [répertoire courant]
#   -t, --title <s>   titre / description             (requis sauf --fill)
#   -b, --body <s>    description longue (corps)
#   --ticket <n>      n° de ticket Redmine -> préfixe "LUT-<n>" au titre et à la branche
#   --version <v>     version visée -> suffixe "-v<v>" (ex. --version 8 => LUT-<n>-v8)
#   --new-branch      créer une branche "LUT-<n>[-v<v>]-<slug>" depuis HEAD avant le push
#   --branch-base     avec --new-branch : nommer la branche "LUT-<n>-<base>" (requiert --base)
#   --base <branch>   branche cible                   [branche par défaut de l'upstream, sinon main]
#   --head <branch>   branche source                  [branche courante]
#   --push-remote <r> remote où pousser (ton fork)    [origin]
#   --upstream <r>    remote cible de la PR           [upstream si présent, sinon origin]
#   --draft           créer en brouillon
#   --fill            déduire titre/description des commits
#   --no-push         ne pas pousser la branche
#   -h, --help        afficher cette aide
#
# Variables d'environnement :
#   KDBX_PASS   (REQUISE) passphrase du coffre — exportée AVANT `claude`
#   PR_KDBX     chemin du coffre                 [~/.config/claude.kdbx]
#   GH_ENTRY    entrée du token GitHub           [GitHub]
#   GL_ENTRY    entrée du token GitLab           [GitLab]
#   GITLAB_HOST hôte GitLab (auto-détecté si non défini)

set -euo pipefail

KDBX="${PR_KDBX:-$HOME/.config/claude.kdbx}"
GH_ENTRY_SET="${GH_ENTRY:+1}"   # 1 si l'utilisateur a fixé GH_ENTRY explicitement
GH_ENTRY="${GH_ENTRY:-}"
GL_ENTRY="${GL_ENTRY:-GitLab}"

repo_dir="."
title=""; body=""; base=""; head=""; draft=""; fill=""; do_push=1
push_remote="origin"; up_remote=""
ticket=""; version=""; new_branch=0; branch_base=0
passthrough=()

while [ $# -gt 0 ]; do
  case "$1" in
    -C) repo_dir="$2"; shift 2;;
    -t|--title) title="$2"; shift 2;;
    -b|--body) body="$2"; shift 2;;
    --ticket) ticket="$2"; shift 2;;
    --version) version="$2"; shift 2;;
    --new-branch) new_branch=1; shift;;
    --branch-base) branch_base=1; shift;;
    --base) base="$2"; shift 2;;
    --head) head="$2"; shift 2;;
    --push-remote) push_remote="$2"; shift 2;;
    --upstream) up_remote="$2"; shift 2;;
    --draft) draft=1; shift;;
    --fill) fill=1; shift;;
    --no-push) do_push=0; shift;;
    -h|--help) sed -n '2,47p' "$0"; exit 0;;
    --) shift; passthrough=("$@"); break;;
    *) echo "Option inconnue: $1" >&2; exit 2;;
  esac
done

# --- Prérequis ---
if [ -z "${KDBX_PASS:-}" ]; then
  echo "ERREUR: KDBX_PASS non définie. Exporte-la AVANT de lancer claude :" >&2
  echo "  read -rs KDBX_PASS && export KDBX_PASS && claude --continue" >&2
  exit 1
fi
[ -f "$KDBX" ] || { echo "ERREUR: coffre introuvable : $KDBX" >&2; exit 1; }
[ -z "$fill" ] && [ -z "$title" ] && { echo "ERREUR: --title requis (ou --fill)." >&2; exit 2; }

cd "$repo_dir"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERREUR: pas un dépôt git : $repo_dir" >&2; exit 1; }

# --- Convention lutece-platform : LUT-<ticket>[-v<version>] ---
slugify() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' \
  | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-50 | sed -E 's/-+$//'; }

tag=""
if [ -n "$ticket" ]; then
  case "$ticket" in *[!0-9]*) echo "ERREUR: --ticket doit être un numéro (ID Redmine)." >&2; exit 2;; esac
  tag="LUT-$ticket"
  [ -n "$version" ] && tag="$tag-v$version"
  # Préfixer le titre s'il ne suit pas déjà la convention LUT-/LUTECE-
  if [ -n "$title" ]; then
    case "$title" in LUT-*|LUTECE-*) : ;; *) title="$tag : $title";; esac
  fi
fi

# Création de branche conforme si demandé
if [ "$new_branch" = 1 ]; then
  [ -n "$tag" ] || { echo "ERREUR: --new-branch requiert --ticket." >&2; exit 2; }
  if [ "$branch_base" = 1 ]; then
    [ -n "$base" ] || { echo "ERREUR: --branch-base requiert --base." >&2; exit 2; }
    # nom = LUT-<ticket>-<base> ; on normalise / et espaces en -, on garde les points
    base_ref=$(printf '%s' "$base" | sed -E 's#[[:space:]/]+#-#g; s#^-+##; s#-+$##')
    head="LUT-$ticket-$base_ref"
  else
    slug=$(slugify "${title#$tag : }")
    head="$tag${slug:+-$slug}"
  fi
  git rev-parse --verify --quiet "refs/heads/$head" >/dev/null \
    && git checkout "$head" \
    || git checkout -b "$head"
fi

# Résolution des remotes
git remote get-url "$push_remote" >/dev/null 2>&1 || { echo "ERREUR: remote de push introuvable : $push_remote" >&2; exit 1; }
if [ -z "$up_remote" ]; then
  if git remote get-url upstream >/dev/null 2>&1; then up_remote="upstream"; else up_remote="$push_remote"; fi
fi
git remote get-url "$up_remote" >/dev/null 2>&1 || { echo "ERREUR: remote upstream introuvable : $up_remote" >&2; exit 1; }

push_url=$(git remote get-url "$push_remote")
up_url=$(git remote get-url "$up_remote")
[ -n "$head" ] || head=$(git rev-parse --abbrev-ref HEAD)
if [ -z "$base" ]; then
  base=$(git symbolic-ref -q "refs/remotes/$up_remote/HEAD" 2>/dev/null | sed "s@^refs/remotes/$up_remote/@@") || true
  [ -n "$base" ] || base="main"
fi

# owner et owner/repo depuis une URL (https://host/owner/repo(.git) ou git@host:owner/repo(.git))
ownerrepo() { printf '%s' "$1" | sed -E 's#^[a-z]+://[^/]+/##; s#^[^@]*@[^:]+:##; s#\.git$##'; }
host_of()   { printf '%s' "$1" | sed -E 's#^[a-z]+://##; s#^[^@]*@##; s#[:/].*$##'; }

fork_owner=$(ownerrepo "$push_url" | cut -d/ -f1)
up_slug=$(ownerrepo "$up_url")           # owner/repo de l'upstream (cible PR)

case "$up_url" in
  *github.com*) platform="github";;
  *gitlab*|*dev.lutece.paris.fr*) platform="gitlab";;
  *) echo "ERREUR: plateforme non reconnue pour upstream=$up_url" >&2; exit 1;;
esac

echo ">> Push  : $push_remote ($push_url)"
echo ">> PR vers: $up_remote ($up_slug) [$platform]"
echo ">> $fork_owner:$head -> $base${draft:+ | draft}"

extract() { printf '%s' "$KDBX_PASS" | keepassxc-cli show -s -a Password -q "$KDBX" "$1"; }

# Entrée GitHub : respecte un GH_ENTRY explicite ; sinon préfère GithubClassic
# (classic PAT, seul capable de fork + PR cross-fork vers une orga tierce),
# repli sur Github (fine-grained, restreint au push).
resolve_gh_entry() {
  [ -n "$GH_ENTRY_SET" ] && return 0
  if printf '%s' "$KDBX_PASS" | keepassxc-cli show -q "$KDBX" GithubClassic >/dev/null 2>&1; then
    GH_ENTRY="GithubClassic"
  else
    GH_ENTRY="Github"
  fi
}

if [ "$platform" = "github" ]; then
  resolve_gh_entry
  echo ">> Entrée token GitHub : $GH_ENTRY"
  TOKEN=$(extract "$GH_ENTRY")
  [ -n "$TOKEN" ] || { echo "ERREUR: token GitHub vide (entrée '$GH_ENTRY')." >&2; exit 1; }
  export GIT_ASKPASS_TOKEN="$TOKEN"
  if [ "$do_push" = 1 ]; then
    git -c credential.helper='!f(){ echo username=x-access-token; echo "password=$GIT_ASKPASS_TOKEN"; };f' \
        push -u "$push_remote" "$head"
  fi
  args=(pr create --repo "$up_slug" --base "$base" --head "$fork_owner:$head")
  [ -n "$title" ] && args+=(--title "$title")
  [ -n "$body" ]  && args+=(--body "$body")
  [ -n "$fill" ]  && args+=(--fill)
  [ -n "$draft" ] && args+=(--draft)
  GH_TOKEN="$TOKEN" gh "${args[@]}" "${passthrough[@]}"
else
  TOKEN=$(extract "$GL_ENTRY")
  [ -n "$TOKEN" ] || { echo "ERREUR: token GitLab vide (entrée '$GL_ENTRY')." >&2; exit 1; }
  : "${GITLAB_HOST:=$(host_of "$up_url")}"
  export GIT_ASKPASS_TOKEN="$TOKEN"
  if [ "$do_push" = 1 ]; then
    git -c credential.helper='!f(){ echo username=oauth2; echo "password=$GIT_ASKPASS_TOKEN"; };f' \
        push -u "$push_remote" "$head"
  fi
  # MR fork -> upstream : --source-project (ton fork) vers --target-project (upstream)
  args=(mr create --source-branch "$head" --target-branch "$base" --target-project "$up_slug" --yes)
  [ -n "$title" ] && args+=(--title "$title")
  [ -n "$body" ]  && args+=(--description "$body")
  [ -n "$fill" ]  && args+=(--fill)
  [ -n "$draft" ] && args+=(--draft)
  GITLAB_TOKEN="$TOKEN" GITLAB_HOST="$GITLAB_HOST" glab "${args[@]}" "${passthrough[@]}"
fi
