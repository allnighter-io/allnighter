#!/usr/bin/env python3
"""Second pass: zero forbidden vocabulary in docs/."""
from pathlib import Path
import os

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"

REPLACEMENTS = [
    ("council_start", "team_start"),
    ("council_status", "team_status"),
    ("council_result", "team_result"),
    ("council_pricing", "team_pricing"),
    ("council_*", "team_*"),
    ("`council_*`", "`team_*`"),
    ("X-Allnighter-Council-Depth", "X-Allnighter-Team-Depth"),
    ("JudgeAnalysis", "PlanAnalysis"),
    ("panel→judge→plan", "team→plan writer→plan"),
    ("panel->judge->plan", "team->plan writer->plan"),
    ("member/judge", "worker/plan writer"),
    ("agent race/council", "agent race/team"),
    ("imp-panel", "imp-surface"),
    ("jc-seat", "jc-worker"),
    ("ja-seat", "ja-worker"),
    ("ji3-seat", "ji3-worker"),
    ("A_SEATS", "A_WORKERS"),
    ("council/2026", "team/2026"),
    ("panel answer", "worker answer"),
    ("judge it", "review it"),
    ("judge analysis", "plan analysis"),
    ("panel-tier", "team-tier"),
    ("TeamRun.panel", "TeamRun.workers"),
    ("panel *and*", "team *and*"),
    ("budget-panel", "budget-team"),
    ("worker/seat", "worker"),
    ("member_<seat>", "member_<worker>"),
    ('group="Council"', 'group="Team"'),
    ('section="Council"', 'section="Team"'),
    ("Council*", "Team*"),
    ("Council,", "Team,"),
    ("Council ", "Team "),
    ("Council.", "Team."),
    ("Council:", "Team:"),
    ("Council)", "Team)"),
    ("Council(", "Team("),
    ("Council/", "Team/"),
    ("Council-", "Team-"),
    ("council/", "team/"),
    ("council,", "team,"),
    ("council.", "team."),
    ("council:", "team:"),
    ("council)", "team)"),
    ("council(", "team("),
    ("'Panel'", "'Team'"),
    ('"Panel"', '"Team"'),
    ("label: 'Panel'", "label: 'Team'"),
    ("id: 'panel'", "id: 'team'"),
    ("['Panel'", "['Team'"),
    ("Council-as-tool", "Team-as-tool"),
    ("Council-as-Tool", "Team-as-Tool"),
    ("team/worker/council/plan", "team/worker/plan"),
    ("panel, worker, team run", "team, worker, team run"),
    ("panel ·", "team ·"),
    ("panel review", "team review"),
    ("panel is `[Worker]`", "team is `[Worker]`"),
    ("The *panel*", "The *team*"),
    ("**Panel**", "**Team**"),
    ("| **Panel** |", "| **Team** |"),
    ("(panel ", "(team "),
    ("(panel)", "(team)"),
    ("(panel,", "(team,"),
    ("(panel·", "(team·"),
    (" panel ", " team "),
    (" panel.", " team."),
    (" panel,", " team,"),
    (" panel·", " team·"),
    (" panel)", " team)"),
    (" panel/", " team/"),
    (" panel:", " team:"),
    (" panel`", " team`"),
    ("`panel`", "`team`"),
    ("`seat`", "`worker`"),
    (" or `seat`", " or `worker`"),
    ("`judge`", "`plan writer`"),
    (" or `judge`", " or `plan writer`"),
    ("judge profiles", "plan writer profiles"),
    ("synthesis/judge", "synthesis/plan writer"),
    ("Selectable (panel)", "Selectable (team)"),
    (".panel{", ".ds-surface{"),
    (".panel ", ".ds-surface "),
    (".panel.", ".ds-surface."),
    ('className: "panel"', 'className: "ds-surface"'),
    ("layout-panel-left", "layout-sidebar"),
    ("uploads/README", "archive/mentor-uploads/README"),
    ("design-system/uploads", "archive/mentor-uploads"),
    ("RB6_Council_As_Tool", "RB6_Team_As_Tool"),
    ("ON HOLD/13_Council.md", "archived team slice"),
    ("13_Council.md", "team slice"),
    ("Judgment_Workflow", "Review_Workflow"),
    ("Judgment workflow", "Review workflow"),
    ("judgment workflow", "review workflow"),
]

EXTENSIONS = {".md", ".swift", ".html", ".jsx", ".js", ".css", ".json", ".prompt.md", ".d.ts", ".tsx"}


def main():
    changed = 0
    for dirpath, _, filenames in os.walk(DOCS):
        for name in filenames:
            path = Path(dirpath) / name
            if path.suffix not in EXTENSIONS and path.name not in {"SKILL.md", "README"}:
                continue
            try:
                text = path.read_text(encoding="utf-8")
            except (UnicodeDecodeError, OSError):
                continue
            new = text
            for old, rep in REPLACEMENTS:
                new = new.replace(old, rep)
            if new != text:
                path.write_text(new, encoding="utf-8")
                changed += 1
    print(f"pass2: {changed} files")


if __name__ == "__main__":
    main()
