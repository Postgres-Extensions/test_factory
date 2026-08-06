\set ECHO none
\i test/helpers/psql.sql

/*
 * Runs the versioned SQL files under sql/ directly via \i (not CREATE
 * EXTENSION), so a genuine syntax error is reported clearly instead of
 * hiding behind a generic CREATE EXTENSION failure. Compare
 * test/build/install.sql: that one tests packaging (dependency
 * declarations, clean install/uninstall) via a real CREATE EXTENSION; this
 * one tests raw SQL syntax by deliberately bypassing it.
 *
 * Wrapped in one transaction, rolled back at the end, so nothing persists
 * whether this runs under pg_regress or ad hoc locally. ON_ERROR_ROLLBACK
 * savepoints each statement, so the two expected errors below
 * (pg_extension_config_dump() requires a real CREATE/ALTER EXTENSION
 * context; harmless here) don't abort the rest of the file -- a real syntax
 * error later still shows up on its own. VERBOSITY is knocked down from
 * psql.sql's "verbose" to "default" since the verbose LOCATION line differs
 * across PG majors. \o /dev/null hides the one row of query output each
 * file prints (current_user, which varies by environment) while leaving
 * NOTICE/WARNING/ERROR visible.
 */
\set ON_ERROR_STOP false
\set ON_ERROR_ROLLBACK on
\set VERBOSITY default
\o /dev/null

/*
 * Resolve the CURRENT versioned filenames rather than hardcoding a version
 * number here -- pg_available_extensions reads the .control files `make
 * install` (test-build's own dependency) just put in place, so this always
 * matches whatever's actually being built, with nothing to remember to bump
 * by hand alongside a real version bump.
 */
SELECT default_version FROM pg_available_extensions WHERE name = 'test_factory' \gset tf_
SELECT default_version FROM pg_available_extensions WHERE name = 'test_factory_pgtap' \gset tfp_

BEGIN;

-- test_factory first: test_factory_pgtap's file needs its "tf" schema/role.
\i sql/test_factory--:tf_default_version.sql
\i sql/test_factory_pgtap--:tfp_default_version.sql

ROLLBACK;

-- vi: expandtab ts=2 sw=2
