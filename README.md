Note
----

We are in the process (as of June 20, 2017) of adding information here as well as
adding a VirtualBox VM with running software. We are also going to provide a link
to a video. This should be posted by the end of this week.

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
Eclipse project. This will be in the same workspace as the PHPAnalysis
project that you get from installing PHP AiR. You may also need to add the
PHPAnalysis as a Project Reference. To do so, you should right-click on the
QCPAnalysis project (the project for this repository), select Properties,
select Project References, then check PHPAnalysis. You can tell you need to
do this if the Rascal scripts in QCPAnalysis complain about missing Rascal
modules.

Finally, to parse SQL queries, you will also want to check out our modified
MySQL parser. You find find the GitHub page for this parser [here][mysql-parser].
You should `git clone` this into the PHPAnalysis directory, creating a new
directory called sql-parser. Once you do this, you will also need to download
[Composer][composer], a package manager for PHP. You can just follow the instructions
on the [Composer download page][composer-download] to download it into the sql-parser
directory. This will create a file composer.phar. Finally, run `php composer.phar install`
to install the dependencies for the MySQL parser.

In summary, from inside the PHPAnalysis directory:
* `git clone https://github.com/ecu-pase-lab/mysql-query-construction-analysis.git`
* `git clone https://github.com/ecu-pase-lab/sql-parser.git`
* `cd sql-parser`
* Download [Composer][composer] following the [Composer download instructions][composer-download]
* `php composer.phar install`
* You should now be able to import the QCPAnalysis project into Eclipse and start running the code!

[mysql-parser]: https://github.com/ecu-pase-lab/sql-parser
[composer]: https://getcomposer.org/
[composer-download]: https://getcomposer.org/download/

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

Details will be posted soon.