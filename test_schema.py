#!/usr/bin/env python3
"""Test du schéma corrigé"""

import psycopg2
import json
import sys

def test_schema():
    """Teste que toutes les colonnes nécessaires existent"""
    try:
        conn = psycopg2.connect(
            host="localhost",
            database="synapse",
            user="synapse",
            password="synapse123"
        )
        cur = conn.cursor()
        
        # Test 1: Vérifier les colonnes de jobs
        print("🧪 Test 1: Vérification des colonnes de 'jobs'...")
        required_columns = [
            'job_id', 'client_id', 'model_name', 'input_data',
            'status', 'priority', 'created_at', 'submitted_at',
            'estimated_cost', 'assigned_node'
        ]
        
        cur.execute("""
            SELECT column_name 
            FROM information_schema.columns 
            WHERE table_name = 'jobs'
        """)
        
        existing_columns = [row[0] for row in cur.fetchall()]
        missing = set(required_columns) - set(existing_columns)
        
        if missing:
            print(f"❌ Colonnes manquantes: {missing}")
            return False
        else:
            print("✅ Toutes les colonnes requises sont présentes")
        
        # Test 2: Insérer un job de test
        print("\n🧪 Test 2: Insertion d'un job de test...")
        try:
            cur.execute("""
                INSERT INTO jobs (
                    job_id, client_id, model_name, input_data, 
                    status, priority, estimated_cost
                ) VALUES (
                    'test_job_schema', 'test-client', 'test-model',
                    '{"test": "data"}', 'queued', 2, 0.02
                )
                ON CONFLICT (job_id) DO UPDATE 
                SET priority = 2, updated_at = CURRENT_TIMESTAMP
            """)
            conn.commit()
            print("✅ Insertion réussie")
        except Exception as e:
            print(f"❌ Erreur insertion: {e}")
            return False
        
        # Test 3: Requête sans COALESCE
        print("\n🧪 Test 3: Requête des jobs en attente...")
        try:
            cur.execute("""
                SELECT job_id, client_id, priority
                FROM jobs
                WHERE status = 'queued'
                ORDER BY priority DESC, created_at ASC
                LIMIT 5
            """)
            
            jobs = cur.fetchall()
            print(f"✅ {len(jobs)} jobs trouvés")
            for job in jobs:
                print(f"   - {job[0]} (client: {job[1]}, priorité: {job[2]})")
        except Exception as e:
            print(f"❌ Erreur requête: {e}")
            return False
        
        cur.close()
        conn.close()
        return True
        
    except Exception as e:
        print(f"❌ Erreur connexion: {e}")
        return False

if __name__ == "__main__":
    success = test_schema()
    print("\n" + "="*50)
    if success:
        print("🎉 Tous les tests passent! Le schéma est correct.")
    else:
        print("❌ Des erreurs ont été détectées.")
    sys.exit(0 if success else 1)
