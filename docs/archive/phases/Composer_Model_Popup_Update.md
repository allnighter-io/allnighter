Update the composer team/model popover to simplify team selection.

Context:
The current composer popover shows Team / Worker, then craft chips like Code, Design, Copy, Signal, then a list of teams. We want this popover to become a fast picker, not a full roster browser. The full Teams screen can remain the place for browsing, filtering, editing, starring, and managing teams.

Relevant product language:
- Keep “Team” as the product noun.
- Auto literally means AUTO.
- In this UI, label it exactly: “Auto”
- Supporting copy should be: “Default model”
- Do not rename Auto to route, default route, smart route, etc.

Goal:
Simplify the composer popover so it always exposes:
1. Auto at the top
2. Search / drill down
3. Most recent teams
4. Favorite teams

Remove the craft filter chips from this popover.

Desired default layout:
- Keep the existing Team / Worker segmented control if it is already part of this picker.
- Under that, show Auto as the first pinned row/card.
- Then show a compact search field.
- Then show “Recent” with the last 2-3 selected teams.
- Then show “Favorites” as the main scrolling list.
- Everything else should be hidden unless the user searches.

Suggested structure:

Auto
Default model

[Search teams...]

Recent
- Code Core
- Bug Hunt
- GUI Bug Hunt

Favorites
- Security Review
- Copy Polish
- Design Critique
- etc.

Behavior:
- Auto is always visible at the top, even while searching.
- Auto should show selected state when no specific team/model has been chosen.
- Search filters across all available teams, not only favorites.
- Search should match team name, craft, worker/model/provider metadata if available, and any existing searchable descriptors already used elsewhere.
- When the search query is empty:
  - show Recent, max 3 items
  - show Favorites
  - hide all non-favorite, non-recent teams
- When the search query is non-empty:
  - show matching teams from the full roster
  - favorites/recent matches can still appear, but avoid duplicate rows
  - use a simple “No teams found” empty state if nothing matches
- Recent should not duplicate Auto.
- Recent should not duplicate rows already visible in Favorites if the same team is favorited; either omit duplicates from Recent or visually prioritize it once.
- Favorites are the default browsing surface.
- Non-favorites should not be visible in the picker unless found by search.
- Keep any existing selected-team checkmark behavior.
- Keep favorite/star affordance only if it already works cleanly in this popover; otherwise this picker can be selection-only and team management stays in the full Teams screen.
- Keep “Customize...” or “Manage teams...” only if needed, but it should be visually secondary and below the lists.

Remove:
- Remove Code / Design / Copy / Signal chips from the composer popover.
- Remove any “All” chip/filter from this composer popover.
- Do not turn Search / Favorites / Recent into tabs. Search is a field; Recent and Favorites are sections.

Copy:
- Pinned row title: “Auto”
- Pinned row subtitle: “Default model”
- Search placeholder: “Search teams...”
- Section label: “Recent”
- Section label: “Favorites”
- Empty search state: “No teams found”
- Optional footer action: “Manage teams...”

Visual direction:
- Match the existing Allnighter dark UI and amber phosphor accent.
- The picker should feel lighter and faster than the full Teams screen.
- Search should visually replace the chip row.
- Keep spacing compact enough that Auto + search + at least a couple rows are visible without scrolling.
- Avoid making the popover into a dashboard/card grid.

Implementation notes:
- Prefer deriving recent teams from existing selection history if available.
- If no recents exist, omit the Recent section entirely.
- If no favorites exist, show Auto + search and optionally a subtle empty Favorites state or “Manage teams...”.
- Keep the full Teams / roster page behavior separate; this change is only for the composer picker unless shared components force a small refactor.

Acceptance criteria:
- Composer popover no longer shows craft chips.
- Auto is always first and reads “Auto” / “Default model”.
- Empty search shows Recent max 3 plus Favorites.
- Search reveals matching teams from the full roster.
- Non-favorites are hidden by default.
- Selecting Auto or a team updates the composer exactly as before.
- No duplicate teams appear between Recent and Favorites/search results.
- Existing tests pass, and add/adjust a focused test for picker filtering if the project has UI/model tests around this surface.

Proof:
Run the repo’s normal checks from docs/operations/TechStack.md. At minimum:
- swift test
- any relevant xcodebuild test command if this surface has an app target test available

Commit:
Stage only the files changed for this slice and commit with a clear message, for example:
“composer: simplify team picker”

One small product note: I’d put search directly under Auto, not below Recent. That lets the picker answer both modes instantly: “I know what I want” and “show me my bench.”