# Projet NoSQL — Refonte de l'Architecture de Données LDLC

* Constantin LOSZACH
* Paul KUTZNER
* Florian BURY
---

## 1. Contexte et Objectif
Face aux limites de sa base relationnelle monolithique actuelle, la plateforme e-commerce high-tech **LDLC** (> 27 000 références, > 600 marques, millions de visites mensuelles et jusqu'à 25 000 colis/jour) nécessite une refonte complète de sa couche de données. 

Ce projet propose une architecture basée sur la **persistance polyglotte**, attribuant à chaque domaine fonctionnel (Lot) le moteur NoSQL le plus adapté à ses contraintes de volumétrie, de latence et de structure.

---

## 2. Synthèse de l'Architecture (Persistance Polyglotte)

| Lot | Périmètre Fonctionnel | Technologie | Famille NoSQL | Compromis CAP | Justification & Patterns Clés |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Lot 1** | **Catalogue Produits** | **MongoDB** | Orientée Documents | **CP** | Schémas polymorphes sans migration. Lecture en une requête. Patterns *Polymorphic*, *Attribute* (indexation des caractéristiques), *Subset* (5 derniers avis) et *Extended Reference* (marques). |
| **Lot 2** | **Panier & Sessions** | **Redis** | Clé-Valeur (*In-Memory*) | **AP** *(+ CP amont)* | Latence sub-milliseconde en RAM et partage de sessions inter-serveurs. Structures `Hash` avec gestion native de la volatilité via **TTL** (30 min session, 24h/7j panier) et dénormalisation du prix unitaire. |
| **Lot 3** | **Logs & Analytics** | **Apache Cassandra** | Orientée Colonnes | **AP** | Ingestion massive en écriture (*Append-Only* / *LSM-Tree*) et architecture *Masterless*. Modélisation *Query-Driven* (4 tables dédiées), *Time-Bucketing* anti-*Wide Partitions*, compteurs et purge par TTL (180 jours). |
| **Lot 4** | **Recommandations** | **Neo4j** | Orientée Graphe | **CP** *(ACID)* | Traversée de relations en temps réel via *Index-Free Adjacency* ($O(1)$) et requêtes **Cypher**. Idéal pour le filtrage collaboratif (achats croisés) et les graphes de compatibilité matérielle multi-sauts. |

### Articulation inter-lots
* **Source de vérité catalogue :** MongoDB (Lot 1) stocke l'intégralité des fiches produits autour d'un identifiant pivot (`id_produit`) partagé avec tous les autres moteurs.
* **Parcours d'achat :** Lors de la navigation, les sessions et paniers actifs vivent en mémoire dans Redis (Lot 2), tandis que chaque interaction génère un événement asynchrone dans Cassandra (Lot 3).
* **Recommandation & Validation :** Neo4j (Lot 4) ne conserve que la topologie (nœuds légers et arêtes de compatibilité/achat) pour suggérer des composants en temps réel. Au moment du *Checkout*, le panier Redis est vérifié auprès de MongoDB pour valider le prix final.

---

## 3. Sommaire des Livrables

### Architecture & Conception Globale
* [`README.md`](./README.md) — Présentation du projet, synthèse de l'architecture polyglotte et sommaire des livrables.
* [`docker-compose.yml`](./docker-compose.yml) — Déploiement local des services Cassandra et Neo4j.
* [`requirements.txt`](./requirements.txt) — Dépendances Python du prototype Cassandra.
* Diagramme Mermaid ci-dessous — Architecture globale de la plateforme.

### Lot 1 : Catalogue Produits (MongoDB)
* [`docs/lot1_conception.md`](./docs/lot1_conception.md) — Choix technologique, comparaison *Embedded vs References*, patterns, indexation et requêtes types.
* [`data/Lot 1/lot1_produits.json`](./data/Lot%201/lot1_produits.json) — Jeu de données des fiches produits.
* [`data/Lot 1/lot1_avis.json`](./data/Lot%201/lot1_avis.json) — Jeu de données des avis clients.
* [`data/Lot 1/lot1_marques.json`](./data/Lot%201/lot1_marques.json) — Jeu de données des marques.
* [`data/Lot 1/lot1_index.js`](./data/Lot%201/lot1_index.js) — Script de création des index MongoDB.
* [`prototype/lot1_requetes.js`](./prototype/lot1_requetes.js) — Requêtes commentées MongoDB pour les principaux cas d'utilisation.

### Lot 2 : Panier et Sessions Utilisateurs (Redis)
* [`docs/lot2_conception.md`](./docs/lot2_conception.md) — Modélisation des clés (`session:<token_id>`, `cart:user:<id>`), structures `Hash`, politique de TTL, sécurité et commandes types (`HSET`, `HGETALL`, `EXPIRE`).
* [`schemas/lot2_redis_schemaless.md`](./schemas/lot2_redis_schemaless.md) — Schéma Redis, conventions de clés, TTL et exemples de commandes.

### Lot 3 : Logs de Navigation et Analytics (Apache Cassandra)
* [`docs/lot3_conception.md`](./docs/lot3_conception.md) — Modélisation *Query-Driven*, choix des *Partition Keys* et *Clustering Columns*, cohérence réglable (`ONE` / `QUORUM`) et requêtes analytiques.
* [`schemas/lot3_cassandra.cql`](./schemas/lot3_cassandra.cql) — Création du keyspace `ldlc_analytics` et des tables Cassandra.
* [`prototype/analytics_cassandra.py`](./prototype/analytics_cassandra.py) — Prototype Python d'écriture et de lecture des données Cassandra.

### Lot 4 : Moteur de Recommandations (Neo4j)
* [`docs/lot4_conception.md`](./docs/lot4_conception.md) — Modélisation du graphe (nœuds `Produit`, `Client`, `Categorie`, `Marque` et arêtes `:A_ACHETE`, `:COMPATIBLE_AVEC`) et requêtes Cypher.
* [`schemas/lot4_neo4j.cypher`](./schemas/lot4_neo4j.cypher) — Contraintes, jeu de données et requêtes Cypher du graphe Neo4j.

```mermaid
flowchart TB
    %% Définition des styles visuels
    classDef client fill:#1e293b,stroke:#0f172a,stroke-width:2px,color:#ffffff,font-weight:bold
    classDef api fill:#2563eb,stroke:#1d4ed8,stroke-width:2px,color:#ffffff,font-weight:bold
    classDef mongo fill:#16a34a,stroke:#15803d,stroke-width:2px,color:#ffffff
    classDef redis fill:#dc2626,stroke:#b91c1c,stroke-width:2px,color:#ffffff
    classDef cassandra fill:#d97706,stroke:#b45309,stroke-width:2px,color:#ffffff
    classDef neo4j fill:#0284c7,stroke:#0369a1,stroke-width:2px,color:#ffffff
    classDef auth fill:#475569,stroke:#334155,stroke-width:2px,color:#ffffff

    %% Couche Front & Backend
    Client(["🖥️ Client Web / Mobile LDLC"]):::client
    API["⚙️ Backend / API Gateway LDLC<br/>(Routage & Orchestration Polyglotte)"]:::api

    Client <==>|"Requêtes HTTPS (Navigation, Panier, Achat)"| API

    %% Sous-graphe des Bases de Données
    subgraph Polyglot["Architecture de Données NoSQL (Persistance Polyglotte)"]
        direction TB

        subgraph L1["Lot 1 : Catalogue Produits (Orienté Documents)"]
            Mongo[("🍃 MongoDB (CP)<br/>Base externe : ldlc<br/>• Lot1_Produits (~27k réf)<br/>• Lot1_Avis (illimité)<br/>• Lot1_Marques (~600)<br/>Patterns : Polymorphic, Attribute, Subset")]:::mongo
        end

        subgraph L2["Lot 2 : Panier & Sessions (Clé-Valeur In-Memory)"]
            Redis[("⚡ Redis (AP - RAM)<br/>Structures Hash + TTL<br/>• session:&lt;token_id&gt; (30 min)<br/>• cart:user:&lt;id&gt; (7 jours)<br/>• cart:guest:&lt;id&gt; (24 h)")]:::redis
            AuthDB[("🔒 Base Comptes externe (CP / ACID)<br/>PostgreSQL ou MongoDB<br/>emails & hash Argon2id/bcrypt")]:::auth
        end

        subgraph L3["Lot 3 : Logs & Analytics (Orienté Colonnes)"]
            Cassandra[("👁️ Apache Cassandra (AP)<br/>Keyspace : ldlc_analytics<br/>• logs_navigation (TTL 180j)<br/>• vues_par_produit_jour (Counter)<br/>• top_produits_semaine<br/>• commandes_par_client")]:::cassandra
        end

        subgraph L4["Lot 4 : Recommandations (Orienté Graphe)"]
            Neo4j[("🕸️ Neo4j (CP / ACID)<br/>Traversée Cypher O(1)<br/>• Nœuds : Produit, Client, Categorie, Marque<br/>• Arêtes : :A_ACHETE, :COMPATIBLE_AVEC,<br/>:APPARTIENT_A, :DE_MARQUE")]:::neo4j
        end
    end

    %% Flux API <-> Bases de données
    API ==>|"1. Lecture fiches, filtres<br/>& avis ($elemMatch, IXSCAN)"| Mongo
    API ==>|"2. Vérification et sessions<br/>HSET, HGETALL, EXPIRE"| Redis
    API -.->|"3. Écritures logs (ONE)<br/>Lecture commandes (QUORUM)"| Cassandra
    API ==>|"4. Achats croisés &<br/>compatibilité multi-sauts"| Neo4j
    API -.->|"Authentification initiale"| AuthDB

    %% Interactions et cohérence inter-bases (Liens métier entre les Lots)
    AuthDB -.->|"Validation login puis<br/>création du token UUID"| Redis
    Mongo -.->|"Copie nom et prix unitaire<br/>dans Redis à l'ajout au panier"| Redis
    Mongo -.->|"Vérification finale du prix<br/>au moment du Checkout"| Redis
    Mongo -.->|"id_produit : P000xxx<br/>Source des fiches et compatibilités"| Neo4j
    Redis -.->|"Validation du Checkout :<br/>archivage dans commandes_par_client"| Cassandra
    Redis -.->|"Confirmation d'achat :<br/>ajout de l'arête :A_ACHETE"| Neo4j
