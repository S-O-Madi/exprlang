--!strict
--[[
	Errors.luau

	Structured error handling for the ASM DSL.
	Every error thrown by the pipeline (Lex/Parse/Execute) is an ASMError
	instance instead of a raw string, so callers can inspect `.Kind`,
	`.Message` and `.Position` programmatically (e.g. to build editor
	diagnostics) while still getting a readable `tostring()`.
]]

local Errors = {}
local BuiltIn = {}
Errors.__index = Errors

export type ErrorKind =
	"LexError"
	| "ParseError"
	| "ExecuteError"
	| "RegistryError"

export type self = typeof(setmetatable(
	{} :: {
		Kind: ErrorKind,
		Message: string,
		Position: number?,
		Source: string?,
	},
	Errors
))

--==================================================
-- Constructor
--==================================================

function Errors.new(kind: ErrorKind, message: string, position: number?, source: string?): self
	return setmetatable({
		Kind = kind,
		Message = message,
		Position = position,
		Source = source,
	}, Errors) :: self
end

--==================================================
-- Formatting
--==================================================

function Errors.__tostring(self: self): string
	if self.Position then
		return ("[ASM:%s] %s (position %d)"):format(self.Kind, self.Message, self.Position)
	end

	return ("[ASM:%s] %s"):format(self.Kind, self.Message)
end

--==================================================
-- Helpers
--==================================================

-- Throws a structured ASMError. Use this instead of `error()` directly
-- everywhere inside the ASM pipeline.
function Errors.Throw(kind: ErrorKind, message: string, position: number?, source: string?): never
	local err = Errors.new(kind, message, position, source)
	error(err, 0) -- level 0: we already format our own message, no need for Lua to prepend file:line
end

-- Returns true if the given value is an ASMError instance.
function Errors.Is(value: any): boolean
	return typeof(value) == "table" and getmetatable(value) == Errors
end

--==================================================
-- Built-in Errors
--==================================================

function BuiltIn.DivByZero(pos:number?, source:string?)
	Errors.Throw("ExecuteError", "Divided by Zero.", pos, source)
end

Errors["BuiltIn"] = BuiltIn
return Errors
