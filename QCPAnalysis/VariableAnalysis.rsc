/* the purpose of this module is to further analyze mysql_query calls
 * whose parameter is a variable (QCP3), or QCP2 calls whose parameter
 * contains variable(s) concatenated or interpolated. Information about
 * the origin of the variable and how its SQL string is built is
 * reported.
 * Note: in function and variable naming, QWV stands with Query With Variable(s)
 */
module QCPAnalysis::VariableAnalysis

import QCPAnalysis::Util;
import QCPAnalysis::GeneralQCP;
import QCPAnalysis::QCP2Analysis;

import IO;
import lang::php::util::Utils;
import lang::php::ast::System;
import lang::php::ast::AbstractSyntax;

alias Query = list[ActualParameter];

// represents a mysql_query call that contains variables.
// QCP2 occurrences may contain multiple variables while
// QCP3 occurrences contain a single variable 
data QueryWithVar = QCP2(Query query, list[str] variables)
			      | QCP3(Query query, str variable);

data QueryVarTrace = qvt(QueryWithVar query, list[Stmt] trace);

// maps each system in the corpus to a list of all queries with variables
public map[str, list[QueryWithVar]] getQWV(){
	map[str, list[QueryWithVar]] corpusQWV = ();
	map[str, list[Query]] corpusQCP2 = getQCPCorpus(2);
	map[str, list[Query]] corpusQCP3 = getQCPCorpus(3);
	for(system <- corpusQCP2){
		list[Query] qcp2System = corpusQCP2[system];
		list[Query] qcp3System = corpusQCP3[system];
		list[QueryWithVar] qcp2WV = getQCP2WV(qcp2System);
		list[QueryWithVar] qcp3WV = getQCP3WV(qcp3System);
		list[QueryWithVar] qwv = qcp2WV + qcp3WV;
		corpusQWV += (system : qwv);
	}
	return corpusQWV;
}

// returns a list of QueryWithVar objects representing all
// QCP2 occurrences in a particular system that contain variables
private list[QueryWithVar] getQCP2WV(list[Query] qcp2){
	list[QueryWithVar] qwvList = [];
	for(query <- qcp2){
		if(checkVariables(query)){
			QueryWithVar qwv = QCP2(query,[]);
			top-down visit(query){
				case var(name(name(n))):{
					if( n != "_POST" && n != "_GET" && n != "_SESSION")
						qwv.variables += [n];
				}
			}
			qwvList += qwv;
		}
	}
	return qwvList;
}

// returns a list of QueryWithVar objects representing all
// QCP3 occurrences in a particular system
private list[QueryWithVar] getQCP3WV(list[Query] qcp3){
	list[QueryWithVar] qwvList = [];
	for(query <- qcp3){
		QueryWithVar qwv = QCP3(query,"");
		top-down visit(query){
			case var(name(name(n))):{
				qwv.variable = n;
			}
		}
		qwvList += qwv;	
	}
	return qwvList;	
}