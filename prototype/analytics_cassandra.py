from datetime import date, datetime
import uuid
from cassandra.cluster import Cluster
from cassandra.util import uuid_from_time

cluster = Cluster(['127.0.0.1'], port=9042)
session = cluster.connect('ldlc_analytics')

insert_log_stmt = session.prepare("""
    INSERT INTO logs_navigation (jour, bucket, event_time, event_id, user_id, type_event, produit_id)
    VALUES (?, ?, ?, ?, ?, ?, ?)
""")

inc_vue_stmt = session.prepare("""
    UPDATE vues_par_produit_jour SET nb_vues = nb_vues + 1
    WHERE produit_id = ? AND jour = ?
""")

get_vues_stmt = session.prepare("""
    SELECT nb_vues FROM vues_par_produit_jour WHERE produit_id = ? AND jour = ?
""")

get_commandes_stmt = session.prepare("""
    SELECT commande_id, date_commande, montant_total, statut, produits
    FROM commandes_par_client WHERE client_id = ? LIMIT 10
""")

def enregistrer_vue_produit(user_id: uuid.UUID, produit_id: str):
    maintenant = datetime.utcnow()
    aujourd_hui = date.today()
    bucket = maintenant.hour
    event_id = uuid_from_time(maintenant)

    session.execute(insert_log_stmt, (
        aujourd_hui, bucket, maintenant, event_id, user_id, 'vue_produit', produit_id
    ))
    session.execute(inc_vue_stmt, (produit_id, aujourd_hui))

def lire_vues_jour(produit_id: str) -> int:
    row = session.execute(get_vues_stmt, (produit_id, date.today())).one()
    return row.nb_vues if row else 0

if __name__ == "__main__":
    test_user = uuid.uuid4()
    enregistrer_vue_produit(test_user, "P000001")
    print(f"Vues aujourd'hui : {lire_vues_jour('P000001')}")
