#!/usr/bin/env python3

"""Substitute variables using jinja2."""

import json
import jinja2
import argparse
import socket


parser = argparse.ArgumentParser()
parser.add_argument('-s', '--source', help='source template file',
                    required=True, type=str)
parser.add_argument('-x', '--extra', help='extra source template files; added to doc based on filename',
                    type=str, action='append', default=[])
parser.add_argument('-o', '--out', help='output file',
                    required=True, type=str)
parser.add_argument('-d', '--data', help='json data file',
                    required=True, type=str)
parser.add_argument('-v', '--var', type=str, action='append',
                    default=[], help="set variable to value (--var foo=baz)")
args = parser.parse_args()

# https://stackoverflow.com/questions/166506/finding-local-ip-addresses-using-pythons-stdlib
ip = [l for l in ([ip for ip in
      socket.gethostbyname_ex(socket.gethostname())[2]
      if not ip.startswith("127.")][:1],
      [[(s.connect(('8.8.8.8', 53)), s.getsockname()[0], s.close())
          for s in [socket.socket(socket.AF_INET, socket.SOCK_DGRAM)]][0][1]])
      if l][0][0]


def apply_template(data, source_file):
    """Run file through Jinja2 Template system."""
    template = jinja2.Template(source_file.read())
    return template.render(**data)


# get our source data to start
data = None
with open(args.data) as data_file:
    data = json.load(data_file)
    data = dict(data=data, ip=ip)

# extend with any extra data
for extra in args.extra:
    with open(extra) as data_file:
        extra_name = extra.split('.')[0].split('/')[-1]
        data[extra_name] = json.load(data_file)

# plus any one-off vars from the command line
if args.var:
    for var in args.var:
        splitted = var.split("=", 1)
        if len(splitted) == 1:
            data[splitted[0]] = ''
        else:
            data[splitted[0]] = splitted[1]

# finally, apply this all to the source template
with open(args.source) as source_file:
    content = apply_template(data, source_file)
    with open(args.out, "w") as dest_file:
        dest_file.write(content)
