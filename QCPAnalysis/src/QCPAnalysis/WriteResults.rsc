/* The purpose of this module is to provide functions that
 * output results of analyzing query construction patterns
 */

module QCPAnalysis::WriteResults

import QCPAnalysis::GeneralQCP;
import QCPAnalysis::QCP2Analysis;
import QCPAnalysis::VariableAnalysis;

import lang::php::ast::AbstractSyntax;
import IO;

loc lists = |project://QCPAnalysis/results/lists/|;
loc counts =  |project://QCPAnalysis/results/counts/|;

// convenience function that performs all other functions in this module
public void writeResults(){
	writeCounts();
	writeLists();
}
// writes the counts from all QCP analyses to a file in the results folder
public void writeCounts(){
	loc file = counts + "countMysqlQuery.txt";
	iprintToFile(file, countMSQCorpus());
	
	file = counts + "countQCP.txt";
	iprintToFile(file, countQCP());
	
	file = counts + "countQCP2WithExprType.txt";
	iprintToFile(file, getQCP2Counts());
}

public void writeLists(){
	loc file = lists + "callsWithVariables.txt";
	iprintToFile(file, getCallsWithVars());
}