#!/usr/bin/perl
use warnings;
use strict;
use open IO => ':encoding(utf8)';

use utf8;

my $debug = 0;
my $tgt   = "SPEECH";

if ((@ARGV + 0) != 1) {
  print "perl simple_merge_scluster_output.pl <in:scluster>\n\n";
  print "     <sclsuter>   - scluster results.\n";
  exit 1;
}

my $min_num_cooccurance = 2;
my $fn_scluster = $ARGV[0];

my %scluster;
my %dur;
open SCLUSTER, "$fn_scluster" or die "Error: Cannot open '$fn_scluster' for reading!\n";
while(<SCLUSTER>) {
  chomp;
  my @parts = split(/\s+/,$_);
  $scluster{$parts[1]}{"te"} = $parts[2];
  $scluster{$parts[1]}{"lab"} = $parts[0];
  $dur{$parts[0]} += $parts[2] - $parts[1];
}
close(SCLUSTER);

# 1. Merge adjoining clusters with identical labels
my @sorted = sort { $a <=> $b} keys %scluster;
printf "Info: %d start times\n", scalar(@sorted);
foreach my $i (0..(@sorted - 2)) {
  my $ts_a = $sorted[$i];
  my $ts_b = $sorted[$i + 1];
  my $te_a = $scluster{$ts_a}{"te"};
  my $te_b = $scluster{$ts_b}{"te"};

  if ($te_a == $ts_b and $scluster{$ts_a}{"lab"} eq $scluster{$ts_b}{"lab"}) {
    # Merge
    printf "Info: merging '%s': %.2f - %.2f & %.2f - %.2f =>", $scluster{$ts_a}{"lab"}, $ts_a, $te_a, $ts_b, $te_b;
    $scluster{$ts_a}{"te"} = $scluster{$ts_b}{"te"};
    delete $scluster{$ts_b};
    $sorted[$i + 1] = $ts_a;
    printf " %.2f - %.2f\n", $ts_a, $scluster{$ts_a}{"te"};
  }
}

# 2. Merge clusters coocuring
#    - going to note clusters co-occuring in the same segment. It
#      seems to always be from the same speaker. Only thing we're
#      trying to prevent here, is merging two clusters where
#      completely different people spoke without any silence
#      inbetween.
@sorted = sort { $a <=> $b} keys %scluster;
printf "Info: %d start times\n", scalar(@sorted);

my %pairs;
my $i = 0;
while ($i <= (@sorted - 2)) {
  my $ts_a = $sorted[$i];
  my $ts_b = $sorted[$i + 1];
  my $te_a = $scluster{$ts_a}{"te"};
  my $te_b = $scluster{$ts_b}{"te"};

  # Store all the different clusters from a continuous speech segment
  # in a hash %tmp
  my %tmp;
  while ($te_a == $ts_b) {
    my $la = $scluster{$ts_a}{"lab"};
    my $lb =  $scluster{$ts_b}{"lab"};
    $tmp{$la} = 1;
    $tmp{$lb} = 1;
    $i += 1;
    if ($i <= (@sorted - 2)) {
      $ts_a = $sorted[$i];
      $ts_b = $sorted[$i + 1];
      $te_a = $scluster{$ts_a}{"te"};
      $te_b = $scluster{$ts_b}{"te"};
    } else {
      $te_a = 0;
      $ts_b = 1;
    }
  }

  foreach my $a (sort keys %tmp) {
    foreach my $b (sort keys %tmp) {
      if ($a ne $b) {
        $pairs{$a}{$b} += 1;
        $pairs{$b}{$a} += 1;
      }
    }
  }

  $i += 1;
}

# Now iterate through the segments again, checking if two adjoining segments
# co-occur often
foreach my $i (0..(@sorted - 2)) {
  my $ts_a = $sorted[$i];
  my $ts_b = $sorted[$i + 1];
  my $te_a = $scluster{$ts_a}{"te"};
  my $te_b = $scluster{$ts_b}{"te"};
  my $la = $scluster{$ts_a}{"lab"};
  my $lb = $scluster{$ts_b}{"lab"};

  if ($te_a == $ts_b and 
	  exists($pairs{$la}) and 
	  exists($pairs{$la}{$lb}) and 
	  $pairs{$la}{$lb} >= $min_num_cooccurance) {

    # Merge
    printf "Info: merging-b '%s': %.2f - %.2f & %.2f - %.2f =>", $scluster{$ts_a}{"lab"}, $ts_a, $te_a, $ts_b, $te_b;
    printf " %.2f - %.2f (%s | %s == %d)\n", $ts_a, $scluster{$ts_a}{"te"}, $scluster{$ts_a}{"lab"}, $scluster{$ts_b}{"lab"}, $pairs{$scluster{$ts_a}{"lab"}}{$scluster{$ts_b}{"lab"}};

    # Use the label of the next cluster, as we may want to merge it with
    # the next cluster as well.
    $scluster{$ts_a}{"lab"} = $scluster{$ts_b}{"lab"};
    $scluster{$ts_a}{"te"} = $scluster{$ts_b}{"te"};
    delete $scluster{$ts_b};
    $sorted[$i + 1] = $ts_a;
  } elsif ($te_a == $ts_b and 
	  exists($pairs{$la}) and 
	  exists($pairs{$la}{$lb}) and 
	  $pairs{$la}{$lb} < $min_num_cooccurance) {
    printf "Warning: $la - $lb co-occured less than '$min_num_cooccurance' times\n";
  }
}

# 3. Merge adjoining clusters with identical labels
@sorted = sort { $a <=> $b} keys %scluster;
printf "Info: %d start times\n", scalar(@sorted);
foreach my $i (0..(@sorted - 2)) {
  my $ts_a = $sorted[$i];
  my $ts_b = $sorted[$i + 1];
  my $te_a = $scluster{$ts_a}{"te"};
  my $te_b = $scluster{$ts_b}{"te"};

  if ($te_a == $ts_b and $scluster{$ts_a}{"lab"} eq $scluster{$ts_b}{"lab"}) {
    # Merge
    printf "Info: merging '%s': %.2f - %.2f & %.2f - %.2f =>", $scluster{$ts_a}{"lab"}, $ts_a, $te_a, $ts_b, $te_b;
    $scluster{$ts_a}{"te"} = $scluster{$ts_b}{"te"};
    delete $scluster{$ts_b};
    $sorted[$i + 1] = $ts_a;
    printf " %.2f - %.2f\n", $ts_a, $scluster{$ts_a}{"te"};
  }
}

@sorted = sort { $a <=> $b} keys %scluster;
printf "Info: %d start times\n", scalar(@sorted);
foreach my $i (0..(@sorted - 1)) {
  my $ts_a = $sorted[$i];
  my $te_a = $scluster{$ts_a}{"te"};
  printf "XXX: %s %f %f\n", $scluster{$ts_a}{"lab"}, $ts_a, $te_a;
}
