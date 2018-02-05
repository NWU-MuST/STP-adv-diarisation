#!/usr/bin/perl
use warnings;
use strict;
use open IO => ':encoding(utf8)';

use utf8;

my $debug = 0;
my $tgt   = "SPEECH";

if ((@ARGV + 0) != 2) {
  print "perl merge_segment_files.pl <in:segment-list> <out:merged-segments>\n\n";
  print "Info: Merges segments from multiple small files, which are assumed to\n";
  print "      come from a single larger file.\n";
  print "      The smaller files should have a _ts-te. in the filename.\n";
  exit 1;
}

my $fn_segments = $ARGV[0];
my $fn_merged   = $ARGV[1];

my %segments;
my $cnt = 1;

open LST, "$fn_segments" or die "Error($0): Can't open '$fn_segments' for reading!\n";
while(<LST>) {
  chomp;
  my $fn = $_;
  my @parts = split(/\//,$fn);
  my $bn = $parts[@parts - 1];
  $bn =~ s/\.[^\.]+$//g;

  my $ts;
  my $te;
  if ($bn =~ /_(\d+\.\d+)-(\d+\.\d+)\./) {
    $ts = $1;
    $te = $2;
  } else {
    die "Error($0): No ts or te found in basename '$bn'\n";
  }

  my %map;
  open SEG, "$fn" or die "Error($0): Cannot open '$fn' for reading!\n";
  while(<SEG>) {
    chomp;
    my @parts = split(/\s+/,$_);
    my $lab_local= $parts[0];
    my $ts_local = $parts[1] + $ts;
    my $te_local = $parts[2] + $ts;

    if (!exists($map{$lab_local})) { $map{$lab_local} = "C_$cnt"; $cnt += 1; }

    if (exists($segments{$ts_local})) {
      die "Error($0): '$ts_local' should not exist! $bn\n";
    }

    $segments{$ts_local}{"lab"} = $map{$lab_local};
    $segments{$ts_local}{"te"} = $te_local;
  }
  close(SEG);
}
close(LST);

open OUT, ">$fn_merged" or die "Error($0): Cannot open '$fn_merged' for writing!\n";
foreach my $ts (sort { $a <=> $b } keys %segments) {
  printf OUT "%s %.2f %.2f\n", $segments{$ts}{"lab"}, $ts, $segments{$ts}{"te"};
}
close(OUT);
