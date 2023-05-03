#!/bin/bash

if [[ $1 == "help" ]]; then
  echo "usage: ./stop.sh [results_directory]"
  echo "stop.sh is a cleanup tool for start.sh local environment.  It attempts"
  echo "to run the network cleanup function on the network in [results_directory]"
  echo "which is by default results/ in the present working directory."
  exit
fi

if [ ! -z $1 ]
then
  RESULTSDIR=$1
else
  RESULTSDIR=results
fi

source network/cleanup.sh $RESULTSDIR
finish
mv results results.bak
