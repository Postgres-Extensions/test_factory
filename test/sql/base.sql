\set ECHO none
\i test/helpers/setup.sql

\set extension_name test_factory
\i test/helpers/create_extension.sql

/*
 * Regression test for issue #14. On PostgreSQL 16+, CREATE ROLE no longer
 * grants the creating role a SET-enabled membership in the new role, so the
 * install must GRANT test_factory__owner ... WITH SET TRUE or the SET ROLE
 * performed during install fails for non-superuser installs (RDS/Aurora). A
 * real superuser bypasses the SET ROLE check, so a plain install here cannot
 * reproduce the failure; instead assert the SET-enabled membership the fix
 * establishes. pg_auth_members.set_option only exists on PG16+, so the check is
 * skipped (with identical TAP output) on older versions, where a plain
 * GRANT ... TO already confers the ability to SET ROLE.
 */
SELECT (current_setting('server_version_num')::int >= 160000) AS pg16plus \gset
\if :pg16plus
SELECT ok(
  EXISTS(
    SELECT 1
      FROM pg_auth_members
      WHERE roleid = 'test_factory__owner'::regrole
        AND member = current_user::regrole
        AND set_option
  )
  , 'Installing role has SET-enabled membership in test_factory__owner (issue #14)'
);
\else
SELECT ok(
  true
  , 'Installing role has SET-enabled membership in test_factory__owner (issue #14)'
);
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
