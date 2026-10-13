CREATE TABLE IF NOT EXISTS job_run (
  job_run_id BIGSERIAL PRIMARY KEY,
  job_name TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'running',
  triggered_by TEXT NOT NULL,
  triggered_by_app_user_id VARCHAR(200) REFERENCES app_user(app_user_id) ON DELETE SET NULL,
  summary JSONB NOT NULL DEFAULT '{}',
  error TEXT,
  failure_acknowledged_at TIMESTAMPTZ,
  failure_acknowledged_by_app_user_id VARCHAR(200) REFERENCES app_user(app_user_id) ON DELETE SET NULL,
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  finished_at TIMESTAMPTZ
);

CREATE OR REPLACE VIEW job_run_full AS
SELECT
  jr.*,
  CASE WHEN tu.app_user_id IS NULL THEN NULL ELSE
    jsonb_build_object(
      'app_user_id', tu.app_user_id,
      'first_name', tu.first_name,
      'last_name', tu.last_name,
      'email', tu.email
    )
  END AS triggered_by_app_user,
  CASE WHEN au.app_user_id IS NULL THEN NULL ELSE
    jsonb_build_object(
      'app_user_id', au.app_user_id,
      'first_name', au.first_name,
      'last_name', au.last_name,
      'email', au.email
    )
  END AS failure_acknowledged_by_app_user
FROM job_run jr
LEFT JOIN app_user tu
  ON tu.app_user_id = jr.triggered_by_app_user_id
LEFT JOIN app_user au
  ON au.app_user_id = jr.failure_acknowledged_by_app_user_id;