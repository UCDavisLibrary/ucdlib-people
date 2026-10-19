CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TABLE IF NOT EXISTS lib_group (
  lib_group_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(255) NOT NULL UNIQUE,
  label TEXT,
  label_short VARCHAR(50),
  parent_lib_group_id UUID REFERENCES lib_group(lib_group_id) ON DELETE SET NULL,
  legacy_iam_id INTEGER UNIQUE, 
  is_organizational BOOLEAN DEFAULT FALSE NOT NULL,
  interim_head_id UUID REFERENCES lib_employee(lib_employee_id) ON DELETE SET NULL,
  rt_name TEXT,
  is_archived BOOLEAN DEFAULT FALSE NOT NULL,
  UNIQUE(lib_group_id, is_organizational)
);

CREATE INDEX IF NOT EXISTS idx_lib_group_label_trgm
  ON lib_group USING gin (label gin_trgm_ops);

-- TEMPORARY: assign a legacy_iam_id to new groups until external apps move to lib_group_id.
-- TODO: after importing groups from the old system, advance the sequence past the imported ids:
-- SELECT setval('lib_group_legacy_iam_id_seq', (SELECT max(legacy_iam_id) FROM lib_group));
-- to remove: drop the trigger, function, sequence, and legacy_iam_id column
CREATE SEQUENCE IF NOT EXISTS lib_group_legacy_iam_id_seq;

-- sets legacy_iam_id from the sequence if not supplied (including explicit nulls)
CREATE OR REPLACE FUNCTION lib_group_set_legacy_iam_id() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.legacy_iam_id IS NULL THEN
    NEW.legacy_iam_id := nextval('lib_group_legacy_iam_id_seq');
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER lib_group_set_legacy_iam_id
  BEFORE INSERT ON lib_group
  FOR EACH ROW EXECUTE FUNCTION lib_group_set_legacy_iam_id();

CREATE OR REPLACE FUNCTION get_lib_group_id(name_or_id TEXT)
  RETURNS UUID AS $$
DECLARE
  uid UUID;
BEGIN
  SELECT lib_group_id INTO uid
  FROM lib_group
  WHERE name = name_or_id
     OR lib_group_id = try_cast_uuid(name_or_id);

  IF uid IS NULL THEN
    RAISE EXCEPTION USING
      MESSAGE = format('Library group not found: %s', name_or_id),
      ERRCODE = 'P4040';
  END IF;

  RETURN uid;
END;
$$ LANGUAGE plpgsql;

-- Returns the given group's id and the ids of all its descendants (subgroups at any depth).
-- Used for "this department and its subdepartments" filtering and visibility.
-- root_group_id: lib_group_id to start from
CREATE OR REPLACE FUNCTION get_lib_group_descendant_ids(root_group_id UUID)
  RETURNS SETOF UUID LANGUAGE sql STABLE AS $$
    WITH RECURSIVE tree AS (
      SELECT lib_group_id FROM lib_group WHERE lib_group_id = root_group_id
      UNION
      SELECT g.lib_group_id
      FROM lib_group g
      JOIN tree t ON g.parent_lib_group_id = t.lib_group_id
    )
    SELECT lib_group_id FROM tree
$$;

CREATE TABLE IF NOT EXISTS lib_group_membership (
  lib_employee_id UUID REFERENCES lib_employee(lib_employee_id) ON DELETE CASCADE,
  lib_group_id UUID REFERENCES lib_group(lib_group_id) ON DELETE CASCADE,
  is_head BOOLEAN DEFAULT FALSE NOT NULL,
  is_organizational BOOLEAN NOT NULL,
  UNIQUE(lib_employee_id, lib_group_id),
  FOREIGN KEY (lib_group_id, is_organizational)
    REFERENCES lib_group (lib_group_id, is_organizational)
    ON UPDATE CASCADE
);

-- enforce only one head per group
CREATE UNIQUE INDEX lib_group_membership_one_head
  ON lib_group_membership (lib_group_id)
  WHERE is_head;

-- enforce only one organizational group per employee
CREATE UNIQUE INDEX lib_group_membership_one_org
  ON lib_group_membership (lib_employee_id)
  WHERE is_organizational;

-- set is_organizational on insert/update of lib_group_membership
-- allows for us to enforce the constrain that an employee can only be in one organizational group at a time
CREATE FUNCTION lib_group_membership_set_org() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  SELECT is_organizational INTO NEW.is_organizational
  FROM lib_group WHERE lib_group_id = NEW.lib_group_id;
  RETURN NEW;
END $$;

CREATE TRIGGER lib_group_membership_set_org
  BEFORE INSERT OR UPDATE OF lib_group_id ON lib_group_membership
  FOR EACH ROW EXECUTE FUNCTION lib_group_membership_set_org();