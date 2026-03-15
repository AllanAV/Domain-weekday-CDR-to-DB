# NetSapiens CDR Pipeline (n8n + Supabase)

This repository contains n8n workflows and a PostgreSQL schema that implement an end‑to‑end NetSapiens CDR pipeline:

- Ingest CDRs from the NetSapiens ns-api v2 endpoint into Postgres/Supabase.
- Store them in a normalized `netsapiens_cdrs` table.
- Expose a web-based CDR dashboard backed by those records. [file:1][file:3][file:3]

---

## Repository Contents

- `DomainWeekdayCdrToDb.json`  
  n8n workflow that fetches CDRs from the NetSapiens API on a schedule and upserts them into Postgres/Supabase. [file:1]

- `Cdr_Dashboard.json`  
  n8n workflow that exposes a webhook endpoint, queries CDRs from `netsapiens_cdrs`, and serves an interactive HTML dashboard. [file:3]

- `ns_cdr_db.sql` (from `ns_cdr_db.txt`)  
  SQL DDL for the `netsapiens_cdrs` table and supporting indexes used by both workflows. [file:3]

---

## Overview

### 1. CDR Ingestion Workflow (`DomainWeekdayCdrToDb.json`)

This workflow pulls CDRs from the NetSapiens ns-api v2 CDR endpoint and upserts them into a Postgres/Supabase table. [file:1]

**Key components**

- **Triggers**
  - Manual Trigger: for ad‑hoc runs. [file:1]
  - Schedule Trigger: cron-based, configured to run daily on weekdays (adjustable). [file:1]

- **Configuration**
  - `Configuration` (Set node) defines:
    - `DOMAIN` – target NetSapiens domain (from `vars.GLOBALDOMAIN` by default).
    - `NSSERVER` – NetSapiens API host (from `vars.PRODSERVER` by default).
  - These values are used to build the base URL:  
    `https://{{NSSERVER}}/ns-api/v2/domains/{{DOMAIN}}/cdrs`. [file:1]

- **Date Range Logic**
  - `Calculate Date Range` (Code node) computes “yesterday” as a full‑day window:
    - `STARTDATETIME`: `YYYY-MM-DD 00:00:00`
    - `ENDDATETIME`: `YYYY-MM-DD 23:59:59`
    - `FETCHDATE`: `YYYY-MM-DD` (for logging/table naming) [file:1]
  - Designed for a daily batch that always pulls the previous day only. [file:1]

- **API Request**
  - `GET CDRs v2 API` (HTTP Request node) calls the NetSapiens CDR endpoint with:
    - Query parameters: `datetime-start`, `datetime-end`, `limit`.  
    - Header: `Authorization: Bearer TOKEN` (placeholder; you attach a real HTTP Bearer credential in n8n). [file:1]
  - Supports offset-based pagination until fewer than `limit` records are returned, with a configurable max requests cap. [file:1]

- **Field Mapping**
  - `Map CDR Fields` (Code node) transforms raw CDR JSON into a flattened, type‑safe structure that matches the `netsapiens_cdrs` schema:
    - API identifiers: `cdrid`, `domain`, `reseller`, `coreserver`.
    - Call identifiers and basics: `callorigcallid`, `calltermcallid`, `calldirection`, routing info, etc.
    - Timestamps and durations.
    - Origination/termination details, media relay, intelligence, disposition, billing, trace URLs, and flags. [file:1][file:3]
  - Skips records missing core fields such as `id` or `call-orig-call-id`. [file:1]

- **Conditional Upsert**
  - `Has Records?` (IF node) checks for an `skipped` flag to avoid DB work when no CDRs were returned. [file:1]
  - `Insert or update rows in a table` (Postgres node) upserts into `netsapienscdrs`:
    - `cdrid` is used as the unique key.
    - Columns are mostly auto‑mapped from the mapped JSON. [file:1]

---

### 2. Database Schema (`ns_cdr_db.sql`)

The SQL script creates the `netsapiens_cdrs` table and indexes expected by the workflows. [file:3]

**Table: `netsapiens_cdrs`**

- Internal
  - `row_id BIGSERIAL PRIMARY KEY`
  - `fetched_at TIMESTAMPTZ DEFAULT NOW()` [file:3]

- API‑level identifiers
  - `cdr_id TEXT UNIQUE`
  - `domain TEXT`
  - `reseller TEXT`
  - `core_server TEXT` [file:3]

- Call identifiers and basics
  - `call_orig_call_id`, `call_parent_call_id`, `call_parent_cdr_id`, `call_term_call_id`, `call_through_call_id`, `call_tag`. [file:3]
  - `call_direction TEXT` (API returns integer; stored as text for flexibility).
  - `call_routing_class INTEGER`, `call_routing_match_uri TEXT`, `call_server_mac_address TEXT`. [file:3]

- Datetimes
  - `call_start_datetime`, `call_ringing_datetime`, `call_answer_datetime`,
    `call_disconnect_datetime`, `call_record_creation_datetime` (all `TIMESTAMPTZ`). [file:3]

- Durations
  - `call_talking_duration_seconds`, `call_total_duration_seconds`,
    `call_on_hold_duration_seconds` (`INTEGER`), `call_disconnect_reason_text TEXT`. [file:3]

- Batch / multi‑leg
  - `call_batch_answer_datetime`, `call_batch_start_datetime`,
    `call_batch_sequence_marker`, `call_batch_total_duration_seconds`,
    `call_batch_on_hold_duration_seconds`, `call_leg_ordinal_index`. [file:3]

- Origination (caller)
  - Caller identity, URIs, routing, and classification:  
    `call_orig_caller_id`, `call_orig_from_name`, `call_orig_from_user`, `call_orig_from_host`,
    `call_orig_from_uri`, `call_orig_to_user`, `call_orig_to_host`, `call_orig_to_uri`,
    `call_orig_request_user`, `call_orig_request_host`, `call_orig_request_uri`,
    `call_orig_pre_routing_uri`, `call_orig_match_uri`, `call_orig_ip_address`,
    `call_orig_domain`, `call_orig_reseller`, `call_orig_department`, `call_orig_site`, `call_orig_user`. [file:3]

- Termination (called party)
  - `call_term_caller_id`, `call_term_to_uri`, `call_term_match_uri`,
    `call_term_pre_routing_uri`, `call_term_ip_address`, `call_term_domain`,
    `call_term_reseller`, `call_term_department`, `call_term_site`, `call_term_user`. [file:3]

- Through / transfer leg
  - `call_through_action`, `call_through_caller_id`, `call_through_uri`,
    `call_through_domain`, `call_through_reseller`, `call_through_department`,
    `call_through_site`, `call_through_user`. [file:3]

- Media relay (audio, video, fax)
  - Audio: codec, side‑A/B ports, remote IPs, packet counts. [file:3]
  - Video: codec, side‑A/B ports, remote IPs, packet counts. [file:3]
  - Fax: codec, side‑A/B ports, remote IPs, packet counts. [file:3]

- Intelligence / sentiment
  - `call_intelligence_job_id BIGINT`
  - `call_intelligence_percent_positive`, `call_intelligence_percent_neutral`,
    `call_intelligence_percent_negative` (`INTEGER`)
  - `call_intelligence_topics_top TEXT`
  - `ending_sentiment INTEGER` [file:3]

- Disposition / billing / trace
  - `call_disposition`, `call_disposition_direction`, `call_disposition_notes`,
    `call_disposition_reason`, `call_disposition_submitted_datetime`.
  - `call_account_code`.
  - `prefilled_trace_api`, `prefilled_transcription_api`. [file:3]

- Flags
  - `hide_from_results INTEGER`
  - `is_trace_expected BOOLEAN` [file:3]

**Indexes**

The script defines indexes tailored for typical CDR queries: [file:3]

- `idx_cdrs_cdr_id` on `cdr_id`
- `idx_cdrs_batch_start` on `call_batch_start_datetime`
- `idx_cdrs_start` on `call_start_datetime`
- `idx_cdrs_direction` on `call_direction`
- `idx_cdrs_orig_domain` on `call_orig_domain`
- `idx_cdrs_term_domain` on `call_term_domain`
- `idx_cdrs_orig_caller` on `call_orig_caller_id`
- `idx_cdrs_term_user` on `call_term_user`
- `idx_cdrs_intelligence_job` on `call_intelligence_job_id`

---

### 3. CDR Dashboard Workflow (`Cdr_Dashboard.json`)

This workflow exposes an HTTP endpoint that returns a browser‑based dashboard, built from the `netsapiens_cdrs` table. [file:3]

**Request flow**

1. **Webhook entry point**
   - `Webhook CDR Dashboard` (Webhook node):
     - `path`: `your-cdr-dashboard-path` (placeholder; set your own when deploying).
     - `responseMode`: `responseNode` (delegates response building to a later node). [file:3]

2. **Configuration**
   - `Config - Edit Here` (Set node) provides:
     - `DOMAIN` (from `vars.GLOBALDOMAIN`)
     - `NSSERVER` (from `vars.PRODSERVER`)
     - `DAYSBACK` (default `30`) [file:3]
   - These values are consumed by the date range logic and for potential future integrations. [file:3]

3. **Date Range**
   - `Calculate Date Range` (Code node) builds a rolling window:
     - From “today minus `DAYSBACK` days” at `00:00:00`
     - To “today” at `23:59:59`
     - Exposes `DATEFROM`, `DATETO`, `LABELFROM`, `LABELTO`. [file:3]

4. **CDR Query**
   - `Query Supabase CDRs` (Postgres node):
     - Uses a Postgres credential (`name: Postgres account`, credential ID redacted). [file:3]
     - Executes a `SELECT` from `netsapienscdrs` with a `WHERE` on `callbatchstartdatetime` between `json.DATEFROM` and `json.DATETO`. [file:3]
     - Returns a subset of columns relevant to the dashboard (direction, timestamps, durations, orig/term info, sentiment, disposition, account code, trace/transcription fields, etc.). [file:3]

5. **User / device normalization**
   - `Group by Base User` (Code node):
     - Strips NetSapiens device suffixes from user IDs (e.g., `775`, `775t`, `775wp`, `775i`, `775m`, `775ai`) to derive `baseuser`. [file:3]
     - Infers `devicetype` (Desk Phone, Web Portal, Softphone, iOS App, Mobile App, AI Agent) from the suffix. [file:3]
     - Attaches `baseuser` and `devicetype` to each record and passes all records as a single JSON array plus `total`. [file:3]

6. **HTML Dashboard Builder**
   - `Build Dashboard HTML` (Code node):
     - Embeds the records as JSON in a `<script>` block, carefully escaping `<`, `>`, and `&`. [file:3]
     - Injects CSS and JS for:
       - Top‑level KPIs (total calls, unique users, average duration, sentiment aggregates, missed calls).
       - Filters:
         - Direction (All, Inbound, Outbound, Missed).
         - Minimum talk duration (slider).
         - Sentiment type (positive/neutral/negative) and threshold.
         - User search (by base user). [file:3]
       - Grouped accordion view per base user:
         - Summary badges (call count, total duration, sentiment). [file:3]
         - Expandable table with per‑call details (direction, datetime, duration, caller, device, sentiment visualization, placeholder buttons for transcription/recording). [file:3]
       - CSV export of the filtered dataset. [file:3]

7. **HTTP Response**
   - `Respond Send Dashboard` (Respond to Webhook node):
     - Responds with the generated HTML (`responseBody: json.html`).
     - Sets `Content-Type: text/html; charset=utf-8`. [file:3]

---

## Requirements

- **n8n**
  - Any reasonably recent n8n version with:
    - HTTP Request, Webhook, Respond to Webhook, Postgres, Set, Code, and IF nodes available. [file:1][file:3]

- **NetSapiens API**
  - Access to the NetSapiens ns-api v2 CDR endpoint.
  - HTTP Bearer token configured in n8n credentials (`httpBearerAuth`). [file:1]

- **Postgres / Supabase**
  - A PostgreSQL-compatible database (e.g., Supabase) reachable from n8n.
  - Credentials stored in n8n as a Postgres credential (no DSN/password in this repo). [file:1][file:3]

- **Browser**
  - Any modern browser to view the CDR dashboard HTML.

---

## Setup

### 1. Create the CDR Table

1. In Supabase (or your Postgres client), run the SQL from `ns_cdr_db.sql`. [file:3]
2. Confirm `netsapiens_cdrs` exists with the expected columns and indexes.

### 2. Import and Configure the Ingestion Workflow

1. In n8n, import `DomainWeekdayCdrToDb.json`. [file:1]
2. Edit the HTTP Request node:
   - Attach your HTTP Bearer credential for the NetSapiens API.
3. Edit the Postgres node:
   - Attach your Postgres/Supabase credential pointing to the DB where `netsapiens_cdrs` lives.
4. Update the `Configuration` node:
   - Set `DOMAIN` as appropriate for your NetSapiens domain.
   - Set `NSSERVER` to your NetSapiens API host.
5. Adjust the schedule trigger to your desired run schedule (time, days, timezone).
6. Activate the workflow.

### 3. Import and Configure the Dashboard Workflow

1. In n8n, import `Cdr_Dashboard.json`. [file:3]
2. In `Config - Edit Here`:
   - Confirm `DOMAIN` and `NSSERVER` mappings are correct (or adjust as needed).
   - Adjust `DAYSBACK` for the dashboard’s rolling window (default 30). [file:3]
3. In `Query Supabase CDRs`:
   - Attach the same Postgres credential used by the ingestion workflow.
4. In `Webhook CDR Dashboard`:
   - Set `path` to your preferred URL path (the JSON uses `your-cdr-dashboard-path` as a placeholder).
   - Optionally protect it via n8n’s auth mechanisms or external reverse proxy/auth.

5. Activate the workflow and browse to the corresponding webhook URL to view the dashboard.

---

## Customization

- **Schema pruning**  
  If you do not need some media relay or intelligence fields, you can drop them from `ns_cdr_db.sql` and adjust the mapping in `Map CDR Fields` accordingly. [file:1][file:3]

- **Dashboard columns**  
  The SQL query and dashboard HTML only use a subset of fields. You can:
  - Add columns to the `SELECT` in `Query Supabase CDRs`.
  - Wire them into the dashboard builder for display or filtering. [file:3]

- **Filters and grouping**
  - Extend filters to include domains, account codes, disposition reasons, or custom tags.
  - Change grouping from `baseuser` to other dimensions (e.g., department, site) by modifying the grouping logic. [file:3]

---

## Security Notes

- No API tokens, passwords, hostnames, or customer data are stored in this repo; all secrets live in n8n credentials or environment variables. [file:1][file:3]
- Protect your running n8n instance:
  - Use HTTPS everywhere.
  - Restrict access to the dashboard webhook (auth, VPN, IP allowlists, or application firewall).
  - Use least‑privilege DB credentials (only required tables/operations).

---

## License

- This project is licensed under the MIT License.
- See the  [LICENSE](https://www.tldrlegal.com/license/mit-license)  file in this repository for the full license text.
