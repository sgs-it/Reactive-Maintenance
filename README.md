# RMCS — Reactive Maintenance Control System

RMCS helps Italian Planters LLC manage landscape and irrigation maintenance across UAE sites. A Manager or Engineer creates a project for a client and site. All roles can register individual **Service Requests** against it, record field work and photographs, and submit the work for verification. Clients can follow their authorized jobs and see approved results after closure.

**Release stage:** ready for a controlled, single-site pilot. The local web build, Flutter checks, backend integration suite and a disposable database restore have passed. Live CompanyCam delivery, hosted recovery, physical-device acceptance and capacity for the planned 200 users still require verification on the intended deployment.

[Daily workflow](#working-in-rmcs) · [Access by role](#roles-and-job-access) · [Windows quick start](#run-locally-on-windows) · [Managed deployment](#deploy-with-supabase) · [API reference](#api-reference) · [Tests and rollout](#verification-commands)

## Working in RMCS

| Screen | How it is used |
| --- | --- |
| Dashboard | Review open work, in-progress requests and closures. Select a metric to open its queue. Staff also see overdue work. |
| Projects | Managers and Engineers register the project name, location, emirate and client. Grant job access to individual accounts and link a CompanyCam project. One job can have many service requests. |
| Service Requests | Register the title, description, category, priority, required action and UAE due date. The signed-in person is the requester. Selecting Other requires a category description. Priorities are Critical, High, Medium and Low. Search by reference or site, filter by job and assignee, and open the request for actions, activity and photos. |
| Alerts | Open assignments, returned work, requests due today or tomorrow, overdue work and pending reviews. Engineers and Managers see alerts after two or more recorded provider upload failures for the same request in 24 hours. The open workspace refreshes approximately every minute. |
| Reports | On the web portal, authorized reviewers can filter, inspect charts and download Excel or PDF. The status and assignee charts operate on the selected records. |
| Profile | Review the signed-in identity, change the password and sign out. Engineers and Managers can open **User Accounts** here. |

### Example field workflow

1. A Manager or Engineer creates the project and grants access to the Supervisor, field worker and client.
2. Users with project access select **New Service Request** to record an irrigation leak. An Engineer assigns a Supervisor. That Supervisor assigns a Team Leader / Foreman with active project access. **Assignment Tracking** records both handoffs. **Profile → My Request Tracking** shows requests the person raised, assigned or received.
3. The assignee starts work, captures a **Before** photo, updates progress and remarks, and submits completed work for verification. The assignee can put work on hold and resume it.
4. A Supervisor, Manager or Engineer verifies the work or returns it for rework. Verification sends the request to Engineer review. At this stage an Engineer can return it for correction or close it with resolution notes.
5. The Engineer approves individual Before or After photos for the client. A client with active job access can see approved photos after closure. Reopening sends the request back to rework. The activity history retains the earlier actions.

### Roles and job access

| Role (stored value) | Responsibilities within authorized jobs |
| --- | --- |
| Team Leader / Foreman (`foreman`) | Register requests, view shared staff photos, upload photos and update work assigned to them. |
| Supervisor (`supervisor`) | Staff functions plus assignment, verification, return for rework and web reports. |
| Manager (`manager`) | Create projects, grant access, register requests, review work, export reports and manage accounts. |
| Engineer (`engineer`) | Create jobs, grant access, administer accounts they create, assign and verify work, approve client photos, close and reopen requests. Can export reports. |
| Client (`client`) | View granted jobs, simplified request status and approved completion photos. Create service requests within granted projects and track their assignment history. |

A role determines permitted actions. A job grant determines where a person can act, and an assignment determines who can update the work. Grants can have a start and end time. The API checks the current grant when serving protected records and images. Client responses omit internal descriptions, progress photos and review remarks.

In **Profile → User Accounts**, only a Manager can create or link an account. Engineers and Managers can manage eligible existing accounts they created and schedule access to jobs they can share. Only Managers can assign or edit the Manager role. Changing a managed user’s role or deactivating the account ends its RMCS sessions.

### Queues, reports and site history

Use **Unassigned**, **Due Today**, **Overdue** or **Awaiting Verification** with a site and staff filter to plan a shift. Assignee choices show matching request counts. **Open** means the initial open status. **All Unclosed** also includes assigned, in-progress, on-hold, rework and review stages. Due Today and Overdue use the UAE calendar and exclude closed requests.

Excel includes request number, site, client, title, category, priority, status, assignee, received date, due date, closure date, calendar days and overdue flag. PDF provides a printable summary of the filtered requests. Calendar days run from receipt to closure, or to today for an active or reopened request. Time on hold counts toward this measure.

Reports show the oldest active request age by assignee and group repeated categories at a site. A repeated category is a lead for investigation. **Site repair history** opens other accessible requests matching the client, site and location, including each request’s gallery.

### Field drafts and photos

In **Update Progress** or **Add Photo**, use **Save Draft** to keep one progress update and one photo per request, per user, server and device. Start with an online sign-in and an accessible request. Open **Alerts** on the same device to review or discard a draft. Reopen the form and send it when connected. Clearing browser or app data can remove unsent drafts. In-app alerts refresh while RMCS is open.

In **New Service Request**, select a linked project and choose **Attach Photo** or use **Take Photo** on mobile. **Create and Upload Photo** saves the request and sends the attachment to the selected CompanyCam project as a Before photo. An interrupted upload can be retried from the same form.

Photos use **Before**, **Progress** and **After** stages. Upload a JPEG, PNG or WebP up to 10 MB. Native mobile screens offer camera and gallery controls. Staff can filter the gallery by uploader group. The backend tracks a retry reference and image checksum. If CompanyCam registration is uncertain, reconcile the reference before attempting another registration.

## Architecture and repository

| Component | Purpose and source |
| --- | --- |
| Flutter and Dart | Shared responsive web, Android and iOS client. Screens, API calls, report charts and device drafts live in [app/lib](app/lib). The Italian Planters branding is in [app/assets](app/assets). |
| Node.js 24 and TypeScript | Serves the compiled web app and HTTP API. Handles authentication, job authorization, workflow transitions, image streaming and exports. See [server/src](server/src). |
| Supabase Auth and PostgreSQL | Individual identities and operational records. The managed installation uses a private `rmcs` schema, restricted runtime role and limited Auth metadata views. See [schema](server/schema.sql) and [runtime grants](deploy/supabase-runtime.sql). |
| CompanyCam | Stores permanent photo files in projects created for RMCS jobs. PostgreSQL stores provider IDs, stage, uploader, timestamps and approvals. |
| Docker and Caddy | Package the prebuilt web client with Node and terminate HTTPS at the proxy. See the [Dockerfile](Dockerfile), [Supabase Compose file](compose.supabase.yaml) and [Caddy configuration](deploy/Caddyfile). |

The Flutter client calls Node. Node checks the RMCS session, role and job access before reading records or contacting CompanyCam. The database contains users and sessions, jobs and dated access grants, requests and their activity history, photos and upload claims. The UI calls these records **Service Requests**. Existing database tables and HTTP routes retain the identifier `complaints`.

## Run locally on Windows

With a Flutter SDK providing Dart 3.12.2 or compatible 3.x and Node.js 24 installed, set `DATABASE_URL`, `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` from the same Supabase project in the workspace root `.env` or the server environment. For TLS and first-account setup, see the [deployment guide](deploy/supabase-companycam.md). Then open PowerShell in this folder and run:

```powershell
.\scripts\start-local.ps1
```

Open [the local portal](http://127.0.0.1:8080) and sign in with a Supabase email and password linked to an RMCS role. Create and link the first Engineer account using the deployment guide. Ctrl+C stops the web server.

## Deploy with Supabase

1. Install the managed schema and runtime grants in the intended Supabase project. On an existing installation, check whether the [account access migration](deploy/supabase-account-access.sql) has already been applied. In managed mode an administrator installs migrations and the API validates the schema at startup.
2. Enable email/password authentication. Create and confirm the first real Engineer in Supabase Auth, then link the Auth UUID and email to an active RMCS Engineer record. The exact SQL and TLS certificate instructions are in the [managed backend guide](deploy/supabase-companycam.md#sg-solutions-managed-backend).
3. Configure the server using the table below. On a new checkout copy [.env.example](.env.example) to a private root `.env`. Preserve an existing deployment’s settings. Use a direct or session-pooler connection appropriate to the host, with certificate verification enabled.
4. Build the Flutter web bundle and start the managed deployment from the repository root.

   ```sh
   cd app
   flutter pub get
   flutter build web --no-web-resources-cdn
   cd ..
   docker compose -f compose.supabase.yaml up -d --build
   ```

5. Point your domain to the VM and allow HTTPS and HTTP for Caddy. Open `https://YOUR-DOMAIN/api/health` and verify `{"ready":true}`. Sign in as the first Engineer, create a pilot job, grant access and verify a second user’s view. Health checks cover database connectivity. The photo workflow has its own acceptance test.

### Configuration reference

| Setting | Where and why |
| --- | --- |
| `DATABASE_URL` | Server-side PostgreSQL connection string. In the managed deployment use the RMCS runtime login. |
| `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` | Auth project URL and publishable key from the same project as the database. |
| `SUPABASE_SECRET_KEY` | Optional server-only credential enabling **Create Supabase Sign-in**. An administrator can also create the identity in Supabase and link it in RMCS. |
| `RMCS_DATABASE_MANAGED` | Set `true` for the administrator-provisioned private schema. |
| `RMCS_AUTH_MODE` | Defaults to `supabase`. The separate standalone Compose deployment selects `local`. |
| `COMPANYCAM_KEY` | Server-side application key for project and photo operations. |
| `RMCS_DOMAIN` | Public hostname used by the Compose HTTPS proxy. |
| `POSTGRES_PASSWORD` | Password for PostgreSQL in the standalone Compose deployment. |
| `HOST`, `PORT`, `WEB_ROOT` | Optional Node settings. Outside Docker the defaults serve `app/build/web` on `127.0.0.1:8080`. |
| `RMCS_API_ORIGIN` | Flutter build-time setting for the API origin. Use the company HTTPS address for distributed mobile builds. |

Store production passwords, database URLs and provider secrets in the host’s secret store or restricted environment file. Use separate credentials and databases for testing.

## Oracle Cloud pilot with standalone PostgreSQL

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
   docker compose run --rm \
     -e RMCS_USER_EMAIL -e RMCS_USER_NAME -e RMCS_USER_ROLE -e RMCS_USER_PASSWORD \
     app node src/seed.ts
   ```

5. Confirm the HTTPS portal opens, `/api/health` returns `{"ready":true}`, and the Engineer account can sign in. Set up independent encrypted database backups and perform a restore test before onboarding staff.

Oracle's [Always Free resource documentation](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm) describes Ampere A1 capacity limits, home-region availability and idle-instance reclamation. The deployment files target a pilot VM. Monitor resources and backup health before expanding use.

## CompanyCam setup

For a hosted Supabase database, individual staff and client logins, and the full CompanyCam setup and verification steps, see [Supabase and CompanyCam setup](deploy/supabase-companycam.md).

Register a private application in your paid CompanyCam account and create an Application Key with project creation and photo read/write access. Store it as `COMPANYCAM_KEY` in the server environment, then recreate the app container. The adapter uses [CompanyCam Public API v1](https://developers.companycam.com/api-reference), including its signed upload flow. PostgreSQL stores only photo metadata and IDs. The API checks job access before streaming a photo.

New CompanyCam projects use the entered Project Name. RMCS leaves address fields blank. Engineers can retry linking from **Projects**. Staff with access can upload directly from a linked project or attach photos to individual service requests. Existing managed installations need the [project photo upload migration](deploy/supabase-project-photos.sql). Existing CompanyCam projects are not imported or listed. A photo registration with an uncertain provider response stays pending, preventing an automatic duplicate. Reconcile it in CompanyCam using the RMCS upload reference in the photo description.

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

To run integration tests, start a local RMCS API in `RMCS_AUTH_MODE=local` on an isolated PostgreSQL database named `rmcs_test_<suffix>`. Keep the live CompanyCam key unset. Set `RMCS_TEST_ORIGIN` and `RMCS_TEST_DATABASE_URL` to the corresponding API and database, both at `127.0.0.1`, then run `npm test` from `server`. Use a disposable database because tests add records and Supabase Auth fixtures to it. The Supabase Auth integration test simulates the provider's HTTPS responses and checks the actual PostgreSQL session gates.

## API reference

Paths below are relative to `/api`. Sign in with `POST /login` and supply the returned RMCS token as `Authorization: Bearer <token>` for protected calls. Health and login are public. The server evaluates job grants and role permissions on protected operations. See the [HTTP handlers](server/src/server.ts), [workflow transitions](server/src/workflow.ts) and [report filters](server/src/reports.ts).

| Method and route | Operation |
| --- | --- |
| `GET /health` | Check API and database readiness. |
| `POST /login`, `POST /logout`, `POST /account/password` | Start a session, end it or change the signed-in user’s password. |
| `GET /workspace` | Read the caller’s visible jobs and requests, with role-specific data. |
| `GET /accounts`, `POST /accounts` | List managed accounts or create/link an account. |
| `POST /accounts/{id}`, `POST /accounts/{id}/jobs/{jobId}` | Update a managed account or set its job grant and visibility window. |
| `POST /jobs`, `POST /jobs/{id}/access`, `POST /jobs/{id}/companycam` | Create a job, grant access or link its CompanyCam project. |
| `POST /complaints`, `GET /complaints/{id}` | Register a service request or read its role-specific detail and photo records. |
| `POST /complaints/{id}/actions` | Assign, start, update, hold, submit, verify, return for rework, close or reopen. |
| `POST /complaints/{id}/photos/{stage}` | Upload raw image bytes with the image content type and a 48-character lowercase hexadecimal `Idempotency-Key`. |
| `GET /photos/{id}/image`, `POST /photos/{id}/approve` | Stream an authorized image or record Engineer approval. |
| `GET /reports/complaints.xlsx`, `GET /reports/complaints.pdf` | Export using optional `scope`, `job`, `assignee` and `search` query parameters. |

## Troubleshooting and recovery

| Symptom | What to check |
| --- | --- |
| Sign-in fails for a newly created user | Verify the Auth email is confirmed, the password is correct, and the active RMCS account links to that Auth UUID in the configured project. The current login form supports password-only accounts. |
| Sign-in succeeds but the workspace is empty | Check the job grant and its start/end time. For field updates also check who is assigned to the request. |
| A CompanyCam project or image is missing | Run `npm run check:companycam` from `server`. Check key expiry, project/photo permissions, outbound HTTPS and the job address. Verify the link and an actual upload in CompanyCam. |
| A request action is rejected | Refresh the request. Check its current stage, the caller’s role and the assignee. Another team member may already have advanced it. |
| The web page loads but health fails | Check API logs, the runtime database login, TLS certificate mount, connection string and installed schema. |
| Records appear missing after migration | Confirm which database and schema the new server uses. A new connection string alone does not transfer records. |

For a recovery drill, restore an independent backup into an isolated environment. Run the [restore verification SQL](deploy/verify-restore.sql) on the restored database and compare it with the matching source snapshot. Include grants, Auth identity linkage and photo-reference fingerprints. Sign in as staff and client and open a previously approved photo. PostgreSQL restores the reference. The original image must also remain available in CompanyCam.

The latest local verification covered five passing backend tests, two Flutter widget tests, static analysis and the web release build. The disposable restore retained all 14 test photo references. The concurrent test exercised eight 1 MiB uploads and 16 workspace reads with simulated CompanyCam responses. Before wider release, repeat the workflow on the intended phones, domain, Supabase project and CompanyCam account, and measure concurrent use on the actual host. Follow the [rollout verification procedure](deploy/supabase-companycam.md#rollout-verification).
