# Version temporaire qui commente l'insertion PostgreSQL problématique
# Cherchez ces lignes dans votre main.py et commentez-les temporairement:

# if postgres_pool:
#     try:
#         async with postgres_pool.acquire() as conn:
#             await conn.execute("""
#                 INSERT INTO jobs (id, model_name, client_id, status, submitted_at, priority)
#                 VALUES ($1, $2, $3, $4, $5, $6)
#             """, job_id, request.model_name, x_client_id, "pending", submitted_at, request.priority)
#     except Exception as e:
#         logger.error(f"Error logging to PostgreSQL: {e}")
#         # Continue sans PostgreSQL
