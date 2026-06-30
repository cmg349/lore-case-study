# How Eligibility Data Moves Through the System

This document explains, in plain terms, what happens to a person’s eligibility record from the moment a partner sends it to us, through to the point where someone can use it to confirm they’re covered. It is written for a product, operations, or business audience, not an engineering one.

---

## The big picture

Think of this system as a sorting and verification facility for benefits eligibility data. Partners (employers, HR platforms, benefits administrators) send us lists of who is covered and under what plan. Our job is to receive that data safely, check it for quality, decide what’s trustworthy enough to act on, and then make it available for real-time eligibility checks.

The journey has five natural phases:

```
  RECEIVE  →  CLEAN & SEPARATE  →  QUALITY CHECK  →  APPROVE & PUBLISH  →  VERIFY
```

---

## Before the data arrives: setting up a partner

Before a partner can send us data, we configure the system to understand their specific format. Every partner is different, they use different field names, different codes for the same values, different file layouts, and different rules about what’s required. Rather than building custom code for each one, all of that knowledge lives in configuration.

When a new partner is onboarded, we capture:

- **How their data is delivered**, file, direct connection, or live event stream
- **What their fields mean**, which column in their file maps to which concept in our system
- **How their codes translate**, for example, their `"EMP"` becomes our `"employee"`, their `"ELIGIBLE"` becomes `"active"`
- **What the quality rules are**, which fields must be present, what formats are required, what values are acceptable, and how serious each violation is
- **How personal data should be handled**, which fields are sensitive, whether they need encryption or additional masking, and how long they can be kept

This means onboarding a new partner is a configuration exercise, not a software development project. It also means that if a partner changes their data format or renegotiates their data quality rules, we update the configuration, we don’t change the code.

---

## Phase 1: Receiving the data

A partner sends us a file or a data feed, this could be a spreadsheet dropped on a secure server, a direct system-to-system connection, or a live event stream as records change on their end.

When that delivery arrives, we immediately register it as a batch, a named, timestamped delivery event. We record where it came from, how it arrived, and what file it was (using a checksum, a kind of digital fingerprint). That fingerprint means if the same file is accidentally sent twice, we catch it immediately and don’t process it again.

At this point the data is sitting in our intake area. Nothing has been approved or published yet.

---

## Phase 2: Cleaning and separating the data

Each person’s record in that delivery gets processed one by one. This step does three important things simultaneously.

**Normalizing the record.** Using the partner configuration set up at onboarding, we translate everything into a common internal format so the rest of the system always speaks the same language, regardless of where the data came from.

**Separating personal information.** Personal details, name, date of birth, home address, phone number, email, are immediately split out and stored in a separate, more tightly controlled location. The main record that flows through the rest of the pipeline contains employment and eligibility information (start dates, plan codes, status) but no personal data. This means the majority of the system never needs to touch sensitive personal information, which limits exposure and simplifies compliance.

**Creating identity fingerprints.** We generate a set of one-way fingerprints from personal details, things like a fingerprint of someone’s email address, phone number, or name-plus-date-of-birth combination. These fingerprints are stored alongside the record and are used later (in Phase 5) to match a person without ever needing to look at their actual personal data. Because they’re one-way, the fingerprint cannot be reversed to recover the original information.

---

## Phase 3: Quality checking

Every record is now run through the validation rules configured for that specific partner. These rules check things like:

- Are all the required fields present?
- Do dates make sense (e.g. an end date isn’t before a start date)?
- Are coded values ones we recognize?
- Is this person’s email address in a valid format?
- Is this person’s email unique, or does it clash with someone already in the system?

Each rule can be set at different severity levels:

- **Blocking**, the record has a problem serious enough that we won’t use it until it’s fixed. The record goes into a quarantine queue for review.
- **Warning**, there’s something worth noting, but it’s not serious enough to stop the record from being used.
- **Informational**, low-level flags for awareness only.

At the end of this step, every record has a quality score and a status: clean, clean-with-warnings, or quarantined. The batch itself gets a summary of how many records fell into each category.

Records that are quarantined go into a review queue where an operations team member (or the partner themselves) can investigate and resolve the issue. Once resolved, those records can be resubmitted through the pipeline without the partner needing to re-send the file.

---

## Phase 4: Approving and publishing

Records that passed quality checking are now candidates for publication, making them available to the rest of the business. Before any record is published, it passes through a final approval gate. This gate checks a series of conditions in order:

1. Did it pass quality checking? (Blocked records can’t proceed.)
2. Does it contain any prohibited personal data?
3. Is it flagged for manual review?
4. Has the personal data fingerprinting process completed successfully?
5. Is all the required organizational information present?
6. Does the record identify a specific person?
7. Is the person an employee? (The current system only publishes employee records, dependents and other relationship types are held.)
8. Does the eligibility status make sense?
9. Are the eligibility dates valid?
10. Are there any unresolved issues from the quarantine review queue?

Every record that passes is written to the published layer, one entry per person per partner. If that person already had a record, the previous version is archived rather than deleted, so we always have a complete history of how their eligibility has changed over time.

**Whether someone is currently eligible is always computed in the moment it’s asked, not stored as a fixed answer.** This matters because eligibility can lapse when a coverage end date passes, even if the partner hasn’t sent an updated file. By calculating it fresh each time from the dates and status on the record, the answer is always accurate without waiting for the next data delivery.

Every attempt to publish a record, whether it succeeds, is skipped as a duplicate, or fails, is logged permanently. This log is the authoritative source of truth for what happened and when.

A real-time notification is also sent the moment a record is published, so any downstream systems that care about eligibility changes can react immediately.

---

## Phase 5: Verifying identity at the point of use

When a person actually needs to use their benefits, at a pharmacy, a provider, or an enrollment portal, they need to prove they’re who they say they are and that they’re covered. This is handled by a separate, on-demand process.

The person submits identifying information. Critically, **we never receive their raw personal details at this stage**, instead, the submitting system sends us the same kind of fingerprints we created in Phase 2. We compare those fingerprints against our stored records.

We score each potential match based on which fingerprints matched. A name-plus-date-of-birth fingerprint is worth more than a phone number alone, for example. A partner employee ID fingerprint is worth more than either. The match score determines the outcome:

- **One clear match above the confidence threshold** → automatically approved.
- **Multiple possible matches, or a score below the threshold** → routed to a human reviewer.
- **No matches** → denied.

The decision, approved, denied, or sent for review, is recorded permanently and cannot be changed after the fact, providing a clear audit trail for any disputed verification.

---

## Background maintenance

Running quietly in the background, two housekeeping processes keep the published layer accurate over time:

**Expiry sweeping** (runs nightly): Some eligibility records have an end date. When that date passes, the record is automatically marked as expired, even if the partner hasn’t sent an updated file yet. This ensures anyone checking eligibility in real time gets an accurate answer.

**Data retention** (runs on a schedule): Personal data is only kept for as long as policy and law require. When a record’s retention period expires and there’s no legal reason to keep it (such as an active dispute or investigation), it is permanently deleted, including the personal information vault.

---

## Who can see what

The system is designed so that one partner’s data is completely invisible to another, and so that access within our own teams is limited to exactly what’s needed.

Every record in the system is tagged with four labels: which partner it belongs to, which tenant manages it, which organizational unit it falls under, and which geographic region it’s in. The database enforces these boundaries automatically, a connection that is authorized for Partner A cannot read Partner B’s data, regardless of what query it runs. This isn’t just application-layer filtering; the database itself refuses to return rows outside the authorized scope.

Within our own infrastructure, two levels of access exist. The application role used for day-to-day operations can read and write data but cannot restructure the database. A separate administration role is used only for migrations and internal tooling; it has unrestricted access but is never used by the live application. These roles are granted only the minimum permissions they need to function.

---

## What happens when something goes wrong

The system is designed so that problems at any stage don’t break the whole pipeline.

- A bad record doesn’t block the good ones in the same batch.
- A batch that fails partway through can be safely restarted, already-processed records are skipped automatically.
- Quarantined records sit in a review queue, not in a black hole, they can be fixed and resubmitted without asking the partner to re-send data.
- If a validation rule changes (e.g. a partner renegotiates what values are acceptable), affected records can be reprocessed against the new rules without re-ingesting any data. The reprocessing system can target a whole batch, all records for a partner, or just the specific records whose quarantine issues have been resolved.

Every outcome at every step is permanently logged. There is no record of “what happened to this person’s data” that disappears.

# lore-case-study
Strategic Data System for Trusted Partner Eligibility &amp; Identity Verification
---------------------------------------------------------------------------------
Scenario: 
We are onboarding several key partners to acquire eligibility data, containing personally identifiable information (PII), essential for identity verification and serving as the definitive source of truth for new user account creation in our application. This inbound data arrives in diverse formats, often presents inconsistencies and data quality challenges, and necessitates strict adherence to privacy regulations. The integrated solution must efficiently handle an initial bulk load of historical eligibility data and sustain continuous, incremental updates reflecting attrition and changes within each partner's eligibility pool. 

Task: 
Outline your strategic vision for integrating and managing this critical eligibility data. Your response should detail how you would establish clear data quality standards and PII governance requirements, including assessing data quality and identifying appropriate privacy controls (e.g., anonymization, pseudonymization) and compliance measures. Propose a comprehensive data integration strategy that robustly supports both the initial bulk ingestion and ongoing change data capture (CDC) for incremental updates, defining key performance and freshness requirements. Describe your plan for an automated data cleansing and curation process that ensures consistency, accuracy, and continuous compliance, along with a high-level design for the identity verification system that leverages this cleansed and curated data as its source of truth, articulating its availability and reliability requirements. As a hands-on component, provide a SQL DDL schema for key table(s) in your cleansed/curated eligibility data store, and a code snippet or SQL query illustrating how you would identify or cleanse a specific type of data inconsistency (e.g., duplicate PII, format errors). Throughout, explain your technical and architectural justifications, considering factors like data profiling, transformation techniques, and overall data security. 

--------------------------------

Local deploy
------------
```bash
# Install dependency
pip install -r requirements.txt

# Set connection details (defaults: localhost:5432/postgres as postgres)
export PGDATABASE=lore_eligibility
export PGUSER=postgres
export PGPASSWORD=

# Apply all migrations
python sql-data-mapping/database/migrate.py

# Check status
python sql-data-mapping/database/migrate.py --status

# Dry run
python sql-data-mapping/database/migrate.py --dry-run

# Roll back last migration
python sql-data-mapping/database/migrate.py --rollback

# Roll back to a specific point
python sql-data-mapping/database/migrate.py --target 011
```
-------------------------------

tech Debt:  
- ~~Down migrations for 012~~
- ~~Running into issues with the promotion logic, had to make a lot of "patch" migrations from 12-15. Need to consolidate them.~~
- ~~schema migration tracker and if migrations are dirty/clean~~
- remove GCP based regions since I am not going forward with a GCP/TF build due to tokens needed for GCP (don't have enough)
- ~~Depending on enforcement needed I set "ENABLE ROW LEVEL SECURITY" not "FORCE ROW LEVEL SECURITY" ... This will still allow bypass of RLS for admin and migrations. In a production enviornment I would force this but generate specific users with bypass permissions on.  These users/accounts would be app specific. Being as it is and not granting my application to have table ownership these should work just fine.~~
- ~~place holder for data cleansing/ DQ function... need to add this later~~
- ~~Only promoting employee records, not dependants need to address this moving forward.~~
- ~~need schema migration tracker~~
- ~~I need to revisit the is_crruently_eligible, looks like I have a stale data issue here.. would have to remove this.. but that would be very distruptive atm Hotfix: I could update the view?~~



Notes:
- want to add tests as CI/CD in github via actions but will save until later.. currently just using manual sql
- identity verification is going to require roles, that I will then need to apply RLS permissons over
- Need to create a small py app that interacts with this DB locally.. prob dont NEED to have it but would make a walk through easier as im heavily focusing on the DB.
- Should I consider policy tags here? If I were to make this more prod level and getting into analytics data sets I would want a DBT/ SQL Mesh resource with tagged data make sure data is permissionsed properly.
- Given that this data will deal with PII, and by extesion since Lore deals with health data HIPAA policy tags and possible GCP SDP with a cloud implementation.
- SDP to apply annon/ puedo anno to data (one way hash, determin. etc)
- If we are expecting flat files I might set up a GCS layer that has SDP sit over the top of if and scan new files as they come in, store results in a table (bigquery?) using the file hash as a key. This would allow us to reference the sensitive data per file and allow duplication detection in the same bound.
- Would host this psql DB in cloud sql
- DOB is bound to "vault" due to PII... would we want this to be quried outside of the vault?

Future state/ questions
- Who are the stalk holders of this data asset?
- Being Lore is GCP, would access to this be granted on Goolge Groups or strictly application interaction via things like SA?
- What is our contract retention period for data?
- Are their EU customers that would need to be considered in this? (GDPR)
- Deletion of data concerns; Would this system need to support one off data deletions? (GDPR, CCPA, CPRA)
- What is the expected volume (through put) here and where would we want to look for scale? 
- will this need to support real/ near-real time? 
- Are we supporting a DWH with this data or other down stream applications?
- do we have any existing data contracts with down stream applications/ infra?
- What level of hand holding is done with a customer being onbaords? How are fields being mapped?
- right now this is targeted at eligibility files, will there be an expansion into HRA, BIO, Tella health?
- Are there current infra system wide UUID patterns that would need to be followed?
- given CDC is there any analysis of this data we would need to see data transformation over time or via point in time? (IE SCD2)
- Idenity matching is fairly simplisitc and would be less clean in a prod envi.
- What would be the lag acceptance of records?


RLS:
Application vars need set:
SET app.partner_id = 'partner_acme'; --test account
SET app.tenant_id = 'tenant_001'; --test tenant
SET app.org_id = 'org_hq';
SET app.data_region = 'us-east-1';