-- Run with the RMCS schema first on search_path. Compare on a quiescent
-- source and isolated restore, or with a manifest from the backup snapshot.
SELECT count(*) AS requests, count(DISTINCT job_id) AS jobs_with_requests,
       count(*) FILTER (WHERE status='closed') AS closed
FROM complaints;
SELECT count(*) AS photo_links,
       md5(coalesce(string_agg(md5(json_build_array(j.id,j.companycam_project_id,
         c.id,p.id,p.provider_id,p.stage,p.approved_at)::text),'' ORDER BY p.id),'')) AS link_fingerprint
FROM photos p JOIN complaints c ON c.id=p.complaint_id JOIN jobs j ON j.id=c.job_id;
SELECT count(*) AS job_grants, count(DISTINCT user_id) AS users_with_grants FROM job_access;
