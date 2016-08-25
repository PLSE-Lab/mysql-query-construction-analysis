/* The purpose of this module is to further analyze QCP2 occurences.
 * That is, mysql_query calls with literals, variables, unsafe inputs, 
 * function or method calls concatenated or interpolated
 */

module QCPAnalysis::QCP2Analysis

import QCPAnalysis::GeneralQCP;
import QCPAnalysis::QCPCorpus;

import lang::php::util::Utils;
import lang::php::ast::System;
import lang::php::ast::AbstractSyntax;

import Node;
import Set;

// for each Expr type that occurrs in the corpus, reports how many times that type
// occurs in all mysql_query calls that match QCP2
public map[str, rel[str, int]] getQCP2Counts(){
	map[str, list[Expr]] qcp2Corpus = getQCP(2);
	set[str] exprTypes = exprTypesInCorpus();
	map[str, rel[str, int]] corpusCounts = ();
	for(sys <- qcp2Corpus, qcp2System := qcp2Corpus[sys]){
		rel[str, int] sysCounts = {};
		sysCounts = { <exprType, count> | exprType <- exprTypes, count := countExprTypeSystem(exprType, qcp2System) };
		corpusCounts += (sys : sysCounts);
	}
	return corpusCounts;
}

// reports how many times a particular Expr type occurrs in all QCP2 occurrences in a system
private int countExprTypeSystem(str exprType, list[Expr] qcp2Calls){
	int count = 0;
	for(call <- qcp2Calls){
		params = {p | p <- call.parameters};
		exprTypes  = {getName(e) | /Expr e := params};
		if(exprType in exprTypes){
			count += 1;
		}
	}
	return count;
}

// returns all QCP2 occurrences that contain a particular Expr type
public map[str, list[Expr]] getQCP2WithExprType(str exprType){
	map[str, list[Expr]] qcp2Corpus = getQCP(2);
	map[str, list[Expr]] qcp2WithExprType = ();
	for(sys <- qcp2Corpus, qcp2System := qcp2Corpus[sys]){
		qcp2List = [];
		for(call <- qcp2System){
			params = {p | p <- call.parameters};
			exprTypes = {getName(e) | /Expr e := params};
			if(exprType in exprTypes){
				qcp2List += call;
			}
		}
		qcp2WithExprType += (sys : qcp2List);
	}
	return qcp2WithExprType;
}