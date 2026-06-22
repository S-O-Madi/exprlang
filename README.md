# ASM

A small DSL engine for Luau: evaluate string-based expressions like
`ADD(VAR("A"), VAR("B"))` against a table of variables.

## Installation (Wally)

Add to your `wally.toml`:

```toml
[dependencies]
ASM = "gt/asm@0.1.0"
```

Then:

```bash
wally install
```

## Usage

```luau
local ASM = require(Packages.ASM)

local result = ASM:Eval([[ADD(VAR("A"), VAR("B"))]], { A = 10, B = 15 })
print(result) --> 25

-- Compile once, run many times with different variables
local compiled = ASM:Build([[POW(VAR("base"), VAR("exp"))]])
print(compiled({ base = 2, exp = 10 })) --> 1024

-- Non-throwing variant
local ok, resultOrErr = ASM:TryEval([[ADD(VAR("A"), VAR("B"))]], { A = 1 })
if not ok then
	warn(tostring(resultOrErr))
end
```

### Registering custom functions

```luau
ASM:Register("DOUBLE", function(x: number)
	return x * 2
end)

ASM:Eval("DOUBLE(21)") --> 42
```

### Conditional logic

`true` / `false` are recognized as boolean literals. `IF`, `AND`, `OR`, and
`NOT` are built into the parser (not regular registered functions), so they
evaluate **lazily** — `IF(cond, a, b)` only evaluates the taken branch, and
`AND`/`OR` short-circuit:

```luau
ASM:Eval([[IF(GT(VAR("hp"), 0), "alive", "dead")]], { hp = 0 })
--> "dead"

-- The else-branch never runs DIV(1, 0) since the condition is true:
ASM:Eval([[IF(true, 42, DIV(1, 0))]])
--> 42

ASM:Eval([[AND(GT(VAR("hp"), 0), NOT(VAR("isStunned")))]], { hp = 10, isStunned = false })
--> true
```

Comparison built-ins: `EQ`, `NEQ`, `LT`, `GT`, `LTE`, `GTE`.

## Local development

Requires [Aftman](https://github.com/LPGhatguy/aftman) to pin tool versions.

```bash
aftman install        # installs rojo, wally, selene, stylua at pinned versions
wally install         # installs TestEZ as a dev-dependency
```

### Serve the package alone (no game, just for sourcemap/inspection)

```bash
rojo serve default.project.json
```

### Run tests

Open `test.project.json` in Rojo, connect Studio, then press Play —
`test/init.server.luau` boots TestEZ against every `*.spec.luau` file
under `src/`.

Headless (CI), see `.github/workflows/ci.yml`.

### Lint / format

```bash
selene src
stylua --check src
```

## Publishing a new version

1. Bump `version` in `wally.toml`.
2. Add an entry to `CHANGELOG.md`.
3. `wally publish`.
