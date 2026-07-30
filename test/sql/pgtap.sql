\set ECHO none
\i test/helpers/setup.sql

/*
 * psql's \if only accepts a plain boolean token, not a comparison
 * expression -- compute it via SQL first.
 */
SELECT current_setting('test_factory.test_load_mode') = 'existing' AS is_existing \gset

\if :is_existing

/*
 * existing mode: both extensions are already installed (see
 * test/install/load.sql) -- don't touch install ordering here; that's what
 * the \else branch below tests. Bypass test/helpers/create_extension.sql
 * entirely rather than let it no-op: it skips creating pre_install_role /
 * post_install_role when the extension is already installed, and the
 * \else branch's DROP TABLE calls on those would then error. Packaging /
 * dependency-declaration checks now live in test/build/install.sql, not
 * here (see add-test-build). Just exercise tf.tap() against what's
 * already there.
 */
\i test/helpers/create.sql

SELECT tf.tap( 'invoice' );
SELECT tf.tap( 'invoice', 'base' );
SELECT throws_ok(
  $$SELECT tf.tap( '"non-existent table"' )$$
  , '42P01'
  , 'relation "non-existent table" does not exist'
  , 'Ensure we get sane error for a non-existent table'
);

\else

\set extension_name test_factory
\i test/helpers/create_extension.sql
DROP TABLE pre_install_role;
DROP TABLE post_install_role;
\set extension_name test_factory_pgtap
\i test/helpers/create_extension.sql

-- NOTE: This runs some tests itself. It also changes search_path
\i test/helpers/create.sql

-- tf.tap already returns tap output
SELECT tf.tap( 'invoice' );
SELECT tf.tap( 'invoice', 'base' );
SELECT throws_ok(
  $$SELECT tf.tap( '"non-existent table"' )$$
  , '42P01'
  , 'relation "non-existent table" does not exist'
  , 'Ensure we get sane error for a non-existent table'
);

\endif

ROLLBACK;

-- vi: expandtab ts=2 sw=2
