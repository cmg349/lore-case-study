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