#!/bin/bash
# Download a Azure blob container and analyze content for xunit files

# If something is wrong: exiting
set -e

# Override this values for testing purpose
TEKTON_RESULTS=${TEKTON_RESULTS:-"/tekton/results"}
DAY_TO_LOCK=${DAY_TO_LOCK:-"1"}
LEGAL_TAG=${LEGAL_TAG:-"qgccontainer"}
ASSERTIONS=${ASSERTIONS:-"defects=0"}

dir_name=$(dirname "$0")

ENV_VARS="AZURE_STORAGE_ACCOUNT CONTAINER_NAME AZURE_STORAGE_KEY"

for env_var in ${ENV_VARS}
do
  value=$(eval echo "\$$env_var")
  if [ -z "${value}" ]; then echo "Missing value for $env_var env var" ; exit 1 ; fi
done

CONTAINER_DIR="/tmp/${CONTAINER_NAME}"

# Clean up the container directory to handle running this script locally
rm -rf "${CONTAINER_DIR}" && mkdir -p "${CONTAINER_DIR}"

# Retrieve container content then, analyze, update annotations and check assertions
az storage blob download-batch -s "${CONTAINER_NAME}" -d "${CONTAINER_DIR}"

# Check for evidence in zip file
for zip in $(find $CONTAINER_DIR -name "evidence-*.zip")
do
  echo "Unzip $zip in progress"
  (cd $CONTAINER_DIR && unzip $zip)
done

python3 "${dir_name}/xunit-parser.py" -i "${CONTAINER_DIR}" -o "${TEKTON_RESULTS}"

bash -c "${dir_name}/update-task-run-annotations.sh"

python3 "${dir_name}/check-assertions.py" -r "${TEKTON_RESULTS}" --assertion ${ASSERTIONS}

# Retrieve etag of the immutability policy. Needed to lock container
#etag=$(az storage container immutability-policy create --account-name "${AZURE_STORAGE_ACCOUNT}" \
#            -c "${CONTAINER_NAME}" --period "${DAY_TO_LOCK}" -o tsv --query "etag")
#
#az storage container immutability-policy lock --account-name "${AZURE_STORAGE_ACCOUNT}" \
#    -c "${CONTAINER_NAME}" --if-match "${etag}"

# For the moment, let use legal hold bit for testing purpose and check immutability later
# TODO: launch this command for real with a Azure service account capable of launching this command
#       for the moment, the real command is not working and tells us to use az login.
echo az storage container legal-hold set \
    --account-name "${AZURE_STORAGE_ACCOUNT}" --container-name "${CONTAINER_NAME}" \
    --tag "${LEGAL_TAG}"
