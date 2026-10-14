#!/usr/bin/env python3
"""Rewrites the character grids in index.html from the manifest made by render_rower_videos.

Usage: update_index.py manifest.json
Everything from the first category heading to the end of the last grid, inside
<section class="characters">, is replaced; the rest of the page is untouched.
"""
import html
import json
import re
import sys

TILE = """        <figure>
          <video
            src="rower_videos/{file}.mp4"
            data-poster="rower_images/{file}.png"
            width="500"
            height="500"
            muted
            loop
            playsinline
            preload="none"
          ></video>
          <figcaption>{label}</figcaption>
        </figure>
"""

manifest = json.load(open(sys.argv[1]))
groups = {}
for item in manifest:
    groups.setdefault(item["category"], []).append(item)

out = ""
for category, items in groups.items():
    out += '      <h3 class="character-category">%s</h3>\n      <div class="character-grid">\n' % html.escape(category)
    out += "".join(TILE.format(file=i["file"], label=html.escape(i["name"])) for i in items)
    out += "      </div>\n"

page = open("index.html").read()
pattern = re.compile(r'(<section class="characters".*?\n)([ ]*)(<h3 class="character-category">.*?\n)([ ]*</section>)', re.S)
m = pattern.search(page)
if not m:
    sys.exit("characters section not found in index.html")
# The template is written for a 6-space indent; shift it to wherever the page nests the headings.
extra = " " * (len(m.group(2)) - 6)
out = "".join(extra + line + "\n" if line else "\n" for line in out.splitlines())
open("index.html", "w").write(page[:m.start(2)] + out + page[m.start(4):])
print("index.html: %d characters in %d categories" % (len(manifest), len(groups)))
