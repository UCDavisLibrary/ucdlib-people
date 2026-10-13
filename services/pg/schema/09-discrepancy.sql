CREATE TABLE IF NOT EXISTS employee_record_discrepancy (
  employee_record_discrepancy_id BIGSERIAL PRIMARY KEY,
  discrepancy TEXT NOT NULL,
  lib_employee_id UUID NOT NULL REFERENCES lib_employee(lib_employee_id) ON DELETE CASCADE,
  details JSONB NOT NULL DEFAULT '{}',
  created_by_job_run_id BIGINT REFERENCES job_run(job_run_id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_confirmed_by_job_run_id BIGINT REFERENCES job_run(job_run_id) ON DELETE SET NULL,
  last_confirmed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (discrepancy, lib_employee_id)
);

CREATE OR REPLACE VIEW employee_record_discrepancy_full AS
SELECT
  d.*,
  jsonb_build_object(
    'lib_employee_id', e.lib_employee_id,
    'iam_id', e.iam_id,
    'user_id', e.user_id,
    'email', e.email,
    'first_name', e.first_name,
    'last_name', e.last_name
  ) AS employee,
  CASE WHEN cj.job_run_id IS NULL THEN NULL ELSE
    jsonb_build_object(
      'job_run_id', cj.job_run_id,
      'job_name', cj.job_name,
      'status', cj.status,
      'triggered_by_app_user', cj.triggered_by_app_user,
      'started_at', cj.started_at,
      'finished_at', cj.finished_at
    )
  END AS created_by_job_run,
  CASE WHEN lj.job_run_id IS NULL THEN NULL ELSE
    jsonb_build_object(
      'job_run_id', lj.job_run_id,
      'job_name', lj.job_name,
      'status', lj.status,
      'triggered_by_app_user', lj.triggered_by_app_user,
      'started_at', lj.started_at,
      'finished_at', lj.finished_at
    )
  END AS last_confirmed_by_job_run
FROM employee_record_discrepancy d
JOIN lib_employee e
  ON e.lib_employee_id = d.lib_employee_id
LEFT JOIN job_run_full cj
  ON cj.job_run_id = d.created_by_job_run_id
LEFT JOIN job_run_full lj
  ON lj.job_run_id = d.last_confirmed_by_job_run_id;