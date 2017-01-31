module QCPAnalysis::AnalyzeQueries

import QCPAnalysis::BuildQueries;
import QCPAnalysis::AbstractQuery;

import List;
import ValueIO;

@doc{gets all queries of a particular pattern. Note: run writeQueries() before this}
public list[Query] getQCP(str pattern){
	queryMap = readBinaryValueFile(#map[str, list[Query]], |project://QCPAnalysis/results/lists/queryMap|);
	queries = [q | sys <- queryMap, queries := queryMap[sys], q <- queries];
	switch(pattern){
		case "unclassified" : return [ q | q <- queries, q is unclassified ];
		case "QCP1" : return [q | q <- queries, q is QCP1a || q is QCP1b ];
		case "QCP1a" : return [q | q <- queries, q is QCP1a ];
		case "QCP1b" : return [q | q <- queries, q is QCP1b ];
		case "QCP2" : return [q | q <- queries, q is QCP2 ];
		case "QCP3" : return [q | q <- queries, q is QCP3a || q is QCP3b ];
		case "QCP3a" : return [q | q <- queries, q is QCP3a ];
		case "QCP3b" : return [q | q <- queries, q is QCP3b ];
		case "QCP4" : return [q | q <- queries, q is QCP4a || q is QCP4b || q is QCP4c ];
		case "QCP4a" : return [q | q <- queries, q is QCP4a ];
		case "QCP4b" : return [q | q <- queries, q is QCP4b ];
		case "QCP4c" : return [q | q <- queries, q is QCP4c ];
		case "QCP5" : return [q | q <- queries, q is QCP5 ];
		default : throw "unexpected pattern name entered";
	}
}

@doc{gets Queries in a particular system of a particular pattern}
public list[Query] getQCPSystem(str p, str v, str pattern){
	queryMap = readBinaryValueFile(#map[str, list[Query]], |project://QCPAnalysis/results/lists/queryMap|);
	queries = queryMap["<p>_<v>"];
	switch(pattern){
		case "unclassified" : return [ q | q <- queries, q is unclassified ];
		case "QCP1" : return [q | q <- queries, q is QCP1a || q is QCP1b ];
		case "QCP1a" : return [q | q <- queries, q is QCP1a ];
		case "QCP1b" : return [q | q <- queries, q is QCP1b ];
		case "QCP2" : return [q | q <- queries, q is QCP2 ];
		case "QCP3" : return [q | q <- queries, q is QCP3a || q is QCP3b ];
		case "QCP3a" : return [q | q <- queries, q is QCP3a ];
		case "QCP3b" : return [q | q <- queries, q is QCP3b ];
		case "QCP4" : return [q | q <- queries, q is QCP4a || q is QCP4b || q is QCP4c ];
		case "QCP4a" : return [q | q <- queries, q is QCP4a ];
		case "QCP4b" : return [q | q <- queries, q is QCP4b ];
		case "QCP4c" : return [q | q <- queries, q is QCP4c ];
		case "QCP5" : return [q | q <- queries, q is QCP5 ];
		default : throw "unexpected pattern name entered";
	}
}

@doc{function for getting QCP counts (true will return subcase counts, false, will return overall counts}
public lrel[str, int] getQCPCounts(true) = [
	<"QCP1a", size(getQCP("QCP1a"))>,
	<"QCP1b", size(getQCP("QCP1b"))>,
	<"QCP2", size(getQCP("QCP2"))>,
	<"QCP3a", size(getQCP("QCP3a"))>,
	<"QCP3b", size(getQCP("QCP3b"))>,
	<"QCP4a", size(getQCP("QCP4a"))>,
	<"QCP4b", size(getQCP("QCP4b"))>,
	<"QCP4c", size(getQCP("QCP4c"))>,
	<"QCP5", size(getQCP("QCP5"))>,
	<"unclassified", size(getQCP("unclassified"))>
];
public lrel[str, int] getQCPCounts(false) = [
	<"QCP1", size(getQCP("QCP1"))>,
	<"QCP2", size(getQCP("QCP2"))>,
	<"QCP3", size(getQCP("QCP3"))>,
	<"QCP4", size(getQCP("QCP4"))>,
	<"QCP5", size(getQCP("QCP5"))>,
	<"unclassified", size(getQCP("unclassified"))>
];

@doc{since buildQueriesCorpus takes a long time to run, this function writes the results of it to a file for quick reference}
public void writeQueries(){
	queries = buildQueriesCorpus();
	writeBinaryValueFile(|project://QCPAnalysis/results/lists/queryMap|, queries);
}