# Introduction

This repository contains our ongoing work on identifying patterns of query
construction in PHP code. At this point, we have focused just on the original
[MySQL API][mysql-api], but plan to expand this to cover other database
APIs in the future.

# First Steps: Installing Needed Software

The easiest way to run the software is to download a [VirtualBox][vbox]
virtual machine running Ubuntu that already has everything installed. You can
find a copy of this virtual machine [here][vm]. Once you download this, just
unzip it and you should be able to open and run it using VirtualBox. A 
[walk-through video][video] is also available that will walk you through
running the software in the VM. You can also use this to help you walk
through the code if you install it yourself.


[vbox]: https://www.virtualbox.org/
[vm]: https://drive.google.com/open?id=0BzLdPikm-ppZQ1FqR3QxalV4ZFE
[video]: https://drive.google.com/open?id=0BzLdPikm-ppZa1dvbDlLaEhLOFk

The analysis code used here is written in [Rascal][rascal], a meta-programming
language for program analysis and transformation. It also uses [PHP AiR][PAiR],
a program analysis for PHP written in Rascal. To install the software on your own
machine, you should start by following the installation instructions given on the
[PHP AiR][PAiR] project page. At the end of this, you will have a working Rascal 
and PHP AiR installation.

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
MySQL parser. You can find the GitHub page for this parser [here][mysql-parser].
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

# Downloading the Corpus

Our current corpus can be downloaded [by clicking here][corpus]. Once downloaded,
the easiest way to use it is to unzip it and then copy the directories into the
`PHPAnalysis/systems` directory. If there is no `systems` directory yet, meaning
you have not yet downloaded any PHP systems to analyze, you can also rename the `query-models-corpus`
directory that the corpus unzips into to `systems` and copy that into `PHPAnalysis`. You
should also [download the current version of summaries we extract for PHP library functions and methods][summaries].
When this is unzipped, it will create a directory named `summaries`. This should be copied into
the `PHPAnalysis/serialized` directory. While you can also generate these files yourself, it
takes quite some time -- it essentially crawls the PHP documentation to extract information about
the official libraries.

For more details about how to set up PHP AiR, please [see the PHP AiR project repository][PAiR].

[corpus]: https://drive.google.com/open?id=0BzLdPikm-ppZb3d3eDNQN3ZTblU
[summaries]: https://drive.google.com/open?id=0BzLdPikm-ppZTzhWZ2FKTEF2WlU

# Running the Analysis

Please see the [walk-through video][video] which shows some of the commands that you can use.

The steps shown here for running the analysis assume that you have followed the installation
procedure above and that you have a working copy of PHP AiR (again, see the [PHP AiR site][PAiR]
for details on how to do this).

The first step is to preprocess the systems in the corpus to prepare them for analysis:

1. If you are not already, switch the Eclipse Perspective to Rascal (this will be under "Other" perspectives).
2. Open the `QCPCorpus` module (file QCPCorpus.rsc) in the QCPAnalysis project.
3. Right click in the editor window opened for the module and select `Start Console`.
4. Right click in the editor window again and select `Import Current Module in Console`.
5. In the console, run `buildCorpus();` (enter the command and hit enter). This will parse all the systems and save the ASTs to disk.
6. In the console, next run `buildCorpusInfo();`. This needs [the summaries mentioned above][summaries] to run successfully.
7. Open the `QCPSystemInfo` module.
8. Right click in the editor window opened for the module and select `Import Current Module in Console`.
9. In the console, run `extractQCPSystemInfo();`. This will extract info needed for the analysis. At this time this is required. We plan to change this to allow this information to be extracted on the fly, but this makes the analysis slower.

At this point, all the information needed to run the analysis has been prepared. To run the analysis itself, open the `SCAM2017Demo` module (under the `Demos` folder) and import it (right click, `Import Current Module...`). Now you can do the following:

* `showSystems()` will show the systems in the corpus, with a numeric ID assigned to each. This makes it easier to refer to these systems using the other functions provided in this module.
* `showCallsInSystem(int systemNumber)` shows the calls to `mysql_query` in the given system.
* `buildModelForNumberedCall(int systemNumber, int callNumber)` builds and returns the model for the query call identified by `callNumber` in system `systemNumber`.
* `showYieldsForNumberedCall(int systemNumber, int callNumber)` shows the yields for the query call identified by `callNumber` in system `systemNumber`, using the same query model returned by `buildModelForNumberedCall`.
* `showQueriesForNumberedCall(int systemNumber, int callNumber)` shows the parsed queries for the query call identified by `callNumber` in system `systemNumber`, using the same query model returned by `buildModelForNumberedCall` and the yields returned by `showYieldsForNumberedCall`.

# Examples

Running `showSystems()` will yield the following:

```
The following systems are available:
        1:AddressBook
        2:faqforge
        3:firesoftboard
        4:geccBBlite
        5:inoERP
        6:LinPHA
        7:MyPHPSchool
        8:OcoMon
        9:OMS
        10:OpenClinic
        11:PHPAgenda
        12:PHPFusion
        13:Schoolmate
        14:Timeclock
        15:UseBB
        16:web2project
        17:WebChess
```

You can then get the calls for a specific system:

```
rascal>showCallsInSystem(7);
$2017-06-26T18:52:25.764+00:00$ :: Loading binary: |home:///PHPAnalysis/serialized/parsed/MyPHPSchool-0.3.1.pt|
A total of 85 were found:
        Call 0: |home:///PHPAnalysis/systems/MyPHPSchool/myphpschool_0.3.1/html/activities.php|(581,21,<20,0>,<20,0>)
        Call 1: |home:///PHPAnalysis/systems/MyPHPSchool/myphpschool_0.3.1/html/activities.php|(2542,21,<124,0>,<124,0>)
        Call 2: |home:///PHPAnalysis/systems/MyPHPSchool/myphpschool_0.3.1/html/athletics.php|(632,21,<20,0>,<20,0>)
        Call 3: |home:///PHPAnalysis/systems/MyPHPSchool/myphpschool_0.3.1/html/athletics.php|(2597,21,<124,0>,<124,0>)
        ...
        Call 68: |home:///PHPAnalysis/systems/MyPHPSchool/myphpschool_0.3.1/html/main.inc.php|(14585,22,<504,0>,<504,0>)
        Call 69: |home:///PHPAnalysis/systems/MyPHPSchool/myphpschool_0.3.1/html/news.php|(559,21,<34,0>,<34,0>)
        ...
        Call 76: |home:///PHPAnalysis/systems/MyPHPSchool/myphpschool_0.3.1/html/resources.php|(2388,22,<66,0>,<66,0>)
        Call 77: |home:///PHPAnalysis/systems/MyPHPSchool/myphpschool_0.3.1/html/resourcesadmin.php|(465,22,<13,0>,<13,0>)
        Call 78: |home:///PHPAnalysis/systems/MyPHPSchool/myphpschool_0.3.1/html/resourcesadmin.php|(707,22,<18,0>,<18,0>)
        ...
        Call 82: |home:///PHPAnalysis/systems/MyPHPSchool/myphpschool_0.3.1/html/staff.php|(1757,21,<69,0>,<69,0>)
        Call 83: |home:///PHPAnalysis/systems/MyPHPSchool/myphpschool_0.3.1/utils/create_dir.php|(204,21,<8,0>,<8,0>)
        Call 84: |home:///PHPAnalysis/systems/MyPHPSchool/myphpschool_0.3.1/utils/create_dir.php|(549,21,<23,0>,<23,0>)
```

Note that some of the calls are elided for space purposes. 

## A Simple Example

Call 84 is a fairly simple query:

```
$sql = "SELECT username FROM user_student";
chdir($basedir);
$query = mysql_query($sql,$db);
```

Returning the model for this call gives the following:

```
rascal>buildModelForNumberedCall(7,84);
$2017-06-26T18:55:14.143+00:00$ :: Loading binary: |home:///PHPAnalysis/serialized/parsed/MyPHPSchool-0.3.1.pt|
SQLModel: sqlModel(
  {<lab(72),nameFragment(varName("sql")),varName("sql"),lab(64),literalFragment("SELECT username FROM user_student"),noInfo()>},
  nameFragment(varName("sql")),
  lab(72),
  |home:///PHPAnalysis/systems/MyPHPSchool/myphpschool_0.3.1/utils/create_dir.php|(549,21,<23,0>,<23,0>))
rascal>
```

The model includes the model graph (referencing labels from the control flow graph), the starting fragment, the label of the CFG node
for the call, and the location of the call. The yields and queries for this model can then be computed as follows:

```
rascal>showYieldsForNumberedCall(7,84);
$2017-06-26T18:57:35.382+00:00$ :: Loading binary: |home:///PHPAnalysis/serialized/parsed/MyPHPSchool-0.3.1.pt|
set[SQLYield]: {[staticPiece("SELECT username FROM user_student")]}

rascal>showQueriesForNumberedCall(7,84);
$2017-06-26T18:57:44.926+00:00$ :: Loading binary: |home:///PHPAnalysis/serialized/parsed/MyPHPSchool-0.3.1.pt|
Now parsing SELECT username FROM user_student

rel[SQLYield yield,str queryWithHoles,SQLQuery parsed]: {<[staticPiece("SELECT username FROM user_student")],"SELECT username FROM user_student",selectQuery(
    [name(column("username"))],
    [name(table("user_student"))],
    noWhere(),
    noGroupBy(),
    noHaving(),
    noOrderBy(),
    noLimit(),
    [])>}
```

## A More Complex Example

Call 68 is a more complex query. The call itself is just `mysql_query($sql, $db)`, with the SQL given above
as `$sql = "UPDATE user_$type SET auth = '$enc' WHERE username = '$user'";`. This has three dynamic holes in the
query, for `$type`, `$enc`, and `$user`. 

* `$enc` is a fairly involve computation, defined as `$enc = base64_encode(keyED(encrypt(keyED($text,$key1),$key2),$key3));`, and
we make no attempt to resolve this
* `$user` also involves multiple computations, and is again unresolved. It is based on the result of an earlier query that has been
put into lower case and trimmed.
* `$type` is assigned to either `"student"` or `"staff"` depending on the path taken through the code. Since we can detect this using
our analysis, this yields two different queries, one for each value of `$type`. This is represented in the model as conditional edges
from `$type` to each of these possible assignments.

The actual yields and resulting parsed queries are shown below:

```
rascal>showQueriesForNumberedCall(7,68);
$2017-06-26T18:58:36.533+00:00$ :: Loading binary: |home:///PHPAnalysis/serialized/parsed/MyPHPSchool-0.3.1.pt|
Now parsing UPDATE user_student SET auth = '?0' WHERE username = '?1'

Now parsing UPDATE user_staff SET auth = '?0' WHERE username = '?1'

rel[SQLYield yield,str queryWithHoles,SQLQuery parsed]: {
  <[
    staticPiece("UPDATE user_staff SET auth = \'"),
    namePiece("enc"),
    staticPiece("\' WHERE username = \'"),
    namePiece("user"),
    staticPiece("\'")
  ],"UPDATE user_staff SET auth = \'?0\' WHERE username = \'?1\'",updateQuery(
    [name(table("user_staff"))],
    [setOp("auth","?0")],
    where(condition(simpleComparison("username","=","?1"))),
    noOrderBy(),
    noLimit())>,
  <[
    staticPiece("UPDATE user_student SET auth = \'"),
    namePiece("enc"),
    staticPiece("\' WHERE username = \'"),
    namePiece("user"),
    staticPiece("\'")
  ],"UPDATE user_student SET auth = \'?0\' WHERE username = \'?1\'",updateQuery(
    [name(table("user_student"))],
    [setOp("auth","?0")],
    where(condition(simpleComparison("username","=","?1"))),
    noOrderBy(),
    noLimit())>
}
```
