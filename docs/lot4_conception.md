## Lot 4 : Moteur de Recommandations et Compatibilité Produits

### 4.1. Analyse du besoin et contraintes métier
Le catalogue high-tech de LDLC (plus de 27 000 références et 600 marques) repose sur des règles d'interdépendance complexes entre composants (sockets de processeurs, formats de cartes mères et boîtiers, générations de mémoire). Le moteur de recommandation doit répondre en temps réel à deux cas d'usage clés :
* **Recommandation collaborative (achats croisés) :** *« Les clients qui ont acheté ce processeur ont aussi acheté cette carte mère »*.
* **Recommandation technique (compatibilité et alternatives) :** *« Produits compatibles avec ce boîtier »* ou parcours multi-niveaux (configurateur PC).

Dans un SGBDR classique, ce type de parcours nécessite des jointures récursives coûteuses (`JOIN` multiples) dont les temps de réponse se dégradent exponentiellement avec la profondeur de recherche.

---

### 4.2. Choix technologique : Neo4j (Famille Graphe)
Pour ce périmètre, nous retenons **Neo4j**, une base de données NoSQL orientée **Graphe** interrogée via le langage déclaratif **Cypher** :
* **Index-Free Adjacency (Adjacence sans index) :** chaque nœud stocke directement des pointeurs physiques vers ses relations adjacentes. Le coût de parcours d'une relation est constant ($O(1)$) et dépend uniquement du nombre de voisins explorés, et non de la taille totale de la base.
* **Expressivité du langage Cypher :** la syntaxe ASCII-art (`(nœud1)-[:RELATION]->(nœud2)`) permet d'exprimer naturellement des traversées de graphe complexes (amis d'amis, compatibilités en chaîne) en quelques lignes.
* **Évolutivité du schéma :** l'ajout d'un nouveau type de relation (ex. `:REMPLACE_PAR`, `:SOUVENT_VU_ENSEMBLE`) ou d'une nouvelle propriété sur une arête s'effectue sans migration lourde.

---

### 4.3. Justification des compromis (Modélisation et Cohérence)
* **Persistance polyglotte (MongoDB + Neo4j) :** les fiches produits complètes (descriptions longues, photos, avis clients) restent stockées dans **MongoDB (Lot 1)**. Neo4j ne conserve que les identifiants (`produit_id`, `client_id`) et les attributs essentiels au filtrage des relations afin de maintenir l'intégralité du graphe en mémoire RAM pour des traversées sub-millisecondes.
* **Compromis CAP et transactions ACID :** contrairement aux logs (Lot 3), Neo4j garantit les propriétés **ACID** sur les mises à jour de relations et privilégie la cohérence (**CP** en architecture cluster causal) afin d'éviter de recommander un composant incompatible lors de la validation d'un panier.

---

### 4.4. Modélisation Graphe (Nœuds, Arêtes et Propriétés)

```text
  (:Client {id, nom})
         │
         │ :A_ACHETE {date, quantite}
         ▼
  (:Produit {id, nom, prix, socket, format}) ◄───┐
     │        │                                  │
     │        └─── :COMPATIBLE_AVEC {regle} ─────┘
     │
     ├─── :APPARTIENT_A ───► (:Categorie {nom})
     └─── :DE_MARQUE ──────► (:Marque {nom})
```

* **Nœuds (Labels et Propriétés) :**
  * `Produit` : `{id (String, UNIQUE), nom (String), prix (Float), socket (String), format (String)}`
  * `Client` : `{id (UUID, UNIQUE), nom (String)}`
  * `Categorie` : `{nom (String, UNIQUE)}`
  * `Marque` : `{nom (String, UNIQUE)}`
* **Arêtes (Types de relations et Propriétés) :**
  * `(:Client)-[:A_ACHETE {date, quantite}]->(:Produit)` : modélise l'historique d'achat pour le filtrage collaboratif.
  * `(:Produit)-[:COMPATIBLE_AVEC {regle, verifie}]->(:Produit)` : modélise les règles de compatibilité technique entre composants.
  * `(:Produit)-[:APPARTIENT_A]->(:Categorie)` et `(:Produit)-[:DE_MARQUE]->(:Marque)` : permettent de filtrer les recommandations par famille ou constructeur.

---

### 4.5. Requêtes Cypher Types et Exemples d'Exécution

#### A. Achats croisés (« Les clients qui ont acheté ce processeur ont aussi acheté... »)
```cypher
MATCH (p1:Produit {id: 'P000001'})<-[:A_ACHETE]-(c:Client)-[:A_ACHETE]->(p2:Produit)
WHERE p1 <> p2
RETURN p2.id AS produit_recommande, p2.nom AS nom, COUNT(DISTINCT c) AS nb_acheteurs_communs
ORDER BY nb_acheteurs_communs DESC
LIMIT 5;
```
*Exemple de résultat retourné :*
```text
 produit_recommande | nom                         | nb_acheteurs_communs
--------------------+-----------------------------+----------------------
 P000002             | ASUS ROG STRIX B650E-F GAMING WIFI |                    2
 P000003             | Corsair Vengeance DDR5 32 Go        |                    1
```

#### B. Compatibilité matérielle (« Produits compatibles avec ce boîtier »)
```cypher
MATCH (b:Produit {id: 'P000005'})-[r:COMPATIBLE_AVEC]-(comp:Produit)-[:APPARTIENT_A]->(cat:Categorie)
RETURN cat.nom AS categorie, comp.id AS produit_id, comp.nom AS nom_produit, r.regle AS critere_compatibilite;
```
*Exemple de résultat retourné :*
```text
 categorie  | produit_id     | nom_produit              | critere_compatibilite
------------+----------------+--------------------------+----------------------
 Carte Mère | P000002 | ASUS ROG STRIX B650E-F GAMING WIFI | Format ATX
```

#### C. Parcours multi-sauts (Configuration complète autour d'un processeur)
```cypher
MATCH (cpu:Produit {id: 'P000001'})-[:COMPATIBLE_AVEC]-(cm:Produit)-[:APPARTIENT_A]->(:Categorie {nom: 'Carte Mère'})
MATCH (cm)-[:COMPATIBLE_AVEC]-(ram:Produit)-[:APPARTIENT_A]->(:Categorie {nom: 'Mémoire RAM'})
RETURN cpu.nom AS processeur, cm.nom AS carte_mere, ram.nom AS ram_compatible;
```