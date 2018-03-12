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

@doc{query comes from function/method parameter}
public str qcp4 = "function query";

@doc{model represents a query type other than select, insert, update, delete}
public str otherType = "other query type";

@doc{pattern cannot be determined due to a parse error (ideally, this shouldnt occur)}
public str parseError = "parse error";

@doc{model matches no patterns (yet, ideally this shouldnt occur)}
public str unknown = "unknown";

@doc{map containing all QCPs, for easy access to QCP names}
public map[str, str] QCPs = (
	"qcp0" 	: "static", 
	"qcp1" 	: "dynamic parameters",
	"qcp2" 	: "dynamic",
	"qcp3a" : "multiple yields, same parsed query",
	"qcp3b" : "multiple yields, same query type",
	"qcp3c" : "multiple yields, different query types",
	"qcp4" : "function query",
	"otherType" : "other query type",
	"parseError" : "parse error",
	"unknown" : "unknown"
	);

@doc{maximum number of times to invoke the parser}
public int maxYields = 1000;

@doc{"ranking" for each pattern indicating ease of transformation}
// note: qcp3 is not included as its score requires some computation
public map[str, int] rankings = (qcp0 : 0, qcp1 : 1, qcp2 : 2, qcp4: 3, unknown : 0, parseError : 0,
	otherType : 0);

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
		return rankings[classifyYield(theYield[0], theYield[2])];
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
		
@doc{groups the counts of each QCP by system}
public map[tuple[str,str], map[str, int]] groupPatternCountsBySystem(){
	res = ( );
	Corpus corpus = getCorpus();
	for(p <- corpus, v := corpus[p]){
		res += (<p, v> : countPatternsInSystem(p, v));
	}
	res += (<"total" , "0.0"> : countPatternsInCorpus());
	
	return res;
}
		
@doc{group models based on pattern from the whole corpus}
public map[str, SQLModelRel] groupSQLModelsCorpus(){

	res = ();
	Corpus corpus = getCorpus();
	
	void addModelsWithPattern(str pattern, map[str, SQLModelRel] models){
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
		patterns = [qcp0, qcp1, qcp2, qcp3a, qcp3b, qcp3c, unknown, parseError, otherType];
		for(pattern <- patterns){
			addModelsWithPattern(pattern, models);
		}
	}
	return res;	
}

@doc{group models in a whole system based on pattern}
public map[str, SQLModelRel] groupSQLModels(str p, str v){
	map[str, SQLModelRel] res = ( );
	models = getModels(p, v);
	
	for(model <- models){
		pattern = classifySQLModel(model);
		if(pattern in res){
			res[pattern] += {model};
		}
		else{
			res += (pattern : {model});
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
		parsedYieldTuple = getOneFrom(modelInfo.yieldsRel);
		return classifyYield(parsedYieldTuple[0], parsedYieldTuple[2]);
	}
	else{
		return classifyQCP3Query(modelInfo.yieldsRel, modelInfo.info);
	}
}

@doc{determines which sub pattern a QCP3 query belongs to}
public str classifyQCP3Query(rel[SQLYield, str, SQLQuery] parsedYields, YieldInfo info){
	if(otherQueryType(t) := info){
		return t == "parseError" ? parseError : otherType;
	}
	
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
	
	if(size(yield) == 1){
		if(head(yield) is staticPiece){
			return qcp0;
		}
		// TODO: this only hanles the basic case where a single function parameter provides the value
		// of the whole query
		if(head(yield) is namePiece || head(yield) is dynamicPiece){
			return qcp4;
		}
	}
	
	if(parsed is parseError){
		return parseError;
	}
	
	if(!(parsed is selectQuery || parsed is insertQuery || parsed is updateQuery || parsed is deleteQuery)){
		return otherType;
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

data ClauseComp = different(set[&T] clauses)
				| same(&T clause)
				| none();
				   
@doc{for yields of the same type, represents information about how the parsed yields differ}  
data ClauseInfo = selectClauses(ClauseComp select, ClauseComp from, ClauseComp where, 
					ClauseComp groupBy, ClauseComp having, ClauseComp orderBy, 
					ClauseComp limit, ClauseComp joins)
				| updateClauses(ClauseComp tables, ClauseComp setOps, 
					ClauseComp where, ClauseComp orderBy, ClauseComp limit)
				| insertClauses(ClauseComp into, ClauseComp values, ClauseComp setOps, 
					ClauseComp select, ClauseComp onDuplicateSetOps)
				| deleteClauses(ClauseComp from, ClauseComp using, ClauseComp where, 
					ClauseComp orderBy, ClauseComp limit)
				| otherQueryType(str queryType);

@doc{represents the differences in yields for a specific set of model yields}
data YieldInfo = sameType(ClauseInfo clauseInfo)
			   | differentTypes(set[str] types);				

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
	res = selectClauses(none(), none(), none(), none(), none(), none(), none(), none());
	
	for(p <- parsed){
		if(hasClause(p.selectExpressions)) res.select = compareClauses(p.selectExpressions, res.select);
		if(hasClause(p.from))	res.from = compareClauses(p.from, res.from);
		if(hasClause(p.where))	res.where = compareClauses(p.where, res.where);
		if(hasClause(p.group))	res.groupBy = compareClauses(p.group, res.groupBy);
		if(hasClause(p.having)) res.having = compareClauses(p.having, res.having);
		if(hasClause(p.order))	res.orderBy = compareClauses(p.order, res.orderBy);
		if(hasClause(p.limit))	res.limit = compareClauses(p.limit, res.limit);
		if(hasClause(p.joins))	res.joins = compareClauses(p.joins, res.joins);
	}
	
	return sameType(res);
}
private YieldInfo compareYields("updateQuery", set[SQLQuery] parsed){
	res = updateClauses(none(), none(), none(), none(), none());
	
	someYield = getOneFrom(parsed);
	for(p <- parsed){
		if(hasClause(p.tables))	res.tables = compareClauses(p.tables, res.tables);
		if(hasClause(p.setOps))	res.setOps = compareClauses(p.setOps, res.setOps);
		if(hasClause(p.where))	res.where = compareClauses(p.where, res.where);
		if(hasClause(p.order))	res.orderBy = compareClauses(p.order, res.orderBy);
		if(hasClause(p.limit))	res.limit = compareClauses(p.limit, res.limit);
	}
	
	return sameType(res);
}
private YieldInfo compareYields("insertQuery", set[SQLQuery] parsed){
	res = insertClauses(none(), none(), none(), none(), none());
	
	for(p <- parsed){
		if(hasClause(p.into))	res.into = compareClauses(p.into, res.into);
		if(hasClause(p.values)) res.values = compareClauses(p.values, res.values);
		if(hasClause(p.setOps)) res.setOps = compareClauses(p.setOps, res.setOps);
		if(hasClause(p.select)) res.select = compareClauses(p.select, res.select);
		if(hasClause(p.onDuplicateSetOps)) 
			res.onDuplicateSetOps = compareClauses(p.onDuplicateSetOps, res.onDuplicateSetOps);
	}
	
	return sameType(res);
}
private YieldInfo compareYields("deleteQuery", set[SQLQuery] parsed){
	res = deleteClauses(none(), none(), none(), none(), none());
	
	for(p <- parsed){
		if(hasClause(p.from)) res.from = compareClauses(p.from, res.from);
		if(hasClause(p.using)) res.using = compareClauses(p.using, res.using);
		if(hasClause(p.where)) res.where = compareClauses(p.where, res.where);
		if(hasClause(p.order)) res.orderBy = compareClauses(p.order, res.orderBy);
		if(hasClause(p.limit)) res.limit = compareClauses(p.limit, res.limit);
	}
	
	return sameType(res);
}

private YieldInfo compareYields(str queryType, set[SQLQuery] parsed){
	return sameType(otherQueryType(queryType));
}

private ClauseComp compareClauses(&T newClause, ClauseComp clauseComp){
	switch(clauseComp){
		case none()  : return same(newClause);
		case same(c) : return c == newClause ? clauseComp : different({c, newClause});
		case different(c) : return different(c + {newClause});
	}
}

@doc{checks whether a given clause exists (list type clauses)}
private bool hasClause(list[&T] clause) = [] !:= clause;

@doc{checks whether a given clause exists (non list type clauses)}
private bool hasClause(&T clause) = !(clause is noWhere || clause is noGroupBy || clause is noHaving 
				|| clause is noOrderBy || clause is noLimit || clause is noQuery);

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
			parsed = getOneFrom(model.yieldsRel)[2];
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
				for(p <- model.yieldsRel[2]){
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
			if(!(clauses.where is none)) info.selectInfo.numWhere += 1;
			if(!(clauses.groupBy is none)) info.selectInfo.numGroupBy += 1;
			if(!(clauses.having is none)) info.selectInfo.numHaving += 1;
			if(!(clauses.orderBy is none)) info.selectInfo.numOrderBy += 1;
			if(!(clauses.limit is none)) info.selectInfo.numLimit += 1;
			if(!(clauses.joins is none)) info.selectInfo.numJoin += 1;
		}
		else if(clauses is updateClauses){
			info.updateInfo.numUpdateQueries += 1;
			if(!(clauses.where is none)) info.updateInfo.numWhere += 1;
			if(!(clauses.orderBy is none)) info.updateInfo.numOrderBy += 1;
			if(!(clauses.limit is none)) info.updateInfo.numLimit += 1;
		}
		else if(clauses is insertClauses){
			info.insertInfo.numInsertQueries += 1;
			if(!(clauses.values is none)) info.insertInfo.numValues += 1;
			if(!(clauses.setOps is none)) info.insertInfo.numSetOp += 1;
			if(!(clauses.select is none)) info.insertInfo.numSelect += 1;
			if(!(clauses.onDuplicateSetOps is none)) info.insertInfo.numOnDuplicate += 1;
		}
		else if(clauses is deleteClauses){
			info.deleteInfo.numDeleteQueries += 1;
			if(!(clauses.using is none)) info.deleteInfo.numUsing += 1;
			if(!(clauses.where is none)) info.deleteInfo.numWhere += 1;
			if(!(clauses.orderBy is none)) info.deleteInfo.numOrderBy += 1;
			if(!(clauses.limit is none)) info.deleteInfo.numLimit += 1;
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
			 
@doc{extracts info about a dynamic query's holes}
public HoleInfo extractHoleInfo(selectQuery(selectExpr, from, where, group, having, order, limit, joins)){
	res = ("name" : 0, "param" : 0, "condition" : 0);
	
	// TODO: refactor some of this into methods, other query types have the same clauses
	
	for(s <- selectExpr){
		res["name"] += holesInExpr(s);
	}
	
	for(f <- from){
		res["name"] += holesInExpr(f);
	}
	
	
	if(!(where is noWhere)){
		res["condition"] += extractConditionHoleInfo(where.condition);
	}
	
	if(!(group is noGroupBy)){
		for(<exp, mode> <- group.groupings){
			res["name"] += holesInExpr(exp);
		}
	}
	
	if(!(having is noHaving)){
		res["condition"] += extractConditionHoleInfo(having.condition);
	}
	
	res["name"] += extractOrderByHoleInfo(order);
	
	res["param"] += extractLimitHoleInfo(limit);
	
	for(j <- joins){
		res["name"] += holesInString(j.joinType);
		res["name"] += holesInExpr(j.joinExp);
		if(j is joinOn){
			res["condition"] += extractConditionHoleInfo(j.on);
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
		res["name"] += holesInExpr(t);
	}
	
	setOpInfo = extractSetOpHoleInfo(setOps);
	res["name"] += setOpInfo[0];
	res["param"] += setOpInfo[1];
	
	if(!(where is noWhere)){
		res["condition"] += extractConditionHoleInfo(where.condition);
	}
	
	res["name"] += extractOrderByHoleInfo(order);
	
	res["param"] += extractLimitHoleInfo(limit);
	
	return res;
}
public HoleInfo extractHoleInfo(insertQuery(into, values, setOps, select, onDuplicate)){
	res = ("name" : 0, "param" : 0, "condition" : 0);
	
	if(!(into is noInto)){
		res["name"] += holesInExpr(into.dest);
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
		res["name"] += holesInExpr(f);
	}
	
	for(u <- using){
		res["name"] += holesInString(u);
	}
	
	if(!(where is noWhere)){
		res["condition"] += extractConditionHoleInfo(where.condition);
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

private int extractConditionHoleInfo(condition(simpleComparison(left, op, right))){
	return holesInString(left) + holesInString(right);
}	
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

private int extractConditionHoleInfo(condition(like(_, exp, pattern)))
	= holesInString(exp) + holesInString(pattern);

private default int extractConditionHoleInfo(condition){ 
 	println( "unhandled condition type encountered : <condition>");
 	return 0;
} 

private int extractOrderByHoleInfo(OrderBy order){
	res = 0;
	if(!(order is noOrderBy)){
		for(<exp, mode> <- order.orderings){
			res += holesInExpr(exp);
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

@doc{returns the number of holes in an expression}
public int holesInExpr(Exp expr){
	switch(expr){
		case literal(s) : return holesInString(s);
		case call(s) : return holesInString(s);
		case unknownExp(s) : return holesInString(s);
		case aliased(e, s) : return holesInExpr(e) + holesInString(s);
		case name(column(c)) : return holesInString(c);
		case name(table(t)) : return holesInString(t);
		case name(database(d)) : return holesInString(d);
		case name(tableColumn(t, c)) : return holesInString(t) + holesInString(c);
		case name(databaseTable(d, t)) : return holesInString(d) + holesInString(t);
		case name(databaseTableColumn(d, t, c)) : return holesInString(d) + holesInString(t) + holesInString(c);
		default: return 0;
	}
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