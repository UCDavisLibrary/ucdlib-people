CREATE TABLE IF NOT EXISTS lib_employee_change_request(
  lib_employee_change_request_id UUID 
    PRIMARY KEY DEFAULT gen_random_uuid(),
  request_type VARCHAR(50) NOT NULL
    CONSTRAINT chk_lib_emp_change_req_type
    CHECK (request_type IN ('onboarding', 'separation', 'permissions', 'transfer', 'meta-update')),
  lib_employee_id UUID
    REFERENCES lib_employee(lib_employee_id) ON DELETE RESTRICT,
  lib_employee_supervisor_id UUID
    REFERENCES lib_employee(lib_employee_id) ON DELETE SET NULL,
  lib_group_id UUID
    REFERENCES lib_group(lib_group_id) ON DELETE SET NULL,
  lib_employee_forbidden BOOLEAN NOT NULL DEFAULT FALSE,
  parent_lib_employee_change_request_id UUID
    REFERENCES lib_employee_change_request(lib_employee_change_request_id) ON DELETE CASCADE,
  payload JSONB NOT NULL DEFAULT '{}',
  submitted_by_app_user_id VARCHAR(200) REFERENCES app_user(app_user_id) ON DELETE SET NULL,
  effective_date DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_lib_emp_change_req_employee_required
    CHECK (request_type = 'onboarding' OR lib_employee_id IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS lib_employee_change_request_action (
  lib_employee_change_request_action_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lib_employee_change_request_id UUID NOT NULL
    REFERENCES lib_employee_change_request(lib_employee_change_request_id) ON DELETE CASCADE,
  action_key VARCHAR(100) NOT NULL,
  action_type VARCHAR(100) NOT NULL,
  config JSONB NOT NULL DEFAULT '{}',
  is_automated BOOLEAN NOT NULL,
  depends_on TEXT[] NOT NULL DEFAULT '{}',
  scheduled_for DATE,
  status VARCHAR(20) NOT NULL DEFAULT 'pending'
    CONSTRAINT chk_lib_emp_change_req_action_status
    CHECK (status IN ('pending', 'done', 'skipped', 'failed')),
  performed_by_app_user_id VARCHAR(200) REFERENCES app_user(app_user_id) ON DELETE SET NULL,
  performed_at TIMESTAMPTZ,
  assigned_to VARCHAR(50),
  label TEXT,
  description TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0,
  completion_data JSONB NOT NULL DEFAULT '{}',
  notes TEXT,
  attempt_count INTEGER NOT NULL DEFAULT 0,
  last_attempted_at TIMESTAMPTZ,
  last_error TEXT,
  external_system VARCHAR(50),
  external_id VARCHAR(100),
  external_subject TEXT,
  external_status VARCHAR(100),
  external_status_checked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (lib_employee_change_request_id, action_key),
  CONSTRAINT chk_lib_emp_change_req_action_done_has_time
    CHECK (status NOT IN ('done', 'skipped') OR performed_at IS NOT NULL),
  CONSTRAINT chk_lib_emp_change_req_action_human_has_performer
    CHECK (is_automated OR status NOT IN ('done', 'skipped') OR performed_by_app_user_id IS NOT NULL),
  CONSTRAINT chk_lib_emp_change_req_action_external_pair
    CHECK ((external_system IS NULL) = (external_id IS NULL))
);

-- the job's work queue: pending system actions
CREATE INDEX idx_lib_emp_change_req_action_pending_system
  ON lib_employee_change_request_action (scheduled_for)
  WHERE status IN ('pending', 'failed') AND is_automated = TRUE;


-- Checks if all dependencies for a given action are met (i.e. done or skipped)
CREATE OR REPLACE FUNCTION lib_emp_change_req_action_deps_met(a lib_employee_change_request_action)
  RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT NOT EXISTS (
      SELECT 1
      FROM unnest(a.depends_on) AS d(dep_key)
      JOIN lib_employee_change_request r
        ON r.lib_employee_change_request_id = a.lib_employee_change_request_id
      LEFT JOIN lib_employee_change_request_action dep
        ON dep.lib_employee_change_request_id =
            CASE WHEN d.dep_key LIKE 'parent:%'
                  THEN r.parent_lib_employee_change_request_id
                  ELSE r.lib_employee_change_request_id END
      AND dep.action_key = regexp_replace(d.dep_key, '^parent:', '')
      WHERE dep.status IS NULL OR dep.status NOT IN ('done', 'skipped')
    )
$$;

-- Returns true if an automated action is ready to run. Used by both the sweep's candidate query
-- and the re-check after locking, so the two can't disagree. Conditions:
--   - automated, status pending or failed
--   - under the retry limit
--   - retry backoff elapsed (15 min, 1 hr, then 4 hrs between attempts)
--   - scheduled_for reached (America/Los_Angeles)
--   - all dependencies met
-- a: lib_employee_change_request_action row
-- max_attempts: stop retrying after this many attempts
CREATE OR REPLACE FUNCTION lib_emp_change_req_action_is_runnable(
  a lib_employee_change_request_action,
  max_attempts INTEGER DEFAULT 5
)
  RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT a.is_automated
      AND a.status IN ('pending', 'failed')
      AND a.attempt_count < max_attempts
      AND (a.last_attempted_at IS NULL OR a.last_attempted_at <= now() -
           CASE a.attempt_count
             WHEN 0 THEN interval '0'
             WHEN 1 THEN interval '15 minutes'
             WHEN 2 THEN interval '1 hour'
             ELSE interval '4 hours'
           END)
      AND (a.scheduled_for IS NULL
           OR a.scheduled_for <= (now() AT TIME ZONE 'America/Los_Angeles')::date)
      AND lib_emp_change_req_action_deps_met(a)
$$;

-- Returns runnable automated actions, oldest first.
-- root_request_id: if provided, limit to this request and all its descendants; otherwise all requests
-- max_attempts: passed through to lib_emp_change_req_action_is_runnable
CREATE OR REPLACE FUNCTION get_runnable_lib_emp_change_req_actions(
  root_request_id UUID DEFAULT NULL,
  max_attempts INTEGER DEFAULT 5
)
  RETURNS SETOF lib_employee_change_request_action LANGUAGE sql STABLE AS $$
    WITH RECURSIVE family AS (
      SELECT lib_employee_change_request_id
      FROM lib_employee_change_request
      WHERE lib_employee_change_request_id = root_request_id
      UNION ALL
      SELECT r.lib_employee_change_request_id
      FROM lib_employee_change_request r
      JOIN family f ON r.parent_lib_employee_change_request_id = f.lib_employee_change_request_id
    )
    SELECT a.*
    FROM lib_employee_change_request_action a
    WHERE lib_emp_change_req_action_is_runnable(a, max_attempts)
      AND (root_request_id IS NULL
           OR a.lib_employee_change_request_id IN (SELECT lib_employee_change_request_id FROM family))
    ORDER BY a.created_at
$$;

-- Returns a display status for an action, explaining why a pending action hasn't run yet.
-- cancelled: skipped by an admin (completion_data.cancelled = true)
-- done, skipped, failed: same as status
-- blocked: pending, dependencies not met
-- scheduled: pending, scheduled_for is in the future (America/Los_Angeles)
-- waiting: pending, waiting on a person (human action) or on child requests (await_children)
-- queued: pending, automated, will run on the next check
-- a: lib_employee_change_request_action row
CREATE OR REPLACE FUNCTION lib_emp_change_req_action_display_status(a lib_employee_change_request_action)
  RETURNS text LANGUAGE sql STABLE AS $$
    SELECT CASE
      WHEN a.status = 'skipped' AND (a.completion_data ->> 'cancelled')::boolean THEN 'cancelled'
      WHEN a.status IN ('done', 'skipped', 'failed') THEN a.status
      WHEN NOT lib_emp_change_req_action_deps_met(a) THEN 'blocked'
      WHEN a.scheduled_for > (now() AT TIME ZONE 'America/Los_Angeles')::date THEN 'scheduled'
      WHEN NOT a.is_automated OR a.action_type = 'await_children' THEN 'waiting'
      ELSE 'queued'
    END
$$;


CREATE TABLE IF NOT EXISTS lib_employee_change_request_revision (
  lib_employee_change_request_revision_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lib_employee_change_request_id UUID NOT NULL
    REFERENCES lib_employee_change_request(lib_employee_change_request_id) ON DELETE CASCADE,
  revision_number INTEGER NOT NULL,
  payload JSONB NOT NULL,
  submitted_by_app_user_id VARCHAR(200) REFERENCES app_user(app_user_id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (lib_employee_change_request_id, revision_number)
);

-- All change requests with their employee, supervisor, group, submitter, parent request, and actions.
-- lib_employee: object, or null (e.g. onboarding before the employee record is created)
-- lib_employee_supervisor: object, or null
-- lib_group: object, or null
-- action_count, outstanding_action_count: outstanding = not done or skipped (cancelled counts as skipped)
-- submitted_by_app_user: object, or null
-- parent_lib_employee_change_request: object, or null if top-level
-- actions: array of every action column plus a performed_by_app_user object (or null) and
--   display_status (see lib_emp_change_req_action_display_status), [] if none.
--   ordered by created_at (groups actions added together, e.g. by a later revision), then sort_order
CREATE OR REPLACE VIEW lib_employee_change_request_full AS
SELECT
  r.*,
  CASE WHEN su.app_user_id IS NULL THEN NULL ELSE
    jsonb_build_object(
      'app_user_id', su.app_user_id,
      'first_name', su.first_name,
      'last_name', su.last_name,
      'email', su.email
    )
  END AS submitted_by_app_user,
  CASE WHEN e.lib_employee_id IS NULL THEN NULL ELSE
    jsonb_build_object(
      'lib_employee_id', e.lib_employee_id,
      'iam_id', e.iam_id,
      'user_id', e.user_id,
      'email', e.email,
      'first_name', e.first_name,
      'last_name', e.last_name
    )
  END AS lib_employee,
  CASE WHEN sup.lib_employee_id IS NULL THEN NULL ELSE
    jsonb_build_object(
      'lib_employee_id', sup.lib_employee_id,
      'iam_id', sup.iam_id,
      'user_id', sup.user_id,
      'email', sup.email,
      'first_name', sup.first_name,
      'last_name', sup.last_name
    )
  END AS lib_employee_supervisor,
  CASE WHEN g.lib_group_id IS NULL THEN NULL ELSE
    jsonb_build_object(
      'lib_group_id', g.lib_group_id,
      'name', g.name,
      'label', g.label,
      'label_short', g.label_short
    )
  END AS lib_group,
  COALESCE(act.action_count, 0) AS action_count,
  COALESCE(act.outstanding_action_count, 0) AS outstanding_action_count,
  CASE WHEN p.lib_employee_change_request_id IS NULL THEN NULL ELSE
    jsonb_build_object(
      'lib_employee_change_request_id', p.lib_employee_change_request_id,
      'request_type', p.request_type,
      'effective_date', p.effective_date,
      'payload', p.payload
    )
  END AS parent_lib_employee_change_request,
  COALESCE(act.actions, '[]'::jsonb) AS actions
FROM lib_employee_change_request r
LEFT JOIN lib_employee e
  ON e.lib_employee_id = r.lib_employee_id
LEFT JOIN lib_employee sup
  ON sup.lib_employee_id = r.lib_employee_supervisor_id
LEFT JOIN lib_group g
  ON g.lib_group_id = r.lib_group_id
LEFT JOIN app_user su
  ON su.app_user_id = r.submitted_by_app_user_id
LEFT JOIN lib_employee_change_request p
  ON p.lib_employee_change_request_id = r.parent_lib_employee_change_request_id
LEFT JOIN LATERAL (
  SELECT jsonb_agg(
    -- to_jsonb(a) picks up every action column, including ones added later
    to_jsonb(a) || jsonb_build_object(
      'performed_by_app_user',
      CASE WHEN u.app_user_id IS NULL THEN NULL ELSE
        jsonb_build_object(
          'app_user_id', u.app_user_id,
          'first_name', u.first_name,
          'last_name', u.last_name,
          'email', u.email
        )
      END,
      'display_status', lib_emp_change_req_action_display_status(a)
    ) ORDER BY a.created_at, a.sort_order, a.action_key
  ) AS actions,
  count(*) AS action_count,
  count(*) FILTER (WHERE a.status NOT IN ('done', 'skipped')) AS outstanding_action_count
  FROM lib_employee_change_request_action a
  LEFT JOIN app_user u ON u.app_user_id = a.performed_by_app_user_id
  WHERE a.lib_employee_change_request_id = r.lib_employee_change_request_id
) act ON true;