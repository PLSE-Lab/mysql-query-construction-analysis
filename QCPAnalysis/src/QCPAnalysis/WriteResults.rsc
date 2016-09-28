/* The purpose of this module is to provide functions that
 * output results of analyzing query construction patterns
 */

module QCPAnalysis::WriteResults

import QCPAnalysis::QCPCorpus;
import QCPAnalysis::QueryGroups;
import QCPAnalysis::QG2Analysis;

import lang::php::ast::AbstractSyntax;
import lang::php::util::Corpus;

import IO;

loc lists = |project://QCPAnalysis/results/lists/|;
loc counts =  |project://QCPAnalysis/results/counts/|;

// convenience function that performs all other functions in this module
public void writeResults(){
	writeCounts();
	writeQG();
}
// writes the counts from all QG analyses to a file in the results folder
public void writeCounts(){
	loc file = counts + "countMysqlQuery.txt";
	iprintToFile(file, countMSQCorpus());
	
	file = counts + "countQG.txt";
	iprintToFile(file, countQG());
}

public void writeQG(){
	map[str, list[Expr]] qcp1 = getQG(1);
	map[str, list[Expr]] qcp2 = getQG(2);
	map[str, list[Expr]] qcp3 = getQG(3);
	map[str, list[Expr]] unmatched = getQG(4);
	Corpus corpus = getCorpus();
	for(p <- corpus, v := corpus[p]){
		loc sys = lists + "<p>_<v>";
		iprintToFile(sys + "QG1", qcp1["<p>_<v>"]);
		iprintToFile(sys + "QG2", qcp2["<p>_<v>"]);
		iprintToFile(sys + "QG3", qcp3["<p>_<v>"]);
		iprintToFile(sys + "unmatched", unmatched["<p>_<v>"]);
	}
}