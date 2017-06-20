Introduction
------------

This repository contains our ongoing work on identifying patterns of query
construction in PHP code. At this point, we have focused just on the original
[MySQL API][mysql-api], but plan to expand this to cover other database
APIs in the future.

Running Our Software
--------------------

The analysis code used here is written in [Rascal][rascal], a meta-programming
language for program analysis and transformation. It also uses [PHP AiR][PAiR],
a program analysis for PHP written in Rascal. You should start by following the
installation instructions given on the [PHP AiR][PAiR] project page. At the
end of this, you will have a working Rascal and PHP AiR installation.

[rascal]: http://www.rascal-mpl.org
[mysql-api]: http://php.net/manual/en/book.mysql.php
[PAiR]: https://github.com/cwi-swat/php-analysis

Once this is done, you should be able to just check out this GitHub repository
using `git clone`, then import it into Eclipse by importing an existing
Eclipse project. This will be in the same workspace as the `PHPAnalysis`
project that you get from installing PHP AiR. You may also need to add the
`PHPAnalysis` as a Project Reference. To do so, you should right-click on the
`QCPAnalysis` project (the project for this repository), select Properties,
select Project References, then check `PHPAnalysis`. You can tell you need to
do this if the Rascal scripts in `QCPAnalysis` complain about missing Rascal
modules.

Downloading the Corpus
----------------------

Our current corpus can be downloaded [by clicking here][corpus]. Once downloaded,
the easiest way to use it is to unzip it and then copy the directories into the
`PHPAnalysis/systems` directory. If there is no `systems` directory yet, meaning
you have not yet downloaded any PHP systems to analyze, you can also rename the `query-models-corpus`
directory that the corpus unzips into to `systems` and copy that into `PHPAnalysis`.
For more details about how to set up PHP AiR, please [see the PHP AiR project repository][PAiR].

[corpus]: https://drive.google.com/open?id=0BzLdPikm-ppZb3d3eDNQN3ZTblU

Running the Analysis
--------------------

Details on running the analysis will be posted here shortly.
