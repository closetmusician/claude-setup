#!/usr/bin/env perl
# ABOUTME: Estimates how many bytes a Bash command prints into context by reading files.
# ABOUTME: Used by read-budget-guard.sh. Splits the command on ; && || | outside quotes,
# ABOUTME: follows `cd`, skips pipelines whose stdout goes to a file or a counter (wc, grep -c),
# ABOUTME: and sizes read verbs (cat, head, tail, sed -n, markitdown, ...) from the real files.
# ABOUTME: Usage: perl bash-read-estimate.pl <cwd> <command> → "<total bytes> <code bytes> <first file>"
use strict;
use warnings;
use Text::ParseWords qw(shellwords);
use File::Basename qw(basename);

my ($cwd, $cmd) = @ARGV;
exit 0 unless defined $cmd && length $cmd;
my $CODE_RE = qr/\.(py|ts|tsx|js|jsx|go|rs|rb|java|kt|cs|swift|c|cpp|h|hpp|vue|svelte|dart|scala|clj|ex|exs|erl|hs|ml|php|sh)$/i;
my %READ_VERB = map { $_ => 1 } qw(cat head tail less more bat nl sed awk jq strings xxd markitdown pdftotext);
my $LINE_GUESS = 160;   # bytes per line when a counted limiter follows an unknown stream

# Heredoc bodies are data, never commands.
$cmd =~ s/<<-?\s*['"]?(\w+)['"]?(.*?)\n.*?^\s*\1\s*$/$2/gms;

# split_ops: split on ; && || newline and |, outside quotes. Returns [text, sep-after].
sub split_ops {
  my ($s) = @_; my (@out, $q); my $cur = '';
  for (my $i = 0; $i < length $s; $i++) {
    my $c = substr($s, $i, 1);
    if ($q) { $cur .= $c; $q = undef if $c eq $q; next; }
    if ($c eq "'" || $c eq '"') { $q = $c; $cur .= $c; next; }
    if ($c eq '\\') { $cur .= substr($s, $i, 2); $i++; next; }
    my $two = substr($s, $i, 2);
    if ($two eq '&&' || $two eq '||') { push @out, [$cur, 'seq']; $cur = ''; $i++; next; }
    if ($c eq ';' || $c eq "\n") { push @out, [$cur, 'seq']; $cur = ''; next; }
    if ($c eq '|') { push @out, [$cur, 'pipe']; $cur = ''; next; }
    $cur .= $c;
  }
  push @out, [$cur, 'seq'];
  return @out;
}

sub resolve {
  my ($p) = @_; $p =~ s{^~(?=/|$)}{$ENV{HOME}};
  $p =~ s{^\$\{?([A-Za-z_]\w*)\}?}{$ENV{$1} // ""}e;
  return $p =~ m{^/} ? $p : "$cwd/$p";
}
sub fsize   { my @s = stat($_[0]); return @s ? $s[7] : 0; }
sub lines_bytes {   # bytes of lines $from..$to (1-based, inclusive) of a file
  my ($f, $from, $to) = @_; my $n = 0; my $b = 0;
  open(my $fh, '<', $f) or return 0;
  while (my $l = <$fh>) { $n++; next if $n < $from; last if $n > $to; $b += length $l; }
  close $fh; return $b;
}
sub tail_bytes {
  my ($f, $k) = @_; open(my $fh, '<', $f) or return 0; my @l = <$fh>; close $fh;
  my $b = 0; $b += length $_ for @l[($#l - $k + 1 < 0 ? 0 : $#l - $k + 1) .. $#l]; return $b;
}
sub count_arg {     # value of -n N / -N / -c N in a token list; returns (kind, N)
  my @t = @_;
  for (my $i = 0; $i < @t; $i++) {
    return ('from', $1) if $t[$i] =~ /^\+(\d+)$/ || $t[$i] =~ /^-n\+(\d+)$/;
    return ('from', $1) if $t[$i] eq '-n' && defined $t[$i+1] && $t[$i+1] =~ /^\+(\d+)$/;
    return ('l', $1) if $t[$i] =~ /^-(\d+)$/;
    return ('l', $1) if $t[$i] =~ /^-n(\d+)$/;
    return ('c', $1) if $t[$i] =~ /^-c(\d+)$/;
    return ('l', $t[$i+1]) if $t[$i] eq '-n' && defined $t[$i+1] && $t[$i+1] =~ /^\d+$/;
    return ('c', $t[$i+1]) if $t[$i] eq '-c' && defined $t[$i+1] && $t[$i+1] =~ /^\d+$/;
  }
  return ('l', 10);
}

# stage_words: tokens of one pipeline stage minus env assignments and redirects;
# also reports whether stdout is redirected away from context.
sub stage_words {
  my ($text) = @_; my @w = shellwords($text); my @keep; my $redir = 0;
  for (my $i = 0; $i < @w; $i++) {
    my $t = $w[$i];
    if ($t =~ /^(?:1|&)?>>?(.*)$/) {           # stdout (or both) redirect
      my $target = length $1 ? $1 : ($w[$i+1] // ''); $i++ unless length $1;
      $redir = 1 unless $target =~ /^&/;       # >&2 still reaches the Bash result
      next;
    }
    next if $t =~ /^\d+>/ || $t =~ /^</;       # stderr redirects and input redirects
    next if !@keep && $t =~ /^[A-Za-z_][A-Za-z0-9_]*=/;
    push @keep, $t;
  }
  my %lead = map { $_ => 1 } (qw(command sudo time do then else elif xargs env nohup), "(", "{", "!");
  shift @keep while @keep && $lead{$keep[0]};
  splice(@keep, 0, 2) if @keep >= 2 && $keep[0] eq 'rtk' && $keep[1] eq 'proxy';
  return ($redir, @keep);
}

# estimate_read: bytes a read verb prints, plus whether a code file is involved.
sub estimate_read {
  my ($verb, @args) = @_;
  my @files = grep { -f $_ } map { /[*?]/ ? glob(resolve($_)) : resolve($_) } grep { !/^-/ } @args;
  return (0, 0, '') unless @files;
  my ($bytes, $code) = (0, 0);
  for my $f (@files) {
    my $before = $bytes;
    if ($verb eq 'head') {
      my ($k, $n) = count_arg(@args); $bytes += $k eq 'c' ? $n : lines_bytes($f, 1, $n);
    } elsif ($verb eq 'tail') {
      my ($k, $n) = count_arg(@args);
      $bytes += $k eq 'c' ? $n : $k eq 'from' ? lines_bytes($f, $n, 1e12) : tail_bytes($f, $n);
    } elsif ($verb eq 'sed' && grep { $_ eq '-n' } @args) {
      my ($script) = grep { /^\d+(,(\d+|\$))?p$/ } @args;
      if ($script && $script =~ /^(\d+)(?:,(\d+|\$))?p$/) {
        $bytes += lines_bytes($f, $1, !defined $2 ? $1 : $2 eq '\$' ? 1e12 : $2);
      } elsif (grep { $_ eq 'p' } @args) { $bytes += fsize($f); }   # identity: sed -n p
      # any other -n script (pattern ranges, s///p) prints a filtered subset: not costed
    } elsif ($verb eq 'jq') {
      $bytes += fsize($f) if grep { $_ eq '.' } @args;            # identity: jq .
    } elsif ($verb eq 'awk') {
      $bytes += fsize($f) if grep { /^(1|\{ ?print ?\}|\{ ?print \$0 ?\})$/ } @args;
    } else {
      $bytes += fsize($f);
    }
    $code += $bytes - $before if $f =~ $CODE_RE;
  }
  return ($bytes, $code, $files[0]);
}

# writes_file: converters that take an output path print nothing to context.
sub writes_file {
  my ($v, @a) = @_;
  return 1 if $v eq 'markitdown' && grep { $_ eq '-o' || /^--output/ } @a;
  if ($v eq 'pdftotext') { my @pos = grep { !/^-/ } @a; return 1 if @pos >= 2 && $pos[1] ne '-'; }
  return 0;
}

my @segs = split_ops($cmd);
my ($total, $code_total, $first) = (0, 0, '');
my @pipeline;
for my $seg (@segs) {
  push @pipeline, $seg->[0];
  next if $seg->[1] eq 'pipe';
  # ── evaluate one complete pipeline ──
  my @stages = @pipeline; @pipeline = ();
  my ($redir_last, @last) = stage_words($stages[-1]);
  next unless @last || @stages > 1;
  if (@stages == 1 && @last && $last[0] eq 'cd') {          # follow cd for later segments
    my $to = resolve($last[1] // $ENV{HOME}); $cwd = $to if -d $to; next;
  }
  next if $redir_last;                                      # stdout goes to a file
  my $lv = @last ? basename($last[0]) : '';
  next if $lv eq 'wc';
  next if ($lv eq 'grep' || $lv eq 'rg') && grep { /^-[a-zA-Z]*c/ } @last;
  next if ($lv eq 'grep' || $lv eq 'rg') && @stages > 1 && !grep { /^-[a-zA-Z]*v/ } @last;
  my ($est, $code, $file) = (0, 0, '');
  my $stream_file;                                          # single file feeding the pipe
  for my $k (0 .. $#stages) {
    my ($r, @w) = stage_words($stages[$k]);
    next unless @w;
    my $v = basename($w[0]);
    next unless $READ_VERB{$v};
    next if $v eq 'sed' && grep { /^-[a-zA-Z]*i/ } @w;     # in-place edit prints nothing
    next if writes_file($v, @w[1..$#w]);
    next if $k > 0 && $k == $#stages && ($v eq 'head' || $v eq 'tail' || $v eq 'sed');   # limiter, below
    my ($b, $c, $f) = estimate_read($v, @w[1..$#w]);
    $stream_file = $f if $k == 0 && ($v eq 'cat' || $v eq 'nl') && $f;
    ($est, $code, $file) = ($est + $b, $code + $c, $file || $f);
  }
  # ── a counted limiter at the end of a pipe caps the stream ──
  if (@stages > 1 && $est > 0) {
    my $lim;
    my @la = @last[1..$#last];
    if ($lv eq 'head' || $lv eq 'tail') {
      my ($k, $n) = count_arg(@la);
      $lim = $k eq 'c' ? $n
           : $k eq 'from' ? undef
           : $stream_file ? ($lv eq 'head' ? lines_bytes($stream_file, 1, $n) : tail_bytes($stream_file, $n))
           : $n * $LINE_GUESS;
    } elsif ($lv eq 'sed' && grep { $_ eq '-n' } @la) {
      my ($sc) = grep { /^\d+(,(\d+|\$))?p$/ } @la;
      if ($sc && $sc =~ /^(\d+)(?:,(\d+|\$))?p$/) {
        my $to = !defined $2 ? $1 : $2 eq '$' ? 1e12 : $2;
        $lim = $stream_file ? lines_bytes($stream_file, $1, $to) : ($to - $1 + 1) * $LINE_GUESS;
      } else { $lim = 0; }                                  # pattern filter: small output
    }
    if (defined $lim && $lim < $est) { $code = $est ? int($code * $lim / $est) : 0; $est = $lim; }
  }
  ($total, $code_total, $first) = ($total + $est, $code_total + $code, $first || $file);
}
print "$total $code_total $first\n" if $total > 0;
