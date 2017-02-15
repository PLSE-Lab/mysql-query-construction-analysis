module QCPAnalysis::MixedQuery::ConcreteSyntax

extend lang::std::Layout;

// putting the dot here should probably not happen...
// right now it is just a quick fix to handle identifiers like row.column
lexical Word = [a-zA-Z0-9_.$]*;

lexical String = "\"" Word "\""
			   | "\'" Word "\'";

lexical Number = "-"?[0-9]+
			   | Number"."Number
			   | Number"E"Number;
			   
lexical Hex = "x\'"[a-fA-F0-9]+"\'"
			| "X\'"[a-fA-F0-9]+"\'"
			| "0x\'"[a-fA-F0-9]+"\'";

lexical Bit = "b\'"[0-1]+"\'"
			| "B\'"[0-1]+"\'"
			| "0b\'"[0-1]+"\'";

lexical Boolean = "TRUE" | "true" | "FALSE" | "false";

lexical Null = "NULL" | "null" | "\\N";

lexical ComparisonOperator = "=" | "\>=" | "\>" | "\<=" | "\<" | "\<\>" | "!=";

lexical ParamMarker = "?";

lexical Variable = "@"Word;

lexical QueryHole =  "Ø";

// todo: add datetime
syntax Literal = string: String
			   | number: Number
			   | hex: Hex
			   | bit: Bit
			   | boolean: Boolean
			   | null: Null
			   | literalHole: QueryHole;

syntax Identifier = identifier: Word
				  | identifier:  "`" Word "`"
				  | identifier: "\"" Word "\""
				  | identifier: "\'" Word "\'"
				  | identifierHole : QueryHole;

syntax SelectExpr = columnName: Identifier 
				  | wildcard: "*";
			  
syntax Expr = orExpr: Expr 'OR' Expr
			| orExpr: Expr "||" Expr
			| xorExpr: Expr 'XOR' Expr
			| andExpr: Expr 'AND' Expr
			| andExpr: Expr "&&" Expr
			| notExpr: 'NOT' Expr
			| notEpxr: "!" Expr
			| booleanWithExpectedValue: BooleanPrimary 'IS' 'NOT'? ('TRUE' | 'FALSE' | 'UNKNOWN')
			| boolean: BooleanPrimary;

syntax BooleanPrimary = booleanNullTest: BooleanPrimary 'IS' 'NOT'? 'NULL'
					  | spaceship: BooleanPrimary "\<=\>" Predicate
					  | comparison: BooleanPrimary ComparisonOperator Predicate
					  | comparisonWithSubQuery: BooleanPrimary ComparisonOperator ('ALL' | 'ANY') SubQuery
					  | predicate: Predicate;

syntax Predicate = bitExprSubQuery: BitExpr 'NOT'? 'IN' SubQuery
				 | bitExprList: BitExpr 'NOT'? 'IN' "(" Expr {"," Expr}* ")"
				 | bitExprBetween: BitExpr 'NOT'? 'BETWEEN' BitExpr 'AND' Predicate
				 | bitExprSoundsLike: BitExpr 'SOUNDS LIKE' BitExpr
				 | bitExprLike: BitExpr 'NOT'? 'LIKE' SimpleExpr ('ESCAPE' SimpleExpr)?
				 | bitExprRegex: BitExpr 'NOT'? 'REGEXP' BitExpr
				 | bitExpr: BitExpr;

syntax BitExpr = bitwiseOr: BitExpr "|" BitExpr
			   | bitwiseAnd: BitExpr "&" BitExpr
			   | bitwoiseXor: BitExpr "^" BitExpr
			   | bitShiftLeft: BitExpr "\<\<" BitExpr	
			   | bitShiftRight: BitExpr "\>\>" BitExpr
			   | addition: BitExpr "+" BitExpr
			   | subtraction: BitExpr "-" BitExpr
			   | multiplication: BitExpr "*" BitExpr
			   | division: BitExpr "/" BitExpr
			   | intDivision: BitExpr 'DIV' BitExpr
			   | modulus: BitExpr 'MOD' BitExpr
			   | modulus: BitExpr "%" BitExpr
			   //| BitExpr "+" IntervalExpr
			   //| BitExpr "-" IntervalExpr
			   | SimpleExpr;
			   
syntax SimpleExpr = lit: Literal
				  | id: Identifier
				  //| FunctionCall
				  | collation: SimpleExpr 'COLLATE' Word
				  | paramMarker: ParamMarker
				  | var: Variable
				  | logicalOr: SimpleExpr "||" SimpleExpr
				  | positive: "+" SimpleExpr
				  | negative: "-" SimpleExpr
				  | logicalNegation: "~" SimpleExpr
				  | negation: "!" SimpleExpr
				  | binary: 'BINARY' SimpleExpr
				  | exprList: "(" {Expr ","}* ")"
				  | rowExpr: 'ROW' "(" Expr "," {Expr ","}* ")"
				  | subQuery: 'EXISTS'? SubQuery 
				  | curlyBraces: "{" Identifier Expr "}";
				  //| MatchExpr
				  //| CaseExpr
				  //| IntervalExpr
	  
start syntax SQLQuery = selectQuery:SelectQuery
				   	  | InsertQuery;
				   //| UpdateQuery
				   //| DeleteQuery;
				   
syntax SelectQuery = select: 'SELECT' ('ALL' | 'DISTINCT' | 'DISTINCTROW')?
									'HIGH_PRIORITY'?
									('MAX_STATEMENT_TIME =' Number)?
									'STRAIGHT_JOIN'?
									'SQL_SMALL_RESULT'? 'SQL_BIG_RESULT'? 'SQL_BUFFER_RESULT'?
									('SQL_CACHE' | 'SQL_NO_CACHE')? 'SQL_CALC_FOUND_ROWS'?
									{SelectExpr ","}*
									('FROM' TableReferences ('PARTITION' {Identifier ","}+)?)?
									('WHERE' Expr)?
									('GROUP BY' {(Identifier | Expr | Number) ('ASC' | 'DESC')?}+ 'WITH ROLLUP'?)?//HERE
									('HAVING' Expr)?
									('ORDER BY' {(Identifier | Expr | Number) ('ASC' | 'DESC')?}+)?
									('LIMIT' (Number | (Number 'OFFSET' Number)))?;
									//add rest of defininition from MySQL grammar (PROCEDURE, INTO, etc.)
	
syntax InsertQuery = insertValues: "INSERT" ("LOW_PRIORITY" | "DELAYED" | "HIGH_PRIORITY")? "IGNORE"?
								 	"INTO"? Identifier
								 	("PARTITION" {Identifier ","}+)?
								 	("(" {Identifier ","}+ ")")?
								 	(("VALUES" | "VALUE" ) "("{(Expr | "DEFAULT") ","}+ ")")
								 	("ON DUPLICATE KEY UPDATE" {(Identifier "=" Expr) ","}+)?
								 			 		
				   | insertSet: "INSERT" ("LOW_PRIORITY" | "DELAYED" | "HIGH_PRIORITY")? "IGNORE"?
								 "INTO"? Identifier
								 ("PARTITION" {Identifier ","}+)?
								 "SET" {(Identifier "=" (Expr | "DEFAULT")) ","}+
								 ("ON DUPLICATE KEY UPDATE" {(Identifier "=" Expr) ","}+)?;
								 
				   //| insertSelect: To be implemented
				   
syntax SubQuery = subQuery:"(" SelectQuery ")";

	
syntax TableReferences = tableReferences: EscapedTableReference {"," EscapedTableReference}*;

syntax EscapedTableReference = escaped: TableReference
							 | escaped: "{" 'OJ' TableReference "}";
							 
syntax TableReference = tableFactor: TableFactor
					  | joinTable: JoinTable;
				  
syntax TableFactor = tableFactorPartition: Identifier ('PARTITION' {Identifier ","}+)?
					 	('AS'? Identifier)? {IndexHint ","}*
					| tableFactorSubQuery: SubQuery 'AS'? Identifier
					| tableFactorReferences: "(" TableReferences ")";

//TODO: meaningful names					
syntax JoinTable = join1:TableReference ('INNER' | 'CROSS') 'JOIN' TableFactor JoinCondition?
		         | join2:TableReference 'STRAIGHT_JOIN' TableFactor JoinCondition?
		         | join3:TableReference ('LEFT' | 'RIGHT') 'OUTER'? 'JOIN' TableReferences JoinCondition
		         | join4:TableReference 'NATURAL' (('LEFT' | 'RIGHT') 'OUTER'?)? 'JOIN' TableFactor;
		         
syntax JoinCondition = joinConditionOn:'ON' Expr
					 | joinConditionUsing:'USING' "(" {Identifier ","}+ ")";
					 

syntax IndexHint = hint:'USE' ('INDEX' | 'KEY') ('FOR' ('JOIN' | 'ORDER BY' | 'GROUP BY'))? "("{Identifier ","}+")"
				 | hint:'IGNORE' ('INDEX' | 'KEY') ('FOR' ('JOIN' | 'ORDER BY' | 'GROUP BY'))? "("{Identifier ","}+")"
				 | hint:'FORCE' ('INDEX' | 'KEY') ('FOR' ('JOIN' | 'ORDER BY' | 'GROUP BY'))? "("{Identifier ","}+")";
	
	
	
				   
				  
				 


					  