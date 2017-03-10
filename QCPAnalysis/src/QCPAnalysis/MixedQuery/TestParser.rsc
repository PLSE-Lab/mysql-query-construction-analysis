module QCPAnalysis::MixedQuery::TestParser

import lang::php::ast::AbstractSyntax;
import lang::php::ast::System;
import QCPAnalysis::AbstractQuery;
import QCPAnalysis::MixedQuery::ConcreteSyntax;

import ParseTree;
import IO;

public set[Query] parseQueries(list[Query] queries) {
	set[Query] failingQueries = { };
	for (q <- queries, q has sql) {
		println("TEST: Attempting to parse <q.sql>");
		try {
			pt = parse(#SQLQuery,q.sql);
			println("TEST: Parsed successfully");
		} catch e : {
			println("TEST: Parse failed: <e>");
			failingQueries = failingQueries + q;
		}
	}
	
	return failingQueries;
}