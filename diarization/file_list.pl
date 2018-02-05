#!/usr/bin/perl
use warnings;
use strict;
use open IO => ':encoding(utf8)';

use utf8;

my $debug = 0;

if ((@ARGV + 0) != 3) {
  print "perl file_list.pl <in:dir_mfccs> <in:fn-seg> <in:min-speech-sec>\n\n";
  exit 1;
}

my $dir_mfccs = $ARGV[0];
my $seg = $ARGV[1];
my $min = $ARGV[2];

my %files;
my %lines;
my $cnt = -1;

my $prev_lab = "";
open SEG, "$seg" or die "Error: Cannot open '$seg' for reading!\n";
while(<SEG>) {
  chomp;
  my $line = $_;
  my @parts = split(/\s+/,$_);
  my $lab = $parts[0];

  if ($lab ne $prev_lab) { $cnt += 1; }
  push @{ $lines{$cnt} }, $line;
  $prev_lab = $lab;

}
close(SEG);

foreach my $i (sort { $a <=> $b } keys %lines) {
  my $dur = 0;
  my $lab = "";
  foreach my $line (@{ $lines{$i} }) {
    my @parts = split(/\s+/,$line);
    $dur += $parts[2] - $parts[1];
    $lab = $parts[0];
  }

  if ($dur >= $min) {
    # Print all the lines
    foreach my $line (@{ $lines{$i} }) {
      print "XXX: $line\n";
    }

    $files{$lab} += $dur;
  }
}

foreach my $lab (sort { ($a =~ /C_(\d+)/)[0] <=> ($b =~ /C_(\d+)/)[0] } keys %files) {
  my $fn = "$dir_mfccs/$lab.seg";
  open FN, ">$fn" or die "Error: Cannot open '$fn' for reading!\n";
  printf FN "%s %.2f %.2f\n", $lab, 0, $files{$lab};
  close(FN);
  printf "YYY: %s %s\n", "$dir_mfccs/$lab.mfcc", $fn;
}
