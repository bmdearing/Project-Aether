#!/usr/bin/perl
# v5.5 defence bases: rewrites armor_value / evasion_value / ward_value in every
# armour and shield base .tres onto one curve per defence:
#   slot_base x growth^(item_level - 1) x (this line's old value / the slot's top line's old value)
# so every slot gets the same share for Armour, Evasion and Ward, and lower
# lines and hybrids keep their old ratio to the top line.
# Run from the project root after tools/generate_base_types.gd (which writes the
# doc's old values): perl tools/rescale_defence_bases.pl
use strict;
use warnings;

my %GROWTH = (armor_value => 1.0247, evasion_value => 1.0247, ward_value => 1.03);
# Top base line's value at item level 1, per slot group (0 Helmet, 1 Body, 2 Gloves, 3 Boots, S Shield).
my %BASE = (
	armor_value => {0 => 8.6, 1 => 19.0, 2 => 6.7, 3 => 6.7, S => 14.4},
	evasion_value => {0 => 8.6, 1 => 19.0, 2 => 6.7, 3 => 6.7, S => 7.7},
	ward_value => {0 => 18.0, 1 => 40.0, 2 => 14.0, 3 => 14.0, S => 30.0},
);

my @files;
for my $dir ("data/armor/instances", "data/shields/instances") {
	opendir(my $dh, $dir) or die "$dir: $!";
	push @files, map { "$dir/$_" } grep { /\.tres$/ } readdir($dh);
	closedir($dh);
}

my @items;
for my $path (@files) {
	open(my $fh, "<", $path) or die "$path: $!";
	local $/;
	my $text = <$fh>;
	close($fh);
	my %it = (path => $path, text => $text);
	$it{group} = $path =~ /shields/ ? "S" : ($text =~ /^equip_slot = (\d+)/m ? $1 : 0);
	$it{ilvl} = $text =~ /^item_level = (\d+)/m ? $1 : 0;
	$it{line} = $text =~ /^base_line_id = "([^"]*)"/m ? $1 : "";
	for my $key (keys %GROWTH) {
		$it{$key} = $1 if $text =~ /^$key = ([\d.]+)/m;
	}
	push @items, \%it;
}

# Top line per (group, defence): the tagged line with the biggest value at its lowest item level.
my %top;
for my $key (keys %GROWTH) {
	my %first;
	for my $it (grep { $_->{line} ne "" && defined $_->{$key} && $_->{$key} > 0 } @items) {
		my $id = "$it->{group}|$it->{line}";
		$first{$id} = $it if !$first{$id} || $it->{ilvl} < $first{$id}{ilvl};
	}
	for my $id (keys %first) {
		my ($group) = split /\|/, $id;
		my $best = $top{$key}{$group};
		$top{$key}{$group} = $first{$id} if !$best || $first{$id}{$key} > $best->{$key};
	}
}

# The top line's old value at `ilvl`, interpolated in log space between its tiers.
sub top_value {
	my ($key, $group, $ilvl) = @_;
	my $top = $top{$key}{$group} or return undef;
	my @pts = sort { $a->[0] <=> $b->[0] } map { [$_->{ilvl}, $_->{$key}] }
		grep { $_->{group} eq $group && $_->{line} eq $top->{line} && defined $_->{$key} } @items;
	return $pts[0][1] if $ilvl <= $pts[0][0];
	return $pts[-1][1] if $ilvl >= $pts[-1][0];
	for my $i (1 .. $#pts) {
		next if $ilvl > $pts[$i][0];
		my ($l0, $v0) = @{$pts[$i - 1]};
		my ($l1, $v1) = @{$pts[$i]};
		my $t = ($ilvl - $l0) / ($l1 - $l0);
		return exp(log($v0) + $t * (log($v1) - log($v0)));
	}
}

my $changed = 0;
for my $it (@items) {
	my $text = $it->{text};
	for my $key (keys %GROWTH) {
		next unless defined $it->{$key} && $it->{$key} > 0;
		my $ref = top_value($key, $it->{group}, $it->{ilvl});
		next unless $ref;
		my $level = $it->{ilvl} > 1 ? $it->{ilvl} : 1;
		my $new = $BASE{$key}{$it->{group}} * $GROWTH{$key} ** ($level - 1) * $it->{$key} / $ref;
		$new = $new < 1 ? 1 : int($new + 0.5);
		$text =~ s/^$key = [\d.]+(\r?)$/$key = $new.0$1/m;
	}
	next if $text eq $it->{text};
	open(my $out, ">", $it->{path}) or die "$it->{path}: $!";
	print $out $text;
	close($out);
	$changed++;
}
print "Rescaled $changed bases\n";
