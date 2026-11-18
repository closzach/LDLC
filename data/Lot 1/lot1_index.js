// =====================================================================
// LOT 1 - CATALOGUE PRODUITS (MongoDB)
// Script 1/2 : index et validation (optionnelle)
// =====================================================================

// ---------------------------------------------------------------------
// BLOC 1 : les 3 index de la collection "Lot1_Produits"
// ---------------------------------------------------------------------

// Index 1 : parcourir le catalogue (catégorie -> sous-catégorie -> prix)
db.Lot1_Produits.createIndex(
  { categorie: 1, sous_categorie: 1, "prix.montant": 1 },
  { name: "idx_categorie_sous_categorie_prix" }
);

// Index 2 : filtrer sur n'importe quelle caractéristique (socket, dpi, ram...)
db.Lot1_Produits.createIndex(
  { "caracteristiques.cle": 1, "caracteristiques.valeur": 1 },
  { name: "idx_caracteristiques" }
);

// Index 3 : retrouver tous les produits d'une marque
db.Lot1_Produits.createIndex(
  { "marque.id": 1 },
  { name: "idx_marque" }
);


// ---------------------------------------------------------------------
// BLOC 2 : l'index de la collection "avis"
// ---------------------------------------------------------------------

// Index 4 : les avis d'un produit, du plus récent au plus ancien
db.Lot1_Avis.createIndex(
  { id_produit: 1, date_creation: -1 },
  { name: "idx_avis_produit_date" }
);


// ---------------------------------------------------------------------
// BLOC 3 : vérifier que les index existent
// (l'index sur _id est créé automatiquement par MongoDB)
// ---------------------------------------------------------------------
db.Lot1_Produits.getIndexes();
db.Lot1_Avis.getIndexes();


// ---------------------------------------------------------------------
// BLOC 4 (OPTIONNEL) : règles de validation minimales sur "produits"
//
// Idée : la flexibilité ne veut pas dire "n'importe quoi".
// On impose seulement un socle commun à toutes les fiches.
// On ne limite VOLONTAIREMENT PAS la liste des catégories : sinon,
// ajouter une nouvelle catégorie demanderait de modifier la règle
// ---------------------------------------------------------------------
db.runCommand({
  collMod: "Lot1_Produits",
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["_id", "version_schema", "nom", "categorie", "prix", "caracteristiques"],
      properties: {
        _id: { bsonType: "string", pattern: "^P[0-9]{6}$" },
        version_schema: { bsonType: ["int", "long", "double"] },
        nom: { bsonType: "string" },
        categorie: { bsonType: "string" },
        prix: {
          bsonType: "object",
          required: ["montant", "devise"],
          properties: {
            montant: { bsonType: ["double", "int", "long", "decimal"], minimum: 0 },
            devise: { bsonType: "string" }
          }
        },
        caracteristiques: {
          bsonType: "array",
          items: {
            bsonType: "object",
            required: ["cle", "valeur"],
            properties: { cle: { bsonType: "string" } }
          }
        }
      }
    }
  },
  validationLevel: "moderate"
});
