# ABOUTME: Converts the "Why We Win" / "Why We Lose" HTML board reports into faithful Markdown.
# ABOUTME: Each <section class="sheet"> becomes a markdown page block separated by ---.
# ABOUTME: Every <sup class="cite">N</sup> becomes a [^N] footnote reference.
# ABOUTME: The Sources <ol> lists are parsed into [^N]: footnote definitions at file end.
# ABOUTME: Run: uv run --with beautifulsoup4 .convert_reports.py <in.html> <out.md>

import re
import sys

from bs4 import BeautifulSoup, NavigableString, Tag


def squash(text):
    """Collapse all runs of whitespace (including nbsp) into single spaces.
    Usage: squash(raw_html_text) before emitting any markdown line.
    Gotcha: also strips leading/trailing space, so callers must add their own padding."""
    return re.sub(r"[\s ]+", " ", text).strip()


class Converter:
    """Walks one report's DOM and emits markdown lines plus a footnote table.
    Usage: Converter(soup).run() -> markdown string.
    Gotchas: cite numbers are collected as seen; footnote definitions come only from
    the Sources <ol> lists, so a cite with no matching <li> is reported as missing."""

    def __init__(self, soup):
        self.soup = soup
        self.out = []
        self.cites = []          # every [^N] emitted, in order
        self.footnotes = {}      # N -> definition text

    # ---------- inline rendering ----------

    def inline(self, node):
        """Render an element's children as a single markdown inline string.
        Usage: self.inline(paragraph_tag).
        Gotchas: <br> becomes a hard line break marker ' \\n'; block children are
        not expected here and are rendered inline if encountered."""
        parts = []
        for child in node.children:
            if isinstance(child, NavigableString):
                parts.append(re.sub(r"[\s ]+", " ", str(child)))
                continue
            if not isinstance(child, Tag):
                continue
            name = child.name
            classes = child.get("class") or []
            if name == "sup" and "cite" in classes:
                parts.append(self.render_cite(child))
            elif name == "br":
                parts.append("<BR>")
            elif name in ("strong", "b"):
                inner = self.inline(child).strip()
                parts.append(f"**{inner}**" if inner else "")
            elif name in ("em", "i"):
                inner = self.inline(child).strip()
                parts.append(f"*{inner}*" if inner else "")
            elif name == "code":
                parts.append(f"`{squash(child.get_text())}`")
            elif name == "span" and "gap" in classes:
                parts.append("**" + squash(child.get_text()) + "**")
            elif name == "a":
                parts.append(self.inline(child))
            else:
                parts.append(self.inline(child))
        text = "".join(parts)
        # tidy spacing introduced by tag boundaries
        text = re.sub(r" +", " ", text)
        text = re.sub(r" +([,.;:)\]])", r"\1", text)
        text = text.replace("****", "")          # drop empty bold left by whitespace-only <strong>
        return text

    def render_cite(self, sup):
        """Turn one <sup class="cite">1, 2</sup> into '[^1][^2]' and record the numbers.
        Usage: called from inline().
        Gotchas: source text may be '1,&nbsp;2' or '1, 2, 3'; non-numeric content is kept verbatim."""
        raw = squash(sup.get_text())
        nums = [n for n in re.split(r"[,\s]+", raw) if n]
        markers = []
        for n in nums:
            if n.isdigit():
                self.cites.append(int(n))
                markers.append(f"[^{n}]")
            else:
                markers.append(n)
        return "".join(markers)

    def para(self, text, prefix=""):
        """Append a markdown paragraph, expanding <BR> markers into hard breaks.
        Usage: self.para(self.inline(tag)).
        Gotchas: silently drops empty paragraphs; prefix is applied to every line."""
        text = text.strip()
        if not text:
            return
        lines = [seg.strip() for seg in text.split("<BR>")]
        body = "  \n".join(prefix + line for line in lines if line != "" or len(lines) == 1)
        self.out.append(body)
        self.out.append("")

    # ---------- block rendering ----------

    def table(self, tag):
        """Render an HTML table as a GitHub-flavoured markdown table.
        Usage: self.table(table_tag).
        Gotchas: right-aligns any column whose header carries class="num";
        tables with no <thead> get an empty header row so the markdown stays valid."""
        head_cells = []
        aligns = []
        thead = tag.find("thead")
        rows = []
        if thead:
            hr = thead.find("tr")
            for th in hr.find_all(["th", "td"]):
                head_cells.append(self.inline(th).replace("<BR>", " ").strip())
                aligns.append("right" if "num" in (th.get("class") or []) else "left")
        body = tag.find("tbody") or tag
        for tr in body.find_all("tr", recursive=False):
            cells = [self.inline(td).replace("<BR>", " ").strip().replace("|", "\\|")
                     for td in tr.find_all(["td", "th"], recursive=False)]
            if cells:
                rows.append(cells)
        width = max([len(head_cells)] + [len(r) for r in rows]) if rows or head_cells else 0
        if width == 0:
            return
        if not head_cells:
            head_cells = [""] * width
            aligns = ["left"] * width
        head_cells += [""] * (width - len(head_cells))
        aligns += ["left"] * (width - len(aligns))
        sep = ["---:" if a == "right" else "---" for a in aligns]
        self.out.append("| " + " | ".join(c.replace("|", "\\|") for c in head_cells) + " |")
        self.out.append("| " + " | ".join(sep) + " |")
        for r in rows:
            r = r + [""] * (width - len(r))
            self.out.append("| " + " | ".join(r) + " |")
        self.out.append("")

    def stats(self, tag):
        """Render a .stats or .stats-panel tile group as a compact value/label table.
        Usage: self.stats(div_tag).
        Gotchas: .stats uses num/lbl/sub children, .stats-panel uses big/cap; both
        are normalised to Value | Label columns with the sub-caption appended."""
        rows = []
        for cell in tag.find_all("div", recursive=False):
            classes = cell.get("class") or []
            if not ({"stat", "cell"} & set(classes)):
                continue
            value = ""
            label_parts = []
            for kid in cell.find_all("div", recursive=False):
                kc = kid.get("class") or []
                rendered = self.inline(kid).replace("<BR>", " ").strip()
                if "num" in kc or "big" in kc:
                    value = rendered
                elif "lbl" in kc or "cap" in kc:
                    label_parts.append(rendered)
                elif "sub" in kc:
                    label_parts.append(rendered)
                else:
                    label_parts.append(rendered)
            label = " — ".join(p for p in label_parts if p)
            rows.append((value, label.replace("|", "\\|")))
        if not rows:
            return
        self.out.append("| Value | Label |")
        self.out.append("| ---: | --- |")
        for value, label in rows:
            self.out.append(f"| {value} | {label} |")
        self.out.append("")

    def callout(self, tag, head_class):
        """Render .callout / .rep-quote as a blockquote whose first line is bold.
        Usage: self.callout(div, 'callout-head').
        Gotchas: body text is the div's remaining children, including loose text nodes;
        <br><br> in the source becomes a blank blockquote line."""
        head = tag.find("div", class_=head_class)
        head_text = self.inline(head).replace("<BR>", " ").strip() if head else ""
        clone_parts = []
        for child in tag.children:
            if isinstance(child, Tag) and child is head:
                continue
            if isinstance(child, NavigableString):
                clone_parts.append(re.sub(r"[\s ]+", " ", str(child)))
            elif isinstance(child, Tag):
                if child.name == "p":
                    clone_parts.append("<BR><BR>" + self.inline(child) + "<BR><BR>")
                elif child.name in ("ul", "ol"):
                    clone_parts.append("<BR>" + self.list_inline(child))
                else:
                    clone_parts.append(self.inline_wrapper(child))
        body = re.sub(r" +", " ", "".join(clone_parts)).strip()
        segments = [s.strip() for s in body.split("<BR>")]
        lines = []
        if head_text:
            lines.append(f"**{head_text}**")
            lines.append("")
        for seg in segments:
            if seg:
                lines.append(seg)
            elif lines and lines[-1] != "":
                lines.append("")
        while lines and lines[-1] == "":
            lines.pop()
        self.out.append("\n".join("> " + line if line else ">" for line in lines))
        self.out.append("")

    def inline_wrapper(self, tag):
        """Render a single inline-ish tag using the same rules as inline().
        Usage: helper for callout bodies.
        Gotchas: wraps the tag so inline() sees it as a child, preserving strong/em/cite handling."""
        holder = self.soup.new_tag("span")
        return self.inline_of_single(tag)

    def inline_of_single(self, tag):
        """Apply inline formatting to one tag (not its siblings).
        Usage: self.inline_of_single(strong_tag).
        Gotchas: duplicates a small part of inline()'s dispatch on purpose to avoid re-parenting nodes."""
        classes = tag.get("class") or []
        if tag.name == "sup" and "cite" in classes:
            return self.render_cite(tag)
        if tag.name == "br":
            return "<BR>"
        if tag.name in ("strong", "b"):
            return f"**{self.inline(tag).strip()}**"
        if tag.name in ("em", "i"):
            return f"*{self.inline(tag).strip()}*"
        if tag.name == "code":
            return f"`{squash(tag.get_text())}`"
        if tag.name == "span" and "gap" in classes:
            return "**" + squash(tag.get_text()) + "**"
        return self.inline(tag)

    def list_inline(self, tag):
        """Flatten a list into '<BR>- item' form for use inside a blockquote.
        Usage: self.list_inline(ul_tag).
        Gotchas: only one nesting level is supported; that is all these reports use."""
        parts = []
        for li in tag.find_all("li", recursive=False):
            parts.append("- " + self.inline(li).replace("<BR>", " ").strip())
        return "<BR>".join(parts)

    def quote(self, tag):
        """Render .quote as a blockquote with the attribution as an italic trailing line.
        Usage: self.quote(div_tag).
        Gotchas: attribution <span class="attrib"> may carry its own citation marker."""
        lines = []
        attrib = None
        for child in tag.children:
            if not isinstance(child, Tag):
                continue
            if "attrib" in (child.get("class") or []):
                attrib = self.inline(child).replace("<BR>", " ").strip()
            elif child.name == "p":
                lines.append(self.inline(child).replace("<BR>", " ").strip())
            else:
                lines.append(self.inline_of_single(child).replace("<BR>", " ").strip())
        body = [l for l in lines if l]
        rendered = []
        for l in body:
            rendered.append("> " + l)
            rendered.append(">")
        if attrib:
            rendered.append("> *" + attrib + "*")
        elif rendered:
            rendered.pop()
        self.out.append("\n".join(rendered))
        self.out.append("")

    def bullet_list(self, tag, ordered=False):
        """Render a ul/ol as a markdown list.
        Usage: self.bullet_list(ul_tag).
        Gotchas: item text keeps <BR> as a two-space hard break with hanging indent."""
        start = int(tag.get("start", 1)) if ordered else 1
        for idx, li in enumerate(tag.find_all("li", recursive=False)):
            marker = f"{start + idx}." if ordered else "-"
            text = self.inline(li).strip()
            segs = [s.strip() for s in text.split("<BR>") if s.strip()]
            first = segs[0] if segs else ""
            self.out.append(f"{marker} {first}")
            for seg in segs[1:]:
                self.out.append(f"  {seg}")
        self.out.append("")

    def sources_list(self, tag):
        """Harvest a Sources <ol> into the footnote-definition map.
        Usage: self.sources_list(ol_tag).
        Gotchas: honours the ol's start= attribute; definition text is squashed to one
        line because markdown footnote definitions must not contain blank lines."""
        start = int(tag.get("start", 1))
        for idx, li in enumerate(tag.find_all("li", recursive=False)):
            num = start + idx
            text = self.inline(li).replace("<BR>", " ")
            text = re.sub(r"\s+", " ", text).strip()
            self.footnotes[num] = text

    # ---------- page walk ----------

    def block(self, tag):
        """Dispatch one top-level block element inside a page to its renderer.
        Usage: self.block(child_of_section).
        Gotchas: .rh and .rf (running header/footer) are deliberately dropped; the
        page number is read from .rf by the caller."""
        classes = set(tag.get("class") or [])
        name = tag.name
        if classes & {"rh", "rf"}:
            return
        if name == "h1":
            self.out.append("# " + self.inline(tag).replace("<BR>", " ").strip())
            self.out.append("")
        elif name == "h2":
            self.out.append("## " + self.inline(tag).replace("<BR>", " ").strip())
            self.out.append("")
        elif name == "h3":
            self.out.append("### " + self.inline(tag).replace("<BR>", " ").strip())
            self.out.append("")
        elif name == "h4":
            self.out.append("#### " + self.inline(tag).replace("<BR>", " ").strip())
            self.out.append("")
        elif name == "p":
            if "cover-sub" in classes:
                self.para("*" + self.inline(tag).strip() + "*")
            elif "product-line" in classes:
                self.para("*" + self.inline(tag).strip() + "*")
            elif "note" in classes:
                self.para(self.inline(tag))
            else:
                self.para(self.inline(tag))
        elif name == "table":
            self.table(tag)
        elif name == "ul":
            self.bullet_list(tag)
        elif name == "ol":
            self.bullet_list(tag, ordered=True)
        elif name == "div":
            if "stats" in classes or "stats-panel" in classes:
                self.stats(tag)
            elif "callout" in classes:
                self.callout(tag, "callout-head")
            elif "rep-quote" in classes:
                self.callout(tag, "rep-head")
            elif "quote" in classes:
                self.quote(tag)
            elif "sources" in classes:
                for ol in tag.find_all("ol"):
                    self.sources_list(ol)
                self.para("*The numbered sources are reproduced as footnote definitions at the end of "
                          "this document.*")
            elif "cover-rule" in classes:
                pass
            else:
                for kid in tag.children:
                    if isinstance(kid, Tag):
                        self.block(kid)
                    elif isinstance(kid, NavigableString) and squash(str(kid)):
                        self.para(re.sub(r"[\s ]+", " ", str(kid)))
        elif name in ("section", "main"):
            for kid in tag.children:
                if isinstance(kid, Tag):
                    self.block(kid)

    def page_number(self, section):
        """Read the printed page number out of the running footer.
        Usage: self.page_number(section_tag) -> str or None.
        Gotchas: footers are formatted two ways across the two reports, hence the regex."""
        rf = section.find("div", class_="rf")
        if not rf:
            return None
        m = re.search(r"Page\s*([0-9]+)", squash(rf.get_text()))
        return m.group(1) if m else None

    def run(self):
        """Convert the whole document and return the markdown text.
        Usage: Converter(soup).run().
        Gotchas: the title block is taken from <title> plus the first running header,
        emitted once; footnote definitions are appended in numeric order."""
        title = squash(self.soup.title.get_text()) if self.soup.title else ""
        rh = self.soup.find("div", class_="rh")
        header = squash(rh.get_text(" ")) if rh else ""
        header = re.sub(r"\s*\|\s*", " | ", header)
        self.out.append(f"# {title}")
        self.out.append("")
        if header:
            self.out.append(f"*{header}*")
            self.out.append("")

        sections = self.soup.find_all("section", class_="sheet")
        for section in sections:
            page = self.page_number(section)
            self.out.append("---")
            self.out.append("")
            self.out.append(f"<!-- Page {page} -->" if page else "<!-- Page -->")
            self.out.append("")
            for kid in section.children:
                if isinstance(kid, Tag):
                    self.block(kid)

        self.out.append("---")
        self.out.append("")
        self.out.append("## Sources (footnote definitions)")
        self.out.append("")
        for num in sorted(self.footnotes):
            self.out.append(f"[^{num}]: {self.footnotes[num]}")
            self.out.append("")

        text = "\n".join(self.out)
        text = re.sub(r"\n{3,}", "\n\n", text)
        text = text.replace("<BR>", " ")
        return text.rstrip() + "\n"


def main():
    src, dst = sys.argv[1], sys.argv[2]
    with open(src, encoding="utf-8") as fh:
        soup = BeautifulSoup(fh.read(), "html.parser")
    html_cite_tags = soup.find_all("sup", class_="cite")
    conv = Converter(soup)
    md = conv.run()
    with open(dst, "w", encoding="utf-8") as fh:
        fh.write(md)

    md_refs = re.findall(r"\[\^(\d+)\](?!:)", md)
    referenced = sorted({int(n) for n in md_refs})
    defined = sorted(conv.footnotes)
    missing = [n for n in referenced if n not in conv.footnotes]
    unused = [n for n in defined if n not in referenced]
    print(f"{dst}")
    print(f"  html <sup class=cite> tags : {len(html_cite_tags)}")
    print(f"  markdown [^N] markers      : {len(md_refs)}")
    print(f"  distinct numbers referenced: {len(referenced)} (max {max(referenced) if referenced else 0})")
    print(f"  footnote definitions       : {len(defined)} (max {max(defined) if defined else 0})")
    print(f"  referenced without a def   : {missing}")
    print(f"  defined but never cited    : {unused}")
    print(f"  markdown lines             : {md.count(chr(10))}")


if __name__ == "__main__":
    main()
