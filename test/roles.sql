/*
 * Single source of truth for test-only role names. Roles are global (not
 * schema- or session-scoped), so this can't be a table constant -- it's a
 * psql variable, \i'd from any session that needs to reference the name:
 * test/install/load.sql, and test/helpers/create.sql (via
 * test/helpers/deps.sql) for the *.sql files under test/sql/.
 */
\set test_role test_role

-- test/install/load.sql only -- see its own comment.
\set installer_role test_factory_installer

/*
 * test/sql/security.sql only -- see its own comment. Deliberately not
 * test_role: that role is set up by test/helpers/create.sql for other
 * files, and this one exists specifically to have no setup beyond
 * Postgres' own role defaults.
 */
\set bare_role test_factory_bare_user

-- vi: expandtab ts=2 sw=2
