---
name: briefeed-app-testing
description: Run Briefeed's isolated Radio test lanes through the shared simulator fleet engine.
---

# Briefeed Radio Simulator Lanes

The shared engine at `$HOME/ericode/skills/app-testing` is authoritative. This
adapter owns app-specific configuration only; do not copy or modify engine
logic here.

Run all simulator work headlessly. Use a distinct lane key for each stream:

```bash
make radio-compile
make radio-golden
make radio-unit
make radio-ui
make radio-smoke
make sim-doctor
make sim-status
```

`run-radio.sh <lane> <unit|ui|smoke>` returns exit `75` when the fleet has no
safe capacity, pressure is critical, or a lane claim is unavailable. Do not
override that result, target an unowned simulator, open Simulator.app, or use
broad simulator actions such as `shutdown all`, global erases, service kills,
or pattern deletes. The lane adapter releases its use lock after each run and
leaves its owned simulator booted for warm reuse.
