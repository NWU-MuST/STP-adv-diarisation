#!/usr/bin/perl
use warnings;
use strict;
use open IO => ':encoding(utf8)';

use utf8;

my $debug = 0;
my $min = 2.5;


if ((@ARGV + 0) != 2) {
  print "perl file_list.pl <in:script> <in:fn-seg>\n\n";
  print " <script>   - the script file provided to scluster\n";
  print " <seg>      - file will be read, and then be overwritten\n";
  exit 1;
}

my $fn_script = $ARGV[0];
my $fn_seg    = $ARGV[1];

# Read the file
my %map;
my %tgts;
my %vals; # Keep track of actual numbers used in hyp cluster ids

# The script contains line in the format:
# <mfcc> <segment-file>
# <mfcc>         - an mfcc file created with spfcat for one cluster 
# <segment-file> - a segment file corresponding to the mfcc. The name
#                  of the file refers to the previously assigned cluster.
#                  The content of the file refers to the re-assigned cluster id
#                  from scluster.
open SCRIPT, "$fn_script" or die "Error: Cannot open '$fn_script' for reading!\n";
while(<SCRIPT>) {
  chomp;
  my @parts = split(/\s+/,$_);
  my $partial_seg = pop @parts;

  my $ref = "";
  if ($partial_seg =~ /C_(\d+)\./) {
    $ref = "C_$1";
  } else {
    die "Error: Format error in cluster name! >$partial_seg<\n";
  }

  my $hyp = "";
  open SEG, "$partial_seg" or die "Error: Cannot open '$partial_seg' for reading!\n";
  my $line = <SEG>;
  if ($line =~ /C\[(\d+)\]/) {
    $hyp = "C_$1";
    $vals{$1} = 1;
  }

  if (exists($map{$ref})) { die "Error: '$ref' should not have been seen!\n"; }
  print "Info: Mapping $ref to $hyp\n";
  $map{$ref} = $hyp;
  $tgts{$hyp} = 1;
}
close(SCRIPT);

my @lines;
open SEG, "$fn_seg" or die "Error: Cannot open '$fn_seg' for reading!\n";
while(<SEG>) {
  chomp;
  my $line = $_;
  my @parts = split(/\s+/,$line);
  if (!exists($map{$parts[0]})) {
    print "Warning: '$parts[0]' not in map!\n";
    if ($parts[0] =~ /C_(\d+)$/) {
      my $number = $1;
      if (exists($vals{$number})) {
        my @sorted = sort { $b <=> $a } keys %vals;
	my $tgt = $sorted[0] + 1;
	$vals{$tgt} = 1;
	$map{$parts[0]} = "C_$tgt";
	print "Info: (A) Mapping '$parts[0]' to 'C_$tgt'\n";
        $parts[0] = $map{$parts[0]};
      } else {
        $vals{$number} = 1;
	$map{$parts[0]} = $parts[0];
	print "Info: (B) Mapping '$parts[0]' to 'C_$number'\n";
        $parts[0] = $map{$parts[0]};
      }
    } else {
      die "Error: Cluster ID format error!\n";
    }
  } else {
    $parts[0] = $map{$parts[0]};
  }
  push @lines, (join " ",@parts);
}
close(SEG);

open OUT, ">$fn_seg" or die "Error: Cannot open '$fn_seg' for reading!\n";
printf OUT "%s\n", join "\n", @lines;
close(OUT);
