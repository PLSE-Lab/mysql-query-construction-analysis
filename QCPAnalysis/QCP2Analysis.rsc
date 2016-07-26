/* The purpose of this module is to further analyze QCP2 occurences. 
 * For each occurence of QCP2, the following questions are asked:
 *
 * Does this QCP2 occurrence use string concatenation?
 * Does this QCP2 occurrence use string interpolation?
 * Does this QCP2 ocurrence contain string literals?
 * Does this QCP2 occurrence contain function calls?
 * Does this QCP2 occurrence contain method calls?
 * Does this QCP2 occurrence contain static method calls?
 * Does this QCP2 occurrence contain variables?
 * Does this QCP2 occurrence conatain unsafe inputs? i.e. 
 * $_POST, $_GET or $_SESSION parameters?
 * 
 */
module QCPAnalysis::QCP2Analysis

import QCPAnalysis::Util;
import QCPAnalysis::GeneralQCP;

import IO;
import lang::php::util::Utils;
import lang::php::ast::System;
import lang::php::ast::AbstractSyntax;

alias Query = list[ActualParameter];

// represents a QCP2 occurrence. Contains the parameters to the mysql_query call as well as
// boolean variables that answer the questions found at the beginning of this module
data QCP2Info = QCP2Info(Query query, bool hasConcatenation, bool hasInterpolation, 
			bool hasLiterals, bool hasFunctionCalls, bool hasMethodCalls, bool hasStaticMethodCalls,
			bool hasVariables, bool hasUnsafeInputs);

// Collection of counts over a particular system. Each int represents the number of QCP2
// occurrences in the system that answer true to the questions found at the beginning of this module
data QCP2Counts = QCP2Counts(int numConcat, int numInter, int numLit, int numFunc, int numMethod,
							 int numStatic, int numVar,int numUnsafe);

// maps each system in the corpus to a QCP2Counts object				 
public map[str, QCP2Counts] getQCP2Counts(){
	map[str, QCP2Counts] corpusCounts = ();
	map[str, list[QCP2Info]] corpusQCP2 = getQCP2Corpus();
	for(sysName <- corpusQCP2){
		list[QCP2Info] sysQCP2 = corpusQCP2[sysName];
		corpusCounts += (sysName : collectQCP2Counts(sysQCP2));
	}
	return corpusCounts;
}

// maps each system in the corpus to a list of QCP2Info objects
public map[str, list[QCP2Info]] getQCP2Corpus(){
	map[str, list[QCP2Info]] corpusQCP2 = ();
	set[str] items = getCorpusItems();
	
	for(item <- items){
		System system = loadBinary(item);
		corpusQCP2 += (item : getQCP2System(system));
	}
	return corpusQCP2;
}

// analyzes a particular system in the corpus and returns
// a list of QCP2Info objects representing all QCP2 occurrences
// in the system
public list[QCP2Info] getQCP2System(System system){
	list[QCP2Info] systemQCP2Info = [];
	for(location <- system.files){
		Script scr = system.files[location];	
		top-down visit(scr){
			case call(name(name("mysql_query" )), params):{
				if(matchesQCP2(params)){
					QCP2Info info = QCP2Info(params, false, false, false, false, false, false, false, false);
					info.hasConcatenation     = checkConcatenation(params);
					info.hasInterpolation     = checkInterpolation(params);
					info.hasLiterals 	      = checkLiterals(params);
					info.hasFunctionCalls     = checkFunctionCalls(params);
					info.hasMethodCalls       = checkMethodCalls(params);
					info.hasStaticMethodCalls = checkStaticMethodCalls(params);
					info.hasVariables 	      = checkVariables(params);
					info.hasUnsafeInputs      = checkUnsafeInputs(params);
					systemQCP2Info += info;
				}
			}
		}
	}
	return systemQCP2Info;
}

// returns a QCP2Counts object that holds the empirical information obtained
// by analyzing the QCP2 occurrences of a particular system in the corpus
private QCP2Counts collectQCP2Counts(list[QCP2Info] sysQCP2){
	QCP2Counts counts = QCP2Counts(0,0,0,0,0,0,0,0);
	
	for(qcp2 <- sysQCP2){
		if(qcp2.hasConcatenation)     counts.numConcat += 1;
		if(qcp2.hasInterpolation)     counts.numInter  += 1;
		if(qcp2.hasLiterals)          counts.numLit    += 1;
		if(qcp2.hasFunctionCalls)     counts.numFunc   += 1;
		if(qcp2.hasMethodCalls)       counts.numMethod += 1;
		if(qcp2.hasStaticMethodCalls) counts.numStatic += 1;
		if(qcp2.hasVariables)         counts.numVar    += 1;
		if(qcp2.hasUnsafeInputs)      counts.numUnsafe += 1;
	}
	return counts;
}

// returns true if this QCP2 occurrence uses string concatenation
public bool checkConcatenation(Query query){
	if([actualParameter(binaryOperation(left,right,concat()),_)] := query
		|| [actualParameter(binaryOperation(left,right,concat()),_), _] := query){
		
		return true;		
	}
	else return false;
}

// returns true if this QCP2 occurrence uses string interpolation
public bool checkInterpolation(Query query){
	if([actualParameter(scalar(encapsed(_)),_)] := query
		|| [actualParameter(scalar(encapsed(_)), _),_] := query){
		
		return true;		
	}
	else return false;
}

// returns true if this QCP2 occurrence contains string literals
public bool checkLiterals(Query query){
	top-down visit(query){
		case scalar(string(t)) : return true;
	}
	return false;
}

// returns true if this QCP2 occurrence contains function calls
public bool checkFunctionCalls(Query query){
	top-down visit(query){
		case call(_,_): return true;
	}
	return false;
}

// returns true if this QCP2 occurrence contains method calls
public bool checkMethodCalls(Query query){
	top-down visit(query){
		case methodCall(_,_,_): return true;
	}
	return false;
}

// returns true if this QCP2 occurrence contains static method calls
public bool checkStaticMethodCalls(Query query){
	top-down visit(query){
		case staticCall(_,_,_): return true;
	}
	return false;
}

// returns true if this QCP2 occurrence contains variables
public bool checkVariables(Query query){
	top-down visit(query){
		case var(name(name(n))):{
			if( n != "_POST" && n != "_GET" && n != "_SESSION")
				return true;
		}
	}
	return false;
}

// returns true if this QCP2 occurrence contains unsafe inputs
public bool checkUnsafeInputs(Query query){
	top-down visit(query){
		case var(name(name(n))):{
			if( n == "_POST" || n == "_GET" || n == "_SESSION")
				return true;
		}
	}
	return false;
}