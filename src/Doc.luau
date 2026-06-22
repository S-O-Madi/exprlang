--[[

	* DOCUMENTATION *
	
	ASM.RegisterFunction(name: string, fn: (...any) -> any)
		Registers a function to be called by the ADD/VAR/MUL/... tokens.
		Function will be called with the current scope (see below) and the
		list of parsed arguments.
		
		For example, to implement a function that returns its arguments
		as a table:
			ASM.RegisterFunction("list", function(scope, ...)
				return table.pack(...)
			end)
		
	ASM.RegisterIdentifier(name: string, value: any)
		Registers an identifier to be used in the scope of the variables.
		This is useful for adding utility functions to the scope of the
		expression without polluting the global scope.
		
		For example, to add a function that returns the current time:
			ASM.RegisterIdentifier("now", function()
				return os.time()
			end)
	
	* BASE FUNCTIONS *
	
	- Arithmetic operators:
		ADD(A, B): return A + B
		MIN(A, B): return A - B
		MUL(A, B): return A * B
		DIV(A, B): return A / B
		POW(A, B): return A ^ B
		FLOORDIV(A, B): return A // B
		MOD(A, B): return A % B
		NEG(A): return -A
	
	- Comparison operators:
		EQ(A, B): return A == B
		NEQ(A, B): return A ~= B
		LT(A, B): return A < B
		LTE(A, B): return A <= B
		GT(A, B): return A > B
		GTE(A, B): return A >= B
	
	- Logic operators:
		NOT(A): return not A
		AND(A, B): return A and B
		OR(A, B): return A or B
	
	- Other:
		IF(A, B, C): return B if A = true else returns C
        CONCAT(...): return a string.
]]
