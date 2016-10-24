/* The purpose of this module is to analyze 
 * the mysql_query calls in the corpus with respect 
 * to some predefined "Query Groups" 
 * and return information about the occurences of each
 * pattern. Query Groups are as follows:
 *
 * QG1: mysql_query calls with string literal parameter
 * QG2: mysql_query calls with literals, variables, unsafe inputs, 
 *		 function or method calls concatenated or interpolated
 * QG3: mysql_query calls with a single variable paramter
 * QG4: mysql_query calls whose parameter is an array
 * While this module is pretty general (hence the name),
 * Other modules provide more in-depth analyses
 */ 

module QCPAnalysis::QueryGroups

import QCPAnalysis::QCPCorpus;

import lang::php::util::Corpus;
import lang::php::util::Utils;
import lang::php::ast::AbstractSyntax;

import List;
import Map;
import Set;

// represents the count of a particular Query Group
data QGCount = QG1(int n)
			  | QG2(int n)
			  | QG3(int n)
			  | QG4(int n)
			  | unmatched(int n);

public bool matchesQG1(call(name(name("mysql_query")), [actualParameter(scalar(string(_)), _)])) = true;
public bool matchesQG1(call(name(name("mysql_query")), [actualParameter(scalar(string(_)), _), _])) = true;
public default bool matchesQG1(Expr e) = false;

public bool matchesQG2(call(name(name("mysql_query")), [actualParameter(scalar(encapsed(_)),_)])) = true;
public bool matchesQG2(call(name(name("mysql_query")), [actualParameter(scalar(encapsed(_)), _),_])) = true;
public bool matchesQG2(call(name(name("mysql_query")), [actualParameter(binaryOperation(left,right,concat()),_)])) = true;
public bool matchesQG2(call(name(name("mysql_query")), [actualParameter(binaryOperation(left,right,concat()),_), _])) = true;
public default bool matchesQG2(Expr e) = false;

public bool matchesQG3(call(name(name("mysql_query")), [actualParameter(var(name(name(_))), _)])) = true;
public bool matchesQG3(call(name(name("mysql_query")), [actualParameter(var(name(name(_))), _), _])) = true;
public default bool matchesQG3(Expr e) = false;

public bool matchesQG4(call(name(name("mysql_query")), [actualParameter(fetchArrayDim(var(name(name(_))),_),_)])) = true;
public bool matchesQG4(call(name(name("mysql_query")), [actualParameter(fetchArrayDim(var(name(name(_))),_),_),_])) = true;
public default bool matchesQG4(Expr e) = false;

public bool unmatched(Expr e) = !matchesQG1(e) && !matchesQG2(e) && !matchesQG3(e) && !matchesQG4(e);

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
	return toList(range(getMSQCorpus()));
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

// maps all systems in the corpus to a list of QG occurrences based on parameter n
// if n = 1, return all QG1, if n = 2, return all QG2, if n = 3
// return all QG3. if n = any other number, return all mysql_query
// calls that do not match any QG
public map[str, list[Expr]] getQG(int n){
	map[str, list[Expr]] calls = getMSQCorpus();
	map[str, list[Expr]] qgMap = ();
	for(sys <- calls, msq := calls[sys]){
		list[Expr] qgList = [];
		switch(n){
			case 1 : qgList = [q | q <- msq, matchesQG1(q)];
			case 2 : qgList = [q | q <- msq, matchesQG2(q)];
			case 3 : qgList = [q | q <- msq, matchesQG3(q)];
			case 4:  qgList = [q | q <- msq, matchesQG4(q)];
			default: qgList = [q | q <- msq, unmatched(q)];
		}
		qgMap += (sys : qgList);
	}
	return qgMap;
}

// returns the number of ocurrences of each QG in each system in the corpus,
// as well as the corpus-wide totals of each QG
public map[str, set[QGCount]] countQG(){
	map[str, set[QGCount]] counts = ();
	Corpus corpus = getCorpus();
	for(p <- corpus, v := corpus[p]){
		counts += ("<p>_<v>" : {});
	}
	for(n <- [1..6]){
		map[str, list[Expr]] qgMap = getQG(n);
		for(sys <- qgMap, qgList := qgMap[sys]){
			switch(n){
				case 1 : counts[sys] += QG1(size(qgList));
				case 2 : counts[sys] += QG2(size(qgList));
				case 3 : counts[sys] += QG3(size(qgList));
				case 4 : counts[sys] += QG4(size(qgList));
				case 5 : counts[sys] += unmatched(size(qgList));
			}
		} 
	}
	return counts;
}