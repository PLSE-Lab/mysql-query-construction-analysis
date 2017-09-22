module QCPAnalysis::Demos::SCAM2017Demo

import lang::php::util::Utils;
import lang::php::util::Config;
import lang::php::ast::System;
import lang::php::ast::AbstractSyntax;

import QCPAnalysis::SQLModel;
import QCPAnalysis::QCPSystemInfo;
import QCPAnalysis::ParseSQL::AbstractSyntax;
import QCPAnalysis::ParseSQL::RunSQLParser;
import QCPAnalysis::QCPCorpus;
import QCPAnalysis::SQLAnalysis;

import IO;
import ValueIO;
import Set;
import List;

@doc{Show the systems in the corpus, with numbers to make them easier to select}
public void showSystems() {
	map[int,str] numberedSystems = getNumbersWithSystems();
	println("The following systems are available:");
	for (i <- sort(toList(numberedSystems<0>))) {
		println("\t<i>:<numberedSystems[i]>");
	}
}

@doc{Sort a set of calls by the locations of the calls}
private lrel[Expr callExpr, loc callLoc] sortCalls(rel[Expr callExpr, loc callLoc] calls) {
	bool compareCall(<Expr c1Call, loc c1Loc>, <Expr c2Call, loc c2Loc>) {
		if (c1Loc.path == c2Loc.path) {
			return c1Loc.offset < c2Loc.offset;
		} else {
			return c1Loc.path < c2Loc.path;
		}
	}

	return sort(toList(calls), compareCall);
}

@doc{Show a numbered list of calls for a given system}
public void showCallsInSystem(int systemNumber) {
	map[int,str] numberedSystems = getNumbersWithSystems();
	if (systemNumber notin numberedSystems) {
		println("That is not a valid system number, please use \"showSystems();\" to show valid system numbers");
		return;
	}
	systemName = numberedSystems[systemNumber];
	corpus = getCorpus();
	systemVersion = corpus[systemName];
	
	// Load in the serialized system, including ASTs for all scripts
	pt = loadBinary(systemName, systemVersion);
	
	// Find all calls to the mysql_query function in the system ASTs
	allCalls = { < c, c@at > | /c:call(name(name("mysql_query")),_) := pt.files };
	
	// Put these into some sort of order, based on the path and line number of the call
	orderedCalls = sortCalls(allCalls);
	
	if (isEmpty(orderedCalls)) {
		println("No calls were found");
		return;
	} else {
		println("A total of <size(orderedCalls)> were found:");
		for (idx <- index(orderedCalls<1>)) {
			println("\tCall <idx>: <orderedCalls[idx][1]>");
		}
	}
}

@doc{Return the SQL model for a specific call in a specific system}
public SQLModel buildModelForNumberedCall(int systemNumber, int callNumber) {
	map[int,str] numberedSystems = getNumbersWithSystems();
	if (systemNumber notin numberedSystems) {
		println("That is not a valid system number, please use \"showSystems();\" to show valid system numbers");
		return;
	}
	systemName = numberedSystems[systemNumber];
	corpus = getCorpus();
	systemVersion = corpus[systemName];
	
	// Load in the serialized system, including ASTs for all scripts
	pt = loadBinary(systemName, systemVersion);
	
	// Find all calls to the mysql_query function in the system ASTs
	allCalls = { < c, c@at > | /c:call(name(name("mysql_query")),_) := pt.files };
	
	// Put these into some sort of order, based on the path and line number of the call
	orderedCalls = sortCalls(allCalls);
	
	if (isEmpty(orderedCalls)) {
		throw "No calls were found";
	} else if (callNumber notin index(orderedCalls)) {
		throw "<callNumber> is not a valid call number";
	} else {
		QCPSystemInfo qcpi = readQCPSystemInfo(systemName, systemVersion);
		callModel = buildModel(qcpi, orderedCalls[callNumber][1]);
		return callModel;
	}
}

@doc{Return the SQL yields for a specific call in a specific system}
public set[SQLYield] showYieldsForNumberedCall(int systemNumber, int callNumber) {
	callModel = buildModelForNumberedCall(systemNumber, callNumber);
	return yields(callModel);
}

@doc{Return the SQL queries for a specific call in a specific system}
public rel[SQLYield yield, str queryWithHoles, SQLQuery parsed] showQueriesForNumberedCall(int systemNumber, int callNumber) {
	ylds = showYieldsForNumberedCall(systemNumber, callNumber);
	rel[SQLYield yield, str queryWithHoles, SQLQuery parsed] res = { };
	for (yld <- ylds) {
		queryString = yield2String(yld);
		parsed = runParser(queryString);
		res += < yld, queryString, parsed >;
	}
	return res;
}

@doc{classify a particular model based on our current patterns}
public str classifyModelForNumberedCall(int systemNumber, int callNumber){
	callModel = buildModelForNumberedCall(systemNumber, callNumber);
	return classifySQLModel(callModel);
}