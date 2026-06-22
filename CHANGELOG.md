# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
### Added
- Boolean literals (`true` / `false`), case-insensitive.
- `IF(condition, then, else)` with lazy branch evaluation.
- `AND(...)` / `OR(...)` with short-circuit evaluation, `NOT(x)`.
- Comparison built-ins: `EQ`, `NEQ`, `LT`, `GT`, `LTE`, `GTE`.

## [0.1.0] - 2026-06-22
### Added
- Initial release: `Lex`, `Parse`, `Execute`, `Compile`, `Eval`, `Build`.
- Structured error handling via `Errors.luau` (`ASMError` with `Kind`/`Message`/`Position`).
- Built-in functions: `ADD`, `SUB`, `MUL`, `DIV`, `POW`, `MIN`, `MAX`, `ABS`, `CONCAT`.
- TestEZ spec suite covering lexer, parser, executor, and error paths.
