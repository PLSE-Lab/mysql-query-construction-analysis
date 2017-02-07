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
				  | identifiedHole : QueryHole;

syntax SelectExpr = columnName: Identifier 
				  | wildcard: "*";
			  
syntax Expr = orExpr: Expr "OR" Expr
			| orExpr: Expr "||" Expr
			| xorExpr: Expr "XOR" Expr
			| andExpr: Expr "AND" Expr
			| andExpr: Expr "&&" Expr
			| notExpr: "NOT" Expr
			| notExpr: "!" Expr
			| booleanExprWithExpected: BooleanPrimary "IS" "NOT"? ("TRUE" | "FALSE" | "UNKNOWN")
			| booleanExpr: BooleanPrimary;

syntax BooleanPrimary = nullTest: BooleanPrimary "IS" "NOT"? "NULL"
					  | spaceShip: BooleanPrimary "\<=\>" Predicate
					  | comparison: BooleanPrimary ComparisonOperator Predicate
					  | comparisonWithSubQuery: BooleanPrimary ComparisonOperator ("ALL" | "ANY") SubQuery
					  | predicate: Predicate;

syntax Predicate = predSubQuery: BitExpr "NOT"? "IN" SubQuery
				 | predExprList: BitExpr "NOT"? "IN" "(" Expr {"," Expr}* ")"
				 | predBetween: BitExpr "NOT"? "BETWEEN" BitExpr "AND" Predicate
				 | predSoundsLike: BitExpr "SOUNDS LIKE" BitExpr
				 | predLike: BitExpr "NOT"? "LIKE" SimpleExpr ("ESCAPE" SimpleExpr)?
				 | predRegex: BitExpr "NOT"? "REGEXP" BitExpr
				 | bitExpr: BitExpr;

syntax BitExpr = bitOr: BitExpr "|" BitExpr
			   | bitAnd: BitExpr "&" BitExpr
			   | bitXor: BitExpr "^" BitExpr
			   | bitShiftLeft: BitExpr "\<\<" BitExpr	
			   | bitShiftRight: BitExpr "\>\>" BitExpr
			   | addition: BitExpr "+" BitExpr
			   | subtraction: BitExpr "-" BitExpr
			   | multiplication: BitExpr "*" BitExpr
			   | division: BitExpr "/" BitExpr
			   | intDivision: BitExpr "DIV" BitExpr
			   | modulo: BitExpr "MOD" BitExpr
			   | modulo: BitExpr "%" BitExpr
			   //| BitExpr "+" IntervalExpr
			   //| BitExpr "-" IntervalExpr
			   | SimpleExpr;
			   
syntax SimpleExpr = Literal
				  | Identifier
				  //| FunctionCall
				  | SimpleExpr "COLLATE" Word
				  | ParamMarker
				  | Variable
				  | SimpleExpr "||" SimpleExpr
				  | "+" SimpleExpr
				  | "-" SimpleExpr
				  | "~" SimpleExpr
				  | "!" SimpleExpr
				  | "BINARY" SimpleExpr
				  | "(" Expr {"," Expr}* ")"
				  | "ROW" "(" Expr "," Expr {"," Expr}* ")"
				  |  SubQuery 
				  | "EXISTS"  SubQuery 
				  | "{" Identifier Expr "}";
				  //| MatchExpr
				  //| CaseExpr
				  //| IntervalExpr
				  
start syntax SQLQuery = SelectQuery;
				   //| InsertQuery
				   //| UpdateQuery
				   //| DeleteQuery;
				   
syntax SelectQuery =
	"SELECT" ("ALL" | "DISTINCT" | "DISTINCTROW")?
	"HIGH_PRIORITY"?
	("MAX_STATEMENT_TIME =" Number)?
	"STRAIGHT_JOIN"?
	"SQL_SMALL_RESULT"? "SQL_BIG_RESULT"? "SQL_BUFFER_RESULT"?
	("SQL_CACHE" | "SQL_NO_CACHE")? "SQL_CALC_FOUND_ROWS"?
	SelectExpr {"," SelectExpr}*
	("FROM" TableReferences ("PARTITION" PartitionList)?)?//PartitionList needs to be defined
	("WHERE" Expr)?
	("GROUP BY" {(Identifier | Expr | Number) ("ASC" | "DESC")?}+ "WITH ROLLUP"?)?
	("HAVING" Expr)?
	("ORDER BY" {(Identifier | Expr | Number) ("ASC" | "DESC")?}+)?
	("LIMIT" (Number | (Number "OFFSET" Number)))?;
	//add rest of defininition from MySQL grammar (PROCEDURE, INTO, etc.)

syntax SubQuery = "(" SelectQuery ")";
	
syntax TableReferences = EscapedTableReference {"," EscapedTableReference}*;

syntax EscapedTableReference = TableReference
							 | "{" "OJ" TableReference "}";
							 
syntax TableReference = TableFactor
					  | JoinTable;
					  
syntax TableFactor = Identifier ("PARTITION" Identifier {"," Identifier}*)?
					 	("AS"? Identifier)? IndexHintList?
					| SubQuery "AS"? Identifier
					| "(" TableReferences ")";
					
syntax JoinTable = TableReference ("INNER" | "CROSS") "JOIN" TableFactor JoinCondition?
		         | TableReference "STRAIGHT_JOIN" TableFactor ("ON" Expr)?
		         | TableReference ("LEFT" | "RIGHT") "OUTER"? "JOIN" TableReferences JoinCondition
		         | TableReference "NATURAL" (("LEFT" | "RIGHT") "OUTER"?)? "JOIN" TableFactor;
		         
syntax JoinCondition = "ON" Expr
					 | "USING" "(" Identifier {"," Identifier}* ")";
					 
syntax IndexHintList = IndexHint {"," IndexHint}*;

syntax IndexHint = "USE" ("INDEX" | "KEY") ("FOR" ("JOIN" | "ORDER BY" | "GROUP BY"))? "("IndexList")"
				 | "IGNORE" ("INDEX" | "KEY") ("FOR" ("JOIN" | "ORDER BY" | "GROUP BY"))? "("IndexList")"
				 | "FORCE" ("INDEX" | "KEY") ("FOR" ("JOIN" | "ORDER BY" | "GROUP BY"))? "("IndexList")";
				 
syntax Index_list = Identifier {"," Identifier}*;
	
	
	
				   
				  
				 


					  