/* The purpose of this module is to analyze 
 * the mysql_query calls in the corpus with respect 
 * to some predefined "Query Construction Patterns" 
 * and return information about the occurences of each
 * pattern. Query Construction Patterns are as follows:
 *
 * QCP1: mysql_query calls with string literal parameter
 * QCP2: mysql_query calls with literals, variables, unsafe inputs, 
 *		 function or method calls concatenated or interpolated
 * QCP3: mysql_query calls with a single variable paramter
 * QCP4: mysql_query calls whose parameter is an array
 * While this module is pretty general (hence the name),
 * Other modules provide more in-depth analyses
 */ 

module QCPAnalysis::GeneralQCP

import QCPAnalysis::QCPCorpus;

import lang::php::util::Corpus;
import lang::php::util::Utils;
import lang::php::ast::AbstractSyntax;

import List;
import Map;

// represents the count of a particular QCP
data QCPCount = QCP1(int n)
			  | QCP2(int n)
			  | QCP3(int n)
			  | QCP4(int n)
			  | unmatched(int n);

public bool matchesQCP1(call(name(name("mysql_query")), [actualParameter(scalar(string(_)), _)])) = true;
public bool matchesQCP1(call(name(name("mysql_query")), [actualParameter(scalar(string(_)), _), _])) = true;
public default bool matchesQCP1(Expr e) = false;

public bool matchesQCP2(call(name(name("mysql_query")), [actualParameter(scalar(encapsed(_)),_)])) = true;
public bool matchesQCP2(call(name(name("mysql_query")), [actualParameter(scalar(encapsed(_)), _),_])) = true;
public bool matchesQCP2(call(name(name("mysql_query")), [actualParameter(binaryOperation(left,right,concat()),_)])) = true;
public bool matchesQCP2(call(name(name("mysql_query")), [actualParameter(binaryOperation(left,right,concat()),_), _])) = true;
public default bool matchesQCP2(Expr e) = false;

public bool matchesQCP3(call(name(name("mysql_query")), [actualParameter(var(name(name(_))), _)])) = true;
public bool matchesQCP3(call(name(name("mysql_query")), [actualParameter(var(name(name(_))), _), _])) = true;
public default bool matchesQCP3(Expr e) = false;

public bool matchesQCP4(call(name(name("mysql_query")), [actualParameter(fetchArrayDim(var(name(name(_))),_),_)])) = true;
public bool matchesQCP4(call(name(name("mysql_query")), [actualParameter(fetchArrayDim(var(name(name(_))),_),_),_])) = true;
public default bool matchesQCP4(Expr e) = false;

public bool unmatched(Expr e) = !matchesQCP1(e) && !matchesQCP2(e) && !matchesQCP3(e) && !matchesQCP4(e);

// gets all mysql_query calls in the corpus
public map[str, list[Expr]] getMSQCorpus(){
	Corpus corpus = getCorpus();
	map[str, list[Expr]] calls = ();
	for (p <- corpus, v := corpus[p]){
		pt = loadBinary(p,v);
		calls += ("<p>_<v>" : [q | /q:call(name(name("mysql_query")),_) := pt]);
	}
	return calls;
}
public list[Expr] getMSQCorpusList(){
	calls = [];
	for(l <- range(getMSQCorpus())){
		calls += l;
	}
	return calls;
}

// returns the number of mysql_query calls in each system in the corpus
public map[str, int] countMSQCorpus(){
	map[str, list[Expr]] calls = getMSQCorpus();
	map[str, int] counts = ();
	int total = 0;
	for(sys <- calls, msq := calls[sys]){
		int count = size(msq);
		total += count;
		counts += (sys : count);
	}
	counts += ("total" : total);
	return counts;
}

// maps all systems in the corpus to a list of QCP occurrences based on parameter n
// if n = 1, return all QCP1, if n = 2, return all QCP2, if n = 3
// return all QCP3. if n = any other number, return all mysql_query
// calls that do not match any QCP
public map[str, list[Expr]] getQCP(int n){
	map[str, list[Expr]] calls = getMSQCorpus();
	map[str, list[Expr]] qcpMap = ();
	for(sys <- calls, msq := calls[sys]){
		list[Expr] qcpList = [];
		switch(n){
			case 1 : qcpList = [q | q <- msq, matchesQCP1(q)];
			case 2 : qcpList = [q | q <- msq, matchesQCP2(q)];
			case 3 : qcpList = [q | q <- msq, matchesQCP3(q)];
			case 4:  qcpList = [q | q <- msq, matchesQCP4(q)];
			default: qcpList = [q | q <- msq, unmatched(q)];
		}
		qcpMap += (sys : qcpList);
	}
	return qcpMap;
}

// returns the number of ocurrences of each QCP in each system in the corpus,
// as well as the corpus-wide totals of each QCP
public map[str, set[QCPCount]] countQCP(){
	map[str, set[QCPCount]] counts = ();
	Corpus corpus = getCorpus();
	for(p <- corpus, v := corpus[p]){
		counts += ("<p>_<v>" : {});
	}
	for(n <- [1..6]){
		map[str, list[Expr]] qcpMap = getQCP(n);
		for(sys <- qcpMap, qcpList := qcpMap[sys]){
			switch(n){
				case 1 : counts[sys] += QCP1(size(qcpList));
				case 2 : counts[sys] += QCP2(size(qcpList));
				case 3 : counts[sys] += QCP3(size(qcpList));
				case 4 : counts[sys] += QCP4(size(qcpList));
				case 5 : counts[sys] += unmatched(size(qcpList));
			}
		} 
	}
	return counts;
}