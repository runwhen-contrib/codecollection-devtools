from setuptools import setup, find_packages

with open("requirements.txt") as f:
    required = f.read().splitlines()

setup(
    name="rw-devtools",
    version=open("VERSION").read().strip(),
    packages=find_packages(where="dev_facade", include=["RW*"]),
    package_dir={"": "dev_facade"},
    license="Apache License 2.0",
    description="A set of RunWhen Developer keywords and python libraries for local development",
    long_description=open("README.md").read(),
    long_description_content_type="text/markdown",
    author="RunWhen",
    author_email="info@runwhen.com",
    url="https://github.com/runwhen-contrib/codecollection-devtools",
    install_requires=required,
    include_package_data=True,
    classifiers=[
        "Programming Language :: Python :: 3",
        "License :: OSI Approved :: Apache Software License",
    ],
)

