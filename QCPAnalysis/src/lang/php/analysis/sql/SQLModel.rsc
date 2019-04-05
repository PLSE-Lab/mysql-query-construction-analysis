module lang::php::analysis::sql::SQLModel

import lang::php::ast::AbstractSyntax;
import lang::php::ast::System;
import lang::php::analysis::cfg::CFG;
import lang::php::analysis::cfg::BuildCFG;
import lang::php::analysis::cfg::Util;
import lang::php::analysis::cfg::FlowEdge;
import lang::php::analysis::cfg::Label;
import lang::php::util::Utils;
import lang::php::analysis::usedef::UseDef;
import lang::php::analysis::slicing::BasicSlicer;
import lang::php::analysis::evaluators::Simplify;
import lang::php::analysis::includes::QuickResolve;
import lang::php::analysis::cfg::Visualize;
import lang::php::pp::PrettyPrinter;
import lang::php::util::Config;
import lang::php::util::Corpus;

import lang::php::analysis::sql::Utils;
import lang::php::analysis::sql::QCPSystemInfo;

import Set;
import IO;
import Relation;
import List;
import Map;
import analysis::graphs::Graph;
import String;
import ValueIO;

// TODO: Currently, this focuses just on function calls. We need to also add
// support for method calls to pick up calls to new APIs, such as the PDO
// libraries.

// Fragment can be
// 1) literal
// 2) name
// 3) dynamic
// 4) list of fragments
// 5) concat
data QueryFragment
	= literalFragment(str literalFragment)
	| nameFragment(Name name)
	| dynamicFragment(Expr fragmentExpr)
	| compositeFragment(list[QueryFragment] fragments)
	| concatFragment(QueryFragment left, QueryFragment right)
	| globalFragment(Name name)
	| inputParamFragment(Name name)
	| unknownFragment()
	;

public str printQueryFragment(literalFragment(str literalFragment)) = "literal: \"<literalFragment>\"";
public str printQueryFragment(nameFragment(Name name)) = "name: <printName(name)>";
public str printQueryFragment(dynamicFragment(Expr fragmentExpr)) = "dynamic: <pp(fragmentExpr)>";
public str printQueryFragment(compositeFragment(list[QueryFragment] fragments)) = "composite: <intercalate(" . ", ["( <printQueryFragment(qf)> )" | qf <- fragments])>";
public str printQueryFragment(concatFragment(QueryFragment left, QueryFragment right)) = "concat: ( <printQueryFragment(left)> ) . ( <printQueryFragment(right)> )";
public str printQueryFragment(globalFragment(Name name)) = "global name: <printName(name)>";
public str printQueryFragment(inputParamFragment(Name name)) = "parameter name: <printName(name)>";
public str printQueryFragment(unknownFragment()) = "unknown";

data EdgeInfo = noInfo() | nameInfo(Name name) | edgeCondsInfo(set[Expr] conds, Lab l);

public str printEdgeInfo(nameInfo(Name name)) = "Name: <printName(name)>";
public str printEdgeInfo(edgeCondsInfo(set[Expr] conds, Lab l)) = "Conditions: <intercalate(",", [pp(e) | e <- conds])>";
public str printEdgeInfo(Name n, set[EdgeInfo] eis) {
	eis = eis - noInfo();
	if (isEmpty(eis)) {
		return "Name: <printName(n)>";
	} else {
		return "Name: <printName(n)>\n<intercalate("\n",[printEdgeInfo(ei) | ei <- eis])>";
	}	
}

alias ContainmentRel = rel[Lab containedNode, set[Expr] preds, Lab containingNode];

alias FragmentRel = rel[Lab sourceLabel, QueryFragment sourceFragment, Name name, Lab targetLabel, QueryFragment targetFragment, EdgeInfo edgeInfo];
data SQLModel = sqlModel(FragmentRel fragmentRel, ContainmentRel containmentRel, QueryFragment startFragment, Lab startLabel, loc callLoc) | emptyModel();

@doc{Turn a specific expression into a possibly-nested query fragment.}
public QueryFragment expr2qf(Expr ex, QCPSystemInfo qcpi, bool simplify=true) {
	QueryFragment expr2qfAux(Expr e) {
		if (simplify) {
			e = simplifyExpr(replaceConstants(e,qcpi.iinfo), qcpi.sys.baseLoc);
		}
		
		switch(e) {
			case scalar(string(s)) :
				return literalFragment(s);
				
			case scalar(encapsed(parts)) : {
				return compositeFragment([expr2qfAux(part) | part <- parts ]);
			}
			
			case binaryOperation(left, right, concat()) :
				return concatFragment(expr2qfAux(left), expr2qfAux(right));
				
			case assignWOp(left, right, concat()) :
				return concatFragment(expr2qfAux(left), expr2qfAux(right));
			
			case var(name(name(vn))) :
				return nameFragment(varName(vn));
			
			case fetchArrayDim(var(name(name(vn))),noExpr()) :
				return nameFragment(varName(vn));

			case fetchArrayDim(var(name(name(vn))),someExpr(idxExpr)) : {
				if (scalar(string(idxName)) := idxExpr) {
					return nameFragment(elementName(vn, idxName));
				} else {
					return nameFragment(varName(vn));
				}
			}
				
			case var(expr(Expr e)) :
				return nameFragment(computedName(e));
			
			case fetchArrayDim(var(expr(Expr e)),_) :
				return nameFragment(computedName(e));
			
			case propertyFetch(target, name(name(vn))) :
				return nameFragment(propertyName(target, vn));
				
			case propertyFetch(target, Expr e) :
				return nameFragment(computedPropertyName(target, e));
			
			case staticPropertyFetch(name(name(target)), name(name(vn))) :
				return nameFragment(staticPropertyName(target, vn));
				
			case staticPropertyFetch(name(name(target)), Expr e) :
				return nameFragment(computedStaticPropertyName(target, e));
			
			case staticPropertyFetch(expr(Expr target), name(name(vn))) :
				return nameFragment(computedStaticPropertyName(target, vn));
				
			case staticPropertyFetch(expr(Expr target), Expr e) :
				return nameFragment(computedStaticPropertyName(target, e));
		
			default:
				return dynamicFragment(e);
		}
	}
	
	return expr2qfAux(ex);
}

public FragmentRel expandFragment(Lab l, QueryFragment qf, UsesMap u, DefsMap d, QCPSystemInfo qcpi) {
	FragmentRel res = { };
	
	// TODO: Do we want all names in the fragment, or just leaf node names?
	set[Name] usedNames = { n | /nameFragment(Name n) := qf };
	//println("Found <size(usedNames)> names in fragment");
	
	for (n <- usedNames, ul <- u[<l, n>], < de, dl > <- d[<ul, n>]) {
		if (de is defExpr) {
			newFragment = expr2qf(de.e, qcpi);
			res = res + < l, qf, n, dl, newFragment, noInfo() >;
		} else if (de is defExprWOp) {
			newFragment = expr2qf(de.e, qcpi);
			if (de.usedOp is concat) {
				newFragment = concatFragment(nameFragment(de.usedName),newFragment);
			}
			res = res + < l, qf, n, dl, newFragment, noInfo() >;
		} else if (de is inputParamDef) {
			res = res + < l, qf, n, dl, inputParamFragment(de.paramName), noInfo() >;
		} else if (de is globalDef) {
			res = res + < l, qf, n, dl, globalFragment(de.globalName), noInfo() >;
		}
	}
	
	for (n <- usedNames, <l,n> notin u) {
		res = res + < l, qf, n, l, unknownFragment(), noInfo() >;
	}
	
	return res;
} 

public rel[loc callLoc, CFG graph] cfgsWithCalls(System s, set[str] functionNames = {}, set[str] methodNames = {}) {
	rel[loc callLoc, CFG graph] res = { };
	for (l <- s.files) {
		cfgsForFile = buildCFGs(s.files[l], buildBasicBlocks=false);
		
		// Find the relevant function calls
		res = res + { < cn@at, cfgsForFile[np] > | np <- cfgsForFile, n:exprNode(cn:call(name(name(fname)),_), _) <- cfgsForFile[np].nodes, fname in functionNames };
	}
	return res;
}

public Expr getQueryExpr(map[str,int] functionParams, map[str,int] methodParams, map[tuple[str,str],int] staticParams, Expr callExpr) {
	if (call(name(name(fn)),actuals) := callExpr) {
		if (fn in functionParams && size(actuals) > functionParams[fn] ) {
			if (actualParameter(Expr e,_,false) := actuals[functionParams[fn]]) {
				return e;
			} else {
				throw "Looking for parameter at index <functionParams[fn]> but only <size(actuals)> actuals";
			}
		} else {
			throw "Looking for parameter at index <functionParams[fn]> but only <size(actuals)> actuals";
		}		
	} else if (methodCall(_,name(name(mn)),actuals) := callExpr) {
		if (mn in methodParams && size(actuals) > methodParams[mn] ) {
			if (actualParameter(Expr e,_,false) := actuals[methodParams[mn]]) {
				return e;
			} else {
				throw "Looking for parameter at index <methodParams[mn]> but only <size(actuals)> actuals";
			}
		} else {
			throw "Looking for parameter at index <methodParams[mn]> but only <size(actuals)> actuals";
		}			
	} else if (staticCall(name(name(cln)), name(name(mn)), actuals) := callExpr) {
		if (<cln,mn> in staticParams && size(actuals) > staticParams[<cln,mn>] ) {
			if (actualParameter(Expr e,_,false) := actuals[staticParams[<cln,mn>]]) {
				return e;
			} else {
				throw "Looking for parameter at index <staticParams[mn]> but only <size(actuals)> actuals";
			}
		} else {
			throw "Looking for parameter at index <staticParams[mn]> but only <size(actuals)> actuals";
		}
	}
	
	throw "Unhandled query expression <callExpr>";
}

public Expr queryParameter(map[str,int] functionParams, map[str,int] methodParams, map[tuple[str,str],int] staticParams, exprNode(Expr e,_)) {
	return getQueryExpr(functionParams, methodParams, staticParams, e);
}

public default Expr queryParameter(map[str,int] functionParams, map[str,int] methodParams, map[tuple[str,str],int] staticParams, CFGNode n) { 
	throw "Unexpected parameter <n>"; 
}

alias DefsMap = map[tuple[Lab, Name], rel[DefExpr definedAs, Lab definedAt]];
alias UsesMap = map[tuple[Lab, Name], set[Lab]];

public tuple[SQLModel,QCPSystemInfo] buildModel(QCPSystemInfo qcpi, loc callLoc, map[str,int] functionParams, map[str,int] methodParams, map[tuple[str,str],int] staticParams) {
	inputSystem = qcpi.sys;
	inputCFGLoc = findContainingCFGLoc(inputSystem.files[callLoc.top], qcpi.systemCFGs[callLoc.top], callLoc);
	inputCFG = findContainingCFG(inputSystem.files[callLoc.top], qcpi.systemCFGs[callLoc.top], callLoc);
	iinfo = qcpi.iinfo;
	try {
		inputNode = findNodeForExpr(inputCFG, callLoc);

		< qcpi, d > = getDefs(qcpi, callLoc.top, inputCFGLoc);
		< qcpi, u > = getUses(qcpi, callLoc.top, inputCFGLoc);
	
		DefsMap defsMap = ( <dl,dn> : { } | <dl,dn> <- d<0,1> );
		for (<dl, dn, de, dat> <- d) defsMap[<dl,dn>] = defsMap[<dl,dn>] + <de,dat>;
		
		UsesMap usesMap = ( < ul, un > : { } | < ul, un > <- u<0,1> );
		for (<ul, un, uat> <- u) usesMap[<ul, un>] = usesMap[<ul, un>] + uat;
		 
		slicedCFG = basicSlice(inputCFG, inputNode, u[inputNode.l]<0>, d = d, u = u);
		nodesForLabels = ( n.l : n | n <- inputCFG.nodes );
		
		queryExp = queryParameter(functionParams, methodParams, staticParams, inputNode);
		startingFragment = expr2qf(queryExp, qcpi);
		FragmentRel res = { };
		solve(res) {
			for ( < l, f > <- (res<3,4> + < inputNode.l, startingFragment>) ) {
				res = res + expandFragment(l, f, usesMap, defsMap, qcpi);
			} 
		}
		
		res = addEdgeInfo(res, slicedCFG);
		crel = computeContainmentRel(res, slicedCFG);
		return < sqlModel(res, crel, startingFragment, inputNode.l, callLoc), qcpi >;
	} catch _ : {
		return < emptyModel(), qcpi >;
	}
}

ContainmentRel computeContainmentRel(FragmentRel frel, CFG slicedCFG) {
	// Map the labels to their labeled nodes, to make it easier to find them later
	nodesForLabels = ( n.l : n | n <- slicedCFG.nodes );
	
	// Get the entry node for the current CFG
	entryNode = getEntryNode(slicedCFG);
	
	// The resulting containment relation, which relates contained nodes x predicates x containers
	ContainmentRel res = { };
	
	// Get the labels of the target nodes in frel, we want to know if those
	// nodes are only reachable under certain conditions
	targetLabels = frel<3>;	

	// Get the nodes for each of these labels
	targetNodes = { n | n <- slicedCFG.nodes, n.l in targetLabels };
	
	// Get the information on which headers dominate the target nodes
	containsRel = containers(slicedCFG);
	
	// We are only interested in conditional containers (ifs and ternary
	// expressions) since the loop headers don't add useful information.
	// So, remove them for now -- we can always put them back later if
	// they would be helpful.
	containsRel = { < n, cn > | < n, cn > <- containsRel,
								(headerNode(Stmt s,_,_) := cn && s is \if) ||
								(headerNode(Expr e,_,_) := cn && e is ternary) };
	
	// Get a graph of the CFG to make it easier to find the proper
	// nodes. Also get the inverse so we can isolate the path. We
	// also remove the backedges so we don't get relationships that are
	// reachable in the graph but not mirrored in the tree (e.g., an if
	// inside a loop would attach both conditions to everything)
	slicedCFG = removeBackEdges(slicedCFG);
	g = cfgAsGraph(slicedCFG);
	ig = invert(g);
	
	// The slicedCFG may be smaller, so remove the nodes that are now gone from the map
	nodesForLabels = ( n.l : n | n <- slicedCFG.nodes );

	// For each target node, get the containers and the predicates	
	for (tn <- targetNodes) {
		// Get the nodes that reach this node in the CFG
		reachedFrom = (ig*)[tn];
		set[Expr] preds = { };
		for (h <- containsRel[tn]) {
			// Get the nodes the header nodes (h) reaches in the CFG
			reachableFrom = (g*)[h];
			
			// The path is nodes that are reached from the header (going forwards) and
			// are reached from the target node (going backwards)
			nodesOnPath = reachedFrom & reachableFrom;
			
			// Since we work with the labels, this makes it easy to see which we have on the path
			labelsOnPath = { n.l | n <- nodesOnPath };
			
			// Get edges on the path, which have a source and target that are both on the
			// path. Note that we used ig* and g* above, so the header and target nodes
			// are possible sources and targets. 
			edgesOnPath = { e | e <- slicedCFG.edges, e.from in labelsOnPath, e.to in labelsOnPath };
			
			// Winnow this down to just those edges that are tied back to the header.
			// NOTE: The condition is commented out since edges with predicates don't always directly come
			// from the header or have a head field
			conditionEdgesOnPath = edgesOnPath; // { e | e <- edgesOnPath, e has header, e.header == h.l };
			
			// Extract the conditions from each edge and add that to the preds for this
			// target node.
			for (e <- conditionEdgesOnPath) {
				if (e has why) preds = preds + e.why;
				if (e has whyNot) preds = preds + unaryOperation(e.whyNot,booleanNot());
				if (e has whys) preds = preds + toSet(e.whys);
				if (e has whyNots) preds = preds + { unaryOperation(wn,booleanNot()) | wn <- e.whyNots };
			}
			
			res = res + < tn.l, preds, h.l >;
		}		
	}
	
	return res;
}

FragmentRel addEdgeInfo(FragmentRel frel, CFG slicedCFG) {
	nodesForLabels = ( n.l : n | n <- slicedCFG.nodes );
	entryNode = getEntryNode(slicedCFG);
	
	// Get the labels of the target nodes in frel, we want to know if those
	// nodes are only reachable under certain conditions
	targetLabels = frel<3>;	

	// Get the nodes for each of these labels
	targetNodes = { n | n <- slicedCFG.nodes, n.l in targetLabels };
	
	// Get the information on which headers dominate the target nodes
	containsRel = containers(slicedCFG);
	
	// We are only interested in conditional containers (ifs and ternary
	// expressions) since the loop headers don't add useful information.
	// So, remove them for now -- we can always put them back later if
	// they would be helpful.
	containsRel = { < n, cn > | < n, cn > <- containsRel,
								(headerNode(Stmt s,_,_) := cn && s is \if) ||
								(headerNode(Expr e,_,_) := cn && e is ternary) };
	
	// Get a graph of the CFG to make it easier to find the proper
	// nodes. Also get the inverse so we can isolate the path. We
	// also remove the backedges so we don't get relationships that are
	// reachable in the graph but not mirrored in the tree (e.g., an if
	// inside a loop would attach both conditions to everything)
	slicedCFG = removeBackEdges(slicedCFG);
	g = cfgAsGraph(slicedCFG);
	ig = invert(g);
	
	// For each node, find the predicates that are required to reach it
	map[Lab, tuple[set[Expr] preds, Lab l]] nodePredicates = ( );
	nodesForLabels = ( n.l : n | n <- slicedCFG.nodes );
	
	for (tn <- targetNodes) {
		// Get the nodes that reach this node in the CFG
		reachedFrom = (ig*)[tn];
		set[Expr] preds = { };
		for (h <- containsRel[tn]) {
			// Get the nodes the header nodes reaches in the CFG
			reachableFrom = (g*)[h];
			
			// The path is nodes that are reached from the header (going forwards) and
			// are reached from the target node (going backwards)
			nodesOnPath = reachedFrom & reachableFrom;
			
			// Since we work with the labels, this makes it easy to see which we have on the path
			labelsOnPath = { n.l | n <- nodesOnPath };
			
			// Get edges on the path, which have a source and target that are both on the
			// path. Note that we used ig* and g* above, so the header and target nodes
			// are possible sources and targets. 
			edgesOnPath = { e | e <- slicedCFG.edges, e.from in labelsOnPath, e.to in labelsOnPath };
			
			// Winnow this down to just those edges that are tied back to the header.
			conditionEdgesOnPath = edgesOnPath; // { e | e <- edgesOnPath, e has header, e.header == h.l };
			
			// Extract the conditions from each edge and add that to the preds for this
			// target node.
			for (e <- conditionEdgesOnPath) {
				if (e has why) preds = preds + e.why;
				if (e has whyNot) preds = preds + unaryOperation(e.whyNot,booleanNot());
				if (e has whys) preds = preds + toSet(e.whys);
				if (e has whyNots) preds = preds + { unaryOperation(wn,booleanNot()) | wn <- e.whyNots };
			}
			
		}
		// Find the header that is most precise, it will be nested in the others
		if (!isEmpty(containsRel[tn])) {
			mostPrecise = getOneFrom(containsRel[tn]);
			for (n <- containsRel[tn]) {
				if (nodesForLabels[n.l] < nodesForLabels[mostPrecise.l]) {
					mostPrecise = n;
				}
			}
			nodePredicates[tn.l] = < preds, mostPrecise.l >;
		}
	}
	
	// Since we really only care about conditions that do not impact all the target nodes, remove any
	// labels that are common to all of them
	commonConds = { };
	if (!isEmpty(nodePredicates<1>.preds)) {
		commonConds = getOneFrom(nodePredicates<1>.preds);
		for (l <- nodePredicates) {
			commonConds = commonConds & nodePredicates[l].preds;
		}
		for (l <- nodePredicates) {
			nodePredicates[l].preds = nodePredicates[l].preds - commonConds;
		}
	}
	
	// Now, using this information, add these conditions to any edges that target these nodes
	for ( < l1, f1, n1, l2, f2, _ > <- frel, l2 in nodePredicates, < preds, headerLabel > := nodePredicates[l2]) {
		frel = frel + < l1, f1, n1, l2, f2, edgeCondsInfo(preds, headerLabel) >;
	}

	return frel;		 
}

public rel[CFGNode containedNode, CFGNode containerNode] containers(CFG inputCFG) {
	map[Lab, set[Lab]] resMap = ( );
	nodesForLabels = ( n.l : n | n <- inputCFG.nodes );

	g = cfgAsGraph(inputCFG);
	gInverted = invert(g);
	entry = getEntryNode(inputCFG);
	  
	list[CFGNode] worklist = buildForwardWorklist(inputCFG);
	workset = toSet(worklist);
	
	while (!isEmpty(worklist)) {
		n = worklist[0];
		worklist = worklist[1..];
		workset = workset - n;
		resStart = resMap[n.l] ? {};
		
		// The containing nodes that reach n through incoming labels
		set[Lab] inbound = { *(resMap[ni.l]? {}) | ni <- gInverted[n]};
		
		// The containing nodes that pass through n
		set[Lab] outbound = inbound;
		
		// If n is a footer node, this "closes" the containment, so we remove the
		// associated header node. If n is a header node, this is a new container,
		// so we add it
		if (n is footerNode) {
			outbound = outbound - { l | l <- inbound, l == n.header };
		} else if (n is headerNode) {
			outbound = outbound + n.l;
		}
		
		// The container nodes that contain n
		resMap[n.l] = outbound;
		
		resEnd = resMap[n.l] ? {};
		
		// If we added new containers, downstream nodes need to be recalculated, so
		// add those into the worklist
		if (resStart != resEnd) {
			newElements = [ gi | gi <- g[n], gi notin workset ];
			worklist = newElements + worklist;
			workset = workset + toSet(newElements);
		}
	}
	
	return { < nodesForLabels[l], nodesForLabels[h] > | l <- resMap, h <- resMap[l] }; 	
}

public QueryFragment testFragments(str exprText) {
	QCPSystemInfo qcpi = readQCPSystemInfo("Schoolmate","1.5.4");
	inputExpr = parsePHPExpression(exprText);
	return expr2qf(inputExpr, qcpi);
}

data LabeledPiece = labeledPiece(SQLPiece piece, set[EdgeInfo] edgeInfo);
alias LabeledYield = list[LabeledPiece];

data SQLPiece = staticPiece(str literal) | namePiece(str name) | dynamicPiece();
alias SQLYield = list[SQLPiece];

public set[LabeledYield] wow = { };
public SQLModel wowModel;

public set[SQLYield] yields(SQLModel m, bool filterYields=false, bool limitYields=true) {
	if (m is emptyModel) return { };
	
	SQLYield yieldForFragment(literalFragment(str s)) = [ staticPiece(s) ];
	SQLYield yieldForFragment(nameFragment(Name n)) = [ yieldForName(n) ];
	SQLYield yieldForFragment(dynamicFragment(Expr e)) = [ dynamicPiece() ];
	SQLYield yieldForFragment(unknownFragment()) = [ dynamicPiece() ];
	SQLYield yieldForFragment(compositeFragment(list[QueryFragment] fragments)) = [ *yieldForFragment(f) | f <- fragments ];
	SQLYield yieldForFragment(concatFragment(QueryFragment left, QueryFragment right)) = yieldForFragment(left) + yieldForFragment(right);
	SQLYield yieldForFragment(inputParamFragment(Name n)) = [ yieldForName(n) ];
	SQLYield yieldForFragment(globalFragment(Name n)) = [ yieldForName(n) ];
	
	SQLPiece yieldForName(varName(str varName)) = namePiece(varName);
	SQLPiece yieldForName(elementName(str varName, str indexName)) = namePiece("<varName>[\'<indexName>\']");
	SQLPiece yieldForName(computedName(Expr computedName)) = namePiece("UNKNOWN_NAME");
	SQLPiece yieldForName(propertyName(Expr targetObject, str propertyName)) = namePiece("UNKNOWN_TARGET.<propertyName>");
	SQLPiece yieldForName(computedPropertyName(Expr targetObject, Expr computedPropertyName)) = namePiece("UNKNOWN_TARGET.UNKNOWN_PROPERTY");
	SQLPiece yieldForName(staticPropertyName(str className, str propertyName)) = namePiece("<className>::<propertyName>");
	SQLPiece yieldForName(computedStaticPropertyName(Expr computedClassName, str propertyName)) = namePiece("UNKNOWN_TARGET::<propertyName>");
	SQLPiece yieldForName(computedStaticPropertyName(str className, Expr computedPropertyName)) = namePiece("<className>::UNKNOWN_PROPERTY");
	SQLPiece yieldForName(computedStaticPropertyName(Expr computedClassName, Expr computedPropertyName)) = namePiece("UNKNOWN_TARGET::UNKNOWN_PROPERTY");

	LabeledPiece addLabels(SQLPiece piece, set[EdgeInfo] edgeInfo) = labeledPiece(piece, edgeInfo);
	LabeledYield addLabels(SQLYield yield, set[EdgeInfo] edgeInfo) = [ addLabels(p,edgeInfo) | p <- yield ];
	set[LabeledYield] addLabels(set[SQLYield] ys, set[EdgeInfo] edgeInfo) = { addLabels(li,edgeInfo) | li <- ys };
	
	SQLPiece stripLabels(labeledPiece(SQLPiece piece, set[EdgeInfo] edgeInfo)) = piece;
	SQLYield stripLabels(LabeledYield ly) = [ stripLabels(lp) | lp <- ly ];
	set[SQLYield] stripLabels(set[LabeledYield] ls) = { stripLabels(li) | li <- ls };

	map[tuple[Lab sourceLabel, QueryFragment sourceFragment],rel[Name name, Lab targetLabel, QueryFragment targetFragment, EdgeInfo edgeInfo]] fragmentRelMap =
		( < sourceLabel, sourceFragment > : { } | < sourceLabel, sourceFragment > <- m.fragmentRel<0,1> );
	
	for (< sourceLabel, sourceFragment, n, targetLabel, targetFragment, edgeInfo > <- m.fragmentRel ) {
		fragmentRelMap[ < sourceLabel, sourceFragment > ] += < n, targetLabel, targetFragment, edgeInfo >;
	}
		
	map[tuple[QueryFragment,Lab], set[LabeledYield]] buildCache = ( );
				   
	set[LabeledYield] buildPieces(QueryFragment inputFragment, Lab l, set[EdgeInfo] edgeInfo, set[Lab] alreadyVisited) {
		if (<inputFragment, l> in buildCache) {
			return buildCache[<inputFragment,l>];
		}
		
		// Get the possible expansions for each at this location
		expansionsWithConditions = (<l, inputFragment> in fragmentRelMap) ? fragmentRelMap[<l, inputFragment>] : { };
		expansions = expansionsWithConditions<0,1,2>;
		
		map[QueryFragment, set[LabeledYield]] expansionCache = ( );
		set[LabeledYield] performExpansion(QueryFragment fragment) {
			if (fragment in expansionCache) {
				return expansionCache[fragment];
			}
			
			if (fragment is nameFragment) {
				if (isEmpty(expansions[fragment.name])) {
					expansionCache[fragment] = { labeledPiece(yieldForFragment(fragment), edgeInfo) };
					return expansionCache[fragment];
				}
				
				nameExpansions = { *buildPieces(lf,ll,edgeInfo + expansionsWithConditions[fragment.name,ll,lf], alreadyVisited+l) 
								 | < ll, lf > <- expansions[fragment.name], 
								   ll != l && ll notin alreadyVisited } +
							     { addLabels([ dynamicPiece() ], edgeInfo) | < ll, lf > <- expansions[fragment.name], ll == l || ll in alreadyVisited };
							     
				// This is a heuristic: if we have an edge condition stating that a name is non-null,
				// then we discard empty replacements for the name since we specifically were filtering
				// those out in the code. TODO: This should ensure the assignment comes from outside, but
				// there is no reason to check to ensure something isn't empty and then set it to empty
				// to insert it into q query. This is really protecting against defaults set higher up
				// in the code that are reachable in the CFG.
				if (varName(vn) := fragment.name) {
					nameCheckConds = { vn | edgeCondsInfo(set[Expr] conds, _) <- edgeInfo, var(name(name(vn))) <- conds };
					if (size(nameCheckConds) > 0) {
						emptyExpansions = { lp | lp:[labeledPiece(staticPiece(""),_)] <- nameExpansions };
						if (size(emptyExpansions) > 0) {
							nameExpansions = nameExpansions - emptyExpansions;
						}
					}
					println("Found <size(nameExpansions)> expansions");
					if (size(nameExpansions) > 1000) {
						println("Limiting yields for call location <m.callLoc>");
						tempExpansions = { te | te <- (toList(nameExpansions))[0..1000] };
						nameExpansions = tempExpansions;
					}
				}
				// TODO: This is the biggest use of time in the profile (all of it is in the top 4)
				expansionCache[fragment] = 
				       { ne | ne <- nameExpansions, size(ne) != 1 || [labeledPiece(dynamicPiece(),_)] !:= ne } + 
				       { addLabels(yieldForFragment(fragment), edgeInfo) | ne <- nameExpansions, [labeledPiece(dynamicPiece(),_)] := ne };
				return expansionCache[fragment];
			} else if (fragment is compositeFragment) {
				compositeYield = performExpansion(fragment.fragments[0]);
				for (f <- fragment.fragments[1..]) {
					nextYield = performExpansion(f);
					compositeYield = { cyi + nyi | cyi <- compositeYield, nyi <- nextYield };
				}
				expansionCache[fragment] = compositeYield;
				return expansionCache[fragment];
			} else if (fragment is concatFragment) {
				leftYield = performExpansion(fragment.left);
				rightYield = performExpansion(fragment.right);
				concatYield = { lyi + ryi | lyi <- leftYield, ryi <- rightYield };
				expansionCache[fragment] = concatYield;
				return expansionCache[fragment];
			} else {
				expansionCache[fragment] = { addLabels(yieldForFragment(fragment), edgeInfo) };
				return expansionCache[fragment];
			} 
		}
		
		res = performExpansion(inputFragment);
		buildCache[<inputFragment,l>] = res;
		return res;
	}
		
	SQLYield mergeStatics(SQLYield y) {
		if ([*front,staticPiece(sp1),staticPiece(sp2),*back] := y) {
			y = [*front,staticPiece(sp1+sp2),*back];
		}
		return y;
	}
	
	SQLYield simplifyYield(SQLYield y) {
		solve(y) {
			y = mergeStatics(y);
		}
		return y;
	}
	
	set[SQLYield] simplifyYields(set[SQLYield] ys) {
		return { simplifyYield(y) | y <- ys };
	}
	
	labeledYields = buildPieces(m.startFragment, m.startLabel, {}, {});

	feasibleYields = filterYields ? removeInfeasibleYields(labeledYields) : labeledYields;

	regularYields = stripLabels(feasibleYields);
	return simplifyYields(regularYields);
}

public set[SQLYield] removeInfeasibleYields(set[SQLYield] labeledYields) {
	infeasibleYields = { } ;

	yieldsLoop: for (ly <- labeledYields) {
		pieces = [ lp | lp:labeledPiece(_,_) <- ly ];
		condsHeaders = { h | lp <- pieces, edgeCondsInfo(_, h) <- lp.edgeInfo };
		condsMap = ( h : [ ] | h <- condsHeaders );
		for (lp <- pieces, edgeCondsInfo(conds, h) <- lp.edgeInfo) {
			condsMap[h] = condsMap[h] + conds;
		}
		for (h <- condsMap) {
			worklist = condsMap[h];
			while (size(worklist) > 1) {
				item1 = worklist[0]; worklist = worklist[1..];
				for (item2 <- worklist) {
					itemInter = item1 & item2;
					if ( itemInter != item1 && itemInter != item2 ) {
						infeasibleYields = infeasibleYields + ly;
						continue yieldsLoop;
					}
				}
			}
		}
		//if ([_*,labeledPiece(_,ei1),_*,labeledPiece(_,ei2),_*] := ly,
		//	{_*, edgeCondsInfo(conds1, h1), _*} := ei1, {_*, edgeCondsInfo(conds2,h1), _*} := ei2,
		//	(conds1 & conds2) != conds1 && (conds1 & conds2) != conds2) {
		//	infeasibleYields = infeasibleYields + ly;
		//}
	}

	return labeledYields - infeasibleYields;
}

@doc{converts a yield to a string parsable by the sql parser}
public str yield2String(SQLYield yield){
	str res = "";
	int holeID = 0;
	for(SQLPiece piece <- yield){
		if(piece is dynamicPiece || piece is namePiece){
			res = res +  "?<holeID>";
			holeID = holeID + 1;
			continue;
		}
		if(staticPiece(literal) := piece){
			res = res + literal;
			continue;
		}
	}
	return res;
}

@doc{converts a set of yelds to a set of parsable strings}
public set[str] yields2Strings(set[SQLYield] yields) = { yield2String(y) | y <- yields };

public void testcode() {
	pt = loadBinary("Schoolmate", "1.5.4");
	literalQueryLoc = |home:///PHPAnalysis/systems/Schoolmate/schoolmate_1.5.4/EditClass.php|(956,57,<29,0>,<29,0>);
	qloc = |home:///PHPAnalysis/systems/Schoolmate/schoolmate_1.5.4/DeleteFunctions.php|(5364,87,<165,0>,<165,0>);
	locInWhile = |home:///PHPAnalysis/systems/Schoolmate/schoolmate_1.5.4/ManageGrades.php|(7737,98,<213,0>,<213,0>);
	locInIf = |home:///PHPAnalysis/systems/Schoolmate/schoolmate_1.5.4/Registration.php|(860,115,<22,0>,<22,0>);
	cfgs = cfgsWithCalls(pt,functionNames={"mysql_query"});
}

public rel[loc, SQLModel] buildModelsForSystem(str systemName, str systemVersion, System s, set[loc] callLocs, map[str,int] functionParams, map[str,int] methodParams, map[tuple[str,str],int] staticParams) {
	return buildModelsForSystem(s, readQCPSystemInfo(systemName, systemVersion), callLocs, functionParams, methodParams, staticParams);
}

public rel[loc, SQLModel] buildModelsForSystem(str systemName, str systemVersion, set[loc] callLocs, map[str,int] functionParams, map[str,int] methodParams, map[tuple[str,str],int] staticParams) {
	return buildModelsForSystem(loadBinary(systemName, systemVersion), readQCPSystemInfo(systemName, systemVersion), callLocs, functionParams, methodParams, staticParams);
}

public rel[loc, SQLModel] buildModelsForSystem(System s, QCPSystemInfo qcpi, set[loc] callLocs, map[str,int] functionParams, map[str,int] methodParams, map[tuple[str,str],int] staticParams) {
	rel[loc, SQLModel] res = { };
	int buildCount = 0;
	int totalToBuild = size(callLocs);	
	for (l <- callLocs) {
		buildCount += 1;
		println("Building model <buildCount> of <totalToBuild> for call at location <l>");
		< callModel, qcpi > = buildModel(qcpi, l, functionParams, methodParams, staticParams);
		res = res + < l,  callModel >;
	}
	writeQCPSystemInfo(s.name, s.version, qcpi);
	return res;
}

loc modelsLoc = baseLoc + "serialized/sql/models";

public void writeModels(str systemName, str systemVersion, rel[loc, SQLModel] modelsRel) {
	writeBinaryValueFile(modelsLoc + "<systemName>-<systemVersion>.bin", modelsRel, compression=false);		
}

public rel[loc,SQLModel] readModels(str systemName, str systemVersion) {
	return readBinaryValueFile(#rel[loc,SQLModel], modelsLoc + "<systemName>-<systemVersion>.bin");
}

public bool modelsFileExists(str systemName, str systemVersion) {
	return exists(modelsLoc + "<systemName>-<systemVersion>.bin");
}

public void buildAndSaveModelsForCorpus(Corpus corpus, map[str,int] functionParams, map[str,int] methodParams, map[tuple[str,str],int] staticParams, bool overwrite=false) {
	for (systemName <- corpus, systemVersion := corpus[systemName]) {
		if (!modelsFileExists(systemName, systemVersion) || overwrite) {
			qcpi = readQCPSystemInfo(systemName, systemVersion);
			mrel = buildModelsForSystem(qcpi.sys, qcpi, functionParams, methodParams, staticParams);
			writeModels(systemName, systemVersion, mrel);
		}
	}	
} 

public void printYields(rel[loc, SQLModel] models) {
	for (<l, m> <- models) {
		println("For location <l>");
		println("\tModel is <m>");
		println("\tYields are:");
		for (y <- yields(m)) {
			println("\t\t<y>");
		}
	} 
}

//public str getEdgeLabel(nameFragment(Name n)) = printName(n);
//public default str getEdgeLabel(QueryFragment qf) = "";

// TODO: Add code to visualize model as dot graph...
public void renderSQLModelAsDot(SQLModel m, loc writeTo, str title = "", bool showConditions = true) {
	nodes = m.fragmentRel<1> + m.fragmentRel<4>;
	if (isEmpty(nodes)) {
		nodes = { m.startFragment };
	}
	int i = 1;
	nodeMap = ( );
	for (n <- nodes) {
		nodeMap[n] = i;
		i += 1;
	} 
	
	nodes = [ "\"<nodeMap[n]>\" [ label = \"<escapeForDot(printQueryFragment(n))>\", labeljust=\"l\" ];" | n <- nodes ];
	edges = [ "\"<nodeMap[n1]>\" -\> \"<nodeMap[n2]>\" [ label = \"< showConditions ? printEdgeInfo(nm,m.fragmentRel[l1,n1,nm,l2,n2]) : "">\"];" | < l1, n1, nm, l2, n2 > <- m.fragmentRel<0,1,2,3,4> ];
	str dotGraph = "digraph \"SQLModel\" {
				   '	graph [ label = \"SQL Model<size(title)>0?" for <title>":"">\" , ranksep=1, dpi=400];
				   '	node [ shape = box ];
				   '	<intercalate("\n", nodes)>
				   '	<intercalate("\n",edges)>
				   '}";
	writeFile(writeTo,dotGraph);
}

public map[int,SQLModel] renderSQLModelsAsDot(set[SQLModel] ms) {
	int id = 0;
	map[int,SQLModel] res = ( );
	for (SQLModel m <- ms) {
		res[id] = m;
		idStr = "<id>";
		renderSQLModelAsDot(m, |file:///tmp/model<idStr>.dot|, title = "Model <id>");
		id += 1;
	}
	return res;
}

public CFG getCFGForModel(QCPSystemInfo qcpi, SQLModel sqlm) {
	inputSystem = qcpi.sys;
	callLoc = sqlm.callLoc;
	inputCFGLoc = findContainingCFGLoc(inputSystem.files[callLoc.top], qcpi.systemCFGs[callLoc.top], callLoc);
	inputCFG = findContainingCFG(inputSystem.files[callLoc.top], qcpi.systemCFGs[callLoc.top], callLoc);
	return inputCFG;
}
