# Onboarding Request Detail

Artifact: https://claude.ai/artifact/UNhDjaaEMZs67jfu6CYkDv

Local copy: [index.html](index.html) - open directly in a browser. Saved Oct 14, 2026 (artifact version 27). Loads Font Awesome from cdnjs, so icons need a network connection.

## Description

Detail view of a recently submitted, in-progress onboarding request. Tabbed layout.

- **Header** - request type icon + employee name (no "Onboarding:" prefix), start date, position title, department, and a progress bar of completed actions (no overall status label - see notes). The "x of y actions done" text links to the Actions tab
- **Overview tab**
  - "Needs attention" box for failed actions, with a retry button
  - "Needs your action" box for human actions the viewer can complete, e.g. IT approval: description of what approving does and a single Approve button. A wireframe-only toggle at the top of the page swaps between this and the failed-action box
  - Employee panel on its own full-width row - the request payload, including long free-text fields like Notes (line breaks preserved)
  - Request and RT tickets panels side by side below it (wrapping on narrow screens)
  - Request panel - request type, who submitted it, when, and the hierarchy: parent request (or none) and direct child requests with their progress
  - RT tickets panel - linked ticket number, display label from `external_subject` (what this interface shows, not necessarily the RT ticket's subject), ticket status from `external_status`. Includes tickets from all child requests, grouped under a "From [child request]" heading (type icon + link to the child) and indented with a left rule. Tickets a child only comments on (e.g. `parent:ticket_it`) aren't listed twice
- **Actions tab** - table of every action on the request: status, action, who it's assigned to, details, and an action button where one applies
  - Dependencies: blocked actions say what they're waiting on in the details column, e.g. "Waiting on: Facilities ticket (failed)". Other rows show nothing extra
  - Each row expands (click the action name) to show "Depends on" and "Needed by", each with the other action's current status
  - On small screens (640px and below), the Who and Details columns are hidden and shown in the expandable section instead
  - Admin only: the expanded section also shows admin details - action key, action type, automated, depends_on keys, attempts, scheduled for, last attempted, last error, performed by/at, external system info, config, and completion data
  - Admin only: a "Cancel all remaining" button above the table and a "Cancel" button on each unfinished action. Cancelling sets `status = 'skipped'` with `completion_data.cancelled = true` and the admin as `performed_by_app_user_id`; done actions aren't changed. No confirmation step shown (easy to add later).
  - Admin only: a "Run now" button on each scheduled action, to run it before its `scheduled_for` date. Dependencies still apply - scheduled actions only show once their dependencies are met, since blocked takes precedence A wireframe-only "View as" toggle at the top of the page shows the page with and without admin controls
- **Related requests tab**
  - Child requests (e.g. the supervisor's permissions request), with an empty state until one exists
  - All requests for the employee - table of type, submitted date, submitted by, effective date, and progress, newest first. The current request is highlighted. Always shows pagination, even with one page

Example scenario: submitted and approved Oct 13, supervisor submitted the permissions form Oct 14, start date in the future. Shows done, failed, waiting, and scheduled actions, plus one child request.

## Notes

- No overall status for the request, to avoid confusion. Just because all actions have been performed for a request does not mean it is complete. More actions can be added later (for example depending on the supervisor's response), and we won't always know the result of a "notifying" action (e.g. sending an email to someone who needs to do something but doesn't provide feedback to the system).
- The Request panel should be a dedicated custom element shared between requests regardless of type, so it shouldn't include anything specific to a request type (e.g. approved by, account creation). Don't show the submitter's department.
- Action status labels. The `status` column only has pending/done/skipped/failed. The labels shown come from `display_status` (`lib_emp_change_req_action_display_status`), which explains why a pending action hasn't run yet. Checked top to bottom:

  | Display label | Rule |
  |---|---|
  | **Done** | `status = 'done'` |
  | **Cancelled** | `status = 'skipped'` and `completion_data.cancelled = true` (cancelled by an admin) |
  | **Skipped** | `status = 'skipped'` |
  | **Failed** (needs attention) | `status = 'failed'`. Details text should separate "will retry at 2:15" from "gave up after 5 attempts" |
  | **Blocked** | `pending`, dependencies not met |
  | **Scheduled** | `pending`, `scheduled_for` is in the future |
  | **Waiting on [someone]** | `pending`, human action, dependencies met. Shown with `assigned_to`, e.g. "Waiting on supervisor" |
  | **Waiting** | `pending`, automated `await_children` action that isn't ready yet, e.g. "Permissions fulfilled" |
  | **Queued** | `pending`, automated, will run on the next check. Rarely seen, since the event-driven check usually runs it within seconds |

- No "Waiting on" section on the overview. It could get long when multiple actions are waiting (and longer still if scheduled actions were included). Users go to the Actions tab instead, which is easy to read.
- The Employee panel gets its own row because for other request types it's where the payload data goes, which can include results from textarea fields.
- No History tab. It mostly duplicated the Actions tab, and the schema can't back it: actions only keep their latest state, and the workflow tables aren't in the audit log. Who did what and when is already covered by the Actions tab (and its expanded details), the submission date by the Request panel, and cancellations by `completion_data`. If we later need a true event history (every retry, run now, date changes, revisions), add a small `lib_employee_change_request_event` table that handlers and admin endpoints write to.
- No reject button on approvals. Stopping a request is relatively rare, but still needed, so it lives on the Actions tab as admin-only cancel controls rather than on the approval card.
- Icons for each request type are still to be decided. The wireframe uses Font Awesome `user-plus` for onboarding and `key` for permissions as placeholders.

