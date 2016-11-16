#!/usr/bin/perl

use warnings;
use strict;

package LEST97;

# A package to convert L-EST 97 coordinates to WSG84 lat / lon
# and vice versa. See [1] for algorithm details and [2] for 
# specifics on L-EST 97.
#
# [1] http://www.linz.govt.nz/geodetic/conversion-coordinates/
#     projection-conversions/lambert-conformal-conic/index.aspx
# [2] http://www.geo.ut.ee/~raivo/ESTCOORD.HTML
#
# Copyright (c) 2012 University of Tartu
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy of 
# this software and associated documentation files (the "Software"), to deal in 
# the Software without restriction, including without limitation the rights to 
# use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies 
# of the Software, and to permit persons to whom the Software is furnished to do 
# so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all 
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE 
# SOFTWARE.

use Exporter 'import';
use Math::Trig;

our @EXPORT = qw(
	lest97_to_wsg84
	wsg84_to_lest97	
);

# Projection constants

use constant {
	
	# GRS-80 ellipsoid parameters
	
	R		=> 6378137,
	ECC		=> 0.0033528106811823188,
	
	# L-EST97 projection parameters
	
	PHI1 	=> 1.01229096615671, # 1st std parallel, 58d00' N
	PHI2	=> 1.03556202279179, # 2nd std parallel, 59d20' N
	PHI0	=> 1.00387069499363, # Origin parallel, 57d31'03.19415" N
	LAMBDA0	=> 0.41887902047864, # Origin latitude, 24d00' E
	N0		=> 6375000,          # False Northing
	E0		=> 500000,	         # False Easting
};

# Derived projection constants

my $e    = sqrt(2*ECC - ECC**2);
my $m1   = _const_m(PHI1);
my $m2   = _const_m(PHI2);
my $t0   = _const_t(PHI0);
my $t1   = _const_t(PHI1);
my $t2   = _const_t(PHI2);
my $n    = (log($m1)-log($m2)) / (log($t1)-log($t2));
my $F    = $m1 / ($n*($t1**$n));
my $rho0 = _const_rho($t0);

sub lest97_to_wsg84 {
	
	# Convert L-EST 97 coordinates to 
	# WSG84 latitude and longitude (degrees).
	
	my ($x, $y) = @_;

	my $lat;
	my $lon;
	my $Nprim = $y - N0;
	my $Eprim = $x - E0;
	my $rhoprim = sqrt($Eprim**2 + ($rho0-$Nprim)**2);	
	my $tprim = ($rhoprim / (R * $F))**(1/$n);
	my $gammaprim = atan($Eprim / ($rho0 - $Nprim));
	
	$lat = pi/2 - 2*atan($tprim);
	$lon = ($gammaprim/$n) + LAMBDA0;
	
	my $old_lat = 0; while (abs($old_lat - $lat) > 1e-6) {
		my $ax;		
		$old_lat = $lat;
		$ax = $tprim * ((1-$e*sin($lat)) / (1+$e*sin($lat)))**($e/2);
		$lat = pi/2 - 2*atan($ax);
	}
	
	(rad2deg($lat), rad2deg($lon));
}

sub wsg84_to_lest97 {
	
	# Convert WSG84 latitude and longitude (degrees) 
	# to L-EST 97 coordinates.
	
	my ($lat, $lon) = @_;
	
	$lat = deg2rad($lat);
	$lon = deg2rad($lon);
	
	my $t = _const_t($lat);
	my $rho = _const_rho($t);
	my $gamma = $n*($lon - LAMBDA0);
	my $y = int(N0 + $rho0 - $rho*cos($gamma));
	my $x = int(E0 + $rho*sin($gamma));
	
	($x, $y);
}

sub _const_m {
	my ($phi) = @_;	
	cos($phi) / sqrt(1 - $e**2 * sin($phi)**2);
}

sub _const_t {
	my ($phi) = @_;
	my $ax = tan(pi/4 - $phi/2);
	my $bx = (
		(1 - $e*sin($phi)) / 
		(1 + $e*sin($phi))
	) ** ($e / 2);
	
	$ax / $bx;
}

sub _const_rho {
	my ($t) = @_;	
	R * $F*($t**$n);	
}

1;
