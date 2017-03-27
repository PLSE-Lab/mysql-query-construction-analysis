module QCPAnalysis::ParseSQL::AbstractSyntax

public data SQLQuery = selectQuery(Tables tables)
					 | updateQuery(Tables tables)
					 | insertQuery(Tables tables)
					 | deleteQuery(Tables tables)
					 | unknownQuery()// logic to translate this query into rascal is not yet implemented 
					 | parseError();// query did not parse

public data Tables = table(str tablename)
				   | tables(set[str] tablenames);