# rqp-plugin-homebrew

ReqPack Lua wrapper plugin for Homebrew.

Supports:

- macOS and Linux
- Homebrew `formulae`
- Homebrew `casks`
- automatic Homebrew bootstrap during `install` when `brew` is missing

## Bundle Layout

- `metadata.json`: plugin id and bundle metadata
- `reqpack.lua`: plugin bundle manifest
- `run.lua`: Homebrew wrapper implementation
- `scripts/install.lua`: required bundle hook stub
- `scripts/remove.lua`: required bundle hook stub
- `API.md`: ReqPack Lua plugin quick reference
- `.reqpack-test/core/*.lua`: hermetic conformance cases

## Behavior

- package type is auto-detected from Homebrew metadata
- if a name exists as both formula and cask, formula wins
- `install` bootstraps Homebrew automatically if needed
- `list`, `search`, `info`, and `outdated` use Homebrew metadata output
- `installLocal()` is intentionally unsupported in first version

## Running Tests

From plugin root:

```bash
rqp test-plugin --plugin ./run.lua --preset core
```

Run one case:

```bash
rqp test-plugin --plugin ./run.lua --case ./.reqpack-test/core/info.lua
```

## Notes

- wrapper stays thin and delegates package behavior to Homebrew
- package metadata is mapped conservatively from Homebrew JSON output
- CI validates direct plugin execution and copied bundle execution
