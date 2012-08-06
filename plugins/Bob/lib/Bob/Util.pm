#############################################################################
# Copyright © 2008-2009 Six Apart Ltd.
# This program is free software: you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
# version 2 for more details.  You should have received a copy of the GNU
# General Public License version 2 along with this program. If not, see
# <http://www.gnu.org/licenses/>.

package Bob::Util;

use strict;
use warnings;
use base 'Exporter';
our @EXPORT_OK = qw( get_type_data get_frequency_data );

use constant FREQUENCIES => [
    { 1    => '1 minute' },
    { 2    => '2 minutes' },
    { 5    => '5 minutes' },
    { 10   => '10 minutes' },
    { 15   => '15 minutes' },
    { 20   => '20 minutes' },
    { 30   => '30 minutes' },
    { 45   => '45 minutes' },
    { 60   => '60 minutes' },
    { 90   => '90 minutes' },
    { 120  => '2 hours' },
    { 240  => '4 hours' },
    { 360  => '6 hours' },
    { 480  => '8 hours' },
    { 720  => '12 hours' },
    { 1440 => '24 hours' },
    { 2880 => '48 hours' },
    { 10080 => '7 days' },
];

use constant TYPES => [
    { 'all'              => 'Entire Blog' },
    { 'indexes'          => 'All Indices' },
    { 'archives'         => 'All Archives' },
    { 'Page'             => 'All Page Archives' },
    { 'Individual'       => 'All Individual Entry Archives' },
    { 'Yearly'           => 'All Yearly Archives' },
    { 'Monthly'          => 'All Monthly Archives' },
    { 'Weekly'           => 'All Weekly Archives' },
    { 'Daily'            => 'All Daily Archives' },
    { 'Category'         => 'All Category Archives' },
    { 'Category-Yearly'  => 'All Category-Yearly Archives' },
    { 'Category-Monthly' => 'All Category-Monthly Archives' },
    { 'Category-Daily'   => 'All Category-Daily Archives' },
    { 'Category-Weekly'  => 'All Category-Weekly Archives' },
    { 'Author'           => 'All Author Archives' },
    { 'Author-Yearly'    => 'All Author-Yearly Archives' },
    { 'Author-Monthly'   => 'All Author-Monthly Archives' },
    { 'Author-Weekly'    => 'All Author-Weekly Archives' },
    { 'Author-Daily'     => 'All Author-Daily Archives' },
];

sub get_type_data       { get_constants(TYPES, @_) }
sub get_frequency_data  { get_constants(FREQUENCIES, @_) }

sub get_constants {
    my ( $data, $key_name, $val_name, $selected_val ) = @_;
    return unless $data;
    my $converted;
    my $wants_arrayref = (defined $key_name and defined $val_name);
    $selected_val = '' unless defined $selected_val;
    foreach my $pair (@$data) {
        my $row;
        my @pair = %$pair;
        if ($wants_arrayref) {
            ($row->{$key_name}, $row->{$val_name}) = @pair;
            $row->{selected} = ( $selected_val eq $pair[0] );
            push @$converted, $row;            
        }
        else {
            $converted->{ $pair[0] } = $pair[1];
        }
    }
    return $converted;
}

sub rebuild_for_job {
    my $job = shift; # Schwartz job
    use MT::WeblogPublisher;
    use MT::Util;
    use MT;
    use Bob::Job;
    my $bobjob = Bob::Job->load( $job->uniqkey );
    return 1 unless $bobjob;
    my $debug   = MT->config('BobDebug');
    my $blog_id = $bobjob->blog_id;

    if ( $bobjob->is_active ) {
        my $types = get_type_data();
        use MT::WeblogPublisher;
        my $pub = MT::WeblogPublisher->new;
        if ( $bobjob->type eq 'all' ) {
            $pub->rebuild( BlogID => $blog_id );
            if ($debug) {
                MT->log( 'Bob rebuilding all for blog ' . $blog_id );
            }
        }
        elsif ( $bobjob->type eq 'indexes' ) {
            if ($debug) {
                MT->log( 'Bob rebuilding indexes for blog ' . $blog_id );
            }
            $pub->rebuild_indexes( BlogID => $blog_id );
        }
        elsif ( $bobjob->type eq 'archives' ) {
            if ($debug) {
                MT->log( 'Bob rebuilding archives for blog ' . $blog_id );
            }
            $pub->rebuild( BlogID => $blog_id, NoIndexes => 1 );
        }
        else {
            if ($debug) {
                MT->log( 'Bob rebuilding ' . $bobjob->type . ' archives for blog ' . $blog_id );
            }
            $pub->rebuild(
                BlogID      => $blog_id,
                NoIndexes   => 1,
                ArchiveType => $bobjob->type,
            );
        }
        $bobjob->last_run( MT::Util::epoch2ts( $bobjob->blog_id, time ) );
        $bobjob->save;
        return 1;
    }
}

sub job_preremove {
    my ( $cb, $bobjob ) = @_;
    use MT::TheSchwartz::Job;
    my $key = $bobjob->id;
    my @jobs = MT::TheSchwartz::Job->load( { uniqkey => $key } );
    foreach my $job (@jobs) {
        $job->remove;
    }
    return 1;
}

1;
