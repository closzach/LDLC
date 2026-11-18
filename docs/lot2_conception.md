# Projet de Refonte LDLC - Lot 2 : Panier et Sessions Utilisateurs

**Membre responsable du Lot :** Module Base de Données Panier & Sessions

**Contexte Métier :** E-commerce high-tech (LDLC), millions de visites mensuelles, pics de trafic intenses (sorties de composants majeurs), exigence de performance critique.

## 1. Choix Technologique & Justification

### 1.1. Technologie Retenue : Redis (avec persistance polyglotte pour les comptes)

Pour répondre aux contraintes du Lot 2, la technologie principale retenue est **Redis** (Remote Dictionary Server), une base de données clé-valeur orientée en mémoire (*In-Memory*). 

Pour la gestion fiable de l'authentification initiale (vérification de l'email et du mot de passe haché), Redis s'appuie en amont sur une base persistante forte (ex: **PostgreSQL** ou **MongoDB** avec contraintes d'unicité et transactions ACID) qui détient les identifiants permanents des comptes clients, tandis que Redis gère exclusivement les **sessions actives** et les **paniers**.

### 1.2. Justification Métier et Technique

* **Latence Sub-milliseconde :** En stockant les paniers et sessions en mémoire vive (RAM), Redis garantit des temps de réponse inférieurs à la milliseconde pour les opérations de lecture et d'écriture, indispensable lors des pics de trafic.
* **Partage inter-serveurs (Scale-Out applicatif) :** Dans une architecture répartie sur plusieurs serveurs web, Redis agit comme un référentiel centralisé permettant à n'importe quel serveur de vérifier instantanément l'authenticité d'une session active.
* **Volatilité et Gestion du TTL (*Time-To-Live*) :** Les paniers non validés et les sessions de navigation sont éphémères. Redis intègre nativement une gestion automatique de l'expiration des clés par TTL.
* **Modélisation du Théorème CAP :** 
  * **Authentification (Source des comptes) :** Orientée **CP** (Cohérence stricte pour garantir l'unicité des emails et la sécurité des mots de passe).
  * **Paniers & Sessions (Redis) :** Orientée **AP** (Disponibilité et Tolérance aux partitions) avec cohérence de session pour garantir un parcours d'achat fluide sans interruption.

## 2. Modélisation des Données (Clés, Structures et TTL)

La modélisation repose sur l'utilisation du type de structure **Hash** de Redis, particulièrement efficace pour représenter des objets structurés tout en permettant des mises à jour atomiques.

### A. Authentification et Gestion des Sessions Utilisateurs

Le processus de connexion fiable s'effectue en deux étapes :
1. **Vérification des identifiants (Base Comptes) :** L'utilisateur soumet son `email` et son `mot_de_passe`. Le serveur vérifie le condensat cryptographique (*hash* via **Argon2id** ou **bcrypt** + sel unique) stocké dans la base utilisateurs.
2. **Création de la session active (Redis) :** Une fois le mot de passe validé, un jeton aléatoire cryptographiquement sûr (`token_id` UUID v4) est généré et enregistré dans Redis.

* **Format de la Clé Redis :** `session:<token_id>` (Exemple : `session:a8f5c9e2-4b71-4d3a-9e11-f23456789abc`)
* **Structure (Hash Redis) :**
  * `user_id` : Identifiant unique de l'utilisateur du Lot 1 (ex: `"C000001"`).
  * `email` : Adresse e-mail authentifiée (ex: `"client@ldlc.com"`).
  * `role` : Niveau d'accès (`"client"`, `"admin"`).
  * `auth_method` : Méthode utilisée (`"password"`).
  * `created_at` : Horodatage de création de la session.
  * `last_activity` : Horodatage de la dernière action.
* **Mécanisme TTL :** Application d'un TTL de **30 minutes (1800 secondes)** d'inactivité, réinitialisé à chaque requête authentifiée de l'utilisateur.

### B. Gestion du Panier d'Achat (avec Prix Unitaire)

Afin d'afficher le montant total du panier en une seule lecture sans solliciter systématiquement le Lot 1 (Catalogue MongoDB), chaque article stocké dans le Hash Redis embarque sa quantité **et** son prix unitaire au moment de l'ajout.

* **Format de la Clé :**
  * Utilisateur connecté : `cart:user:<user_id>` (Exemple : `cart:user:C000001`)
  * Utilisateur invité : `cart:guest:<session_id>` (Exemple : `cart:guest:a8f5c9e2...`)
* **Structure (Hash Redis) :**
  * **Champs (*Fields*) :** Identifiant produit du Lot 1 (Exemple : `P000001`, `P000003`).
  * **Valeurs (*Values*) :** Chaîne JSON sérialisée contenant la quantité et le prix unitaire TTC en euros (Exemple : `'{"qty": 1, "unit_price": 449.95, "name": "AMD Ryzen 7 7800X3D"}'`).
* **Mécanisme TTL :** 
  * Panier invité : **24 heures (86400 secondes)**.
  * Panier utilisateur connecté : **7 jours (604800 secondes)**.

## 3. Requêtes Types & Exemples d'Opérations

### 1. Flux de Connexion Fiable (Authentification & Session)

*Étape 1 : Vérification côté base utilisateurs (requête préparée sécurisée)*
```sql
SELECT user_id, password_hash, role FROM users WHERE email = 'client@ldlc.com';
-- Vérification applicative : argon2.verify(password_hash, input_password) == True
```

*Étape 2 : Enregistrement de la session dans Redis avec TTL de 30 minutes*
```redis
HSET session:a8f5c9e2-4b71-4d3a-9e11-f23456789abc user_id "C000001" email "client@ldlc.com" role "client" auth_method "password" last_activity "1731934200"
EXPIRE session:a8f5c9e2-4b71-4d3a-9e11-f23456789abc 1800
```

*Étape 3 : Vérification de la session à chaque page visitée et rafraîchissement du TTL*
```redis
HGETALL session:a8f5c9e2-4b71-4d3a-9e11-f23456789abc
EXPIRE session:a8f5c9e2-4b71-4d3a-9e11-f23456789abc 1800
```

*Étape 4 : Déconnexion explicite (Logout)*
```redis
DEL session:a8f5c9e2-4b71-4d3a-9e11-f23456789abc
```

### 2. Opérations sur le Panier (avec Prix)

*Ajouter ou mettre à jour un article avec son prix unitaire dans le panier :*
```redis
HSET cart:user:C000001 P000001 '{"qty": 1, "unit_price": 449.95, "name": "AMD Ryzen 7 7800X3D"}'
HSET cart:user:C000001 P000003 '{"qty": 2, "unit_price": 119.90, "name": "Corsair Vengeance DDR5 32 Go"}'
EXPIRE cart:user:C000001 604800
```

*Récupérer l'intégralité du panier (articles, quantités et prix) en une seule requête :*
```redis
HGETALL cart:user:C000001
```

*Supprimer un article spécifique du panier :*
```redis
HDEL cart:user:C000001 P000003
```

## 4. Compromis et Justification Architecturale

* **Dénormalisation du prix dans Redis :** Stocker `unit_price` directement dans le panier Redis évite une jointure réseau coûteuse avec MongoDB (Lot 1) à chaque affichage du panier. En contrepartie, lors de la validation finale de la commande (*Checkout*), le serveur effectue une vérification finale des prix et des stocks auprès du Lot 1 pour prévenir toute variation tarifaire survenue pendant la durée du TTL.
* **Sécurité des mots de passe :** Redis étant une base *In-Memory* optimisée pour la vitesse et non pour le stockage durable de secrets critiques, les mots de passe hachés (Argon2id/bcrypt) ne sont **jamais** stockés dans Redis. Redis ne manipule que le jeton de session temporaire (`token_id`) généré après authentification réussie.
* **Gestion des pannes et persistance :** L'activation des mécanismes hybrides de Redis (**RDB** + **AOF**) assure qu'en cas de redémarrage d'un nœud, les paniers et sessions actives sont restaurés sans perte pour les clients.