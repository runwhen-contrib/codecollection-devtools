"""
A file for shared functions relating to proxying requests to the RW API
"""

import os

def get_request_verify():
    """Returns the value of the REQUESTS_CA_BUNDLE environment variable, or None if it is not set"""

    if os.getenv("ROBOT_DEV") == "true":
        return os.getenv("REQUESTS_CA_BUNDLE", None)
    # If we're not in a dev environment, we need to use a workaround to handle the REQUESTS_CA_BUNDLE environment variable
    # for now to skip verification of the SSL certificate.
    return get_request_verify_workaround()

def get_request_verify_workaround():
    """
    If the REQUESTS_CA_BUNDLE environment variable is not set, returns None. otherwise return False.
    This is a workaround for the fact that the requests library does not handle the REQUESTS_CA_BUNDLE
    environment variable when using a venv by default. There's a potential workaround for this either
    using pip-system-certs or truststore but this is a workaround for now until there's time to investigate further.
    """

    if os.getenv("REQUESTS_CA_BUNDLE", None) is None:
        return None
    return False