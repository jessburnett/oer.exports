#!/bin/bash

WORKING_DIR=$1
ID=$2
COLID=${3:-0}

DEBUG=$4

echo "LOG: INFO: ------------ Working on $ID ------------"

# If XSLTPROC_ARGS is set (by say a hadoop job) then pass those through

ROOT=`dirname "$0"`
ROOT=`cd "$ROOT/.."; pwd` # .. since we live in scripts/

SCHEMA=$ROOT/docbook-rng/docbook.rng
SAXON="java -jar $ROOT/lib/saxon9he.jar"
JING="java -jar $ROOT/lib/jing-20081028.jar"
# we use --xinclude because the XSLT attempts to load inline svg files
XSLTPROC="xsltproc --xinclude --stringparam cnx.module.id $ID $XSLTPROC_ARGS"
CONVERT="convert "

#Temporary files
CNXML=$WORKING_DIR/index.cnxml
CNXML_UPGRADED=$WORKING_DIR/index_auto_generated.cnxml
CNXML1=$WORKING_DIR/_cnxml1.xml
CNXML2=$WORKING_DIR/_cnxml2.xml
CNXML3=$WORKING_DIR/_cnxml3.xml
CNXML4=$WORKING_DIR/_cnxml4.xml
CNXML5=$WORKING_DIR/_cnxml5.xml
DOCBOOK_INCLUDED=$WORKING_DIR/index.included.dbk # Important. Used in collxml2docbook xinclude
DOCBOOK=$WORKING_DIR/index.dbk # Important. Used in module2epub
DOCBOOK1=$WORKING_DIR/_index1.dbk
DOCBOOK2=$WORKING_DIR/_index2.dbk
DOCBOOK_SVG=$WORKING_DIR/_index.svg.dbk
SVG2PNG_FILES_LIST=$WORKING_DIR/_svg2png-list.txt
VALID=$WORKING_DIR/_valid.dbk
# Custom collection-level params (how to convert content mathml)
PARAMS=$WORKING_DIR/../_params.txt

#XSLT files
CLEANUP_XSL=$ROOT/xsl/cnxml-clean.xsl
CLEANUP2_XSL=$ROOT/xsl/cnxml-clean-math.xsl
SIMPLIFY_MATHML_XSL=$ROOT/xsl/cnxml-clean-math-simplify.xsl
CNXML_TO_DOCBOOK_XSL=$ROOT/xsl/cnxml2dbk.xsl
DOCBOOK_CLEANUP_XSL=$ROOT/xsl/dbk-clean.xsl
DOCBOOK_VALIDATION_XSL=$ROOT/xsl/dbk-clean-for-validation.xsl
MATH2SVG_XSL=$ROOT/xslt2/math2svg-in-docbook.xsl
SVG2PNG_FILES_XSL=$ROOT/xsl/dbk-svg2png.xsl
DOCBOOK_BOOK_XSL=$ROOT/xsl/moduledbk2book.xsl

EXIT_STATUS=0

# remove all the temp files first so we don't accidentally use old ones
[ -a $CNXML1 ] && rm $CNXML1
[ -a $CNXML2 ] && rm $CNXML2
[ -a $CNXML3 ] && rm $CNXML3
[ -a $CNXML4 ] && rm $CNXML4
[ -a $CNXML5 ] && rm $CNXML5
[ -a $DOCBOOK_INCLUDED ] && rm $DOCBOOK_INCLUDED
[ -a $DOCBOOK ] && rm $DOCBOOK
[ -a $DOCBOOK1 ] && rm $DOCBOOK1
[ -a $DOCBOOK2 ] && rm $DOCBOOK2
[ -a $DOCBOOK_SVG ] && rm $DOCBOOK_SVG
[ -a $SVG2PNG_FILES_LIST ] && rm $SVG2PNG_FILES_LIST

# Load up the custom collection params to xsltproc:
if [ -s $PARAMS ]; then
    #echo "Using custom params in params.txt for xsltproc."
    # cat $PARAMS
    OLD_IFS=$IFS
    IFS="
"
    XSLTPROC_ARGS=""
    for ARG in `cat $PARAMS`; do
      if [ ".$ARG" != "." ]; then
        XSLTPROC_ARGS="$XSLTPROC_ARGS --param $ARG"
      fi
    done
    IFS=$OLD_IFS
    XSLTPROC="$XSLTPROC $XSLTPROC_ARGS"
fi

XSLTPROC+=" --param inCollection $COLID"

# Just some code to filter what gets re-converted so all modules don't have to.
#GREP_FOUND=`grep "newline" $CNXML`
#if [ ".$GREP_FOUND" == "." ]; then exit 0; fi

# First check that the XML file is well-formed
#XMLVALIDATE="xmllint --nonet --noout --valid --relaxng /Users/schatz/Documents/workspace/cnxml-schema/cnxml.rng"
XMLVALIDATE="xmllint"
#$XMLVALIDATE $CNXML 2> /dev/null
#if [ $? -ne 0 ]; then exit 0; fi

# Skip validation by just replacing all entities with &amp;
($XMLVALIDATE --nonet --noout $CNXML 2>&1) > $WORKING_DIR/__err.txt
if [ -s $WORKING_DIR/__err.txt ]; then 

  # Try again, but load the DTD this time (and replace the cnxml file)
  echo "Failed without DTD. Trying with DTD" 1>&2
  cat $WORKING_DIR/__err.txt
  CNXML_NEW=$CNXML.new.xml
  ($XMLVALIDATE --loaddtd --noent --dropdtd --output $CNXML_NEW $CNXML 2>&1) > $WORKING_DIR/__err.txt
  if [ -s $WORKING_DIR/__err.txt ]; then 
    echo "LOG: ERROR: Invalid cnxml doc" 1>&2
    cat $WORKING_DIR/__err.txt 1>&2
      exit 1
  fi
  mv $CNXML_NEW $CNXML
fi
#rm $WORKING_DIR/__err.txt


# Use the auto-upgraded cnxml file, otherwise index.cnxml is at the current version 
if [ -s $CNXML_UPGRADED ]; then
  cp $CNXML_UPGRADED $CNXML1
else
  echo "LOG: DEBUG: index_auto_generated.cnxml not found! Assuming index.cnxml is at the latest version" 1>&2
  if [ ! -s $CNXML ]; then
    echo "LOG: ERROR: index.cnxml not found! Cannot convert" 1>&2
    exit 1
  fi
  cp $CNXML $CNXML1
fi

$XSLTPROC -o $CNXML2 $CLEANUP_XSL $CNXML1
EXIT_STATUS=$EXIT_STATUS || $?

$XSLTPROC -o $CNXML3 $CLEANUP2_XSL $CNXML2
EXIT_STATUS=$EXIT_STATUS || $?
# Have to run the cleanup twice because we remove empty mml:mo,
# then remove mml:munder with only 1 child.
# See m21903
$XSLTPROC -o $CNXML4 $CLEANUP2_XSL $CNXML3
EXIT_STATUS=$EXIT_STATUS || $?

# Convert "simple" MathML to cnxml
$XSLTPROC -o $CNXML5 $SIMPLIFY_MATHML_XSL $CNXML4
EXIT_STATUS=$EXIT_STATUS || $?

# Convert to docbook
$XSLTPROC -o $DOCBOOK1 $CNXML_TO_DOCBOOK_XSL $CNXML5
EXIT_STATUS=$EXIT_STATUS || $?

# Convert MathML to SVG
$SAXON -s:$DOCBOOK1 -xsl:$MATH2SVG_XSL -o:$DOCBOOK2
# If there is an error, just use the original file
MATH2SVG_ERROR=$?
EXIT_STATUS=$EXIT_STATUS || $MATH2SVG_ERROR

if [ $MATH2SVG_ERROR -ne 0 ]; then mv $DOCBOOK1 $DOCBOOK2; fi

$XSLTPROC -o $DOCBOOK_SVG $DOCBOOK_CLEANUP_XSL $DOCBOOK2
EXIT_STATUS=$EXIT_STATUS || $?

# Create a list of files to convert from svg to png
$XSLTPROC -o $DOCBOOK_INCLUDED $SVG2PNG_FILES_XSL $DOCBOOK_SVG 2> $SVG2PNG_FILES_LIST
EXIT_STATUS=$EXIT_STATUS || $?

# Create a standalone db:book file for the module
$XSLTPROC -o $DOCBOOK $DOCBOOK_BOOK_XSL $DOCBOOK_INCLUDED
EXIT_STATUS=$EXIT_STATUS || $?

# Convert the SVG files to an image
for ID_AND_EXT in `cat $SVG2PNG_FILES_LIST`
do
  ID=${ID_AND_EXT%%|*}
  EXT=${ID_AND_EXT#*|}
  if [ -s $WORKING_DIR/$ID.svg ]; then
      echo "LOG: DEBUG: Converting-SVG $ID to $EXT"
      # For Macs, use inkscape
      if [ -e /Applications/Inkscape.app/Contents/Resources/bin/inkscape ]; then
        # Default DPI is 90, so double it
        DPI=180
        (/Applications/Inkscape.app/Contents/Resources/bin/inkscape $WORKING_DIR/$ID.svg --export-$EXT=$WORKING_DIR/$ID.$EXT --export-dpi=180 2>&1) > $WORKING_DIR/__err.txt
        EXIT_STATUS=$EXIT_STATUS || $?
      else
        $CONVERT -density 100x100 $WORKING_DIR/$ID.svg $WORKING_DIR/$ID.$EXT
        EXIT_STATUS=$EXIT_STATUS || $?
      fi
  else
    # Print saner error messages.
    # For example, Adobe illustrator generates SVG files that are invalid XML.
    # Those parsing errors show up and are misinterpreted
    #   as SVG files that should be converted.
    echo "LOG: ERROR: Converting-SVG: SVG file not found: $ID"
    EXIT_STATUS=$EXIT_STATUS || 1
  fi
done


# remove all the temp files so the complete zip doesn't contain them
if [ ".$DEBUG" == "." ]; then
  [ -a $WORKING_DIR/__err.txt ] && rm $WORKING_DIR/__err.txt
  [ -a $CNXML1 ] && rm $CNXML1
  [ -a $CNXML2 ] && rm $CNXML2
  [ -a $CNXML3 ] && rm $CNXML3
  [ -a $CNXML4 ] && rm $CNXML4
  [ -a $CNXML5 ] && rm $CNXML5
  [ -a $DOCBOOK1 ] && rm $DOCBOOK1
  [ -a $DOCBOOK2 ] && rm $DOCBOOK2
  [ -a $DOCBOOK_SVG ] && rm $DOCBOOK_SVG
  [ -a $SVG2PNG_FILES_LIST ] && rm $SVG2PNG_FILES_LIST
fi

echo "LOG: DEBUG: Skipping Docbook Validation. Remove next line to enable"
exit $EXIT_STATUS

# Create a file to validate against
$XSLTPROC -o $VALID $DOCBOOK_VALIDATION_XSL $DOCBOOK
EXIT_STATUS=$EXIT_STATUS || $?

# Validate
$JING $SCHEMA $VALID # 1>&2 # send validation errors to stderr
RET=$?
if [ $RET -eq 0 ]; then rm $VALID; fi
if [ $RET -eq 0 ]; then echo "LOG: BUG: Validation Errors" 1>&2 ; fi

exit $EXIT_STATUS || $RET
