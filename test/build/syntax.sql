\set ECHO none
\i test/helpers/psql.sql

/*
 * Runs the actual source files under sql/ (test_factory.sql,
 * test_factory_pgtap.sql -- the ones a developer edits) directly via \i
 * (not CREATE EXTENSION), so a genuine syntax error is reported clearly
 * instead of hiding behind a generic CREATE EXTENSION failure. Deliberately
 * NOT the pgxntool-generated, version-suffixed copies of these same files
 * (verified byte-identical except for one auto-generated "DO NOT EDIT"
 * header line) that exist purely for PGXN packaging -- running those here
 * would just add a version-number-resolution step for zero benefit, since
 * it's the same content either way. (This comment deliberately never
 * spells out that generated filename pattern with a literal wildcard glob
 * right after a slash -- slash-star opens a comment, and Postgres nests
 * block comments, so an unbalanced extra opener here would silently swallow
 * the rest of this file. Hit this for real writing this comment.)
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

BEGIN;

-- test_factory first: test_factory_pgtap's file needs its "tf" schema/role.
\i sql/test_factory.sql
\i sql/test_factory_pgtap.sql

ROLLBACK;

-- vi: expandtab ts=2 sw=2
