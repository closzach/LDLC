CREATE KEYSPACE IF NOT EXISTS ldlc_analytics
WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};

USE ldlc_analytics;

CREATE TABLE logs_navigation (
    jour DATE,
    bucket INT,
    event_time TIMESTAMP,
    event_id TIMEUUID,
    user_id UUID,
    type_event TEXT,
    produit_id TEXT,
    PRIMARY KEY ((jour, bucket), event_time, event_id)
) WITH CLUSTERING ORDER BY (event_time DESC)
  AND default_time_to_live = 15552000;

CREATE TABLE vues_par_produit_jour (
    produit_id TEXT,
    jour DATE,
    nb_vues COUNTER,
    PRIMARY KEY ((produit_id, jour))
);

CREATE TABLE top_produits_semaine (
    semaine TEXT,
    nb_vues INT,
    produit_id TEXT,
    nom_produit TEXT,
    PRIMARY KEY ((semaine), nb_vues, produit_id)
) WITH CLUSTERING ORDER BY (nb_vues DESC, produit_id ASC);

CREATE TABLE commandes_par_client (
    client_id UUID,
    date_commande TIMESTAMP,
    commande_id UUID,
    montant_total DECIMAL,
    statut TEXT,
    produits LIST<TEXT>,
    PRIMARY KEY ((client_id), date_commande, commande_id)
) WITH CLUSTERING ORDER BY (date_commande DESC);