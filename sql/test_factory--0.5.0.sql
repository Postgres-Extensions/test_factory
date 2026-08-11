/* DO NOT EDIT - AUTO-GENERATED FILE */
/*
 * Save the caller's role so we can restore it at the end (we SET LOCAL ROLE
 * below to own our objects). A GUC is used instead of a temp table not to
 * avoid CREATE EXTENSION breakage (trivial to avoid either way) but because
 * it's much lighter weight than creating a table.
 */
SELECT pg_catalog.set_config('test_factory.original_role', current_user, true);

DO $body$
BEGIN
	CREATE ROLE test_factory__owner;
EXCEPTION
	WHEN duplicate_object THEN
        NULL;
END
$body$;

/*
 * CREATE ROLE alone never grants the creator any relationship to the role
 * it just created -- on ANY version, confirmed directly against a genuine
 * non-superuser CREATEROLE installer with zero prior grants: SET ROLE
 * test_factory__owner below fails outright ("permission denied to set
 * role") without an explicit GRANT first, even immediately after this
 * same session created it. A real superuser bypasses the SET ROLE check
 * entirely regardless of any of this, which is why this was easy to miss
 * without testing against a genuine non-superuser role.
 *
 * As of PG16, plain membership isn't enough either -- SET ROLE requires
 * the SET option specifically, which needs GRANT ... WITH SET TRUE.
 * Before PG16, plain membership (no WITH SET syntax, which doesn't exist
 * yet) already confers the ability to SET ROLE. pg_has_role's 'SET'
 * privilege type is PG16+ only, but as a plain function argument (not a
 * catalog column reference) it's safe to call inside this same
 * version-gated branch, unlike a static reference to
 * pg_auth_members.set_option, which would fail to parse on older servers
 * even inside the gate.
 *
 * Either way, skip the GRANT when it's not actually needed: an installer
 * might already have the membership it needs some other way -- e.g. a DBA
 * pre-provisioned the role and granted it directly, deliberately
 * withholding ADMIN OPTION as a least-privilege measure -- and GRANT ROLE
 * requires ADMIN OPTION on the target role (or superuser) to run AT ALL,
 * regardless of whether it would end up a no-op; forcing it unconditionally
 * broke that already-working case (confirmed against a live non-superuser
 * role with SET but not ADMIN OPTION: "ERROR: permission denied to grant
 * role ... Only roles with the ADMIN option ... may grant this role").
 *
 * If the installer has neither the membership it needs nor ADMIN OPTION to
 * grant it themselves, installation genuinely cannot proceed -- nobody
 * else can do it on their behalf from inside this script. Catch that
 * specific case and say so plainly instead of surfacing Postgres's generic
 * permission error.
 */
DO $body$
BEGIN
	IF current_setting('server_version_num')::int >= 160000 THEN
		IF NOT pg_has_role(current_user, 'test_factory__owner', 'SET') THEN
			BEGIN
				EXECUTE format('GRANT test_factory__owner TO %I WITH SET TRUE', current_user);
			EXCEPTION
				WHEN insufficient_privilege THEN
					/*
					 * RAISE's own %-substitution is plain string
					 * interpolation, not format()'s %I/%L -- build the
					 * copy-pastable suggested command with format() first
					 * (so the role name is properly identifier-quoted),
					 * then substitute the whole result in with a single,
					 * ordinary %.
					 */
					RAISE EXCEPTION
						'role "%" lacks SET-enabled membership in "test_factory__owner", and lacks ADMIN OPTION to grant it to itself'
						, current_user
						USING ERRCODE = 'insufficient_privilege'
						, HINT = format(
							'Ask a superuser, or a role with ADMIN OPTION on "test_factory__owner", to run: %s'
							, format('GRANT test_factory__owner TO %I WITH SET TRUE;', current_user)
						);
			END;
		END IF;
	ELSIF NOT pg_has_role(current_user, 'test_factory__owner', 'MEMBER') THEN
		BEGIN
			EXECUTE format('GRANT test_factory__owner TO %I', current_user);
		EXCEPTION
			WHEN insufficient_privilege THEN
				RAISE EXCEPTION
					'role "%" is not a member of "test_factory__owner", and lacks ADMIN OPTION to grant it to itself'
					, current_user
					USING ERRCODE = 'insufficient_privilege'
					, HINT = format(
						'Ask a superuser, or a role with ADMIN OPTION on "test_factory__owner", to run: %s'
						, format('GRANT test_factory__owner TO %I;', current_user)
					);
		END;
	END IF;
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
-- Restore the caller's role saved at the top of this script.
DO $body$
BEGIN
  EXECUTE 'SET ROLE ' || pg_catalog.quote_ident(pg_catalog.current_setting('test_factory.original_role'));
END
$body$;

-- vi: expandtab ts=2 sw=2
