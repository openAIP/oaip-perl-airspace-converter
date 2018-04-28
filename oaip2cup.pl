#!/usr/bin/perl
#
# converts OpenAIP XML Airport descriptions to OpenAir CUP format.
# The OpenAir CUP format is optimized for glider pilots using XCSoar.
# Best effort is made to include as much information as necessary (for
# glider pilots) into the somewhat restricted OpenAir CUP format.
# e.g. multiple runway and radio frequencies.
# AD_MIL type aerodroms are marked as Landingfields meaning:
# don't use it unless you really really have to.
# Any type of heliports or water airfields are ignored. :-)
#
# Author: Ronald Niederhagen
# Initial version as of April 20, 2017
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.


use strict;
use warnings;
use Switch;
use POSIX;
use Data::Dumper qw(Dumper);
use List::MoreUtils qw(any);
use utf8;
use Text::Unidecode;
use XML::LibXML;

my $my_debug = 0;

sub trim {
  $_[0] =~ s/^\s*//g;
  $_[0] =~ s/\s*$//g;
  return $_[0] ;
}

sub format_string_kc {
  my $n = $_[0];
  $n =~ s/"//g;
  $n =~ s/Ä/AE/g;
  $n =~ s/Ö/OE/g;
  $n =~ s/Ü/UE/g;
  $n =~ s/ä/ae/g;
  $n =~ s/ö/oe/g;
  $n =~ s/ü/ue/g;
  $n =~ s/[^[:ascii:]]+//g;  # get rid of non-ASCII characters
  return '"'.$n.'"';
}

sub format_string {
  my $n = format_string_kc($_[0]);
  $n =~ s/"//g;
  $n =~ s/([\w']+)/\u\L$1/g;
  return '"'.$n.'"';
}

sub frac2gmf {
  my $hem;
  my $grad = $_[0];

  if ($grad < 0) {
    $grad = $grad * -1.0;
    $hem = $_[2];
    } else { $hem = $_[1]; }

  my $g = int $grad;
  my $m = 60 * ($grad - $g);

  return (sprintf("%02d%06.3f%s",$g,$m,$hem));
}

my $argc = @ARGV;
if ($argc != 2) { perror "Usage: $0 input_file output_file\n"; exit(); }
my $filename = shift @ARGV;
my $result = shift @ARGV;

open(my $of, '>', $result) or die "Could not open file '$filename' for write $!";

my $parser = XML::LibXML->new();
my $xmldoc = $parser->parse_file($filename);

if($@) {
    # Log failure and exit
    print "Error parsing '$filename':\n$@";
    exit 0;
}

my $nm;
my $icao;
my @attrs;
my @freqs;
my $freq;
my $apt_type;
my ($num,$unit,$ref);
my $nspace=0;
my $country;
my $lat;
my $lon;
my $elev;
my $elev_unit;
my $radio_info;
my $rwy_nm;
my $nrwys;
my @rwydescr;
my $sfc;
my $length;
my $length_unit;
my $direction;
my %type_cnt;
my @loc_of_interest = ('AF_CIVIL','LIGHT_AIRCRAFT','GLIDING','APT','AF_MIL_CIVIL','INTL_APT','AD_MIL');
my @OpenAir;


for my $airport ( $xmldoc->findnodes('/OPENAIP/WAYPOINTS/AIRPORT') ) {

  for (my $i=0; $i < 11; $i++) {$OpenAir[$i] = 'n.a.';}
  $apt_type = $airport->getAttribute('TYPE');
  $type_cnt{$apt_type} += 1;

  if (any {$_ eq $apt_type} @loc_of_interest) {
    print 'AC ', $apt_type, "\n" if $my_debug;
    $OpenAir[6] = 2;

    $nm = $airport->getChildrenByTagName('NAME');
    $icao = $airport->getChildrenByTagName('ICAO');
    $country = $airport->getChildrenByTagName('COUNTRY');
    $OpenAir[0] = format_string($nm->to_literal);
    $OpenAir[1] = '"'.$icao->to_literal.'"';
    $OpenAir[2] = $country->to_literal;
    print 'AN ', trim($nm->to_literal), ' ',
    		trim($country->to_literal), ' ',
    		trim($icao->to_literal), ' ',
		"\n" if $my_debug;

    $radio_info = 0;
    foreach my $radio ($airport->findnodes('./RADIO'))
      {
      foreach my $attr ($radio->findnodes('./@*'))
	{ if (($attr->nodeName eq 'CATEGORY') && ($attr->value eq 'COMMUNICATION'))
	  {
	  if ($radio->getChildrenByTagName('TYPE') eq 'INFO')
	    { $freq = $radio->getChildrenByTagName('FREQUENCY');
	    $radio_info = 1;
	    $OpenAir[9] = trim($freq->to_literal);
	    print 'FREQ ', trim($freq->to_literal), "\n" if $my_debug; }
	  }
	}
      unless ($radio_info) {
	foreach my $attr ($radio->findnodes('./@*'))
	  { if (($attr->nodeName eq 'CATEGORY') && ($attr->value eq 'COMMUNICATION'))
	    {
	    $freq = $radio->getChildrenByTagName('FREQUENCY');
	    $OpenAir[9] = trim($freq->to_literal);
	    print 'FREQ ', $radio->getChildrenByTagName('TYPE'), ' ',
		  trim($freq->to_literal), "\n" if $my_debug; }
	  }
	}
      }

    foreach my $loc ($airport->findnodes('./GEOLOCATION'))
      {
      $lat = $loc->getChildrenByTagName('LAT');
      $lon = $loc->getChildrenByTagName('LON');
      $elev = $loc->getChildrenByTagName('ELEV');
      $elev_unit = '?';
      foreach my $attr ($loc->findnodes('./ELEV/@*'))
	{ if ($attr->nodeName eq 'UNIT') { $elev_unit = $attr->value; }}
      $OpenAir[3] = frac2gmf(trim($lat->to_literal),'N','S');
      $OpenAir[4] = '0'.frac2gmf(trim($lon->to_literal),'E','W');
      $OpenAir[5] = sprintf('%1.1f',trim($elev->to_literal)). $elev_unit;
      print 'LOC ',
	trim($lat->to_literal), ' ',
	trim($lon->to_literal), ' ',
	trim($elev->to_literal), ' ',
 	$elev_unit, ' ',
	"\n" if $my_debug; 
      }

    $nrwys = 0;
    @rwydescr = ();
    foreach my $rwy ($airport->findnodes('./RWY'))
      { 
      foreach my $attr ($rwy->findnodes('./@*'))
	{ if (($attr->nodeName eq 'OPERATIONS') && ($attr->value eq 'ACTIVE'))
	  {
	  $rwy_nm = $rwy->getChildrenByTagName('NAME');
	  $sfc = $rwy->getChildrenByTagName('SFC');
	  $length = $rwy->getChildrenByTagName('LENGTH');
	  $length_unit = '?';
	  $direction = '?';
	  foreach my $attr ($rwy->findnodes('./LENGTH/@*'))
	    { if ($attr->nodeName eq 'UNIT') { $length_unit = $attr->value; }}
	  my $d;
	  $direction = 999;
	  foreach $attr ($rwy->findnodes('./DIRECTION/@*')) {
	    if ($attr->nodeName eq 'TC') {
	      $d = $attr->value;
	      if ($d < $direction) { $direction = $d; }}}
	  $OpenAir[7] = $direction;
	  $OpenAir[8] = trim($length->to_literal) . $length_unit;
	  $OpenAir[10] = format_string($sfc->to_literal);
	  $rwydescr[$nrwys] = $rwy_nm.' '.format_string($sfc->to_literal);
	  $nrwys += 1;
	  print 'RWY ',
	    trim($nm->to_literal), ' ',
	    trim($sfc->to_literal), ' ',
	    trim($length->to_literal), ' ',
	    $length_unit, ' ',
	    "\n" if $my_debug; 
	  }
	}
      }

    if ($nrwys == 0) { $OpenAir[10] = format_string_kc('RWY ??'); }
    if ($nrwys > 1) { $OpenAir[10] = format_string_kc(join (', ',@rwydescr)); }
    if ($apt_type eq 'AD_MIL') {$OpenAir[10] = format_string_kc('Mil '.$OpenAir[10]); $OpenAir[6]=3;}
    if ($apt_type eq 'LIGHT_AIRCRAFT') {$OpenAir[10] = format_string_kc('UL '.$OpenAir[10]);}
    if ($apt_type eq 'GLIDING') {$OpenAir[10] = format_string_kc('Segelflug '.$OpenAir[10]);}

    printf $of join(',',@OpenAir) . "\n";
  }
}

close $of;
print Dumper \%type_cnt if $my_debug;

