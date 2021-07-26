#!/usr/bin/python3
# Low level Python script to communicate with Kubernetes API to update task run annotations
# We dont use python client API because we run this script in a container that dont have this dependency

import argparse
import logging
from os import getenv
from kubelib import get_namespace, patch


parser = argparse.ArgumentParser()
parser.add_argument("-a", "--annotations", help="annotations to add", nargs='+', default=[])
parser.add_argument("-t", "--task-run",    help="task run name to update", default=getenv("TASK_RUN"))
parser.add_argument("-l", "--log",         help="log level", default="INFO")
parser.add_argument("-n", "--namespace",   help="namespace", default=get_namespace())
args = parser.parse_args()

# set logging level using log argument
logging.basicConfig(level=getattr(logging, args.log.upper()))
assert args.task_run, "Please provide task run var"
task_run = args.task_run


logging.debug("generating patch")
patches = []

for annotation in args.annotations:
    (k, v) = annotation.split("=", 1)
    # Replace '/' characters by ~1. Check https://tools.ietf.org/html/rfc6901#section-3 for more explanations
    k = k.replace("/", "~1")
    logging.debug(f"annotation: {k} = {v}")
    patches.append({"op": "replace", "path": f"/metadata/annotations/{k}", "value": str(v)})

logging.debug(f"Patches content: {patches}")

logging.info(f"Updating task run annotations ({args.annotations})")
task_run_def = patch(
    f"apis/tekton.dev/v1beta1/namespaces/{args.namespace}/taskruns/{task_run}",
    data=str(patches).replace("'", '"')
)
response = task_run_def.json()
logging.debug(f"Responce from Kube: {response}")
assert task_run_def, "Error while updating TaskRun object definition"
