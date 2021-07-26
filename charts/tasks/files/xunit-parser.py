#!/usr/bin/python3
# Parse [XJ]unit and store results in little files for Tekton results

from glob import glob

import argparse
import logging
import xml.etree.ElementTree as ET


parser = argparse.ArgumentParser()
parser.add_argument("-o", "--output", help="where to output things", default=".")
parser.add_argument("-i", "--input", help="folder containing files", default=".")
parser.add_argument("-l", "--log", help="log level", default="INFO")
parser.add_argument("-a", "--assertion", help="assertion to check", nargs='+', default=["errors=0"])
args = parser.parse_args()

# set logging level using log argument
logging.basicConfig(level=getattr(logging, args.log.upper()))


def parse_testsuite(test):
    for element in results.keys():
        value = test.attrib.get(element)
        if value is None:
            continue

        value = int(value)
        logging.debug(f"reading {element} value = {value}")
        if results[element] is None:
            results[element] = value
        else:
            results[element] += value


results = dict(tests=None, defects=None, errors=None, failures=None, skipped=None, disabled=None)
for file in glob(f"{args.input}/**/*.xml", recursive=True):
    logging.info(f"Opening file {file}")
    try:
        xunit = ET.parse(file)
        if xunit.getroot().tag == "testsuites":
            for testsuite in xunit.findall("testsuite"):
                parse_testsuite(testsuite)
        else:
            parse_testsuite(xunit.getroot())
    except Exception as e:
        logging.info(f"Exception while reading {file}")
        print(file, e)

if results["errors"] or results["failures"] is not None:
    results["defects"] = (results["errors"] or 0) + (results["failures"] or 0)

logging.info("storing parsed values")
for k, v in results.items():
    if v is not None:
        file = f"{args.output}/{k}"
        with open(file, "w") as f:
            logging.debug(f"{file} = {v}")
            f.write(str(v))
