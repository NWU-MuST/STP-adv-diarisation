#!/usr/bin/perl
use warnings;
use strict;
use open IO => ':encoding(utf8)';

use utf8;

my $debug = 0;
my $tgt   = "SPEECH";

if ((@ARGV + 0) != 1) {
  print "perl interpet_scluster_results.pl <in:speech> <in:scluster>\n\n";
  print "     <speech>     - Input filename of textgrid.\n";
  print "     <sclsuter>   - Output filename of kaldi segments file.\n";
  exit 1;
}

my $fn_scluster = $ARGV[0];

my %lines;
my $cnt = -1;
my $prev_lab = "";

my %scluster;
my %dur;
open SCLUSTER, "$fn_scluster" or die "Error: Cannot open '$fn_scluster' for reading!\n";
while(<SCLUSTER>) {
  chomp;
  my $line = $_;
  my @parts = split(/\s+/,$_);

  if ($parts[0] =~ /C\[(.*)\]/) { $parts[0] = "C_$1"; }
  $line = join " ", @parts;

  $scluster{$parts[1]}{"te"} = $parts[2];
  $scluster{$parts[1]}{"lab"} = $parts[0];
  $dur{$parts[0]} += $parts[2] - $parts[1];

  my $lab = $parts[0];
  if ($lab ne $prev_lab) { $cnt += 1; }
  push @{ $lines{$cnt} }, $line;
  $prev_lab = $lab;
}
close(SCLUSTER);

my @sorted = sort { $a <=> $b} keys %scluster;
printf "Info: %d start times\n", scalar(@sorted);
foreach my $i (0..(@sorted - 1)) {
  my $ts_a = $sorted[$i];
  my $te_a = $scluster{$ts_a}{"te"};
  printf "XXX: %s %f %f\n", $scluster{$ts_a}{"lab"}, $ts_a, $te_a;
}

# Now select candidate for training
my $min_num_samples = 2;
my $min_dur_per_sample = 1.5;
my $min_dur_per_speaker= 10.0;

my %spks;
foreach my $i (sort { $a <=> $b } keys %lines) {
  my $dur = 0;
  my $lab = "";
  foreach my $line (@{ $lines{$i} }) {
    my @parts = split(/\s+/,$line);
    $dur += $parts[2] - $parts[1];
    $lab = $parts[0];
  }

  # Make sure all speakers are kept track of, even if only many short samples.
  $spks{$lab}{"dur"} += 0;

  if ($dur >= $min_dur_per_sample) {
    # Print all the lines
    foreach my $line (@{ $lines{$i} }) {
      #print "XXX: $line\n";
      push @{ $spks{$lab}{"samples"} }, $line;
    }

    $spks{$lab}{"dur"} += $dur;
  }
}

my %print;
foreach my $spk (sort keys %spks) {
  if ($spks{$spk}{"dur"} < $min_dur_per_speaker) {
    printf "Info: discarding '$spk' due to too little speech: %.2f (%.2f required)\n", $spks{$spk}{"dur"}, $min_dur_per_speaker;
    delete $spks{$spk};
  } else {
    printf "Info: speaker '$spk' has %ds available for training.\n", $spks{$spk}{"dur"};
    foreach my $line (@{ $spks{$spk}{"samples"} }) {
      my @parts = split(/\s+/,$line);
      my $ts = $parts[1];
      if (exists($print{$ts})) {
        die "Error: '$line' should not exist yet ($print{$ts})!\n";
      }
      $print{$ts} = $line;
    }
  }
}

foreach my $ts (sort { $a <=> $b } keys %print) {
  printf "YYY %s\n", $print{$ts};
}
