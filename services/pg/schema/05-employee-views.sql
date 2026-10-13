-- Returns true if the employee has started (or has no start date) and is not yet past end_date,
-- in America/Los_Angeles time. Single source of truth for "active" - used by the employee and group views.
-- e: lib_employee row
CREATE OR REPLACE FUNCTION lib_employee_is_active(e lib_employee)
  RETURNS boolean AS $$
  SELECT (e.start_date IS NULL OR e.start_date <= (now() AT TIME ZONE 'America/Los_Angeles')::date)
    AND (e.end_date IS NULL OR e.end_date >= (now() AT TIME ZONE 'America/Los_Angeles')::date)
$$ LANGUAGE sql STABLE;

-- All employees with their supervisor, groups, and meta.
-- is_active: see lib_employee_is_active
-- supervisor: object, or null if no supervisor
-- employee_groups: array of groups, or [] if none
-- employee_meta: object keyed by lib_employee_meta.name, or {} if none
CREATE OR REPLACE VIEW lib_employee_full AS
SELECT
  e.*,
  lib_employee_is_active(e) AS is_active,
  CASE WHEN s.lib_employee_id IS NULL THEN NULL ELSE
    jsonb_build_object(
      'lib_employee_id', s.lib_employee_id,
      'iam_id', s.iam_id,
      'user_id', s.user_id,
      'email', s.email,
      'first_name', s.first_name,
      'last_name', s.last_name
    )
  END AS supervisor,
  COALESCE(grp.employee_groups, '[]'::jsonb) AS employee_groups,
  COALESCE(meta.employee_meta, '{}'::jsonb) AS employee_meta
FROM lib_employee e
LEFT JOIN lib_employee s
  ON s.lib_employee_id = e.supervisor_lib_employee_id
LEFT JOIN LATERAL (
  SELECT jsonb_agg(
    jsonb_build_object(
      'lib_group_id', g.lib_group_id,
      'name', g.name,
      'label', g.label,
      'label_short', g.label_short,
      'is_organizational', g.is_organizational
    ) ORDER BY g.is_organizational DESC, g.name
  ) AS employee_groups
  FROM lib_group_membership gm
  JOIN lib_group g ON g.lib_group_id = gm.lib_group_id
  WHERE gm.lib_employee_id = e.lib_employee_id
) grp ON true
LEFT JOIN LATERAL (
  SELECT jsonb_object_agg(m.name, ma.value) AS employee_meta
  FROM lib_employee_meta_assignment ma
  JOIN lib_employee_meta m ON m.lib_employee_meta_id = ma.lib_employee_meta_id
  WHERE ma.lib_employee_id = e.lib_employee_id
) meta ON true;

-- Same as lib_employee_full, filtered to active employees
CREATE OR REPLACE VIEW lib_employee_full_active AS
SELECT *
FROM lib_employee_full
WHERE is_active;

-- All groups with their interim head, parent, children, and members.
-- interim_head: object, or null if none
-- parent_lib_group: object, or null if top-level
-- children: array of child groups, or [] if none
-- employees: array of members, or [] if none
CREATE OR REPLACE VIEW lib_group_full AS
SELECT
  g.*,
  CASE WHEN ih.lib_employee_id IS NULL THEN NULL ELSE
    jsonb_build_object(
      'lib_employee_id', ih.lib_employee_id,
      'iam_id', ih.iam_id,
      'user_id', ih.user_id,
      'email', ih.email,
      'first_name', ih.first_name,
      'last_name', ih.last_name
    )
  END AS interim_head,
  CASE WHEN p.lib_group_id IS NULL THEN NULL ELSE
    jsonb_build_object(
      'lib_group_id', p.lib_group_id,
      'name', p.name,
      'label', p.label,
      'label_short', p.label_short
    )
  END AS parent_lib_group,
  COALESCE(ch.children, '[]'::jsonb) AS children,
  COALESCE(emp.employees, '[]'::jsonb) AS employees
FROM lib_group g
LEFT JOIN lib_employee ih
  ON ih.lib_employee_id = g.interim_head_id
LEFT JOIN lib_group p
  ON p.lib_group_id = g.parent_lib_group_id
LEFT JOIN LATERAL (
  SELECT jsonb_agg(
    jsonb_build_object(
      'lib_group_id', c.lib_group_id,
      'name', c.name,
      'label', c.label,
      'label_short', c.label_short,
      'is_archived', c.is_archived
    ) ORDER BY c.name
  ) AS children
  FROM lib_group c
  WHERE c.parent_lib_group_id = g.lib_group_id
) ch ON true
LEFT JOIN LATERAL (
  SELECT jsonb_agg(
    jsonb_build_object(
      'lib_employee_id', e.lib_employee_id,
      'iam_id', e.iam_id,
      'user_id', e.user_id,
      'email', e.email,
      'first_name', e.first_name,
      'last_name', e.last_name,
      'is_head', gm.is_head,
      'is_active', lib_employee_is_active(e)
    ) ORDER BY gm.is_head DESC, e.last_name, e.first_name
  ) AS employees
  FROM lib_group_membership gm
  JOIN lib_employee e ON e.lib_employee_id = gm.lib_employee_id
  WHERE gm.lib_group_id = g.lib_group_id
) emp ON true;

-- Non-archived groups. children excludes archived groups and employees excludes inactive employees.
CREATE OR REPLACE VIEW lib_group_full_active AS
SELECT
  lib_group_id,
  name,
  label,
  label_short,
  parent_lib_group_id,
  legacy_iam_id,
  is_organizational,
  interim_head_id,
  rt_name,
  is_archived,
  interim_head,
  parent_lib_group,
  jsonb_path_query_array(children, '$[*] ? (@.is_archived == false)') AS children,
  jsonb_path_query_array(employees, '$[*] ? (@.is_active == true)') AS employees
FROM lib_group_full
WHERE NOT is_archived;
