# Requests Landing Page

Artifact: https://claude.ai/artifact/XBpamiCimkf6NxmYXspV9E

Local copy: [index.html](index.html) - open directly in a browser. Loads Font Awesome from cdnjs, so icons need a network connection.

## Description

Landing page for employee change requests. Filter-sidebar layout: sidebar on the left (stacks above the list on narrow screens), request list as the main content.

- **Start a request** (top of sidebar) - a link for every request type, each with an icon, name, and a one-line blurb: Onboarding, Separation, Permissions, Transfer, Update information (`meta-update`)
  - Collapsible: clicking the heading (with a chevron) hides or shows the links. The choice is remembered per user between sessions in `app_user_settings.requests_start_panel_collapsed`. The wireframe uses browser storage as a stand-in
  - Two views, switched with a wireframe-only "Start panel" toggle:
    - **Full list** (default) - every type with its blurb
    - **Most used** - the user's 3-4 most used types (icon + name, no blurb) under "Your most used", plus an "All request types" link that opens a modal with every type grouped by category (Arriving and leaving, Changes, Access and equipment), each with its blurb. The modal closes with the X button, Escape, or a click outside it
  - Request types come from one list in the page script (key, label, icon, category, blurb). The panel, modal, type filter, and table icons all read from it
- **Filter** (sidebar)
  - Employee - text search with name suggestions
  - Group - dropdown, with an "Include subgroups" checkbox (on by default)
  - Request type
  - Actions - all, some outstanding, all complete
  - Created - from/to dates
  - Effective - from/to dates. Requests with no effective date drop out when this is set
  - Clear filters button
- **Existing requests** (main) - table of type, employee (links to the request), group, created, effective, and actions done (small progress bar + "x of y"), newest first. On small screens (640px and below), only type, employee, and actions done stay as columns; each row gets a chevron button that expands to show group, created, and effective. Pagination is always shown, even with one page
- Wireframe-only "View as" toggle at the top: department head of Digital Applications (sees that department and its subgroups) vs admin (sees everything). Filters and pagination work against example data

Example data: 15 requests across six groups (Digital Applications is a subgroup of Information Technology). The Jordan Alvarez onboarding row links to the [onboarding request wireframe](../onboarding-request/index.html).

## Notes

- Visibility: admins see all requests. Everyone else only sees requests pertinent to them, using new columns on `lib_employee_change_request`: `lib_group_id` (department heads see their group and subgroups), `lib_employee_supervisor_id` (supervisors see their employees' requests), and `lib_employee_forbidden` (the request's subject can't see it). See the Requests section of `notes.md`.
- As request types grow: show users only the types they can start (filtered by role), group by category at around 8-15 types, and switch to the "most used + modal" view (or a dedicated page) beyond that. Request types should be defined in one place in code (key, label, blurb, icon, category, roles allowed to start it, sort order) so every view reads from the same list.
- The Actions filter uses `outstanding_action_count` from `lib_employee_change_request_full` (actions not done or skipped). A request with no actions counts as all complete.
