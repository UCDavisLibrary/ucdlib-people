CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TABLE IF NOT EXISTS lib_employee (
  lib_employee_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  iam_id varchar(20) UNIQUE,
  employee_id varchar(20) UNIQUE,
  student_id varchar(20) UNIQUE,
  user_id varchar(100) UNIQUE,
  email varchar(200) UNIQUE,
  keycloak_id varchar(100) UNIQUE,
  first_name text,
  last_name text,
  middle_name text,
  full_name text GENERATED ALWAYS AS (
    trim(coalesce(first_name, '') || ' ' || coalesce(last_name, ''))
  ) STORED,
  start_date DATE,
  end_date DATE,
  supervisor_lib_employee_id UUID REFERENCES lib_employee(lib_employee_id) ON DELETE SET NULL, -- 
  custom_supervisor boolean NOT NULL DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_lib_employee_full_name_trgm
  ON lib_employee USING gin (full_name gin_trgm_ops);

-- Returns the lib_employee_id for an employee by one of their ids.
-- any_id: the id value to look up
-- id_type: the id column to look up by (iam_id, employee_id, student_id, user_id, email, keycloak_id)
CREATE OR REPLACE FUNCTION get_lib_employee_id(any_id TEXT, id_type TEXT)
  RETURNS UUID AS $$
DECLARE
  uid UUID;
BEGIN
  IF id_type IS NULL OR id_type NOT IN ('iam_id', 'employee_id', 'student_id', 'user_id', 'email', 'keycloak_id') THEN
    RAISE EXCEPTION USING
      MESSAGE = format('Invalid id_type: %s', id_type),
      ERRCODE = '22023';
  END IF;

  EXECUTE format('SELECT lib_employee_id FROM lib_employee WHERE %I = $1', id_type)
    INTO uid
    USING any_id;

  IF uid IS NULL THEN
    RAISE EXCEPTION USING
      MESSAGE = format('Library employee not found: %s', any_id),
      ERRCODE = 'P4040';
  END IF;

  RETURN uid;
END;
$$ LANGUAGE plpgsql;

-- Searches employees by exact (case-insensitive) match of any of their ids.
-- query: the id value
-- id_type: optional id column to restrict the search to (iam_id, employee_id, student_id, user_id, email, keycloak_id).
--          if null, all id columns are searched
CREATE OR REPLACE FUNCTION search_lib_employee_ids(query TEXT, id_type TEXT DEFAULT NULL)
  RETURNS TABLE (lib_employee_id UUID, matched_id_type TEXT) AS $$
BEGIN
  IF id_type IS NOT NULL AND id_type NOT IN ('iam_id', 'employee_id', 'student_id', 'user_id', 'email', 'keycloak_id') THEN
    RAISE EXCEPTION USING
      MESSAGE = format('Invalid id_type: %s', id_type),
      ERRCODE = '22023';
  END IF;

  IF coalesce(trim(query), '') = '' THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT e.lib_employee_id, ids.col
  FROM lib_employee e
  CROSS JOIN LATERAL (VALUES
    ('iam_id', e.iam_id),
    ('employee_id', e.employee_id),
    ('student_id', e.student_id),
    ('user_id', e.user_id),
    ('email', e.email),
    ('keycloak_id', e.keycloak_id)
  ) AS ids(col, val)
  WHERE ids.val IS NOT NULL
    AND (search_lib_employee_ids.id_type IS NULL OR ids.col = search_lib_employee_ids.id_type)
    AND lower(ids.val) = lower(trim(query));
END;
$$ LANGUAGE plpgsql STABLE;

-- Returns everyone who reports to an employee, directly or indirectly, with the supervisor chain
-- from the given employee down to each report's own supervisor. Does not filter by active status.
-- root_lib_employee_id: the employee whose reports to return
-- direct_only: if true, only direct reports (depth 1)
-- returns: lib_employee_id, depth (1 = direct report), supervisor_chain (ids, root first)
CREATE OR REPLACE FUNCTION get_lib_employee_reports(root_lib_employee_id UUID, direct_only BOOLEAN DEFAULT FALSE)
  RETURNS TABLE (lib_employee_id UUID, depth INTEGER, supervisor_chain UUID[]) LANGUAGE sql STABLE AS $$
    WITH RECURSIVE reports AS (
      SELECT e.lib_employee_id, 1 AS depth, ARRAY[root_lib_employee_id] AS supervisor_chain
      FROM lib_employee e
      WHERE e.supervisor_lib_employee_id = root_lib_employee_id
        AND e.lib_employee_id <> root_lib_employee_id
      UNION ALL
      SELECT e.lib_employee_id, r.depth + 1, r.supervisor_chain || r.lib_employee_id
      FROM lib_employee e
      JOIN reports r ON e.supervisor_lib_employee_id = r.lib_employee_id
      -- guard against supervisor loops in bad data
      WHERE NOT direct_only
        AND NOT e.lib_employee_id = ANY(r.supervisor_chain || r.lib_employee_id)
    )
    SELECT lib_employee_id, depth, supervisor_chain FROM reports
$$;
