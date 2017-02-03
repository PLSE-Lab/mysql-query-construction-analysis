module QCPAnalysis::MixedQuery::ParseQuery

import QCPAnalysis::MixedQuery::ConcreteSyntax;
import ParseTree;

// for testing purposes
public Query parseQuery(str txt) = parse(#Query, txt); 

//public Tree parseQuery(str txt) = parse(#Query, txt); 