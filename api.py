#!/usr/bin/env python
# encoding: utf-8
import json
import robot
from flask import Flask, request, render_template_string, send_file
import os
import subprocess

app = Flask(__name__)
host = os.getenv("HOST", "0.0.0.0")
port = os.getenv("PORT", 8001)
log_directory = os.getenv("ROBOT_LOG_DIR")

template = """
<h1>logs listing</h1>
    {% for file in files %}
    <h2>        
        <a href="{{ (request.path + '/' if request.path != '/' else '') + file }}">
            {{ (request.path + '/' if request.path != '/' else '') + file }}
        </a>
    </h2>
    {% endfor %}
"""


@app.route("/", defaults={"request_path": ""})
@app.route("/<path:request_path>")
def dir_listing(request_path):
    path = f"{log_directory}/{request_path}"
    if not os.path.exists(path):
        return "not found", 404
    if os.path.isfile(path):
        return send_file(path)
    return render_template_string(template, files=os.listdir(path))


@app.route("/", methods=["POST"])
def index():
    if request.method == "POST":
        f = open("./temporary_testfile.robot", "w")
        json_request = json.loads(request.data)
        f.write(json_request["data"])
        f.close()
        log_html_url = f"http://{host}:{port}/codebundle-generator-last-run/codebundle-generator-log.html"
        report_html_url = f"http://{host}:{port}/codebundle-generator-last-run/codebundle-generator-report.html"
        result = subprocess.run(
            [
                "robot",
                "--loglevel",
                "trace",
                "--outputdir",
                f"{log_directory}/codebundle-generator-last-run",
                "--log",
                "codebundle-generator-log.html",
                "--output",
                "codebundle-generator-output.xml",
                "--report",
                "codebundle-generator-report.html",
                "./temporary_testfile.robot",
            ],
            stderr=subprocess.STDOUT,
        )
        print(result.stdout)
        if result.returncode != 0:
            # if robot.run_cli(["--loglevel", "trace", "--outputdir",f"{log_directory}/codebundle-generator-last-run", "--log", "codebundle-generator-log.html", "--output", "codebundle-generator-output.xml", "--report", "codebundle-generator-report.html", "./temporary_testfile.robot"], exit=False) != 0:
            return {
                "status": "error",
                "log_html_url": log_html_url,
                "report_html_url": report_html_url,
            }
        return {
            "status": "ok",
            "log_html_url": log_html_url,
            "report_html_url": report_html_url,
        }


app.run(debug=True, port=port, host=host)
