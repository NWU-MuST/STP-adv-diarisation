#!/usr/bin/perl
use warnings;
use strict;
use open IO => ':encoding(utf8)';

use utf8;

my $debug = 1;
my $tgt   = "SPEECH";

# Window size = 5s (count the amount of other high conf tags)
# Threshold (or apply to everything?)

if ((@ARGV + 0) < 3) {
  print "perl window_boost_gmm_scores.pl <in:models> <in:ll.log> <par:smoothing-factor> (<par:remove-small-clusters>)\n\n";
  print "<smoothing-factor>     - value with which the average ll over a 5s window is added\n";
  print "                        to the current ll.\n";
  print "<remove-small-clusters>- if defined, remove all clusters with less than Xs of speech\n";
  exit 1;
}

my $fn_models = $ARGV[0];
my $fn_ll     = $ARGV[1];
my $smoothing_factor = $ARGV[2];

my $min_amount_speech = 0;
if (scalar(@ARGV) == 4) {
  $min_amount_speech = $ARGV[3];
}

my @models;
open MODELS, "$fn_models" or die "Error: Cannot open '$fn_models' for reading!\n";
while(<MODELS>) {
  chomp;
  if (/.*\/(.*).gmm/) {
    push @models, $1;
  }
}
close(MODELS);

# Determine which model is the UBM
my $iubm = 0;
foreach my $i (0..(@models - 1)) { if ($models[$i] =~ /ubm/) { $iubm = $i; } }

my %scores;
open LL, "$fn_ll" or die "Error: Cannot open '$fn_ll' for reading!\n";
while(<LL>) {
  chomp;
  my @parts = split(/\s+/,$_);
  my $bn = shift @parts;
  my $ts = shift @parts;
  my $te = shift @parts;
  my $n_frams = shift @parts;
  my $m_init  = shift @parts;
  my $n_models= shift @parts;

  $scores{$ts}{"te"} = $te;

  my $ubm_ll = $parts[$iubm];

  foreach my $i (0..(@parts - 1)) {
    if ($i != $iubm) {
	    #$scores{$ts}{"models"}{$models[$i]} = $parts[$i] - $ubm_ll;
      $scores{$ts}{"models"}{$models[$i]} = $parts[$i];
    }
  }
}
close(LL);

# Iterate over the scores
my $flag = 1;

my %discarded;
while ($flag == 1) {
  my %cluster_count;
  my @output;

  my $window_size = 5;
  my $boost_pool  = 2;
  my @sorted_ts = sort { $a <=> $b } keys %scores;

  foreach my $i (0..(@sorted_ts - 1)) {
    my %dist;
    my $speech_time = 0;

    my $ts = $sorted_ts[$i];
    my $te = $scores{$ts}{"te"};

    # Count left
    my $flag = 1;
    my $j = $i - 1;
    while ($flag == 1 and $j > 0) {
      # Test that the $jth segment's end time is within window_size seconds from
      # ith start time
      my $j_ts = $sorted_ts[$j];
      my $j_te = $scores{$j_ts}{"te"};
      if ($j_te > ($ts - $window_size)) {
	my $loc_ts = $j_ts;
	if ($j_ts < ($ts - $window_size)) {
	  $loc_ts = $ts - $window_size;
	}
	
	$speech_time += $j_te - $loc_ts;
	foreach my $m (sort keys %{ $scores{$j_ts}{"models"} }) {
	  $dist{$m} += $scores{$j_ts}{"models"}{$m} * ($j_te - $loc_ts);
	}
      } else { $flag = 0; }
      $j -= 1;
    }

    # Count right
    $flag = 1;
    $j = $i + 1;
    while ($flag == 1 and $j < (@sorted_ts + 0)) {
      # Test that the $jth segment's start time is within window_size seconds from
      # ith end time
      my $j_ts = $sorted_ts[$j];
      my $j_te = $scores{$j_ts}{"te"};
      if ($j_ts < ($te + $window_size)) {
	my $loc_te = $j_te;
	if ($j_te > ($te + $window_size)) {
	  $loc_te = $te + $window_size;
	}
	
	$speech_time += $loc_te - $j_ts;

	foreach my $m (sort keys %{ $scores{$j_ts}{"models"} }) {
	  $dist{$m} += $scores{$j_ts}{"models"}{$m} * ($loc_te - $j_ts);
	}
      } else { $flag = 0; }
      $j += 1;
    }

    # LL's over window_size has been accumulated
    # Speech time has been counted
    my @models = sort keys %{ $scores{$ts}{"models"} };
    foreach my $m (@models) {
      if ($speech_time > 0) {
	$dist{$m} /= $speech_time;
      } else {
	$dist{$m} = 0;
      }

      $scores{$ts}{"models"}{$m} += $dist{$m}*$smoothing_factor;
    }

    my $best_score = -999999.99;
    my $best_model = "";
    foreach my $m (@models) {
      # IF a model has been discarded due to too little speech, do not
      # use it again
      if (!exists($discarded{$m})) {
	$cluster_count{$m} += 0; # Make sure all models are taken note of
	if ($scores{$ts}{"models"}{$m} > $best_score) {
	  $best_score = $scores{$ts}{"models"}{$m};
	  $best_model = $m;
	}
      }
    }

    my $line = sprintf "XXX: $best_model %.2f %.2f", $ts, $scores{$ts}{"te"};
    push @output, $line;
    $cluster_count{$best_model} += $scores{$ts}{"te"} - $ts;

    if ($debug == 1) {
    printf "L: %.2f %.2f",$ts, $te;
    foreach my $m (sort keys %{ $scores{$ts}{"models"} }) {
      printf " %8s", $m;
    }
    print "\n";
    printf "O: %.2f %.2f",$ts, $te;
    foreach my $m (sort keys %{ $scores{$ts}{"models"} }) {
      printf " %8.2f", $scores{$ts}{"models"}{$m};
    }
    print "\n";
    printf "B: %.2f %.2f",$ts, $te;
    foreach my $m (sort keys %{ $scores{$ts}{"models"} }) {
      printf " %8.2f", $dist{$m};
    }
    print "\n";
    }
  }

  if ($min_amount_speech == 0) {
    $flag = 0;
  } else {
    my %tmp;
    foreach my $cluster (sort keys %cluster_count) {
      if ($cluster_count{$cluster} < $min_amount_speech) {
	$tmp{$cluster} = 1;
      }
    }

    if (scalar(keys %tmp) > 0) {
      $flag = 1;
      foreach my $cluster (sort keys %tmp) {
	$discarded{$cluster} = 1;
	printf "Warning: Discarding cluster '$cluster': $cluster_count{$cluster}s of speech!\n";
      }
    } else {
      $flag = 0;
    }
  }

  if ($flag == 0) {
    printf "%s\n", (join "\n",@output);
  }

}
print "Done!\n";
