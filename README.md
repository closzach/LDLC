# Projet NoSQL — Refonte de l'Architecture de Données LDLC

*Constantin
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
* [`Docs/Architecture_Globale.png`](./Docs/Architecture_Globale.png) — Schéma d'architecture globale de la plateforme.
* [`Docs/Document_Conception_Global.pdf`](./Docs/Document_Conception_Global.pdf) — Document de conception complet regroupant les 4 lots.

### Lot 1 : Catalogue Produits (MongoDB)
* [`Docs/lot1_conception.md`](./Docs/lot1_conception.md) — Choix technologique, comparaison *Embedded vs References*, patterns, indexation et requêtes types.
* [`Schémas/Lot1_Produits.json`](./Schémas/Lot1_Produits.json) — Jeu de données des fiches produits (15 produits, 4 catégories).
* [`Schémas/Lot1_Avis.json`](./Schémas/Lot1_Avis.json) & [`Schémas/Lot1_Marques.json`](./Schémas/Lot1_Marques.json) — Collections référencées des avis clients et des marques.
* [`Schémas/Lot1_Index.js`](./Schémas/Lot1_Index.js) — Script de création des index composés/multikey et validation de schéma.
* [`Prototype/Lot1_Requetes.js`](./Prototype/Lot1_Requetes.js) — 15 requêtes commentées (CRUD, filtres par attributs, agrégations `$lookup`).

### Lot 2 : Panier et Sessions Utilisateurs (Redis)
* [`Docs/lot2_conception.md`](./Docs/lot2_conception.md) — Modélisation des clés (`session:<token_id>`, `cart:user:<id>`), structures `Hash`, politique de TTL, sécurité et commandes types (`HSET`, `HGETALL`, `EXPIRE`).

### Lot 3 : Logs de Navigation et Analytics (Apache Cassandra)
* [`Docs/lot3_conception.md`](./Docs/lot3_conception.md) — Modélisation *Query-Driven*, choix des *Partition Keys* et *Clustering Columns*, cohérence réglable (`ONE` / `QUORUM`), schémas CQL du Keyspace `ldlc_analytics` et requêtes analytiques.

### Lot 4 : Moteur de Recommandations (Neo4j)
* [`Docs/lot4_conception.md`](./Docs/lot4_conception.md) — Modélisation du graphe (nœuds `Produit`, `Client`, `Categorie`, `Marque` et arêtes `:A_ACHETE`, `:COMPATIBLE_AVEC`) et requêtes Cypher (achats croisés et compatibilité multi-sauts).

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
            Mongo[("🍃 MongoDB (CP)<br/>Base : ldlc<br/>• Lot1_Produits (~27k réf)<br/>• Lot1_Avis (Illimité)<br/>• Lot1_Marques (~600)<br/>Patterns : Polymorphic, Attribute, Subset")]:::mongo
        end

        subgraph L2["Lot 2 : Panier & Sessions (Clé-Valeur In-Memory)"]
            Redis[("⚡ Redis (AP - RAM)<br/>Structures Hash + TTL<br/>• session:&lt;token_id&gt; (TTL 30m)<br/>• cart:user:&lt;id&gt; (TTL 7j)<br/>• cart:guest:&lt;id&gt; (TTL 24h)")]:::redis
            AuthDB[("🔒 Base Comptes (CP / ACID)<br/>Stockage persistant des<br/>emails & hash Argon2id")]:::auth
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
    API ==>|"2. Lecture/Écriture < 1ms<br/>(HSET, HGETALL, EXPIRE)"| Redis
    API -.->|"3. Écriture asynchrone (ONE)<br/>& lecture commandes (QUORUM)"| Cassandra
    API ==>|"4. Achats croisés &<br/>compatibilité multi-sauts"| Neo4j

    %% Interactions et cohérence inter-bases (Liens métier entre les Lots)
    AuthDB -.->|"Validation login initial<br/>puis création token UUID"| Redis
    Mongo -.->|"Dénormalisation à l'ajout au panier<br/>(Copie nom + unit_price)<br/>& Vérification prix au Checkout"| Redis
    Mongo -.->|"Source de vérité Catalogue<br/>Synchronisation de l'id_produit<br/>et des règles de compatibilité"| Neo4j
    Redis -.->|"Validation commande (Checkout) :<br/>Archivage dans commandes_par_client<br/>& ajout arête :A_ACHETE"| Cassandra
    Redis -.->|"Mise à jour graphe d'achat (:A_ACHETE)"| Neo4j