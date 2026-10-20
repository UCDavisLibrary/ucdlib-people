# Employee Detail

Artifact: https://claude.ai/artifact/G7KzkAPGjN17HUUeE1z8kV

Local copy: [index.html](index.html) - open directly in a browser. Loads Font Awesome from cdnjs, so icons need a network connection.

## Description

Detail page for an individual library employee. Tabbed layout, like the onboarding request detail page.

- **Header** - avatar icon, name, position, department
- **Overview tab**
  - Record discrepancy notice (amber box) when the employee has open discrepancies. With one, it names it; with more than one, it names the first and says "and x more". Links to the Discrepancies tab. Hidden when there are none
  - Summary and Unique Identifiers panels sit side by side on screens 800px and wider, stacked below that
  - Summary, in this order - name, position, department (with a "Department head" label when they're the head), groups they're interim head of, supervisor (links to their page; a grey "Custom" label when `custom_supervisor` is true, with a tooltip explaining Rosetta won't replace it), other groups (one per line), number of direct reports (links to the Employees tab), start date, and end date ("None" if not set)
  - Unique Identifiers - IAM ID, employee ID, student ID, user ID, email, Keycloak ID, and library employee ID (`lib_employee_id`), in monospace. Each has an icon-only copy button with a circular border; the icon briefly changes to a green check after copying (and screen readers hear "IAM ID copied", etc). If the browser refuses clipboard access, the id is selected instead. Missing ones show "None" with no button
- **Metadata tab** - one box per `meta_group` (General, Contact, Appointment, HR), since the meta group determines access. Each value has a Local / Rosetta source label
  - Each box has a circular `</>` icon button in its header that opens a modal with the group's raw JSON: `{ "meta_group": "appointment", "meta": { ... } }`, keyed by `lib_employee_meta.name` with the raw stored values
  - Fields with a `lib_employee_meta.description` get a small circular "?" button after the label that opens a modal with the description and the field's `name`
  - One shared modal for both; closes with the X button, Escape, or a click outside it
- **Employees tab** - people who report to this employee. A Direct reports / All reports switch (direct by default). Table of name, position, department, and supervisor chain (from this employee down to the report's own supervisor, e.g. "Sam Okafor › Elena Ruiz"). On small screens (640px and below), position and department combine into one column (department on the line below), and the supervisor chain moves into an expandable row opened with a circular chevron button. Pagination is always shown below the table, even with one page
- **Discrepancies tab** - a box per open discrepancy: its label as the heading with the type (e.g. `no-supervisor-rosetta-record`) in muted monospace below, a plain-language explanation, when it was first found and last confirmed (each with the job name that did it, e.g. `rosetta_sync`), then the discrepancy's `details` as a raw JSON block. Empty state when there are none
  - Explanations are generic per discrepancy type (no names), so they can live with the type definition rather than being written per employee. Employee-specific values belong in the details
- **Requests tab** - paginated table of requests for this employee: type (links to the request), submitted, effective, actions done. Pagination always shown
- Wireframe-only "Discrepancies" toggle at the top: None / One / Several, to see the notice and tab in each state

Example data: Sam Okafor, head of Digital Applications and interim head of Access Services, with 4 direct reports and 6 reports in total. The discrepancy types beyond `no-supervisor-rosetta-record` are made-up examples.

## Notes

- Data sources:
  - `lib_employee_full` - `employee_groups` (now with `is_head`), `interim_head` (groups where `lib_group.interim_head_id` is this employee), `direct_report_count` (active direct reports), `employee_record_discrepancies` (summary only, no `details` - enough for the overview notice), `employee_meta`
  - `employee_record_discrepancy_full` - separate API call when the Discrepancies tab is opened. Provides `details` and the `created_by_job_run` / `last_confirmed_by_job_run` objects (with `job_name`)
  - `get_lib_employee_reports(lib_employee_id, direct_only)` - reports with `depth` and `supervisor_chain`, for the Employees tab. Returns inactive reports too, so filter by joining `lib_employee_full_active`
  - Metadata tab groups `employee_meta` values using `lib_employee_meta.meta_group` and `source`
- Users only see the meta groups their Keycloak roles allow (planned `meta:<group>` roles), so the raw JSON modal only ever shows a group the viewer can already see.
