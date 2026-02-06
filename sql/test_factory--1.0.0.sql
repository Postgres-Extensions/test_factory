/* DO NOT EDIT - AUTO-GENERATED FILE */
CREATE TEMP TABLE original_role ON COMMIT DROP AS SELECT current_user AS original_role;

GRANT SELECT ON pg_temp.original_role TO public;
DO $body$
BEGIN
	CREATE ROLE test_factory__owner;
EXCEPTION
	WHEN duplicate_object THEN
        NULL;
END
$body$;

CREATE SCHEMA tf AUTHORIZATION test_factory__owner;
COMMENT ON SCHEMA tf IS $$Test factory. Tools for maintaining test data.$$;
GRANT USAGE ON SCHEMA tf TO public;

CREATE SCHEMA _tf AUTHORIZATION test_factory__owner;
-- Sucks that we have to do this. Need community to separate visibility and usage.
GRANT USAGE ON SCHEMA _tf TO public;

CREATE SCHEMA _test_factory_test_data AUTHORIZATION test_factory__owner;

-- Need to be SU
CREATE OR REPLACE FUNCTION _tf.schema__getsert(
) RETURNS name SECURITY DEFINER SET search_path = pg_catalog LANGUAGE plpgsql AS $body$
BEGIN
  /*
  IF NOT EXISTS( SELECT 1 FROM pg_namespace WHERE nspname = '_test_data' ) THEN
    CREATE SCHEMA _test_data AUTHORIZATION test_factory__owner;
  END IF;
  */

  RETURN '_test_factory_test_data';
END
$body$;

SET LOCAL ROLE test_factory__owner;

CREATE TYPE tf.test_set AS (
	set_name		text
	, insert_sql	text
);

CREATE TABLE _tf._test_factory(
	factory_id		SERIAL		NOT NULL PRIMARY KEY
	, table_oid		regclass	NOT NULL -- Can't do a FK to a catalog
	, set_name		text	  	NOT NULL
	, insert_sql	text	  	NOT NULL
	, UNIQUE( table_oid, set_name )
);
SELECT pg_catalog.pg_extension_config_dump('_tf._test_factory', '');
SELECT pg_catalog.pg_extension_config_dump('_tf._test_factory_factory_id_seq', '');


CREATE OR REPLACE FUNCTION _tf.data_table_name(
  table_name text -- Sanitized by tf.test_factory__get()
  , set_name _tf._test_factory.set_name%TYPE
) RETURNS name LANGUAGE plpgsql AS $body$
DECLARE
  v_factory_id_text text;
  v_table_name name;

  v_name name;
BEGIN
  SELECT
      -- Get a fixed-width representation of ID. btrim shouldn't be necessary but it is
      '_' || btrim( to_char(
        factory_id
        -- Get a string of 0's long enough to hold a max-sized int
        , repeat( '0', length( (2^31-1)::int::text ) )
      ) )
      , c.relname
    INTO v_factory_id_text, v_table_name
    FROM tf.test_factory__get( table_name, set_name ) f
      JOIN pg_class c ON c.oid = f.table_oid
      JOIN pg_namespace n ON n.oid = c.relnamespace
  ;

  v_name := v_table_name || v_factory_id_text;

  -- Was the name truncated?
  IF v_name <> (v_table_name || v_factory_id_text) THEN
    v_name := substring( v_table_name, length(v_name) - length(v_factory_id_text ) )
                || v_factory_id_text
    ;
  END IF;

  RETURN v_name;
END
$body$;


CREATE OR REPLACE FUNCTION _tf.test_factory__get(
  table_name text -- Sanitized by tf.test_factory__get()
  , set_name _tf._test_factory.set_name%TYPE
  , table_oid oid -- Must be passed in because of forced search_path
) RETURNS _tf._test_factory SECURITY DEFINER SET search_path = pg_catalog LANGUAGE plpgsql AS $body$
DECLARE
  v_test_factory _tf._test_factory;
BEGIN
  SELECT * INTO STRICT v_test_factory
    FROM _tf._test_factory tf
    WHERE tf.table_oid = test_factory__get.table_oid
      AND tf.set_name = test_factory__get.set_name
  ;

  RETURN v_test_factory;
EXCEPTION
  WHEN no_data_found THEN
    RAISE 'No factory found for table "%", set name "%"', table_name, set_name;
END
$body$;
CREATE OR REPLACE FUNCTION tf.test_factory__get(
  table_name text
  , set_name _tf._test_factory.set_name%TYPE
) RETURNS _tf._test_factory LANGUAGE sql AS $body$
SELECT * FROM _tf.test_factory__get(table_name, set_name, table_name::regclass)
$body$;


CREATE OR REPLACE FUNCTION _tf.test_factory__set(
  table_oid regclass
  , set_name text
  , insert_sql text
) RETURNS void SECURITY DEFINER SET search_path = pg_catalog LANGUAGE plpgsql AS $body$
BEGIN
  UPDATE _tf._test_factory
    SET insert_sql = test_factory__set.insert_sql
    WHERE _test_factory.table_oid = test_factory__set.table_oid
      AND _test_factory.set_name = test_factory__set.set_name
  ;
  /*
   * There shouldn't be concurrency conflicts here. If there are I think it's
   * better to error than UPSERT.
   */
  IF NOT FOUND THEN
    INSERT INTO _tf._test_factory( table_oid, set_name, insert_sql )
      VALUES( table_oid, set_name, insert_sql )
    ;
  END IF;
END
$body$;


CREATE OR REPLACE FUNCTION tf.register(
  table_name text
  , test_sets tf.test_set[]
) RETURNS void LANGUAGE plpgsql AS $body$
DECLARE
  c_table_oid CONSTANT regclass := table_name;
  v_set tf.test_set;
BEGIN
  FOREACH v_set IN ARRAY test_sets LOOP
    PERFORM _tf.test_factory__set(
      c_table_oid
      , v_set.set_name
      , v_set.insert_sql
    );
  END LOOP;
END
$body$;


CREATE OR REPLACE FUNCTION _tf.table_create(
  table_name text
) RETURNS void SECURITY DEFINER SET search_path = pg_catalog LANGUAGE plpgsql AS $body$
DECLARE
  c_td_schema CONSTANT name := _tf.schema__getsert();
  sql text;
BEGIN
  sql := format(
    $sql$
CREATE TABLE %I.%I AS SELECT * FROM pg_temp.%2$I;
    $sql$
    , c_td_schema
    , table_name
  );
  RAISE DEBUG 'sql = %', sql;
  EXECUTE sql;
END
$body$;

CREATE OR REPLACE FUNCTION tf.get(
  table_type anyelement
  , set_name text
) RETURNS SETOF anyelement LANGUAGE plpgsql AS $body$
DECLARE
  c_table_name CONSTANT text := pg_typeof(table_type);
  c_data_table_name CONSTANT name := _tf.data_table_name( c_table_name, set_name );
BEGIN
  -- SEE BELOW AS WELL
  RETURN QUERY SELECT * FROM _tf.get(table_type, set_name, c_data_table_name);
EXCEPTION
  WHEN undefined_table THEN
    DECLARE
      create_sql text;
    BEGIN
      -- TODO: Create temp table with caller security then create permanent table as test_factory__owner
      SELECT format(
            $$
CREATE TEMP TABLE %I ON COMMIT DROP AS
WITH i AS (
      %s
    )
  SELECT *
    FROM i
;
GRANT SELECT ON pg_temp.%1$I TO test_factory__owner;
$$
            , c_data_table_name
            , factory.insert_sql
          )
        INTO create_sql
        FROM tf.test_factory__get( c_table_name, set_name ) factory
      ;
      RAISE DEBUG 'sql = %', create_sql;
      EXECUTE create_sql;
      PERFORM _tf.table_create( c_data_table_name );

      -- SEE ABOVE AS WELL
      RETURN QUERY SELECT * FROM _tf.get(table_type, set_name, c_data_table_name);

      -- Can't do this in the secdef function because it doesn't own it.
      EXECUTE format( 'DROP TABLE pg_temp.%I', c_data_table_name );
    END;
END
$body$;

CREATE OR REPLACE FUNCTION _tf.get(
  table_type anyelement -- Sanitized by tf.test_factory__get()
  , set_name text
  , data_table_name name
) RETURNS SETOF anyelement SECURITY DEFINER SET search_path = pg_catalog LANGUAGE plpgsql AS $body$
DECLARE
  c_table_name CONSTANT text := pg_typeof(table_type);
  c_td_schema CONSTANT name := _tf.schema__getsert();

  sql text;
BEGIN
  sql := format(
    'SELECT * FROM %I.%I AS t'
    , c_td_schema
    , data_table_name 
  );
  RAISE DEBUG 'sql = %', sql;

  RETURN QUERY EXECUTE sql;
END
$body$;

--select (tf.get('moo','moo')::moo).*;
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
