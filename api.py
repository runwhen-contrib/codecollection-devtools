#!/usr/bin/env python
# encoding: utf-8
import json
import robot
from flask import Flask, request, render_template_string, send_file
import os

app = Flask(__name__)

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
        if robot.run("./temporary_testfile.robot") != 0:
            return {"status": "error"}
    return {"status": "ok"}


@app.route("/report")
def get_report():
    try:
        f = open("./report.html", "r")
        report = f.read()
        f.close()
    except FileNotFoundError:
        return "not found", 404
    return report


@app.route("/log")
def get_log():
    try:
        f = open("./log.html", "r")
        log = f.read()
        f.close()
    except FileNotFoundError:
        return "not found", 404
    return log


app.run(debug=True, port=8001, host="0.0.0.0")
