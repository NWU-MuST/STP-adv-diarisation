#!/usr/bin/perl
use warnings;
use strict;
use open IO => ':encoding(utf8)';

use utf8;

my $debug = 0;
my $tgt   = "SPEECH";

if ((@ARGV + 0) != 3) {
  print "perl split_segment_info_folds.pl <in:segment> <in:tag> <dir_out>\n\n";
  print "     <speech>     - Input filename of textgrid.\n";
  print "     <sclsuter>   - Output filename of kaldi segments file.\n";
  exit 1;
}

my $fn_seg = $ARGV[0];
my $tag    = $ARGV[1];
my $dir_out= $ARGV[2];

my %seg;
my %dur;
open SEG, "$fn_seg" or die "Error: Cannot open '$fn_seg' for reading!\n";
while(<SEG>) {
  chomp;
  my $line = $_;
  my @parts = split(/\s+/,$line);

  if ($parts[0] =~ /C\[(.*)\]/) { $parts[0] = "C_$1"; }

  if ($parts[0] eq "$tag") {
    $line = join " ", @parts;

    $seg{$parts[1]}{"line"} = $line;
    $seg{$parts[1]}{"te"} = $parts[2];
    $seg{$parts[1]}{"lab"} = $parts[0];
    $dur{$parts[0]} += $parts[2] - $parts[1];
  }
}
close(SEG);

if (exists($dur{$tag})) {
  printf "Info: %.2fs found for '$tag'\n", $dur{$tag};
} else {
  die "Error: no data found for '$tag'!\n";
}

my $fold_len = $dur{$tag} / 10.0;

printf "Info: desired fold length: %.2fs\n", $fold_len;

my @sorted = sort { $a <=> $b} keys %seg;
my $fold = 1;
my $cnt = 0;
my %folds;

foreach my $i (0..(@sorted - 1)) {
  my $ts = $sorted[$i];
  my $te = $seg{$ts}{"te"};
  my $dur= $te - $ts;

  if ($cnt + $dur < $fold_len) {
    # Assign to this fold
  } else {
    if (($fold_len - $cnt) < ($cnt + $dur - $fold_len) and $fold < 10) {
      # Assign to the next cluster
      $fold += 1;
      $cnt = 0;
    }
  }

  $cnt += $dur;
  $folds{$fold}{"dur"} += $dur;
  push @{ $folds{$fold}{"data"} }, $seg{$ts}{"line"};
}

foreach my $fold (sort { $a <=> $b } keys %folds) {
  printf "FOLD($tag) $fold: %.2fs\n", $folds{$fold}{"dur"};
  my $fn = "$dir_out/$tag.$fold.seg";
  open FN, ">$fn" or die "Error: Cannot open '$fn' for reading!\n";
  printf FN "%s\n", join "\n", @{ $folds{$fold}{"data"} };
  close(FN);
}
