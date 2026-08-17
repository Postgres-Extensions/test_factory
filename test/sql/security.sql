\set ECHO none
\i test/helpers/setup.sql

/*
 * Prove the public tf.* API needs nothing beyond what a freshly-created,
 * unprivileged login role already gets by default: no owned schema, no
 * explicit GRANTs, and (deliberately) no membership in test_factory__owner.
 * Everything it uses here (tf/_tf schema USAGE, EXECUTE on tf.* functions,
 * CREATE TEMP TABLE) comes from either Postgres' own defaults or the GRANTs
 * test_factory's install script makes to PUBLIC.
 */
SET ROLE = DEFAULT;
CREATE ROLE test_factory_bare_user;
-- USAGE on tap is a pgtap test-harness necessity (to call lives_ok() etc.
-- below), not one of the grants under test here.
GRANT USAGE ON SCHEMA tap TO test_factory_bare_user;
/*
 * SET SESSION AUTHORIZATION, not SET ROLE: it changes session_user too, which
 * is what a further SET ROLE's permission check actually looks at. A plain
 * SET ROLE here would leave this session able to SET ROLE into anything
 * (including test_factory__owner below) regardless of grants, since
 * pg_regress always connects as a superuser.
 */
SET SESSION AUTHORIZATION test_factory_bare_user;

CREATE TEMP TABLE widget(
  widget_id   serial  PRIMARY KEY
  , name      text    NOT NULL
);

SELECT lives_ok(
$lives_ok$SELECT tf.register(
  'widget'
  , array[
    row(
      'base'
      , $$INSERT INTO widget VALUES (DEFAULT, 'gadget') RETURNING *$$
    )::tf.test_set
  ]
);$lives_ok$
  , 'Bare, unprivileged role can register test data with zero extra grants'
);

SELECT results_eq(
  $$SELECT * FROM tf.get( NULL::widget, 'base' )$$
  , $$VALUES( 1, 'gadget' )$$
  , 'Bare, unprivileged role can create+fetch test data with zero extra grants'
);

SELECT results_eq(
  $$SELECT * FROM tf.get( NULL::widget, 'base' )$$
  , $$VALUES( 1, 'gadget' )$$
  , 'Bare, unprivileged role gets the cached row on a second call'
);

-- Confirm role isolation still holds for a role that otherwise works fine
SELECT throws_ok(
  $$SET ROLE test_factory__owner$$
  , '42501'
  , NULL
  , 'Bare role cannot SET ROLE into the extension owner role'
);

ROLLBACK;

-- vi: expandtab ts=2 sw=2
