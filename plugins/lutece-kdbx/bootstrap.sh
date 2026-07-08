#!/usr/bin/env bash
# bootstrap.sh — prépare un nouveau poste pour les skills « git-pr-kdbx » et « redmine-kdbx ».
#
# Ne manipule ni n'affiche AUCUN secret : il vérifie les prérequis, crée le coffre
# KeePassXC s'il est absent, et guide l'ajout des entrées (les commandes à taper
# demandent elles-mêmes les mots de passe de façon masquée).
#
# Usage :
#   bash ~/.claude/skills/bootstrap.sh
#
# Variables (surchargeables) :
#   PR_KDBX / REDMINE_KDBX   chemin du coffre   [~/.config/claude.kdbx]

set -euo pipefail

KDBX="${PR_KDBX:-${REDMINE_KDBX:-$HOME/.config/claude.kdbx}}"
SKILLS_DIR="$HOME/.claude/skills"

ok( )   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn( ) { printf '  \033[33m!\033[0m %s\n' "$1"; }
ko( )   { printf '  \033[31m✗\033[0m %s\n' "$1"; }
title( ){ printf '\n\033[1m%s\033[0m\n' "$1"; }

missing=0

# ---------------------------------------------------------------------------
title "1. Outils requis"
declare -A HINT=(
  [gh]="GitHub CLI — https://cli.github.com (apt install gh)"
  [glab]="GitLab CLI — https://gitlab.com/gitlab-org/cli (optionnel si pas de GitLab)"
  [keepassxc-cli]="KeePassXC — apt install keepassxc"
  [jq]="apt install jq"
  [curl]="apt install curl"
  [git]="apt install git"
)
for t in git curl jq keepassxc-cli gh glab; do
  if command -v "$t" >/dev/null 2>&1; then
    ok "$t"
  else
    if [ "$t" = "glab" ]; then
      warn "$t absent — ${HINT[$t]}"
    else
      ko "$t absent — ${HINT[$t]}"; missing=1
    fi
  fi
done

# ---------------------------------------------------------------------------
title "2. Fichiers des skills"
for s in git-pr-kdbx redmine-kdbx; do
  if [ -f "$SKILLS_DIR/$s/SKILL.md" ]; then
    ok "$s présent"
    # rendre les scripts exécutables
    find "$SKILLS_DIR/$s" -maxdepth 1 -name '*.sh' -exec chmod +x {} \; 2>/dev/null || true
  else
    ko "$s absent dans $SKILLS_DIR/ — copiez le dossier depuis l'ancien poste (ou votre dépôt dotfiles)"; missing=1
  fi
done

# ---------------------------------------------------------------------------
title "3. Coffre KeePassXC ($KDBX)"
if [ -f "$KDBX" ]; then
  ok "coffre présent"
  perm=$(stat -c '%a' "$KDBX" 2>/dev/null || echo "?")
  [ "$perm" = "600" ] && ok "permissions 600" || { warn "permissions $perm — recommandé 600"; chmod 600 "$KDBX" && ok "corrigées en 600"; }
else
  warn "coffre absent"
  read -rp "  Créer un coffre vide maintenant ? [o/N] " rep
  if [ "${rep:-N}" = "o" ] || [ "${rep:-N}" = "O" ]; then
    mkdir -p "$(dirname "$KDBX")"
    keepassxc-cli db-create -p "$KDBX"   # demande la passphrase (masquée)
    chmod 600 "$KDBX"
    ok "coffre créé : $KDBX (chmod 600)"
  else
    warn "création ignorée — créez-le avec : keepassxc-cli db-create -p \"$KDBX\""
  fi
fi

# ---------------------------------------------------------------------------
title "4. Entrées du coffre"
# GithubClassic : requis pour fork + PR cross-fork (classic PAT public_repo)
# Github        : optionnel (fine-grained, repli push seul)
# Redmine       : requis pour le skill redmine-kdbx
# GitLab        : optionnel (dépôts dev.lutece.paris.fr)
REQUIRED_ENTRIES="GithubClassic Redmine"
OPTIONAL_ENTRIES="Github GitLab"

if [ -f "$KDBX" ] && [ -n "${KDBX_PASS:-}" ]; then
  existing=$(printf '%s' "$KDBX_PASS" | keepassxc-cli ls -q "$KDBX" 2>/dev/null || true)
  for e in $REQUIRED_ENTRIES; do
    printf '%s\n' "$existing" | grep -qx "$e" && ok "$e (requis)" \
      || { ko "$e MANQUANT (requis) — keepassxc-cli add -p \"$KDBX\" $e"; missing=1; }
  done
  for e in $OPTIONAL_ENTRIES; do
    printf '%s\n' "$existing" | grep -qx "$e" && ok "$e (optionnel)" \
      || warn "$e absent (optionnel) — keepassxc-cli add -p \"$KDBX\" $e"
  done
else
  warn "KDBX_PASS non définie (ou coffre absent) : impossible de lister les entrées."
  echo "  Entrées attendues (le champ 'password' = le token) :"
  echo "    keepassxc-cli add -p \"$KDBX\" GithubClassic   # REQUIS  : classic PAT scope public_repo"
  echo "    keepassxc-cli add -p \"$KDBX\" Redmine         # REQUIS  : clé API Redmine (Mon compte > API)"
  echo "    keepassxc-cli add -p \"$KDBX\" Github          # optionnel : fine-grained PAT"
  echo "    keepassxc-cli add -p \"$KDBX\" GitLab          # optionnel : PAT GitLab (scope api)"
fi

# ---------------------------------------------------------------------------
title "5. Environnement de session"
if [ -n "${KDBX_PASS:-}" ]; then
  ok "KDBX_PASS définie (len ${#KDBX_PASS})"
else
  warn "KDBX_PASS non définie — lancez claude ainsi :"
  echo "     read -rs KDBX_PASS && export KDBX_PASS && claude"
fi
if [ -n "${https_proxy:-}${HTTPS_PROXY:-}" ]; then
  ok "proxy HTTPS configuré"
else
  warn "pas de proxy détecté — nécessaire pour dev.lutece.paris.fr (skill set-proxy)"
fi

# ---------------------------------------------------------------------------
title "Bilan"
if [ "$missing" -eq 0 ]; then
  ok "Prérequis bloquants satisfaits. Les skills sont prêts (voir avertissements éventuels ci-dessus)."
else
  ko "Des prérequis bloquants manquent — corrigez les lignes ✗ ci-dessus puis relancez ce script."
  exit 1
fi
