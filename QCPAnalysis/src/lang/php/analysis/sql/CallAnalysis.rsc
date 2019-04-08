module lang::php::analysis::sql::CallAnalysis

import lang::php::ast::System;
import lang::php::ast::AbstractSyntax;
import lang::php::util::Utils;
import lang::php::util::Config;
import lang::php::analysis::cfg::CFG;
import lang::php::analysis::cfg::Label;
import lang::php::analysis::cfg::Util;
import lang::php::analysis::usedef::UseDef;
import lang::php::pp::PrettyPrinter;

import lang::php::analysis::sql::QCPCorpus;
import lang::php::analysis::sql::QCPSystemInfo;
import lang::php::analysis::sql::SQLModel;
import lang::php::analysis::sql::ModelAnalysis;
import lang::php::analysis::sql::WriteResults;
import lang::php::analysis::sql::SQLAnalysis;

import IO;
import ValueIO;
import List;
import Set;

alias CallRel = rel[str systemName, str callName, Expr callExpr, loc at];

private set[str] queryFunctions = { "mysql_query", "mysqli_query" };
private set[str] queryMethods = { "query" };

public CallRel getQueryFunctionCalls(System pt) {
	if (! (pt has name)) {
		throw "Should only use named systems";
	}
	
	return { < pt.name, cn, c, c@at > | /c:call(name(name(str cn)),_) := pt, cn in queryFunctions};
}

public CallRel getQueryMethodCalls(System pt) {
	if (! (pt has name)) {
		throw "Should only use named systems";
	}
	
	return { < pt.name, cn, c, c@at > | /c:methodCall(_, name(name(str cn)),_) := pt, cn in queryMethods};
}

public CallRel getDBInstantiations(System pt) {
	if (! (pt has name)) {
		throw "Should only use named systems";
	}
	
	return { < pt.name, "mysqli", c, c@at > | /c:new(explicitClassName(name("mysqli")),_) := pt};
}

public CallRel getCorpusQueryFunctionCalls() {
	currentSystems = getSQLSystems();
	CallRel res = { };
	
	for (s <- currentSystems) {
		pt = loadBinary(s, "current");
		res = res + getQueryFunctionCalls(pt);
	}
	
	return res;
}

public CallRel getCorpusQueryMethodCalls() {
	currentSystems = getSQLSystems();
	CallRel res = { };
	
	for (s <- currentSystems) {
		pt = loadBinary(s, "current");
		res = res + getQueryMethodCalls(pt);
	}
	
	return res;
}

public CallRel getCorpusDBInstantiations() {
	currentSystems = getSQLSystems();
	CallRel res = { };
	
	for (s <- currentSystems) {
		pt = loadBinary(s, "current");
		res = res + getDBInstantiations(pt);
	}
	
	return res;
}

private loc callInfoLoc = baseLoc + "serialized/sql/callinfo";

public void writeCorpusQueryFunctionCalls(CallRel callRel) {
	writeBinaryValueFile(callInfoLoc + "function-calls.info", callRel, compression=false);
}

public CallRel readCorpusQueryFunctionCalls() {
	return readBinaryValueFile(#CallRel, callInfoLoc + "function-calls.info");
}

public void writeCorpusQueryMethodCalls(CallRel callRel) {
	writeBinaryValueFile(callInfoLoc + "method-calls.info", callRel, compression=false);
}

public CallRel readCorpusQueryMethodCalls() {
	return readBinaryValueFile(#CallRel, callInfoLoc + "method-calls.info");
}

public void writeDBNewCalls(CallRel callRel) {
	writeBinaryValueFile(callInfoLoc + "db-new.info", callRel, compression=false);
}

public CallRel readDBNewCalls() {
	return readBinaryValueFile(#CallRel, callInfoLoc + "db-new.info");
}

public void writeCorpusFilteredQueryMethodCalls(CallRel callRel) {
	writeBinaryValueFile(callInfoLoc + "filtered-method-calls.info", callRel, compression=false);
}

public CallRel readCorpusFilteredQueryMethodCalls() {
	return readBinaryValueFile(#CallRel, callInfoLoc + "filtered-method-calls.info");
}

public CallRel filterMethodCalls(CallRel methodCalls, CallRel dbnew, bool useHeuristics=true) {
	invalidTargets = { "$db1", "$h", "$i", "$this-\>pDO()", "$db1", "$this-\>biz[\'db\']",
					   "$this-\>_link", "$Dom", "$dom", "$domxpath", "$dxpath",
					   "$htmlDom", "$mypdo", "$pDO", "$pdo", "$request", "$this-\>pdo",
					   "$this-\>query", "$this-\>xpath", "$xPath", "$xp", "$this", "$xpath"
					 };
	invalidSystems = { "magento-mirror" };
	
	invalidTargetCalls = { <sn,cn,ce,at> | <sn,cn,ce,at> <- methodCalls, pp(ce.target) in invalidTargets };
	invalidParamCalls = { <sn,cn,ce,at> | <sn,cn,ce,at> <- methodCalls, size(ce.parameters) == 0 || size(ce.parameters) > 2 };
	moodleOtherCalls = { <sn,cn,ce,at> | <sn,cn,ce,at> <- methodCalls, sn == "moodle", propertyFetch(var(name(name("this"))),name(name("mysqli"))) !:= ce.target };
	otherDBCalls = { <sn,cn,ce,at> | <sn,cn,ce,at> <- methodCalls, /sqlite/i := at.path || /pdo/i := at.path 
		|| /adminer/i := at.path || "fbi.php" == at.file || /sqlserver/i := at.path || /oracle/i := at.path || /postgres/i := at.path };
	invalidSystemCalls = { <sn,cn,ce,at> | <sn,cn,ce,at> <- methodCalls, sn in invalidSystems };
	heuristics = invalidTargetCalls + invalidParamCalls + moodleOtherCalls + otherDBCalls + invalidSystemCalls;
	
	dbNewSystems = dbnew<0>;
	callsInSystems = { <sn, cn, ce, at> | <sn, cn, ce, at> <- methodCalls, sn in dbNewSystems };
	
	if (useHeuristics) {	
		return callsInSystems - heuristics;
	} else {
		return callsInSystems;
	}
}

public CallRel getMethodCallTargets(CallRel methodCalls) {
	return { <sn,cn,ct,at> | <sn,cn,methodCall(ct,_,_),at> <- methodCalls };
}

public rel[Name,DefExpr] targetDefiners(QCPSystemInfo qcpi, Expr callExpr) {
	loc callLoc = callExpr@at;
	inputSystem = qcpi.sys;
	inputCFGLoc = findContainingCFGLoc(inputSystem.files[callLoc.top], qcpi.systemCFGs[callLoc.top], callLoc);
	inputCFG = findContainingCFG(inputSystem.files[callLoc.top], qcpi.systemCFGs[callLoc.top], callLoc);
	iinfo = qcpi.iinfo;
	inputNode = findNodeForExpr(inputCFG, callLoc);

	< qcpi, d > = getDefs(qcpi, callLoc.top, inputCFGLoc);
	< qcpi, u > = getUses(qcpi, callLoc.top, inputCFGLoc);
	
	filteredDefs = { };
	for ( < un, uat > <- u[inputNode.l], dexp <- (d[uat, un])<0> ) {
		filteredDefs = filteredDefs + < un, dexp > ;
	}
	return filteredDefs;
}

alias CallWithDefRel = rel[str systemName, str callName, Expr callExpr, loc at, Name exprName, DefExpr definers];

public CallWithDefRel definersForCalls(CallRel methodCalls) {
	systems = sort(toList(methodCalls<0>));
	res = { };
	for (s <- systems) {
		println("Checking system <s>");
		qcpi = readQCPSystemInfo(s, "current");
		for (<cn,ce,at> <- methodCalls[s]) {
			println("Checking call at <at>");
			callTargetDefs = targetDefiners(qcpi,ce);
			for (< ctname, ctdef > <- callTargetDefs) {
				res = res + < s, cn, ce, at, ctname, ctdef >;
			}
		}
	}
	return res;
}

public map[str, int] callsBySystem(CallRel methodCalls) {
	map[str,int] res = ( s : 0 | s <- methodCalls<0> );
	for (<s,mn,c,cl> <- methodCalls) res[s] = res[s] + 1;
	return res;
}

public data QueryWrapper
	= functionWrapper(str wrapperName, str paramName, int queryParamPos, loc wrapperLoc, str wrappedFunction, loc wrappedCallLoc)
	| methodWrapper(str wrapperName, str paramName, int queryParamPos, loc wrapperLoc, str wrappedFunction, loc wrappedCallLoc)
	| staticMethodWrapper(str wrapperClass, str wrapperName, str paramName, int queryParamPos, loc wrapperLoc, str wrappedFunction, loc wrappedCallLoc)
	;

public set[QueryWrapper] findWrappers(System pt, set[loc] methodLocs = { }, bool filterLocs = true) {
	// First, get all the query function and method calls
	queryCalls = 
		{ < "mysql_query", pn, c@at > | /c:call(name(name("mysql_query")),[actualParameter(var(name(name(pn))),_,_),_*]) := pt } +
		{ < "mysqli_query", pn, c@at > | /c:call(name(name("mysqli_query")),[_,actualParameter(var(name(name(pn))),_,_),_*]) := pt } +
		{ < "query", pn, c@at > | /c:methodCall(_, name(name("query")),[actualParameter(var(name(name(pn))),_,_),_*]) := pt, (filterLocs ? c@at in methodLocs : true ) };
		
	// Second, get the functions that contain them
	functionWrappers = { functionWrapper(fn, pn, indexOf(plist,p), f@at, cn, at) | 
		/f:function(fn,_,plist,_,_) := pt,  < cn, pn, at > <- queryCalls, at.path == f@at.path, at < f@at, [_*,p:param(pn,_,_,_,_),_*] := plist };
	
	// Third, get the methods that contain them
	methodWrappers = { }; staticMethodWrappers = { };
	for (/m:method(mn,mods,_,plist,_,_) := pt, < cn, pn, at > <- queryCalls, at.path == m@at.path, at < m@at, [_*,p:param(pn,_,_,_,_),_*] := plist) {
		if (static() in mods) {
			for (/c:class(cln,_,_,_,_) := pt, c@at.path == m@at.path, m@at < c@at) { 
				staticMethodWrappers = staticMethodWrappers + staticMethodWrapper(cln, mn, pn, indexOf(plist,p), m@at, cn, at);
			}
		} else {
			methodWrappers = methodWrappers + methodWrapper(mn, pn, indexOf(plist,p), m@at, cn, at);
		}
	}
		
	// Last, return the query wrapper information for all the calls
	return functionWrappers + methodWrappers + staticMethodWrappers;
}

public map[str, set[QueryWrapper]] findWrappers(CallRel methodLocs, bool filterLocs = true) {
	currentSystems = getSQLSystems();
	map[str, set[QueryWrapper]] res = ( );
	
	for (s <- currentSystems) {
		pt = loadBinary(s, "current");
		res[s] = findWrappers(pt, methodLocs = ((methodLocs[s])<2>), filterLocs = filterLocs);
	}
	
	return res;
}

alias WrapperMap = map[str, set[QueryWrapper]];

public void writeWrapperMap(WrapperMap wrapperMap) {
	writeBinaryValueFile(callInfoLoc + "wrapper-map.info", wrapperMap, compression=false);
}

public WrapperMap readWrapperMap() {
	return readBinaryValueFile(#WrapperMap, callInfoLoc + "wrapper-map.info");
}

public rel[str e, loc at] queryCallTargets(CallRel queryCalls) {
	return { < pp(e.target), at > | < _, _, e, at > <- queryCalls };
}

public map[str,int] getDefaultQueryFunctionParamPositions() {
	return ( "mysql_query" : 0, "mysqli_query" : 1 );
} 

public map[str,int] getDefaultQueryMethodParamPositions() {
	return ( "query" : 0 );
}

public CallRel wrapperFunctionCalls(System pt, set[QueryWrapper] wrappers, bool checkParams = true) {
	CallRel res = { };
	for (w <- wrappers) {
		if (functionWrapper(str wrapperName, _, _, _, _, _) := w) {
			if (!checkParams) {
				res = res + { < pt.name, wrapperName, c, c@at > | /c:call(name(name(wrapperName)),_) := pt };
			} else {
				res = res + { < pt.name, wrapperName, c, c@at > | /c:call(name(name(wrapperName)),actuals) := pt, w.queryParamPos < size(actuals) };
			}
		}
	}
	return res;
}

public CallRel wrapperMethodCalls(System pt, set[QueryWrapper] wrappers, bool checkParams = true) {
	CallRel res = { };
	for (w <- wrappers) {
		if (methodWrapper(str wrapperName, _, _, _, _, _) := w) {
			if (!checkParams) {
				res = res + { < pt.name, wrapperName, c, c@at > | /c:methodCall(_, name(name(wrapperName)),_) := pt };
			} else {
				res = res + { < pt.name, wrapperName, c, c@at > | /c:methodCall(_, name(name(wrapperName)),actuals) := pt, w.queryParamPos < size(actuals) };
			}
		}
	}
	return res;
}

public CallRel wrapperStaticCalls(System pt, set[QueryWrapper] wrappers, bool checkParams = true) {
	CallRel res = { };
	for (w <- wrappers) {
		if (staticMethodWrapper(str wrapperClass, str wrapperName, _, _, _, _, _) := w) {
			if (!checkParams) {
				res = res + { < pt.name, wrapperName, c, c@at > | /c:staticCall(name(name(wrapperClass)), name(name(wrapperName)),_) := pt };
			} else {
				res = res + { < pt.name, wrapperName, c, c@at > | /c:staticCall(name(name(wrapperClass)), name(name(wrapperName)),actuals) := pt, w.queryParamPos < size(actuals) };
			}
		}
	}
	return res;
}

public void writeWrapperFunctionCalls(CallRel wrapperCalls) {
	writeBinaryValueFile(callInfoLoc + "wrapper-function-calls.info", wrapperCalls, compression=false);
}

public CallRel readWrapperFunctionCalls() {
	return readBinaryValueFile(#CallRel, callInfoLoc + "wrapper-function-calls.info");
}

public void writeWrapperMethodCalls(CallRel wrapperCalls) {
	writeBinaryValueFile(callInfoLoc + "wrapper-method-calls.info", wrapperCalls, compression=false);
}

public CallRel readWrapperMethodCalls() {
	return readBinaryValueFile(#CallRel, callInfoLoc + "wrapper-method-calls.info");
}

public void writeWrapperStaticCalls(CallRel wrapperCalls) {
	writeBinaryValueFile(callInfoLoc + "wrapper-static-calls.info", wrapperCalls, compression=false);
}

public CallRel readWrapperStaticCalls() {
	return readBinaryValueFile(#CallRel, callInfoLoc + "wrapper-static-calls.info");
}

public CallRel wrapperFunctionCalls(set[str] systems, WrapperMap wrapperMap, set[str] excludes = defaultExcludes) {
	CallRel res = { };
	
	for (s <- systems, s notin excludes) {
		// Load the system being analyzed
		System pt = loadBinary(s, "current");
	
		// Get the wrappers for this system
		wrappers = wrapperMap[s];
		
		// Get the call locs for wrapped calls
		res = res + wrapperFunctionCalls(pt, wrappers);
	}
	
	return res;
}

public CallRel wrapperMethodCalls(set[str] systems, WrapperMap wrapperMap, set[str] excludes = defaultExcludes) {
	CallRel res = { };
	
	for (s <- systems, s notin excludes) {
		// Load the system being analyzed
		System pt = loadBinary(s, "current");
	
		// Get the wrappers for this system
		wrappers = wrapperMap[s];
		
		// Get the call locs for wrapped calls
		res = res + wrapperMethodCalls(pt, wrappers);
	}
	
	return res;
}

public CallRel wrapperStaticCalls(set[str] systems, WrapperMap wrapperMap, set[str] excludes = defaultExcludes) {
	CallRel res = { };
	
	for (s <- systems, s notin excludes) {
		// Load the system being analyzed
		System pt = loadBinary(s, "current");
	
		// Get the wrappers for this system
		wrappers = wrapperMap[s];
		
		// Get the call locs for wrapped calls
		res = res + wrapperStaticCalls(pt, wrappers);
	}
	
	return res;
}

public rel[loc, SQLModel] buildQueryModels(str systemName, CallRel queryCalls, WrapperMap wrapperMap, bool buildForWrappers = true) {
	// Load the system being analyzed
	System pt = loadBinary(systemName, "current");
	
	// Get just the call locs for this system
	standardLocs = queryCalls[systemName]<2>;
	
	// Get the wrappers for this system
	wrappers = wrapperMap[systemName];
	
	// Get the call locs for wrapped calls
	wrappedCallsRel = wrapperCalls(pt, wrappers);
	wrappedLocs = wrappedCallsRel[systemName]<2>;
	
	// Build the parameter maps
	functionParams = ( "mysql_query" : 0, "mysqli_query" : 1 );
	methodParams = ( "query" : 0 );
	staticParams = ( );
	for (wr <- wrappers) {
		if (wr is functionWrapper) {
			functionParams[wr.wrapperName] = wr.queryParamPos;
		} else if (wr is methodWrapper && wr.wrapperName notin methodParams) {
			methodParams[wr.wrapperName] = wr.queryParamPos;
		} else if (wr is staticMethodWrapper) {
			staticParams[< wr.wrapperClass, wr.wrapperName >] = wr.queryParamPos;
		}
	}
	
	// Build the models for the system
	callLocs = buildForWrappers ? (standardLocs + wrappedLocs) : standardLocs;
	res = buildModelsForSystem(systemName, "current", pt, callLocs, functionParams, methodParams, staticParams);
	writeModels(systemName, "current", res);	
	
	return res;
}

public rel[loc, SQLModel] buildQueryModels(CallRel queryCalls, WrapperMap wrapperMap, bool buildForWrappers = true, bool overwrite=false, set[str] excludes = defaultExcludes) {
	currentSystems = getSQLSystems();
	rel[loc, SQLModel] res = { };
	
	for (s <- currentSystems, s notin excludes) {
		if (!overwrite && modelsFileExists(s, "current")) {
			res = res + readModels(s, "current");
		} else {
			res = res + buildQueryModels(s, queryCalls, wrapperMap);
		}
	}
	
	return res;
}

// Build the SQL ASTs for each model
public void buildSQLInfo(set[str] systems, bool overwrite=false, set[str] excludes = defaultExcludes) {
	for (s <- systems, s notin excludes) {
		if (!exists(analysisLoc + "<s>-current.bin") || overwrite) {
			getModels(s, "current");
		}
	}  
}

public rel[loc callLoc, SQLModel sqm, FragmentCategories fc] computeFragmentCategories(rel[loc,SQLModel] models) {
	return computeForRelation(models);
} 

public void generateFCForSystem(str s) {
	models = readModels(s,"current");
	fcrel = computeForRelation(models);
	writeFC(s,"current",fcrel);
}

public void generateFCForAllSystems(set[str] systems, set[str] excludes = defaultExcludes) {
	for (s <- systems, s notin excludes) {
		println("Generating Fragment Categories for <s>");
		generateFCForSystem(s);
	}
}

public rel[loc callLoc, SQLModel sqm, FragmentCategories fc] getFCForSystem(str s) {
	return readFC(s, "current");
}

public void writeCorpusFC(rel[loc callLoc, SQLModel sqm, FragmentCategories fc] fcrel) {
	writeFC(fcrel);
}

public FCMap readCorpusFC(set[str] systems, set[str] excludes = defaultExcludes) {
	FCMap fcMap = ( );
	for (s <- systems, s notin excludes) {
		fcMap[s] = readFC(s,"current");
	}
	return fcMap;
}

public str generateCorpusTable() { 
	return top20CorpusAsLatexTable(78, 91839, 10657061);
}

public CallCountInfo countsInfoForSystem(str systemName, CallRel calls, CallRel wrapperCalls, WrapperMap wrapperMap) {
	systemCalls = calls[systemName];
	
	// Direct calls
	mysqlCalls = size(systemCalls["mysql_query"]);
	mysqliCalls = size(systemCalls["mysqli_query"]);
	queryCalls = size(systemCalls["query"]);
	
	// Get the wrappers for this system
	wrappers = wrapperMap[systemName];
	
	// Indirect calls
	indirectFunctionCalls = size({ wc | wc <- wrapperCalls[systemName], wc[1] is call });
	indirectMethodCalls = size({ wc | wc <- wrapperCalls[systemName], wc[1] is methodCall || wc[1] is staticCall });

	return callCountInfo(mysqlCalls, mysqliCalls, queryCalls, indirectFunctionCalls, indirectMethodCalls);		
}

public CountsMap countsInfoForSystems(set[str] systems, CallRel calls, CallRel wrapperCalls, WrapperMap wrapperMap, set[str] excludes = defaultExcludes) {
	CountsMap res = ( );
	
	for (s <- systems, s notin excludes) {
		res[s] = countsInfoForSystem(s, calls, wrapperCalls, wrapperMap);
	}
	
	return res;
}

public void writeCountsMap(CountsMap countsMap) {
	writeBinaryValueFile(callInfoLoc + "counts-map.info", countsMap, compression=false);
}

public CountsMap readCountsMap() {
	return readBinaryValueFile(#CountsMap, callInfoLoc + "counts-map.info");
}

public CallRel filterCalls(CallRel calls, set[str] excludes = defaultExcludes) {
	return { lt | lt:<s,_,_,_> <- calls, s notin excludes };
}

public CallRel getDefiniteCalls() {
	return readCorpusQueryFunctionCalls() + readWrapperFunctionCalls() + readWrapperStaticCalls();
}

public CallRel getInferredCalls() {
	return readCorpusFilteredQueryMethodCalls() + readWrapperMethodCalls();
}

public CallRel getAllCalls() {
	return getDefiniteCalls() + getInferredCalls();
}