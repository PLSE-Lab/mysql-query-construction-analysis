module QCPAnalysis::SQLAnalysis


import lang::php::util::Utils;
import lang::php::util::Config;
import lang::php::ast::System;
import lang::php::util::Corpus;
import lang::php::ast::AbstractSyntax;

import QCPAnalysis::SQLModel;
import QCPAnalysis::QCPSystemInfo;
import QCPAnalysis::ParseSQL::AbstractSyntax;
import QCPAnalysis::ParseSQL::RunSQLParser;
import QCPAnalysis::QCPCorpus;

import IO;
import ValueIO;
import Set;
import Relation;
import Map;
import String;
import List;
import Node;

alias SQLModelMap = map[SQLModel model, rel[SQLYield yield, str queryWithHoles, SQLQuery parsed] yieldsRel];
alias HoleInfo = map[str, int];

public loc modelLoc = baseLoc + "serialized/qcp/sqlmodels/";

@doc{single yield, single static piece}
public str qcp0 = "static";

@doc{single yield, mixture of static and dynamic pieces, all dynamic pieces are parameters}
public str qcp1 = "dynamic parameters";

@doc{single yield with at least one dynamic piece that is not a parameter}
public str qcp2 = "dynamic";

@doc{query has multiple yields, but all yields lead to the same parsed query}
public str qcp3a = "multiple yields, same parsed query";

@doc{query has multiple yields, all yields are the same type of query (select, insert, etc)}
public str qcp3b = "multiple yields, same query type";

@doc{query has multiple yields, yields are of differing query types}
public str qcp3c = "multiple yields, different query types";

@doc{model matches no patterns}
public str unknown = "unknown";

@doc{"ranking" for each pattern indicating ease of transformation}
// note: qcp3 is not included as its score requires some computation
public map[str, int] rankings = (qcp0 : 0, qcp1 : 1, qcp2 : 2, unknown : 3);

@doc{gets the "ranking" for this model, indicating how easy it will be to transform}
public int getRanking(SQLModel model){
	pattern = classifySQLModel(model);
	
	// for qcp3a, check whether this is dynamic parameters or completely dynamic
	if(pattern == qcp3a){
		yield = getOneFrom(yields(model));
		return rankings[classifyYield(yield)];
	}
	
	// for qcp3b and qcp3c, the ranking is the ranking of the "worst" yield
	if(pattern == qcp3b || pattern == qcp3c){
		int max = 0;
		modelYields = yields(model);
		
		for(yield <- modelYields){
			int rank = rankings[classifyYield(yield)];
			if(rank > max) max = rank;
		}
		
		return max;
	}
	
	// otherwise, look up ranking in the map
	return rankings[pattern];
}

@doc{gets the average score of all models in a system}
public real rankSystem(str p, str v){
	models = getModels(p, v);
	int count = 0;
	real total = 0.0;
 	
	for(<location, model> <- models){
		pattern = classifySQLModel(model);
		int score = getRanking(model);
		total += score;
		count = count + 1;
	}
	
	return total / count;
}

@doc{determine which pattern matches a SQLModel}
public str classifySQLModel(SQLModel model){
	modelYields = yields(model);
	
	if(size(modelYields) == 1){
		return classifyYield(getOneFrom(modelYields));
	}
	else{
		return classifyQCP3Query(modelYields);
	}
}

@doc{determines which sub pattern a QCP3 query belongs to}
public str classifyQCP3Query(set[SQLYield] modelYields){
	parsed = { runParser(yield2String(y)) | y <- modelYields};
	// check if these different yields actually lead to different parsed queries
	// in many cases, the yields only differ in hole source and not query type, clauses, etc.
	if(size(parsed) == 1){
		return qcp3a;
	}
	
	someType = getName(getOneFrom(parsed));
	sameType = (true | it && getName(p) == someType | p <- parsed);
	
	if(sameType){
		return qcp3b;
	}
	else{
		return qcp3c;
	}
}

@doc{classify a single yield}
private str classifyYield(SQLYield yield){
	if(size(yield) == 1 && staticPiece(_) := head(yield)){
		return qcp0;
	}
	
	if(hasDynamicPiece(yield)){
		holeInfo = extractHoleInfo(runParser(yield2String(yield)));
		if(holeInfo["name"] > 0){
			return qcp2;
		}
		if(holeInfo["param"] > 0 || holeInfo["condition"] > 0){
			return qcp1;
		}
	}
	
	// uncommenting this stops the program when an unknown model is found (for inspection)
	// println(yield);
	// println(runParser(yield2String(yield)));
	// throw "stop";
	
	return unknown;
}

@doc{return whether at least one piece in a SQLYield is dynamic}
private bool hasDynamicPiece(SQLYield yield){
	for(piece <- yield){
		if(dynamicPiece() := piece || namePiece(_) := piece){
			return true;
		}
	}
	
	return false;
}

@doc{group models in a whole system based on pattern}
public map[str, list[SQLModel]] groupSQLModels(str p, str v){
	res = ( );
	models = getModels(p, v);
	
	for(<location, model> <- models){
		pattern = classifySQLModel(model);
		if(pattern in res){
			res[pattern] += model;
		}
		else{
			res += (pattern : [model]);
		}
	}
	
	return res;
}

@doc{group the locations of models in a whole system based on pattern}
public map[str, list[loc]] groupSQLModelLocs(str p, str v)
	= (pattern : [m.callLoc | m <- models] | modelMap := groupSQLModels(p, v), 
		pattern <- modelMap, models := modelMap[pattern]);
		
@doc{return just the counts of each pattern in a system}
public map[str, int] countPatternsInSystem(str p, str v) = (pattern : size([m | m <- models]) | modelMap := groupSQLModels(p, v), 
		pattern <- modelMap, models := modelMap[pattern]);
	
data QueryInfo = selectInfo(int numSelectQueries, int numWhere, int numGroupBy, int numHaving, int numOrderBy, int numLimit, int numJoin)
					 | updateInfo(int numUpdateQueries, int numWhere, int numOrderBy, int numLimit)
					 | insertInfo(int numInsertQueries, int numValues, int numSetOp, int numSelect, int numOnDuplicate)
					 | deleteInfo(int numDeleteQueries, int numUsing, int numWhere, int numOrderBy, int numLimit)
					 | otherInfo(int numOtherQueryTypes);
					 
data SystemQueryInfo = systemQueryInfo(QueryInfo selectInfo, QueryInfo updateInfo, QueryInfo insertInfo, QueryInfo deleteInfo, int numOtherQueryTypes);
								
@doc{analyzes the queries in a system and returns counts for query types, clauses, etc.}
public SystemQueryInfo collectSystemQueryInfo(str p, str v){
	res = systemQueryInfo(selectInfo(0,0,0,0,0,0,0),
						  updateInfo(0,0,0,0),
						  insertInfo(0,0,0,0,0),
						  deleteInfo(0,0,0,0,0),
						  0);
						  
	models = getModels(p, v);
	
	for(<l,m> <- models){
		pattern = classifySQLModel(m);
		if(pattern == qcp0 || pattern == qcp1 || pattern == qcp2 || pattern == qcp3a){
			parsed = runParser(yield2String(getOneFrom(yields(m))));
			res = extractQueryInfo(parsed, res);
		}
		else{
			if(pattern == qcp3b){
				// TODO: compare yields, only count once for clauses that are the same
				continue;
			}
			if(pattern == qcp3c){
				// TODO: for yields that are different query types, count the clauses of each yield
				continue;
			}
		}
	}
	
	return res;
}

@doc{extracts clause and query type counts from a single query}
private SystemQueryInfo extractQueryInfo(SQLQuery parsed, SystemQueryInfo info){
	if(parsed is selectQuery){
		info.selectInfo.numSelectQueries += 1;
		if(parsed.where is where) info.selectInfo.numWhere += 1;
		if(parsed.group is groupBy) info.selectInfo.numGroupBy += 1;
		if(parsed.having is having) info.selectInfo.numHaving += 1;
		if(parsed.order is orderBy) info.selectInfo.numOrderBy += 1;
		if(!parsed.limit is noLimit) info.selectInfo.numLimit += 1;
		if(!isEmpty(parsed.joins)) info.selectInfo.numJoin += 1;
	}
	else if(parsed is updateQuery){
		info.updateInfo.numUpdateQueries += 1;
		if(parsed.where is where) info.updateInfo.numWhere += 1;
		if(parsed.order is orderBy) info.updateInfo.numOrderBy += 1;
		if(!parsed.limit is noLimit) info.updateInfo.numLimit += 1;
	}
	else if(parsed is insertQuery){
		info.insertInfo.numInsertQueries += 1;
		if(!isEmpty(parsed.values)) info.insertInfo.numValues += 1;
		if(!isEmpty(parsed.setOps)) info.insertInfo.numSetOp += 1;
		if(parsed.select is selectQuery) info.insertInfo.numSelect += 1;
		if(!isEmpty(parsed.onDuplicateSetOps)) info.insertInfo.numOnDuplicate += 1;
	}
	else if(parsed is deleteQuery){
		info.deleteInfo.numDeleteQueries += 1;
		if(!isEmpty(parsed.using)) info.deleteInfo.numUsing += 1;
		if(parsed.where is where) info.deleteInfo.numWhere += 1;
		if(parsed.order is orderBy) info.deleteInfo.numOrderBy += 1;
		if(!parsed.limit is noLimit) info.deleteInfo.numLimit += 1;
	}
	else{
		info.otherInfo.numOtherQueryTypes += 1;
	}
	return info;
}

//@doc{for queries with multiple yields, extracts query type and clause counts}
//private SystemQueryInfo extractQueryInfo(set[SQLQuery] parsed, SystemQueryInfo info){
//	// first, check if all yields are the same query type
//	someType = getName(getOneFrom(parsed));
//	sameType = (true | it && getName(p) == someType | p <- parsed);
//	
//	// uncommenting this stops the program when a query with multiple possible parsed queries is 
//	// found and prints the parsed yields (for inspection)
//	// iprintln(parsed);
//	// throw "stop";
//	
//	if(sameType){
//		info.otherInfo.numAllYieldsSameType += 1;
//	}
//	else{
//		info.otherInfo.numQueriesWithVaryingTypes += 1;
//	}
//	
//	//TODO: look into this more, see where the yields actually differ
//	
//	return info;
//} 
			 
@doc{extracts info about a dynamic query's holes}
public HoleInfo extractHoleInfo(selectQuery(selectExpr, from, where, group, having, order, limit, joins)){
	res = ("name" : 0, "param" : 0, "condition" : 0);
	
	// TODO: refactor some of this into methods, other query types have the same clauses
	
	for(s <- selectExpr){
		if(hole(_) := s) res["name"] += 1;
	}
	
	for(f <- from){
		if(hole(_) := f)  res["name"] += 1;
	}
	
	
	if(!(where is noWhere)){
		res["condition"] = extractConditionHoleInfo(where.condition);
	}
	
	if(!(group is noGroupBy)){
		for(<exp, mode> <- group.groupings){
			if(hole(_) := exp){
				res["name"] += 1;
			}
		}
	}
	
	if(!(having is noHaving)){
		res["condition"] = extractConditionHoleInfo(having.condition);
	}
	
	res["name"] += extractOrderByHoleInfo(order);
	
	res["param"] += extractLimitHoleInfo(limit);
	
	for(j <- joins){
		res["name"] += holesInString(j.joinType);
		if(hole(_) := j.joinExp) res["name"] += 1;
		if(j is joinOn){
			res["condition"] = extractConditionHoleInfo(j.on);
			continue;
		}
		if(j is joinUsing){
			for(u <- using){
				res["name"] += holesInString(u);
			}
		}	
	}
	
	return res;
}
public HoleInfo extractHoleInfo(updateQuery(tables, setOps, where, order, limit)){
	res = ("name" : 0, "param" : 0, "condition" : 0);
	
	for(t <- tables){
		if(hole(_) := t){
			res["name"] += 1;
		}
	}
	
	setOpInfo = extractSetOpHoleInfo(setOps);
	res["name"] += setOpInfo[0];
	res["param"] += setOpInfo[1];
	
	if(!(where is noWhere)){
		res["condition"] = extractConditionHoleInfo(where.condition);
	}
	
	res["name"] += extractOrderByHoleInfo(order);
	
	res["param"] += extractLimitHoleInfo(limit);
	
	return res;
}
public HoleInfo extractHoleInfo(insertQuery(into, values, setOps, select, onDuplicate)){
	res = ("name" : 0, "param" : 0, "condition" : 0);
	
	if(!(into is noInto)){
		if(hole(_) := into.dest) res["name"] += 1;
		for(c <- into.columns){
			res["name"] += holesInString(c);
		}
	}	
	
	for(valueList <- values, v <- valueList){
		res["param"] += holesInString(v);
	}
	
	setOpInfo = extractSetOpHoleInfo(setOps);
	res["name"] += setOpInfo[0];
	res["param"] += setOpInfo[1];
	
	if(select is selectQuery){
		selectHoleInfo = extractHoleInfo(select);
		res["name"] += selectHoleInfo["name"];
		res["param"] += selectHoleInfo["param"];
	}
	
	duplicateInfo = extractSetOpHoleInfo(onDuplicate);
	res["name"] += duplicateInfo[0];
	res["param"] += duplicateInfo[1];
	
	return res;
}
public HoleInfo extractHoleInfo(deleteQuery(from, using, where, order, limit)){
	res = ("name" : 0, "param" : 0, "condition" : 0);
	
	for(f <- from){
		if(hole(_) := f)  res["name"] += 1;
	}
	
	for(u <- using){
		res["name"] += holesInString(u);
	}
	
	if(!(where is noWhere)){
		res["condition"] = extractConditionHoleInfo(where.condition);
	}
	
	res["name"] += extractOrderByHoleInfo(order);
	
	res["param"] += extractLimitHoleInfo(limit);
	
	return res;
}
public default HoleInfo extractHoleInfo(SQLQuery query){
	return ("unhandled query type" : 0);
}

private int extractConditionHoleInfo(and(left, right)){
	leftHoles = extractConditionHoleInfo(left);
	rightHoles = extractConditionHoleInfo(right);
	return leftHoles + rightHoles;
}
private int extractConditionHoleInfo(or(left, right)){
	leftHoles = extractConditionHoleInfo(left);
	rightHoles = extractConditionHoleInfo(right);
	return leftHoles + rightHoles;
}
private int extractConditionHoleInfo(xor(left, right)){
	leftHoles = extractConditionHoleInfo(left);
	rightHoles = extractConditionHoleInfo(right);
	return leftHoles + rightHoles;
}
private int extractConditionHoleInfo(not(negated)){
	return extractConditionHoleInfo(negated);
}

// do we need a case where the comparison operator is a hole? I hope developers dont do this...	
private int extractConditionHoleInfo(condition(simpleComparison(left, op, right)))
	= holesInString(left) + holesInString(right);
	
private int extractConditionHoleInfo(condition(compoundComparison(left, op, right))){
	rightHoles = extractConditionHoleInfo(right);
	return holesInString(left) + rightHoles;
}

private int extractConditionHoleInfo(condition(between(_, exp, lower, upper)))
	= holesInString(exp) + holesInString(lower) + holesInString(upper);
	
private int extractConditionHoleInfo(condition(isNull(_, exp)))
	= holesInString(exp);
	
private int extractConditionHoleInfo(condition(inValues(_, exp, values))){
	res = 0;
	res  += holesInString(exp);
	for(v <- values){
		res += holesInString(v);
	}
	return res;
}

// revisit this, do we need the distinction between name and param holes that are in subqueries used for filtering?
//private tuple[int nameHoles, int paramHoles] extractConditionHoleInfo(condition(inSubquery(_, exp, subquery))){
//	res = <0,0>;
//	res[0] += holesInString(exp);
//	selectInfo = extractHoleInfo(subquery);
//	res[0] += selectInfo["name"];
//	res[1] += selectInfo["param"];
//	return res;
//}

private int extractConditionHoleInfo(condition(like(_, exp, pattern)))
	= holesInString(exp) + holesInString(pattern);

private default tuple[int nameHoles, int paramHoles] extractConditionHoleInfo(condition){ 
  throw "unhandled condition type encountered"; 
} 

private int extractOrderByHoleInfo(OrderBy order){
	res = 0;
	if(!(order is noOrderBy)){
		for(<exp, mode> <- order.orderings){
			if(hole(_) := exp){
				res += 1;
			}
		}
	}
	return res;
}

private int extractLimitHoleInfo(Limit limit){
	res = 0;
	if(!(limit is noLimit)){
		res += holesInString(limit.numRows);
		if(limit is limitWithOffset){
			res += holesInString(limit.offset);
		}
	}
	return res;
}	

private tuple[int nameHoles, int paramHoles] extractSetOpHoleInfo(list[SetOp] setOps){
	res = <0,0>;
	
	for(s <- setOps){
		res[0] += holesInString(s.column);
		res[1] += holesInString(s.newValue);
	}
	
	return res;
}

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

public rel[loc, SQLModel] getModels(str p, str v){
	models = {};
	if(modelsFileExists(p, v)){
 		models = readModels(p, v);
 	}
 	else{
 		models = buildModelsForSystem(p, v);
 		writeModels(p, v, models);
 	}
 	return models;
}