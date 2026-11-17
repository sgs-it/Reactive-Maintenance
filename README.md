# RMCS

Reactive Maintenance Control System for field staff, supervisors, engineers, managers and clients. Flutter targets Android, iOS and the responsive web portal. Node.js serves the API and web build. PostgreSQL stores operational records, permissions, history and CompanyCam photo references.

## Local demo on Windows

With Flutter, Node.js 24 and PostgreSQL 18 installed, open PowerShell in this folder and run:

```powershell
.\scripts\start-demo.ps1
```

Open [the local portal](http://127.0.0.1:8080). Select an account under **Local Demo Accounts**. The role buttons sign in to the local API with fictional data. To try the workflow, the Team Leader can select **Start Work** and **Submit for Verification** on an assigned service request. The Supervisor can select **Verify Work**, then the Engineer can select **Close Request**. The Client account can see the service requests for Verdant Gardens.

You can also enter `engineer@rmcs.demo` and `rmcs-demo-2026` in the sign-in form. The other demo emails are `foreman@rmcs.demo`, `supervisor@rmcs.demo`, `manager@rmcs.demo` and `client@rmcs.demo`. They share the demo password.

If PostgreSQL is installed elsewhere, pass `-PostgresBin 'C:\path\to\bin'`. Ctrl+C stops the web server. To stop the separate demo database, run the installed `pg_ctl.exe -D .local/demo-db stop`.

## Service request workflow

- Engineers create RM jobs and grant existing staff and client accounts access by email.
- Authorized staff create service requests with priority, required action and a UAE target closing date. Supervisors, engineers and managers allocate work and review submitted jobs.
- The assignee starts work, logs progress, can put work on hold and submits completed work. Reviewers can return work for correction. Only an Engineer can close or reopen a service request. The API records who took each action and when.
- Clients see their assigned sites and simplified service request statuses. Approved Before and After photos appear after closure. Internal descriptions, assignments, remarks and progress photos are excluded from client responses.
- Staff can see CompanyCam photos on service requests for their authorized jobs and filter by uploader group. Supervisors, engineers and managers can download Excel and PDF reports for the filtered register in the web portal.

## Oracle Cloud pilot

1. Provision an OCI Linux VM in the tenancy home region with Docker and the Compose plugin. Configure the domain DNS and permit TCP 80/443 for the app and restricted SSH access for administration. The database port stays internal to the Compose network.
2. Transfer the source. Copy `.env.example` to `.env` and set `RMCS_DOMAIN` and a random hex `POSTGRES_PASSWORD`. Keep the file on the host with restricted permissions.
3. Build the web bundle with the installed Flutter SDK, or transfer the resulting `app/build/web` directory from the build machine.

   ```sh
   cd app
   flutter build web --no-web-resources-cdn
   cd ..
   docker compose up -d --build
   ```

4. Provision each account in a trusted shell. Set `RMCS_USER_EMAIL`, `RMCS_USER_NAME`, `RMCS_USER_ROLE` and `RMCS_USER_PASSWORD` in the shell, supplying the password through your secret manager or a hidden prompt. Roles are `foreman`, `supervisor`, `engineer`, `manager` and `client`.

   ```sh
   docker compose run --rm +     -e RMCS_USER_EMAIL -e RMCS_USER_NAME -e RMCS_USER_ROLE -e RMCS_USER_PASSWORD +     app node src/seed.ts
   ```

5. Confirm the HTTPS portal opens, `/api/health` returns `{"ready":true}`, and the Engineer account can sign in. Set up independent encrypted database backups and perform a restore test before onboarding staff.

Oracle's [Always Free resource documentation](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm) describes Ampere A1 capacity limits, home-region availability and idle-instance reclamation. The deployment files target a pilot VM. Monitor resources and backup health before expanding use.

## CompanyCam setup

Register a private application in your paid CompanyCam account and create an Application Key with project creation and photo read/write access. Store it as `COMPANYCAM_KEY` in the server environment, then recreate the app container. The adapter uses [CompanyCam Public API v1](https://developers.companycam.com/api-reference), including its signed upload flow. PostgreSQL stores only photo metadata and IDs. The API checks job access before streaming a photo.

Start with one new test job. Project creation uses the RM job code, site and stable job ID. For the pilot mapping it uses the entered location as the street address, the emirate for city and state, and `00000` as the UAE postal placeholder. Verify address validation with CompanyCam. If the automatic project link fails, the Engineer can select **Link CompanyCam Project** under **Jobs**. Existing CompanyCam projects are not imported or listed. A photo registration with an uncertain provider response stays pending, preventing an automatic duplicate. Reconcile it in CompanyCam using the RMCS upload reference in the photo description.

Live project creation, upload and image retrieval require validation with the company's Application Key. Use a sandbox or designated test project before enabling company-wide access.

## Native builds

```sh
cd app
flutter build apk --dart-define=RMCS_API_ORIGIN=https://rmcs.example.com
flutter build ipa --dart-define=RMCS_API_ORIGIN=https://rmcs.example.com
```

Use the actual pilot domain in both commands. Without the build-time origin, the mobile sign-in screen accepts the company's HTTPS server URL. iOS build and signing require macOS and Xcode. Android distribution needs the company's release signing setup.

## Historical workbooks

| Workbook sheet | Treatment |
| --- | --- |
| Helpdesk Records / AMC Projects List | Historical site and job-code reference |
| Helpdesk Records / RM Log | Historical issues, original RM references and status text |
| Helpdesk Records / History RM Report | Historical reporting reference |
| Landscape Complaint Tracking Register / Complaint Register | Historical complaint, priority, assignment and date fields |
| VO Status, Indoor Plants FOC Log, Old Job Numbers | Keep in the original workbook for future mapping |

The read-only `scripts/profile_workbooks.py` script uses Python and `openpyxl`. It reports 600 job references, 934 RM Log rows with descriptions, two duplicate RM reference groups and 21 complaint register entries. Twenty of the 21 closed register entries lack a valid closing date. Historical import remains a separate follow-up after status and closure review. Operational records use generated UUIDs and unique RM numbers.

## Verification commands

```text
cd server
npm run check
npm test
cd ../app
flutter analyze
flutter test
```

Set `RMCS_TEST_ORIGIN` to a running API backed by a disposable copy of the demo database to run the integration test. It creates a test job and complaint and checks account isolation, closure, history and both exports. Keep the live CompanyCam key unset in this test environment.
