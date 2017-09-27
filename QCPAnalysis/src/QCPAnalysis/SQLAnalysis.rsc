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

@doc{QCP1 (static query) recognizer}
public bool matchesQCP1(SQLModel model){
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
@doc{QCP2 (mixture of static query text and dynamic inputs)}
public bool matchesQCP2(SQLModel model){
	if(model.startFragment is compositeFragment){
		return true;
	}
	else if(model.startFragment is concatFragment){
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
@doc{QCP3 (query text based on control flow)}
public bool matchesQCP3(SQLModel model){
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


//TODO: split into sub patterns
@doc{classify a single model}
public str classifySQLModel(SQLModel model){
	return matchesQCP1(model) ? "QCP1" : matchesQCP2(model) 
							  ? "QCP2" : matchesQCP3(model) 
							  ? "QCP3" : "unclassified";
}


//public map[str, SQLModelMap] classifySQLModels(SQLModelMap modelMap){
//	loc dotLoc = baseLoc + "/dots";
//	res = ("QCP1" : (), "QCP2" : (), "QCP3" : (),  "QCP4" : (), "unclassified" : ());
//	int modelid = 0;
//	// TODO: other patterns
//	for(model <- modelMap){
//		if(matchesQCP1(model)){
//			res["QCP1"] += (model : modelMap[model]);
//			renderSQLModelAsDot(model, dotLoc + "/qcp1//<modelid>");
//		}
//		else if(matchesQCP2(model)){
//			res["QCP2"] += (model : modelMap[model]);
//			renderSQLModelAsDot(model, dotLoc + "/qcp2/<modelid>");
//			
//		}
//		else if(matchesQCP3(model)){
//			res["QCP3"] += (model : modelMap[model]);
//			renderSQLModelAsDot(model, dotLoc + "/qcp3/<modelid>");
//		}
//		else if(matchesQCP4(model)){
//			res["QCP4"] += (model : modelMap[model]);
//			renderSQLModelAsDot(model, dotLoc + "/qcp4/<modelid>");
//		}
//		else{
//			res["unclassified"] += (model : modelMap[model]);
//			renderSQLModelAsDot(model, dotLoc + "/unclassified/<modelid>");
//			
//		}
//		modelid = modelid + 1;
//	}
//	
//	return res;
//}