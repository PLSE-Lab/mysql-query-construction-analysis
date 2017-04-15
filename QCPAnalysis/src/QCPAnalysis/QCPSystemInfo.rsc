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

import QCPAnalysis::QCPCorpus;

import IO;
import ValueIO;
import Relation;

data QCPSystemInfo = qcpSystemInfo(
	System sys, 
	map[loc,map[loc,CFG]] systemCFGs, 
	rel[loc callLoc, str methodName, Expr methodCall] methodCalls,
	rel[loc callLoc, str functionName, Expr functionCall] functionCalls,
	InvertedCallGraph cg,
	IncludesInfo iinfo
	);

public QCPSystemInfo extractQCPSystemInfo(System s) {
	map[loc,map[loc,CFG]] systemCFGs = ( );
	for (l <- s.files) {
		systemCFGs[l] = buildCFGs(s.files[l], buildBasicBlocks=false);
	}
	methodCalls = { < mc@at, methodName, mc > | /mc:methodCall(_,name(name(methodName)),_) := s };
	functionCalls = { < c@at, functionName, c > | /c:call(name(name(functionName)),_) := s };
	
	invertedCallGraph = invert(computeSystemCallGraph(s));
	
	IncludesInfo iinfo = loadIncludesInfo(s.name, s.version);
	
	return qcpSystemInfo(s, systemCFGs, methodCalls, functionCalls, invertedCallGraph, iinfo);
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