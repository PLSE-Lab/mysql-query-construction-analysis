module src::lang::php::analysis::sql::SQLAnalysis

import lang::php::util::Utils;
import lang::php::util::Config;
import lang::php::ast::System;
import lang::php::util::Corpus;
import lang::php::ast::AbstractSyntax;

import src::lang::php::analysis::sql::SQLModel;
import src::lang::php::analysis::sql::QCPSystemInfo;
import QCPAnalysis::ParseSQL::AbstractSyntax;
import QCPAnalysis::ParseSQL::RunSQLParser;
import src::lang::php::analysis::sql::QCPCorpus;

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
public map[str, int] countPatternsInCorpus(Corpus corpus = getCorpus()){
	res = ();
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

	res = (qcp0 : {}, qcp1 : {}, qcp2 : {}, qcp3a : {}, qcp3b : {}, qcp3c : {}, qcp4 : {}, unknown : {}, parseError : {}, otherType : {});
	Corpus corpus = getCorpus();
		
	for(p <- corpus, v := corpus[p]){
		models = groupSQLModels(p, v);
		for(pattern <- models){
			res[pattern] = res[pattern] + models[pattern];
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

	if(parsed is parseError){
		return parseError;
	}
	
	if(parsed is partialStatement){
		if(size(yield) == 1 && (head(yield) is namePiece || head(yield) is dynamicPiece)){
			return qcp4;
		}
		return qcp2;
	}
	
	if(!(parsed is selectQuery || parsed is insertQuery || parsed is updateQuery || parsed is deleteQuery)){
		return otherType;
	}
	
	if(size(yield) == 1){
		if(head(yield) is staticPiece){
			return qcp0;
		}
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

data ClauseComp = different(set[&T] clauses) // this clause differs across yields
				| some(set[&T] clauses)		 // some yields include this clause while others do not
				| same(&T clause)			 // this clause is constant throughout all yields
				| none();					 // no yields contain this clause
				   
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
				| partial(str queryType)
				| otherQueryType(str queryType);

@doc{represents the differences in yields for a specific set of model yields}
data YieldInfo = sameType(ClauseInfo clauseInfo)
			   | differentTypes(set[ClauseInfo] clauseInfos);				

@doc{determine how a set of parsed queries are different}
public YieldInfo compareYields(set[SQLQuery] parsed){
	someType = getName(getOneFrom(parsed));
	types = {getName(p) | p <- parsed};
	
	if(size(types) == 1){
		if(partialStatement(t) := getOneFrom(parsed)){
			return compareYields(t is unknownStatementType ? "unknown" : "partial" + toLowerCase(t.queryType), parsed);
		}
		return compareYields(someType, parsed);
	}
	else{
		typeMap = ( );
		for(p <- parsed){
			aType = "";
			if(partialStatement(t)  := p){
				aType = t is unknownStatementType ? "unknown" : "partial" + toLowerCase(t.queryType);
			}
			else{
				aType = getName(p);
			}
			
			if(aType notin typeMap){
				typeMap += (aType : {p});
			}
			else{
				typeMap[aType] += {p};
			}
		}
		
		comparisons = {compareYields(t, p).clauseInfo | t <- typeMap, p := typeMap[t]};
		// in some cases, one yield is a full query and another is a partial statement. this
		// checks for this to make sure we really have a case of differentTypes
		// if this matches, we throw away the partial yields
		if(partialSameType(comparisons)){
			comparisons = {c | c <- comparisons, !(c is partial)};
			return sameType(getOneFrom(comparisons));
		}
		return differentTypes(comparisons);
	}
}

private bool partialSameType(set[ClauseInfo] comparisons){
	types = {};
	for(c <- comparisons){
		if(partial(t) := c){
			types += t + "Clauses";
		}
		else{
			types += getName(c);
		}
	}
	return size(types) == 1;
}

private YieldInfo compareYields("selectQuery", set[SQLQuery] parsed){
	res = selectClauses(none(), none(), none(), none(), none(), none(), none(), none());
	
	bool firstYield = true;
	for(p <- parsed){
		res.select = compareClauses(p.selectExpressions, res.select, firstYield);
		res.from = compareClauses(p.from, res.from, firstYield);
		res.where = compareClauses(p.where, res.where, firstYield);
		res.groupBy = compareClauses(p.group, res.groupBy, firstYield);
		res.having = compareClauses(p.having, res.having, firstYield);
		res.orderBy = compareClauses(p.order, res.orderBy, firstYield);
		res.limit = compareClauses(p.limit, res.limit, firstYield);
		res.joins = compareClauses(p.joins, res.joins, firstYield);
		firstYield = false;
	}
	
	return sameType(res);
}
private YieldInfo compareYields("updateQuery", set[SQLQuery] parsed){
	res = updateClauses(none(), none(), none(), none(), none());
	
	bool firstYield = true;
	for(p <- parsed){
		res.tables = compareClauses(p.tables, res.tables, firstYield);
		res.setOps = compareClauses(p.setOps, res.setOps, firstYield);
		res.where = compareClauses(p.where, res.where, firstYield);
		res.orderBy = compareClauses(p.order, res.orderBy, firstYield);
		res.limit = compareClauses(p.limit, res.limit, firstYield);
		firstYield = false;
	}
	
	return sameType(res);
}
private YieldInfo compareYields("insertQuery", set[SQLQuery] parsed){
	res = insertClauses(none(), none(), none(), none(), none());
	
	bool firstYield = true;
	for(p <- parsed){
		res.into = compareClauses(p.into, res.into, firstYield);
		res.values = compareClauses(p.values, res.values, firstYield);
		res.setOps = compareClauses(p.setOps, res.setOps, firstYield);
		res.select = compareClauses(p.select, res.select, firstYield);
		res.onDuplicateSetOps = compareClauses(p.onDuplicateSetOps, res.onDuplicateSetOps, firstYield);
		firstYield = false;
	}
	
	return sameType(res);
}
private YieldInfo compareYields("deleteQuery", set[SQLQuery] parsed){
	res = deleteClauses(none(), none(), none(), none(), none());
	
	bool firstYield = true;
	for(p <- parsed){
		res.from = compareClauses(p.from, res.from, firstYield);
		res.using = compareClauses(p.using, res.using, firstYield);
		res.where = compareClauses(p.where, res.where, firstYield);
		res.orderBy = compareClauses(p.order, res.orderBy, firstYield);
		res.limit = compareClauses(p.limit, res.limit, firstYield);
		firstYield = false;
	}
	
	return sameType(res);
}

private YieldInfo compareYields(str queryType, set[SQLQuery] parsed){
	if(queryType == "unknown"){
		return sameType(partial("unknown"));
	}
	if(/partial<x:[a-z]+>/ := queryType){
		return sameType(partial(x));
	}
	return sameType(otherQueryType(queryType));
}

/**
 * State machine:
 *
 * State                        Condition                        New State
 * ----------------------------------------------------------------------
 * none                         firstYield &&                    none
 *                              empty(new clause)
 * ----------------------------------------------------------------------
 * none                         firstYield &&                    same
 *                              !empty(new clause)
 * ----------------------------------------------------------------------
 * none                         !firstYield &&                   none
 *                              empty(new clause)
 * ----------------------------------------------------------------------    
 * none                         !firstYield &&                   some 
 *                              !empty(new clause)            
 * ----------------------------------------------------------------------
 * same                         empty(new clause)                some
 * ----------------------------------------------------------------------
 * same                         new clause == prev clause        same
 * ----------------------------------------------------------------------
 * same                         new clause != prev clause        different
 * ----------------------------------------------------------------------
 * different                    empty(new clause)                some
 * ----------------------------------------------------------------------
 * different                    !empty(new clause)               different
 * ----------------------------------------------------------------------
 * some                         -                                some
 * ----------------------------------------------------------------------                            
 */
private ClauseComp compareClauses(&T newClause, ClauseComp clauseComp, bool firstYield){
	if(firstYield){
		if(!clauseComp is none) throw "illegal start state";
		return hasClause(newClause) ? same(newClause) : none();
	}
	
	switch(clauseComp){
		case none()  : return hasClause(newClause) ? some({newClause}) : none();
		case same(c) : {
			if(!hasClause(newClause)) return some({c});
			else return c == newClause ? same(c) : different({c, newClause});
		} 
		case different(c) : return hasClause(newClause) ? different(c + {newClause}) : some(c);
		case some(c) : return hasClause(newClause) ? some(c + {newClause}) : some(c);
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

alias ClauseCompMap = map[str queryType, map[str clause, tuple[int same, int some, int different, int none] clauses] clauseMap];
alias ClauseCountMap = map[str queryType, map[str, int] clauseCounts];

public ClauseCompMap extractClauseComparison(SQLModelRel models){
	res = buildInitialClauseCompMap();
	void incMap(str queryType, str clause, ClauseComp cc){
		switch(cc){
			case same(_) 	  : res[queryType][clause].same += 1;
			case some(_) 	  : res[queryType][clause].some += 1;
			case different(_) : res[queryType][clause].different += 1;
			case none() 	  : res[queryType][clause].none += 1;
		}
	}
	void incMap("other"){
		res["other"]["count"].same += 1;
	}
	void incMap("partial", s){
		res["partial"][s].same += 1;
	}
	
	void extract(ClauseInfo ci){
		if(selectClauses(select, from, where, groupBy, having, orderBy, limit, joins) := ci){
			pairs = {<"select", select>, <"from", from>, <"where", where>, <"groupBy", groupBy>,
					 <"having", having>, <"orderBy", orderBy>, <"limit", limit>, <"joins", joins>};
			for(<name, clauseComp> <- pairs){
				incMap("select", name, clauseComp);
			}
		} 
		else if(insertClauses(into, values, setOps, select, onDuplicateSetOps) := ci){
			pairs = {<"into", into>, <"values", values>, <"setOps", setOps>, <"select", select>,
					 <"onDuplicateSetOps", onDuplicateSetOps>};
			for(<name, clauseComp> <- pairs){
				incMap("insert", name, clauseComp);
			}
		}
		else if(updateClauses(tables, setOps, where, orderBy, limit) := ci){
			pairs = {<"tables", tables>, <"setOps", setOps>, <"where", where>, <"orderBy", orderBy>, <"limit", limit>};
			for(<name, clauseComp> <- pairs){
				incMap("update", name, clauseComp);
			}
		}
		else if(deleteClauses(from, using, where, orderBy, limit) := ci){
			pairs = {<"from", from>, <"using", using>, <"where", where>, <"orderBy", orderBy>, <"limit", limit>};
			for(<name, clauseComp> <- pairs){
				incMap("delete", name, clauseComp);
			}
		}
		else if(partial(t) := ci){
			incMap("partial", t);
		}
		else{
			incMap("other");
		}
	}
	
	for(model <- models){
		yi = model.info;
		if(yi is sameType){
			ci = model.info.clauseInfo;
			extract(ci);
		}
		else{
			for(ci <- model.info.clauseInfos){
				extract(ci);
			}
		}
	}
	return res;
}

public ClauseCountMap extractClauseCounts(SQLModelRel models){
	res = ( );
	clauseComp = extractClauseComparison(models);
	for(queryType <- clauseComp, clauses := clauseComp[queryType]){
		res += (queryType : ( ));
		for(clause <- clauses, counts := clauses[clause]){
			res[queryType] += (clause : counts.same + counts.some + counts.different);
		}
		
		if(queryType == "partial"){
			res[queryType] += ("total queries" : res[queryType]["select"] + res[queryType]["insert"]
												 + res[queryType]["update"] + res[queryType]["delete"]
												 + res[queryType]["unknown"]);
		}
		// to get the total number of queries of this query type, we can just pick a clause
		// then add up the same/some/different/none counts
		else{
			aClause = getOneFrom(clauses);
			counts = clauses[aClause];
			res[queryType] += ("total queries" : counts.same + counts.some + counts.different + counts.none);
		}
	}
	return res;
}

private ClauseCompMap buildInitialClauseCompMap(){
	zeros = <0,0,0,0>;
	res = (
		"select"  : ("select": zeros, "from": zeros, "where" : zeros, "groupBy" : zeros, "having": zeros, "orderBy": zeros, "limit": zeros, "joins": zeros),
		"insert"  : ("into": zeros, "values": zeros, "setOps": zeros, "select": zeros, "onDuplicateSetOps": zeros),
		"update"  : ("tables": zeros, "setOps": zeros, "where": zeros, "orderBy": zeros, "limit": zeros),
		"delete"  : ("from": zeros, "using": zeros, "where": zeros, "orderBy": zeros, "limit": zeros),
		"partial" : ("select" : zeros, "insert" : zeros, "update" : zeros, "delete" : zeros, "unknown" : zeros),
		"other"   : ("count": zeros)
	);
	
	return res;
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

public SQLModelRel getModelsCorpus(Corpus corpus = getCorpus()){
	res = {};
	for(p <- corpus, v := corpus[p]){
		res = res + getModels(p, v);
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