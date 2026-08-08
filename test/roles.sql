/*
 * Single source of truth for test-only role names. Roles are global (not
 * schema- or session-scoped), so this can't be a table constant -- it's a
 * psql variable, \i'd from any session that needs to reference the name:
 * test/install/load.sql, and test/helpers/create.sql (via
 * test/helpers/deps.sql) for the *.sql files under test/sql/.
 */
\set test_role test_role

-- vi: expandtab ts=2 sw=2
