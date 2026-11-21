#!/usr/bin/env python3
"""Ensure an internal TestFlight group for the app and add the account holder.

Runs in Codemagic with the App Store Connect integration, which provides
APP_STORE_CONNECT_KEY_IDENTIFIER, APP_STORE_CONNECT_ISSUER_ID and
APP_STORE_CONNECT_PRIVATE_KEY. Prints no secrets; e-mail addresses are masked.
Idempotent: an existing group or tester is reused.
"""
from __future__ import annotations

import os
import re
import sys
import textwrap
import time

import jwt  # PyJWT
import requests

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE_ID = os.environ.get("BUNDLE_ID", "uz.ulash.app")
GROUP_NAME = os.environ.get("TESTFLIGHT_GROUP", "Internal Testers")


def private_key() -> str:
    raw = os.environ["APP_STORE_CONNECT_PRIVATE_KEY"].strip()
    if raw.startswith("@file:"):
        raw = open(os.path.expanduser(raw[6:])).read().strip()
    raw = raw.replace("\\r", "").replace("\\n", "\n").replace("\r", "")
    body = re.sub(r"\s+", "", re.sub(r"-----[A-Z ]+-----", "", raw))
    return ("-----BEGIN PRIVATE KEY-----\n" + "\n".join(textwrap.wrap(body, 64))
            + "\n-----END PRIVATE KEY-----\n")


def session() -> requests.Session:
    now = int(time.time())
    token = jwt.encode(
        {"iss": os.environ["APP_STORE_CONNECT_ISSUER_ID"], "iat": now,
         "exp": now + 15 * 60, "aud": "appstoreconnect-v1"},
        private_key(), algorithm="ES256",
        headers={"kid": os.environ["APP_STORE_CONNECT_KEY_IDENTIFIER"], "typ": "JWT"},
    )
    s = requests.Session()
    s.headers.update({"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    return s


def mask(email: str) -> str:
    name, _, domain = email.partition("@")
    return (name[:2] + "***@" + domain) if domain else "***"


def check(response: requests.Response, what: str) -> dict:
    if response.status_code >= 400:
        detail = "; ".join(e.get("detail", e.get("title", "")) for e in
                           response.json().get("errors", [])) if response.content else ""
        sys.exit(f"{what} failed: HTTP {response.status_code} {detail}")
    return response.json() if response.content else {}


def main() -> None:
    s = session()
    apps = check(s.get(f"{API}/apps", params={"filter[bundleId]": BUNDLE_ID}), "find app")["data"]
    if not apps:
        sys.exit(f"No App Store Connect app for {BUNDLE_ID}")
    app_id = apps[0]["id"]
    print(f"App {apps[0]['attributes']['name']} ({app_id})")

    builds = check(s.get(f"{API}/builds", params={
        "filter[app]": app_id, "sort": "-uploadedDate", "limit": 5,
        "fields[builds]": "version,processingState,uploadedDate,expired"}), "list builds")["data"]
    for b in builds:
        a = b["attributes"]
        print(f"  build {a['version']}: {a['processingState']} (uploaded {a['uploadedDate']})")
    if not builds:
        print("  no builds visible yet (upload may still be processing)")

    groups = check(s.get(f"{API}/apps/{app_id}/betaGroups", params={"limit": 50}), "list groups")["data"]
    group = next((g for g in groups if g["attributes"].get("isInternalGroup")
                  and g["attributes"]["name"] == GROUP_NAME), None)
    if group is None:
        group = check(s.post(f"{API}/betaGroups", json={"data": {
            "type": "betaGroups",
            "attributes": {"name": GROUP_NAME, "isInternalGroup": True,
                           "hasAccessToAllBuilds": True},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
        }}), "create internal group")["data"]
        print(f"Created internal group '{GROUP_NAME}' ({group['id']})")
    else:
        print(f"Internal group '{GROUP_NAME}' exists ({group['id']})")

    holders = check(s.get(f"{API}/users", params={"filter[roles]": "ACCOUNT_HOLDER", "limit": 5}),
                    "find account holder")["data"]
    if not holders:
        sys.exit("No account holder visible to this API key")
    holder = holders[0]["attributes"]
    email = holder["username"]
    print(f"Account holder: {holder.get('firstName', '')} {holder.get('lastName', '')} <{mask(email)}>")

    members = check(s.get(f"{API}/betaGroups/{group['id']}/betaTesters", params={"limit": 200}),
                    "list group testers")["data"]
    if any(t["attributes"].get("email", "").lower() == email.lower() for t in members):
        print("Account holder is already in the group")
    else:
        # Internal groups take App Store Connect users by e-mail; creating the
        # tester with the group relationship works even if a tester record for
        # this e-mail already exists from other apps.
        created = s.post(f"{API}/betaTesters", json={"data": {
            "type": "betaTesters",
            "attributes": {"email": email, "firstName": holder.get("firstName", ""),
                           "lastName": holder.get("lastName", "")},
            "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": group["id"]}]}},
        }})
        if created.status_code >= 400:
            print(f"create tester with group: HTTP {created.status_code} "
                  + "; ".join(e.get("detail", "") for e in created.json().get("errors", [])))
            existing = check(s.get(f"{API}/betaTesters", params={"filter[email]": email}),
                             "find tester")["data"]
            if not existing:
                sys.exit("Could not add the account holder")
            check(s.post(f"{API}/betaGroups/{group['id']}/relationships/betaTesters",
                         json={"data": [{"type": "betaTesters", "id": existing[0]["id"]}]}),
                  "add existing tester to group")
        members = check(s.get(f"{API}/betaGroups/{group['id']}/betaTesters", params={"limit": 200}),
                        "verify group testers")["data"]
        if not any(t["attributes"].get("email", "").lower() == email.lower() for t in members):
            sys.exit("Account holder is not listed in the group after adding")
        print("Added the account holder to the internal group")

    # Internal groups with access to all builds get every processed build;
    # attach the newest explicitly too, in case the group predates that flag.
    if builds and builds[0]["attributes"]["processingState"] == "VALID":
        r = s.post(f"{API}/betaGroups/{group['id']}/relationships/builds",
                   json={"data": [{"type": "builds", "id": builds[0]["id"]}]})
        print("Newest build attached to the group" if r.status_code < 400
              else f"Build attach skipped (HTTP {r.status_code}); group has access to all builds")


if __name__ == "__main__":
    main()
