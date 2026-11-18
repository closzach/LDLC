CREATE CONSTRAINT produit_id_unique IF NOT EXISTS FOR (p:Produit) REQUIRE p.id IS UNIQUE;
CREATE CONSTRAINT client_id_unique IF NOT EXISTS FOR (c:Client) REQUIRE c.id IS UNIQUE;
CREATE CONSTRAINT categorie_nom_unique IF NOT EXISTS FOR (cat:Categorie) REQUIRE cat.nom IS UNIQUE;
CREATE CONSTRAINT marque_nom_unique IF NOT EXISTS FOR (m:Marque) REQUIRE m.nom IS UNIQUE;


MERGE (catCpu:Categorie {nom: 'Processeur'})
MERGE (catCm:Categorie {nom: 'Carte Mère'})
MERGE (catBoitier:Categorie {nom: 'Boîtier PC'})
MERGE (catRam:Categorie {nom: 'Mémoire RAM'})
MERGE (mAmd:Marque {nom: 'AMD'})
MERGE (mAsus:Marque {nom: 'ASUS'})
MERGE (mFractal:Marque {nom: 'Fractal Design'})
MERGE (mCorsair:Marque {nom: 'Corsair'});

MERGE (pCpu:Produit {id: 'P000001'})
SET pCpu.nom = 'AMD Ryzen 7 7800X3D', pCpu.prix = 449.90, pCpu.socket = 'AM5'
MERGE (pCm:Produit {id: 'P000002'})
SET pCm.nom = 'ASUS ROG STRIX B650E-F GAMING WIFI', pCm.prix = 289.90, pCm.socket = 'AM5', pCm.format = 'ATX'
MERGE (pBoitier:Produit {id: 'P000005'})
SET pBoitier.nom = 'Fractal Design North', pBoitier.prix = 149.90, pBoitier.format_supporte = 'ATX'
MERGE (pRam:Produit {id: 'P000003'})
SET pRam.nom = 'Corsair Vengeance DDR5 32 Go (2 x 16 Go) 6000 MHz', pRam.prix = 119.90, pRam.type = 'DDR5';

MERGE (c1:Client {id: '550e8400-e29b-41d4-a716-446655440000'})
SET c1.nom = 'Alice Martin'
MERGE (c2:Client {id: '6ba7b810-9dad-11d1-80b4-00c04fd430c8'})
SET c2.nom = 'Lucas Bernard';


MATCH (p:Produit {id: 'P000001'}), (c:Categorie {nom: 'Processeur'}), (m:Marque {nom: 'AMD'})
MERGE (p)-[:APPARTIENT_A]->(c)
MERGE (p)-[:DE_MARQUE]->(m);

MATCH (p:Produit {id: 'P000002'}), (c:Categorie {nom: 'Carte Mère'}), (m:Marque {nom: 'ASUS'})
MERGE (p)-[:APPARTIENT_A]->(c)
MERGE (p)-[:DE_MARQUE]->(m);

MATCH (p:Produit {id: 'P000005'}), (c:Categorie {nom: 'Boîtier PC'}), (m:Marque {nom: 'Fractal Design'})
MERGE (p)-[:APPARTIENT_A]->(c)
MERGE (p)-[:DE_MARQUE]->(m);

MATCH (p:Produit {id: 'P000003'}), (c:Categorie {nom: 'Mémoire RAM'}), (m:Marque {nom: 'Corsair'})
MERGE (p)-[:APPARTIENT_A]->(c)
MERGE (p)-[:DE_MARQUE]->(m);

MATCH (p1:Produit {id: 'P000001'}), (p2:Produit {id: 'P000002'})
MERGE (p1)-[:COMPATIBLE_AVEC {regle: 'Socket AM5', verifie: true}]->(p2);

MATCH (p1:Produit {id: 'P000002'}), (p2:Produit {id: 'P000005'})
MERGE (p1)-[:COMPATIBLE_AVEC {regle: 'Format ATX', verifie: true}]->(p2);

MATCH (p1:Produit {id: 'P000002'}), (p2:Produit {id: 'P000003'})
MERGE (p1)-[:COMPATIBLE_AVEC {regle: 'Support DDR5', verifie: true}]->(p2);

MATCH (c:Client {id: '550e8400-e29b-41d4-a716-446655440000'}), (p:Produit)
WHERE p.id IN ['P000001', 'P000002', 'P000003']
MERGE (c)-[:A_ACHETE {date: '2026-11-15', quantite: 1}]->(p);

MATCH (c:Client {id: '6ba7b810-9dad-11d1-80b4-00c04fd430c8'}), (p:Produit)
WHERE p.id IN ['P000001', 'P000002']
MERGE (c)-[:A_ACHETE {date: '2026-11-16', quantite: 1}]->(p);


MATCH (p1:Produit {id: 'P000001'})<-[:A_ACHETE]-(c:Client)-[:A_ACHETE]->(p2:Produit)
WHERE p1 <> p2
RETURN p2.id AS produit_recommande, p2.nom AS nom, COUNT(DISTINCT c) AS nb_acheteurs_communs
ORDER BY nb_acheteurs_communs DESC
LIMIT 5;

MATCH (b:Produit {id: 'P000005'})-[r:COMPATIBLE_AVEC]-(comp:Produit)-[:APPARTIENT_A]->(cat:Categorie)
RETURN cat.nom AS categorie, comp.id AS produit_id, comp.nom AS nom_produit, r.regle AS critere_compatibilite;