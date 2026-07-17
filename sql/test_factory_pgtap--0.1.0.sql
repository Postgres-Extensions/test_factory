/* DO NOT EDIT - AUTO-GENERATED FILE */
/*
 * Save the caller's role so we can restore it at the end (we SET LOCAL ROLE
 * below to own our objects). Stashed in a transaction-local GUC rather than a
 * temp table, which would be owned by the extension and break CREATE EXTENSION.
 */
SELECT pg_catalog.set_config('test_factory_pgtap.original_role', current_user, true);

SET LOCAL ROLE test_factory__owner;

CREATE OR REPLACE FUNCTION tf.tap(
  table_name text
  , set_name text DEFAULT 'base'
) RETURNS SETOF text LANGUAGE plpgsql AS $body$
DECLARE
  c_table CONSTANT regclass := table_name;
BEGIN
  RETURN NEXT isnt_empty(
    format(
      $$SELECT tf.get( NULL::%s, %L )$$ -- We assume regclass::text gives us valid output
      , c_table
      , set_name
    )
    , format(
        'Get test data set "%s" for table %s'
        , set_name
        , c_table
      )
  );
END
$body$;

-- Set role back to original value (saved at the top of this script).
DO $body$
BEGIN
  EXECUTE 'SET ROLE ' || pg_catalog.quote_ident(pg_catalog.current_setting('test_factory_pgtap.original_role'));
END
$body$;

-- vi: expandtab ts=2 sw=2
