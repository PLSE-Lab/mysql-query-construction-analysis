/* The purpose of this module is to provide functions that
 * output results of analyzing query construction patterns
 */

module QCPAnalysis::WriteResults

import QCPAnalysis::Util;
import QCPAnalysis::GeneralQCP;
import QCPAnalysis::QCP2Analysis;
import QCPAnalysis::VariableAnalysis;

import IO;
import lang::php::util::Utils;
import lang::php::ast::System;
import lang::php::ast::AbstractSyntax;

alias Query = list[ActualParameter];

loc results = |project://QCPAnalysis/results/full%20QCP%20lists/|;
loc counts =  |project://QCPAnalysis/results/counts/|;

// convenience function that performs all other functions in this module
public void writeResults(){
	writeCounts();
	writeQCP1();
	writeQCP2();
	writeQCP3();
	writeUnmatched();
	writeQCP2WithProperties();
	writeVariableAnalysis();
}
// writes the counts from all QCP analyses to a file in the results folder
public void writeCounts(){
	loc file = counts + "countMysqlQuery.txt";
	iprintToFile(file, numMSQCallsCorpus());
	
	file = counts + "countQCP.txt";
	iprintToFile(file, countQCPCorpus());
	
	file = counts + "countQCP2.txt";
	writeFile(file, "");
	writeQCP2Counts(file);
}

// writes the list of QCP2Counts objects to a file in the results folder
public void writeQCP2Counts(loc location){
	map[str, QCP2Counts] qcp2counts = getQCP2Counts();
	for(system <- qcp2counts){
		QCP2Counts systemCounts = qcp2counts[system];
		appendToFile(location, "QCP2Counts for <system>\n");
		appendToFile(location, "\tNumber of QCP2 occurrences using string concatenation: <systemCounts.numConcat>\n");
		appendToFile(location, "\tNumber of QCP2 occurrences using string interpolation: <systemCounts.numInter>\n");
		appendToFile(location, "\tNumber of QCP2 occurrences containing sting literals:  <systemCounts.numLit>\n");
		appendToFile(location, "\tNumber of QCP2 occurrences containing function calls:  <systemCounts.numFunc>\n");
		appendToFile(location, "\tNumber of QCP2 occurrences containing variables:       <systemCounts.numVar>\n");
		appendToFile(location, "\tNumber of QCP2 occurrences containing unsafe inputs:   <systemCounts.numUnsafe>\n");
	}
}

// writes all QCP1 occurrences to a file in the results folder
public void writeQCP1(){
	map[str, list[Query]] qcp1Map = getQCPCorpus(1);
	iprintToFile(results + "QCP1.txt", qcp1Map);
}

// writes all QCP2 ocurrences to a file in the results folder
public void writeQCP2(){
	map[str, list[Query]] qcp2Map = getQCPCorpus(2);
	iprintToFile(results + "QCP2.txt", qcp2Map);
}

// writes all QCP3 occurrences to a file in the results folder
public void writeQCP3(){
	map[str, list[Query]] qcp3Map = getQCPCorpus(3);
	iprintToFile(results + "QCP3.txt", qcp3Map);
}

// writes all mysql_query parameters that did not match any QCP (if any)
public void writeUnmatched(){
	map[str, list[Query]] unmatchedMap = getQCPCorpus(4);
	iprintToFile(results + "unmatched.txt", unmatchedMap);
}

// for each boolean parameter, writes to a file in the results folder a list of
// all QCP2 that satisfy that boolean parameter
public void writeQCP2WithProperties(){
	list[Query] concat = [];
	list[Query] inter  = [];
	list[Query] lit    = [];
	list[Query] func   = [];
	list[Query] method = [];
	list[Query] static = [];
	list[Query] var    = [];
	list[Query] unsafe = [];
	map[str, list[QCP2Info]] qcp2Info = getQCP2Corpus();
	for(system <- qcp2Info){
		list[QCP2Info] infoList = qcp2Info[system];
		for(info <- infoList){
			if(info.hasConcatenation)     concat += [info.query];
			if(info.hasInterpolation)     inter  += [info.query];
			if(info.hasLiterals)          lit    += [info.query];
			if(info.hasFunctionCalls)     func   += [info.query];
			if(info.hasMethodCalls)       method += [info.query];
			if(info.hasStaticMethodCalls) static += [info.query];
			if(info.hasVariables)         var    += [info.query];
			if(info.hasUnsafeInputs)      unsafe += [info.query];
		}
	}
	loc detailed = results + "QCP2Detailed/";
	iprintToFile(detailed + "QCP2Concatenation.txt", concat);
	iprintToFile(detailed + "QCP2Interpolation.txt", inter);
	iprintToFile(detailed + "QCP2Literals.txt", lit);
	iprintToFile(detailed + "QCP2FunctionCalls.txt", func);
	iprintToFile(detailed + "QCP2MethodCalls.txt", method);
	iprintToFile(detailed + "QCP2StaticMethodCalls.txt", static);
	iprintToFile(detailed + "QCP2Variables.txt", var);
	iprintToFile(detailed + "QCP2UnsafeInputs.txt", unsafe);
}

// writes results from the variable analysis module
public void writeVariableAnalysis(){
	loc detailed = results + "VariableAnalysis/";
	iprintToFile(detailed + "QueriesWithVariables.txt", getQWV());
}