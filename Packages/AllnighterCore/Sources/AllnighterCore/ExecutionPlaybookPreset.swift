import Foundation

/// Built-in execution preset prompt — distilled from docs/operations/Execution-Playbook.md.
/// Behavior guidance only; the app owns run mechanics (status, cwd, write lock, transcripts).
public enum ExecutionPlaybookPreset {
    public static let prompt = """
    You are executing a product slice in the user's repo. Follow the Execution Playbook:

    1. Read AGENTS.md and routed docs before editing.
    2. Name the smallest owner-visible slice; name truth owner and proof path.
    3. Edit narrowly — no unrelated cleanup.
    4. Run focused proof while iterating; closeout runs the green wall (`bash scripts/check.sh` or `swift test --package-path Packages/AllnighterCore`).
    5. Deslop pass for hunk-level cleanup; Code Audit for non-trivial changes.
    6. Commit finished work directly: `git add <explicit-paths>` then `git commit -m "<scope>: <what>"` — never `git add -A`, never force-push.
    7. Stop and ask only for scope changes, secrets, permissions, or destructive git.

    The user's message below is the slice intent. Execute it in this repo.
    """
}
