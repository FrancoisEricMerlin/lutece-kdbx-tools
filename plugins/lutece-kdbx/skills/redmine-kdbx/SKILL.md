---
name: redmine-kdbx
description: Interroger l'API REST Redmine (bugtracker) en récupérant la clé API depuis un coffre KeePassXC, sans jamais exposer la clé. À utiliser dès que l'utilisateur veut lister/consulter/créer/modifier des projets ou tickets Redmine, ou parle du bugtracker Lutece (dev.lutece.paris.fr/bugtracker).
argument-hint: [chemin API redmine, ex. "issues.json?project_id=extendcomm&status_id=open"]
allowed-tools: Bash
---

## Objectif

Requêter le bugtracker Redmine depuis les outils Bash, en extrayant la clé API d'un coffre KeePassXC à la volée. Ni la clé API, ni la passphrase du coffre n'apparaissent dans la conversation.

## Prérequis (une fois par session)

`keepassxc-cli` doit être installé, et la passphrase du coffre doit être présente dans la variable d'environnement `KDBX_PASS` **du processus qui a lancé `claude`**.

Le shell des outils Bash n'hérite d'une variable **que si elle est exportée AVANT le lancement de `claude`** (il ne source pas `~/.bashrc` et ne partage pas les variables posées via le préfixe `!`). Donc, dans un vrai terminal :

```bash
read -rs KDBX_PASS && export KDBX_PASS   # passphrase masquée
claude --continue                         # (ou `claude`) depuis le même terminal
```

Vérifier que la passphrase est visible avant tout appel :

```bash
[ -n "$KDBX_PASS" ] && echo "KDBX_PASS OK (len ${#KDBX_PASS})" || echo "KDBX_PASS ABSENTE — relancer claude avec la variable exportée"
```

## Configuration (valeurs par défaut)

| Variable | Défaut | Rôle |
|---|---|---|
| `REDMINE_KDBX` | `~/.config/claude.kdbx` | chemin du coffre dédié |
| `REDMINE_ENTRY` | `Redmine` | nom de l'entrée contenant la clé API (champ *password*) |
| `REDMINE_URL` | `https://dev.lutece.paris.fr/bugtracker` | URL de base |

Le coffre dédié ne contient QUE la clé Redmine (principe du moindre privilège), avec sa propre passphrase, en `chmod 600`, hors de tout dépôt git.

## Utilisation

Le script `redmine.sh` (dans ce dossier de skill) gère extraction + authentification + proxy. Toujours l'utiliser plutôt que de réécrire un `curl` à la main.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/redmine-kdbx/redmine.sh "<chemin_api>" [args curl...]
```

Filtre systématiquement la sortie avec `jq` pour ne garder que l'utile.

### Exemples

```bash
S=${CLAUDE_PLUGIN_ROOT}/skills/redmine-kdbx/redmine.sh

# Nombre total de projets
bash "$S" "projects.json?limit=1" | jq '.total_count'

# Lister TOUS les projets (pagination — total ~927, limit max 100)
bash "$S" "projects.json?limit=100&offset=0" | jq -r '.projects[] | [.identifier, .name] | @tsv'

# Tickets ouverts d'un projet, plus récents d'abord
bash "$S" "issues.json?project_id=extendcomm&status_id=open&sort=updated_on:desc&limit=25" \
  | jq -r '.issues[] | "#\(.id) [\(.status.name)] \(.tracker.name) | \(.subject)"'

# Détail complet d'un ticket
bash "$S" "issues/33002.json?include=journals,attachments,relations" | jq '.issue'

# Mes tickets assignés
bash "$S" "issues.json?assigned_to_id=me&status_id=open" | jq -r '.issues[] | "#\(.id) \(.subject)"'

# Créer un ticket
bash "$S" "issues.json" -X POST -H "Content-Type: application/json" \
  -d '{"issue":{"project_id":"extendcomm","subject":"Titre","description":"..."}}'
```

## Règles impératives

- **JAMAIS `--noproxy`** : l'accès à `dev.lutece.paris.fr` DOIT passer par le proxy (sinon timeout). `redmine.sh` respecte déjà cette règle.
- **Ne jamais afficher** la clé API ni la passphrase (pas de `echo "$KEY"`, pas de `env`, etc.).
- Toujours ajouter `--max-time` (déjà dans le script) pour éviter de bloquer.
- `limit` est plafonné à 100 côté Redmine → paginer avec `offset` pour parcourir de grands ensembles.
- Chaque endpoint existe en `.json` et `.xml` ; utiliser `.json` + `jq`.

## Dépannage

- **`clé API vide`** → mauvaise passphrase, ou l'entrée `Redmine` n'a pas de mot de passe / mauvais nom (`REDMINE_ENTRY`).
- **`KDBX_PASS non définie`** → relancer `claude` depuis un terminal où la variable est exportée.
- **timeout** → vérifier que le proxy est actif (skill `set-proxy`) et qu'on n'a pas mis `--noproxy`.
- **401/403** → clé API invalide ou révoquée ; en régénérer une dans Redmine (*Mon compte → Clé d'accès API*) et la remettre dans le coffre.
