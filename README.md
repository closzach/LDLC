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
