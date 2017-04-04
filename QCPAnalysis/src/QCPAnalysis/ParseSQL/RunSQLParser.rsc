module QCPAnalysis::ParseSQL::RunSQLParser

import QCPAnalysis::ParseSQL::AbstractSyntax;

import lang::php::util::Utils;
import lang::php::util::Config;

import ValueIO;

public SQLQuery runParser(str query){
	sqlParserLoc = lang::php::util::Config::baseLoc + "sql-parser/src/Rascal";
	
	args = ["SQL2Rascal.php", query];
	phpOut = executePHP(args, sqlParserLoc);
	
	return readTextValueString(#SQLQuery, phpOut);
}