\set ECHO none
\i test/helpers/psql.sql

/*
 * Run the raw, generated versioned SQL install scripts directly (\i, NOT
 * CREATE EXTENSION) against a fresh database. This is a deliberately simple
 * test: its whole point is that a genuine SQL syntax error anywhere in
 * either file shows up immediately and clearly, instead of being obscured
 * behind a generic CREATE EXTENSION failure the way test/build/install.sql
 * (or a normal `make install`) would report it.
 *
 * KNOWN / EXPECTED ERRORS BAKED INTO THIS TEST'S EXPECTED OUTPUT
 * (verified locally; these are not bugs -- see explanation before each
 * occurrence below):
 *
 * 1. Two "pg_extension_config_dump() can only be called from an SQL script
 *    executed by CREATE EXTENSION" errors (both from test_factory's file).
 *    That function always errors when its containing script is \i'd
 *    directly rather than run by CREATE/ALTER EXTENSION, regardless of
 *    whether the file's SQL is otherwise valid.
 *
 * 2. One "zero-length delimited identifier" error from `SET ROLE ""` near
 *    the end of EACH file. Both files save the caller's role in a GUC via
 *    `pg_catalog.set_config(..., true)` (the trailing `true` = is_local,
 *    i.e. transaction-scoped) so they can restore it before the script
 *    ends. A real CREATE EXTENSION runs its whole script as one transaction,
 *    so that works fine there. Run via plain \i in autocommit (no enclosing
 *    transaction), each top-level statement is its own implicit
 *    transaction, so the GUC's scope ends immediately -- by the time the
 *    restore-role code runs, current_setting() returns an empty string, and
 *    `SET ROLE ""` fails this way instead.
 *
 * We deliberately do NOT wrap the \i calls below in an explicit
 * BEGIN/COMMIT to "fix" the above -- that would make the FIRST
 * pg_extension_config_dump error poison the whole transaction, aborting
 * every statement after it instead of just these known, harmless ones
 * (verified locally: with an explicit transaction, every subsequent
 * statement fails with "current transaction is aborted", which would hide
 * real syntax errors instead of surfacing them). Relatedly, we disable
 * ON_ERROR_STOP below (which test/helpers/psql.sql just turned on) so that
 * these known errors don't stop psql from processing the rest of either
 * file -- each statement already being its own autocommit transaction means
 * a REAL syntax error later in either file still shows up as its own clear
 * diff, it just doesn't halt the whole test.
 *
 * We also dial VERBOSITY back down from psql.sql's "verbose" to "default":
 * verbose mode appends a LOCATION line with the triggering backend C source
 * file/line for every error above, which differs across PG major versions
 * (and even between builds of the same version) -- it would make this
 * file's expected output impossible to match across the PG12/PG17 matrix
 * this repo tests against.
 */
\set ON_ERROR_STOP false
\set VERBOSITY default

-- Guard against test/build/install.sql (or a previous run) having left
-- either extension installed; keep this file runnable on its own regardless
-- of test-build's file-execution order.
DROP EXTENSION IF EXISTS test_factory_pgtap;
DROP EXTENSION IF EXISTS test_factory;

-- test_factory must run first: test_factory_pgtap's raw file creates
-- objects in the "tf" schema, owned by the test_factory__owner role, both of
-- which only exist once test_factory's file has run.
\i sql/test_factory--0.5.0.sql

\i sql/test_factory_pgtap--0.1.0.sql

-- vi: expandtab ts=2 sw=2
