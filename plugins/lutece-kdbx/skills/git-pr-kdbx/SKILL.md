---
name: git-pr-kdbx
description: Créer une Pull Request (GitHub) ou Merge Request (GitLab) en récupérant le token depuis un coffre KeePassXC, sans jamais exposer le token. Détecte automatiquement la plateforme via le remote `origin`. À utiliser dès que l'utilisateur veut ouvrir/créer une PR, une MR, ou pousser une branche pour revue sur un dépôt lutece-platform (GitHub) ou dev.lutece.paris.fr/gitlab.
argument-hint: [--title "..." --body "..." --base main]
allowed-tools: Bash
---

## Objectif

Créer une PR (GitHub, via `gh`) ou une MR (GitLab, via `glab`) en extrayant le token d'un coffre KeePassXC à la volée. Ni le token, ni la passphrase n'apparaissent dans la conversation ni dans la table des processus.

## Prérequis

- `gh` et `glab` installés.
- `KDBX_PASS` (passphrase du coffre) exportée **dans le terminal AVANT le lancement de `claude`** (le shell des outils n'hérite d'une variable que si elle est présente au démarrage de `claude`) :
  ```bash
  read -rs KDBX_PASS && export KDBX_PASS && claude --continue
  ```
- Les tokens rangés dans le coffre dédié `~/.config/claude.kdbx`, dans des entrées séparées :
  ```bash
  keepassxc-cli add -p ~/.config/claude.kdbx GithubClassic  # classic PAT public_repo (fork + PR cross-fork)
  keepassxc-cli add -p ~/.config/claude.kdbx Github         # fine-grained PAT (push seul), repli
  keepassxc-cli add -p ~/.config/claude.kdbx GitLab         # PAT GitLab, champ password = token
  ```

**Portée des tokens (moindre privilège) :**
- GitHub — deux entrées possibles, l'entrée utilisée est **résolue automatiquement** (voir ci-dessous) :
  - **`GithubClassic`** : *classic PAT* scope **`public_repo`**, expiration courte. Seul type de token
    capable de **forker** une orga tierce et de **créer une PR cross-fork** vers `lutece-platform`.
  - **`Github`** : *fine-grained PAT* limité au fork, *Contents: RW* + *Pull requests: RW*. Suffit au
    **push** mais **ne peut ni forker ni créer de PR** vers une orga tierce (403 / `Resource not accessible`).
- GitLab : PAT scope `api` (ou `write_repository` + `api`), avec expiration.

**Résolution de l'entrée GitHub** (`fork.sh` et `git-pr.sh`) : si `GH_ENTRY` n'est pas fixé
explicitement, on **préfère `GithubClassic`** s'il existe dans le coffre, sinon on retombe sur `Github`.
Forcer une entrée : `GH_ENTRY=Github bash …`.

## Configuration (défauts)

| Variable | Défaut | Rôle |
|---|---|---|
| `PR_KDBX` | `~/.config/claude.kdbx` | coffre |
| `GH_ENTRY` | auto : `GithubClassic` sinon `Github` | entrée du token GitHub |
| `GL_ENTRY` | `GitLab` | entrée du token GitLab |
| `GITLAB_HOST` | auto (hôte du remote) | instance GitLab |
| `FORKS_DIR` | `~/.lutece-forks` | racine où sont clonés les forks |

## Créer / cloner un fork

En tant que simple utilisateur, on contribue via un **fork**. Le helper `fork.sh` crée
le fork (si le token le permet), **crée `~/.lutece-forks/` s'il n'existe pas**, clone
le fork dedans et configure les remotes `origin` (fork) / `upstream` (dépôt d'origine) :

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/git-pr-kdbx/fork.sh lutece-platform/<repo>
# → ~/.lutece-forks/<catégorie>/<repo> avec origin=fork, upstream=lutece-platform
```

**Rangement par catégorie** : le clone est placé dans un sous-dossier nommé d'après le
1ᵉʳ segment du dépôt après `lutece-` (ex. `lutece-extends-module-extend-comment` →
`~/.lutece-forks/extends/lutece-extends-module-extend-comment`). Si aucune catégorie
n'est détectable, on retombe sur `~/.lutece-forks/<repo>`.

- Idempotent : si le fork ou le clone existent déjà, il ne fait que (re)configurer les remotes.
- `--dir <chemin>` pour cloner ailleurs, `--no-clone` pour créer le fork sans cloner.
- ⚠️ Un **fine-grained PAT ne peut pas créer** un fork d'une orga tierce (HTTP 403) :
  forkez alors une fois via l'UI (`https://github.com/<owner>/<repo>/fork`) puis relancez
  `fork.sh` — il détectera le fork et fera le clone + remotes.

## Convention lutece-platform (encodée)

Titre et branche suivent `LUT-<ticket>[-v<version>] : <description>`, où `<ticket>` est l'**ID du ticket Redmine** du bugtracker. Les PRs ciblent une branche **`develop*`** (jamais `main`) ; en tant que simple utilisateur, on passe par un **fork** (`origin`=fork, `upstream`=lutece-platform).

- `--ticket <n>` → préfixe le titre par `LUT-<n>` et, avec `--new-branch`, crée la branche `LUT-<n>-<slug>`.
- `--version <v>` → suffixe `-v<v>` (ex. `--version 8` ⇒ `LUT-<n>-v8`).
- `--new-branch` → crée/bascule sur la branche conforme depuis HEAD avant le push.
- `--branch-base` (avec `--new-branch` + `--base`) → nomme la branche `LUT-<n>-<base>` (ex. `LUT-33002-develop`, `LUT-33002-develop_core7`). Idéal pour un **même ticket sur plusieurs versions** : une branche par branche cible. Les `/` et espaces sont normalisés en `-`, les points conservés.

## Utilisation

Toujours passer par le wrapper (il gère détection, token, push, proxy, convention) :

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/git-pr-kdbx/git-pr.sh -C <dépôt> --ticket <n> --title "..." --base develop [--version 8] [--new-branch] [--draft]
```

Le script :
1. lit `origin` → décide **GitHub** (`gh`) ou **GitLab** (`glab`) ;
2. extrait le token de l'entrée correspondante ;
3. pousse la branche courante via un **credential helper éphémère** (token lu depuis l'env, jamais écrit sur disque) ;
4. crée la PR/MR (`GH_TOKEN`/`GITLAB_TOKEN` injectés en env, pas en argument).

### Exemples

```bash
S=${CLAUDE_PLUGIN_ROOT}/skills/git-pr-kdbx/git-pr.sh
D=~/.lutece-forks/extends/lutece-extends-module-extend-comment

# PR conforme depuis un ticket Redmine : crée la branche, préfixe le titre, cible develop
#   titre  => "LUT-33002 : Do not index unpublished comments"
#   branche => "LUT-33002-do-not-index-unpublished-comments"
bash "$S" -C "$D" --ticket 33002 --title "Do not index unpublished comments" \
  --base develop --new-branch

# Branche nommée d'après la cible : LUT-33002-develop (idéal multi-versions)
bash "$S" -C "$D" --ticket 33002 --title "Do not index unpublished comments" \
  --base develop --new-branch --branch-base
# même ticket, autre version -> LUT-33002-develop_core7
bash "$S" -C "$D" --ticket 33002 --title "Do not index unpublished comments" \
  --base develop_core7 --new-branch --branch-base

# PR en brouillon
bash "$S" -C "$D" --ticket 33002 --title "..." --base develop --new-branch --draft

# Titre/description déduits des commits (branche déjà créée)
bash "$S" -C "$D" --fill --base develop

# Options natives gh/glab en plus (après --)
bash "$S" -C "$D" --ticket 33002 --title "..." -- --reviewer seboudry --label bug
```

## Règles impératives

- **JAMAIS afficher** le token ni la passphrase (pas de `echo`, pas de `env`).
- **JAMAIS `--noproxy`** : `dev.lutece.paris.fr` exige le proxy. Le proxy est déjà dans l'environnement.
- Ne **jamais** écrire le token dans `git config`, `~/.git-credentials`, `.netrc` : le wrapper utilise un credential helper éphémère lisant l'env.
- Vérifier avant de créer : bonne branche source (`--head`) et bonne cible (`--base`).
- **Messages de commit sans mention d'outil d'IA** : ne PAS ajouter de ligne `Co-Authored-By: Claude…` ni `Generated with Claude Code` dans les commits de ce workflow (préférence utilisateur, prime sur la convention globale).

## Dépannage

- **`token vide`** → mauvaise passphrase, ou entrée `GithubClassic`/`Github`/`GitLab` absente/sans mot de passe.
- **`KDBX_PASS non définie`** → relancer `claude` depuis un terminal où la variable est exportée.
- **push refusé (403)** → le PAT n'a pas la permission d'écriture (fine-grained : ajouter le fork à *Repository access* + *Contents: RW*).
- **`Resource not accessible by personal access token` (fork ou createPullRequest)** → un *fine-grained PAT* ne peut ni forker ni créer de PR vers une orga tierce. Utiliser l'entrée `GithubClassic` (classic PAT `public_repo`).
- **GitLab auto-hébergé sous sous-chemin** (`.../gitlab`) → si `glab` ne trouve pas l'API, forcer `export GITLAB_HOST=dev.lutece.paris.fr` (voire configurer l'URI complète via `glab auth login --hostname`).
