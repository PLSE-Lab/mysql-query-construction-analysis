module QCPAnalysis::QCPSystemInfo

import lang::php::ast::AbstractSyntax;
import lang::php::ast::System;
import lang::php::analysis::cfg::BuildCFG;
import lang::php::analysis::cfg::CFG;
import lang::php::analysis::cfg::Util;
import lang::php::util::Config;
import lang::php::util::Utils;
import lang::php::analysis::NamePaths;
import lang::php::analysis::callgraph::SimpleCG;
import lang::php::analysis::includes::IncludesInfo;
import lang::php::analysis::usedef::UseDef;

import src::lang::php::analysis::sql::QCPCorpus;

import IO;
import ValueIO;
import Relation;

data QCPSystemInfo = qcpSystemInfo(
	System sys, 
	map[loc,map[loc,CFG]] systemCFGs, 
	rel[loc callLoc, str methodName, Expr methodCall] methodCalls,
	rel[loc callLoc, str functionName, Expr functionCall] functionCalls,
	InvertedCallGraph cg,
	IncludesInfo iinfo,
	map[loc,map[loc,Defs]] systemDefs,
	map[loc,map[loc,Uses]] systemUses
	);

public QCPSystemInfo extractQCPSystemInfo(System s, bool buildDefUse = false) {
	map[loc,map[loc,CFG]] systemCFGs = ( );
	for (l <- s.files) {
		systemCFGs[l] = buildCFGs(s.files[l], buildBasicBlocks=false);
	}
	methodCalls = { < mc@at, methodName, mc > | /mc:methodCall(_,name(name(methodName)),_) := s };
	functionCalls = { < c@at, functionName, c > | /c:call(name(name(functionName)),_) := s };
	
	invertedCallGraph = invert(computeSystemCallGraph(s));
	
	IncludesInfo iinfo = loadIncludesInfo(s.name, s.version);
	
	map[loc,map[loc,Defs]] systemDefs = ( );
	map[loc,map[loc,Uses]] systemUses = ( );
	
	if (buildDefUse) {
		for (fileLoc <- systemCFGs) {
			systemDefs[fileLoc] = ( );
			for (cfgLoc <- systemCFGs[fileLoc]) {
				systemDefs[fileLoc][cfgLoc] = definitions(systemCFGs[fileLoc][cfgLoc]);
				systemUses[fileLoc][cfgLoc] = uses(systemCFGs[fileLoc][cfgLoc], systemDefs[fileLoc][cfgLoc]);
			}
		} 
	}
	
	return qcpSystemInfo(s, systemCFGs, methodCalls, functionCalls, invertedCallGraph, iinfo, systemDefs, systemUses);
}

loc qcpLoc = baseLoc + "serialized/qcp/qcpinfo";
 
public void writeQCPSystemInfo(str systemName, str systemVersion, QCPSystemInfo sinfo) {
	writeBinaryValueFile(qcpLoc + "<systemName>-<systemVersion>.info", sinfo, compression=false);
}

public QCPSystemInfo readQCPSystemInfo(str systemName, str systemVersion) {
	return readBinaryValueFile(#QCPSystemInfo, qcpLoc + "<systemName>-<systemVersion>.info");
}

public void extractQCPSystemInfo(str systemName, str systemVersion) {
	pt = loadBinary(systemName, systemVersion);
	writeQCPSystemInfo(systemName, systemVersion, extractQCPSystemInfo(pt));		
}

public void extractQCPSystemInfo() {
	corpus = getCorpus();
	for (systemName <- corpus) {
		extractQCPSystemInfo(systemName, corpus[systemName]);
	}
}

public tuple[QCPSystemInfo qcpi, Defs d] getDefs(QCPSystemInfo qcpi, loc fileLoc, loc cfgLoc) {
	if (qcpi.sys is namedVersionedSystem) {
		return getDefs(qcpi.sys.name, qcpi.sys.version, qcpi, fileLoc, cfgLoc);
	}
	throw "getDefs must be called with the system name and version explicitly provided";
}

public tuple[QCPSystemInfo qcpi, Defs d] getDefs(str systemName, str systemVersion, QCPSystemInfo qcpi, loc fileLoc, loc cfgLoc) {
	if (fileLoc in qcpi.systemDefs && cfgLoc in qcpi.systemDefs[fileLoc]) {
		return < qcpi, qcpi.systemDefs[fileLoc][cfgLoc] >;
	}
	d = definitions(qcpi.systemCFGs[fileLoc][cfgLoc]);
	if (fileLoc notin qcpi.systemDefs) {
		qcpi.systemDefs[fileLoc] = ( );
	}
	qcpi.systemDefs[fileLoc][cfgLoc] = d;
	writeQCPSystemInfo(systemName, systemVersion, qcpi);
	return < qcpi, d >;
}

public tuple[QCPSystemInfo qcpi, Uses u] getUses(QCPSystemInfo qcpi, loc fileLoc, loc cfgLoc) {
	if (qcpi.sys is namedVersionedSystem) {
		return getUses(qcpi.sys.name, qcpi.sys.version, qcpi, fileLoc, cfgLoc);
	}
	throw "getUses must be called with the system name and version explicitly provided";
}

public tuple[QCPSystemInfo qcpi, Uses u] getUses(str systemName, str systemVersion, QCPSystemInfo qcpi, loc fileLoc, loc cfgLoc) {
	if (fileLoc in qcpi.systemUses && cfgLoc in qcpi.systemUses[fileLoc]) {
		return < qcpi, qcpi.systemUses[fileLoc][cfgLoc] >;
	}
	< _, d > = getDefs(qcpi, fileLoc, cfgLoc);
	u = uses(qcpi.systemCFGs[fileLoc][cfgLoc], d);
	if (fileLoc notin qcpi.systemUses) {
		qcpi.systemUses[fileLoc] = ( );
	}
	qcpi.systemUses[fileLoc][cfgLoc] = u;
	writeQCPSystemInfo(systemName, systemVersion, qcpi);
	return < qcpi, u >;
}