# Runtime performance probes

The repository includes optional probes for release-note summaries, timestamp
parsing, screenshot coverage caches, and screenshot toolbar state. They warm up
before collecting samples and check their computed results. Timing thresholds
are intentionally omitted so correctness does not depend on machine load.

## Reproduction

```sh
swift test
SHIPNOTES_BENCHMARKS=1 swift test -c release --filter RuntimePerformanceTests
SHIPNOTES_BENCHMARKS=1 swift test -c release --filter ScreenshotToolbarPerformanceTests
```

The default run skips the optional probes. Record the commit, OS, compiler, SDK,
build configuration, and hardware class when comparing results; use the same
fixtures and environment for both versions. Do not publish workstation names,
account identifiers, or absolute personal paths with benchmark output.

## Implementation and limits

- `DiffEngine.summary` counts common ends directly and computes the remaining
  longest common subsequence with one row. DP storage is linear in the shorter
  remaining sequence; worst-case time for unrelated inputs remains quadratic.
  The detailed diff retains its full table and alignment behavior.
- Screenshot coverage resolves paths during cache rebuilds and indexes direct
  and shared assets. Warm reads reuse coverage and issue results; changes to
  assets, locales, sharing, requirements, or overrides invalidate those caches.
- Screenshot toolbar state reuses the cached AI-matching candidates and
  computes preview control state together.
- Date parsing reuses two private formatter configurations under a lock rather
  than constructing them for every timestamp.

Fixtures use in-memory metadata and synthetic documents. Measurements exclude
build time, image decoding, file scanning, network requests, screenshot uploads,
and actual UI frame rendering. They do not establish whole-app speed, startup
latency, memory use, or frame rate. Functional regression tests independently
cover parsing, diff behavior, and cache invalidation.
