module QCPAnalysis::MixedQuery::AbstractSyntax

public data Literal = string(str strVal)
				    | number(str numVal)
				    | hex(str hexVal)
				    | bit(str bitVal)
				    | boolean(str boolVal)
				    | null(str nullVal)
				    | literalHole();


public data Identifier = identifier(str identifierVal)
					   | identifierHole();

public data SelectExpr = columnName(str columnname)
					   | wildcard();
					   
public data Expr = orExpr(Expr left, Expr right)
				 | xorExpr(Expr ledft, Expr right)
			     | andExpr(Expr left, Expr right)
			     | notExpr(Expr negated)
			     | booleanWithExpectedValue(BooleanPrimary boolean, bool optionalNot, str expected)
			     | boolean(BooleanPrimary bp);

public data BooleanPrimary = booleanNullTest(BooleanPrimary boolean, bool optionalNot)
						   | spaceship(BooleanPrimary left, Predicate right)
						   | comparison(BooleanPrimary left, str operator, Predicate right)
						   | comparisonWithSubQuery(BooleanPrimary left, str operator, SubQuery sub)
						   | predicate(Predicate pred);
						   
public data Predicate = bitExprSubQuery(BitExpr left, bool optionalNot, SubQuery sub)
					  | bitExprList(BitExpr left, bool optionalNot, Expr head, list[Expr] tail)
					  | bitExprBetween(BitExpr left, bool optionalNot, BitExpr bounds1, Predicate bounds2)
					  | bitExprSoundsLike(BitExpr left, BitExpr bitight)
					  | bitExprLike(BitExpr left, bool optionalNot, SimpleExpr simpleRight, list[SimpleExpr] optionalEscape)//list is empty if no escape provided
					  | bitExprRegex(BitExpr left, bool optionalNot, BitExpr bitRight)
					  | bitExpr(BitExpr expr);
					  
public data BitExpr = bitwiseOr(BitExpr left, BitExpr right)
					| bitwiseAnd(BitExpr left, BitExpr right)
					| bitwiseXor(BitExpr left, BitExpr right)
					| bitShiftLeft(BitExpr left, BitExpr right)
					| bitShiftRight(BitExpr left, BitExpr right)
					| addition(BitExpr left, BitExpr right)
					| subtraction(BitExpr left, BitExpr right)
					| multiplication(BitExpr left, BitExpr right)
					| division(BitExpr left, BitExpr right)
					| intDivision(BitExpr left, BitExpr right)
					| modulus(BitExpr left, BitExpr right)
					| simpleExpr(SimpleExpr expr);

public data SimpleExpr = lit(Literal literalVal)
					   | id(Identifier identifier)
					   | collation(SimpleExpr left, str word)
					   | paramMarker()
					   | var(str sqlvar)
					   | logicalOr(SimpleExpr left, SimpleExpr right)
					   | positive(SimpleExpr simple)
					   | negative(SimpleExpr sunple)
					   | logicalNegation(SimpleExpr simple)
					   | negation(SimpleExpr simple)
					   | binary(SimpleExpr simple)
					   | exprList(list[Expr] exprs)
					   | rowExpr(list[Expr] exprs)
					   | subQuery(bool optionalExists, SubQuery sub)
					   | curlyBraces(Identifier id, Expr expr);

public data SubQuery = subQuery(SelectQuery query);

public data SQLQuery = selectQuery(SelectQuery query)
					 | error(); //constructor for queries that could not parse
					 
public data SelectQuery = select(
	list[str] optionalSelectType, bool highPriority, list[Literal] optionalMaxStatementSize, bool optionalStraightJoin,
	bool smallResult, bool bigResult, bool bufferResult, list[str] optionalCaching, bool optionalFoundRows,
	list[SelectExpr] columns, list[tuple[TableReferences references, list[Identifier] optionalPartition]] from,
	list[Expr] where
	//list[str] groupBy,//Needs to be updated to not implode into string
	//list[Expr] having,
	//list[str] orderBy,//Needs to be updated to not implode into string
	//list[str] limit //Needs to be updated to not implode into string
);

public data TableReferences = tableReferences(EscapedTableReference head, list[EscapedTableReference] tail);

public data EscapedTableReference = escaped(TableReference reference);

public data TableReference = tableFactor(TableFactor factor)
						   | joinTable(JoinTable jt);

public data TableFactor = tableFactorPartition(Identifier firstId, list[list[Identifier]] idList, list[Identifier] optionalAs, list[IndexHint] optionalHints)
						| tableFactorSubQuery(SubQuery subquery, bool includedAsKeyword, Identifier id)
						| tableFactorReferences(TableReferences references);
						
public data JoinTable = join1(TableReference reference, str keywords, TableFactor factor, list[JoinCondition] optionalJoinCondition)
					  | join2(TableReference reference, str keywords, TableFactor factor, list[JoinCondition] optionalJoinCondition)
					  | join3(TableReference reference, str keywords, TableReferences references, JoinCondition joinCondition)
					  | join4(TableReference reference, str keywords, TableFactor factor);
					  
public data JoinCondition = joinConditionOn(Expr expr)
						  | joinConditionUsing(list[Identifier] ids);
						  
public data IndexHint = hint(str keywords, list[Identifier] ids);
					