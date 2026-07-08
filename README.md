# lutece-kdbx-tools — marketplace Claude Code

Marketplace personnelle hébergeant le plugin **`lutece-kdbx`**, qui regroupe deux skills :

| Skill (namespacé) | Rôle |
|---|---|
| `/lutece-kdbx:git-pr-kdbx` | Créer PR/MR (GitHub via `gh`, GitLab via `glab`) + fork/clone, tokens lus depuis un coffre KeePassXC |
| `/lutece-kdbx:redmine-kdbx` | Interroger l'API Redmine (bugtracker Lutèce), clé lue depuis le coffre |

Aucun secret n'est stocké dans ce dépôt : les tokens vivent dans `~/.config/claude.kdbx`,
et la passphrase est fournie via `KDBX_PASS` au lancement de `claude`.

## Installation

```bash
# 1. Ajouter la marketplace (chemin local, dépôt git, ou owner/repo GitHub-GitLab)
/plugin marketplace add ~/lutece-kdbx-tools
#   ou depuis git :  /plugin marketplace add <url-ou-owner/repo>

# 2. Installer le plugin
/plugin install lutece-kdbx@lutece-kdbx-tools

# 3. Provisionner le poste (outils, coffre, entrées, env) — ne touche à aucun secret
bash "${CLAUDE_PLUGIN_ROOT}/bootstrap.sh"    # ou : bash ~/lutece-kdbx-tools/plugins/lutece-kdbx/bootstrap.sh
```

## Prérequis (assurés par `bootstrap.sh`)

- Outils : `gh`, `glab`, `keepassxc-cli`, `jq`, `curl`, `git`.
- Coffre `~/.config/claude.kdbx` (chmod 600) avec les entrées : `GithubClassic` (requis),
  `Redmine` (requis), `Github`/`GitLab` (optionnels).
- `KDBX_PASS` exportée **avant** `claude` :
  ```bash
  read -rs KDBX_PASS && export KDBX_PASS && claude
  ```

Voir `plugins/lutece-kdbx/PORTAGE.md` pour le détail (portées des tokens, sécurité).

## Développement / mise à jour

- Éditer les `SKILL.md` : effet immédiat.
- Après édition d'autres composants : `/reload-plugins`.
- Publier : commiter ce dépôt sur GitHub/GitLab ; les postes font
  `/plugin marketplace update lutece-kdbx-tools`.
