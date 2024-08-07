"""A set of python interfaces also exposed in RW.Core (and used outside of that)"""
import requests, os, pprint, traceback, json
from typing import Union, Optional, List
from dataclasses import dataclass, field
from robot.api import logger as user_logger
from robot.api import Failure, Error, FatalError, logger
from robot.libraries.BuiltIn import BuiltIn

import logging

platform_logger = logging.getLogger(__name__)
robot_builtin = BuiltIn()

session = None

from . import proxy

REQUEST_VERIFY=proxy.get_request_verify()


class TemporaryException(Exception):
    pass


class PermanentException(Exception):
    pass


class InputException(PermanentException):
    pass


class Secret:
    """The secret class is used as a wrapper around secret values to track their usage
    and to make sure they don't accidentally escape in to logs as strings.  Keyword
    authors should take instances of Secret as arguments when they suspect that the
    content of the string is sensitive, prompting Robot authors to add import secret
    commands and flag this sensitivity to users.
    """

    def __init__(self, key: str, val: str):
        self._key = key
        self._val = val

    @property
    def value(self):
        stack = traceback.format_stack()
        robot_builtin.log(f"secret {self._key} accessed from callstack {stack}")
        return self._val

    @property
    def key(self):
        return self._key

    def __str__(self):
        return "*" * len(self.value)


@dataclass(frozen=True)
class Service:
    """The secret class is used as a wrapper around service URLs, created by
    the Import Service keyword.  (Over time, the gist is to offer health
    check / status / version params as well as providing the basic URL
    for robot authors.)
    """

    url: str

    def health_check(self):
        """A stub implementation for now, should raise an Exception
        if the service is not currently healthy.
        """
        return True


@dataclass(frozen=True)
class ShellServiceRequestSecret:
    secret: Secret
    as_file: bool = False


@dataclass(frozen=True)
class ShellServiceRequest:
    cmd: str
    request_secrets: List[ShellServiceRequestSecret] = field(default_factory=lambda: [])
    env: dict = field(default_factory=lambda: {})
    files: dict = field(default_factory=lambda: {})
    timeout_seconds: int = 60

    def to_json(self):
        """Serialize this request out to json appropriate for shell service post body.  (The default
        todict implementation of dataclasses doesn't serialize the request_secrets, so this
        replaces it for the common use case.)
        """
        # Without the nested dataclass or camel case, this would be json.dumps(self.todict()),
        # but we have both
        obj = {}
        obj["cmd"] = self.cmd
        if self.request_secrets:
            obj["secrets"] = [
                {"key": s.secret.key, "value": s.secret.value, "file": s.as_file} for s in self.request_secrets
            ]
        if self.files:
            obj["files"] = self.files
        if self.env:
            obj["env"] = self.env
        return json.dumps(obj)


@dataclass(frozen=True)
class ShellServiceResponse:
    cmd: str  # The original cmd string given
    parsed_cmd: str = None  # Useful for debugging long commands
    stdout: str = None  # stdout from running cmd
    stderr: str = None  # stderr from running cmd
    returncode: int = -1  # The returncode from running cmd
    status: int = 500  # The http status code from the service, representing any errors
    # the plumbing pre/post command
    body: str = ""  # The raw body of the response as a string for troubleshooting plumbing errors
    # A list of strings with error messages from the plumbing and cmd results
    errors: List[str] = field(default_factory=lambda: [])

    @staticmethod
    def from_json(obj, status_code=200):
        """De-serialize this request from a json obj found in shell service http response and the status_code"""
        if isinstance(obj, list):
            if len(obj) != 1:
                raise ValueError(
                    f"Trying to parse JSON string in to ShellServiceResponse, but"
                    + f"JSON string had more than one object {str(obj)}"
                )
            else:
                obj = obj[0]
        # Note conversion from camelcase is required (and not worth another dependency IMHO)
        try:
            ret = ShellServiceResponse(
                cmd=obj["cmd"],
                parsed_cmd=obj["parsedCmd"],
                stdout=obj["stdout"],
                stderr=obj["stderr"],
                returncode=obj["returncode"],
                status=status_code,
            )
            return ret
        except KeyError as ke:
            raise TaskError(
                f"Error parsing shell service response {type(ke)}: {ke} from object {obj} and status code {status_code}"
            )


class TaskFailure(Failure):
    """
    This exception can be raised for a task failure due to a failed
    validation.
    """


class TaskError(Error):
    """
    This exception can be raised for a task error caused by a malfunction
    or unexpected result.
    """


def error_log(*msg, console: Union[bool, str] = False, if_true: Optional[str] = None) -> None:
    """
    Note: Error logs are automatically written to console.
    """
    if if_true is not None and BuiltIn().evaluate(if_true) is not True:
        return
    _ = console
    for s in msg:
        if not isinstance(s, str):
            s = pprint.pformat(s, indent=1, width=80)
        if console or isinstance(console, str) and console.lower() == "true":
            robot_builtin.log_to_console(f"\n{str(s)}")
        logger.error(str(s))


def warning_log(*msg, console: Union[bool, str] = False, if_true: Optional[str] = None) -> None:
    """
    Note: Warning logs are automatically written to console.
    """
    if if_true is not None and BuiltIn().evaluate(if_true) is not True:
        return
    _ = console
    for s in msg:
        if not isinstance(s, str):
            s = pprint.pformat(s, indent=1, width=80)
        if console or isinstance(console, str) and console.lower() == "true":
            robot_builtin.log_to_console(f"\n{str(s)}")
        logger.warn(str(s))


def info_log(*msg, console: Union[bool, str] = False, if_true: Optional[str] = None) -> None:
    if if_true is not None and BuiltIn().evaluate(if_true) is not True:
        return
    _ = console
    for s in msg:
        if not isinstance(s, str):
            s = pprint.pformat(s, indent=1, width=80)
        if console or isinstance(console, str) and console.lower() == "true":
            robot_builtin.log_to_console(f"\n{str(s)}")
        logger.info(str(s))


def debug_log(*msg, console: Union[bool, str] = False, if_true: Optional[str] = None) -> None:
    if if_true is not None and BuiltIn().evaluate(if_true) is not True:
        return
    _ = console
    for s in msg:
        if not isinstance(s, str):
            s = pprint.pformat(s, indent=1, width=80)
        if console or isinstance(console, str) and console.lower() == "true":
            robot_builtin.log_to_console(f"\n{str(s)}")
        logger.debug(str(s))


def trace_log(*msg, console: Union[bool, str] = False, if_true: Optional[str] = None) -> None:
    if if_true is not None and BuiltIn().evaluate(if_true) is not True:
        return
    _ = console
    for s in msg:
        if not isinstance(s, str):
            s = pprint.pformat(s, indent=1, width=80)
        if console or isinstance(console, str) and console.lower() == "true":
            robot_builtin.log_to_console(f"\n{str(s)}")
        logger.trace(str(s))


def console_log(*msg) -> None:
    info_log(*msg, console=True)


def console_log_if_true(condition: str, *msg) -> None:
    info_log(msg, console=True, if_true=condition)


def form_access_token():
    access_token = os.getenv("RW_ACCESS_TOKEN")
    if not access_token:
        doc_url = "https://docs.runwhen.com/public/platform-rest-api/getting-started-with-the-platform-rest-api"
        raise Exception(
            f"When doing local dev please refer to {doc_url} to set RW_ACCESS_TOKEN in your local environment variables"
        )
    return access_token


def get_authenticated_session():
    """Returns a request.session object authenticated to the RW public API using the
    RW_ACCESS_TOKEN that should be available (either a user or service acct)
    """
    global session
    if session:
        return session
    session = requests.Session()
    access_token = form_access_token()
    session.headers.update(
        {
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        }
    )
    return session


def execute_shell_command(
    cmd: str,
    service: Service,
    request_secrets: List[ShellServiceRequestSecret] = None,
    env: dict = None,
    files: dict = None,
):
    ss_req = ShellServiceRequest(cmd=cmd, request_secrets=request_secrets, env=env, files=files)
    url = service.url + "/api/v1/cmd"
    headers = {"Content-type": "application/json", "Accept": "application/json"}
    try:
        rsp = requests.post(url, data=ss_req.to_json(), headers=headers)
        response_obj = rsp.json()
        ss_rsp = ShellServiceResponse.from_json(response_obj, rsp.status_code)
        logger.debug(f"execute_shell_command with shell service requrest: {ss_req} and received response {ss_rsp}")
        return ss_rsp
    except requests.JSONDecodeError as e:
        raise TaskFailure(
            f"JSON Decode Error {type(e)}: {e} trying to parse shell service response from response {rsp} with body {rsp.text}"
        ) from e
