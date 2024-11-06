from setuptools import setup

setup(
    name="rw-devtools",
    version=open("VERSION").read().strip(),
    packages=["RW"],  # Explicitly list the `RW` package
    package_dir={"RW": "dev_facade/RW"},  # Map `RW` to its directory
    license="Apache License 2.0",
    description="A set of RunWhen Developer keywords and python libraries for local development",
    long_description=open("README.md").read(),
    long_description_content_type="text/markdown",
    author="RunWhen",
    author_email="info@runwhen.com",
    url="https://github.com/runwhen-contrib/codecollection-devtools",
    install_requires=open("requirements.txt").read().splitlines(),
    include_package_data=True,
    classifiers=[
        "Programming Language :: Python :: 3",
        "License :: OSI Approved :: Apache Software License",
    ],
)
