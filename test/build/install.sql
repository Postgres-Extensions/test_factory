\set ECHO none
\i test/helpers/psql.sql

/*
 * Extension packaging checks (dependency declarations, clean
 * install/uninstall) -- not test_factory's business logic, which is
 * test/sql/base.sql and test/sql/pgtap.sql's job. Compare
 * test/build/syntax.sql: that one runs the raw SQL files directly to catch
 * syntax errors; this one goes through a real CREATE EXTENSION to catch
 * packaging errors instead.
 *
 * test/build runs in an isolated database with none of the main suite's
 * pgTAP/role setup, so this is plain SQL, relying on pg_regress's classic
 * expected-output diffing. ON_ERROR_STOP is off since the bare CREATE
 * EXTENSION below is expected to fail (each top-level statement is its own
 * autocommit transaction, so that doesn't touch anything after it).
 * VERBOSITY is knocked down from psql.sql's "verbose" to "default" since the
 * verbose LOCATION line differs across PG majors.
 */
\set ON_ERROR_STOP false
\set VERBOSITY default

SET client_min_messages = WARNING;

-- pgtap is test_factory_pgtap's other declared dependency; install it first
-- so the bare-create failure below isolates on test_factory specifically.
CREATE EXTENSION IF NOT EXISTS pgtap;

-- Clean slate; non-CASCADE so we'd notice if something was already there.
DROP EXTENSION IF EXISTS test_factory_pgtap;
DROP EXTENSION IF EXISTS test_factory;

/*
 * A bare (non-CASCADE) create must fail: test_factory isn't installed yet.
 * Proves test_factory_pgtap.control's "requires = 'pgtap, test_factory'" is
 * real and enforced, not just documentation. IF THIS SUCCEEDS INSTEAD (e.g.
 * with a "schema tf does not exist" error later), the dependency
 * declaration is missing/broken -- check test_factory_pgtap.control.
 */
CREATE EXTENSION test_factory_pgtap;

-- CASCADE should pull test_factory in automatically.
CREATE EXTENSION test_factory_pgtap CASCADE;

-- tf.tap(text, text) should exist after install; the cast errors visibly if not.
SELECT 'tf.tap(text, text)'::regprocedure;

-- Clean removal: a bare (non-CASCADE) drop must not error.
DROP EXTENSION test_factory_pgtap;
DROP EXTENSION test_factory;

-- vi: expandtab ts=2 sw=2
