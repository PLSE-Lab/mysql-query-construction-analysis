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

alias SQLModelMap = map[SQLModel model, rel[SQLYield yield, str queryWithHoles, SQLQuery parsed] yieldsRel];

public loc modelLoc = baseLoc + "serialized/qcp/sqlmodels/";

public map[str, SQLModelMap] buildModelsCorpus(){
	res = ( );
	
	Corpus corpus = getCorpus();
	
	for(p <- corpus, v := corpus[p]){
		modelMap = buildModelMap(p, v);
		res = res + ("<p>_<v>" : modelMap);
	}
	
	writeBinaryValueFile(modelLoc + "corpus", res);
	
	return res;
}

public SQLModelMap buildModelMap(str p , str v, rel[loc, SQLModel] modelsRel = {}){
	SQLModelMap res = ( );
	
	System sys = loadBinary(p, v);
	QCPSystemInfo qcpi = readQCPSystemInfo(p, v);
	set[SQLModel] models = {};
	if (isEmpty(modelsRel)) { 
		models = buildModelsForSystem(sys, qcpi)<1>;
	} else {
		models = modelsRel<1>;
	}
	
	for(model <- models){
		res = res + (model : parseYields(yields(model)));
	}
	
	iprintToFile(modelLoc + "<p>_<v>.txt", res);
	writeBinaryValueFile(modelLoc + "<p>_<v>", res);
	
	return res;
}

public map[str, SQLModelMap] readModelsCorpus() = readBinaryValueFile(#map[str, SQLModelMap], modelLoc + "corpus");

public SQLModelMap readModelsSystem(str p, str v) = readBinaryValueFile(#SQLModelMap, modelLoc + "<p>_<v>");

public rel[SQLYield, str, SQLQuery] parseYields(set[SQLYield] yields){
	res = {};
	for(yield <- yields){
		queryString = yield2String(yield);
		
		parsed = runParser(queryString);
		
		res = res + <yield, queryString, parsed>;
	}
	
	return res;
}

@doc{counts the number of calls that have been modeled and the number of yields parsed}
public tuple[int,int] countCallsCorpus(){
	corpusModels = readBinaryValueFile(#map[str, SQLModelMap], modelLoc + "corpus");
	
	numCalls = 0;
	numParsed = 0;
	for(sys <- corpusModels, models := corpusModels[sys]){
		numCalls = numCalls + size(models);
		for(model <- models, parsed := models[model]){
			numParsed = numParsed + size(parsed);
		}
	}
	
	return <numCalls,numParsed>;
}

@doc{static query ecognizer}
public bool matchesLiteral(SQLModel model){
	if(size(model.fragmentRel) == 0 && model.startFragment is literalFragment){
		return true;
	}
	else if(size(model.fragmentRel) == 1 && nameFragment(varName(n)) := model.startFragment){
		possibleLiteral = getOneFrom(model.fragmentRel);
		
		return varName(n) := possibleLiteral.name && possibleLiteral.targetFragment is literalFragment
			&& possibleLiteral.sourceLabel == model.startLabel && possibleLiteral.sourceFragment == model.startFragment;
	}
	else{
		return false;
	}
}

//TODO: split into sub patterns
@doc{Dynamic Query (mixture of static query text and dynamic inputs)}
public bool matchesDynamic(SQLModel model){
	if(model.startFragment is compositeFragment || model.startFragment is concatFragment){
		return true;
	}
	else if(nameFragment(vn:varName(n)) := model.startFragment){
		// first, make sure there is only one edge from the startFragment and that edge leads to a compositeFragment
		// or concatFragment
		edges = {x | x <- model.fragmentRel, vn := x.name};
		if(size(edges) != 1){
			return false;
		}
		else{
			edge = getOneFrom(edges);
			return edge.targetFragment is compositeFragment || edge.targetFragment is concatFragment;
		}
	}
	else{
		return false;
	}
}

//TODO: split into sub patterns
@doc{ControlFlow (query text based on control flow)}
public bool matchesControlFlow(SQLModel model){
	bool foundAMatchingEdge = false;
	bool foundAnotherMatchingEdge = false;
	for(<sourceLabel, sourceFragment, fragmentName, targetName, targetFragment, edgeInfo>
			<- model.fragmentRel){
	
		if(sourceLabel := model.startLabel && sourceFragment := model.startFragment){
			if(foundAMatchingEdge){
				foundAnotherMatchingEdge = true;
			}
			else{
				foundAMatchingEdge = true;
			}
		}
	}
	return foundAMatchingEdge && foundAnotherMatchingEdge;
}

@doc{query comes from a function or method parameter}
public bool matchesFunctionParam(SQLModel model){
	return size(model.fragmentRel) == 1 && 
		<startLabel, nameFragment(n), n, _, inputParamFragment(n), _> := getOneFrom(model.fragmentRel);
}



//TODO: split into sub patterns
@doc{classify a single model}
public str classifySQLModel(SQLModel model){
	return matchesLiteral(model) ? "Literal" : matchesDynamic(model) 
							  ? "Dynamic" : matchesControlFlow(model) 
							  ? "ControlFlow" : matchesFunctionParam(model)
							  ? "FunctionParam" : "unclassified";
}

@doc{group models in a whole system based on pattern}
public map[str ,list[SQLModel]] groupSQLModels(str p, str v){
	res = ( );
	
	pt = loadBinary(p, v);
	
	// Find all calls to the mysql_query function in the system ASTs
	allCalls = { c | /c:call(name(name("mysql_query")),_) := pt.files };
	
	QCPSystemInfo qcpi = readQCPSystemInfo(p, v);
	
	for(aCall <- allCalls){
		callModel = buildModel(qcpi, aCall@at);
		pattern = classifySQLModel(callModel);
		if(pattern in res){
			res[pattern] += callModel;
		}
		else{
			res += (pattern : [callModel]);
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
		
data DynamicQueryInfo = dynamicQueryInfo(
							SQLYield yield,
							SQLQuery parsed,
					  		int numStaticParts,
					  		int numDynamicParts,
					  		HoleInfo holeInfo
					  );

alias HoleInfo = map[str, int];
				 
@doc{further classifies a Dynamic query into sub pattern(s)}
public set[DynamicQueryInfo] classifyDynamicQuery(SQLModel model){
	if(!matchesDynamic(model)){
		throw "error calling classifyDynamicQuery on non dynamic query";
	}
	
	res = {};
	
	for(yield <- yields(model)){
		int staticParts = 0;
		int dynamicParts = 0;
		
		for(piece <- yield){
			if(piece is staticPiece){
				staticParts += 1;
			}
			else{
				dynamicParts += 1;
			}
		}
		parsed = runParser(yield2String(yield));
		
		holeInfo = extractHoleInfo(parsed);
		
		res += dynamicQueryInfo(yield, parsed, staticParts, dynamicParts, holeInfo);
	}
	
	return res;
}

@doc{extracts info about a dynamic query's holes}
public HoleInfo extractHoleInfo(selectQuery(selectExpr, from, where, group, having, order, limit, joins)){
	res = ("name" : 0, "param" : 0);
	
	// TODO: refactor some of this into methods, other query types have the same clauses
	
	for(s <- selectExpr){
		if(hole(_) := s) res["name"] += 1;
	}
	
	for(f <- from){
		if(hole(_) := f)  res["name"] += 1;
	}
	
	
	if(!(where is noWhere)){
		whereInfo = extractConditionHoleInfo(where.condition);
		res["name"] += whereInfo[0];
		res["param"] += whereInfo[1];
	}
	
	if(!(group is noGroupBy)){
		for(<exp, mode> <- group.groupings){
			if(hole(_) := exp){
				res["name"] += 1;
			}
		}
	}
	
	if(!(having is noHaving)){
		havingInfo = extractConditionHoleInfo(having.condition);
		res["name"] += havingInfo[0];
		res["param"] += havingInfo[1];
	}
	
	res["name"] += extractOrderByHoleInfo(order);
	
	res["param"] += extractLimitHoleInfo(limit);
	
	for(j <- joins){
		res["name"] += holesInString(j.joinType);
		if(hole(_) := j.joinExp) res["name"] += 1;
		if(j is joinOn){
			onInfo = extractConditionHoleInfo(on);
			res["name"] += onInfo[0];
			res["param"] += onInfo[1];
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
	res = ("name" : 0, "param" : 0);
	
	for(t <- tables){
		if(hole(_) := t){
			res["name"] += 1;
		}
	}
	
	setOpInfo = extractSetOpHoleInfo(setOps);
	res["name"] += setOpInfo[0];
	res["param"] += setOpInfo[1];
	
	if(!(where is noWhere)){
		whereInfo = extractConditionHoleInfo(where.condition);
		res["name"] += whereInfo[0];
		res["param"] += whereInfo[1];
	}
	
	res["name"] += extractOrderByHoleInfo(order);
	
	res["param"] += extractLimitHoleInfo(limit);
	
	return res;
}
public HoleInfo extractHoleInfo(insertQuery(into, values, setOps, select, onDuplicate)){
	res = ("name" : 0, "param" : 0);
	
	if(!(into is noInto)){
		if(hole(_) := into.dest) res["name"] += 1;
		for(c <- into.columns){
			intoColumnHole += res["name"] += 1;
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
	res = ("name" : 0, "param" : 0);
	
	for(f <- from){
		if(hole(_) := f)  res["name"] += 1;
	}
	
	for(u <- using){
		res["name"] += holesInString(u);
	}
	
	if(!(where is noWhere)){
		whereInfo = extractConditionHoleInfo(where.condition);
		res["name"] += whereInfo[0];
		res["param"] += whereInfo[1];
	}
	
	res["name"] += extractOrderByHoleInfo(order);
	
	res["param"] += extractLimitHoleInfo(limit);
	
	return res;
}
public default HoleInfo extractHoleInfo(SQLQuery query){
	return ("unhandled query type" : 0);
}

private tuple[int nameHoles, int paramHoles] extractConditionHoleInfo(and(left, right)){
	leftHoles = extractConditionHoleInfo(left);
	rightHoles = extractConditionHoleInfo(right);
	return <leftHoles["name"] + rightHoles["name"], leftHoles["param"] + rightHoles["param"]>;
}
private tuple[int nameHoles, int paramHoles] extractConditionHoleInfo(or(left, right)){
	leftHoles = extractConditionHoleInfo(left);
	rightHoles = extractConditionHoleInfo(right);
	return <leftHoles["name"] + rightHoles["name"], leftHoles["param"] + rightHoles["param"]>;
}
private tuple[int nameHoles, int paramHoles] extractConditionHoleInfo(xor(left, right)){
	leftHoles = extractConditionHoleInfo(left);
	rightHoles = extractConditionHoleInfo(right);
	return <leftHoles["name"] + rightHoles["name"], leftHoles["param"] + rightHoles["param"]>;
}
private tuple[int nameHoles, int paramHoles] extractConditionHoleInfo(not(negated)){
	holes = extractConditionHoleInfo(negated);
	return <holes["name"], holes["param"]>;
}

// do we need a case where the comparison operator is a hole? I hope developers dont do this...	
private tuple[int nameHoles, int paramHoles] extractConditionHoleInfo(condition(simpleComparison(left, op, right)))
	= <holesInString(left), holesInString(right)>;
private tuple[int nameHoles, int paramHoles] extractConditionHoleInfo(condition(compoundComparison(left, op, right))){
	rightHoles = extractConditionHoleInfo(right);
	return <holesInString(left) + rightHoles["name"], rightHoles["param"]>;
}

// do we need a case where the NOT is a hole?
private tuple[int nameHoles, int paramHoles] extractConditionHoleInfo(condition(between(_, exp, lower, upper)))
	= <holesInString(exp), holesInString(lower) + holesInString(upper)>;
private tuple[int nameHoles, int paramHoles] extractConditionHoleInfo(condition(isNull(_, exp)))
	= <holesInString(exp), 0>;
private tuple[int nameHoles, int paramHoles] extractConditionHoleInfo(condition(inValues(_, exp, values))){
	res = <0,0>;
	res[0] += holesInString(exp);
	for(v <- values){
		res[1] += holesInString(v);
	}
	return res;
}
private tuple[int nameHoles, int paramHoles] extractConditionHoleInfo(condition(inSubquery(_, exp, subquery))){
	res = <0,0>;
	res[0] += holesInString(exp);
	selectInfo = extractHoleInfo(subquery);
	res[0] += selectInfo["name"];
	res[1] += selectInfo["param"];
	return res;
}
private tuple[int nameHoles, int paramHoles] extractConditionHoleInfo(condition(like(_, exp, pattern)))
	= <holesInString(exp), holesInString(pattern)>;

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
		if(isQueryHole(limit.numRows)) res += 1;
		
		if(limit is limitWithOffset && isQueryHole(limit.offset)){
			res += 1;
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