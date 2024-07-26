"""
Core keyword library

Scope: Global
"""

import re
import os
from typing import Union, List
from robot.libraries.BuiltIn import BuiltIn
from RW import platform
import logging

import json
import textwrap
from collections import OrderedDict

logger = logging.getLogger(__name__)


class Core:
    """Core keyword library defines keywords used to access key platform features from robot code."""

    ROBOT_LIBRARY_SCOPE = "GLOBAL"

    def __init__(self) -> None:
        self.builtin = BuiltIn()  # TODO - use get library instance

    def import_secret(self, varname: str, description: str = None, example: str = None, pattern: str = None, **kwargs):
        skeys_json_str = os.getenv("RW_SECRET_REMAP", "{}")
        fkeys_json_str = os.getenv("RW_FROM_FILE", "{}")
        secret_remaps = json.loads(skeys_json_str)
        secrets_from_files = json.loads(fkeys_json_str)
        if varname in secret_remaps:
            key = secret_remaps.get(varname)
        else:
            key = varname

        if key in secrets_from_files.keys():
            secret_filepath = secrets_from_files[key]
            with open(secret_filepath) as fh:
                val = fh.read()
        else:
            val = os.getenv(key, "")
        ret = platform.Secret(varname, val)
        self.builtin.set_suite_variable("${" + varname + "}", ret)
        return ret

    def import_service(self, varname: str, description: str = None, example: str = None, default: str = None, **kwargs):
        """Creates an instance of rwplatform.Service for use by other keywords.

        Note that the description, example, default args are parsed in RunWhen static
        analysis for type hinting in the GUI, and are not (currently) used here.
        """
        env_var_url = "RW_SVC_URLS"
        urls_json_str = os.getenv(env_var_url)
        if not urls_json_str:
            raise ImportError(
                f"Import Service {varname}: No services provided in configuration ({env_var_url} has no value set)"
            )
        url = json.loads(urls_json_str).get(varname)
        if not url:
            raise ImportError(f"Import Service {varname}: No service provided, found only ({urls_json_str})")
        ret = platform.Service(url)
        self.builtin.set_suite_variable("${" + varname + "}", ret)
        return ret

    def import_user_variable(
        self,
        varname: str,
        type: str = "string",
        description: str = None,
        example: str = None,
        pattern: str = None,
        enum: str = None,
        format: str = None,
        default: str = None,
        **kwargs,
    ) -> str:
        """
        Imports a variable set by the user, raises error if not available.
        When locally run these correspond to environment variables.
        The user may remap what environment key names are imported by setting the `RW_ENV_REMAP` environment variable.

        Example:
          Import User Variable   FOO
          Debug Log              ${FOO}

        Throws an error if the config variable doesn't exist and no default is
        provided (Implementation subject to change)

        Impl note - the optional args correspond to JSONSchema / OpenAPIv3 properties that are used in RW's static
        analysis of robot code to do type hinting and validation in the ui and pre-commit hooks, i.e. they
        are not (currently) consumed in this code.  For type, we currently support "string", "boolean", "number",
        "integer".  Description and Example should be short phrase or single sentence strings.  Enum, for Robot
        ease-of-use, should be a string of comma-separated values (typically strings themselves) without escaped
        quotes or brackets, e.g. the python call would look like enum="option-1,option-2,option-3" and the Robot
        call looks like enum=option-1,option-2,option-3.
        """
        ekeys_json_str = os.getenv("RW_ENV_REMAP", "{}")
        env_remaps = json.loads(ekeys_json_str)
        if varname in env_remaps:
            key = env_remaps.get(varname)
            val = os.getenv(key, "")
        else:
            val = os.getenv(varname, "")
        if default and not val:
            val = default
        self.builtin.set_suite_variable("${" + varname + "}", val)
        return val

    def run_keyword_and_push_metric(self, name: str, *args) -> None:
        """
        Run a keyword and push the returned metric up to the MetricStore.
        This should only be called once per sli.robot file.

        Example:
          Run Keyword and Push Metric   Ping Hosts and Return Highest Avg RTT
          ...                           hosts=${PING_HOSTS}
        """
        self.debug_log(f"Running keyword: {name}, arguments: {args}")
        result = self.builtin.run_keyword(name, *args)
        self.debug_log(f"Push metric result: {result}")
        return self.push_metric(result)

    GAUGE = "gauge"
    COUNTER = "counter"
    HISTOGRAM = "histogram"
    UNTYPED = "untyped"

    def push_metric(
        self,
        value=None,
        sub_name=None,
        metric_type=UNTYPED,
        dry_run=False,
        **kwargs,
    ):
        """
        Used to push a metric up to the MetricStore.  Each SLX has a single default metric
        by default that all SLIs should use where the sub_name should be set to None.
        Callers may also use this method multiple times in a single SLI with subsequent
        metric sub_name args set to various strings in order to push multiple metrics in
        addition to the default.

        Examples:
            #Base case test
            Push Metric   10

            #Try with a sub-name
            Push Metric   11      sub_name=some_non_default_metric

            #Try various types
            Push Metric   12      sub_name=as_gauge  metric_type=gauge
            Push Metric   13      sub_name=as_counter  metric_type=counter

            #Try with labels
            Push Metric   12      sub_name=with_labels  a_label=a    b_label=b     c_label=c

        Example:
          Push Metric	5
          Push Metric	5	http_code=200 #Pushes a metric names
          Push Metric   10  sub_name=foo    type=${GAUGE}   http_code=300 #Pushes a non-defualt metric

        Note that calls to Push Metric are not exactly atomic. Once a metric/sub-metric is pushed
        with a set of labels in the scope of a Suite, it is expected that any
        subsequent calls have the same set of labels.  Since it would be very
        odd (an error?) to have any metric/sub-metric called in more than one place per Suite,
        this doesn't seem like a constraint in practice.
        """
        # Note that during local dev this simply logs to the console.
        self.builtin.log_to_console(
            f"\nPush metric: value:{value} sub_name:{sub_name} metric_type:{metric_type} labels:{kwargs}\n"
        )

    def task_failure(self, msg: str) -> None:
        """
        Report a validation failure. Skip to the next task/test.

        :param msg: Log message
        """
        raise platform.TaskFailure(msg)

    def task_error(self, msg: str) -> None:
        """
        Report an error in execution. Skip to the next task/test.

        :param msg: Log message
        """
        raise platform.TaskError(msg)

    def fatal_error(self, msg: str) -> None:
        """
        Report a fatal error. Stop the whole robot execution.

        :param msg: Log message
        """
        raise platform.FatalError(msg)

    def error_log(self, *args, **kwargs) -> None:
        """
        Error log

        :param msg: Log message
        """
        platform.error_log(*args, **kwargs)

    def warning_log(self, *args, **kwargs) -> None:
        """
        Warning log

        :param msg: Log message
        """
        platform.warning_log(*args, **kwargs)

    def info_log(self, *args, **kwargs) -> None:
        """
        Info log

        :param msg: Log message
        """
        platform.info_log(*args, **kwargs)

    def inspect_object_attributes(self, d, console: Union[str, bool] = False) -> None:
        platform.debug_log(dir(d), console=console)

    def debug_log(self, *args, **kwargs) -> None:
        """
        Debug log

        :param str: Log message
        :param console: Write log message to console (default is true)
        """
        platform.debug_log(*args, **kwargs)

    def trace_log(self, *args, **kwargs) -> None:
        """
        Trace log

        :param msg: Log message
        """
        platform.trace_log(*args, **kwargs)

    def console_log(self, *args, **kwargs) -> None:
        platform.console_log(*args, **kwargs)

    def console_log_if_true(self, *args, **kwargs) -> None:
        """
        If the condition is evaluated to true, the message is written to the
        console.

        :param condition: Condition to evaluate as a Python expression
        :param msg: Log message
        """
        platform.console_log_if_true(*args, **kwargs)

    def add_to_report(
        self,
        obj: object,
        fmt: str = "p",
        **kwargs,
    ) -> None:
        """
        Generic keyword used to add to reports.  The common case is adding a string
        with "p" formatting, but this is intended to be extensible to include pre-formatted
        blocks, code blocks, links and potentially chart data.
        """
        # for local dev, simply output to the console
        self.builtin.log_to_console(f"\n{obj}\n")

    def add_code_to_report(self, obj: str) -> None:
        """Add a block of text to the report that should follow
        similar formatting rules as the html tag "code"
        """
        return self.add_to_report(obj=str(obj), fmt="code")

    def add_pre_to_report(self, obj: str) -> None:
        """Add a block fo text to the report that should follow
        similar formatting rules as the html tag "pre"
        """
        return self.add_to_report(obj=str(obj), fmt="pre")

    def add_url_to_report(self, url: str, text: str = None) -> None:
        """Add a url fo text to the report that should follow
        similar formatting rules as the html tag "pre"
        """
        return self.add_to_report(obj=str(url), fmt="a", text=text)

    def add_json_to_report(self, obj) -> None:
        """Add a json string or json serializable object to the report implying to
        most formatters that it shoudl be pretty printed.  Internally this is stored
        as in object rather than string form.
        """
        if isinstance(obj, str):  # If we got a string, make sure it is valid json
            obj = json.loads(obj)
        elif isinstance(obj, object):  # If we got an object, make sure it serializes safely
            json.dumps(obj)
        return self.add_to_report(obj=obj, fmt="json")

    def add_table_to_report(self, about: str, body: list, head: list) -> None:
        """Adds a table of data to the report.  The 'about' string should be
        rendered to the left, right or below the table.  The body is expected to
        be a 2d array of strings.  head is a 1d array of strings.  The gist
        is to map closesly to an html table element.
        """
        body_o = body
        head_o = head
        return self.add_to_report(obj=about, fmt="table", body=body_o, head=head_o)

    def add_datagrid_to_report(
        self,
        about: str,
        rows: list,
        columns: list,
        page_size: int,
        rows_per_page_options: list[int],
    ) -> None:
        """Adds an object that will map closely to a MUI datagrid.  For args,
        see https://mui.com/x/react-data-grid/
        """
        return self.add_to_report(
            obj=str(about),
            fmt="table",
            rows=rows,
            columns=columns,
            page_size=page_size,
            rows_per_page_options=rows_per_page_options,
        )

    def get_report_data(self) -> object:
        """Return the data for this report as an object (not formatted)"""
        return self._report

    def get_report_data_as_string(self) -> str:
        """Return the data for this report (with all formatting hints)
        as a string
        """
        return json.dumps(self._report, indent=2)

    def _code_to_string(self, obj) -> str:
        """Converts a "code" obj to a string"""
        return str(obj)

    def _pre_to_string(self, obj) -> str:
        """Converts a "pre" obj to a string"""
        return str(obj)

    def _p_to_string(self, obj) -> str:
        """Converts a "p" obj to a string"""
        lines = textwrap.wrap(" ".join(str(obj).split()))
        return "\n".join(lines)

    def _a_to_string(self, obj, text) -> str:
        """Converts a "a" obj to a string"""
        if text:
            return f"{text} ({obj})"
        else:
            return f"{obj}"

    def _json_to_string(self, obj) -> str:
        """Converts a "json" string or json-serializable object to a (prettified) string"""
        if isinstance(obj, str):
            obj = json.loads(obj)
        return json.dumps(obj, indent=2)

    def _table_to_string(self, about, body, head) -> str:
        """Converts a "table" obj to a string"""
        max_lens = []  # Calculate max length of the text in each column
        for col in range(0, len(head)):
            max_lens.append(len(str(head[col])))
        for row in body:
            for col in range(0, len(row)):
                max_lens[col] = max(max_lens[col], len(str(row[col])))
        ret = []
        ret_row = []
        for i in range(0, len(head)):
            txt = head[i]
            max_len = max_lens[i]
            ret_row.append(f"{txt:>{max_len}}")
        ret.append("|".join(ret_row))
        for row in body:
            ret_row = []
            for i in range(0, len(row)):
                txt = row[i]
                max_len = max_lens[i]
                ret_row.append(f"{txt:>{max_len}}")
            ret.append("|".join(ret_row))
        ret.append(about)
        return "\n".join(ret)

    def _datagrid_to_string(self, about, rows, columns) -> str:
        return self._json_to_string(rows)

    def import_platform_variable(self, varname: str, *args, **kwargs) -> str:
        """
        Imports a variable set by the platform, making it available in the robot runtime
        as a suite variable.
        Raises ValueError if this isn't a valid platform variable name, or ImportError if not available.
        :param str: Name to be used both to lookup the config val and for the
            variable name in robot
        :return: The value found
        """
        # in local dev, simply import from local environment
        return self.import_user_variable(varname, *args, **kwargs)

    def import_memo_variable(self, key: str, *args, **kwargs):
        """
        Imports a value from the "memo" dict created when the request to run
        was first submitted.  (Note - this is specific to runbooks.  If an SLI,
        this simply returns None.). If the memo was not found or this key was not
        found, simply return None.
        Like Import Platform Variable, this will both set a suite level variable
        to key with the value found and will return the value.
        """
        # in local dev mode, we will import this from a file location specified by an env var
        # val = platform.import_memo_variable(key)
        # self.builtin.set_suite_variable("${" + key + "}", val)
        # return val

        fkeys_json_str = os.getenv("RW_MEMO_FILE", "{}")
        memos_from_files = json.loads(fkeys_json_str)
        if key in memos_from_files.keys():
            memo_filepath = memos_from_files[key]
            with open(memo_filepath) as fh:
                val = fh.read()
            self.builtin.set_suite_variable("${" + key + "}", val)
            return val
        else:
            raise ValueError(
                f"Memo key {key} could not be found or read. Please check value of env RW_MEMO_FILE"
            )

    def shell(
        self,
        cmd: str,
        service: platform.Service,
        request_secrets: List[platform.ShellServiceRequestSecret] = None,
        secret: platform.Secret = None,
        secret_as_file: bool = False,
        env: dict = None,
        files: dict = None,
    ):
        """Robot Keyword to expose rwplatform.execute_shell_command.

        For robot syntax convenience, a single secret and secret_as_file may be given instead of or in addition
        to the request_secrets arg (an array of ShellServiceRequestSecrets).  This will wrap secret and secret_as_file in
        to a one-item list of ShellServiceRequestSecrets, adding the request_secrets list if one was given.
        """
        if not isinstance(service, platform.Service):
            raise ValueError(
                f"service {service} is not an instance of rwplatform.Service - check arg type from Robot, see import_service"
            )
        request_secrets_p = request_secrets[:] if request_secrets else []
        if secret:
            ssrs = platform.ShellServiceRequestSecret(secret=secret, as_file=secret_as_file)
            request_secrets_p.append(ssrs)
        return platform.execute_shell_command(
            cmd=cmd, service=service, request_secrets=request_secrets_p, env=env, files=files
        )

    def add_issue(
        self,
        severity: int,
        title: str,
        expected: str = "",
        actual: str = "",
        reproduce_hint: str = "",
        details: str = "",
        next_steps: str = "",
        **kwargs,
    ) -> None:
        issue_str: str = f"\nRaising Issue: Severity: {severity}\n title: {title}\n expected: {expected}\n actual: {actual}\n reproduce hints: {reproduce_hint}\n details: {details}\n next_steps: {next_steps}\n kwargs: {kwargs}\n"
        logger.info(issue_str)
        self.builtin.log_to_console(issue_str)
