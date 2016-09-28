/* The purpose of this module is to further analyze QG2 occurences.
 * That is, mysql_query calls with literals, variables, unsafe inputs, 
 * function or method calls concatenated or interpolated
 */

module QCPAnalysis::QG2Analysis

import QCPAnalysis::QueryGroups;
import QCPAnalysis::QCPCorpus;

import lang::php::util::Utils;
import lang::php::ast::System;
import lang::php::ast::AbstractSyntax;

import Node;
import Set;
import Map;


// for each Expr type that occurrs in the corpus, reports how many times that type
// occurs in all mysql_query calls that match QG2
public map[str, rel[str, int]] getQG2Counts(){
	map[str, list[Expr]] qg2Corpus = getQG(2);
	set[str] exprTypes = exprTypesInCorpus();
	map[str, rel[str, int]] corpusCounts = ();
	for(sys <- qg2Corpus, qg2System := qg2Corpus[sys]){
		rel[str, int] sysCounts = {};
		sysCounts = { <exprType, count> | exprType <- exprTypes, count := countExprTypeSystem(exprType, qg2System) };
		corpusCounts += (sys : sysCounts);
	}
	return corpusCounts;
}

// reports how many times a particular Expr type occurrs in all QG2 occurrences in a system
private int countExprTypeSystem(str exprType, list[Expr] qg2Calls){
	int count = 0;
	for(call <- qg2Calls){
		params = {p | p <- call.parameters};
		exprTypes  = {getName(e) | /Expr e := params};
		if(exprType in exprTypes){
			count += 1;
		}
	}
	return count;
}

// returns all QG2 occurrences that contain a particular Expr type
public map[str, list[Expr]] getQG2WithExprType(str exprType){
	map[str, list[Expr]] qg2Corpus = getQG(2);
	map[str, list[Expr]] qg2WithExprType = ();
	for(sys <- qg2Corpus, qg2System := qg2Corpus[sys]){
		qg2List = [];
		for(call <- qg2System){
			params = {p | p <- call.parameters};
			exprTypes = {getName(e) | /Expr e := params};
			if(exprType in exprTypes){
				qg2List += call;
			}
		}
		qg2WithExprType += (sys : qg2List);
	}
	return qg2WithExprType;
}