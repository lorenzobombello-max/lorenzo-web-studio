begin;

alter function public.get_operator_website_quotation_pricing_state_v1(uuid,uuid,uuid)
  rename to get_operator_website_quotation_pricing_state_pre_billing_v1;

create function public.get_operator_website_quotation_pricing_state_v1(
  p_actor_auth_user_id uuid,
  p_quote_request_id uuid,
  p_intake_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  v_pricing jsonb;
  v_request public.quote_requests%rowtype;
begin
  v_pricing:=public.get_operator_website_quotation_pricing_state_pre_billing_v1(
    p_actor_auth_user_id,p_quote_request_id,p_intake_id
  );
  select * into strict v_request
  from public.quote_requests
  where id=p_quote_request_id;
  return v_pricing || jsonb_build_object(
    'billing_context_complete',
      lws_internal.is_iso_3166_1_alpha2_v1(v_request.billing_country),
    'billing_context',jsonb_build_object(
      'billing_address',v_request.billing_address,
      'billing_postal_code',v_request.billing_postal_code,
      'billing_city',v_request.billing_city,
      'billing_country',v_request.billing_country,
      'billing_email',v_request.billing_email
    )
  );
end;
$$;

revoke all on function public.get_operator_website_quotation_pricing_state_pre_billing_v1(uuid,uuid,uuid)
  from public,anon,authenticated,service_role;
revoke all on function public.get_operator_website_quotation_pricing_state_v1(uuid,uuid,uuid)
  from public,anon,authenticated,service_role;
grant execute on function public.get_operator_website_quotation_pricing_state_v1(uuid,uuid,uuid)
  to authenticated;

comment on function public.get_operator_website_quotation_pricing_state_v1(uuid,uuid,uuid) is
  'Caller-bound Website pricing and canonical billing-context projection for quotation preparation.';

commit;