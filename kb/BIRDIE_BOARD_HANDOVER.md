# Birdie Board — project handover

## Purpose

Birdie Board is a mobile-first web app for social golf groups. Users create accounts, join social clubs, create and prepare Stableford tournaments, assign players and groups, and ultimately run live scoring with a shared leaderboard.

Brand:

- Name: **Birdie Board**
- Main green: `#006747`
- Accent yellow: `#FCE300`
- Primary text: white
- Logo: cursive/serif styling, inspired by classic golf branding; Birdie white, Board yellow.
- Tagline used at sign-in: **Live golf scoring.**

## Repositories, hosting and services

- GitHub repository: `https://github.com/Darce87/birdie-board`
- Live site: `https://birdieboard.uk`
- GitHub Pages is the host, with the custom domain configured through Cloudflare.
- Previous project folder: `C:\Users\AdamAdmin\Documents\Codex\2026-08-05\i-want-to-build-an-app`
- Current local workspace: `C:\Users\AdamAdmin\Documents\ChatGPT\Birdie Board`
- Supabase project URL: `https://otqkceoknzzqnpfgvldh.supabase.co`
- A Supabase publishable key is embedded in the static frontend. Do **not** expose any Supabase service-role key or email/API secrets in browser code.

## Deployment routine

The user works from PowerShell and manually publishes changes:

```powershell
git add <files>
git commit -m "Description"
git push
```

GitHub Pages deploys from `main` / root. `app.js` loads `supabase-ui.js` with a version query string; increment it whenever `supabase-ui.js` changes to bypass caching.

## Authentication and security

- Supabase Auth provides sign-up, email verification, sign-in, password reset and password changes.
- Sign-up asks for first name, last name, exact handicap, email, password and password confirmation.
- After sign-up, users are returned to sign-in and told to check spam/junk for confirmation mail.
- Accounts have an Account/Profile area to update name, exact handicap and password.
- Profiles are intentionally not broadly readable through RLS. Secure `security definer` RPCs return club-member details only to authorised club members.
- RLS and `security definer` functions are used extensively for club/tournament actions. Avoid direct browser-side privileged database writes.

## Email/domain setup

- Domain `birdieboard.uk` was purchased through Cloudflare.
- Resend was discussed for transactional email and custom-domain sending.
- Cloudflare Email Routing can forward `adam@birdieboard.uk` or `hello@birdieboard.uk` to a normal inbox, but does not provide a mailbox/compose screen.
- To manually send as the domain from Gmail: verify `birdieboard.uk` with Resend, then configure Gmail **Send mail as** using `smtp.resend.com`, port `465`, username `resend`, password = a dedicated Resend API key. Never put that key in frontend code.
- England Golf enquiry contact identified: `whs.support@englandgolf.org`; CC `info@englandgolf.org` if useful.

## Social clubs and participants

Product flow:

1. A golfer creates a Birdie Board account and profile.
2. They create or join a social club using a persistent join code.
3. Club owners/admins can view club members, names, exact handicaps, events and join code.
4. Tournaments are created within a club.
5. The organiser adds club members as tournament participants.
6. Participants can see a read-only version of the tournament dashboard.

Roles currently used:

- Club roles: `owner`, `admin`, `member`.
- Avoid `organizer` / `organiser` database enum values; the deployed enum only accepts the above club roles.
- Tournament organiser permission is based mainly on `tournaments.created_by` / helper functions such as `can_manage_tournament`.

Important previous RLS issue:

- A recursive `club_members` RLS policy caused “infinite recursion”. It was fixed by using helper functions/security-definer RPCs rather than self-querying policies.
- The secure RPC `get_social_club_members(target_club)` is the correct source for names and handicaps. Direct profile joins may return null and display “Player”.

## Tournament preparation design

### Tournament setup

The intended creation flow is:

1. Tournament name.
2. Number of rounds.
3. Number of distinct courses.
4. Configure each distinct course once: course name, scorecard/manual input/OCR.
5. Assign each round a date and course. A course can be reused across multiple rounds (for example A/B/A).

### Preparation dashboard

Shows:

- Every round, its course and UK-formatted date (`DD/MM/YYYY`).
- Round edit action for course, date and scorecard.
- Players/participants and their exact handicaps.
- Owners can delete unplayed events.
- Events list has small, aligned Edit and Delete actions on the right.

### Editing tournament plan

- Edit Tournament can change tournament name and number of rounds.
- Increasing rounds creates new round records using the first course initially.
- Reducing to one round removes excess rounds and standardises the retained plan to the first course.
- “Courses being played” exposes additional course-name fields only after increasing the required number of courses.
- Adding a new course assigns it automatically to the next available round. Existing unassigned courses can be selected by editing a round.
- Scorecard and tee/rating entries are edited inside the individual round editor.

### Course data and handicaps

Each course/tee setup needs:

- Tee name (for example, Black tees)
- Slope rating
- Course rating
- Hole pars
- Stroke indices

Exact handicap is the player’s profile Handicap Index. The app calculates:

```text
Course Handicap = round(Handicap Index × Slope / 113 + (Course Rating − Par))
Playing Handicap = round(Course Handicap × 95%)
```

The 95% allowance is for individual Stableford. Display exact and playing handicaps separately, and calculate a playing handicap for each tournament round/course.

Example discussed: Weymouth black tees, par 70, rating 70.0, slope 133, exact 8.9:

- Course handicap: 10
- 95% Stableford playing handicap: 10

## Scorecard import/OCR

- A course scorecard can be entered manually or imported from an image/screenshot.
- Camera option was intentionally removed for now; use “Import photo” and manual entry.
- OCR uses Tesseract in the browser and looks for `SI` or `S.I.` then attempts to find a complete, unique 1–18 stroke-index row.
- OCR should always be presented as a draft requiring manual checking.
- Import/scorecard editing can be revisited later; user considers current preparation flow largely complete.

## Current live tournament design

The desired separation is:

- **Tournament Preparation**: organiser workspace for course/scorecard, players, handicaps and group setup.
- **Live Tournament**: participant-facing scoring and real-time leaderboard.

Lifecycle per round:

```text
Preparation → Live → Locked
```

Before starting a round, the organiser sets groups and a scorer for each group. Starting a round should:

- Lock/snapshot exact, course and playing handicaps for that round.
- Lock tee/course/scorecard preparation data for that round.
- Publish groups.
- Allow only the nominated scorer for a group (or organiser) to submit group scores.
- Show the live leaderboard to all tournament participants.

For multi-round tournaments:

- Each round stores its own Stableford points.
- The leaderboard has columns `R1`, `R2`, `R3` etc. and an overall accumulated `Total`.
- The current round is visibly highlighted.
- Organisers can set different groups / tee order for later rounds, including leader groups on a final day.

Live leaderboard visual direction:

- Compact Masters-style leaderboard.
- Condensed, bold uppercase typeface (`Roboto Condensed` was used for the prototype).
- Columns: Position, Player, each Round’s points, Total.
- White score rows with golf green header; current round highlighted pale green.

Mobile group allocation:

- Preferred eventual interaction: drag handles and drop zones for player cards.
- Always provide a touch-safe fallback: select a player, then tap/select their group.
- Auto-group evenly, then allow edits.
- Groups limited to 1–4 players, each with a scorer.

Live scoring:

- Scorer selects/advances hole and enters gross scores for all players in their group.
- Save the group’s hole together.
- Stableford points calculate server-side from the frozen round handicap and hole SI/par.
- Participants see realtime updates.
- Organiser can later get controlled correction/finalisation tools with an audit trail.
- Offline queue/draft support was identified as desirable future work but is not implemented yet.

## Latest implementation: live tournament (needs SQL run and frontend publish)

The last implementation added these files/changes in the previous workspace:

- `supabase-live-tournament.sql` — new migration.
- `supabase-ui.js` — live group builder, round controls, scorer screen and realtime multi-round leaderboard.
- `app.js` cache-bust version updated to `20260822-8`.

The migration introduces:

- `tournament_rounds.status`, `started_at`, `locked_at`.
- `live_round_groups` and `live_round_group_members`.
- `live_round_handicaps` for frozen exact/course/playing handicap snapshots.
- `live_round_hole_scores` for round-specific gross scores (required because the older `hole_scores` table has no round key).
- RPCs:
  - `save_live_round_groups(target_round, groups)`
  - `start_live_round(target_round)`
  - `save_live_round_scores(target_round, entries)`
  - `lock_live_round(target_round)`
  - `can_view_live_round(target_round)`
- Realtime publication for `live_round_hole_scores`.

Important: the migration should be reviewed/test-run in Supabase before depending on it. The static app has become heavily override-based (`supabase-ui.js` contains successive wrapper assignments), so future work should preferably refactor it into modules before substantial additional work.

To deploy the last live-scoring work from the original project folder:

```powershell
git add app.js supabase-ui.js supabase-live-tournament.sql
git commit -m "Add live tournament scoring"
git push
```

## Earlier database migrations/files

These have been created/run at different points. Do not assume they have all been re-run in a new environment; inspect Supabase first.

- `supabase-social-clubs.sql`
- `supabase-account.sql`
- `supabase-profile-and-invites.sql`
- `supabase-signup-repair.sql`
- `supabase-profile-recovery.sql`
- `supabase-club-event-access.sql`
- `supabase-tournament-management.sql`
- `supabase-multi-rounds.sql`
- `supabase-tournament-plan.sql`
- `supabase-course-handicaps.sql`
- `supabase-live-tournament.sql` (latest; may still need to be run)

## England Golf / MyEG integration research

Do not scrape MyEG or ask users for MyEG credentials.

Findings:

- England Golf/DotGolf has an ISV API with club-scoped credentials, member handicap endpoints, course/tee data and webhooks.
- This is not known to be a public “Sign in with MyEG” OAuth connection for general consumers.
- The app would need formal licensed ISV/API approval plus a secure backend. GitHub Pages cannot hold the secret credentials.
- A future Supabase Edge Function could store the issued secrets, retrieve access tokens, verify webhook signatures and update profile exact handicaps.
- Start with a read-only integration (handicap/course lookup); do not submit official scores initially.

Draft email subject:

```text
Birdie Board — enquiry about licensed ISV API access
```

The draft asks for licensed ISV onboarding, scope for read-only Handicap Index / course data / webhooks, support for social groups across clubs, test access, consent/data-protection obligations, costs, and whether player-authorised MyEG access exists.

Useful official links:

- England Golf WHS resources: https://www.englandgolf.org/resource-detail/whs-resources
- DotGolf ISV API: https://isvapi.whsplatform.englandgolf.org/index.html
- DotGolf supplementary technical docs: https://isvapi.whsplatform.englandgolf.org/v1documentation

## UI/UX fixes already made

- Logo links to sign-in/dashboard based on auth state.
- Favicon: `BB` with green background, white B then yellow B.
- UK date formatting applied in app display.
- Buttons use hand cursor.
- Login/Sign Up and password reset button alignment were adjusted.
- Browser Back behaviour was implemented with `history` / `popstate` wrappers.
- “Event History” renamed to “Events”.
- Event list open status was removed after alignment problems; Edit/Delete actions were placed together.
- Sign-in fields: email and password; Sign Up opens expanded profile form.

## Known cautions / technical debt

- `supabase-ui.js` is a large, compact script with many successive function wrappers/overrides. It works as an incremental prototype but is difficult to maintain and easy to regress. Refactor before adding teams/Ryder Cup formats, offline support, audit history or MyEG integration.
- Test with at least two user accounts before relying on RLS or live scoring.
- Do not claim changes are being made “in the background”; work only happens while the agent is active.
- If changes do not appear after GitHub Pages deploys, ensure `app.js` cache query version changed and do a hard refresh/incognito test.
- Preserve user changes in a dirty worktree; do not reset or overwrite unrelated edits.

## Suggested next steps

1. Verify/run `supabase-live-tournament.sql` and publish the frontend.
2. Test a two-user, one-round event end-to-end: add players → groups → start → scorer enters a hole → participant sees board update.
3. Test two-round accumulation and round-specific playing handicaps.
4. Improve the group builder from select controls to drag handles + tap-to-move fallback.
5. Add organiser score corrections, audit history and round locking/finalisation UI.
6. Add offline score draft/retry support.
7. Refactor the frontend into maintainable modules before larger features.
8. Send England Golf ISV enquiry; only design an integration after their response.
