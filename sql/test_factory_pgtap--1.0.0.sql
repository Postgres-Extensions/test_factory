/* DO NOT EDIT - AUTO-GENERATED FILE */
CREATE TEMP TABLE original_role ON COMMIT DROP AS SELECT current_user AS original_role;
GRANT SELECT ON pg_temp.original_role TO public;

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

-- Set role back to original value
DO $body$
DECLARE
  c_sql CONSTANT text :=  'SET ROLE ' || (SELECT original_role FROM pg_temp.original_role);
BEGIN
  --RAISE WARNING 'c_sql = %', c_sql;
  EXECUTE c_sql;
END
$body$;

DROP TABLE pg_temp.original_role;

-- vi: expandtab ts=2 sw=2
