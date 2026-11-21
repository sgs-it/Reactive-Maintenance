# RMCS setup with Supabase and CompanyCam

The Flutter app signs in through the RMCS Node.js API. Supabase Auth verifies email and password. Supabase PostgreSQL stores RMCS roles, job access, service requests, and photo references. CompanyCam stores the images. Complete the database and account setup first, then connect CompanyCam.

## SG Solutions managed backend

The managed installation keeps operational data in the private `rmcs` schema. The RMCS API uses the `rmcs_runtime` login with access to operational tables and limited Auth metadata. An administrator provisions the first Engineer in Supabase. Apply database changes with a Supabase migration owned by an administrator.

On the app host, set `RMCS_DATABASE_MANAGED=true` alongside `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, and the private `DATABASE_URL`. Use the Session pooler URL with username `rmcs_runtime.PROJECT_REF` for an IPv4 host, or the direct database URL with username `rmcs_runtime` for an IPv6 host. Keep TLS verification enabled. For a managed installation, carry out the provisioning steps below instead of running the account setup shell commands in section 2.

1. Open **Authentication → Users** and create the staff or client user with their individual email. Verify the address before confirming it. Copy the user's UUID.
2. In the project's **SQL Editor**, run the following after replacing the UUID and name and selecting the appropriate role. Start with an `engineer` and use the role table in section 2 for subsequent accounts. A repeated run keeps the current link and role.

   ```sql
   INSERT INTO rmcs.users (name, email, role, auth_user_id)
   SELECT 'FULL_NAME', lower(email), 'engineer', id
   FROM auth.users
   WHERE id = 'SUPABASE_USER_UUID'::uuid
     AND email_confirmed_at IS NOT NULL
     AND email IS NOT NULL
     AND lower(email) NOT LIKE '%@rmcs.demo'
   ON CONFLICT DO NOTHING
   RETURNING name, email, role;
   ```

3. Sign in with the email and password managed in Supabase. Grant job access individually and verify the account sees its expected jobs.

Managers use **Profile → User Accounts → Add User** to link confirmed Supabase users or create new sign-ins. Engineers and Managers can manage eligible existing accounts they created, including job visibility dates. Only Managers can assign or edit the Manager role. They can share jobs they can currently access. To create Supabase credentials directly from this screen, create a server API key under **Supabase → Project Settings → API Keys** and put it in the app host's private environment as `SUPABASE_SECRET_KEY`. Restart the RMCS server to enable **Create Supabase Sign-in**. Keep the key out of Flutter and source control. For a previously installed managed backend, apply [the account management migration](supabase-account-access.sql) before restarting. [Supabase API keys](https://supabase.com/docs/guides/api/api-keys)

For a new managed installation, install [the app schema](../server/schema.sql) in a new `rmcs` schema and apply [the runtime grants and Auth views](supabase-runtime.sql) as an administrator. Apply both files within the same migration with `SET LOCAL search_path TO rmcs, pg_catalog`. Provision a unique password for the runtime role separately from the migration, then store it in the deployment secret store.

## 1. Connect the RMCS server to Supabase

1. Open the Supabase project and select **Connect**. Copy the **Project URL** and **publishable key** into the server environment or root `.env` as `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`. Use the same project for `DATABASE_URL`. Choose **Direct connection** if the server can reach IPv6 or **Session pooler** if it uses IPv4. Substitute the database password and URL-encode any reserved characters. For a new RMCS installation, the default `postgres` role in the connection string can create the RMCS tables and read the required Auth metadata. For an existing installation, the selected role also needs to own the RMCS tables. [Supabase connection guide](https://supabase.com/docs/guides/database/connecting-to-postgres) · [Supabase Auth schema permissions](https://supabase.com/kb/troubleshooting/permission-errors-when-granting-custom-roles-access-to-the-auth-schema-9e32e7)
2. Set `DATABASE_URL` and, for Docker with HTTPS, `RMCS_DOMAIN`. Download the server certificate from **Database Settings → SSL Configuration** in Supabase and save it on the host as `.local/certs/supabase-ca.crt`. For Docker, append `?sslmode=verify-full&sslrootcert=/run/rmcs-db-certs/supabase-ca.crt` to the connection string. If it already has query parameters, append with `&`. For Node directly, use the path to the certificate on that machine, URL-encoded if needed. [Supabase SSL guidance](https://supabase.com/docs/guides/database/connecting-to-postgres#connecting-with-ssl)
3. Enable email/password in **Authentication**. In a dedicated RMCS project, disable **Allow new users to sign up** if account creation is managed exclusively by administrators. Keep RMCS tables unexposed in **Integrations → Data API**. The app schema enables Row-Level Security and revokes access for browser-facing roles as well. [Supabase Auth configuration](https://supabase.com/docs/guides/auth/general-configuration) · [Supabase Data API security](https://supabase.com/docs/guides/api/securing-your-api)
4. From the RMCS checkout on your build machine, build Flutter Web. Copy the resulting `app/build/web` directory to the same relative path on the server if you build on a separate machine.

   ```sh
   cd app
   flutter build web --no-web-resources-cdn
   cd ..
   ```

5. On your server, use the Supabase Compose configuration. It starts the API and HTTPS proxy and connects to the hosted database. For a server already running the API outside Docker, restart that service with the new environment instead.

   ```sh
   docker compose -f compose.supabase.yaml up -d --build
   ```

6. Open `https://YOUR-RMCS-DOMAIN/api/health` and confirm it returns `{"ready":true}`. On startup, the API creates missing RMCS tables, secures their grants, and disables any legacy demo logins. For an existing deployment, update it against the same database and keep the old database or a backup until you have verified the records. Changing a connection string alone does not copy records.

For a local Windows run against Supabase, save all three Supabase connection settings in the workspace root `.env`, then run `.\scripts\start-local.ps1` from the workspace root. The default address is `http://127.0.0.1:8080`. Use a separate Supabase project for test records.

## 2. Create one RMCS login per person

In **Supabase → Authentication → Users**, create a user with their individual email and a unique initial password. Confirm the email after verifying the address with the person. Copy the user's UUID. Run the following on the RMCS server to grant that user an RMCS role. Start with an Engineer account, then repeat for each staff member or client.

```bash
read -r -p 'Staff or client name: ' RMCS_USER_NAME
read -r -p 'Email address: ' RMCS_USER_EMAIL
read -r -p 'Supabase user UUID: ' RMCS_AUTH_USER_ID
read -r -p 'Role (foreman/supervisor/engineer/manager/client): ' RMCS_USER_ROLE
export RMCS_USER_NAME RMCS_USER_EMAIL RMCS_USER_ROLE RMCS_AUTH_USER_ID
docker compose -f compose.supabase.yaml run --rm --no-deps \
  -e RMCS_USER_NAME -e RMCS_USER_EMAIL -e RMCS_USER_ROLE -e RMCS_AUTH_USER_ID \
  app node src/seed.ts
unset RMCS_USER_NAME RMCS_USER_EMAIL RMCS_USER_ROLE RMCS_AUTH_USER_ID
```

For a Node.js deployment without Docker, run `npm run seed` from `server` with the same variables set. If the email and role match a legacy RMCS account, linking keeps its existing job access and history and clears its old password hash. Share initial passwords privately. Users can choose **Profile → Change Password** to update their Supabase password and end existing RMCS sessions. A session lasts up to the configured Supabase access token lifetime and at most 12 hours. The RMCS sign-in form supports password-only accounts. Accounts with an enrolled and verified MFA factor require an MFA sign-in flow before they can use RMCS. [Supabase sessions](https://supabase.com/docs/guides/auth/sessions)

On Windows PowerShell 7, run the following from `server`:

```powershell
$env:RMCS_USER_NAME = Read-Host 'Staff or client name'
$env:RMCS_USER_EMAIL = Read-Host 'Email address'
$env:RMCS_AUTH_USER_ID = Read-Host 'Supabase user UUID'
$env:RMCS_USER_ROLE = Read-Host 'Role (foreman/supervisor/engineer/manager/client)'
npm.cmd run seed
```

| Role value | RMCS role | Typical access |
| --- | --- | --- |
| `foreman` | Team Leader / Foreman | View granted jobs, update assigned work, and add photos |
| `supervisor` | Supervisor | Assign and review work on granted jobs |
| `engineer` | Engineer | Create jobs, grant job access, approve photos, close or reopen requests |
| `manager` | Manager | Assign and review work and export reports for granted jobs |
| `client` | Client | View granted jobs, public-facing statuses, and approved photos on closed requests |

1. Sign in as the engineer who owns or already has access to the job.
2. Open **Jobs**. Create the job if it does not exist.
3. Next to that job, select **Grant Job Access**. Enter each authorized person’s RMCS email separately. Repeat only for the jobs they should be able to view.
4. Open **Service Requests**, select a request, then use **Assign Request** to choose the staff member who will carry out the work. Job access determines what the user can see. Request assignment determines who can start and update the work.
5. Verify that each account sees its expected jobs and requests and that the client shows only client-facing information. Account creation by itself does not give access to another user’s jobs.

## 3. Register RMCS in CompanyCam

1. Sign in to the [CompanyCam web app](https://app.companycam.com/) with a CompanyCam Admin or Manager account that can use custom integrations.
2. Open **Integrations → Applications → New Application**.
3. Name it **RMCS – Italian Planters** and describe it as a private integration for job and service request photos. Use read/write access. An OAuth redirect URL is only relevant when setting up OAuth. RMCS authenticates with an Application Key. Select **Create Application**. [CompanyCam application registration](https://help.companycam.com/en/articles/15937352-registering-an-application)
4. Open **Integrations → Access Tokens → New Application Key** and select **RMCS – Italian Planters**.
5. Name the key **RMCS Backend**. If you use **Custom** permissions, grant the project and photo read/write permissions needed to create projects, upload images, and retrieve photos. If the custom permission screen does not give your integration the required upload access, use **Read & Write**. RMCS does not need Full Access or deletion permissions. Set an expiration that you can track and rotate the key before it expires. [CompanyCam Application Key instructions](https://help.companycam.com/en/articles/14724612-creating-access-tokens-and-application-keys)
6. Select **Create token** and copy the key. Store it only on the RMCS server as `COMPANYCAM_KEY`. Its access is tied to the creator’s permissions and can stop if that account is deactivated. Keep the key out of Flutter, source control, and support messages. RMCS and CompanyCam users each sign in to their own systems. A single server-side Application Key handles the integration for RMCS.

## 4. Configure and verify the CompanyCam key

1. Set `COMPANYCAM_KEY` in the private `.env` or server secret store. Use the value from **New Application Key**.
2. Recreate the app container so it receives the new variable.

   ```sh
   docker compose -f compose.supabase.yaml up -d --force-recreate app
   ```

3. Check the key without printing it or creating a CompanyCam job.

   ```sh
   docker compose -f compose.supabase.yaml exec app node src/check-companycam.ts
   ```

   For Node outside Docker, run `npm run check:companycam` from `server`. The check calls the token verification endpoint on [CompanyCam Public API v1](https://developers.companycam.com/api-reference). A successful check confirms CompanyCam accepts the key. The project and photo permissions are verified in the next section.

## 5. Test the job and photo workflow

1. Sign in to RMCS as an engineer and create a test job with a valid site and address. RMCS attempts to create a matching CompanyCam project. For an earlier unlinked job, select **Link CompanyCam Project** on the Projects page. That action creates the RMCS-managed project in CompanyCam.
2. Open CompanyCam and find the project by its entered name. Keep it private in CompanyCam if you plan to control client photo visibility through RMCS.
3. Create or open a service request for the test job and select **Add Photo**. Choose **Before**, **Progress**, or **After**, then upload a JPEG, PNG, or WebP up to 10 MB. Check that the photo is visible both in CompanyCam and in the RMCS request.
4. Confirm another authorized staff member can open the photo and filter by uploader group. Confirm a user without access to the job cannot view it.
5. As an engineer, use **Approve Photo** on a Before or After photo. After request verification and closure, sign in as an authorized client and check that the approved photos are visible.

## Troubleshooting

- **The health endpoint is unavailable.** Verify the database password, correct direct or session-pooler URI, TLS settings, and whether the Supabase project is active. Review the API startup logs on the server.
- **A staff member can sign in but sees an empty page.** Grant their account access to the intended job. For work updates, also assign the request to them.
- **The key check returns HTTP 401 or 403.** Check the key value, expiration, and permissions in CompanyCam. Ensure the creator still has access. After changing the key, recreate the container.
- **The key check succeeds but linking the job fails.** Verify project write access. RMCS sends the entered project name and empty address fields. If CompanyCam requires a populated address for your account, review the rejection before retrying.
- **Uploading fails or a thumbnail stays blank.** Confirm project and photo permissions. The app server needs outbound HTTPS to CompanyCam and the signed upload and image hosts returned by the API. Refresh once CompanyCam has processed the image. If RMCS reports a pending upload, check CompanyCam for the upload reference in the image description before retrying.
- **Rotating a key.** Create the replacement, update the server secret, recreate the app container, run the key check, and verify a photo upload before revoking the old key.
## Rollout verification

Test on a staging server using separate staff and client identities. Include two clients with different jobs. Record the build, database snapshot time, device, and results.

* In **Service Requests**, combine a site and assignee with Unassigned, Due Today, Overdue or Awaiting Verification. The UAE calendar determines deadlines. In **Reports**, use the same selections and compare the Excel and PDF results with the visible requests. Calendar days run from receipt through last closure (or today while reopened) and include on-hold periods.
* In **Alerts**, open an assignment, returned request or approaching deadline. Deadlines cover today and tomorrow. Engineers and managers also see two or more provider upload failures for the same request in 24 hours. Alerts refresh while the workspace is open.
* In **Update Progress** and **Add Photo**, save a draft, close the form, and reopen it from the same account and device. Alerts lists drafts for currently accessible requests. Drafts require an initial online sign-in and an accessible request. Sending is manual. Save one progress draft and one photo per request at a time. On a phone, interrupt an upload, reconnect, retry, and check the original in CompanyCam. If confirmation is pending, use the upload reference in CompanyCam before retrying registration.
* Take an independent encrypted backup using your hosting backup process, including RMCS records, grants, roles and the Supabase Auth recovery configuration. Restore to an isolated staging project. Compare the output of deploy/verify-restore.sql against the matching source snapshot with the RMCS schema first on search_path. Verify login, site isolation, access expiration and reopen an approved photo against CompanyCam. Database backups contain references; recovering CompanyCam originals depends on your provider account.
* Run the backend integration suite against a disposable local database as described in README. It includes concurrent photo transfers with simulated CompanyCam and mixed report/workspace reads. Measure real upload latency, failed requests, memory and database connections during a representative shift on the intended host before inviting all 200 users.
