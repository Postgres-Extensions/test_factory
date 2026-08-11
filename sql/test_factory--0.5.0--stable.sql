/*
 * Same issue as a fresh install (see sql/test_factory.sql's own comment):
 * CREATE ROLE never granted the ORIGINAL installer any relationship to
 * test_factory__owner either, on any PostgreSQL version. An existing
 * 0.5.0 install already has test_factory__owner and doesn't need it
 * recreated -- it only needs this same GRANT, so that whoever runs this
 * update (and anyone else who later needs to SET ROLE
 * test_factory__owner) has it too. No object in this extension changed
 * between 0.5.0 and here, so nothing needs to run AS test_factory__owner
 * -- unlike the fresh-install script, there's no role to switch to or
 * restore.
 */
DO $body$
BEGIN
	IF current_setting('server_version_num')::int >= 160000 THEN
		IF NOT pg_has_role(current_user, 'test_factory__owner', 'SET') THEN
			BEGIN
				EXECUTE format('GRANT test_factory__owner TO %I WITH SET TRUE', current_user);
			EXCEPTION
				WHEN insufficient_privilege THEN
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

-- vi: expandtab ts=2 sw=2
