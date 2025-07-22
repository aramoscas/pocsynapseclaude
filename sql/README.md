# Scripts d'initialisation PostgreSQL

Ce dossier contient les scripts d'initialisation automatique de PostgreSQL pour SynapseGrid.

## Scripts

- `00-init-synapsegrid.sql` : Initialisation principale (tables, vues, fonctions)
- `99-health-check.sql` : Vérification de santé après initialisation

## Fonctionnement

Ces scripts sont automatiquement exécutés par PostgreSQL au démarrage si :
1. Le volume de données est vide (première initialisation)
2. Les scripts sont dans `/docker-entrypoint-initdb.d/`

Les scripts sont exécutés dans l'ordre alphabétique.

## Pour réinitialiser la base de données

```bash
# Arrêter et supprimer le volume PostgreSQL
docker-compose down -v postgres

# Redémarrer PostgreSQL (les scripts s'exécuteront automatiquement)
docker-compose up -d postgres

# Vérifier les logs
docker-compose logs postgres
```

## Pour ajouter de nouveaux scripts

Nommez-les avec un préfixe numérique pour contrôler l'ordre d'exécution :
- `01-xxx.sql` : Après l'init principale
- `50-xxx.sql` : Au milieu
- `98-xxx.sql` : Avant le health check
