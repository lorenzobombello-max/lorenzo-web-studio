alter table lws_internal.operator_dossier_states
  drop constraint operator_dossier_states_shape_valid,
  add constraint operator_dossier_states_shape_valid check (
    (
      state = 'TRASHED'
      and state_before_trash is not null
      and state_before_trash in ('ACTIVE', 'ARCHIVED')
      and (
        deletion_eligible_at is null
        or deletion_eligible_at > updated_at
      )
    )
    or (
      state in ('ACTIVE', 'ARCHIVED')
      and state_before_trash is null
      and deletion_eligible_at is null
    )
  );

alter table lws_internal.operator_dossier_state_events
  drop constraint operator_dossier_state_events_retention_valid,
  add constraint operator_dossier_state_events_retention_valid check (
    (
      new_state = 'TRASHED'
      and state_before_trash is not null
      and state_before_trash in ('ACTIVE', 'ARCHIVED')
      and (
        deletion_eligible_at is null
        or deletion_eligible_at > occurred_at
      )
    )
    or (
      new_state <> 'TRASHED'
      and deletion_eligible_at is null
    )
  );

comment on column lws_internal.operator_dossier_states.deletion_eligible_at is
  'NULL explicitly means no purge or hard-delete authority. This column does not schedule cleanup.';
comment on column lws_internal.operator_dossier_state_events.deletion_eligible_at is
  'NULL records no purge or hard-delete authority for the transition event.';