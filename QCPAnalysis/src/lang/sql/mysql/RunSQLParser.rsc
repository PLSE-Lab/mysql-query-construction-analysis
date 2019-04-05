module lang::sql::mysql::RunSQLParser

import lang::sql::mysql::AbstractSyntax;

import lang::php::util::Utils;
import lang::php::util::Config;

import ValueIO;
import IO;
import String;

@doc{The base install location for the sql parser}
private loc sqlParserLoc = lang::php::util::Config::baseLoc + "sql-parser/src/Rascal";

public SQLQuery runParser(str query){
	if(isEmpty(query)){
		return parseError();
	}
	println("Now parsing <query>\n");
	
	absoluteLoc = resolveLocation(sqlParserLoc);
	parserFile = absoluteLoc + "SQL2Rascal.php";
	
	args = [parserFile.path, query];
	phpOut = executePHP(args, absoluteLoc);
	
	println("Parsed Query: <phpOut>");
	
	return readTextValueString(#SQLQuery, phpOut);
}