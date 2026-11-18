# Lot 1 — Catalogue produits (MongoDB)

> Les données de démonstration (produits, prix, avis) sont fictives et indicatives. Elles servent uniquement à illustrer le modèle.

## 1. Besoin et contraintes

Le catalogue LDLC compte environ 27 000 références issues de 600 marques. Trois contraintes guident la conception :

- **Schémas variables** : un processeur, une souris et un logiciel n'ont pas les mêmes attributs.
- **Évolution sans migration** : l'ajout d'un attribut ou d'une catégorie ne doit pas modifier la structure de la base.
- **Lecture intensive, écriture rare** : une fiche est consultée très souvent et modifiée peu. Elle contient des sous-éléments : spécifications techniques, avis clients, produits compatibles.

## 2. Choix technologique : MongoDB

MongoDB est une base orientée documents : une collection regroupe des documents JSON dont la structure peut varier d'un document à l'autre.

**Justification**

- Une fiche produit complète tient dans un seul document, lisible en une seule requête, sans jointure.
- Le schéma flexible permet de faire cohabiter des produits de formes différentes dans une même collection.
- Les tableaux et sous-documents natifs accueillent spécifications, avis et compatibilités.
- Ajouter un attribut revient à modifier un document, ajouter une catégorie revient à insérer un document.

**Technologies écartées**

| Technologie | Raison |
|---|---|
| SQL (existant) | Schéma rigide : colonnes vides ou une table par catégorie, et chaque nouvel attribut impose une migration. |
| Cassandra | Modèle construit requête par requête, peu adapté au filtrage libre sur n'importe quel attribut. Réservée aux logs et à l'analytique (Lot 3). |
| Redis | Clé-valeur en mémoire, sans filtres riches. Adapté au panier et aux sessions (Lot 2). |
| Neo4j | Pensé pour le parcours de relations (Lot 4), pas pour stocker des fiches détaillées. |

## 3. Modèle de données

### Collections

| Collection | Rôle | Volume estimé |
|---|---|---|
| `Lot1_Produits` | Une fiche par produit, toutes catégories confondues | ~27 000 |
| `Lot1_Avis` | Un document par avis client | Illimité |
| `Lot1_Marques` | Une fiche par marque | ~600 |

Tous les produits sont regroupés dans **une seule collection**, avec un champ `categorie`. Une collection par catégorie obligerait à interroger plusieurs collections pour une recherche globale, et chaque nouvelle catégorie nécessiterait de nouvelles collections et de nouveaux index, ce qui constituerait une migration.

### Identifiants

`_id` d'un produit est l'identifiant produit commun à tous les lots (`id_produit` dans les autres collections), au format `P000123`. Il est opaque : il ne contient pas la catégorie, et reste stable si le produit change de catégorie. Les marques utilisent le format `B001`, les clients `C000001`.

### Document `Lot1_Produits`

```js
{
  _id: "P000001",
  version_schema: 1,
  nom: "AMD Ryzen 7 7800X3D",
  categorie: "composants",
  sous_categorie: "processeur",
  marque: { id: "B001", nom: "AMD" },
  prix: { montant: 449.90, devise: "EUR" },
  description: "Processeur 8 cœurs avec technologie 3D V-Cache...",
  caracteristiques: [
    { cle: "socket", valeur: "AM5" },
    { cle: "coeurs", valeur: 8 },
    { cle: "frequence_base", valeur: 4.2, unite: "GHz" },
    { cle: "tdp", valeur: 120, unite: "W" }
  ],
  compatible_avec: ["P000002", "P000003"],
  resume_avis: { nombre: 7, somme: 33 },
  derniers_avis: [
    { id_avis: ObjectId("..."), note: 5, titre: "Le meilleur choix", date: ISODate("...") }
    // 5 avis au maximum
  ],
  date_creation: ISODate("..."),
  date_modification: ISODate("...")
}
```

### Document `Lot1_Avis`

```js
{
  _id: ObjectId("..."),
  id_produit: "P000001",
  id_client: "C000001",
  note: 5,
  titre: "Une bête de jeu",
  commentaire: "Les performances en jeu sont impressionnantes...",
  achat_verifie: true,
  date_creation: ISODate("...")
}
```

### Catégories illustrées

| Catégorie | Exemples | Caractéristiques types |
|---|---|---|
| composants | Processeur, carte mère, RAM, GPU, boîtier, SSD | socket, cœurs, chipset, capacité |
| peripheriques | Souris, clavier, écran | dpi, poids, diagonale, fréquence |
| logiciels | Système d'exploitation, bureautique, sécurité | type de licence, plateforme, durée |
| ordinateurs_portables | PC gaming, PC bureautique | diagonale, RAM, stockage, batterie |

Le stock n'est volontairement pas modélisé : il est modifié à chaque commande, ce qui contredit le principe d'une fiche rarement modifiée.

## 4. Embedded vs References

Une information est **imbriquée** (embedded) lorsqu'elle est copiée dans le document, ce qui permet de tout lire en une requête. Elle est **référencée** lorsqu'on ne stocke que son identifiant, ce qui évite la duplication au prix d'une seconde lecture. La règle appliquée : imbriquer ce qui est lu avec la fiche, reste petit et ne grossit pas indéfiniment ; référencer ce qui grossit sans limite ou est partagé.

| Information | Choix | Justification |
|---|---|---|
| Caractéristiques techniques | Embedded | Toujours lues avec la fiche, propres au produit, taille limitée. |
| Résumé des avis (nombre, somme) | Embedded | Deux valeurs affichées dans les listes et sur la fiche. |
| 5 derniers avis | Embedded (copie) | Affichés immédiatement, sans seconde lecture. |
| Ensemble des avis | Reference (`Lot1_Avis`) | Croissance illimitée ; un document MongoDB est limité à 16 Mo. |
| Produits compatibles | Reference (liste d'identifiants) | Évite de dupliquer des fiches entières et leurs mises à jour. |
| Marque | Embedded partiel (`id` + `nom`) | Évite une lecture supplémentaire ; le nom change très rarement. |

## 5. Patterns de modélisation

| Pattern | Problème résolu | Application | Contrepartie |
|---|---|---|---|
| **Polymorphic** | Produits de formes différentes | Une collection unique, champ `categorie` | Nécessite de la discipline sur les clés utilisées |
| **Attribute** | Attributs différents par catégorie, qui imposeraient un index par attribut | `caracteristiques` : liste `{cle, valeur, unite}` couverte par un seul index | Requêtes plus verbeuses (`$elemMatch`) |
| **Subset** | Avis trop nombreux pour être imbriqués | 5 derniers avis dans la fiche, tous les avis dans `Lot1_Avis` | Information stockée à deux endroits |
| **Extended reference** | Lecture supplémentaire pour afficher la marque | `marque: { id, nom }` | Mise à jour des produits si la marque est renommée |
| **Schema versioning** | Évolution future de la structure | Champ `version_schema` | L'application gère plusieurs versions pendant une transition |

## 6. Index

Un index est une structure triée construite à l'avance. Sans index, MongoDB parcourt tous les documents (`COLLSCAN`) ; avec un index, il accède directement aux documents concernés (`IXSCAN`). L'index sur `_id` est créé automatiquement.

| # | Collection | Index | Requête servie |
|---|---|---|---|
| 1 | `Lot1_Produits` | `{ categorie, sous_categorie, prix.montant }` | Parcours du catalogue, filtré par catégorie et trié par prix |
| 2 | `Lot1_Produits` | `{ caracteristiques.cle, caracteristiques.valeur }` | Filtres par attribut (socket, diagonale, etc.) |
| 3 | `Lot1_Produits` | `{ marque.id }` | Produits d'une marque |
| 4 | `Lot1_Avis` | `{ id_produit, date_creation: -1 }` | Avis d'un produit, du plus récent au plus ancien |

**Choix de conception**

- L'index 1 est composé : l'ordre des champs compte. Les champs filtrés par égalité (`categorie`, `sous_categorie`) précèdent le champ trié (`prix.montant`). L'index sert pour la catégorie seule, catégorie + sous-catégorie, ou ces deux champs avec le tri par prix, mais pas pour la sous-catégorie ou le prix seuls.
- L'index 2 est un index sur tableau : une entrée est créée par élément de `caracteristiques`. Associé au pattern Attribute, il remplace des dizaines d'index par attribut. Les requêtes utilisent `$elemMatch` pour que la clé et la valeur soient testées sur le même élément.

**Coût** : chaque index ralentit les écritures et occupe de l'espace, l'index 2 étant le plus volumineux. Ce compromis est cohérent avec un catalogue très lu et peu écrit ; seuls les index correspondant à des requêtes réelles sont créés. L'utilisation d'un index se vérifie avec `explain("executionStats")`.

## 7. Théorème CAP

En cas de partition réseau, un système réparti doit choisir entre cohérence (C) et disponibilité (A). MongoDB est par défaut orienté **CP** : les écritures passent par un serveur principal, et en cas de perte de ce serveur le système attend l'élection d'un nouveau principal plutôt que d'accepter des écritures contradictoires.

Ce choix est adapté au catalogue : les écritures sont rares, quelques secondes d'indisponibilité en écriture sont tolérables, et une donnée incohérente (prix, caractéristique) est plus pénalisante qu'une écriture temporairement refusée. Les lectures, très nombreuses, restent possibles.

## 8. Requêtes types

```js
// Fiche produit (lecture la plus fréquente, index sur _id)
db.Lot1_Produits.findOne({ _id: "P000001" })

// Processeurs, du moins cher au plus cher (index 1)
db.Lot1_Produits.find({ categorie: "composants", sous_categorie: "processeur" })
                .sort({ "prix.montant": 1 })

// Cartes mères AM5 et DDR5 (index 2, pattern Attribute)
db.Lot1_Produits.find({
  sous_categorie: "carte_mere",
  $and: [
    { caracteristiques: { $elemMatch: { cle: "socket", valeur: "AM5" } } },
    { caracteristiques: { $elemMatch: { cle: "type_memoire", valeur: "DDR5" } } }
  ]
})

// Avis d'un produit, du plus récent au plus ancien (index 4)
db.Lot1_Avis.find({ id_produit: "P000001" }).sort({ date_creation: -1 }).limit(5)

// Produits compatibles (références + $lookup)
db.Lot1_Produits.aggregate([
  { $match: { _id: "P000002" } },
  { $lookup: { from: "Lot1_Produits", localField: "compatible_avec",
               foreignField: "_id", as: "produits_compatibles" } }
])

// Ajout d'une caractéristique sans migration
db.Lot1_Produits.updateOne({ _id: "P000001" },
  { $push: { caracteristiques: { cle: "technologie_gravure", valeur: 5, unite: "nm" } } })
```

Le script `Prototype/Lot1_Requetes.js` contient 15 requêtes commentées, dont la moyenne des notes, l'ajout d'un avis (mise à jour du sous-ensemble et du résumé), l'ajout d'une nouvelle catégorie sans migration et la déclaration d'une compatibilité symétrique.

## 9. Limites et compromis

- **Compatibilités dupliquées** : la relation étant symétrique (A↔B), l'identifiant est stocké dans les deux fiches. Deux écritures non atomiques peuvent laisser la base incohérente en cas d'échec intermédiaire ; une transaction ou un contrôle périodique le corrige. Si une liste devenait très longue, une collection dédiée serait préférable.
- **Avis stockés à deux endroits** : l'ajout d'un avis nécessite deux écritures (collection `Lot1_Avis` puis fiche produit), non atomiques sans transaction. C'est le coût du pattern Subset.
- **Moyenne non stockée** : elle est calculée à la lecture (`somme / nombre`).
- **Discipline sur les attributs** : MongoDB ne contrôle pas les types ni les noms de clés. Une valeur stockée en texte (`"8"`) fausserait les comparaisons numériques, et deux clés synonymes (`tdp` / `TDP`) rendraient l'index inopérant. Une validation minimale est proposée (champs obligatoires, types de base) sans restreindre la liste des catégories, afin de ne pas réintroduire de migration.
- **Nom de marque dupliqué** : un renommage impose de mettre à jour tous les produits de la marque.
- **Jointures** : `$lookup` est moins performant qu'une jointure relationnelle ; son usage est limité aux produits compatibles.
- **Hors périmètre** : le stock, la recherche plein texte et les relations complexes entre produits (Lot 4). La compatibilité étant également utile au graphe du Lot 4, MongoDB en reste la source de vérité.
- **Volume** : 27 000 fiches représentent quelques dizaines de Mo. La difficulté est le grand nombre de lectures et la variété des fiches, pas la taille des données.

## 10. Contenu du lot

| Dossier | Fichier | Contenu |
|---|---|---|
| `Docs/` | `Lot1_Catalogue_Produits.md` | Ce document |
| `Schémas/` | `Lot1_Produits.json` | Collection `Lot1_Produits` : 15 produits, 4 catégories |
| `Schémas/` | `Lot1_Avis.json` | Collection `Lot1_Avis` : 33 avis |
| `Schémas/` | `Lot1_Marques.json` | Collection `Lot1_Marques` : 13 marques |
| `Schémas/` | `Lot1_Index.js` | Index et validation des collections |
| `Prototype/` | `Lot1_Requetes.js` | 15 requêtes types commentées |

**Mise en œuvre** : dans MongoDB Atlas / Compass, créer la base `ldlc` et les trois collections, importer chaque fichier JSON dans sa collection (type JSON), exécuter `Lot1_Index.js`, puis les requêtes de `Lot1_Requetes.js` dans la console mongosh.
