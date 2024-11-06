from setuptools import setup, find_packages

with open("requirements.txt") as f:
    required = f.read().splitlines()

with open("VERSION") as f:
    version_info = json.load(f)

setup(
    name=version_info["name"],
    version=version_info["version"],
    packages=find_packages(where="dev_facade"),
    package_dir={"": "dev_facade"},
    license="Apache License 2.0",
    description="A set of RunWhen Developer keywords and python libraries for local development",
    long_description=open("README.md").read(),
    long_description_content_type="text/markdown",
    author="RunWhen",
    author_email="info@runwhen.com",
    url="https://github.com/runwhen-contrib/rw-cli-codecollection",
    install_requires=required,
    include_package_data=True,
    classifiers=[
        "Programming Language :: Python :: 3",
        "License :: OSI Approved :: Apache Software License",
    ],
)
