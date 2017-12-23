module QCPAnalysis::ParseSQL::RunSQLParser

import QCPAnalysis::ParseSQL::AbstractSyntax;

import lang::php::util::Utils;
import lang::php::util::Config;

import ValueIO;
import IO;

@doc{The base install location for the sql parser}
public loc sqlParserLoc = |file:///Users/mhills/PHPAnalysis/sql-parser/src/Rascal|;

public SQLQuery runParser(str query){
	println("Now parsing <query>\n");
	sqlParserFile = (sqlParserLoc + "SQL2Rascal.php").path;
	
	args = [sqlParserFile, query];
	phpOut = executePHP(args, sqlParserLoc);
	writeFile(|file:///tmp/parsed.txt|, phpOut);
	return readTextValueString(#SQLQuery, phpOut);
}