// =====================================================================
// LOT 1 - CATALOGUE PRODUITS (MongoDB)
// =====================================================================

// ---------------------------------------------------------------------
// 1. Afficher une fiche produit
// ---------------------------------------------------------------------
db.Lot1_Produits.findOne({ _id: "P000001" });


// ---------------------------------------------------------------------
// 2. Lister les processeurs, du moins cher au plus cher
// ---------------------------------------------------------------------
db.Lot1_Produits.find(
  { categorie: "composants", sous_categorie: "processeur" },
  { nom: 1, "marque.nom": 1, "prix.montant": 1 }   // projection : on ne renvoie que ces champs
).sort({ "prix.montant": 1 });


// ---------------------------------------------------------------------
// 3. Filtrer sur une caractéristique : les cartes mères au socket AM5
// ---------------------------------------------------------------------
db.Lot1_Produits.find({
  categorie: "composants",
  sous_categorie: "carte_mere",
  caracteristiques: { $elemMatch: { cle: "socket", valeur: "AM5" } }
});


// ---------------------------------------------------------------------
// 4. Filtrer sur plusieurs caractéristiques : cartes mères AM5 ET DDR5
// ---------------------------------------------------------------------
db.Lot1_Produits.find({
  sous_categorie: "carte_mere",
  $and: [
    { caracteristiques: { $elemMatch: { cle: "socket", valeur: "AM5" } } },
    { caracteristiques: { $elemMatch: { cle: "type_memoire", valeur: "DDR5" } } }
  ]
});


// ---------------------------------------------------------------------
// 5. Filtre numérique : produits avec au moins 8 cœurs
// ---------------------------------------------------------------------
db.Lot1_Produits.find({
  caracteristiques: { $elemMatch: { cle: "coeurs", valeur: { $gte: 8 } } }
});


// ---------------------------------------------------------------------
// 6. Tous les produits d'une marque (ici ASUS = B002)
// ---------------------------------------------------------------------
db.Lot1_Produits.find({ "marque.id": "B002" }, { nom: 1, categorie: 1 });


// ---------------------------------------------------------------------
// 7. Les avis d'un produit, du plus récent au plus ancien (page 1 puis 2)
//    Les 5 derniers avis sont déjà dans la fiche produit (derniers_avis).
// ---------------------------------------------------------------------
db.Lot1_Avis.find({ id_produit: "P000001" }).sort({ date_creation: -1 }).limit(5);
db.Lot1_Avis.find({ id_produit: "P000001" }).sort({ date_creation: -1 }).skip(5).limit(5);


// ---------------------------------------------------------------------
// 8. Les produits compatibles avec une fiche (références + $lookup)
// ---------------------------------------------------------------------
db.Lot1_Produits.aggregate([
  { $match: { _id: "P000002" } },
  { $lookup: {
      from: "Lot1_Produits",
      localField: "compatible_avec",
      foreignField: "_id",
      as: "produits_compatibles"
  } },
  { $project: {
      nom: 1,
      "produits_compatibles._id": 1,
      "produits_compatibles.nom": 1,
      "produits_compatibles.prix": 1
  } }
]);


// ---------------------------------------------------------------------
// 9. Top 5 des produits les mieux notés
//    La moyenne n'est pas stockée : on la calcule avec somme / nombre.
// ---------------------------------------------------------------------
db.Lot1_Produits.aggregate([
  { $match: { "resume_avis.nombre": { $gt: 0 } } },
  { $project: {
      nom: 1,
      nombre_avis: "$resume_avis.nombre",
      moyenne: { $round: [{ $divide: ["$resume_avis.somme", "$resume_avis.nombre"] }, 2] }
  } },
  { $sort: { moyenne: -1, nombre_avis: -1 } },
  { $limit: 5 }
]);


// ---------------------------------------------------------------------
// 10. Nombre de produits par catégorie
// ---------------------------------------------------------------------
db.Lot1_Produits.aggregate([
  { $group: { _id: "$categorie", nombre_produits: { $sum: 1 } } },
  { $sort: { nombre_produits: -1 } }
]);


// ---------------------------------------------------------------------
// 11. Vérifier qu'un index est bien utilisé 
// ---------------------------------------------------------------------
db.Lot1_Produits.find(
  { categorie: "composants", sous_categorie: "processeur" }
).sort({ "prix.montant": 1 }).explain("executionStats");


// ---------------------------------------------------------------------
// 12. [ÉCRITURE] Ajouter un nouvel avis
//     Deux étapes : (a) on écrit l'avis dans "avis",
//     (b) on met à jour la fiche produit : résumé + 5 derniers avis.
//     $push + $position:0 + $slice:5 => on ajoute en tête et on garde 5 max.
//     ATTENTION : ne l'exécute qu'une fois, sinon l'avis est compté deux fois.
// ---------------------------------------------------------------------
const idNouvelAvis = new ObjectId();
const maintenant = new Date();

db.Lot1_Avis.insertOne({
  _id: idNouvelAvis,
  id_produit: "P000001",
  id_client: "C000021",
  note: 4,
  titre: "Très bon processeur",
  commentaire: "Très satisfait, un peu cher.",
  achat_verifie: true,
  date_creation: maintenant
});

db.Lot1_Produits.updateOne(
  { _id: "P000001" },
  {
    $push: {
      derniers_avis: {
        $each: [{ id_avis: idNouvelAvis, note: 4, titre: "Très bon processeur", date: maintenant }],
        $position: 0,
        $slice: 5
      }
    },
    $inc: { "resume_avis.nombre": 1, "resume_avis.somme": 4 },
    $set: { date_modification: maintenant }
  }
);


// ---------------------------------------------------------------------
// 13. [ÉCRITURE] Ajouter une caractéristique SANS migration
//     Les autres produits ne sont pas touchés, rien à modifier ailleurs.
// ---------------------------------------------------------------------
db.Lot1_Produits.updateOne(
  { _id: "P000001" },
  { $push: { caracteristiques: { cle: "technologie_gravure", valeur: 5, unite: "nm" } } }
);


// ---------------------------------------------------------------------
// 14. [ÉCRITURE] Ajouter une NOUVELLE CATÉGORIE sans migration
//     Aucune table à créer, aucun schéma à modifier : on insère le document.
// ---------------------------------------------------------------------
db.Lot1_Produits.insertOne({
  _id: "P000099",
  version_schema: 1,
  nom: "Fauteuil gaming exemple",
  categorie: "mobilier_gaming",
  sous_categorie: "fauteuil",
  marque: { id: "B002", nom: "ASUS" },
  prix: { montant: 299.0, devise: "EUR" },
  description: "Produit de test pour montrer l'ajout d'une nouvelle catégorie.",
  caracteristiques: [
    { cle: "charge_max", valeur: 120, unite: "kg" },
    { cle: "materiau", valeur: "simili cuir" }
  ],
  compatible_avec: [],
  resume_avis: { nombre: 0, somme: 0 },
  derniers_avis: [],
  date_creation: new Date(),
  date_modification: new Date()
});

// ---------------------------------------------------------------------
// 15. [ÉCRITURE] Déclarer une compatibilité SYMÉTRIQUE (des deux côtés)
//     $addToSet = "ajoute si absent" : on peut relancer sans créer de doublon.
//     Exemple : le boîtier (P000005) peut accueillir le SSD (P000006).
// ---------------------------------------------------------------------
db.Lot1_Produits.updateOne({ _id: "P000005" }, { $addToSet: { compatible_avec: "P000006" } });
db.Lot1_Produits.updateOne({ _id: "P000006" }, { $addToSet: { compatible_avec: "P000005" } });
