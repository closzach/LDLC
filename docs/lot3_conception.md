## Lot 3 : Logs de Navigation et Analytics

### 3.1. Analyse du besoin et contraintes métier
Dans le cadre de la refonte de la plateforme LDLC, le module **Logs et Analytics** doit absorber la télémétrie générée par des millions de visiteurs mensuels (clics, pages vues, recherches) ainsi que la consultation des historiques de commandes. Ce périmètre présente quatre contraintes critiques :
* **Vélocité d'écriture extrême :** chaque interaction utilisateur génère un événement en temps réel (plusieurs millions d'écritures par jour avec de forts pics lors des lancements produits).
* **Volumétrie massive et rétention longue :** les événements doivent être conservés sur plusieurs mois (voire années) à des fins d'analyse.
* **Requêtes analytiques ciblées :** le système doit répondre rapidement à trois besoins précis :
  1. Nombre de vues d'un produit sur la journée en cours.
  2. Classement des produits les plus consultés sur la semaine.
  3. Historique chronologique des commandes d'un client donné.
* **Absence de relations complexes :** les logs sont des événements immuables (*append-only*) qui ne nécessitent ni transactions multi-tables ni jointures complexes.

---

### 3.2. Choix technologique : Apache Cassandra (Famille Colonne)
Pour répondre à ces contraintes, nous retenons **Apache Cassandra**, une base de données NoSQL orientée colonnes distribuée :
* **Performance en écriture (*Append-Only*) :** grâce à son moteur de stockage basé sur des structures *LSM-Tree* (écriture séquentielle dans le *CommitLog* et la *Memtable* en mémoire avant vidage sur disque), Cassandra absorbe des débits d'écriture massifs sans verrouillage.
* **Architecture *Masterless* (Anneau / Ring) :** tous les nœuds du cluster sont égaux (aucun point unique de défaillance). La charge d'écriture et le stockage sont répartis automatiquement via un hachage cohérent (*Consistent Hashing*).
* **Scalabilité horizontale linéaire :** l'ajout de nouveaux nœuds augmente proportionnellement la capacité de stockage et le débit d'absorption lors des pics de trafic LDLC.

---

### 3.3. Justification des compromis (Théorème CAP & Cohérence)
Dans le cadre du **théorème CAP**, en présence d'une coupure réseau (**P** - *Partition Tolerance*), nous privilégions le compromis **AP (Disponibilité + Tolérance aux partitions)** :
* **Priorité à la disponibilité (A) :** la collecte de logs ne doit jamais ralentir ou bloquer le parcours d'achat d'un client en cas de défaillance d'un nœud. Le système continue d'accepter les écritures et converge vers un état cohérent dès le rétablissement du réseau (**cohérence éventuelle** / *Eventual Consistency*).
* **Cohérence réglable (*Tunable Consistency*) par cas d'usage :**
  * *Logs de navigation :* niveau de cohérence **`ONE`** en écriture pour garantir une latence minimale (la perte marginale d'un log de clic en cas de panne majeure est acceptable).
  * *Historique des commandes :* niveau de cohérence **`QUORUM`** en lecture et écriture pour garantir l'exactitude et la durabilité des données financières du client.
* **Gestion automatique du cycle de vie via TTL :** afin d'éviter la saturation des disques sur le long terme sans opérations de maintenance lourdes, les logs bruts utilisent la fonctionnalité native **`default_time_to_live`** (180 jours) pour purger automatiquement les événements expirés.

---

### 3.4. Modélisation *Query-Driven* et Schéma de Données CQL
Contrairement à MongoDB où l'on modélise la structure de la donnée, Cassandra impose une **modélisation orientée requêtes (*Query-Driven Modeling*)** : les `JOIN` et les `GROUP BY` à la volée n'existent pas, et les clauses `WHERE` ne peuvent filtrer que sur les colonnes composant la clé primaire.

Chaque clé primaire (`PRIMARY KEY`) est structurée en deux parties :
1. **Partition Key** (entre parenthèses) : détermine sur quel nœud du cluster la donnée est stockée (« le où »).
2. **Clustering Columns** : déterminent l'ordre de tri physique des lignes à l'intérieur d'une partition (« le comment »).

Nous dénormalisons donc le modèle en **4 tables dédiées** au sein du *Keyspace* `ldlc_analytics` :

```sql
CREATE KEYSPACE IF NOT EXISTS ldlc_analytics
WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};
-- Note : en production multi-datacenter, utiliser NetworkTopologyStrategy avec replication_factor = 3.

USE ldlc_analytics;

-- Table 1 : Stockage brut des événements de navigation
-- Le "bucket" (heure 0..23) évite les "Wide Partitions" (partitions trop volumineuses sur un seul nœud)
CREATE TABLE logs_navigation (
    jour DATE,
    bucket INT,
    event_time TIMESTAMP,
    event_id TIMEUUID,
    user_id UUID,
    type_event TEXT,
    produit_id TEXT,
    PRIMARY KEY ((jour, bucket), event_time, event_id)
) WITH CLUSTERING ORDER BY (event_time DESC)
  AND default_time_to_live = 15552000; -- Rétention automatique de 180 jours

-- Table 2 : Réponse à la requête "Nombre de vues pour ce produit aujourd'hui"
-- Partition composite (produit_id, jour) pour un accès direct en O(1) et type COUNTER atomique
CREATE TABLE vues_par_produit_jour (
    produit_id TEXT,
    jour DATE,
    nb_vues COUNTER,
    PRIMARY KEY ((produit_id, jour))
);

-- Table 3 : Réponse à la requête "Top produits consultés cette semaine"
-- Cassandra ne trie que dans une même partition : 'semaine' est donc la Partition Key
-- et 'nb_vues DESC' est placé en première Clustering Column (alimentée par batch périodique)
CREATE TABLE top_produits_semaine (
    semaine TEXT,
    nb_vues INT,
    produit_id TEXT,
    nom_produit TEXT,
    PRIMARY KEY ((semaine), nb_vues, produit_id)
) WITH CLUSTERING ORDER BY (nb_vues DESC, produit_id ASC);

-- Table 4 : Réponse à la requête "Historique des commandes d'un client"
-- Partitionnée par client_id et pré-triée par date décroissante sur disque
CREATE TABLE commandes_par_client (
    client_id UUID,
    date_commande TIMESTAMP,
    commande_id UUID,
    montant_total DECIMAL,
    statut TEXT,
    produits LIST<TEXT>,
    PRIMARY KEY ((client_id), date_commande, commande_id)
) WITH CLUSTERING ORDER BY (date_commande DESC);
```

---

### 3.5. Requêtes Types et Exemples d'Exécution

#### A. Ingestion d'un log et incrémentation des vues
```sql
-- Écriture d'un événement de clic/vue
INSERT INTO logs_navigation (jour, bucket, event_time, event_id, user_id, type_event, produit_id)
VALUES ('2026-11-18', 14, '2026-11-18 14:22:05', now(), 550e8400-e29b-41d4-a716-446655440000, 'vue_produit', 'P000001');

-- Mise à jour atomique du compteur journalier
UPDATE vues_par_produit_jour
SET nb_vues = nb_vues + 1
WHERE produit_id = 'P000001' AND jour = '2026-11-18';
```

#### B. Requête 1 : Nombre de vues d'un produit aujourd'hui
```sql
SELECT nb_vues
FROM vues_par_produit_jour
WHERE produit_id = 'P000001' AND jour = '2026-11-18';
```
*Exemple de résultat retourné :*
```text
 nb_vues
---------
   14820
```

#### C. Requête 2 : Top 3 des produits les plus consultés cette semaine
```sql
SELECT produit_id, nom_produit, nb_vues
FROM top_produits_semaine
WHERE semaine = '2026-W47'
LIMIT 3;
```
*Exemple de résultat retourné :*
```text
 produit_id          | nom_produit                  | nb_vues
---------------------+------------------------------+---------
 P000001             | AMD Ryzen 7 7800X3D            |   84310
 P000002             | ASUS ROG STRIX B650E-F GAMING WIFI |   71940
 P000005             | Fractal Design North           |   42105
```

#### D. Requête 3 : Historique des commandes d'un client
```sql
SELECT commande_id, date_commande, montant_total, statut, produits
FROM commandes_par_client
WHERE client_id = 550e8400-e29b-41d4-a716-446655440000
LIMIT 5;
```
*Exemple de résultat retourné :*
```text
 commande_id                          | date_commande                   | montant_total | statut | produits
--------------------------------------+---------------------------------+---------------+--------+---------------------------------------------
 9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d | 2026-11-15 18:40:12.000000+0000 |        549.95 | livré  | ['P000001', 'P000005']
 1b9d6bcd-bbfd-4b2d-9b5d-ab8dfbbd4bed | 2026-09-02 10:15:44.000000+0000 |        129.90 | livré  | ['LOGITECH-G-PRO-X']
```