--!strict
--[[
	ASM/init.luau

	A small DSL engine that parses and evaluates expressions like:
		ADD(VAR(A), VAR(B))
		MUL(ADD(VAR(x), 5), VAR(y))
		CONCAT("Hello, ", VAR(name))
		IF(GT(VAR(hp), 0), "alive", "dead")
		AND(GT(VAR(hp), 0), LT(VAR(hp), VAR(maxHp)))

	Pipeline: Lex (string -> tokens) -> Parse (tokens -> AST)
	          -> Execute (AST + variables -> value)
	                   or Compile (AST -> reusable callable)

	IF / AND / OR / NOT are parsed as dedicated AST node types (like VAR)
	rather than regular function calls, so their branches are evaluated
	lazily: IF(cond, expensive(), 0) never runs expensive() when cond is
	false, and AND/OR short-circuit on the first decisive value.

	All methods are written as `function ASM.Method(self: self, ...)` and
	exposed publicly through `:Method()`. This keeps Luau's strict typecheck
	happy on `self` inside the module while preserving the familiar method
	call syntax for external callers.
]]

local Errors = require(script.Errors)
local BuiltError = Errors.BuiltIn

local ASM = {}
ASM.__index = ASM

--==================================================
-- Types
--==================================================

export type TokenType = "IDENT" | "NUMBER" | "STRING" | "BOOLEAN" | "LPAREN" | "RPAREN" | "COMMA"

export type Token = {
	Type: TokenType,
	Value: any,
	Position: number,
}

export type ASTNodeType = "Call" | "Number" | "String" | "Boolean" | "Var" | "If" | "And" | "Or" | "Not"

export type ASTNode = {
	Type: ASTNodeType,
	Value: any,
	Children: { ASTNode },
}

export type Variables = { [string]: any }

export type CompiledFn = (variables: Variables?) -> any

export type self = typeof(setmetatable(
	{} :: {
		Functions: { [string]: (...any) -> any },
	},
	ASM
))

--==================================================
-- Registration
--==================================================

function ASM.Register(self: self, name: string, callback: (...any) -> any)
	self.Functions[string.upper(name)] = callback
end

function ASM.Unregister(self: self, name: string)
	self.Functions[string.upper(name)] = nil
end

function ASM.GetFunction(self: self, name: string): ((...any) -> any)?
	return self.Functions[string.upper(name)]
end

--==================================================
-- Helpers
--==================================================

function ASM.CreateNode(_: self, nodeType: ASTNodeType, value: any, children: { ASTNode }?): ASTNode
	return {
		Type = nodeType,
		Value = value,
		Children = children or {},
	}
end

--==================================================
-- Lexer
--==================================================

local function isDigit(c: string): boolean
	return c >= "0" and c <= "9"
end

local function isAlpha(c: string): boolean
	return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_"
end

local function isAlphaNumeric(c: string): boolean
	return isAlpha(c) or isDigit(c)
end

function ASM.Lex(_: self, source: string): { Token }
	local tokens: { Token } = {}
	local i = 1
	local len = #source

	while i <= len do
		local c = string.sub(source, i, i)

		-- Skip whitespace
		if c == " " or c == "\t" or c == "\n" or c == "\r" then
			i += 1
			continue
		end

		-- Parentheses
		if c == "(" then
			table.insert(tokens, { Type = "LPAREN", Value = "(", Position = i })
			i += 1
			continue
		end

		if c == ")" then
			table.insert(tokens, { Type = "RPAREN", Value = ")", Position = i })
			i += 1
			continue
		end

		-- Comma
		if c == "," then
			table.insert(tokens, { Type = "COMMA", Value = ",", Position = i })
			i += 1
			continue
		end

		-- String literal ("..." or '...')
		if c == '"' or c == "'" then
			local quote = c
			local startPos = i
			local j = i + 1
			local buffer = {}

			while j <= len and string.sub(source, j, j) ~= quote do
				local ch = string.sub(source, j, j)
				-- Basic escape support: \" \' \\ \n \t
				if ch == "\\" and j < len then
					local nextCh = string.sub(source, j + 1, j + 1)
					if nextCh == "n" then
						table.insert(buffer, "\n")
					elseif nextCh == "t" then
						table.insert(buffer, "\t")
					else
						table.insert(buffer, nextCh)
					end
					j += 2
				else
					table.insert(buffer, ch)
					j += 1
				end
			end

			if j > len then
				Errors.Throw("LexError", "Unterminated string literal", startPos, source)
			end

			table.insert(tokens, { Type = "STRING", Value = table.concat(buffer), Position = startPos })
			i = j + 1
			continue
		end

		-- Number literal (123, 12.5, -3, -3.5)
		if isDigit(c) or (c == "-" and isDigit(string.sub(source, i + 1, i + 1))) then
			local startPos = i
			local j = i + 1

			while j <= len and isDigit(string.sub(source, j, j)) do
				j += 1
			end

			if string.sub(source, j, j) == "." then
				j += 1
				while j <= len and isDigit(string.sub(source, j, j)) do
					j += 1
				end
			end

			local numStr = string.sub(source, startPos, j - 1)
			local num = tonumber(numStr)

			if not num then
				Errors.Throw("LexError", ("Invalid number literal '%s'"):format(numStr), startPos, source)
			end

			table.insert(tokens, { Type = "NUMBER", Value = num, Position = startPos })
			i = j
			continue
		end

		-- Identifier / function name (ADD, VAR, SUB, myFunc123...)
		if isAlpha(c) then
			local startPos = i
			local j = i + 1

			while j <= len and isAlphaNumeric(string.sub(source, j, j)) do
				j += 1
			end

			local ident = string.sub(source, startPos, j - 1)
			local lowerIdent = string.lower(ident)

			if lowerIdent == "true" then
				table.insert(tokens, { Type = "BOOLEAN", Value = true, Position = startPos })
			elseif lowerIdent == "false" then
				table.insert(tokens, { Type = "BOOLEAN", Value = false, Position = startPos })
			else
				table.insert(tokens, { Type = "IDENT", Value = ident, Position = startPos })
			end

			i = j
			continue
		end

		Errors.Throw("LexError", ("Unexpected character '%s'"):format(c), i, source)
	end

	return tokens
end

--==================================================
-- Parser
--==================================================

-- Grammar:
--   expr := IDENT LPAREN args? RPAREN | NUMBER | STRING
--   args := expr (COMMA expr)*

function ASM.Parse(self: self, tokens: { Token }, source: string?): ASTNode
	local pos = 1
	local len = #tokens

	local function peek(): Token?
		return tokens[pos]
	end

	local function advance(): Token
		local tok = tokens[pos]
		if not tok then
			Errors.Throw("ParseError", "Unexpected end of input", nil, source)
		end
		pos += 1
		return tok
	end

	local function expect(tokenType: TokenType): Token
		local tok = peek()
		if not tok then
			Errors.Throw(
				"ParseError",
				("Expected %s but reached end of input"):format(tokenType),
				nil,
				source
			)
		end
		if tok and tok.Type ~= tokenType then
			Errors.Throw(
				"ParseError",
				("Expected %s but got %s ('%s')"):format(tokenType, tok.Type, tostring(tok.Value)),
				tok.Position,
				source
			)
		end
		return advance()
	end

	local parseExpr: () -> ASTNode

	local function parseArgs(): { ASTNode }
		local args: { ASTNode } = {}

		local nextTok = peek()
		if nextTok and nextTok.Type ~= "RPAREN" then
			table.insert(args, parseExpr())

			while peek() and (peek() :: Token).Type == "COMMA" do
				advance() -- consume comma
				table.insert(args, parseExpr())
			end
		end

		return args
	end

	parseExpr = function(): ASTNode
		local tok = peek()

		if not tok then
			Errors.Throw("ParseError", "Unexpected end of input while parsing expression", nil, source)
		end

		local token = tok :: Token

		if token.Type == "NUMBER" then
			advance()
			return self:CreateNode("Number", token.Value)
		end

		if token.Type == "STRING" then
			advance()
			return self:CreateNode("String", token.Value)
		end

		if token.Type == "BOOLEAN" then
			advance()
			return self:CreateNode("Boolean", token.Value)
		end

		if token.Type == "IDENT" then
			advance()
			local name = token.Value :: string
			local upperName = string.upper(name)

			expect("LPAREN")
			local args = parseArgs()
			expect("RPAREN")

			if upperName == "VAR" then
				if #args ~= 1 then
					Errors.Throw(
						"ParseError",
						("VAR() expects exactly 1 argument, got %d"):format(#args),
						token.Position,
						source
					)
				end
				return self:CreateNode("Var", name, args)
			end

			if upperName == "IF" then
				if #args ~= 3 then
					Errors.Throw(
						"ParseError",
						("IF() expects exactly 3 arguments (condition, then, else), got %d"):format(#args),
						token.Position,
						source
					)
				end
				return self:CreateNode("If", name, args)
			end

			if upperName == "AND" or upperName == "OR" then
				if #args < 2 then
					Errors.Throw(
						"ParseError",
						("%s() expects at least 2 arguments, got %d"):format(upperName, #args),
						token.Position,
						source
					)
				end
				return self:CreateNode(if upperName == "AND" then "And" else "Or", name, args)
			end

			if upperName == "NOT" then
				if #args ~= 1 then
					Errors.Throw(
						"ParseError",
						("NOT() expects exactly 1 argument, got %d"):format(#args),
						token.Position,
						source
					)
				end
				return self:CreateNode("Not", name, args)
			end

			return self:CreateNode("Call", name, args)
		end

		Errors.Throw(
			"ParseError",
			("Unexpected token '%s' (%s)"):format(tostring(token.Value), token.Type),
			token.Position,
			source
		)
		return {} :: ASTNode
	end

	local ast = parseExpr()

	if pos <= len then
		local trailing = tokens[pos]
		Errors.Throw(
			"ParseError",
			("Unexpected trailing token '%s' (%s)"):format(tostring(trailing.Value), trailing.Type),
			trailing.Position,
			source
		)
	end

	return ast
end

--==================================================
-- Execute (AST walked directly with a variables table)
--==================================================

function ASM.Execute(self: self, ast: ASTNode, variables: Variables): any
	local nodeType = ast.Type

	if nodeType == "Number" then
		return ast.Value
	end

	if nodeType == "String" then
		return ast.Value
	end

	if nodeType == "Boolean" then
		return ast.Value
	end

	if nodeType == "Var" then
		-- VAR(name) -> the single child resolves to the variable's name
		local nameNode = ast.Children[1]
		if not nameNode then
			Errors.Throw("ExecuteError", "VAR() requires exactly one argument (the variable name)")
		end

		local varName: string
		if nameNode.Type == "String" then
			varName = nameNode.Value
		elseif nameNode.Type == "Call" or nameNode.Type == "Var" then
			-- support VAR(SOMEFUNC(...)) resolving to a name dynamically
			varName = self:Execute(nameNode, variables)
		else
			Errors.Throw("ExecuteError", "VAR() argument must resolve to a variable name (string)")
		end

		local value = variables[varName]
		if value == nil then
			Errors.Throw("ExecuteError", ("Unknown variable '%s'"):format(tostring(varName)))
		end

		return value
	end

	if nodeType == "If" then
		-- IF(condition, thenBranch, elseBranch) - only the taken branch is evaluated.
		local condition = self:Execute(ast.Children[1], variables)

		if condition then
			return self:Execute(ast.Children[2], variables)
		else
			return self:Execute(ast.Children[3], variables)
		end
	end

	if nodeType == "And" then
		-- AND(a, b, ...) - short-circuits on the first falsy value.
		local result: any = true
		for _, childNode in ast.Children do
			result = self:Execute(childNode, variables)
			if not result then
				return false
			end
		end
		return true
	end

	if nodeType == "Or" then
		-- OR(a, b, ...) - short-circuits on the first truthy value.
		for _, childNode in ast.Children do
			if self:Execute(childNode, variables) then
				return true
			end
		end
		return false
	end

	if nodeType == "Not" then
		return not self:Execute(ast.Children[1], variables)
	end

	if nodeType == "Call" then
		local fn = self:GetFunction(ast.Value)
		if not fn then
			Errors.Throw("ExecuteError", ("Unknown function '%s'"):format(tostring(ast.Value)))
		end

		local args = table.create(#ast.Children)
		for index, childNode in ast.Children do
			args[index] = self:Execute(childNode, variables)
		end

		local ok, result = pcall(fn :: (...any) -> any, table.unpack(args))
		if not ok then
			Errors.Throw(
				"ExecuteError",
				("Error while calling '%s': %s"):format(tostring(ast.Value), tostring(result))
			)
		end

		return result
	end

	Errors.Throw("ExecuteError", ("Unknown AST node type '%s'"):format(tostring(nodeType)))
	return
end

--==================================================
-- Compile (AST -> reusable callable function)
--==================================================

function ASM.Compile(self: self, ast: ASTNode): CompiledFn
	return function(variables: Variables?): any
		return self:Execute(ast, variables or {})
	end
end

--==================================================
-- High Level API
--==================================================

-- Runs the full pipeline and returns either (true, result) or (false, ASMError).
-- Prefer this over :Eval() when you don't want errors to propagate via `error()`.
function ASM.TryEval(self: self, source: string, variables: Variables?): (boolean, any)
	local ok, result = pcall(function()
		local tokens = self:Lex(source)
		local ast = self:Parse(tokens, source)
		return self:Execute(ast, variables or {})
	end)

	return ok, result
end

function ASM.Eval(self: self, source: string, variables: Variables?): any
	local tokens = self:Lex(source)
	local ast = self:Parse(tokens, source)

	return self:Execute(ast, variables or {})
end

function ASM.Build(self: self, source: string): CompiledFn
	local tokens = self:Lex(source)
	local ast = self:Parse(tokens, source)

	return self:Compile(ast)
end

--==================================================
-- Instance
--==================================================

local instance: self = setmetatable({
	Functions = {},
}, ASM) :: self

--==================================================
-- Built-in Functions
--==================================================

instance:Register("ADD", function(a: number, b: number)
	return a + b
end)

instance:Register("SUB", function(a: number, b: number)
	return a - b
end)

instance:Register("MUL", function(a: number, b: number)
	return a * b
end)

instance:Register("DIV", function(a: number, b: number)
	if b == 0 then
		BuiltError.DivByZero()
	end
	return a / b
end)

instance:Register("POW", function(a: number, b: number)
	return a ^ b
end)

instance:Register("FLOORDIV", function(a:number, b:number)
	if b == 0 then
		BuiltError.DivByZero()
	end

	return a // b
end)

instance:Register("MIN", math.min)
instance:Register("MAX", math.max)
instance:Register("ABS", math.abs)

instance:Register("CONCAT", function(...: any)
	local parts = { ... }
	local strs = table.create(#parts)
	for i, v in parts do
		strs[i] = tostring(v)
	end
	return table.concat(strs)
end)

--==================================================
-- Comparison built-ins
--==================================================
--[[ 
	NOTE: IF / AND / OR / NOT are NOT registered here - they are handled as special AST nodes in Execute() 
	for short-circuit / lazy evaluation
	(so IF(cond, EXPENSIVE(), 0) doesn't run EXPENSIVE() when cond is false).
]]
	
instance:Register("EQ", function(a: any, b: any)
	return a == b
end)

instance:Register("NEQ", function(a: any, b: any)
	return a ~= b
end)

instance:Register("LT", function(a: number, b: number)
	return a < b
end)

instance:Register("GT", function(a: number, b: number)
	return a > b
end)

instance:Register("LTE", function(a: number, b: number)
	return a <= b
end)

instance:Register("GTE", function(a: number, b: number)
	return a >= b
end)

return instance
