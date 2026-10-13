CREATE TABLE IF NOT EXISTS lib_audit_log (
  lib_audit_log_id BIGSERIAL PRIMARY KEY,
  table_name TEXT NOT NULL,
  row_id JSONB NOT NULL,
  operation TEXT NOT NULL,
  changes JSONB NOT NULL,
  actor_app_user_id VARCHAR(200),
  source TEXT,
  lib_employee_change_request_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_lib_audit_log_table_created ON lib_audit_log (table_name, created_at);
CREATE INDEX IF NOT EXISTS idx_lib_audit_log_row_id ON lib_audit_log USING gin (row_id);
CREATE INDEX IF NOT EXISTS idx_lib_audit_log_request ON lib_audit_log (lib_employee_change_request_id);

-- generic audit trigger. pk column names are passed as trigger args
CREATE FUNCTION lib_audit_log_trigger() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  old_row jsonb := CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END;
  new_row jsonb := CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END;
  row_data jsonb := COALESCE(new_row, old_row);
  diff jsonb;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    SELECT jsonb_object_agg(n.key, jsonb_build_array(old_row -> n.key, n.value))
      INTO diff
    FROM jsonb_each(new_row) n
    WHERE n.value IS DISTINCT FROM old_row -> n.key
      AND n.key <> 'updated_at'; -- don't count timestamp bumps as changes
    IF diff IS NULL THEN RETURN NULL; END IF; -- no-op update
  ELSE
    diff := row_data;
  END IF;

  INSERT INTO lib_audit_log
    (table_name, row_id, operation, changes, actor_app_user_id, source, lib_employee_change_request_id)
  VALUES (
    TG_TABLE_NAME,
    (SELECT jsonb_object_agg(c, row_data -> c) FROM unnest(TG_ARGV) c),
    TG_OP,
    diff,
    NULLIF(current_setting('app.actor', true), ''),
    NULLIF(current_setting('app.source', true), ''),
    NULLIF(current_setting('app.request_id', true), '')::uuid
  );
  RETURN NULL;
END $$;

CREATE TRIGGER lib_employee_audit
  AFTER INSERT OR UPDATE OR DELETE ON lib_employee
  FOR EACH ROW EXECUTE FUNCTION lib_audit_log_trigger('lib_employee_id');

CREATE TRIGGER lib_employee_meta_assignment_audit
  AFTER INSERT OR UPDATE OR DELETE ON lib_employee_meta_assignment
  FOR EACH ROW EXECUTE FUNCTION lib_audit_log_trigger('lib_employee_id', 'lib_employee_meta_id');

CREATE TRIGGER lib_group_audit
  AFTER INSERT OR UPDATE OR DELETE ON lib_group
  FOR EACH ROW EXECUTE FUNCTION lib_audit_log_trigger('lib_group_id');

CREATE TRIGGER lib_group_membership_audit
  AFTER INSERT OR UPDATE OR DELETE ON lib_group_membership
  FOR EACH ROW EXECUTE FUNCTION lib_audit_log_trigger('lib_employee_id', 'lib_group_id');