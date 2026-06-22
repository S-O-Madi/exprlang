# ExprLang

A lightweight `ASM-DSL` engine for evaluating string-based expressions.

## Installation (Wally)

Add to your `wally.toml`:

```toml
[dependencies]
Exprlang = "s-o-madi/exprlang@0.1.0"
```

Then:

```bash
wally install
```

## Usage

```luau
local Exprlang = require(Packages.Exprlang)

local result = Exprlang:Eval([[ADD(VAR("A"), VAR("B"))]], { A = 10, B = 15 })
print(result) --> 25

-- Compile once, run many times with different variables
local compiled = Exprlang:Build([[POW(VAR("base"), VAR("exp"))]])
print(compiled({ base = 2, exp = 10 })) --> 1024

-- Non-throwing variant
local ok, resultOrErr = Exprlang:TryEval([[ADD(VAR("A"), VAR("B"))]], { A = 1 })
if not ok then
	warn(tostring(resultOrErr))
end
```

### Registering custom functions

```luau
Exprlang:Register("DOUBLE", function(x: number)
	return x * 2
end)

Exprlang:Eval("DOUBLE(21)") --> 42
```

### Conditional logic

`true` / `false` are recognized as boolean literals. `IF`, `AND`, `OR`, and
`NOT` are built into the parser (not regular registered functions), so they
evaluate **lazily** — `IF(cond, a, b)` only evaluates the taken branch, and
`AND`/`OR` short-circuit:

```luau
Exprlang:Eval([[IF(GT(VAR("hp"), 0), "alive", "dead")]], { hp = 0 })
--> "dead"

-- The else-branch never runs DIV(1, 0) since the condition is true:
Exprlang:Eval([[IF(true, 42, DIV(1, 0))]])
--> 42

Exprlang:Eval([[AND(GT(VAR("hp"), 0), NOT(VAR("isStunned")))]], { hp = 10, isStunned = false })
--> true
```

Comparison built-ins: `EQ`, `NEQ`, `LT`, `GT`, `LTE`, `GTE`.
