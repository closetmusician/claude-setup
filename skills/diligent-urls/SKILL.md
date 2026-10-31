---
name: diligent-urls
description: Use when the user mentions internal Diligent sites, company URLs, Confluence, JIRA, Glean, SharePoint, Salesforce, or needs to access company tools without searching the web
---

# Diligent Internal URLs

## Overview
Quick reference for Diligent company URLs. Use this instead of web search when accessing internal tools.

## When to Use
- User mentions Glean, Confluence, JIRA, Salesforce, SharePoint
- User says "internal site", "company dashboard", "work tools"
- User references Diligent-specific systems
- Before doing web searches for company tools

## Quick Reference

**The authoritative list is in the user's project at `.claude/work-urls.md`**

Always read that file first for current URLs. Key systems include:
- Glean (search)
- Confluence (wiki)
- JIRA (tickets)
- Salesforce (CRM)
- SharePoint (documents)

## Full Bookmarks Archive

For URLs not in work-urls.md, search the full Chrome bookmarks:

```bash
# Search full archive by keyword
grep -i "keyword" ~/OneDrive/Work/Code/chrome-bookmarks.md

# Examples:
grep -i "benchmarking" ~/OneDrive/Work/Code/chrome-bookmarks.md
grep -i "governance" ~/OneDrive/Work/Code/chrome-bookmarks.md
```

## Workflow

1. Check `.claude/work-urls.md` in project first (curated essentials)
2. If not found, grep `~/OneDrive/Work/Code/chrome-bookmarks.md` (full archive)
3. Use URLs directly - don't search the web for internal tools
