#!/usr/bin/env python3

# Copyright 2024 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import argparse
import json
from pathlib import Path
from urllib.request import urlretrieve

import semver


RELEASES_URL = "https://api.github.com/repos/kubernetes/kubernetes/releases?per_page=100"


def previous_k8s(k8s_version: str) -> str:
    """
    Get the previous Kubernetes release version to the one provided.

    For example:
    >>> previous_k8s("1.27.10")
    '1.27.9'
    >>> previous_k8s("1.27.0")
    '1.26.14'
    >>> previous_k8s("0.9.1-bogus+1234")
    '1.29.2'

    It compares against only the 100 most recent Kubernetes releases. If a version
    is older than that or doesn't represent a valid Kubernetes release, it returns
    the most recent release.

    This function saves a "releases.json" file to the current directory, and will
    use that data source if found, rather than download the release data again.

    Args:
        k8s_version (str): A Kubernetes release version to check

    Returns:
        str: The previous Kubernetes release version to the one provided
    """
    filename = Path("releases.json")
    if not filename.is_file() or filename.stat().st_size == 0:
        filename, _ = urlretrieve(RELEASES_URL, filename)
    k8s_version = k8s_version.strip('v ')
    with filename.open() as html:
        versions = [k8s_version]
        versions.extend(r["tag_name"].strip('v ') for r in json.loads(html.read()) if not r["prerelease"])
        versions.sort(key=semver.Version.parse)
        return versions[versions.index(k8s_version) - 1]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Get the previous Kubernetes release version.')
    parser.add_argument('version', help='A Kubernetes version to check.')
    args = parser.parse_args()
    print(previous_k8s(args.version))
