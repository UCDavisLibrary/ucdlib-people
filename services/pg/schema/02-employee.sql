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