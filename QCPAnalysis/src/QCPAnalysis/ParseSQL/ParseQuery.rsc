module QCPAnalysis::ParseSQL::ParseQuery

import QCPAnalysis::ParseSQL::ConcreteSyntax;
import ParseTree;

public Tree parse(str txt) = parse(#SQLQuery, txt);