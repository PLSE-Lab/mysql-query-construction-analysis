module QCPAnalysis::SQLModel

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

import QCPAnalysis::Utils;
import QCPAnalysis::QCPSystemInfo;

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

alias FragmentRel = rel[Lab sourceLabel, QueryFragment sourceFragment, Name name, Lab targetLabel, QueryFragment targetFragment, EdgeInfo edgeInfo];
data SQLModel = sqlModel(FragmentRel fragmentRel, QueryFragment startFragment, Lab startLabel, loc callLoc);

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
			
			case fetchArrayDim(var(name(name(vn))),_) :
				return nameFragment(varName(vn));
				
			case var(expr(Expr e)) :
				return nameFragment(computedName(e));
			
			case fetchArrayDim(var(expr(Expr e)),_) :
				return nameFragment(computedName(e));
			
			case propertyFetch(target, name(name(vn))) :
				return nameFragment(propertyName(target, vn));
				
			case propertyFetch(target, Expr e) :
				return nameFragment(computedPropertyName(target, e));
			
			case staticPropertyFetch(name(name(target)), name(name(vn))) :
				return nameFragment(staticPopertyName(target, vn));
				
			case staticPropertyFetch(name(name(target)), Expr e) :
				return nameFragment(computedStaticPopertyName(target, e));
			
			case staticPropertyFetch(expr(Expr target), name(name(vn))) :
				return nameFragment(computedStaticPopertyName(target, vn));
				
			case staticPropertyFetch(expr(Expr target), Expr e) :
				return nameFragment(computedStaticPopertyName(target, e));
		
			default:
				return dynamicFragment(e);
		}
	}
	
	return expr2qfAux(ex);
}

public FragmentRel expandFragment(Lab l, QueryFragment qf, Uses u, Defs d, QCPSystemInfo qcpi) {
	FragmentRel res = { };
	
	// TODO: Do we want all names in the fragment, or just leaf node names?
	set[Name] usedNames = { n | /nameFragment(Name n) := qf };
	//println("Found <size(usedNames)> names in fragment");
	
	for (n <- usedNames, ul <- u[l, n], < de, dl > <- d[ul, n]) {
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
	
	for (n <- usedNames, n notin u[l]<0>) {
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

public Expr getQueryExpr(call(name(name("mysql_query")),[actualParameter(Expr e,_,false),*_])) = e;
public default Expr getQueryExpr(Expr e) { throw "Unhandled query expression <e>"; }
 
public Expr queryParameter(exprNode(Expr e,_)) = getQueryExpr(e);
public default Expr queryParameter(CFGNode n) { throw "Unexpected parameter <n>"; }
 
public SQLModel buildModel(QCPSystemInfo qcpi, loc callLoc, set[str] functions = { "mysql_query" }) {
	inputSystem = qcpi.sys;
	baseLoc = inputSystem.baseLoc;
	inputCFGLoc = findContainingCFGLoc(inputSystem.files[callLoc.top], qcpi.systemCFGs[callLoc.top], callLoc);
	inputCFG = findContainingCFG(inputSystem.files[callLoc.top], qcpi.systemCFGs[callLoc.top], callLoc);
	iinfo = qcpi.iinfo;
	inputNode = findNodeForExpr(inputCFG, callLoc);

	< qcpi, d > = getDefs(qcpi, callLoc.top, inputCFGLoc);
	< qcpi, u > = getUses(qcpi, callLoc.top, inputCFGLoc);
	slicedCFG = basicSlice(inputCFG, inputNode, u[inputNode.l]<0>, d = d, u = u);
	nodesForLabels = ( n.l : n | n <- inputCFG.nodes );
	
	queryExp = queryParameter(inputNode);
	startingFragment = expr2qf(queryExp, qcpi);
	FragmentRel res = { };
	solve(res) {
		for ( < l, f > <- (res<3,4> + < inputNode.l, startingFragment>) ) {
			res = res + expandFragment(l, f, u, d, qcpi);
		} 
	}
	
	res = addEdgeInfo(res, slicedCFG);
	return sqlModel(res, startingFragment, inputNode.l, callLoc);
}

FragmentRel addEdgeInfo(FragmentRel frel, CFG slicedCFG) {
	nodesForLabels = ( n.l : n | n <- slicedCFG.nodes );
	entryNode = getEntryNode(slicedCFG);
	rel[CFGNode,CFGNode] containedIn = { };
	
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

public rel[CFGNode,CFGNode] containers(CFG inputCFG) {
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
		
		set[Lab] inbound = { *(resMap[ni.l]? {}) | ni <- gInverted[n]};
		set[Lab] outbound = inbound;
		
		if (n is footerNode) {
			outbound = outbound - { l | l <- inbound, l == n.header };
		} else if (n is headerNode) {
			outbound = outbound + n.l;
		}
		
		resMap[n.l] = outbound;
		
		resEnd = resMap[n.l] ? {};
		
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

public set[SQLYield] yields(SQLModel m, bool filterYields=false) {
	SQLYield yieldForFragment(literalFragment(str s)) = [ staticPiece(s) ];
	SQLYield yieldForFragment(nameFragment(Name n)) = [ yieldForName(n) ];
	SQLYield yieldForFragment(dynamicFragment(Expr e)) = [ dynamicPiece() ];
	SQLYield yieldForFragment(unknownFragment()) = [ dynamicPiece() ];
	SQLYield yieldForFragment(compositeFragment(list[QueryFragment] fragments)) = [ *yieldForFragment(f) | f <- fragments ];
	SQLYield yieldForFragment(concatFragment(QueryFragment left, QueryFragment right)) = yieldForFragment(left) + yieldForFragment(right);
	SQLYield yieldForFragment(inputParamFragment(Name n)) = [ yieldForName(n) ];
	SQLYield yieldForFragment(globalFragment(Name n)) = [ yieldForName(n) ];
	
	SQLPiece yieldForName(varName(str varName)) = namePiece(varName);
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

	set[LabeledYield] buildPieces(QueryFragment inputFragment, Lab l, set[EdgeInfo] edgeInfo, set[Lab] alreadyVisited) {
		// Get the possible expansions for each at this location
		expansionsWithConditions = m.fragmentRel[l, inputFragment];
		expansions = expansionsWithConditions<0,1,2>;
		
		set[LabeledYield] performExpansion(QueryFragment fragment) {
			if (fragment is nameFragment) {
				if (isEmpty(expansions[fragment.name])) {
					return { labeledPiece(yieldForFragment(fragment), edgeInfo); }
				}
				
				nameExpansions = { *buildPieces(lf,ll,edgeInfo + expansionsWithConditions[fragment.name,ll,lf], alreadyVisited+l) 
								 | < ll, lf > <- expansions[fragment.name], 
								   ll != l && ll notin alreadyVisited } +
							     { addLabels([ dynamicPiece() ], edgeInfo) | < ll, lf > <- expansions[fragment.name], ll == l || ll in alreadyVisited };
				return { ne | ne <- nameExpansions, [labeledPiece(dynamicPiece(),_)] !:= ne } + 
				       { addLabels(yieldForFragment(fragment), edgeInfo) | ne <- nameExpansions, [labeledPiece(dynamicPiece(),_)] := ne };
			} else if (fragment is compositeFragment) {
				compositeYield = performExpansion(fragment.fragments[0]);
				for (f <- fragment.fragments[1..]) {
					nextYield = performExpansion(f);
					compositeYield = { cyi + nyi | cyi <- compositeYield, nyi <- nextYield };
				}
				return compositeYield;
			} else if (fragment is concatFragment) {
				leftYield = performExpansion(fragment.left);
				rightYield = performExpansion(fragment.right);
				concatYield = { lyi + ryi | lyi <- leftYield, ryi <- rightYield };
				return concatYield;
			} else {
				return { addLabels(yieldForFragment(fragment), edgeInfo) };
			} 
		}
		
		return performExpansion(inputFragment);
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
	infeasibleYields = { ly | ly <- labeledYields, 
						      [_*,labeledPiece(_,ei1),_*,labeledPiece(_,ei2),_*] := ly,
						      {_*, edgeCondsInfo(conds1, h1), _*} := ei1, {_*, edgeCondsInfo(conds2,h1), _*} := ei2,
						      (conds1 & conds2) != conds1 && (conds1 & conds2) != conds2};
	feasibleYields = filterYields ? (labeledYields - infeasibleYields) : labeledYields;
		
	regularYields = stripLabels(feasibleYields);
	return simplifyYields(regularYields);
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

public rel[loc, SQLModel] buildModelsForSystem(str systemName, str systemVersion) {
	return buildModelsForSystem(loadBinary(systemName, systemVersion), readQCPSystemInfo(systemName, systemVersion));
}

public rel[loc, SQLModel] buildModelsForSystem(System s, QCPSystemInfo qcpi) {
	allCalls = { < c@at, c > | /c:call(name(name("mysql_query")), _) := s };
	rel[loc, SQLModel] res = { };
	for (l <- allCalls<0>) {
		println("Building model for call at location <l>");
		res = res + < l, buildModel(qcpi, l) >;
	}
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

public void buildAndSaveModelsForCorpus(Corpus corpus, bool overwrite=false) {
	for (systemName <- corpus, systemVersion := corpus[systemName]) {
		if (!modelsFileExists(systemName, systemVersion) || overwrite) {
			qcpi = readQCPSystemInfo(systemName, systemVersion);
			mrel = buildModelsForSystem(qcpi.sys, qcpi);
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
public void renderSQLModelAsDot(SQLModel m, loc writeTo, str title = "") {
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
	edges = [ "\"<nodeMap[n1]>\" -\> \"<nodeMap[n2]>\" [ label = \"<printEdgeInfo(nm,m.fragmentRel[l1,n1,nm,l2,n2])>\"];" | < l1, n1, nm, l2, n2 > <- m.fragmentRel<0,1,2,3,4> ];
	str dotGraph = "digraph \"SQLModel\" {
				   '	graph [ label = \"SQL Model<size(title)>0?" for <title>":"">\" ];
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