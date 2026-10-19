# Employees Landing Page

Artifact: https://claude.ai/artifact/Tk42uBHmXGU2XJMiMTxSHu

Local copy: [index.html](index.html) - open directly in a browser. Loads Font Awesome from cdnjs, so icons need a network connection.

## Description

Filterable, paginated list of library employees. Filter-sidebar layout, matching the requests landing page: sidebar on the left (stacks above the list on narrow screens), employee teasers as the main content.

- **Filter** (sidebar)
  - Name - partial match on first or last name
  - ID - exact (case-insensitive) match on any id: IAM ID, employee ID, student ID, user ID, email, or Keycloak ID. Backed by `search_lib_employee_ids(query, id_type)`
  - Department - dropdown, with an "Include subgroups" checkbox (on by default)
  - Employee status - Active (default), Inactive, or All
  - Has record discrepancy - checkbox
  - Clear filters - resets to the defaults, so status goes back to Active
- **Employees** (main) - a teaser per employee. Employees with record discrepancies always sort to the top, then everyone is sorted by last name:
  - Name (links to the employee), followed by indicators: "Record discrepancy" (amber, with a warning icon; hovering lists the discrepancy types) and "Inactive" (grey). Inactive employees' name and position are also greyed
  - Position title
  - Department and supervisor ("None" if there isn't one)
  - Each field is prefixed with an inline icon instead of a text label: briefcase (position), sitemap (department), user-tie (supervisor). The label is kept as a tooltip and for screen readers
  - No primary appointment title (dropped)
- Pagination is always shown, even with one page

Example data: 18 employees across seven departments (Digital Applications is a subgroup of Information Technology), 3 inactive and 3 with record discrepancies. With the default Active filter, 15 employees show across two pages.

## Notes

- `lib_employee_full` includes an `employee_record_discrepancies` array (id, discrepancy, details, created_at, last_confirmed_at; oldest first, `[]` if none), which drives the discrepancy indicator and filter.
- The employee views file was renamed from `05-employee-views.sql` to `10-employee-views.sql` so it runs after `09-discrepancy.sql` on a fresh database.
