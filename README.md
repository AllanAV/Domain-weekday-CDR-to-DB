# NetSapiens CDR to Supabase via n8n

This repository contains an n8n workflow and a PostgreSQL schema that ingest NetSapiens CDRs from the NetSapiens API into a Supabase (PostgreSQL) table for analytics and downstream automation. [file:1][file:2]

## Contents

- `DomainWeekdayCdrToDb.json`  
  n8n workflow that:
  - Calculates a daily date range (yesterday, aligned to weekdays). [file:1]
  - Pulls CDRs from the NetSapiens API (`ns-api/v2/domains/{DOMAIN}/cdrs`) with pagination. [file:1]
  - Maps raw CDR JSON fields into normalized keys. [file:1]
  - Upserts records into a `netsapiens_cdrs` table in Postgres/Supabase. [file:1]

- `ns_cdr_db.sql` (from `ns_cdr_db.txt`)  
  SQL DDL to create the `netsapiens_cdrs` table and supporting indexes matching the workflow’s mapped fields. [file:2]

## Architecture

At a high level:

1. A schedule trigger (and optional manual trigger) kicks off the workflow on weekdays. [file:1]
2. A configuration step injects `DOMAIN`, `NSSERVER`, and related settings from n8n variables. [file:1]
3. A code node computes the previous calendar day’s full window and exposes:
   - `START_DATETIME` (`YYYY-MM-DD 00:00:00`)
   - `END_DATETIME` (`YYYY-MM-DD 23:59:59`)
   - `FETCH_DATE` (for table naming or logging)
   - `LIMIT` (page size) [file:1]
4. An HTTP Request node calls the NetSapiens CDR v2 API with `datetime-start`, `datetime-end`, and `limit`, using Bearer-token auth and offset-based pagination. [file:1]
5. A mapping code node converts the raw NetSapiens JSON into a flattened object with stable column names that align with the database schema. [file:1][file:2]
6. An IF node checks whether any CDRs were returned and skips the DB work if the batch is empty. [file:1]
7. A Postgres node upserts rows into `netsapiens_cdrs`, keyed by `cdr_id`. [file:1][file:2]

## Database Schema

The table is created by `ns_cdr_db.sql` (originally `ns_cdr_db.txt`), which:

- Drops and recreates `netsapiens_cdrs`. [file:2]
- Defines columns for:
  - Internal meta `row_id` (PK), `fetched_at`. [file:2]
  - API identifiers: `cdr_id`, `domain`, `reseller`, `core_server`. [file:2]
  - Call identifiers, basics, timestamps, and durations. [file:2]
  - Origination and termination details (caller/called side, URIs, domains, departments, site, user). [file:2]
  - Media relay (audio, video, fax), intelligence/sentiment, disposition, billing, trace URLs, and flags. [file:2]
- Creates indexes for common access patterns (e.g., by `cdr_id`, `call_start_datetime`, `call_orig_domain`, `call_term_domain`, `call_intelligence_job_id`). [file:2]

You should run this DDL (or an adapted version) in your Supabase/Postgres project before enabling the workflow.

## Requirements

- **n8n** instance with:
  - Access to the NetSapiens ns-api v2 CDR endpoint.
  - Network access to your Supabase/Postgres database.
- **NetSapiens API credentials**:
  - HTTP Bearer token configured in an n8n HTTP credential (`httpBearerAuth`). [file:1]
- **Supabase/Postgres credentials**:
  - n8n Postgres credential pointing at your database. [file:1][file:2]
- **Environment / variables in n8n**:
  - `GLOBALDOMAIN` (default CDR domain).
  - `PRODSERVER` (NetSapiens API host; used to build the base URL).
  - Any other variables referenced by your configuration node. [file:1]

## Setup

1. **Create the CDR table**

   - Copy the contents of `ns_cdr_db.sql` into your SQL editor for Supabase (or any Postgres client) and run it against your target database. [file:2]
   - Confirm the `netsapiens_cdrs` table exists with the expected columns and indexes. [file:2]

2. **Import the n8n workflow**

   - In n8n, go to “Workflows” → “Import from file” and select `DomainWeekdayCdrToDb.json`. [file:1]
   - Save the imported workflow.

3. **Configure credentials**

   - Edit the HTTP Request node labeled something like `GET CDRs v2 API` and attach your HTTP Bearer credential. [file:1]
   - Edit the Postgres node (`Insert or update rows in a table`) to use your Supabase/Postgres credential. [file:1]

4. **Set configuration values**

   - Open the `Configuration` (Set) node and ensure:
     - `DOMAIN` is set appropriately (or mapped from `vars.GLOBALDOMAIN`).
     - `NSSERVER` points to your NetSapiens host (e.g., `your-netsapiens-host.example.com`). [file:1]
   - Adjust any defaults like `LIMIT` if required. [file:1]

5. **Enable scheduling**

   - Review the schedule trigger node (e.g., `Schedule Trigger Tue–Sat 00:00`) and adjust the cron expression, timezone, and run window to match your requirements. [file:1]
   - Activate the workflow once you are satisfied with the configuration.

## How the Date Range Logic Works

The `Calculate Date Range` code node:

- Computes “yesterday” relative to the current server time.
- Outputs a full-day window:
  - `START_DATETIME` at `00:00:00`
  - `END_DATETIME` at `23:59:59`
- Uses the schedule pattern (Tue–Sat) so that “yesterday” always resolves to a weekday (Mon–Fri). [file:1]

This makes it safe to run daily for a prior-day batch without gaps or overlaps, assuming the workflow runs once per day on schedule.

## Customization

You can adjust the following aspects easily:

- **Time window / backfill**  
  - For backfill, temporarily switch to the manual trigger, override the date range logic to run for a broader historical window, then switch back to the daily schedule. [file:1]

- **Pagination / batch size**  
  - Increase or decrease `LIMIT` to trade off between API calls and memory usage per run. The HTTP Request node supports offset-based pagination until fewer than `LIMIT` records are returned. [file:1]

- **Columns and schema**  
  - If you do not need some fields (for example, detailed media relay or intelligence metrics), you can:
    - Remove those columns from the DDL. [file:2]
    - Remove or ignore the corresponding mappings in the `Map CDR Fields` code node. [file:1]

- **Additional indexes**  
  - Add indexes for your usage patterns (e.g., by `call_account_code` or `call_disposition`) directly in the SQL file. [file:2]

## Security Considerations

- No secrets or tokens are stored in this repository; all sensitive credentials are referenced via n8n’s credentials system. [file:1]
- The workflow assumes HTTPS access to the NetSapiens API and to Supabase; ensure you maintain TLS everywhere in production.
- Restrict database credentials to the minimal privileges required (insert/update on `netsapiens_cdrs` and related indices).

## Troubleshooting

- **No records inserted**  
  - Check the IF node condition for `json.skipped` – if no CDRs are returned for the date range, the workflow will exit early by design. [file:1]
  - Manually hit the NetSapiens CDR endpoint (using the same parameters) to verify that CDRs exist for the given window. [file:1]

- **Schema mismatch errors**  
  - Ensure your `netsapiens_cdrs` column names match exactly with the mapped JSON keys from the `Map CDR Fields` node. [file:1][file:2]

## License

Add your preferred license here (for example, MIT), along with any attribution or usage notes relevant to your environment.
