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
			     | booleanWithExpectedValue(BooleanPrimary boolean, bool includedNot, str expected)
			     | boolean(BooleanPrimary bp);

public data BooleanPrimary = booleanNullTest(BooleanPrimary boolean, bool includedNot)
						   | spaceship(BooleanPrimary left, Predicate right)
						   | comparison(BooleanPrimary left, str operator, Predicate right)
						   | comparisonWithSubQuery(BooleanPrimary left, str operator, SubQuery sub)
						   | predicate(Predicate pred);
						   
public data Predicate = bitExprSubQuery(BitExpr left, bool includedNot, SubQuery sub)
					  | bitExprList(BitExpr left, bool includedNot, Expr head, list[Expr] tail)
					  | bitExprBetween(BitExpr left, bool includedNot, BitExpr bounds1, Predicate bounds2)
					  | bitExprSoundsLike(BitExpr left, BitExpr right)
					  | bitExprLike(BitExpr left, bool includedNot, SimpleExpr right, list[SimpleExpr] optionalEscape)//list is empty if no escape provided
					  | bitExprRegex(BitExpr left, bool includedNot, BitExpr right)
					  | bitExpr(bitExpr expr);
					  
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
					   | positive(SimpleExpr expr)
					   | negative(SimpleExpr expr)
					   | logicalNegation(SimpleExpr expr)
					   | negation(SimpleExpr expr)
					   | binary(SimpleExpr expr)
					   | exprList(Expr head, list[Expr] tail)
					   | rowExpr(list[Expr] exprs)
					   | subQuery(bool includedExists, Subquery sub)
					   | curlyBraces(Identifier id, Expr expr);

public data SubQuery = subQuery(SelectQuery query);

public data SelectQuery = selectQuery();


		 			