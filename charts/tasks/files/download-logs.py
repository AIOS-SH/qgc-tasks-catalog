#!/usr/bin/python3
# Retrieve logs of all containers from current pods

from os import getenv, makedirs
from os.path import isdir
import argparse
from kubelib import get, get_namespace

parser = argparse.ArgumentParser()
parser.add_argument("-p", "--pod", help="pods name")
parser.add_argument("-s", "--skip", help="container logs to skip", nargs='+', default=[])
args = parser.parse_args()

k8s_namespace = get_namespace()

pod_api_endpoint = f"api/v1/namespaces/{k8s_namespace}/pods/{getenv('HOSTNAME')}"
pod_def = get(pod_api_endpoint)
pod = response = pod_def.json()

EVIDENCE_DIRECTORY = getenv("EVIDENCE_DIRECTORY", "/evidence/container-logs")

for container in [container["name"] for container in pod["spec"]["containers"]]:
    if container in args.skip:
        continue
    log_api_endpoint = f"{pod_api_endpoint}/log?container={container}"
    log_def = get(log_api_endpoint)
    if not isdir(EVIDENCE_DIRECTORY):
        makedirs(EVIDENCE_DIRECTORY)
    with open(f"{EVIDENCE_DIRECTORY}/{container}.log", "w") as f:
        f.write(log_def.text)
