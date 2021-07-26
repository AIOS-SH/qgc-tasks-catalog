#!/usr/bin/python3

from os import getenv
import requests

KUBE_API = getenv("KUBE_API", "https://kubernetes.default")
SECRETS_PATH = getenv("SECRETS_PATH", "/var/run/secrets/kubernetes.io/serviceaccount")
(CA_CERT, TOKEN_PATH, NAMESPACE_PATH) = (f"{SECRETS_PATH}/ca.crt", f"{SECRETS_PATH}/token", f"{SECRETS_PATH}/namespace")


def read_content(filename):
    with open(filename, 'r') as content_file:
        return content_file.read().strip()


def get_kube_connections():
    (k8s_namespace, http_headers) = (None, {})
    token = read_content(TOKEN_PATH)
    k8s_namespace = read_content(NAMESPACE_PATH)
    http_headers["Authorization"] = f"Bearer {token}"
    http_headers["Content-Type"] = "application/json-patch+json"
    return k8s_namespace, http_headers


def get_ca_cert():
    return CA_CERT


def get_namespace():
    return read_content(NAMESPACE_PATH)


def get(context):
    (k8s_namespace, http_headers) = get_kube_connections()
    return requests.get(
        f"{KUBE_API}/{context}",
        headers=http_headers,
        verify=CA_CERT
    )


def patch(context, data):
    (k8s_namespace, http_headers) = get_kube_connections()
    return requests.patch(
        f"{KUBE_API}/{context}",
        data=data,
        headers=http_headers,
        verify=CA_CERT
    )
