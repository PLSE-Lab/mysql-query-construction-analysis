module QCPAnalysis::ParseSQL::AbstractSyntax

import lang::php::ast::AbstractSyntax;

public data SQLQuery = selectQuery(list[Exp] selectExpressions, list[Exp] from, Where where, GroupBy group, Having having, OrderBy order, Limit limit, list[Join] joins)
					 | updateQuery(list[Exp] tables, Where where, OrderBy order, Limit limit)
					 | insertQuery(list[Exp] into)
					 | deleteQuery(list[Exp] from, Where where, OrderBy order, Limit limit)
					 | unknownQuery()// logic to translate this query into rascal is not yet implemented 
					 | parseError();// query did not parse

public data Exp = name(SQLName name)
			    | literal(str literalVal)
			    | call(str functionName)//TODO: function params
				| star()
				| hole(int holeID)
				| unknownExpression()
				| aliased(Exp exp, str theAlias);
				
public data SQLName = column(str column)
					| table(str table)
					| database(str database)
					| tableColumn(str table, str column)
					| databaseTable(str database, str column)
					| databaseTableColumn(str database, str table, str column);

public data OrderBy = orderBy(rel[Exp exp, str mode] orderings)
					| noOrderBy();
					
public data GroupBy = groupBy(rel[Exp exp, str mode] groupings)
					| noGroupBy();
					
public data Where = where(Condition condition)
				  | noWhere();
				 
public data Having = having(Condition condition)
				   | noHaving();
				   
public data Condition = condition(str exp)// TODO: hold more information about conditions rather than just their string representation
					  | and(Condition left, Condition right)
					  | or(Condition left, Condition right)
					  | xor(Condition left, Condition right)
					  | not(Condition condition);

public data Limit = limit(int numRows)
				  | limitWithOffset(int numRows, int offset)
				  | noLimit();

public data Join = simpleJoin(str joinType, Exp joinExp)
				 | joinOn(str joinType, Exp joinExp, Condition on)
				 | joinUsing(str joinType, Exp joinExp, list[str] using);
				  