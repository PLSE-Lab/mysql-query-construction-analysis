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

alias SQLModelRel = rel[loc location, SQLModel model, rel[SQLYield, str, SQLQuery] yieldsRel, YieldInfo info];
alias HoleInfo = map[str, int];

public loc analysisLoc = baseLoc + "serialized/qcp/sqlanalysis/";

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

@doc{maximum number of times to invoke the parser}
public int maxYields = 1000;

@doc{"ranking" for each pattern indicating ease of transformation}
// note: qcp3 is not included as its score requires some computation
public map[str, int] rankings = (qcp0 : 0, qcp1 : 1, qcp2 : 2, unknown : 3);

@doc{scores all systems in the corpus}
public map[str, real] rankCorpus(){
	res = ();
	Corpus corpus = getCorpus();
	for(p <- corpus, v := corpus[p]){
		res = res + ("<p>_<v>" : rankSystem(p, v));
	}
	return res;
}

@doc{gets the average score of all models in a system}
public real rankSystem(str p, str v){
	modelsRel = getModels(p, v);
	int count = 0;
	real total = 0.0;
	for(model <- modelsRel){
		//pattern = classifySQLModel(model);
		int score = getRanking(model);
		total += score;
		count = count + 1;
	}
	return total / count;
}

@doc{gets the "ranking" for this model, indicating how easy it will be to transform}
public int getRanking(tuple[loc location, SQLModel model, rel[SQLYield, str, SQLQuery] yieldsRel, 
	YieldInfo info] modelInfo){
	
	pattern = classifySQLModel(modelInfo);
	
	// for qcp3a, check whether this is dynamic parameters or completely dynamic
	if(pattern == qcp3a){
		theYield = getOneFrom(modelInfo.yieldsRel);
		return rankings[classifyYield(theYield[0], theYield[1])];
	}
	
	// for qcp3b and qcp3c, the ranking is the ranking of the "worst" yield
	if(pattern == qcp3b || pattern == qcp3c){
		int max = 0;
		
		for(<yield, parsed> <- modelInfo.yieldsRel){
			int rank = rankings[classifyYield(yield, parsed)];
			if(rank > max) max = rank;
		}
		
		return max;
	}
	
	// otherwise, look up ranking in the map
	return rankings[pattern];
}

@doc{returns the corpus wide counts of each pattern}
public map[str, int] countPatternsInCorpus(){
	res = ();
	Corpus corpus = getCorpus();
	for(p <- corpus, v := corpus[p]){
		sysCounts = countPatternsInSystem(p, v);
		println("<p>, <v>, <sysCounts>");
		for(pattern <- sysCounts, count := sysCounts[pattern]){
			if(pattern in res){
				res[pattern] += count;
			}
			else{
				res = res + (pattern : count);
			}
		}
	}
	
	return res;
}

@doc{return just the counts of each pattern in a system}
public map[str, int] countPatternsInSystem(str p, str v) = (pattern : size([m | m <- models]) | modelMap := groupSQLModels(p, v), 
		pattern <- modelMap, models := modelMap[pattern]);
		
@doc{group models based on pattern from the whole corpus}
public map[str, list[SQLModel]] groupSQLModelsCorpus(){

	res = ();
	Corpus corpus = getCorpus();
	
	void addModelsWithPattern(str pattern, map[str, list[SQLModel]] models){
		if(pattern in models){
			if(pattern in res){
				res[pattern] = res[pattern] + models[pattern];
			}
			else{
				res = res + (pattern : models[pattern]);
			}
		}
		
	}
		
	for(p <- corpus, v := corpus[p]){
		models = groupSQLModels(p, v);
		patterns = [qcp0, qcp1, qcp2, qcp3a, qcp3b, qcp3c, unknown];
		for(pattern <- patterns){
			addModelsWithPattern(pattern, models);
		}
	}
	return res;	
}

@doc{group models in a whole system based on pattern}
public map[str, list[SQLModel]] groupSQLModels(str p, str v){
	res = ( );
	models = getModels(p, v);
	
	for(model <- models){
		pattern = classifySQLModel(model);
		if(pattern in res){
			res[pattern] += model.model;
		}
		else{
			res += (pattern : [model.model]);
		}
	}
	
	return res;
}

@doc{group the location of models corpus wide based on pattern}
public map[str, list[loc]] groupSQLModelLocsCorpus()
	= (pattern : [m.callLoc | m <- models] | modelMap := groupSQLModelsCorpus(), 
		pattern <- modelMap, models := modelMap[pattern]);

@doc{group the locations of models in a whole system based on pattern}
public map[str, list[loc]] groupSQLModelLocs(str p, str v)
	= (pattern : [m.callLoc | m <- models] | modelMap := groupSQLModels(p, v), 
		pattern <- modelMap, models := modelMap[pattern]);

@doc{determine which pattern matches a SQLModel}
public str classifySQLModel(tuple[loc location, SQLModel model, rel[SQLYield, str, SQLQuery] yieldsRel, 
	YieldInfo info] modelInfo){
	
	if(size(modelInfo.yieldsRel) == 1){
		parsedYieldPair = getOneFrom(modelInfo.yieldsRel);
		return classifyYield(parsedYieldPair[0], parsedYieldPair[2]);
	}
	else{
		return classifyQCP3Query(modelInfo.yieldsRel, modelInfo.info);
	}
}

@doc{determines which sub pattern a QCP3 query belongs to}
public str classifyQCP3Query(rel[SQLYield, str, SQLQuery] parsedYields, YieldInfo info){
	// check for the case where all yields lead to the same parsed query (qcp3a)
	if(size(parsedYields<2>) == 1){
		return qcp3a;
	}
	
	// in these cases, the yields actually lead to different parsed queries, so we consult the
	// yield info to see how they differ
	if(info is sameType){
		return qcp3b;
	}
	else{
		return qcp3c;
	}
}

@doc{classify a single yield}
private str classifyYield(SQLYield yield, SQLQuery parsed){
	
	if(size(yield) == 1 && staticPiece(_) := head(yield)){
		return qcp0;
	}
	
	if(hasDynamicPiece(yield)){
		holeInfo = extractHoleInfo(parsed);
		if("name" in holeInfo && holeInfo["name"] > 0){
			return qcp2;
		}
		if("param" in holeInfo && holeInfo["param"] > 0 || "condition" in holeInfo &&
			holeInfo["condition"] > 0){
			return qcp1;
		}
	}
	
	// uncommenting this stops the program when an unknown model is found (for inspection)
	// println(yield);
	// println(runParser(yield2String(yield)));
	// throw "stop";
	
	return unknown;
}

@doc{represents the differences in yields for a specific set of model yields}
// until we actually see QCP3c, differentType will only keep track of what the query types are
data YieldInfo = sameType(ClauseInfo clauseInfo)
			   | differentTypes(set[str] types);
			   
@doc{for yields of the same type, represents information about how the parsed yields differ}  
data ClauseInfo = selectClauses(set[list[Exp]] sameSelectExp, set[list[Exp]] sameFrom, set[Where] sameWhere, 
					set[GroupBy] sameGroupBy, set[Having] sameHaving, set[OrderBy] sameOrderBy, 
					set[Limit] sameLimit, set[list[Join]] sameJoin)
				| updateClauses(set[list[Exp]] sameTables, set[list[SetOp]] sameSetOps, 
					set[Where] sameWhere, set[OrderBy] sameOrderBy, set[Limit] sameLimit)
				| insertClauses(set[Into] sameInto, set[list[list[str]]] sameValues, set[list[SetOp]] sameSetOps, 
					set[SQLQuery] sameSelect, set[list[SetOp]] sameOnDuplicateSetOps)
				| deleteClauses(set[list[Exp]] sameFrom, set[list[str]] sameUsing, set[Where] sameWhere, 
					set[OrderBy] sameOrderBy, set[Limit] sameLimit)
				| otherQueryType(str queryType);
				

@doc{determine how a set of parsed queries are different}
public YieldInfo compareYields(set[SQLQuery] parsed){
	someType = getName(getOneFrom(parsed));
	types = {getName(p) | p <- parsed};
	
	if(size(types) == 1){
		return compareYields(someType, parsed);
	}
	else{
		// todo: collect more information about what this case generally looks like
		return differentTypes(types);
	}
}
private YieldInfo compareYields("selectQuery", set[SQLQuery] parsed){
	res = selectClauses({}, {}, {}, {}, {}, {}, {}, {});
	
	for(p <- parsed){
		res.sameSelectExp = res.sameSelectExp + p.selectExpressions;
		res.sameFrom 	  = res.sameFrom + p.from;
		res.sameWhere 	  = res.sameWhere + p.where;
		res.sameGroupBy   = res.sameGroupBy + p.group;
		res.sameHaving    = res.sameHaving + p.having;
		res.sameOrderBy   = res.sameOrderBy + p.order;
		res.sameLimit     = res.sameLimit + p.limit;
		res.sameJoin      = res.sameJoin + p.joins;
	}
	
	return sameType(res);
}
private YieldInfo compareYields("updateQuery", set[SQLQuery] parsed){
	res = updateClauses({}, {}, {}, {}, {});
	
	someYield = getOneFrom(parsed);
	for(p <- parsed){
		res.sameTables  = res.sameTables + p.tables;
		res.sameSetOps  = res.sameSetOps + p.setOps;
		res.sameWhere   = res.sameWhere + p.where;
		res.sameOrderBy = res.sameOrderBy + p.order;
		res.sameLimit   = res.sameLimit + p.limit;
	}
	
	return sameType(res);
}
private YieldInfo compareYields("insertQuery", set[SQLQuery] parsed){
	res = insertClauses({}, {}, {}, {}, {});
	
	for(p <- parsed){
		res.sameInto 			  = res.sameInto + p.into;
		res.sameValues 			  = res.sameValues + p.values;
		res.sameSetOps 			  = res.sameSetOps + p.setOps;
		res.sameSelect 			  = res.sameSelect + p.select;
		res.sameOnDuplicateSetOps = res.sameOnDuplicateSetOps + p.onDuplicateSetOps;
	}
	
	return sameType(res);
}
private YieldInfo compareYields("deleteQuery", set[SQLQuery] parsed){
	res = deleteClauses({}, {}, {}, {}, {});
	
	for(p <- parsed){
		res.sameFrom    = res.sameFrom + p.from;
		res.sameUsing   = res.sameUsing + p.using;
		res.sameWhere   = res.sameWhere + p.where;
		res.sameOrderBy = res.sameOrderBy + p.order;
		res.sameLimit   = res.sameLimit + p.limit;
	}
	
	return sameType(res);
}
private YieldInfo compareYields(str queryType, set[SQLQuery] parsed){
	return sameType(otherQueryType(queryType));
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
	
@doc{empirical information about a specific query type in a system}
data QueryInfo = selectInfo(int numSelectQueries, int numWhere, int numGroupBy, int numHaving, int numOrderBy, int numLimit, int numJoin)
					 | updateInfo(int numUpdateQueries, int numWhere, int numOrderBy, int numLimit)
					 | insertInfo(int numInsertQueries, int numValues, int numSetOp, int numSelect, int numOnDuplicate)
					 | deleteInfo(int numDeleteQueries, int numUsing, int numWhere, int numOrderBy, int numLimit)
					 | otherInfo(int numOtherQueryTypes);
					 
@doc{empirical information about all query types in a system}					 
data SystemQueryInfo = systemQueryInfo(QueryInfo selectInfo, QueryInfo updateInfo, QueryInfo insertInfo, QueryInfo deleteInfo, int numOtherQueryTypes);
								
@doc{analyzes the queries in a system and returns counts for query types, clauses, etc.}
public SystemQueryInfo collectSystemQueryInfo(str p, str v){
	res = systemQueryInfo(selectInfo(0,0,0,0,0,0,0),
						  updateInfo(0,0,0,0),
						  insertInfo(0,0,0,0,0),
						  deleteInfo(0,0,0,0,0),
						  0);
						  
	models = getModels(p, v);
	
	for(model <- models){
		pattern = classifySQLModel(model);
		if(pattern == qcp0 || pattern == qcp1 || pattern == qcp2 || pattern == qcp3a){
			parsed = getOneFrom(model.yieldsRel)[1];
			res = extractQueryInfo(parsed, res);
		}
		else{
			if(pattern == qcp3b){
				// check the yield info for clauses contained in this model, it is possible
				// one yield contains a clause that another doesnt
				res = extractQueryInfo(model.info, res);
				continue;
			}
			if(pattern == qcp3c){
				//for yields that are different query types, count the clauses of each yield
				for(p <- model.yieldsRel[1]){
					res = extractQueryInfo(p, res);
				}
			}
		}
	}
	
	return res;
}

@doc{extracts clause counts from a QCP3b query. The yield info is consulted as it is possible
	that one yield contains a clause that another yield does not}
private SystemQueryInfo extractQueryInfo(YieldInfo yieldInfo, SystemQueryInfo info){
	if(yieldInfo is sameType){
		clauses = yieldInfo.clauseInfo;
		if(clauses is selectClauses){
			info.selectInfo.numSelectQueries += 1;
			if(hasClause(clauses.sameWhere)) info.selectInfo.numWhere += 1;
			if(hasClause(clauses.sameGroupBy)) info.selectInfo.numGroupBy += 1;
			if(hasClause(clauses.sameHaving)) info.selectInfo.numHaving += 1;
			if(hasClause(clauses.sameOrderBy)) info.selectInfo.numOrderBy += 1;
			if(hasClause(clauses.sameLimit)) info.selectInfo.numLimit += 1;
			if(hasClause(clauses.sameJoin)) info.selectInfo.numJoin += 1;
		}
		else if(clauses is updateClauses){
			info.updateInfo.numUpdateQueries += 1;
			if(hasClause(clauses.sameWhere)) info.updateInfo.numWhere += 1;
			if(hasClause(clauses.sameOrderBy)) info.updateInfo.numOrderBy += 1;
			if(hasClause(clauses.sameLimit)) info.updateInfo.numLimit += 1;
		}
		else if(clauses is insertClauses){
			info.insertInfo.numInsertQueries += 1;
			if(hasClause(clauses.sameValues)) info.insertInfo.numValues += 1;
			if(hasClause(clauses.sameSetOps)) info.insertInfo.numSetOp += 1;
			if(hasClause(clauses.sameSelect)) info.insertInfo.numSelect += 1;
			if(hasClause(clauses.sameOnDuplicateSetOps)) info.insertInfo.numOnDuplicate += 1;
		}
		else if(clauses is deleteClauses){
			info.deleteInfo.numDeleteQueries += 1;
			if(hasClause(clauses.sameUsing)) info.deleteInfo.numUsing += 1;
			if(hasClause(clauses.sameWhere)) info.deleteInfo.numWhere += 1;
			if(hasClause(clauses.sameOrderBy)) info.deleteInfo.numOrderBy += 1;
			if(hasClause(clauses.sameLimit)) info.deleteInfo.numLimit += 1;
		}
		else{
			info.numOtherQueryTypes += 1;
		}
		return info;
	}
	else{
		// TODO: this should handle QCP3c, but this will only be done if this pattern is actually encountered
		return info;
	}
}


@doc{extracts clause counts from a single query (QCP0, QCP1, QCP2, QCP3a)}
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
		info.numOtherQueryTypes += 1;
	}
	return info;
}

@doc{given a clause set from a YieldInfo, determines if any clauses exist in the set}
private bool hasClause(set[list[&T]] clauses){
	if(size(clauses) == 0){
		return false;
	}
	if(size(clauses) > 1){
		return true;
	}
	
	clause = getOneFrom(clauses);
	
	// if this clause is the empty list, it does not exist in any yields
	if([] := clause){
		return false;
	}
	
	return true;
}

@doc{given a clause set from a YieldInfo, determines if any clauses exist in the set}
private bool hasClause(set[&T] clauses){
	if(size(clauses) == 0){
		return false;
	}
	if(size(clauses) > 1){
		return true;
	}

	clause = getOneFrom(clauses);
	//check if the clauses matches non existent clause placeholders
	return !(clause is noWhere || clause is noGroupBy || clause is noHaving || clause is noOrderBy
			|| clause is noLimit || clause is noQuery);	
}
			 
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

private default int extractConditionHoleInfo(condition){ 
 	println( "unhandled condition type encountered");
 	return 0;
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

public SQLModelRel getModels(str p, str v){
	modelsRel = {};
	rel[loc, SQLModel] models; 
	if(exists(analysisLoc + "<p>-<v>.bin")){
 		modelsRel = readBinaryValueFile(#SQLModelRel, analysisLoc + "<p>-<v>.bin");
 	}
 	else{
	 	models = modelsFileExists(p, v) ? readModels(p, v) : buildModelsForSystem(p, v);
 		for(<l,m> <- models){
 			yieldsAndParsed = {};
 			modelYields = yields(m);
 			int i = 0;
 			for(y <- modelYields){
 				 if(i < maxYields){
 				 	 println("yield <i> for call at <l>");
 				 	 sql = yield2String(y);
 				 	 parsed = runParser(sql);
 					 yieldsAndParsed = yieldsAndParsed + <y, sql, parsed>;
 					 i = i + 1;
 				}
 				else{
 					break;
 				}
 			}
 			yieldInfo = compareYields(yieldsAndParsed<2>);
 			modelsRel = modelsRel + <l, m, yieldsAndParsed, yieldInfo>;
 		}
 		writeBinaryValueFile(analysisLoc + "<p>-<v>.bin", modelsRel, compression=false);	
 	}
 	return modelsRel;
}

@doc{rebuilds yields, parsed queries, and yield info for the entire corpus}
public void rebuildYieldInfo(){
	Corpus corpus = getCorpus();
	for(p <- corpus, v := corpus[p]){
		modelsRel = getModels(p, v);
		for(modelInfo <- modelsRel){
			yieldsAndParsed = {};
 			modelYields = yields(modelInfo.model);
 			int i = 0;
 			for(y <- modelYields){
 				if(i < maxYields){
				 	 println("yield <i> for call at <l>");
 				 	 sql = yield2String(y);
 				 	 parsed = runParser(sql);
 					 yieldsAndParsed = yieldsAndParsed + <y, sql, parsed>;
 					 i = i + 1;
 				}
 				else{
 					break;
 				}
 			}
 			yieldInfo = compareYields(yieldsAndParsed<2>);
 			modelInfo.yieldsRel = yieldsAndParsed;
 			modelInfo.info = yieldInfo;
		}
		writeBinaryValueFile(analysisLoc + "<p>-<v>.bin", modelsRel, compression=false);
	}
}