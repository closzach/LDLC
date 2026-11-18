# Projet de Refonte LDLC - Lot 2 : Panier et Sessions Utilisateurs

**Membre responsable du Lot :** Module Base de Données Panier & Sessions  
**Contexte Métier :** E-commerce high-tech (LDLC), millions de visites mensuelles, pics de trafic intenses (sorties de composants majeurs), exigence de performance critique.

---

## 1. Choix Technologique & Justification

### 1.1. Technologie Retenue : Redis
Pour répondre aux contraintes du Lot 2, la technologie retenue est **Redis** (Remote Dictionary Server), une base de données clé-valeur orientée en mémoire (*In-Memory*).

### 1.2. Justification Métier et Technique
* **Latence Sub-milliseconde :** En stockant l'intégralité des données en mémoire vive (RAM), Redis garantit des temps de réponse inférieurs à la milliseconde pour les opérations de lecture et d'écriture. C'est indispensable pour encaisser les pics de trafic sans impacter l'expérience utilisateur lors de l'ajout d'articles au panier.
* **Partage inter-serveurs (Scale-Out applicatif) :** Dans une architecture e-commerce moderne répartie sur plusieurs serveurs web, les sessions de navigation et les paniers ne peuvent pas être stockés localement. Redis agit comme une brique centrale partagée et accessible instantanément par l'ensemble des instances applicatives.
* **Volatilité et Gestion du TTL (*Time-To-Live*) :** Les paniers non validés et les sessions de navigation sont par nature éphémères. Redis intègre nativement une gestion automatique de l'expiration des clés par TTL, évitant ainsi l'engorgement de la base avec des paniers abandonnés ou des sessions périmées.
* **Modélisation du Théorème CAP :** Redis s'inscrit dans un profil **AP** (Disponibilité et Tolérance aux partitions) avec un mécanisme de cohérence de session. En cas d'incident réseau, le système privilégie la disponibilité pour permettre au client de poursuivre ses achats ou de conserver son panier, la synchronisation et la persistance s'effectuant de manière asurée.

---

## 2. Modélisation des Données (Clés, Structures et TTL)

La modélisation repose sur l'utilisation du type de structure **Hash** de Redis, particulièrement efficace pour représenter des objets semi-structurés sans surcoût de performance.

### A. Gestion des Sessions Utilisateurs
* **Format de la Clé :** `session:<token_id>` (Exemple : `session:a8f5c9e2-4b71-4d3a-9e11-f23456789abc`)
* **Structure (Hash Redis) :**
  * `user_id` : Identifiant unique de l'utilisateur (ou `null` si visiteur anonyme).
  * `email` : Adresse e-mail de rattachement.
  * `role` : Rôle ou niveau d'accès (`client`, `guest`, `admin`).
  * `last_activity` : Horodatage de la dernière action.
* **Mécanisme TTL :** Application d'un TTL de **30 minutes (1800 secondes)**, réinitialisé à chaque interaction de l'utilisateur sur le site.

### B. Gestion du Panier d'Achat
* **Format de la Clé :** 
  * Utilisateur connecté : `cart:user:<user_id>` (Exemple : `cart:user:45892`)
  * Utilisateur invité : `cart:guest:<session_id>` (Exemple : `cart:guest:a8f5c9e2...`)
* **Structure (Hash Redis) :**
  * **Champs (*Fields*) :** Référence unique du produit ou SKU (Exemple : `prod_ryzen_7_7800x3d`, `prod_rtx_4070`).
  * **Valeurs (*Values*) :** Quantité commandée (Entier, ex: `1`, `2`).
* **Mécanisme TTL :** Application d'un TTL étendu à **7 jours (604800 secondes)** pour garantir la persistance temporaire du panier si le client quitte le site et revient ultérieurement.

---

## 3. Requêtes Types & Exemples d'Opérations (Commandes Redis)

Les interactions de l'application avec le système de panier et de session s'articulent autour des commandes Redis suivantes :

### 1. Ajouter un produit au panier (ou incrémenter sa quantité)
Si le produit est déjà présent, sa quantité est incrémentée atomiquement. S'il n'est pas présent, il est créé.
```redis
HINCRBY cart:user:45892 prod_ryzen_7_7800x3d 1
```

### 2. Récupérer le contenu complet du panier
Permet d'afficher l'ensemble des articles et des quantités associés au panier de l'utilisateur en une seule lecture optimisée.
```redis
HGETALL cart:user:45892
```

### 3. Supprimer un article spécifique du panier
```redis
HDEL cart:user:45892 prod_rtx_4070
```

### 4. Initialiser ou mettre à jour une session utilisateur avec un TTL de 30 minutes
```redis
HSET session:a8f5c9e2-4b71-4d3a-9e11-f23456789abc user_id "45892" email "client@ldlc.com" role "client"
EXPIRE session:a8f5c9e2-4b71-4d3a-9e11-f23456789abc 1800
```

### 5. Rafraîchir la session à chaque clic de navigation
```redis
EXPIRE session:a8f5c9e2-4b71-4d3a-9e11-f23456789abc 1800
```

---

## 4. Compromis et Justification Architecturale (Persistance Polyglotte)

* **Pourquoi ne pas utiliser un SGBDR relationnel pour le panier ?**  
  Un SGBDR classique nécessiterait des verrous de tables ou des transactions lourdes (ACID) pour chaque modification de panier, créant un goulot d'étranglement (*bottleneck*) lors des pics de forte affluence (soldes, lancements de cartes graphiques). Redis élimine cette friction grâce à son exécution monothread en mémoire et ses structures atomiques.
* **Gestion des pannes et persistance :**  
  Bien que les données soient en mémoire, Redis propose des mécanismes hybrides de sauvegarde (RDB snapshots et AOF append-only logs) garantissant qu'en cas de redémarrage d'urgence d'un nœud, les paniers des clients ne sont pas perdus de manière définitive.