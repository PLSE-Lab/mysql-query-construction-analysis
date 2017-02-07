module QCPAnalysis::MixedQuery::ParseQuery

import QCPAnalysis::MixedQuery::ConcreteSyntax;
import ParseTree;

// for testing purposes
public SQLQuery parse(str txt) = parse(#SQLQuery, txt); 

//public Tree parseQuery(str txt) = parse(#Query, txt); 