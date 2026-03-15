-- Drop and recreate with full schema
DROP TABLE IF EXISTS netsapiens_cdrs;

CREATE TABLE netsapiens_cdrs (

  -- Internal
  row_id                               BIGSERIAL PRIMARY KEY,
  fetched_at                           TIMESTAMPTZ DEFAULT NOW(),

  -- API-level identifiers
  cdr_id                               TEXT UNIQUE,
  domain                               TEXT,
  reseller                             TEXT,
  core_server                          TEXT,

  -- Call identifiers
  call_orig_call_id                    TEXT,
  call_parent_call_id                  TEXT,
  call_parent_cdr_id                   TEXT,
  call_term_call_id                    TEXT,
  call_through_call_id                 TEXT,
  call_tag                             TEXT,

  -- Call basics (call_direction stored as TEXT; API returns integer)
  call_direction                       TEXT,
  call_routing_class                   INTEGER,
  call_routing_match_uri               TEXT,
  call_server_mac_address              TEXT,

  -- Datetimes
  call_start_datetime                  TIMESTAMPTZ,
  call_ringing_datetime                TIMESTAMPTZ,
  call_answer_datetime                 TIMESTAMPTZ,
  call_disconnect_datetime             TIMESTAMPTZ,
  call_record_creation_datetime        TIMESTAMPTZ,

  -- Durations
  call_talking_duration_seconds        INTEGER,
  call_total_duration_seconds          INTEGER,
  call_on_hold_duration_seconds        INTEGER,
  call_disconnect_reason_text          TEXT,

  -- Batch / multi-leg
  call_batch_answer_datetime           TIMESTAMPTZ,
  call_batch_start_datetime            TIMESTAMPTZ,
  call_batch_sequence_marker           TEXT,
  call_batch_total_duration_seconds    INTEGER,
  call_batch_on_hold_duration_seconds  INTEGER,
  call_leg_ordinal_index               INTEGER,

  -- Origination (caller)
  call_orig_caller_id                  TEXT,
  call_orig_from_name                  TEXT,
  call_orig_from_user                  TEXT,
  call_orig_from_host                  TEXT,
  call_orig_from_uri                   TEXT,
  call_orig_to_user                    TEXT,
  call_orig_to_host                    TEXT,
  call_orig_to_uri                     TEXT,
  call_orig_request_user               TEXT,
  call_orig_request_host               TEXT,
  call_orig_request_uri                TEXT,
  call_orig_pre_routing_uri            TEXT,
  call_orig_match_uri                  TEXT,
  call_orig_ip_address                 TEXT,
  call_orig_domain                     TEXT,
  call_orig_reseller                   TEXT,
  call_orig_department                 TEXT,
  call_orig_site                       TEXT,
  call_orig_user                       TEXT,

  -- Termination (called party)
  call_term_caller_id                  TEXT,
  call_term_to_uri                     TEXT,
  call_term_match_uri                  TEXT,
  call_term_pre_routing_uri            TEXT,
  call_term_ip_address                 TEXT,
  call_term_domain                     TEXT,
  call_term_reseller                   TEXT,
  call_term_department                 TEXT,
  call_term_site                       TEXT,
  call_term_user                       TEXT,

  -- Through / transfer leg
  call_through_action                  TEXT,
  call_through_caller_id               TEXT,
  call_through_uri                     TEXT,
  call_through_domain                  TEXT,
  call_through_reseller                TEXT,
  call_through_department              TEXT,
  call_through_site                    TEXT,
  call_through_user                    TEXT,

  -- Audio relay
  call_audio_codec                     TEXT,
  call_audio_relay_side_a_local_port   INTEGER,
  call_audio_relay_side_a_remote_ip    TEXT,
  call_audio_relay_side_a_packet_count BIGINT,
  call_audio_relay_side_b_remote_ip    TEXT,
  call_audio_relay_side_b_packet_count BIGINT,

  -- Video relay
  call_video_codec                     TEXT,
  call_video_relay_side_a_local_port   INTEGER,
  call_video_relay_side_a_remote_ip    TEXT,
  call_video_relay_side_a_packet_count BIGINT,
  call_video_relay_side_b_remote_ip    TEXT,
  call_video_relay_side_b_packet_count BIGINT,

  -- Fax relay
  call_fax_codec                       TEXT,
  call_fax_relay_side_a_local_port     INTEGER,
  call_fax_relay_side_a_remote_ip      TEXT,
  call_fax_relay_side_a_packet_count   BIGINT,
  call_fax_relay_side_b_remote_ip      TEXT,
  call_fax_relay_side_b_packet_count   BIGINT,

  -- Intelligence / sentiment
  call_intelligence_job_id             BIGINT,
  call_intelligence_percent_positive   INTEGER,
  call_intelligence_percent_neutral    INTEGER,
  call_intelligence_percent_negative   INTEGER,
  call_intelligence_topics_top         TEXT,
  ending_sentiment                     INTEGER,

  -- Disposition
  call_disposition                     TEXT,
  call_disposition_direction           TEXT,
  call_disposition_notes               TEXT,
  call_disposition_reason              TEXT,
  call_disposition_submitted_datetime  TIMESTAMPTZ,

  -- Billing
  call_account_code                    TEXT,

  -- Trace links
  prefilled_trace_api                  TEXT,
  prefilled_transcription_api          TEXT,

  -- Flags
  hide_from_results                    INTEGER,
  is_trace_expected                    BOOLEAN
);

-- Indexes for fast querying by other workflows
CREATE INDEX idx_cdrs_cdr_id           ON netsapiens_cdrs (cdr_id);
CREATE INDEX idx_cdrs_batch_start      ON netsapiens_cdrs (call_batch_start_datetime);
CREATE INDEX idx_cdrs_start            ON netsapiens_cdrs (call_start_datetime);
CREATE INDEX idx_cdrs_direction        ON netsapiens_cdrs (call_direction);
CREATE INDEX idx_cdrs_orig_domain      ON netsapiens_cdrs (call_orig_domain);
CREATE INDEX idx_cdrs_term_domain      ON netsapiens_cdrs (call_term_domain);
CREATE INDEX idx_cdrs_orig_caller      ON netsapiens_cdrs (call_orig_caller_id);
CREATE INDEX idx_cdrs_term_user        ON netsapiens_cdrs (call_term_user);
CREATE INDEX idx_cdrs_intelligence_job ON netsapiens_cdrs (call_intelligence_job_id);