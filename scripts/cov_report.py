#!/usr/bin/env python3
"""Functional coverage from Verilator coverage.dat files: hits per coverpoint and unhit bins.

Verilator records covergroup bins but does not compute coverage. SVA covers (c_*) are listed as sva.cover.
"""
import re
import sys
from collections import defaultdict

REC = re.compile(r"^C '(.*)' (\d+)$")


def load(paths):
    hits = defaultdict(int)
    for p in paths:
        with open(p, encoding="latin-1") as f:
            for line in f:
                m = REC.match(line.rstrip("\n"))
                if not m:
                    continue
                fields = dict(kv.split("\x02", 1) for kv in m.group(1).split("\x01") if "\x02" in kv)
                if fields.get("t") == "covergroup" and "h" in fields:
                    hits[fields["h"].replace("__vlAnonCG_", "")] += int(m.group(2))
                elif fields.get("t") == "user" and fields.get("o", "").startswith("c_"):
                    hits["sva.cover." + fields["o"]] += int(m.group(2))
    return hits


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: cov_report.py coverage.dat [...]")
    hits = load(sys.argv[1:])
    points = defaultdict(dict)
    for h, n in hits.items():
        group_point, _, bin_ = h.rpartition(".")
        points[group_point][bin_] = n

    tot_bins = tot_hit = 0
    print(f"{'coverpoint':34} {'hit/bins':>9} {'cov':>7}")
    for gp in sorted(points):
        bins = points[gp]
        hit = sum(1 for n in bins.values() if n > 0)
        tot_bins += len(bins)
        tot_hit += hit
        print(f"{gp:34} {hit:>4}/{len(bins):<4} {100.0 * hit / len(bins):6.1f}%")
    print(f"{'TOTAL':34} {tot_hit:>4}/{tot_bins:<4} {100.0 * tot_hit / max(tot_bins, 1):6.1f}%")

    holes = [f"{gp}.{b}" for gp in sorted(points) for b, n in sorted(points[gp].items()) if n == 0]
    if holes:
        print("unhit bins:")
        for h in holes:
            print(f"  {h}")


if __name__ == "__main__":
    main()
