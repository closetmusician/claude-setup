#!/usr/bin/env perl
# ABOUTME: Lint that flags "how we made this" content (method, process, tooling) in
# ABOUTME: finished .md and .html docs, so deliverables show results, not sausage-making.
# ABOUTME: Rules live in ~/.claude/policy/method-lint.rules (heading + phrase patterns).
# ABOUTME: Exit 0 = clean, 1 = findings (printed as file:line), 2 = usage or read error.
# ABOUTME: Escapes: "method-lint: allow" on a line skips it; "method-lint: off" skips the file.
use strict; use warnings;
use open qw(:std :encoding(UTF-8));
use File::Basename qw(dirname);

# Purpose: load "kind::regex::advice" rules into heading and phrase lists.
# Usage: my ($h, $p) = load_rules($path);
# Gotchas: bad regexes are reported and skipped so one typo cannot disable the lint.
sub load_rules {
  my ($path) = @_;
  open my $fh, '<', $path or die "method-lint: cannot read rules $path\n";
  my (@h, @p);
  while (my $l = <$fh>) {
    chomp $l;
    next if $l =~ /^\s*(#|$)/;
    my ($kind, $re, $advice) = split /::/, $l, 3;
    next unless defined $advice && $kind =~ /^(heading|phrase)$/;
    my $rx = eval { qr/$re/i };
    if (!$rx) { warn "method-lint: bad regex skipped: $re\n"; next }
    push @{ $kind eq 'heading' ? \@h : \@p }, [$rx, $advice];
  }
  return (\@h, \@p);
}

# Purpose: turn a file into [line_no, text, is_heading] rows with non-prose removed.
# Usage: my @rows = prose_lines($text, $is_html);
# Gotchas: multi-line comments, fences and script/style blocks are blanked line by line
#   so the line numbers in findings still match the source file.
sub prose_lines {
  my ($text, $html) = @_;
  my @orig = split /\n/, $text, -1;
  # Blank a region but keep its newlines, so line numbers never shift.
  my $blank = sub { my $s = shift; $s =~ s/[^\n]//g; $s };
  $text =~ s/(<!--.*?-->)/$blank->($1)/gse;
  $text =~ s/(<(script|style)\b.*?<\/\2>)/$blank->($1)/gsie;
  if ($html) {
    $text =~ s/(<(pre|code|title)\b.*?<\/\2>)/$blank->($1)/gsie;
    $text =~ s/(<[^>]*>)/$blank->($1) . ' '/gse;
  } else {
    $text =~ s/(^[ ]{0,3}(`{3,}|~{3,}).*?^[ ]{0,3}\2)/$blank->($1)/gsme;
  }
  my @lines = split /\n/, $text, -1;
  my @rows; my $n = 0;
  for my $i (0 .. $#lines) {
    my $line = $lines[$i];
    $n++;
    next if ($orig[$i] // '') =~ /method-lint:\s*allow/i;
    my $is_h = 0;
    if ($html) {
      $is_h = 1 if ($orig[$i] // '') =~ /<h[1-6]\b/i;
      $line =~ s/&nbsp;/ /g; $line =~ s/&amp;/&/g; $line =~ s/&#39;|&rsquo;/'/g;
    } else {
      $is_h = 1 if $line =~ s/^\s{0,3}#{1,6}\s+//;
      # Setext heading: a text line underlined with === or ---.
      $is_h = 1 if $line =~ /\S/ && ($lines[$i + 1] // '') =~ /^\s{0,3}(=+|-+)\s*$/;
      $line =~ s/`[^`]*`//g;
      $line =~ s/\]\([^)]*\)/]/g;
      $line =~ s/[*_]{1,3}//g;
    }
    $line =~ s{https?://\S+}{}g;
    push @rows, [$n, $line, $is_h] if $line =~ /\S/;
  }
  return @rows;
}

my $rules = $ENV{METHOD_LINT_RULES} || dirname(__FILE__) . '/../policy/method-lint.rules';
unless (@ARGV) { print STDERR "usage: method-lint.pl FILE.md|FILE.html ...\n"; exit 2 }
my ($heads, $phrases) = eval { load_rules($rules) } or do { print STDERR $@; exit 2 };

my ($found, $bad) = (0, 0);
for my $file (@ARGV) {
  my $text;
  if (-f $file && open my $fh, '<', $file) { local $/; $text = <$fh> }
  unless (defined $text) { warn "method-lint: cannot read $file\n"; $bad = 1; next }
  next if $text =~ /method-lint:\s*off/i;
  my $html = $file =~ /\.html?$/i;
  for my $row (prose_lines($text, $html)) {
    my ($n, $line, $is_h) = @$row;
    my @checks = ($is_h ? @$heads : (), @$phrases);
    for my $c (@checks) {
      next unless $line =~ $c->[0];
      (my $hit = $&) =~ s/^\s+|\s+$//g;
      (my $ctx = $line) =~ s/^\s+|\s+$//g;
      $ctx = substr($ctx, 0, 90) . '...' if length $ctx > 93;
      print "$file:$n: \"$hit\" -> $c->[1]\n    $ctx\n";
      $found++;
      last;
    }
  }
}
print STDERR "method-lint: $found finding(s)\n" if $found;
exit($bad ? 2 : $found ? 1 : 0);
