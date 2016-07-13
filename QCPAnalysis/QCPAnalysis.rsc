/* The purpose of this module is to analyze 
 * the mysql_query calls in the corpus with respect 
 * to some predefined "Query Construction Patterns" 
 * and return information about the occurences of each
 * pattern. Query Construction Patterns are as follows:
 *
 * QCP1: mysql_query calls with string literal parameter
 * QCP2: mysql_query calls with literals, variables, unsafe inputs, 
 *		 function or method calls concatenated or interpolated
 * QCP3: mysql_query calls with variable parameters
 *
 * By David Anderson
 */ 
module QCPAnalysis::QCPAnalysis

import lang::php::util::Utils;
import lang::php::ast::System;
import lang::php::ast::AbstractSyntax;
import QCPAnalysis::Util;

data QCPCount = QCP1(int n)
			  | QCP2(int n)
			  | QCP3(int n);

// returns the number of ocurrences of each QCP in a System
public list[QCPCount] countQCPSystem(System system){
	QCPCount nQCP1 = QCP1(0);
	QCPCount nQCP2 = QCP2(0);
	QCPCount nQCP3 = QCP3(0);
	
	for(location <- system.files){
		Script scr = system.files[location];	
		top-down visit (scr) {
			case call(name(name("mysql_query" )),[actualParameter(scalar(string(_)), _)]) : nQCP1.n = nQCP1.n + 1;
			case call(name(name("mysql_query" )),[actualParameter(scalar(string(_)), _), _]): nQCP1.n = nQCP1.n + 1;
			case call(name(name("mysql_query" )),[actualParameter(scalar(encapsed(_)),_)]) : nQCP2.n = nQCP2.n + 1;
			case call(name(name("mysql_query" )),[actualParameter(scalar(encapsed(_)), _),_]) : nQCP2.n = nQCP2.n + 1;
			case call(name(name("mysql_query" )),[actualParameter(binaryOperation(left,right,concat()),_)]) : nQCP2.n = nQCP2.n + 1;
			case call(name(name("mysql_query" )),[actualParameter(binaryOperation(left,right,concat()),_), _]) : nQCP2.n = nQCP2.n + 1;
			case call(name(name("mysql_query" )),[actualParameter(var(name(name(_))), _)]) : nQCP3.n = nQCP3.n + 1;
			case call(name(name("mysql_query" )),[actualParameter(var(name(name(_))), _), _]) : nQCP3.n = nQCP3.n + 1;
		};
	}
	return [nQCP1, nQCP2, nQCP3];
}

// returns the number of ocurrences of each QCP in each system in the corpus,
// as well as the corpus-wide totals of each QCP
public map[str, list[QCPCount]] countQCPCorpusItems(){
	set[str] items = getCorpusItems();
	map[str, list[QCPCount]] corpusItemCounts = ();
	QCPCount totalQCP1 = QCP1(0);
	QCPCount totalQCP2 = QCP2(0);
	QCPCount totalQCP3 = QCP3(0);
	
	for(item <- items){
		System system = loadBinary(item);
		list[QCPCount] systemCounts = countQCPSystem(system);
		top-down visit(systemCounts){
			case QCP1(x) : totalQCP1.n = totalQCP1.n + x;
			case QCP2(x) : totalQCP2.n = totalQCP2.n + x;
			case QCP3(x) : totalQCP3.n = totalQCP3.n + x;
		}
		corpusItemCounts += (item : systemCounts);
	}
	corpusItemCounts += ("totals" : [totalQCP1, totalQCP2, totalQCP3]);
	return corpusItemCounts;
}