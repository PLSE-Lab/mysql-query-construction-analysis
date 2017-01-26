module QCPAnalysis::MixedQuery::ParseQuery

import QCPAnalysis::MixedQuery::ConcreteSyntax;
import ParseTree;

public Tree parseQuery(str txt) = parse(#Query, txt); 