#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# <xbar.title>Github review requests</xbar.title>
# <xbar.desc>Shows a list of PRs that need to be reviewed</xbar.desc>
# <xbar.version>v0.1</xbar.version>
# <xbar.author>Adam Bogdał</xbar.author>
# <xbar.author.github>bogdal</xbar.author.github>
# <xbar.image>https://github-bogdal.s3.amazonaws.com/bitbar-plugins/review-requests.png</xbar.image>
# <xbar.dependencies>python</xbar.dependencies>

# ----------------------
# ---  BEGIN CONFIG  ---
# ----------------------

# Create your Personal Access Token here https://github.com/settings/tokens
# The token needs the following permissions:
# - repo - Full control of private repositories
# (See also https://help.github.com/articles/creating-a-personal-access-token-for-the-command-line/)
ACCESS_TOKEN = ''

# (required) Your GitHub login https://github.com/<login>
GITHUB_LOGIN = ''

# (optional) PRs with this label (e.g 'in progress') will be grayed out on the list
WIP_LABEL = ''

# (optional) Filter the PRs by an organization, labels, etc. E.g 'org:YourOrg -label:dropped draft:false'
FILTERS = 'draft:false'

# (optional) Filter by specific organizations (e.g. ['org1', 'org2']). Leave empty [] to show all.
TARGET_ORGS = []

# (optional) Filter by specific repositories (e.g. ['owner/repo1', 'owner/repo2']). Leave empty [] to show all.
TARGET_REPOS = []

# (optional) Filter by specific users involved in PRs (e.g. ['user1', 'user2']). Leave empty [] to show all.
TARGET_USERS = []

# --------------------
# ---  END CONFIG  ---
# --------------------

import datetime
import json
import os
import sys
try:
    # For Python 3.x
    from urllib.request import Request, urlopen
except ImportError:
    # For Python 2.x
    from urllib2 import Request, urlopen

DARK_MODE = os.environ.get('BitBarDarkMode') == '1'

query = '''{
  search(query: "%(search_query)s", type: ISSUE, first: 100) {
    issueCount
    edges {
      node {
        ... on PullRequest {
          repository {
            nameWithOwner
          }
          author {
            login
          }
          createdAt
          number
          url
          title
          labels(first:100) {
            nodes {
              name
            }
          }
        }
      }
    }
  }
}'''


colors = {
    'inactive': '#b4b4b4',
    'title': '#ffffff' if DARK_MODE else '#000000',
    'subtitle': '#586069'}


def should_include_pr(pr):
    """Check if PR should be included based on TARGET filters."""
    repo_name = pr['repository']['nameWithOwner']
    author_name = pr['author']['login']

    # Extract organization from repo name (owner/repo -> owner)
    org_name = repo_name.split('/')[0]

    # Check organization filter
    if TARGET_ORGS and org_name not in TARGET_ORGS:
        return False

    # Check repository filter
    if TARGET_REPOS and repo_name not in TARGET_REPOS:
        return False

    # Check user filter (author or any involved user)
    if TARGET_USERS and author_name not in TARGET_USERS:
        return False

    return True


def execute_query(query):
    headers = {
        'Authorization': 'bearer ' + ACCESS_TOKEN,
        'Content-Type': 'application/json'}
    data = json.dumps({'query': query}).encode('utf-8')
    req = Request(
        'https://api.github.com/graphql', data=data, headers=headers)
    body = urlopen(req).read()
    return json.loads(body)


def search_pull_requests(search_query):
    response = execute_query(query % {'search_query': search_query})
    return response['data']['search']


def get_review_requests(login, filters=''):
    search_query = 'type:pr state:open review-requested:%(login)s %(filters)s' % {
        'login': login, 'filters': filters}
    return search_pull_requests(search_query)


def get_authored_prs(login, filters=''):
    search_query = 'type:pr state:open author:%(login)s %(filters)s' % {
        'login': login, 'filters': filters}
    return search_pull_requests(search_query)


def parse_date(text):
    date_obj = datetime.datetime.strptime(text, '%Y-%m-%dT%H:%M:%SZ')
    return date_obj.strftime('%B %d, %Y')


def print_line(text, **kwargs):
    params = ' '.join(['%s=%s' % (key, value) for key, value in kwargs.items()])
    print('%s | %s' % (text, params) if kwargs.items() else text)


if __name__ == '__main__':
    if not all([ACCESS_TOKEN, GITHUB_LOGIN]):
        print_line('⚠ Github review requests', color='red')
        print_line('---')
        print_line('ACCESS_TOKEN and GITHUB_LOGIN cannot be empty')
        sys.exit(0)

    review_requests = get_review_requests(GITHUB_LOGIN, FILTERS)
    authored_prs = get_authored_prs(GITHUB_LOGIN, FILTERS)

    # Apply TARGET filters
    filtered_review_requests = [r['node'] for r in review_requests['edges'] if should_include_pr(r['node'])]
    filtered_authored_prs = [r['node'] for r in authored_prs['edges'] if should_include_pr(r['node'])]

    total_count = len(filtered_review_requests) + len(filtered_authored_prs)
    print_line('PR: %s' % total_count)
    print_line('---')

    # Display review requests
    if filtered_review_requests:
        print_line('👀 Review Requested (%s)' % len(filtered_review_requests), color=colors['title'], font='Menlo-Bold', size=13)
        print_line('---')

        for pr in filtered_review_requests:
            labels = [l['name'] for l in pr['labels']['nodes']]
            title = '%s - %s' % (pr['repository']['nameWithOwner'], pr['title'].replace('|', '-'))
            title_color = colors.get('inactive' if WIP_LABEL in labels else 'title')
            subtitle = '#%s opened on %s by @%s' % (
                pr['number'], parse_date(pr['createdAt']), pr['author']['login'])
            subtitle_color = colors.get('inactive' if WIP_LABEL in labels else 'subtitle')

            print_line(title, size=12, color=title_color, href=pr['url'])
            print_line(subtitle, size=10, color=subtitle_color)
            print_line('---')

    # Display authored PRs
    if filtered_authored_prs:
        print_line('✍️ Created by Me (%s)' % len(filtered_authored_prs), color=colors['title'], font='Menlo-Bold', size=13)
        print_line('---')

        for pr in filtered_authored_prs:
            labels = [l['name'] for l in pr['labels']['nodes']]
            title = '%s - %s' % (pr['repository']['nameWithOwner'], pr['title'].replace('|', '-'))
            title_color = colors.get('inactive' if WIP_LABEL in labels else 'title')
            subtitle = '#%s opened on %s by @%s' % (
                pr['number'], parse_date(pr['createdAt']), pr['author']['login'])
            subtitle_color = colors.get('inactive' if WIP_LABEL in labels else 'subtitle')

            print_line(title, size=12, color=title_color, href=pr['url'])
            print_line(subtitle, size=10, color=subtitle_color)
            print_line('---')
