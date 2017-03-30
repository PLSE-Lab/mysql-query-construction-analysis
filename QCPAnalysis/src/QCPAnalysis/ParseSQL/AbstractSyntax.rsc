module QCPAnalysis::ParseSQL::AbstractSyntax

public data SQLQuery = selectQuery(list[Exp] selectExpressions, list[Exp] from, GroupBy group, OrderBy order)
					 | updateQuery(list[Exp] tables, OrderBy order)
					 | insertQuery(list[Exp] into)
					 | deleteQuery(list[Exp] from, OrderBy order)
					 | unknownQuery()// logic to translate this query into rascal is not yet implemented 
					 | parseError();// query did not parse

public data Exp = name(SQLName name)
				| star()
				| unknownExpression();
				
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
					