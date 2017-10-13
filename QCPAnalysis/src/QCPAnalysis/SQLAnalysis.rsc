module QCPAnalysis::SQLAnalysis


import lang::php::util::Utils;
import lang::php::util::Config;
import lang::php::ast::System;
import lang::php::util::Corpus;

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
	
	whereInfo = extractWhereHoleInfo(where);
	res["name"] += whereInfo[0];
	res["param"] += whereInfo[1];
	
	return res;
	
}
public HoleInfo extractHoleInfo(updateQuery(tables, setOps, where, order, limit)){
	res = ("name" : 0, "param" : 0);
	
	// TODO: implement
	
	return res;
}
public HoleInfo extractHoleInfo(insertQuery(into, values, setOps, select, onDuplicate)){
	res = ("name" : 0, "param" : 0);
	
	// TODO: implement
	
	return res;
}
public HoleInfo extractHoleInfo(deleteQuery(from, using, where, order, limit)){
	res = ("name" : 0, "param" : 0);
	
	// TODO: implement
	
	return res;
}
public default HoleInfo extractHoleInfo(SQLQuery query){
	return ("unhandled query type" : 0);
}

public bool isHole(str string) = /^\?\d+$/ := string;

private tuple[int nameHoles, int paramHoles] extractWhereHoleInfo(Where where){
	res = <0,0>;
	top-down visit(where){
		case simpleComparison(left, op, right) : {
			if(isHole(left)) res[0] += 1;
			if(isHole(right)) res[1] += 1;
		}
		case between(not, exp, lower, upper) : {
			if(isHole(exp)) res[0] += 1;
			if(isHole(lower)) res[1] += 1;
			if(isHole(upper)) res[1] += 1;
		}
		case isNull(not, exp) : {
			if(isHole(exp)) res[0] += 1;
		}
		case inValues(not, exp, values) : {
			if(isHole(exp)) res[0] += 1;
			for(v <- values){
				if(isHole(v)) res[1] += 1;
			}
		}
		case like(not, exp, pattern) : {
			if(isHole(exp)) res[0] += 1;
			if(isHole(pattern)) res[1] += 1;
		}
		//todo: other condition types
	}
	return res;
}
