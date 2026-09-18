-- LOCAL DEVELOPMENT BOOTSTRAP FIXTURE ONLY.
do $$
declare
	required_identity record;
begin
	for required_identity in
		select required.id, required.email
		from (values
			('c9bcd3ef-1e7e-4889-8a12-db827f1b97b0'::uuid, 'lorenzo@lorenzowebsolutions.be'::text),
			('bd2ab636-0d42-4069-88a9-60bd97f2b335'::uuid, 'herlinde@lorenzowebsolutions.be'::text),
			('d0247fd9-60d5-40bc-a905-6b02024b6420'::uuid, 'finance@lorenzowebsolutions.be'::text)
		) as required(id, email)
	loop
		if exists (
			select 1
			from auth.users
			where id = required_identity.id
				and (email is distinct from required_identity.email or email_confirmed_at is null)
		) then
			raise exception using errcode = '23505', message = 'LOCAL_AUTH_IDENTITY_MISMATCH';
		end if;

		if exists (
			select 1
			from auth.users
			where email = required_identity.email
				and id <> required_identity.id
		) then
			raise exception using errcode = '23505', message = 'LOCAL_AUTH_EMAIL_CONFLICT';
		end if;

		insert into auth.users (id, email, email_confirmed_at)
		select required_identity.id, required_identity.email, clock_timestamp()
		where not exists (
			select 1 from auth.users where id = required_identity.id
		);
	end loop;
end;
$$;