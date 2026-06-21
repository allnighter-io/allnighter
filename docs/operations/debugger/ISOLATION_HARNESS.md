# Isolation Harness

An isolation harness is a disposable proof project for a repeated bug. It strips
the product down to the smallest app that still contains the suspected seam, then
makes the failing capability work there before any more product patches.

The green harness is the spec. The delta between the harness and Allnighter is
the fix boundary.

## Mandate

Build an isolation harness before more in-product patching when any of these are
true:

- The same bug fingerprint survived two honest fixes.
- The bug crosses a native/framework seam: AppKit/SwiftUI, pasteboard/responder,
  TCC/app lifecycle, filesystem watcher, process/pty, network/session, parser/UI.
- The only current evidence is founder confirmation, "this one layer works", a
  build, a screenshot, or a direct unit test below the failing seam.
- The honest kill test cannot yet be written in the product because too many
  layers move at once.

One failed fix is enough to mandate a harness when the bug is obviously a
cross-framework seam.

## Shape

The harness must be smaller than the product but faithful to the seam:

- Keep only the primitive and the seam. Remove routing, stores, styling, worker
  dispatch, persistence, analytics, and product helpers unless they are the seam.
- Mirror the same frameworks and boundary. A simpler analog that removes the
  seam proves the wrong thing.
- Give it one visible/output success criterion a non-coder can confirm.
- Keep the run command, relevant files, and observation notes small enough to
  archive or reconstruct.

For the composer image-paste bug, "one text field, paste an image, a chip
appears" was the harness. A plain pasteboard reader test was not enough because
it did not include the AppKit/SwiftUI responder seam.

## Outcomes

- If the bug reproduces in the harness, the seam itself is broken. Fix it there,
  then port the working API/path back.
- If the bug does not reproduce, the product is adding the breakage. Reintroduce
  product layers one at a time until the harness fails; that layer is the culprit.
- If the primitive cannot work in the harness, stop and report a platform or
  assumption problem instead of patching product code.

## Port Back

Before editing the product again, write down:

```text
Harness path / command:
Seam mirrored:
Success criterion:
Working API/path:
Baseline-to-product delta:
Kill test created from the harness:
```

Only port the necessary delta. Do not copy the harness architecture into the
product, and do not keep unrelated cleanup in the same fix.

## Proof Law

A true statement near the bug is not proof. For seam bugs, proof must traverse
the seam end to end.

Founder confirmation is useful intake, but if a repeated seam bug relies on it
as the only proof, the process is missing an isolation harness.
