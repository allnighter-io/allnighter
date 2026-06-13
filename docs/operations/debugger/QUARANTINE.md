# Quarantine

Tests or gates that cannot run green yet must be listed here with owner, reason,
and expiry. Expired quarantine entries should fail the green wall once CI exists.

Format:

```text
- <command or test path>: owner <name>, reason <why>, expiry YYYY-MM-DD
```

No active quarantines.
