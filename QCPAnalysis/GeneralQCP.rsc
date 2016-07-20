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
 * While this module is pretty general (hence the name),
 * Other modules provide more in-depth analyses
 */ 
module QCPAnalysis::GeneralQCP

import QCPAnalysis::Util;

import IO;
import lang::php::util::Utils;
import lang::php::ast::System;
import lang::php::ast::AbstractSyntax;

// represents the count of a particular QCP
data QCPCount = QCP1(int n)
			  | QCP2(int n)
			  | QCP3(int n)
			  | unmatched(int n);

alias QCP = list[ActualParameter];

// returns true if QCP1 matches params
public bool matchesQCP1(QCP params){
	if([actualParameter(scalar(string(_)), _)] := params
		|| [actualParameter(scalar(string(_)), _), _] := params){
	
		return true;	
	}
	else 
		return false;
}

// returns true if QCP2 matches params
public bool matchesQCP2(QCP params){
	if([actualParameter(scalar(encapsed(_)),_)] := params
		|| [actualParameter(scalar(encapsed(_)), _),_] := params
		|| [actualParameter(binaryOperation(left,right,concat()),_)] := params
		|| [actualParameter(binaryOperation(left,right,concat()),_), _] := params){
	
		return true;	
	}
	else 
		return false;
}

// returns true if QCP3 matches params
public bool matchesQCP3(QCP params){
	if([actualParameter(var(name(name(_))), _)] := params
		|| [actualParameter(var(name(name(_))), _), _] := params){
	
		return true;	
	}
	else 
		return false;
}

// returns true if no QCP matches params
public bool unmatched(QCP params){
	if(!matchesQCP1(params) && !matchesQCP2(params) && !matchesQCP3(params)){
		return true;
	}
	else
		return false;
}

// returns the number of ocurrences of each QCP in each system in the corpus,
// as well as the corpus-wide totals of each QCP
public map[str, list[QCPCount]] countQCPCorpus(){
	set[str] items = getCorpusItems();
	map[str, list[QCPCount]] corpusItemCounts = ();
	QCPCount totalQCP1 = QCP1(0);
	QCPCount totalQCP2 = QCP2(0);
	QCPCount totalQCP3 = QCP3(0);
	QCPCount totalUnmatched = unmatched(0);
	for(item <- items){
		System system = loadBinary(item);
		list[QCPCount] systemCounts = countQCPSystem(system);
		top-down visit(systemCounts){
			case QCP1(x) : totalQCP1.n += x;
			case QCP2(x) : totalQCP2.n += x;
			case QCP3(x) : totalQCP3.n += x;
			case unmatched(x) : totalUnmatched.n += x;
		}
		corpusItemCounts += (item : systemCounts);
	}
	corpusItemCounts += ("totals" : [totalQCP1, totalQCP2, totalQCP3, totalUnmatched]);
	return corpusItemCounts;
}

// returns the number of ocurrences of each QCP in a particular System
public list[QCPCount] countQCPSystem(System system){
	QCPCount nQCP1 = QCP1(0);
	QCPCount nQCP2 = QCP2(0);
	QCPCount nQCP3 = QCP3(0);
	QCPCount nUnmatched = unmatched(0);
	
	for(location <- system.files){
		Script scr = system.files[location];	
		top-down visit (scr) {
			case call(name(name("mysql_query" )), params):{
				if(matchesQCP1(params)){
					nQCP1.n += 1;	
				}
				else if(matchesQCP2(params)){
					nQCP2.n += 1;
				}
				else if(matchesQCP3(params)){
					nQCP3.n += 1;
				}
				else{
					nUnmatched.n += 1;
				}
			}
		};
	}
	return [nQCP1, nQCP2, nQCP3, nUnmatched];
}

// maps all systems in the corpus to a list of QCP occurrences, regardless of case
public map[str, list[QCP]] getQCPCorpus(){
	map[str, list[QCP]] qcpMap = ();
	set[str] items = getCorpusItems();
	for(item <- items){
		System system = loadBinary(item);
		qcpMap += (item : getQCPSystem(system));
	}
	return qcpMap;
}

// maps all systems in the corpus to a list of QCP occurrences based on parameter n
// if n = 1, return all QCP1, if n = 2, return all QCP2, if n = 3
// return all QCP3. if n = any other number, return all mysql_query
// calls that do not match any QCP (if any)
public map[str, list[QCP]] getQCPCorpus(int n){
	map[str, list[QCP]] qcpMap = ();
	set[str] items = getCorpusItems();
	for(item <- items){
		System system = loadBinary(item);
		qcpMap += (item : getQCPSystem(system, n));
	}
	return qcpMap;
}

// returns a list of all QCP occurrences in a particular system, regardless of case
public list[QCP] getQCPSystem(System system){
	list[QCP] qcpList = [];
	for(location <- system.files){
		Script scr = system.files[location];
		top-down visit(scr){
			case call(name(name("mysql_query" )), params): qcpList += [params];
		}
	}
	return qcpList;
}

// returns a list of all QCP occurrences in a particular system, based on parameter n
// if n = 1, return all QCP1, if n = 2, return all QCP2, if n = 3
// return all QCP3. if n = any other number, return all mysql_query
// calls that do not match any QCP (if any)
public list[QCP] getQCPSystem(System system, int n){
	list[QCP] qcpList = [];
	switch(n){
		case 1 : qcpList = getQCP1System(system);
		case 2 : qcpList = getQCP2System(system);
		case 3 : qcpList = getQCP3System(system);
		default: qcpList = getUnmatchedSystem(system);
	}
	return qcpList;
}

// returns all QCP1 occurrences in a system
private list[QCP] getQCP1System(System system){
	list[QCP] qcp1List = [];
	for(location <- system.files){
		Script scr = system.files[location];
		top-down visit(scr){
			case call(name(name("mysql_query" )), params):{
				if(matchesQCP1(params)){
					qcp1List += [params];	
				}
			}
		}
	}
	return qcp1List;
}

// returns all QCP2 occurrences in a system
private list[QCP] getQCP2System(System system){
	list[QCP] qcp2List = [];
	for(location <- system.files){
		Script scr = system.files[location];
		top-down visit(scr){
			case call(name(name("mysql_query" )), params):{
				if(matchesQCP2(params)){
					qcp2List += [params];	
				}
			}
		}
	}
	return qcp2List;
}

// returns all QCP3 occurrences in a system
private list[QCP] getQCP3System(System system){
	list[QCP] qcp3List = [];
	for(location <- system.files){
		Script scr = system.files[location];
		top-down visit(scr){
			case call(name(name("mysql_query" )), params):{
				if(matchesQCP3(params)){
					qcp3List += [params];	
				}
			}
		}
	}
	return qcp3List;
}

// returns all mysql_query calls in a system whose parameters match no QCP (if any)
private list[QCP] getUnmatchedSystem(System system){
	list[QCP] unmatchedList = [];
	for(location <- system.files){
		Script scr = system.files[location];
		top-down visit(scr){
			case call(name(name("mysql_query" )), params):{
				if(unmatched(params)){
					unmatchedList += [params];
				}
			}
		}
	}
	return unmatchedList;
}
