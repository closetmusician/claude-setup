#!/usr/bin/env bash
# ABOUTME: Stop hook that enforces ASD-STE100 Simplified Technical English on the
# ABOUTME: reply about to be shown. It blocks the turn once and names every word to
# ABOUTME: change, so the rewrite is mechanical rather than a matter of taste.
# ABOUTME: Scope: prose, table cells and link text. Code fences and inline code are not
# ABOUTME: checked. It works on a private copy; your reply is never altered by it.
# ABOUTME: Rules: policy/ste-style.rules. Fail-OPEN, and it blocks once per reply.

set -uo pipefail
trap 'exit 0' ERR

[ "${HARNESS_STE_LINT:-1}" = "0" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v perl >/dev/null 2>&1 || exit 0

INPUT="$(cat 2>/dev/null)" || INPUT=""
[ -z "$INPUT" ] && exit 0
printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1 || exit 0

# One enforcement per turn: a retry after our own block must go through.
[ "$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false')" = "true" ] && exit 0

TRANSCRIPT="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty')"
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULES="${SCRIPT_DIR}/../policy/ste-style.rules"
[ -f "$RULES" ] || exit 0
SEEN_DIR="${STE_SEEN_DIR:-${HOME}/.claude/state/ste-lint-seen}"

_rev() { tail -r "$1" 2>/dev/null || tac "$1" 2>/dev/null; }

# Last assistant turn: its id (for the once-per-reply guard) and its visible text.
# Gotchas: `fromjson?` skips half-written lines; only "text" blocks are shown to
#   Yu-Kuan, so thinking blocks and tool calls are not linted.
LAST="$(_rev "$TRANSCRIPT" | jq -R -r 'fromjson? | select(.type=="assistant" and (.isSidechain != true)) | [(.uuid // "?"), ((.message.content // []) | if type=="array" then (map(select(.type=="text") | .text) | join("\n")) else tostring end)] | @tsv' 2>/dev/null | head -1)"
[ -z "$LAST" ] && exit 0

MSG_ID="${LAST%%$'\t'*}"
PROSE="${LAST#*$'\t'}"
[ -z "$PROSE" ] && exit 0

mkdir -p "$SEEN_DIR" 2>/dev/null || exit 0
MARKER="${SEEN_DIR}/$(printf '%s' "$MSG_ID" | tr -c 'A-Za-z0-9_-' '_')"
[ -f "$MARKER" ] && exit 0

PROSE_FILE="$(mktemp)"; trap 'rm -f "$PROSE_FILE"' EXIT
printf '%b' "$PROSE" > "$PROSE_FILE"

FINDINGS="$(perl - "$RULES" "$PROSE_FILE" <<'PERLEOF'
use strict; use warnings;
use open qw(:std :encoding(UTF-8));
my ($rules_path, $prose_path) = @ARGV;

# Load the rule table. Anything that is not "severity::regex::advice" is skipped.
my (@block, @warn);
open my $R, "<:encoding(UTF-8)", $rules_path or exit 0;
while (my $line = <$R>) {
  chomp $line;
  next if $line =~ /^\s*(#|$)/;
  my ($sev, $pat, $adv) = split /::/, $line, 3;
  next unless defined $adv;
  push @{ $sev eq 'block' ? \@block : \@warn }, [$pat, $adv];
}
close $R;

my $text = do { local $/; open my $P, "<:encoding(UTF-8)", $prose_path or exit 0; <$P> };

# is_code_token: true when the match sits inside an identifier, flag, path or URL
# rather than standing as an English word. This is precision, not exemption —
# "we leverage it" is caught, "scripts/leverage-x.sh" and "--utilize-cache" are not.
sub is_code_token {
  my ($t, $s, $e) = @_;
  my $before = $s >= 1 ? substr($t, $s - 1, 1) : ' ';
  my $after  = $e < length($t) ? substr($t, $e, 2) : ' ';
  return 1 if $before =~ m{[/_\\:=.\-]};
  return 1 if $after  =~ m{^[/_\\:=\-(]};
  return 1 if $after  =~ m{^\.\w};       # robust.sh, but not "it is robust."
  return 0;
}

# Scope: tables, link text and ordinary prose are checked. Code fences and inline
# code are not, because a real function or command name cannot be renamed to satisfy
# a style rule. Table pipes stay in place here so cell text is scanned normally.
my $scan = $text;
$scan =~ s/^```.*?^```//gsm;
$scan =~ s/^~~~.*?^~~~//gsm;
$scan =~ s/`[^`\n]*`//g;

my @hits;
for my $r (@block) {
  my ($pat, $adv) = @$r;
  my %seen;
  while ($scan =~ /($pat)/gi) {
    next if is_code_token($scan, $-[1], $+[1]);
    my $found = lc $1;
    next if $seen{$found}++;
    push @hits, sprintf('B|"%s" -> %s', $1, $adv);
  }
}

# Sentence length judges PROSE shape. Table rows are split at the pipe so each cell
# is judged on its own.
my $structural = $scan;
$structural =~ s/\|/. /g;
for my $s (split /(?<=[.!?])\s+/, $structural) {
  my @w = ($s =~ /\S+/g);
  next if @w <= 25;
  push @hits, sprintf('B|%d-word sentence ("%s ...") -> split it; max 25 words',
                      scalar @w, join(' ', @w[0 .. 7]));
}

# Dashes used as dramatic pauses are the loudest tell of the house style.
my $dashes = () = $scan =~ /\x{2014}/g;
push @hits, sprintf('B|%d em dashes -> use a full stop, a comma, or brackets; max 2', $dashes)
  if $dashes > 2;

if (@hits) {
  for my $r (@warn) {
    my ($pat, $adv) = @$r;
    my %seen;
    while ($scan =~ /($pat)/gi) {
      next if is_code_token($scan, $-[1], $+[1]);
      my $found = lc $1;
      next if $seen{$found}++;
      push @hits, sprintf('W|"%s" -> %s', $1, $adv);
    }
  }
}
print "$_\n" for @hits;
PERLEOF
)"

printf '%s' "$FINDINGS" | grep -q '^B|' || exit 0
: > "$MARKER"

BLOCKS="$(printf '%s\n' "$FINDINGS" | perl -lne 'print "  - $1" if /^B\|(.*)$/')"
WARNS="$(printf '%s\n' "$FINDINGS" | perl -lne 'print "  - $1" if /^W\|(.*)$/')"
REASON="WRITING STYLE GATE: this reply breaks the ASD-STE100 rules in ~/.claude/rules/writing-style.md. Rewrite it and send it again. Do not explain the rewrite, do not apologise, just send the corrected reply. If a finding is a real code name you cannot change, send the reply again unchanged; the gate fires only once.

Fix these:
${BLOCKS}"
[ -n "$WARNS" ] && REASON="${REASON}

Also worth cutting:
${WARNS}"

jq -cn --arg r "$REASON" '{"decision":"block","reason":$r}'
exit 0
