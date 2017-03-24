module QCPAnalysis::ParseSQL::AbstractSyntax

public data SQLQuery = selectQuery()
					 | updateQuery()
					 | insertQuery()
					 | deleteQuery()
					 | unknownQuery()// logic to translate this query into rascal is not yet implemented 
					 | parseError();// query did not parse