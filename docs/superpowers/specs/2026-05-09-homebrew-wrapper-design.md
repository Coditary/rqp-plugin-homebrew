# Homebrew Wrapper Plugin Design

## Goal

Implement ReqPack Lua wrapper plugin for Homebrew that:

- supports macOS and Linux
- supports both Homebrew formulae and casks
- auto-installs Homebrew during `install` if `brew` is missing
- auto-detects package type and prefers formula when a name exists as both formula and cask
- exposes realistic `list`, `search`, `info`, `outdated`, and `resolvePackage` behavior

## Scope

In scope:

- replace template metadata with `homebrew` plugin metadata
- implement wrapper behavior in `run.lua`
- keep bundle hook stubs in `scripts/install.lua` and `scripts/remove.lua`
- update hermetic `.reqpack-test/core/*.lua` cases to reflect Homebrew behavior
- update README usage text from template wording to Homebrew wording

Out of scope for first version:

- full local artifact installation for arbitrary `.rb` formula files or tap bundles
- advanced tap management
- custom package-type flags in ReqPack requests
- deep SBOM enrichment beyond stable metadata already available from Homebrew

## Design Choices

### Single plugin, early internal resolution

Use one plugin id: `homebrew`.

External UX stays simple: user asks for `homebrew <name>` and plugin resolves package type automatically. Internally, package type is determined early and reused for command building and metadata mapping.

### Auto-bootstrap only on install

If `brew` is missing:

- `install` attempts official Homebrew bootstrap automatically
- all other actions do not bootstrap and instead report unavailability or no-op as appropriate

This keeps read-only actions safe and avoids surprising side effects outside explicit installation.

### Package-type auto-detection

Package type detection uses Homebrew itself as source of truth:

1. query `brew info --json=v2 <name>`
2. inspect returned `formulae` and `casks`
3. choose:
   - formula if only formula exists
   - cask if only cask exists
   - formula if both exist
   - unavailable if neither exists

Resolved package info is reused by `install`, `remove`, `update`, `info`, and `resolvePackage`.

### Conservative data mapping

Only stable and obviously available Homebrew fields are mapped into ReqPack package info:

- `name`
- `packageId`
- `version`
- `latestVersion`
- `installed`
- `status`
- `summary`
- `description`
- `homepage`
- `license`
- `repository`
- `packageType`
- `dependencies`
- `binaries`
- `extraFields.packageType`

This avoids coupling plugin behavior to unstable or undocumented JSON subfields.

## Runtime Flow

### `init()`

`init()` returns `true` even if `brew` is absent.

Reason: plugin must remain loadable so `install` can bootstrap Homebrew later.

### `getMissingPackages(packages)`

Behavior by action:

- `install`: return packages that are not already installed
- `remove`: return packages that are installed
- `update`: return packages that are outdated
- unknown/no action: keep conservative fallback and return unresolved work items

When `brew` is missing:

- install -> return all requested packages
- remove/update -> return empty set

### `install(context, packages)`

1. if no packages: return `true`
2. if `brew` missing: run official installer
3. resolve each package to `formula` or `cask`
4. batch formulae and casks separately
5. execute:
   - `brew install <formulae...>`
   - `brew install --cask <casks...>`
6. emit `installed` event with resolved packages
7. call `tx.success()` on success

If bootstrap or install command fails, call `tx.failed(...)` and return `false`.

### `installLocal(context, path)`

First version does not support local Homebrew artifacts. Method exists for contract compatibility and returns `false` after a clear transaction failure.

### `remove(context, packages)`

Resolve package types, then batch:

- `brew uninstall <formulae...>`
- `brew uninstall --cask <casks...>`

Emit `deleted` event and `tx.success()` on success.

### `update(context, packages)`

Resolve package types, then batch:

- `brew upgrade <formulae...>`
- `brew upgrade --cask <casks...>`

Emit `updated` event and `tx.success()` on success.

### `list(context)`

Use installed Homebrew JSON views to collect installed formulae and casks, then map to ReqPack package info array and emit `listed`.

### `search(context, prompt)`

Use `brew search <prompt>` to get candidate names, then enrich candidates with `brew info --json=v2` so results can include package type, summary, versions, and installed state.

If prompt is empty, return empty result set and emit `searched`.

### `info(context, packageName)`

Use `brew info --json=v2 <name>`, resolve preferred package record, map it into one package info table, emit `informed`, return that table.

If package does not exist, emit `unavailable` and return empty table.

### `outdated(context)`

Use `brew outdated --json=v2`, map formulae and casks into package info records with both current and latest versions, emit `outdated`, return array.

### `resolvePackage(context, package)`

Resolve exact package type and best available version from Homebrew metadata.

Return package-like table enriched with:

- `name`
- `version`
- `latestVersion`
- `packageType`
- `extraFields.packageType`

This improves planning quality and later audit/SBOM compatibility.

### `getSecurityMetadata()`

Return thin-layer security metadata for wrapper plugin:

- role: package-manager
- capabilities: exec, network
- ecosystem scope: homebrew
- privilege level: user
- purl type: generic or omitted if unsure

`osvEcosystem` stays unset for now because Homebrew spans multiple upstream ecosystems and first version should not overclaim audit fidelity.

## Helpers

`run.lua` should keep implementation thin with a few focused helpers:

- shell quoting
- optional log wrappers
- transaction wrappers
- `brew_exists()`
- `ensure_brew_installed(context)`
- `brew_cmd(...)`
- `run_brew(context, args, options)`
- `decode_json(context, raw)`
- `fetch_info_json(context, names, extraArgs)`
- `detect_package_type_from_info(info, name)`
- `map_formula_to_package_info(formula)`
- `map_cask_to_package_info(cask)`
- `resolve_requested_package(context, pkg)`

Implementation should prefer small local helpers instead of introducing extra files.

## JSON Handling Strategy

Homebrew exposes best metadata through JSON. Plugin should decode JSON in Lua when possible.

Implementation plan:

1. try common Lua JSON modules in `pcall(require, ...)`
2. use first available decoder
3. if decoder is unavailable, fail actions that require JSON with clear error

This avoids brittle string parsing and keeps wrapper deterministic.

## Bootstrap Strategy

Official installer command:

`/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`

Wrapper uses non-interactive environment where practical:

- `NONINTERACTIVE=1`

After bootstrap, plugin re-checks `brew` availability before continuing install.

Bootstrap support is best-effort. If target host misses prerequisites like Xcode CLT on macOS, plugin surfaces the installer failure instead of trying to hide it.

## Error Handling

- missing `brew` for non-install actions -> unavailable event or empty result
- package not found -> unavailable event and graceful failure/empty result depending on action
- JSON decode failure -> transaction failure for action methods, empty result for read methods when safer
- ambiguous package names -> formula wins, log informational message
- command failure -> use `tx.failed(...)` and return `false`

## Test Plan

Hermetic tests should cover at least:

- install formula
- install cask
- install with missing `brew` followed by bootstrap success
- install bootstrap failure
- remove formula
- remove cask
- update formula
- list mixed formula/cask installed set
- search mixed formula/cask results
- info formula
- info cask
- outdated mixed formula/cask
- missing package
- formula-vs-cask ambiguity prefers formula
- installLocal unsupported failure

## Verification

Primary verification:

- `rqp test-plugin --plugin ./run.lua --preset core`

Optional later smoke tests on real hosts:

- macOS with no Homebrew installed
- macOS with formula + cask mix
- Linux with Homebrew already installed

## Risks

- ReqPack runtime may not ship Lua JSON module expected by plugin
- Homebrew installer may require prerequisites not available in hermetic tests
- Homebrew JSON schema can add fields over time; plugin must ignore unknown fields
- `brew search` output is not JSON, so enrichment step must stay conservative

## Mitigations

- decoder loading isolated in one helper with clear failure path
- tests focus on command contracts, events, and result mapping
- mapping uses only stable subset of Homebrew fields
- command strings remain explicit and predictable for fakeExec matching
