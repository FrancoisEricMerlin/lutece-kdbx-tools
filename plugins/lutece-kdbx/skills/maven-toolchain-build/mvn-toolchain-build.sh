#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# mvn-toolchain-build.sh
#
# Construit un projet Maven en sélectionnant le JDK via le maven-toolchains-plugin,
# d'après la propriété `targetJdk` de l'EFFECTIVE pom (héritée du parent Lutece).
#
# Le JDK choisi compile/teste le projet indépendamment du JDK qui exécute Maven.
#
# Usage :
#   bash mvn-toolchain-build.sh [goals/phases maven...]
#   bash mvn-toolchain-build.sh clean install
#   bash mvn-toolchain-build.sh clean lutece:exploded antrun:run -Dlutece-test-hsql test
#
# Sans argument : "clean install".
#
# Variables d'environnement (optionnelles) :
#   TARGET_JDK_OVERRIDE         force la version JDK (court-circuite targetJdk)
#   TOOLCHAINS_FILE             chemin du toolchains.xml (défaut ~/.m2/toolchains.xml)
#   TOOLCHAINS_PLUGIN_VERSION   version du maven-toolchains-plugin (défaut 3.2.0)
# ---------------------------------------------------------------------------
set -euo pipefail

TOOLCHAINS_PLUGIN_VERSION="${TOOLCHAINS_PLUGIN_VERSION:-3.2.0}"
TOOLCHAINS_FILE="${TOOLCHAINS_FILE:-$HOME/.m2/toolchains.xml}"
SELECT_GOAL="org.apache.maven.plugins:maven-toolchains-plugin:${TOOLCHAINS_PLUGIN_VERSION}:select-jdk-toolchain"

err( ) { printf 'ERREUR: %s\n' "$*" >&2; exit 1; }

# --- Prérequis --------------------------------------------------------------
command -v mvn >/dev/null 2>&1 || err "Maven (mvn) introuvable dans le PATH."
[ -f pom.xml ] || err "Aucun pom.xml dans le répertoire courant ($(pwd)) — placez-vous à la racine du projet Maven."
[ -f "$TOOLCHAINS_FILE" ] || err "Fichier toolchains introuvable : $TOOLCHAINS_FILE (déclarez-y vos JDK)."

# --- 1. Déterminer la version du JDK ----------------------------------------
# Priorité : override explicite, sinon propriété targetJdk de l'effective pom.
JDK_VERSION="${TARGET_JDK_OVERRIDE:-}"
if [ -z "$JDK_VERSION" ]; then
    # Récupère la dernière ligne non vide (la valeur) et retire les espaces.
    read_target( ) {
        mvn -B -q "$@" help:evaluate -Dexpression=targetJdk -DforceStdout 2>/dev/null \
            | awk 'NF{v=$0} END{gsub(/[[:space:]]/,"",v); print v}'
    }
    # Essai hors-ligne d'abord (rapide), repli en ligne si le cache est absent.
    JDK_VERSION="$(read_target -o || true)"
    [ -n "$JDK_VERSION" ] || JDK_VERSION="$(read_target || true)"

    case "$JDK_VERSION" in
        '' | *'null object'* | *'invalid expression'* )
            err "Propriété targetJdk introuvable dans l'effective pom." ;;
    esac
fi

echo ">> JDK cible (targetJdk) : $JDK_VERSION"

# La toolchain doit exister pour cette version.
grep -q "<version>${JDK_VERSION}</version>" "$TOOLCHAINS_FILE" \
    || err "Aucune toolchain <version>${JDK_VERSION}</version> dans $TOOLCHAINS_FILE."

# --- 2. Build : select-jdk-toolchain EN TÊTE, puis les goals demandés -------
# select-jdk-toolchain mémorise la toolchain dans le contexte du build ;
# maven-compiler-plugin et maven-surefire-plugin la reprennent ensuite.
GOALS=( "$@" )
[ ${#GOALS[@]} -gt 0 ] || GOALS=( clean install )

echo ">> mvn $SELECT_GOAL -Dtoolchain.jdk.version=[$JDK_VERSION] ${GOALS[*]}"
exec mvn "$SELECT_GOAL" "-Dtoolchain.jdk.version=[$JDK_VERSION]" "${GOALS[@]}"
