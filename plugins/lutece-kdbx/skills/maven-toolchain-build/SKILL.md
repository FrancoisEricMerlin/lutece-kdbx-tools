---
name: maven-toolchain-build
description: Construit un projet Maven Lutece en sélectionnant le JDK via le maven-toolchains-plugin, d'après la propriété targetJdk de l'effective pom. À utiliser dès que l'utilisateur veut builder/compiler/tester un projet Lutece avec la bonne version de Java (toolchain), builder multi-JDK, ou parle de targetJdk / toolchains.xml / select-jdk-toolchain.
argument-hint: [goals maven, ex. "clean install" ou "clean lutece:exploded antrun:run -Dlutece-test-hsql test"]
allowed-tools: Bash
---

## Objectif

Builder un projet Maven en laissant le JDK être **choisi automatiquement** à partir de la
propriété `targetJdk` de l'**effective pom** (héritée du parent `lutece-global-pom`), via le
`maven-toolchains-plugin`. Le JDK sélectionné compile et teste le projet **indépendamment du
JDK qui exécute Maven**.

Aucune modification du `pom.xml` du projet n'est nécessaire : la sélection se fait en ligne de
commande avec le goal `select-jdk-toolchain`.

## Prérequis

1. **`~/.m2/toolchains.xml`** (pluriel — Maven ignore `toolchain.xml` singulier) déclarant une
   toolchain `<type>jdk</type>` pour chaque version cible. Exemple :

   ```xml
   <toolchains>
     <toolchain>
       <type>jdk</type>
       <provides><version>11</version></provides>
       <configuration><jdkHome>/usr/lib/jvm/java-11-openjdk-amd64</jdkHome></configuration>
     </toolchain>
     <!-- répéter pour 8, 17, 21… -->
   </toolchains>
   ```

2. **Maven ≥ 3.6.3** (le goal `select-jdk-toolchain` existe depuis le plugin 3.2.0).

## Utilisation

Se placer à la racine du projet (là où est le `pom.xml`), puis appeler le script — il lit
`targetJdk`, vérifie qu'une toolchain existe pour cette version, puis lance le build en
préfixant `select-jdk-toolchain` aux goals demandés.

```bash
S=${CLAUDE_PLUGIN_ROOT}/skills/maven-toolchain-build/mvn-toolchain-build.sh

# Build + install avec le JDK de targetJdk
bash "$S" clean install

# Build complet avec tests (commande de test Lutece)
bash "$S" clean lutece:exploded antrun:run -Dlutece-test-hsql test

# Sans argument -> "clean install"
bash "$S"
```

La commande réellement exécutée est de la forme :

```
mvn org.apache.maven.plugins:maven-toolchains-plugin:3.2.0:select-jdk-toolchain \
    -Dtoolchain.jdk.version=[<targetJdk>] <goals...>
```

### Forcer une autre version (build multi-JDK)

Pour tester la compilation sous un autre JDK sans toucher au pom :

```bash
TARGET_JDK_OVERRIDE=17 bash "$S" clean compile
TARGET_JDK_OVERRIDE=21 bash "$S" clean test
```

### Autres réglages

| Variable | Défaut | Rôle |
|---|---|---|
| `TARGET_JDK_OVERRIDE` | *(vide)* | force la version JDK, court-circuite `targetJdk` |
| `TOOLCHAINS_FILE` | `~/.m2/toolchains.xml` | emplacement du fichier toolchains |
| `TOOLCHAINS_PLUGIN_VERSION` | `3.2.0` | version du `maven-toolchains-plugin` |

## Comment est lue `targetJdk`

```
mvn -q help:evaluate -Dexpression=targetJdk -DforceStdout
```

Le script tente d'abord en mode hors-ligne (`-o`, rapide si le plugin `help` est en cache) puis
bascule en ligne au besoin. Il ne retient que la dernière ligne non vide (la valeur).

## Règles impératives

- **`select-jdk-toolchain` doit rester en TÊTE** des goals, dans le **même appel Maven** : il
  mémorise la toolchain dans le contexte du build, reprise ensuite par `maven-compiler-plugin`
  et `maven-surefire-plugin`. Le script s'en charge — ne pas réordonner.
- **Ne pas modifier le `pom.xml` du projet** pour cela : la sélection est purement CLI.
- La `<version>` demandée doit exister dans `toolchains.xml`, sinon le build échoue avec
  « Cannot find matching toolchain ».
- `targetJdk` reste piloté par le parent Lutece : si le socle passe à 17/21, le build suit
  automatiquement, sans changer ni le script ni le pom.

## Dépannage

- **`Propriété targetJdk introuvable`** → le pom (ou son parent) ne définit pas `targetJdk` ;
  utiliser `TARGET_JDK_OVERRIDE=<version>`.
- **`Cannot find matching toolchain for jdk [version='X']`** → ajouter la toolchain `X` dans
  `~/.m2/toolchains.xml` (et vérifier que `jdkHome` contient bien un `bin/javac`).
- **Erreur `--release`** (ex. `TARGET_JDK_OVERRIDE=8` avec `maven.compiler.release=11`) → un JDK
  antérieur à la release cible ne sait pas cross-compiler vers une version plus récente ;
  choisir un JDK ≥ à la release.
- **Le plugin ne se télécharge pas (hors-ligne)** → fixer une version présente en cache via
  `TOOLCHAINS_PLUGIN_VERSION`, ou lancer une première fois en ligne.
