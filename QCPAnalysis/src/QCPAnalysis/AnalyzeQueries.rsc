module QCPAnalysis::AnalyzeQueries

import lang::php::util::Corpus;
import lang::php::util::Utils;
import lang::php::util::Config;

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
	return readBinaryValueFile(#QueryMap, baseLoc + "serialized/qcp/queryMap");
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
	writeBinaryValueFile(baseLoc + "serialized/qcp/queryMap", queries);
}

@doc{function to write abstract sql queries to a file for manual inspection}
public void writeParsed(QueryMap queryMap = ()){
	parsedLoc = baseLoc + "serialized/qcp/parsed";
	writeFile(parsedLoc, "");
	qcp1 = getQCP("QCP1", queryMap = loadQueryMap(), withFunctionQueries = true);
	mixed = getQCP("QCP4", queryMap = loadQueryMap(), withFunctionQueries = true);
	mixed += getQCP("QCP2", queryMap = loadQueryMap(), withFunctionQueries = true);
	
	int parseErrorsQCP1 = 0;
	int unknownQueriesQCP1 = 0;
	int parseErrorsQCP4 = 0;
	int unknownQueriesQCP4 = 0;	
	
	
	for(q <- qcp1){
		appendToFile(parsedLoc,"<q.sql>\n<q.parsed>\n<q.callloc>\n\n");
		if(q.parsed is parseError) parseErrorsQCP1 = parseErrorsQCP1 + 1;
		if(q.parsed is unknownQuery) unknownQueriesQCP1 = unknownQueriesQCP1 + 1; 
	}
	for(q <- mixed){
		appendToFile(parsedLoc,"<q.mixedQuery>\n<q.parsed>\n<q.callloc>\n\n");
		if(q.parsed is parseError){
			println(q.callloc);
			parseErrorsQCP4 = parseErrorsQCP4 + 1;
		}
		if(q.parsed is unknownQuery) unknownQueriesQCP4 = unknownQueriesQCP4 + 1; 
	}
	
	println("Out of <size(qcp1)> QCP1 query parse attempts, <unknownQueriesQCP1> were an unknown query type and <parseErrorsQCP1> did not parse.");
	println("Out of <size(mixed)> Dynamic(QCP2 and QCP4) query parse attempts, <unknownQueriesQCP4> were an unknown query type and <parseErrorsQCP4> did not parse.");
}

@doc{counts the number of each query type in the corpus}
public rel[str, int] countQueryTypes(QueryMap queryMap = ( )){
	if (size(queryMap) == 0) {
		queryMap = loadQueryMap();
	}
	
	queries = [q | sys <- queryMap, queries := queryMap[sys], q <- queries];
	parsed = [q.parsed | q <- queries, q is QCP1a || q is QCP1b || q is QCP2 || q is QCP4a || q is QCP4b || q is QCP4c];
	
	return {
		<"SELECT querys", size([p | p <- parsed, p is selectQuery])>,
		<"UPDATE querys", size([p | p <- parsed, p is updateQuery])>,
		<"INSERT querys", size([p | p <- parsed, p is insertQuery])>,
		<"DELETE querys", size([p | p <- parsed, p is deleteQuery])>,
		<"SET querys", size([p | p <- parsed, p is setQuery])>,
		<"DROP querys", size([p | p <- parsed, p is dropQuery])>,
		<"ALTER querys", size([p | p <- parsed, p is alterQuery])>,
		<"REPLACE querys", size([p | p <- parsed, p is replaceQuery])>,
		<"TRUNCATE querys", size([p | p <- parsed, p is truncateQuery])>,
		<"Queries with unknown type", size([p | p <- parsed, p is unknownQuery])>,
		<"Parse Errors", size([p | p <- parsed, p is parseError])>
	};
}

@doc{returns true if this string represents a query hole}
public bool isQueryHole(str queryPart) = /^\?\d+$/ := trim(queryPart);

@doc{returns the number of query holes found in the subject string}
public int holesInString(str subject){
	res = 0;
	
	possibleMatches = findAll(subject, "?");

	// for each possible match (? character), check if the next character or the next two characters make up a number
	// (making the reasonable assumption that all queries have <=99 holes)
	for(p <- possibleMatches){
		try{
			int d = toInt(substring(subject, p + 1, p + 3));
			res = res + 1;
			continue;
		}
		catch: {
			try{
				int d = toInt(substring(subject, p + 1, p + 2));
				res = res + 1;
				continue;
			}
			catch: {
				continue;
			}
		}	
	}
	
	return res;
}

@doc{traverses the queryMap and classifies the query holes contained in each SQLQuery}
public map[str, int] classifyQueryHoles(QueryMap queryMap = ( )){
	if (size(queryMap) == 0) {
		queryMap = loadQueryMap();
	}
	
	queries = [q | sys <- queryMap, queries := queryMap[sys], q <- queries];
	queriesWithHoles = [q | q <- queries, q is QCP2 || q is QCP4a || q is QCP4b || q is QCP4c];
	
	// hole in select expression such as SELECT ?0 ...
	int selectHole = 0;
	
	// hole in FROM such as ... FROM ?0 ...
	int fromHole = 0;
	
	// hole in tables in UPDATE query such as UPDATE ?0 ...
	int updateTableHole = 0;
	
	// hole in table name in INTO query such as INTO ?0
	int intoTableHole = 0;
	
	// hole in INTO columns
	int intoColumnHole = 0;
	
	// hole in group by column name
	int groupByHole = 0;
	
	// hole in order by column name
	int orderByHole = 0;
	
	// hole in limit
	int limitHole = 0;
	
	// hole in join type
	int joinTypeHole = 0;
	
	// hole in join expression (table name)
	int joinExpHole = 0;
	
	// hole in USING clause of a join (column name)
	int usingHole = 0;
	
	// hole in LHS of Set operation
	int setOpLHSHole = 0;
	
	// hole in RHS of Set operation
	int setOpRHSHole = 0;
	
	// hole in LHS of ON DUPLICATE SET...
	int duplicateSetOpLHSHole = 0;
	
	// hole in RHS of ON DUPLICATE SET...
	int duplicateSetOpRHSHole = 0;
	
	// hole in VALUES clause
	int valuesHole = 0;
	
	// map representing the counts of different hole types in conditions
	map[str, int] conditionHoles = (
		"Comparison LHS": 0,
		"Comparison Op": 0,
		"Comparison RHS": 0,
		"Between Expr": 0,
		"Between Lower": 0,
		"Between Upper": 0,
		"IS NULL Expr": 0,
		"IN Expr": 0,
		"IN Values": 0,
		"LIKE Expr": 0,
		"LIKE Pattern": 0
	);
	
	void classifySelectQueryHoles(SQLQuery query)
		= classifySelectQueryHoles(query.selectExpressions, query.from, query.where, query.group, query.having, query.order, query.limit, query.joins);
		
	void classifySelectQueryHoles(list[Exp] selectExpressions, list[Exp] from, Where where, GroupBy group, Having having, OrderBy order, Limit limit, list[Join] joins){
		for(s <- selectExpressions){
				if(hole(_) := s) selectHole += 1;
		}
		for(f <- from){
			if(hole(_) := f)  fromHole += 1;
		}
			
		if(!(where is noWhere)){
			conditionHoles = classifyConditionHoles(conditionHoles, where.condition);
		}
			
		if(!(group is noGroupBy)){
			for(<exp, mode> <- group.groupings){
				if(hole(_) := exp){
					groupByHole += 1;
				}
			}
		}
			
		if(!(having is noHaving)){
			conditionHoles = classifyConditionHoles(conditionHoles, having.condition);
		}
			
		if(!(order is noOrderBy)){
			for(<exp, mode> <- order.orderings){
				if(hole(_) := exp){
					orderByHole += 1;
				}
			}
		}
			
		if(!(limit is noLimit)){
			if(isQueryHole(limit.numRows)) limitHole += 1;
			
			if(limit is limitWithOffset && isQueryHole(limit.offset)){
				limitHoles += 1;
			}	
		}
			
		for(j <- joins){
			if(isQueryHole(j.joinType)) joinTypeHole += 1;
			if(hole(_) := j.joinExp) joinExpHole += 1;
			if(j is joinOn){
				conditionHoles = classifyConditionHoles(conditionHoles, j.on);
				continue;
			}
			if(j is joinUsing){
				for(u <- using){
					usingHole += holesInString(u);
				}
			}	
		}
	}
	
	void classifyUpdateQueryHoles(SQLQuery query)
		=  classifyUpdateQueryHoles(query.tables, query.setOps, query.where, query.order, query.limit);
		
	void classifyUpdateQueryHoles(list[Exp] tables, list[SetOp] setOps, Where where, OrderBy order, Limit limit){
		for(t <- tables){
			if(hole(_) := t){
				updateTableHole += 1;
			}
		}
		for(s <- setOps){
			setOpLHSHole += holesInString(s.column);
			setOpRHSHole += holesInString(s.newValue);
		}
		if(!(where is noWhere)){
			conditionHoles = classifyConditionHoles(conditionHoles, where.condition);
		}
		if(!(order is noOrderBy)){
			for(<exp, mode> <- order.orderings){
				if(hole(_) := exp){
					orderByHole += 1;
				}
			}
		}
		if(!(limit is noLimit)){
			if(isQueryHole(limit.numRows)) limitHole += 1;
			
			if(limit is limitWithOffset && isQueryHole(limit.offset)){
				limitHoles += 1;
			}
		}
	}
	
	void classifyInsertQueryHoles(SQLQuery query)
		= classifyInsertQueryHoles(query.into, query.values, query.setOps, query.select, query.onDuplicateSetOps);
	
	void classifyInsertQueryHoles(Into into, list[list[str]] values, list[SetOp] setOps, SQLQuery select, list[SetOp] onDuplicateSetOps){
		if(!(into is noInto)){
			if(hole(_) := into.dest) intoTableHole += 1;
			for(c <- into.columns){
				intoColumnHole += holesInString(c);
			}
		}	
		for(valueList <- values, v <- valueList){
			valuesHole += holesInString(v);
		}
		for(s <- setOps){
			setOpLHSHole += holesInString(s.column);
			setOpRHSHole += holesInString(s.newValue);
		}
		if(!(select is noQuery)){
			classifySelectQueryHoles(select);
		}
		for(s <- onDuplicateSetOps){
			duplicateSetOpLHSHole += holesInString(s.column);
			duplicateSetOpRHSHole += holesInString(s.newValue);
		}
	}	
	
	map[str, int] classifyConditionHoles(map[str, int] counts, Condition condition){
		if(condition is and || condition is or || condition is xor){
			counts = classifyConditionHoles(counts, condition.left);
			counts = classifyConditionHoles(counts, condition.right);
		}
		else if(condition is not){
			counts = classifyConditionHoles(condition.negated);
		}
		else{
			cond = condition.condition;
			if(cond is simpleComparison){
				counts["Comparison LHS"] += holesInString(cond.left);
				counts["Comparison Op"] += holesInString(cond.op);
				counts["Comparison RHS"] += holesInString(cond.rightExp);
			}
			if(cond is compoundComparison){
				counts["Comparison LHS"] += holesInString(cond.left);
				counts["Comparison Op"] += holesInString(cond.op);
				counts = classifyConditionHoles(counts, cond.rightCondition);
			}
			if(cond is between){
				counts["Between Expr"] += holesInString(cond.exp);
				counts["Between Lower"] += holesInString(cond.lower);
				counts["Between Upper"] += holesInString(cond.upper);
			}
			if(cond is isNull){
				counts["IS NULL Expr"] += holesInString(cond.exp);
			}
			if(cond is inValues){
				counts["IN Expr"] += holesInString(cond.exp);
				for(v <- cond.values){
					counts["IN Values"] += holesInString(v);
				}	
			}
			if(cond is inSubquery){
				classifySelectQueryHoles(cond.subquery);
			}
			if(cond is like){
				counts["LIKE Expr"] += holesInString(cond.exp);
				counts["LIKE Pattern"] += holesInString(cond.pattern);
			}
		}
		return counts;
	}
	
	for(query <- queriesWithHoles){
		if(query.parsed is selectQuery){
			classifySelectQueryHoles(query.parsed);
		}
		else if(query.parsed is updateQuery){
			classifyUpdateQueryHoles(query.parsed);
		}
		else if(query.parsed is insertQuery){
			classifyInsertQueryHoles(query.parsed);
		}
	}
	
	return(
		"SELECT Expr": selectHole,
		"FROM": fromHole,
		"GROUP BY": groupByHole,
		"ORDER BY": orderByHole,
		"LIMIT": limitHole,
		"JOIN Type ": joinTypeHole,
		"JOIN Expr": joinExpHole,
		"USING": usingHole,
		"UPDATE Table" : updateTableHole,
		"SET LHS" : setOpLHSHole,
		"SET RHS" : setOpRHSHole,
		"DUPLICATE SET LHS" : duplicateSetOpLHSHole,
		"DUPLICATE SET RHS" : duplicateSetOpRHSHole,
		"INTO Table" : intoTableHole,
		"INTO Column" : intoColumnHole,
		"VALUES" : valuesHole
		
	) + conditionHoles;
}