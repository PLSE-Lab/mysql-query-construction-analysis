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

keyword MYSQLKeywords 
	= 'AS'
	| 'SELECT'
	| 'FROM'
	| 'PARTITION'
	| 'USE'
	| 'IGNORE'
	| 'FORCE'
	| 'INDEX'
	| 'KEY'
	| 'FOR'
	| 'JOIN'
	;

// todo: add datetime
syntax Literal = string: String
			   | number: Number
			   | hex: Hex
			   | bit: Bit
			   | boolean: Boolean
			   | null: Null
			   | literalHole: QueryHole;

syntax Identifier = identifier: Word \ RascalKeywords
				  | identifier:  "`" Word "`"
				  | identifier: "\"" Word "\""
				  | identifier: "\'" Word "\'"
				  | identifierHole : QueryHole;

syntax SelectExpr = columnName: Identifier name 
				  | wildcard: "*"
				  | aliased: Identifier name 'AS' Identifier aliasName
				  ;
			  
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

lexical DMLModifier 
	= 'ALL' 
	| 'DISTINCT' 
	| 'DISTINCTROW' 
	| 'HIGH_PRIORITY' 
	| 'STRAIGHT_JOIN' 
	| 'SQL_SMALL_RESULT' 
	| 'SQL_BIG_RESULT'
	| 'SQL_BUFFER_RESULT'
	| 'SQL_CACHE'
	| 'SQL_NO_CACHE'
	| 'SQL_CALC_FOUND_ROWS'
	;
	
// TODO: Need support for MAX_STATEMENT_TIME

syntax SelectExprs = selectExprs: {SelectExpr ","}* exprs;
 			   
syntax FromClause 
	= basicFromClause: 'FROM' TableReferences
	| fromClauseWithPartition: 'FROM' TableReferences 'PARTITION' {Identifier ","}+ identifiers
	| emptyFromClause:
	;
	
syntax WhereClause
	= whereClause: 'WHERE' Expr whereExpr
	| emptyWhereClause:
	;
	
syntax SelectQuery = select: 'SELECT' DMLModifier* modifiers SelectExprs FromClause WhereClause;									
									//('GROUP BY' {(Identifier | Expr | Number) ('ASC' | 'DESC')?}+ 'WITH ROLLUP'?)?//HERE
									//('HAVING' Expr)?
									//('ORDER BY' {(Identifier | Expr | Number) ('ASC' | 'DESC')?}+)?
									//('LIMIT' (Number | (Number 'OFFSET' Number)))?
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

	
syntax TableReferences 
	= tableReferences: { EscapedTableReference ","}+ tableReferences;

syntax EscapedTableReference 
	= normalReference: TableReference
	| escapedReference: "{" 'OJ' TableReference "}"
	;
							 
syntax TableReference 
	= tableFactor: TableFactor
	| joinTable: JoinTable
	;

syntax TableFactorPartition
	= tableFactorPartion: 'PARTITION' {Identifier ","}+ partitionNames
	| noPartition:
	;
	
syntax TableFactorAlias
	= tableFactorAlias: 'AS' Identifier identifier
	| noAlias:
	;
	
//syntax IndexHintList
//	= indexHintList: { IndexHint "," }* hints
//	| noIndexHints:
//	;
	
syntax TableFactor = tableFactorPartition: Identifier tableName TableFactorPartition TableFactorAlias //IndexHintList
					| tableFactorSubQuery: SubQuery 'AS' Identifier
					| tableFactorReferences: "(" TableReferences ")";

//TODO: meaningful names					
syntax JoinTable 
	= innerJoin: TableReference ('INNER' | 'CROSS') 'JOIN' TableFactor JoinCondition?
	| straightJoin: TableReference 'STRAIGHT_JOIN' TableFactor JoinCondition?
	| outerJoin: TableReference ('LEFT' | 'RIGHT') 'OUTER'? 'JOIN' TableReferences JoinCondition
	| outerJoinNoCondition: TableReference 'NATURAL' (('LEFT' | 'RIGHT') 'OUTER'?)? 'JOIN' TableFactor
	;
		         
syntax JoinCondition = joinConditionOn:'ON' Expr
					 | joinConditionUsing:'USING' "(" {Identifier ","}+ ")";
					 

//syntax IndexHint = hint:'USE' ('INDEX' | 'KEY') ('FOR' ('JOIN' | 'ORDER BY' | 'GROUP BY'))? "("{Identifier ","}+")"
//				 | hint:'IGNORE' ('INDEX' | 'KEY') ('FOR' ('JOIN' | 'ORDER BY' | 'GROUP BY'))? "("{Identifier ","}+")"
//				 | hint:'FORCE' ('INDEX' | 'KEY') ('FOR' ('JOIN' | 'ORDER BY' | 'GROUP BY'))? "("{Identifier ","}+")";
	
	
	
				   
				  
				 


					  