module QCPAnalysis::AnalyzeQueries

import lang::php::util::Corpus;
import lang::php::util::Utils;

import QCPAnalysis::BuildQueries;
import QCPAnalysis::AbstractQuery;
import QCPAnalysis::QCPCorpus;
import QCPAnalysis::ParseSQL::AbstractSyntax;

import List;
import Map;
import ValueIO;
import IO;
import String;

set[str] qcp = {"unclassified", "QCP1", "QCP2", "QCP3", "QCP4", "QCP5"};
set[str] qcpsubcases = {"unclassified", "QCP1a", "QCP1b", "QCP2", "QCP3a", "QCP3b", "QCP4a", "QCP4b", "QCP4c", "QCP5"};

@doc{counts the calls to mysql_query in each system}
public lrel[str, int] countCallsSystem(){
	Corpus corpus = getCorpus();
	res = [];
	total = 0;
	for(p <- corpus, v := corpus[p]){
		pt = loadBinary(p,v);
		calls = [ c | /c:call(name(name("mysql_query")),_) := pt ];
		total += size(calls);
		res += <"<p>_<v>", size(calls)>;
	}
	return res + <"total", total>;
}

alias QueryMap = map[str, list[Query]];

public QueryMap loadQueryMap() {
	return readBinaryValueFile(#QueryMap, |project://QCPAnalysis/results/lists/queryMap|);
}

@doc{gets all queries found by FunctionQueries.rsc (i.e., queries whose function is not mysql_query)}
public list[Query] getFunctionQueries(QueryMap queryMap = ()){
	if (size(queryMap) == 0) {
		queryMap = loadQueryMap();
	}
	
	res = [];
	visit(queryMap){
		case QCP5(_,_,paramQueries): res = res + paramQueries;
	}
	return res;
}

@doc{gets all unclassified queries with a particular errorcode}
public list[Query] getUnclassifiedQueries(int errorCode, QueryMap queryMap = ()){
	queries = [q | sys <- queryMap, queries := queryMap[sys], q <- queries] + getFunctionQueries(queryMap = queryMap);
	return [q | q <- queries, unclassified(_,errorCode) := q];
}

@doc{gets all queries of a particular pattern. Note: run writeQueries() before this}
public list[Query] getQCP(str pattern, QueryMap queryMap = ( ), bool withFunctionQueries = true){
	if (size(queryMap) == 0) {
		queryMap = loadQueryMap();
	}
	
	list[Query] functionQueries = [];
	if(withFunctionQueries){
		functionQueries = getFunctionQueries(queryMap = queryMap);
	}	
	
	queries = [q | sys <- queryMap, queries := queryMap[sys], q <- queries];
	switch(pattern){
		case "unclassified" : return [ q | q <- queries + functionQueries, q is unclassified ];
		case "QCP1" : return [q | q <- queries + functionQueries, q is QCP1a || q is QCP1b ];
		case "QCP1a" : return [q | q <- queries + functionQueries, q is QCP1a ];
		case "QCP1b" : return [q | q <- queries + functionQueries, q is QCP1b ];
		case "QCP2" : return [q | q <- queries + functionQueries, q is QCP2];
		case "QCP3" : return [q | q <- queries + functionQueries, q is QCP3a || q is QCP3b ];
		case "QCP3a" : return [q | q <- queries + functionQueries, q is QCP3a ];
		case "QCP3b" : return [q | q <- queries + functionQueries, q is QCP3b ];
		case "QCP4" : return [q | q <- queries + functionQueries, q is QCP4a || q is QCP4b || q is QCP4c ];
		case "QCP4a" : return [q | q <- queries + functionQueries, q is QCP4a ];
		case "QCP4b" : return [q | q <- queries + functionQueries, q is QCP4b ];
		case "QCP4c" : return [q | q <- queries + functionQueries, q is QCP4c ];
		case "QCP5" : return [q | q <- queries + functionQueries, q is QCP5 ];
		default : throw "unexpected pattern name <pattern> entered";
	}
}

@doc{gets counts for each QCP (subcases = true will return subcase counts, false will return only overall counts}
public lrel[str, int] getQCPCounts(bool subcases, QueryMap queryMap = ( ), bool withFunctionQueries = false){
	res = [];
	if(subcases){
		for(p <- qcpsubcases){
			res += <p, size(getQCP(p, queryMap = queryMap, withFunctionQueries = withFunctionQueries))>;
		}
	}
	else{
		for(p <- qcp){
			res += <p, size(getQCP(p, queryMap = queryMap, withFunctionQueries = withFunctionQueries))>;
		}
	}	
	return res;
}

@doc{since buildQueriesCorpus takes a long time to run, this function writes the results of it to a file for quick reference}
public void writeQueries(){
	queries = buildQueriesCorpus();
	writeBinaryValueFile(|project://QCPAnalysis/results/lists/queryMap|, queries);
}

@doc{function to write abstract sql queries to a file for manual inspection}
public void writeParsed(QueryMap queryMap = ()){
	writeFile(|project://QCPAnalysis/results/lists/qcp1|, "");
	qcp1 = getQCP("QCP1", queryMap = loadQueryMap(), withFunctionQueries = true);
	mixed = getQCP("QCP4", queryMap = loadQueryMap(), withFunctionQueries = true);
	mixed += getQCP("QCP2", queryMap = loadQueryMap(), withFunctionQueries = true);
	
	int parseErrorsQCP1 = 0;
	int unknownQueriesQCP1 = 0;
	int parseErrorsQCP4 = 0;
	int unknownQueriesQCP4 = 0;	
	
	
	for(q <- qcp1){
		appendToFile(|project://QCPAnalysis/results/lists/qcp1|,"<q.sql>\n<q.parsed>\n<q.callloc>\n\n");
		if(q.parsed is parseError) parseErrorsQCP1 = parseErrorsQCP1 + 1;
		if(q.parsed is unknownQuery) unknownQueriesQCP1 = unknownQueriesQCP1 + 1; 
	}
	for(q <- mixed){
		appendToFile(|project://QCPAnalysis/results/lists/qcp1|,"<q.mixedQuery>\n<q.parsed>\n<q.callloc>\n\n");
		if(q.parsed is parseError){
			println(q.callloc);
			parseErrorsQCP4 = parseErrorsQCP4 + 1;
		}
		if(q.parsed is unknownQuery) unknownQueriesQCP4 = unknownQueriesQCP4 + 1; 
	}
	
	println("Out of <size(qcp1)> QCP1 query parse attempts, <unknownQueriesQCP1> were an unknown query type and <parseErrorsQCP1> did not parse.");
	println("Out of <size(mixed)> Dynamic(QCP2 and QCP4) query parse attempts, <unknownQueriesQCP4> were an unknown query type and <parseErrorsQCP4> did not parse.");
}

@doc{returns true if this string represents a query hole}
public bool isQueryHole(str queryPart) = /^\?\d+$/ := trim(queryPart);

@doc{traverses the queryMap and classifies the query holes contained in each SQLQuery type}
public rel[str, int] classifyQueryHoles(QueryMap queryMap = ( )){
	if (size(queryMap) == 0) {
		queryMap = loadQueryMap();
	}
	
	queries = [q | sys <- queryMap, queries := queryMap[sys], q <- queries];
	queriesWithHoles = [q | q <- queries, q is QCP2 || q is QCP3b || q is QCP4a || q is QCP4b || q is QCP4c];
	int name = 0;
	int valuesClause = 0;
	int setOpNewValue = 0;
	
	top-down visit(queriesWithHoles){
		case i:insertQuery(into, valueLists, setOps, onDuplicateSetOps) : {
			println("Examining query holes in <i>");
			if(hole(_) := into.dest)  name = name + 1;
			for(c <- into.columns){
				if(isQueryHole(c)) name = name + 1;
			}
			for(l <- valueLists, v <- l){
				if(isQueryHole(v)) valuesClause = valuesClause + 1;
			}
			for(s <- setOps + onDuplicateSetOps){
				if(isQueryHole(s.column)) nameHoles = nameHoles + 1;
				if(isQueryHole(s.newValue)) setOpNewValue = setOpNewValue + 1;
			}
		}
	}
	
	return {
		<"Query Hole in SQL name", name>,
		<"Query Holes on RHS of SET operation", setOpNewValue>,
		<"Query Hole in VALUES clause", valuesClause>
	};
}