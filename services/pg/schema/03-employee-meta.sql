CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TABLE IF NOT EXISTS lib_employee_meta (
  lib_employee_meta_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(255) NOT NULL UNIQUE,
  label TEXT,
  description TEXT,
  source VARCHAR(50) NOT NULL DEFAULT 'local',
  source_path VARCHAR(255),
  meta_group VARCHAR(50) NOT NULL
);

CREATE TABLE IF NOT EXISTS lib_employee_meta_assignment (
  lib_employee_id UUID REFERENCES lib_employee(lib_employee_id) ON DELETE CASCADE,
  lib_employee_meta_id UUID REFERENCES lib_employee_meta(lib_employee_meta_id) ON DELETE CASCADE,
  value JSONB NOT NULL,
  PRIMARY KEY (lib_employee_id, lib_employee_meta_id)
);

CREATE INDEX IF NOT EXISTS idx_lib_employee_meta_label_trgm
  ON lib_employee_meta USING gin (label gin_trgm_ops);

CREATE OR REPLACE FUNCTION get_lib_employee_meta_id(name_or_id TEXT)
  RETURNS UUID AS $$
DECLARE
  uid UUID;
BEGIN
  SELECT lib_employee_meta_id INTO uid
  FROM lib_employee_meta
  WHERE name = name_or_id
     OR lib_employee_meta_id = try_cast_uuid(name_or_id);

  IF uid IS NULL THEN
    RAISE EXCEPTION USING
      MESSAGE = format('Library employee meta not found: %s', name_or_id),
      ERRCODE = 'P4040';
  END IF;

  RETURN uid;
END;
$$ LANGUAGE plpgsql;