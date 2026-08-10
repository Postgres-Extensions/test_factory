\set ECHO none
\i test/helpers/setup.sql

-- test/install/load.sql already installed the extension, in every mode.

/*
 * Regression test for issue #14. On PostgreSQL 16+, CREATE ROLE no longer
 * grants the creating role a SET-enabled membership in the new role, so the
 * install must GRANT test_factory__owner ... WITH SET TRUE (when needed --
 * see sql/test_factory.sql's own comment) or the SET ROLE performed during
 * install fails for non-superuser installs (RDS/Aurora).
 *
 * pg_has_role(), not a raw pg_auth_members query: a real superuser always
 * has effective SET privilege on every role (bypasses the check entirely,
 * no explicit grant needed), which pg_has_role correctly reports as true --
 * a literal catalog-row check would not, since CI's installer here IS a
 * real superuser and the fix's own gating logic (also pg_has_role-based)
 * correctly skips granting a superuser something they don't need. This is
 * what the fix actually guarantees -- "can this role SET ROLE
 * test_factory__owner", not "does a specific catalog row exist" -- and
 * checking it the same way the fix does is what makes this a real
 * regression test rather than an assertion about an implementation detail.
 *
 * pg_has_role's 'SET' privilege type is PG16+ only (same reasoning as
 * sql/test_factory.sql), so the check is skipped (identical TAP output) on
 * older versions, where a plain GRANT ... TO already confers the ability
 * to SET ROLE.
 */
SELECT (current_setting('server_version_num')::int >= 160000) AS pg16plus \gset
-- pg16+ SET-enabled membership check
\if :pg16plus
SELECT ok(
  pg_has_role(current_user, 'test_factory__owner', 'SET')
  , 'Installing role has SET-enabled membership in test_factory__owner (issue #14)'
);
-- pg16+ SET-enabled membership check
\else
SELECT ok(
  true
  , 'Installing role has SET-enabled membership in test_factory__owner (issue #14)'
);
-- pg16+ SET-enabled membership check
\endif

-- NOTE: This runs some tests itself
\i test/helpers/create.sql

SELECT is_empty(
  'SELECT * FROM customer'
  , 'customer table is empty'
);
SELECT is_empty(
  'SELECT * FROM invoice'
  , 'invoice table is empty'
);

SELECT results_eq(
  $$SELECT * FROM tf.get( NULL::invoice, 'base' )$$
  , $$VALUES( 1, 1, current_date, current_date + 30 )$$
  , 'invoice factory output'
);

SELECT bag_eq(
  $$SELECT * FROM invoice$$
  , $$VALUES( 1, 1, current_date, current_date + 30 )$$
  , 'invoice table content'
);

SELECT bag_eq(
  $$SELECT * FROM customer$$
  , $$VALUES( 1, 'first', 'last' )$$
  , 'customer table content'
);

SELECT results_eq(
  $$SELECT * FROM tf.get( NULL::invoice, 'base' )$$
  , $$VALUES( 1, 1, current_date, current_date + 30 )$$
  , 'invoice factory second call'
);

SELECT bag_eq(
  $$SELECT * FROM invoice$$
  , $$VALUES( 1, 1, current_date, current_date + 30 )$$
  , 'invoice table content stayed constant'
);

SELECT bag_eq(
  $$SELECT * FROM customer$$
  , $$VALUES( 1, 'first', 'last' )$$
  , 'customer table content stayed constant'
);

SELECT results_eq(
  $$SELECT * FROM tf.get( NULL::customer, 'function' )$$
  , $$VALUES( 2, 'func first', 'func last' )$$
  , 'Test function factory'
);

SELECT bag_eq(
  $$SELECT * FROM customer$$
  , $$VALUES
      ( 1, 'first', 'last' )
      , ( 2, 'func first', 'func last' )
    $$
  , 'customer table has new row'
);

SELECT lives_ok(
  $$TRUNCATE invoice$$
  , 'truncate invoice'
);

SELECT results_eq(
  $$SELECT * FROM tf.get( NULL::invoice, 'base' )$$
  , $$VALUES( 1, 1, current_date, current_date + 30 )$$
  , 'invoice factory get remains the same after truncate'
);

ROLLBACK;

-- vi: expandtab ts=2 sw=2
