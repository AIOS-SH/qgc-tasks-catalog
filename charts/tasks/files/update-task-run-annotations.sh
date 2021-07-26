#!/bin/bash
set -e

dirname=$(dirname $0)
dirname=$(cd "${dirname}" ; pwd)
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY

cd /tekton/results
for result in *
do
  annotation="results/$result=$(<$result)"
  python3 ${dirname}/update-task-run-annotations.py -a "${annotation}"
done
