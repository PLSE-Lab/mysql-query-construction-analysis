module lang::php::analysis::sql::ModelAnalysis

import lang::php::ast::AbstractSyntax;
import lang::php::ast::System;
import lang::php::util::Utils;
import lang::php::util::Config;
import lang::php::util::Corpus;
import lang::php::analysis::cfg::CFG;

import lang::php::analysis::sql::Utils;
import lang::php::analysis::sql::QCPSystemInfo;
import lang::php::analysis::sql::SQLModel;
import lang::php::analysis::sql::QCPCorpus;

import Set;
import Relation;
import IO;
import ValueIO;

data FragmentCategories = fcat(
	int literals, // string literals
	int localVars, // local variables
	int localArrayVars, // local array variables
	int localProps, // properties of locally-defined variables
	int localComputed, // computed local names
	int globalVars, // global variables
	int globalArrayVars, // global array variables
	int globalProps, // properties of globally-defined variables
	int globalComputed,// computed global names
	int parameterNames, // parameters
	int parameterArrayVars, // parameter array variables
	int parameterProps, // properties of parameters
	int parameterComputed, // computed property names
	int computed // dynamic fragments that are not names
	);

FragmentCategories initFC() = fcat(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);

map[str, int] fcToAbbreviatedMap(fcat(literal, localVars, localArrayVars, localProps, localComputed, globalVars, 
									  globalArrayVars, globalProps, globalComputed, 
										parameterNames, parameterArrayVars, parameterProps, parameterComputed, computed))
	= ("L" : literal, "LV" : localVars, "LP" : localProps, "LC" : localComputed,
	   "GV" : globalVars, "GP" : globalProps, "GC" : globalComputed, 
	   "PN" : parameterNames, "PP" : parameterProps, "PC" : parameterComputed,
	   "C" : computed, "LA" : localArrayVars, "GA" : globalArrayVars, "PA" : parameterArrayVars
	);

public set[QueryFragment] flattenFragment(QueryFragment qf) {
	if (qf is compositeFragment) {
		return { qf } + { *flattenFragment(fi) | fi <- qf.fragments };
	} 
	
	if (qf is concatFragment) {
		return { qf } + flattenFragment(qf.left) + flattenFragment(qf.right);
	}
	
	return { qf };
}

public set[QueryFragment] flattenFragment(set[QueryFragment] qfs) {
	return { *flattenFragment(qf) | qf <- qfs };
}

public FragmentCategories computeFragmentCategories(SQLModel sqm) {
	FragmentCategories fc = initFC();
	fragments = flattenFragment(sqm.fragmentRel<1> + sqm.fragmentRel<4>);
	
	for (fragment <- fragments) {
		switch(fragment) {
			case literalFragment(str lf): {
				fc.literals += 1;
			}
			
			case nameFragment(Name n): {
				switch(n) {
					case varName(_) :
						fc.localVars += 1;
					case computedName(_) :
						fc.localComputed += 1;
					case propertyName(Expr targetObject, str propertyName) :
						fc.localProps += 1;
					case computedPropertyName(Expr targetObject, Expr computedPropertyName) :
						fc.localComputed += 1;
					case staticPropertyName(str className, str propertyName) :
						fc.localProps += 1;
					case computedStaticPropertyName(Expr computedClassName, str propertyName) :
						fc.localComputed += 1;
					case computedStaticPropertyName(str className, Expr computedPropertyName) :
						fc.localComputed += 1;
					case computedStaticPropertyName(Expr computedClassName, Expr computedPropertyName) :
						fc.localComputed += 1;
					case elementName(str varName, str indexName) :
						fc.localArrayVars += 1;
					default:
						throw "Unrecognized name fragment case: <n>";
				}				
			}
			
			case dynamicFragment(_): {
				fc.computed += 1;
			}

			// NOTE: This should never happen if we actually had a literal since
			// that would have been simplified
			case compositeFragment(_): {
				fc.computed += 1;
			}
			
			// NOTE: This should never happen if we actually had a literal since
			// that would have been simplified
			case concatFragment(_): {
				fc.computed += 1;
			}
			
			case inputParamFragment(Name n): {
				switch(n) {
					case varName(_) :
						fc.parameterNames += 1;
					case computedName(_) :
						fc.parameterComputed += 1;
					case propertyName(Expr targetObject, str propertyName) :
						fc.parameterProps += 1;
					case computedPropertyName(Expr targetObject, Expr computedPropertyName) :
						fc.parameterComputed += 1;
					case staticPropertyName(str className, str propertyName) :
						fc.parameterProps += 1;
					case computedStaticPropertyName(Expr computedClassName, str propertyName) :
						fc.parameterComputed += 1;
					case computedStaticPropertyName(str className, Expr computedPropertyName) :
						fc.parameterComputed += 1;
					case computedStaticPropertyName(Expr computedClassName, Expr computedPropertyName) :
						fc.parameterComputed += 1;
					case elementName(str varName, str indexName) :
						fc.parameterArrayVars += 1;
					default:
						throw "Unrecognized input param fragment case: <n>";
				}				
			}
			
			case globalFragment(Name n): {
				switch(n) {
					case varName(_) :
						fc.globalVars += 1;
					case computedName(_) :
						fc.globalComputed += 1;
					case propertyName(Expr targetObject, str propertyName) :
						fc.globalProps += 1;
					case computedPropertyName(Expr targetObject, Expr computedPropertyName) :
						fc.globalComputed += 1;
					case staticPropertyName(str className, str propertyName) :
						fc.globalProps += 1;
					case computedStaticPropertyName(Expr computedClassName, str propertyName) :
						fc.globalComputed += 1;
					case computedStaticPropertyName(str className, Expr computedPropertyName) :
						fc.globalComputed += 1;
					case computedStaticPropertyName(Expr computedClassName, Expr computedPropertyName) :
						fc.globalComputed += 1;
					case elementName(str varName, str indexName) :
						fc.globalArrayVars += 1;
					default:
						throw "Unrecognized global fragment case: <n>";
				}				
			}
			
			case unknownFragment(): {
				fc.computed += 1;
			}
			
		}
	}

	return fc;
}

private loc modelAnalysisLoc = baseLoc + "serialized/qcp/modelanalysis/";

public void writeFC(str systemName, str systemVersion, rel[loc callLoc, SQLModel sqm, FragmentCategories fc] fc) {
	writeBinaryValueFile(analysisLoc + "<systemName>-<systemVersion>.bin", fc);
}

public void writeFC(rel[loc callLoc, SQLModel sqm, FragmentCategories fc] fc) {
	writeBinaryValueFile(analysisLoc + "fc-all-systems.bin", fc);
}

public rel[loc callLoc, SQLModel sqm, FragmentCategories fc] readFC(str systemName, str systemVersion) {
	return readBinaryValueFile(#rel[loc callLoc, SQLModel sqm, FragmentCategories fc], analysisLoc + "<systemName>-<systemVersion>.bin");
}

public rel[loc callLoc, SQLModel sqm, FragmentCategories fc] readFC() {
	return readBinaryValueFile(#rel[loc callLoc, SQLModel sqm, FragmentCategories fc], analysisLoc + "fc-all-systems.bin");
}

public rel[loc callLoc, SQLModel sqm, FragmentCategories fc] computeForSystem(str systemName, str systemVersion, bool useCache=true) {
	rel[loc callLoc, SQLModel sqm, FragmentCategories fc] res = { };
	
	System pt = loadBinary(systemName, systemVersion);
	QCPSystemInfo qcpi = readQCPSystemInfo(systemName, systemVersion);
	rel[loc,SQLModel] models = { };
	if (useCache) {
		models = readModels(systemName, systemVersion);
	}
	allCalls = { < c, c@at > | /c:call(name(name("mysql_query")),_) := pt.files };

	for (< c, l > <- allCalls) {		
		callModel = (l in models<0>) ? getOneFrom(models[l]) : buildModel(qcpi, l);
		fc = computeFragmentCategories(callModel);
		res = res + < l, callModel, fc >;
	}
	
	writeFC(systemName, systemVersion, res);
	return res;	
}

public rel[loc callLoc, SQLModel sqm, FragmentCategories fc] computeForRelation(rel[loc, SQLModel] models) {
	rel[loc callLoc, SQLModel sqm, FragmentCategories fc] res = { };
	
	for ( < l, m > <- models, m is sqlModel ) {
		res = res + < l, m, computeFragmentCategories(m) >;
	}
	
	return res;
}

public map[str system, rel[loc callLoc, SQLModel sqm, FragmentCategories fc] fcrel] computeForCorpus(Corpus corpus = getCorpus()) {
	map[str system, rel[loc callLoc, SQLModel sqm, FragmentCategories fc] fcrel] res = ( );
	for (systemName <- corpus, systemVersion := corpus[systemName]) {
		res[systemName] = computeForSystem(systemName, systemVersion);
	}
	return res;
}

public FragmentCategories sumFC(rel[loc,SQLModel,FragmentCategories] fcrel) {
	FragmentCategories fc = initFC();
	for (< l, sqm, fci > <- fcrel ) {
		fc.literals += fci.literals;
		fc.localVars += fci.localVars;
		fc.localProps += fci.localProps;
		fc.localComputed += fci.localComputed;
		fc.globalVars += fci.globalVars;
		fc.globalProps += fci.globalProps;
		fc.globalComputed += fci.globalComputed;
		fc.parameterNames += fci.parameterNames;
		fc.parameterProps += fci.parameterProps;
		fc.parameterComputed += fci.parameterComputed;
		fc.computed += fci.computed;
		fc.localArrayVars += fci.localArrayVars;
		fc.globalArrayVars += fci.globalArrayVars;
		fc.parameterArrayVars += fci.parameterArrayVars;
	}
	return fc;
}

public map[str, FragmentCategories] sumFCMap(map[str system, rel[loc callLoc, SQLModel sqm, FragmentCategories fc] fcrel] fcmap) {
	map[str,FragmentCategories] res = ( );
	for (s <- fcmap<0>) {
		res[s] = sumFC(fcmap[s]);
	}
	return res;
}

public FragmentCategories totalFCForCorpus(Corpus corpus = getCorpus()){
	fcMap = sumFCMap(computeForCorpus(corpus = corpus));
	total = initFC();
	for(p <- fcMap, fc := fcMap[p]){
		total.literals += fc.literals;
		total.localVars += fc.localVars;
		total.localProps += fc.localProps;
		total.localComputed += fc.localComputed;
		total.globalVars += fc.globalVars;
		total.globalProps += fc.globalProps;
		total.globalComputed += fc.globalComputed;
		total.parameterNames += fc.parameterNames;
		total.parameterProps += fc.parameterProps;
		total.parameterComputed += fc.parameterComputed;
		total.computed += fc.computed;
		total.localArrayVars += fc.localArrayVars;
		total.globalArrayVars += fc.globalArrayVars;
		total.parameterArrayVars += fc.parameterArrayVars;		
	}
	return total;
}