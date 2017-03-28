module QCPAnalysis::ParseSQL::AbstractSyntax

public data SQLQuery = selectQuery(list[Exp] selectExpressions, list[Exp] from)
					 | updateQuery(list[Exp] tables)
					 | insertQuery(Exp into)
					 | deleteQuery(list[Exp] from)
					 | unknownQuery()// logic to translate this query into rascal is not yet implemented 
					 | parseError();// query did not parse

public data Exp = column(str columnName)
				| table(str tableName)
				| database(str dbName)
				| unknownExpression();