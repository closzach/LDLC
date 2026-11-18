CREATE CONSTRAINT produit_id_unique IF NOT EXISTS FOR (p:Produit) REQUIRE p.id IS UNIQUE;
CREATE CONSTRAINT client_id_unique IF NOT EXISTS FOR (c:Client) REQUIRE c.id IS UNIQUE;
CREATE CONSTRAINT categorie_nom_unique IF NOT EXISTS FOR (cat:Categorie) REQUIRE cat.nom IS UNIQUE;
CREATE CONSTRAINT marque_nom_unique IF NOT EXISTS FOR (m:Marque) REQUIRE m.nom IS UNIQUE;


CREATE (catCpu:Categorie {nom: 'Processeur'}),
       (catCm:Categorie {nom: 'Carte Mère'}),
       (catBoitier:Categorie {nom: 'Boîtier PC'}),
       (catRam:Categorie {nom: 'Mémoire RAM'}),
       (mAmd:Marque {nom: 'AMD'}),
       (mAsus:Marque {nom: 'ASUS'}),
       (mFractal:Marque {nom: 'Fractal Design'}),
       (mCorsair:Marque {nom: 'Corsair'});

CREATE (pCpu:Produit {id: 'AMD-RYZEN-7-9800X3D', nom: 'AMD Ryzen 7 9800X3D', prix: 529.95, socket: 'AM5'}),
       (pCm:Produit {id: 'ASUS-ROG-X870E', nom: 'ASUS ROG Crosshair X870E', prix: 499.90, socket: 'AM5', format: 'ATX'}),
       (pBoitier:Produit {id: 'FRACTAL-NORTH-XL', nom: 'Fractal Design North XL', prix: 189.95, format_supporte: 'ATX'}),
       (pRam:Produit {id: 'CORSAIR-DDR5-32G', nom: 'Corsair Vengeance 32Go DDR5', prix: 129.90, type: 'DDR5'});

CREATE (c1:Client {id: '550e8400-e29b-41d4-a716-446655440000', nom: 'Alice Martin'}),
       (c2:Client {id: '6ba7b810-9dad-11d1-80b4-00c04fd430c8', nom: 'Lucas Bernard'});


CREATE (pCpu)-[:APPARTIENT_A]->(catCpu),
       (pCpu)-[:DE_MARQUE]->(mAmd),
       (pCm)-[:APPARTIENT_A]->(catCm),
       (pCm)-[:DE_MARQUE]->(mAsus),
       (pBoitier)-[:APPARTIENT_A]->(catBoitier),
       (pBoitier)-[:DE_MARQUE]->(mFractal),
       (pRam)-[:APPARTIENT_A]->(catRam),
       (pRam)-[:DE_MARQUE]->(mCorsair);

CREATE (pCpu)-[:COMPATIBLE_AVEC {regle: 'Socket AM5', verifie: true}]->(pCm),
       (pCm)-[:COMPATIBLE_AVEC {regle: 'Format ATX', verifie: true}]->(pBoitier),
       (pCm)-[:COMPATIBLE_AVEC {regle: 'Support DDR5', verifie: true}]->(pRam);

CREATE (c1)-[:A_ACHETE {date: '2026-11-15', quantite: 1}]->(pCpu),
       (c1)-[:A_ACHETE {date: '2026-11-15', quantite: 1}]->(pCm),
       (c1)-[:A_ACHETE {date: '2026-11-15', quantite: 1}]->(pRam),
       (c2)-[:A_ACHETE {date: '2026-11-16', quantite: 1}]->(pCpu),
       (c2)-[:A_ACHETE {date: '2026-11-16', quantite: 1}]->(pCm);


MATCH (p1:Produit {id: 'AMD-RYZEN-7-9800X3D'})<-[:A_ACHETE]-(c:Client)-[:A_ACHETE]->(p2:Produit)
WHERE p1 <> p2
RETURN p2.id AS produit_recommande, p2.nom AS nom, COUNT(DISTINCT c) AS nb_acheteurs_communs
ORDER BY nb_acheteurs_communs DESC
LIMIT 5;

MATCH (b:Produit {id: 'FRACTAL-NORTH-XL'})-[r:COMPATIBLE_AVEC]-(comp:Produit)-[:APPARTIENT_A]->(cat:Categorie)
RETURN cat.nom AS categorie, comp.id AS produit_id, comp.nom AS nom_produit, r.regle AS critere_compatibilite;