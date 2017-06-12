module QCPAnalysis::Demos::SCAM2017Demo

import lang::php::util::Utils;
import lang::php::util::Config;
import lang::php::ast::System;

import QCPAnalysis::SQLModel;
import QCPAnalysis::QCPSystemInfo;
import QCPAnalysis::ParseSQL::AbstractSyntax;
import QCPAnalysis::ParseSQL::RunSQLParser;

import IO;
import ValueIO;
import Set;

alias SQLModelMap = map[SQLModel model, rel[SQLYield yield, str queryWithHoles, SQLQuery parsed] yields];

loc modelLoc = baseLoc + "serialized/qcp/sqlmodels/";
/*  
	step 1, build SQL models models for a system

	step 2, generate yields for all SQL models

	step 3, convert yields to parsable strings

	step 4, parse strings
*/

public SQLModelMap runDemo(str p = "WebChess" , str v = "0.9.0", rel[loc, SQLModel] modelsRel = {}){
	SQLModelMap res = ( );
	
	// step 1
	System sys = loadBinary(p, v);
	QCPSystemInfo qcpi = readQCPSystemInfo(p, v);
	set[SQLModel] models = {};
	if (isEmpty(modelsRel)) { 
		models = buildModelsForSystem(sys, qcpi)<1>;
	} else {
		models = modelsRel<1>;
	}
	
	for(model <- models){
		// step 2
		res = res + (model : parseYields(yields(model)));
	}
	
	writeBinaryValueFile(modelLoc + "<p>_<v>", res);
	iprintToFile(modelLoc + "<p>_<v>.txt", res);
	
	return res;
}

public rel[SQLYield, str, SQLQuery] parseYields(set[SQLYield] yields){
	res = {};
	for(yield <- yields){
		// step 3
		queryString = yield2String(yield);
		
		// step 4
		parsed = runParser(queryString);
		
		res = res + <yield, queryString, parsed>;
	}
	
	return res;
}

public SQLModelMap readSQLModelMap(str p = "WebChess", str v = "0.9.0"){
	res = ( );
	try{
		res = readBinaryValueFile(#SQLModelMap, mapLoc + "<p>_<v>");
	}
	catch: {
		res = runDemo(p,v);
	}
	return res;
}