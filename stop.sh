#!/bin/bash

if [ ! -z $1 ]
then
  RESULTSDIR=$1
else
  RESULTSDIR=results
fi

source network/cleanup.sh $RESULTSDIR
finish
mv results results.bak
