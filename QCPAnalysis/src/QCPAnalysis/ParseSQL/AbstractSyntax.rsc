module QCPAnalysis::ParseSQL::AbstractSyntax

public data SQLQuery = selectQuery(list[Exp] selectExpressions, list[Exp] from)
					 | updateQuery(list[Exp] tables)
					 | insertQuery(list[Exp] into)
					 | deleteQuery(list[Exp] from)
					 | unknownQuery()// logic to translate this query into rascal is not yet implemented 
					 | parseError();// query did not parse

public data Exp = name(SQLName name)
				| unknownExpression();
				
public data SQLName = column(str column)
					| table(str table)
					| database(str database)
					| tableColumn(str table, str column)
					| databaseTable(str database, str column)
					| databaseTableColumn(str database, str table, str column);