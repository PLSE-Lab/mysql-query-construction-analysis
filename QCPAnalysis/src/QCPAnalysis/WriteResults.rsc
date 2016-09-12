/* The purpose of this module is to provide functions that
 * output results of analyzing query construction patterns
 */

module QCPAnalysis::WriteResults

import QCPAnalysis::QCPCorpus;
import QCPAnalysis::GeneralQCP;
import QCPAnalysis::QCP2Analysis;
import QCPAnalysis::VariableAnalysis;

import lang::php::ast::AbstractSyntax;
import lang::php::util::Corpus;

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
}

public void writeQCP(){
	map[str, list[Expr]] qcp1 = getQCP(1);
	map[str, list[Expr]] qcp2 = getQCP(2);
	map[str, list[Expr]] qcp3 = getQCP(3);
	map[str, list[Expr]] unmatched = getQCP(4);
	Corpus corpus = getCorpus();
	for(p <- corpus, v := corpus[p]){
		loc sys = lists + "<p>_<v>";
		iprintToFile(sys + "QCP1", qcp1["<p>_<v>"]);
		iprintToFile(sys + "QCP2", qcp2["<p>_<v>"]);
		iprintToFile(sys + "QCP3", qcp3["<p>_<v>"]);
		iprintToFile(sys + "unmatched", unmatched["<p>_<v>"]);
	}
}

public void writeQCP2Subcases(){
	Corpus corpus = getCorpus();
	for(p <- corpus, v := corpus[p]){
		loc sys = lists + "<p>_<v>";
		iprintToFile(sys + "QCP2subcases/whereQCP2", getQCP2WithSubcase("where")["<p>_<v>"]);
		iprintToFile(sys + "QCP2subcases/andQCP2", getQCP2WithSubcase("and")["<p>_<v>"]);
		iprintToFile(sys + "QCP2subcases/orQCP2", getQCP2WithSubcase("or")["<p>_<v>"]);
		iprintToFile(sys + "QCP2subcases/notQCP2", getQCP2WithSubcase("not")["<p>_<v>"]);
		iprintToFile(sys + "QCP2subcases/unmatched", getQCP2WithSubcase("unmatched")["<p>_<v>"]);
	}
}