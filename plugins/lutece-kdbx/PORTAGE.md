# Portage des skills `git-pr-kdbx` et `redmine-kdbx`

Guide pour rendre ces deux skills utilisables sur un **nouveau poste de travail**.
Les skills eux‑mêmes ne contiennent **aucun secret** : ils lisent tout depuis
l'environnement et un coffre KeePassXC. Seuls les secrets et la config réseau sont
spécifiques au poste.

## Ce qui compose les skills

| Élément | Nature | Portable ? |
|---|---|---|
| `~/.claude/skills/git-pr-kdbx/` (`SKILL.md`, `git-pr.sh`, `fork.sh`) | fichiers, sans secret | ✅ copier / versionner (git) |
| `~/.claude/skills/redmine-kdbx/` (`SKILL.md`, `redmine.sh`) | fichiers, sans secret | ✅ copier / versionner (git) |
| `gh`, `glab`, `keepassxc-cli`, `jq`, `curl`, `git` | binaires | ⚙️ à installer |
| `~/.config/claude.kdbx` (entrées `GithubClassic`, `Redmine`, `Github`, `GitLab`) | **secrets** (tokens) | 🔒 recréer / transférer |
| `KDBX_PASS` (passphrase du coffre) | secret de session | 🔒 exporter avant `claude` |
| Proxy (`https_proxy`…) | config réseau | ⚙️ par poste |

## Procédure express

```bash
# 1. Récupérer les fichiers des skills (sans secret) — via dépôt dotfiles ou scp
mkdir -p ~/.claude/skills
scp -r ANCIEN_POSTE:~/.claude/skills/git-pr-kdbx ~/.claude/skills/
scp -r ANCIEN_POSTE:~/.claude/skills/redmine-kdbx ~/.claude/skills/

# 2. Lancer le bootstrap : il vérifie tout et guide le reste
bash ~/.claude/skills/git-pr-kdbx/bootstrap.sh
```

Le script `bootstrap.sh` :
1. contrôle la présence des outils (et donne les commandes d'installation manquantes) ;
2. vérifie les dossiers des skills et rend les `*.sh` exécutables ;
3. crée le coffre `~/.config/claude.kdbx` (chmod 600) s'il est absent ;
4. liste les entrées présentes/manquantes (si `KDBX_PASS` est définie) et affiche les
   commandes `keepassxc-cli add` à taper pour les entrées manquantes ;
5. rappelle comment exporter `KDBX_PASS` et configurer le proxy.

## Détail des entrées du coffre

Le champ **`password`** de chaque entrée contient le token/la clé.

| Entrée | Rôle | Portée conseillée |
|---|---|---|
| **`GithubClassic`** (requis) | fork + push + PR cross‑fork vers `lutece-platform` | *classic PAT* scope **`public_repo`**, expiration courte |
| **`Redmine`** (requis) | API bugtracker `dev.lutece.paris.fr` | clé API perso (Mon compte → Clé d'accès API) |
| `Github` (optionnel) | repli push seul | *fine‑grained PAT* limité au fork, *Contents+PR: RW* |
| `GitLab` (optionnel) | dépôts GitLab lutece | PAT scope `api` |

```bash
keepassxc-cli add -p ~/.config/claude.kdbx GithubClassic
keepassxc-cli add -p ~/.config/claude.kdbx Redmine
# optionnels :
keepassxc-cli add -p ~/.config/claude.kdbx Github
keepassxc-cli add -p ~/.config/claude.kdbx GitLab
```

## Lancement de `claude`

La passphrase du coffre doit être exportée **avant** de lancer `claude` (le shell des
outils n'hérite d'une variable que si elle est présente au démarrage de `claude`) :

```bash
read -rs KDBX_PASS && export KDBX_PASS && claude
```

## Recommandations de sécurité

- **Un token par poste** : créez des PAT dédiés à chaque machine (avec expiration)
  plutôt que de copier le même coffre partout. Révoquer une machine n'impacte alors
  pas les autres. C'est préférable au transfert du fichier `.kdbx`.
- **Ne versionnez jamais** `~/.config/claude.kdbx` ni `KDBX_PASS` dans un dépôt git.
  Seuls les dossiers de skills (sans secret) peuvent être versionnés.
- Gardez le coffre en **`chmod 600`**, hors de tout dépôt.
- Pas de `--noproxy` : l'accès à `dev.lutece.paris.fr` passe par le proxy.

## Variables surchargeables (aucun chemin en dur)

| Variable | Défaut | Skill |
|---|---|---|
| `PR_KDBX` | `~/.config/claude.kdbx` | git-pr-kdbx |
| `REDMINE_KDBX` | `~/.config/claude.kdbx` | redmine-kdbx |
| `GH_ENTRY` | auto : `GithubClassic` sinon `Github` | git-pr-kdbx |
| `GL_ENTRY` | `GitLab` | git-pr-kdbx |
| `REDMINE_ENTRY` | `Redmine` | redmine-kdbx |
| `FORKS_DIR` | `~/.lutece-forks` | git-pr-kdbx (fork.sh) |
