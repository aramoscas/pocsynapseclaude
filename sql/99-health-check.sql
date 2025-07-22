-- 99-health-check.sql
-- Script de vérification de santé exécuté après l'initialisation

\echo 'Performing database health check...'

DO $$
DECLARE
    table_count INTEGER;
    view_count INTEGER;
    function_count INTEGER;
BEGIN
    -- Compter les tables
    SELECT COUNT(*) INTO table_count
    FROM information_schema.tables
    WHERE table_schema = 'public'
    AND table_type = 'BASE TABLE';
    
    -- Compter les vues
    SELECT COUNT(*) INTO view_count
    FROM information_schema.views
    WHERE table_schema = 'public';
    
    -- Compter les fonctions
    SELECT COUNT(*) INTO function_count
    FROM information_schema.routines
    WHERE routine_schema = 'public'
    AND routine_type = 'FUNCTION';
    
    RAISE NOTICE 'Database health check:';
    RAISE NOTICE '  Tables: %', table_count;
    RAISE NOTICE '  Views: %', view_count;
    RAISE NOTICE '  Functions: %', function_count;
    
    IF table_count >= 7 AND view_count >= 4 AND function_count >= 4 THEN
        RAISE NOTICE 'Health check: PASSED ✓';
    ELSE
        RAISE WARNING 'Health check: FAILED - Some objects may be missing';
    END IF;
END $$;

\echo 'Health check complete!'
