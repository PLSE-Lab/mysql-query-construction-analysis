module QCPAnalysis::ParseSQL::RunSQLParser

import QCPAnalysis::ParseSQL::AbstractSyntax;

import lang::php::util::Utils;
import lang::php::util::Config;

import ValueIO;
import IO;

@doc{The base install location for the sql parser}
private loc sqlParserLoc = lang::php::util::Config::baseLoc + "sql-parser/src/Rascal";

public SQLQuery runParser(str query){
	println("Now parsing <query>\n");
	
	absoluteLoc = resolveLocation(sqlParserLoc);
	parserFile = absoluteLoc + "SQL2Rascal.php";
	
	args = [parserFile.path, query];
	phpOut = executePHP(args, absoluteLoc);
	
	return readTextValueString(#SQLQuery, phpOut);
}