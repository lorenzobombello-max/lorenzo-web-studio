insert into storage.buckets (
	id, name, public, file_size_limit, allowed_mime_types
) values (
	'quotation-artifacts',
	'quotation-artifacts',
	false,
	10485760,
	array[
		'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
		'application/pdf'
	]::text[]
);

create table public.quote_request_quotation_artifacts (
	artifact_id uuid primary key default gen_random_uuid(),
	issuance_id uuid not null references public.quote_request_quotation_issuances(id),
	artifact_type text not null check (artifact_type in ('DOCX', 'PDF')),
	storage_bucket_id text not null check (storage_bucket_id = 'quotation-artifacts'),
	storage_object_path text not null,
	content_type text not null,
	sha256 char(64) not null check (sha256 ~ '^[0-9a-f]{64}$'),
	byte_count bigint not null check (byte_count > 0 and byte_count <= 10485760),
	registration_idempotency_key uuid not null unique,
	registration_fingerprint char(64) not null check (registration_fingerprint ~ '^[0-9a-f]{64}$'),
	created_at timestamptz not null default clock_timestamp(),
	created_by text not null check (nullif(btrim(created_by), '') is not null),
	constraint quotation_artifact_issuance_type_unique unique (issuance_id, artifact_type),
	constraint quotation_artifact_storage_object_unique unique (storage_bucket_id, storage_object_path),
	constraint quotation_artifact_type_content_path_coherent check (
		(artifact_type = 'DOCX'
			and content_type = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
			and storage_object_path = 'issuances/' || issuance_id::text || '/docx/' || rtrim(sha256) || '.docx')
		or
		(artifact_type = 'PDF'
			and content_type = 'application/pdf'
			and storage_object_path = 'issuances/' || issuance_id::text || '/pdf/' || rtrim(sha256) || '.pdf')
	)
);

create table public.quote_request_quotation_artifact_events (
	event_id bigint generated always as identity primary key,
	artifact_id uuid references public.quote_request_quotation_artifacts(artifact_id),
	issuance_id uuid not null references public.quote_request_quotation_issuances(id),
	artifact_type text not null check (artifact_type in ('DOCX', 'PDF')),
	event_type text not null check (event_type in (
		'ARTIFACT_ARCHIVED', 'ARTIFACT_ARCHIVE_FAILED', 'ARTIFACT_RECONCILED'
	)),
	operation_id uuid not null unique,
	actor text not null check (nullif(btrim(actor), '') is not null),
	event_at timestamptz not null default clock_timestamp(),
	evidence jsonb not null,
	constraint quotation_artifact_event_shape_valid check (
		jsonb_typeof(evidence) = 'object'
		and not (evidence ?| array[
			'signed_url', 'token', 'token_digest', 'credential', 'credentials',
			'binary', 'content', 'customer_content', 'raw_exception', 'secret',
			'service_role_key', 'admin_access_token_hash'
		])
		and (
			(event_type = 'ARTIFACT_ARCHIVED'
				and artifact_id is not null
				and public.jsonb_has_exact_keys(evidence, array['bucket', 'path', 'sha256', 'byte_count', 'outcome'])
				and evidence->>'outcome' = 'ARCHIVED'
				and evidence->>'bucket' = 'quotation-artifacts'
				and evidence->>'sha256' ~ '^[0-9a-f]{64}$'
				and public.is_jsonb_nonnegative_integer(evidence->'byte_count'))
			or
			(event_type = 'ARTIFACT_ARCHIVE_FAILED'
				and public.jsonb_has_exact_keys(evidence, array['failure_code', 'outcome'])
				and evidence->>'outcome' = 'FAILED'
				and evidence->>'failure_code' in (
					'UPLOAD_FAILED', 'REGISTRATION_FAILED', 'HASH_MISMATCH',
					'BYTE_COUNT_MISMATCH', 'OBJECT_CONFLICT', 'OBJECT_METADATA_MISMATCH'
				))
			or
			(event_type = 'ARTIFACT_RECONCILED'
				and public.jsonb_has_exact_keys(evidence, array[
					'bucket', 'path', 'sha256', 'byte_count', 'content_type',
					'object_present', 'outcome'
				])
				and evidence->>'bucket' = 'quotation-artifacts'
				and evidence->>'outcome' in (
					'CONSISTENT', 'MISSING_OBJECT', 'ORPHAN_OBJECT', 'METADATA_MISMATCH'
				)
				and jsonb_typeof(evidence->'object_present') = 'boolean')
		)
	)
);

create function public.prevent_quotation_artifact_history_mutation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
	raise exception using errcode = '55000', message = 'QUOTATION_ARTIFACT_HISTORY_IMMUTABLE';
end;
$$;

create trigger trg_quotation_artifacts_immutable
before update or delete on public.quote_request_quotation_artifacts
for each row execute function public.prevent_quotation_artifact_history_mutation();

create trigger trg_quotation_artifact_events_immutable
before update or delete on public.quote_request_quotation_artifact_events
for each row execute function public.prevent_quotation_artifact_history_mutation();

create function public.register_quotation_artifact_v1(
	p_issuance_id uuid,
	p_artifact_type text,
	p_observed_sha256 text,
	p_observed_bytes bigint,
	p_content_type text,
	p_idempotency_key uuid,
	p_actor text
)
returns table (
	artifact_id uuid,
	issuance_id uuid,
	artifact_type text,
	storage_bucket_id text,
	storage_object_path text,
	content_type text,
	sha256 text,
	byte_count bigint,
	created_at timestamptz,
	created_by text,
	was_created boolean
)
language plpgsql
security definer
set search_path = public, storage, extensions
as $$
declare
	v_issuance public.quote_request_quotation_issuances%rowtype;
	v_existing public.quote_request_quotation_artifacts%rowtype;
	v_artifact public.quote_request_quotation_artifacts%rowtype;
	v_expected_sha256 text;
	v_expected_bytes bigint;
	v_expected_content_type text;
	v_expected_path text;
	v_fingerprint text;
	v_storage_metadata jsonb;
	v_inserted boolean := false;
begin
	if p_artifact_type not in ('DOCX', 'PDF') then
		raise exception using errcode = '22023', message = 'ARTIFACT_TYPE_INVALID';
	end if;
	if p_observed_sha256 is null or p_observed_sha256 !~ '^[0-9a-f]{64}$' then
		raise exception using errcode = '22023', message = 'ARTIFACT_HASH_INVALID';
	end if;
	if p_observed_bytes is null or p_observed_bytes <= 0 or p_observed_bytes > 10485760 then
		raise exception using errcode = '22023', message = 'ARTIFACT_BYTES_INVALID';
	end if;
	if p_idempotency_key is null or nullif(btrim(p_actor), '') is null then
		raise exception using errcode = '42501', message = 'UNAUTHORIZED';
	end if;

	select * into v_issuance
	from public.quote_request_quotation_issuances
	where id = p_issuance_id;
	if not found then
		raise exception using errcode = 'P0001', message = 'ISSUANCE_NOT_FOUND';
	end if;
	if v_issuance.status not in ('ISSUED', 'SUPERSEDED') then
		raise exception using errcode = 'P0001', message = 'ARTIFACT_ARCHIVE_NOT_AVAILABLE';
	end if;

	if p_artifact_type = 'DOCX' then
		v_expected_sha256 := rtrim(v_issuance.docx_sha256);
		v_expected_bytes := v_issuance.docx_bytes;
		v_expected_content_type := 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
		v_expected_path := 'issuances/' || p_issuance_id::text || '/docx/' || v_expected_sha256 || '.docx';
	else
		v_expected_sha256 := rtrim(v_issuance.pdf_sha256);
		v_expected_bytes := v_issuance.pdf_bytes;
		v_expected_content_type := 'application/pdf';
		v_expected_path := 'issuances/' || p_issuance_id::text || '/pdf/' || v_expected_sha256 || '.pdf';
	end if;

	if v_expected_sha256 is null or v_expected_bytes is null then
		raise exception using errcode = 'P0001', message = 'ARTIFACT_EVIDENCE_NOT_AVAILABLE';
	end if;

	v_fingerprint := encode(extensions.digest(convert_to(jsonb_build_object(
		'artifactType', p_artifact_type,
		'byteCount', p_observed_bytes,
		'contentType', p_content_type,
		'issuanceId', p_issuance_id,
		'sha256', p_observed_sha256,
		'storageBucketId', 'quotation-artifacts',
		'storageObjectPath', v_expected_path
	)::text, 'UTF8'), 'sha256'), 'hex');

	select * into v_existing
	from public.quote_request_quotation_artifacts
	where registration_idempotency_key = p_idempotency_key;
	if found then
		if rtrim(v_existing.registration_fingerprint) <> v_fingerprint then
			raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
		end if;
		return query select v_existing.artifact_id, v_existing.issuance_id,
			v_existing.artifact_type, v_existing.storage_bucket_id,
			v_existing.storage_object_path, v_existing.content_type,
			rtrim(v_existing.sha256), v_existing.byte_count, v_existing.created_at,
			v_existing.created_by, false;
		return;
	end if;

	select * into v_existing
	from public.quote_request_quotation_artifacts
	where quote_request_quotation_artifacts.issuance_id = p_issuance_id
		and quote_request_quotation_artifacts.artifact_type = p_artifact_type;
	if found then
		if rtrim(v_existing.sha256) <> p_observed_sha256
			 or v_existing.byte_count <> p_observed_bytes
			 or v_existing.content_type <> p_content_type
			 or v_existing.storage_object_path <> v_expected_path then
			raise exception using errcode = 'P0001', message = 'ARTIFACT_CONFLICT';
		end if;
		return query select v_existing.artifact_id, v_existing.issuance_id,
			v_existing.artifact_type, v_existing.storage_bucket_id,
			v_existing.storage_object_path, v_existing.content_type,
			rtrim(v_existing.sha256), v_existing.byte_count, v_existing.created_at,
			v_existing.created_by, false;
		return;
	end if;

	if p_observed_sha256 <> v_expected_sha256 then
		raise exception using errcode = 'P0001', message = 'ARTIFACT_HASH_MISMATCH';
	end if;
	if p_observed_bytes <> v_expected_bytes then
		raise exception using errcode = 'P0001', message = 'ARTIFACT_BYTE_COUNT_MISMATCH';
	end if;
	if p_content_type is distinct from v_expected_content_type then
		raise exception using errcode = 'P0001', message = 'ARTIFACT_CONTENT_TYPE_MISMATCH';
	end if;

	select objects.metadata into v_storage_metadata
	from storage.objects as objects
	where objects.bucket_id = 'quotation-artifacts'
		and objects.name = v_expected_path;
	if not found then
		raise exception using errcode = 'P0001', message = 'ARTIFACT_OBJECT_NOT_FOUND';
	end if;
	if coalesce(v_storage_metadata->>'mimetype', '') <> v_expected_content_type
		 or coalesce(v_storage_metadata->>'size', '') !~ '^[0-9]+$'
		 or (v_storage_metadata->>'size')::bigint <> v_expected_bytes then
		raise exception using errcode = 'P0001', message = 'ARTIFACT_OBJECT_METADATA_MISMATCH';
	end if;

	begin
		insert into public.quote_request_quotation_artifacts (
			issuance_id, artifact_type, storage_bucket_id, storage_object_path,
			content_type, sha256, byte_count, registration_idempotency_key,
			registration_fingerprint, created_by
		) values (
			p_issuance_id, p_artifact_type, 'quotation-artifacts', v_expected_path,
			p_content_type, p_observed_sha256, p_observed_bytes, p_idempotency_key,
			v_fingerprint, p_actor
		) returning * into v_artifact;
		v_inserted := true;
	exception when unique_violation then
		select * into v_artifact
		from public.quote_request_quotation_artifacts
		where registration_idempotency_key = p_idempotency_key
			 or (quote_request_quotation_artifacts.issuance_id = p_issuance_id
				 and quote_request_quotation_artifacts.artifact_type = p_artifact_type)
		order by (registration_idempotency_key = p_idempotency_key) desc
		limit 1;
		if not found
			 or rtrim(v_artifact.sha256) <> p_observed_sha256
			 or v_artifact.byte_count <> p_observed_bytes
			 or v_artifact.content_type <> p_content_type
			 or v_artifact.storage_object_path <> v_expected_path then
			raise exception using errcode = 'P0001', message = 'ARTIFACT_CONFLICT';
		end if;
	end;

	if v_inserted then
		insert into public.quote_request_quotation_artifact_events (
			artifact_id, issuance_id, artifact_type, event_type,
			operation_id, actor, evidence
		) values (
			v_artifact.artifact_id, p_issuance_id, p_artifact_type,
			'ARTIFACT_ARCHIVED', p_idempotency_key, p_actor,
			jsonb_build_object(
				'bucket', 'quotation-artifacts', 'path', v_expected_path,
				'sha256', p_observed_sha256, 'byte_count', p_observed_bytes,
				'outcome', 'ARCHIVED'
			)
		);
	end if;

	return query select v_artifact.artifact_id, v_artifact.issuance_id,
		v_artifact.artifact_type, v_artifact.storage_bucket_id,
		v_artifact.storage_object_path, v_artifact.content_type,
		rtrim(v_artifact.sha256), v_artifact.byte_count, v_artifact.created_at,
		v_artifact.created_by, v_inserted;
end;
$$;

create function public.get_quotation_artifact_metadata_v1(p_issuance_id uuid)
returns table (
	artifact_id uuid,
	issuance_id uuid,
	artifact_type text,
	storage_bucket_id text,
	storage_object_path text,
	content_type text,
	sha256 text,
	byte_count bigint,
	created_at timestamptz,
	created_by text
)
language sql
stable
security definer
set search_path = public
as $$
	select artifact.artifact_id, artifact.issuance_id, artifact.artifact_type,
		artifact.storage_bucket_id, artifact.storage_object_path,
		artifact.content_type, rtrim(artifact.sha256), artifact.byte_count,
		artifact.created_at, artifact.created_by
	from public.quote_request_quotation_artifacts as artifact
	where artifact.issuance_id = p_issuance_id
	order by artifact.artifact_type
$$;

create function public.record_quotation_artifact_archive_failure_v1(
	p_issuance_id uuid,
	p_artifact_type text,
	p_failure_code text,
	p_idempotency_key uuid,
	p_actor text
)
returns table (event_id bigint, was_created boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
	v_event public.quote_request_quotation_artifact_events%rowtype;
begin
	if p_artifact_type not in ('DOCX', 'PDF')
		 or p_failure_code not in (
			 'UPLOAD_FAILED', 'REGISTRATION_FAILED', 'HASH_MISMATCH',
			 'BYTE_COUNT_MISMATCH', 'OBJECT_CONFLICT', 'OBJECT_METADATA_MISMATCH'
		 ) then
		raise exception using errcode = '22023', message = 'ARTIFACT_FAILURE_INVALID';
	end if;
	if p_idempotency_key is null or nullif(btrim(p_actor), '') is null then
		raise exception using errcode = '42501', message = 'UNAUTHORIZED';
	end if;
	perform 1 from public.quote_request_quotation_issuances where id = p_issuance_id;
	if not found then
		raise exception using errcode = 'P0001', message = 'ISSUANCE_NOT_FOUND';
	end if;

	select * into v_event
	from public.quote_request_quotation_artifact_events
	where operation_id = p_idempotency_key;
	if found then
		if v_event.event_type <> 'ARTIFACT_ARCHIVE_FAILED'
			 or v_event.issuance_id <> p_issuance_id
			 or v_event.artifact_type <> p_artifact_type
			 or v_event.evidence->>'failure_code' <> p_failure_code then
			raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
		end if;
		return query select v_event.event_id, false;
		return;
	end if;

	insert into public.quote_request_quotation_artifact_events (
		issuance_id, artifact_type, event_type, operation_id, actor, evidence
	) values (
		p_issuance_id, p_artifact_type, 'ARTIFACT_ARCHIVE_FAILED',
		p_idempotency_key, p_actor,
		jsonb_build_object('failure_code', p_failure_code, 'outcome', 'FAILED')
	) returning * into v_event;
	return query select v_event.event_id, true;
end;
$$;

create function public.reconcile_quotation_artifact_v1(
	p_issuance_id uuid,
	p_artifact_type text,
	p_observed_sha256 text,
	p_observed_bytes bigint,
	p_observed_content_type text,
	p_idempotency_key uuid,
	p_actor text
)
returns table (event_id bigint, outcome text, was_created boolean)
language plpgsql
security definer
set search_path = public, storage
as $$
declare
	v_issuance public.quote_request_quotation_issuances%rowtype;
	v_artifact public.quote_request_quotation_artifacts%rowtype;
	v_event public.quote_request_quotation_artifact_events%rowtype;
	v_expected_sha256 text;
	v_expected_bytes bigint;
	v_expected_content_type text;
	v_expected_path text;
	v_storage_metadata jsonb;
	v_object_present boolean;
	v_outcome text;
begin
	if p_artifact_type not in ('DOCX', 'PDF')
		 or p_idempotency_key is null
		 or nullif(btrim(p_actor), '') is null then
		raise exception using errcode = '22023', message = 'ARTIFACT_RECONCILIATION_INVALID';
	end if;
	if p_observed_sha256 is not null and p_observed_sha256 !~ '^[0-9a-f]{64}$' then
		raise exception using errcode = '22023', message = 'ARTIFACT_RECONCILIATION_INVALID';
	end if;

	select * into v_issuance
	from public.quote_request_quotation_issuances
	where id = p_issuance_id;
	if not found then
		raise exception using errcode = 'P0001', message = 'ISSUANCE_NOT_FOUND';
	end if;
	if p_artifact_type = 'DOCX' then
		v_expected_sha256 := rtrim(v_issuance.docx_sha256);
		v_expected_bytes := v_issuance.docx_bytes;
		v_expected_content_type := 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
		v_expected_path := 'issuances/' || p_issuance_id::text || '/docx/' || v_expected_sha256 || '.docx';
	else
		v_expected_sha256 := rtrim(v_issuance.pdf_sha256);
		v_expected_bytes := v_issuance.pdf_bytes;
		v_expected_content_type := 'application/pdf';
		v_expected_path := 'issuances/' || p_issuance_id::text || '/pdf/' || v_expected_sha256 || '.pdf';
	end if;
	if v_expected_sha256 is null or v_expected_bytes is null then
		raise exception using errcode = 'P0001', message = 'ARTIFACT_EVIDENCE_NOT_AVAILABLE';
	end if;

	select * into v_event
	from public.quote_request_quotation_artifact_events
	where operation_id = p_idempotency_key;
	if found then
		if v_event.event_type <> 'ARTIFACT_RECONCILED'
			 or v_event.issuance_id <> p_issuance_id
			 or v_event.artifact_type <> p_artifact_type
			 or v_event.evidence->'sha256' is distinct from to_jsonb(p_observed_sha256)
			 or v_event.evidence->'byte_count' is distinct from to_jsonb(p_observed_bytes)
			 or v_event.evidence->'content_type' is distinct from to_jsonb(p_observed_content_type) then
			raise exception using errcode = 'P0001', message = 'IDEMPOTENCY_CONFLICT';
		end if;
		return query select v_event.event_id, v_event.evidence->>'outcome', false;
		return;
	end if;

	select * into v_artifact
	from public.quote_request_quotation_artifacts
	where quote_request_quotation_artifacts.issuance_id = p_issuance_id
		and quote_request_quotation_artifacts.artifact_type = p_artifact_type;
	select objects.metadata into v_storage_metadata
	from storage.objects as objects
	where objects.bucket_id = 'quotation-artifacts'
		and objects.name = v_expected_path;
	v_object_present := found;

	if not v_object_present then
		v_outcome := 'MISSING_OBJECT';
	elsif v_artifact.artifact_id is null then
		v_outcome := 'ORPHAN_OBJECT';
	elsif p_observed_sha256 = v_expected_sha256
			and p_observed_bytes = v_expected_bytes
			and p_observed_content_type = v_expected_content_type
			and coalesce(v_storage_metadata->>'size', '') ~ '^[0-9]+$'
			and (v_storage_metadata->>'size')::bigint = v_expected_bytes
			and v_storage_metadata->>'mimetype' = v_expected_content_type then
		v_outcome := 'CONSISTENT';
	else
		v_outcome := 'METADATA_MISMATCH';
	end if;

	insert into public.quote_request_quotation_artifact_events (
		artifact_id, issuance_id, artifact_type, event_type,
		operation_id, actor, evidence
	) values (
		v_artifact.artifact_id, p_issuance_id, p_artifact_type,
		'ARTIFACT_RECONCILED', p_idempotency_key, p_actor,
		jsonb_build_object(
			'bucket', 'quotation-artifacts', 'path', v_expected_path,
			'sha256', p_observed_sha256, 'byte_count', p_observed_bytes,
			'content_type', p_observed_content_type,
			'object_present', v_object_present, 'outcome', v_outcome
		)
	) returning * into v_event;
	return query select v_event.event_id, v_outcome, true;
end;
$$;

alter table public.quote_request_quotation_artifacts enable row level security;
alter table public.quote_request_quotation_artifact_events enable row level security;

revoke all privileges on table public.quote_request_quotation_artifacts
from public, anon, authenticated, service_role;
revoke all privileges on table public.quote_request_quotation_artifact_events
from public, anon, authenticated, service_role;

revoke all on function public.prevent_quotation_artifact_history_mutation()
from public, anon, authenticated, service_role;
revoke all on function public.register_quotation_artifact_v1(uuid, text, text, bigint, text, uuid, text)
from public, anon, authenticated;
revoke all on function public.get_quotation_artifact_metadata_v1(uuid)
from public, anon, authenticated;
revoke all on function public.record_quotation_artifact_archive_failure_v1(uuid, text, text, uuid, text)
from public, anon, authenticated;
revoke all on function public.reconcile_quotation_artifact_v1(uuid, text, text, bigint, text, uuid, text)
from public, anon, authenticated;

grant execute on function public.register_quotation_artifact_v1(uuid, text, text, bigint, text, uuid, text)
to service_role;
grant execute on function public.get_quotation_artifact_metadata_v1(uuid)
to service_role;
grant execute on function public.record_quotation_artifact_archive_failure_v1(uuid, text, text, uuid, text)
to service_role;
grant execute on function public.reconcile_quotation_artifact_v1(uuid, text, text, bigint, text, uuid, text)
to service_role;

comment on table public.quote_request_quotation_artifacts is
	'Immutable metadata binding trusted archiver observations and private Storage objects to existing quotation issuance evidence.';
comment on function public.register_quotation_artifact_v1(uuid, text, text, bigint, text, uuid, text) is
	'Registers trusted archiver SHA-256 and byte observations only after matching immutable issuance evidence and coherent Storage metadata; it does not hash binary content in PostgreSQL.';
