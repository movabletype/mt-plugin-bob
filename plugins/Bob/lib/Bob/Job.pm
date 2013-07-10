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

package Bob::Job;

use strict;
use warnings;

use constant WORKER_PRIORITY    => 1;
use constant SECONDS_PER_MINUTE => 60;

use base qw( MT::Object );
use Bob::Util qw( get_type_data get_frequency_data );

__PACKAGE__->install_properties(
    {   column_defs => {
            'id'          => 'integer not null auto_increment',
            'blog_id'     => 'integer not null',
            'is_active'   => 'integer default 1',
            'frequency'   => 'integer not null',
            'target_time' => 'string(4)',
            'type'        => 'string(10)',
            'identifier'  => 'string(255)',
            'last_run'    => 'datetime',
            'next_run'    => 'datetime'
        },
        indexes     => { blog_id => 1, is_active => 1 },
        audit       => 1,
        datasource  => 'bob_job',
        primary_key => 'id',
    }
);

sub class_type {
    'bob_job';
}

sub class_label {
    MT->translate("Rebuilder Job");
}

sub class_label_plural {
    MT->translate("Rebuilder Jobs");
}

sub inject_worker {
    my $self = shift;
    require MT::TheSchwartz;
    require MT::Util;
    require TheSchwartz::Job;
    require MT::Blog;
    my $blog = MT::Blog->load( $self->blog_id );
    return unless ( $blog );
    my $debug     = MT->config('BobDebug');
    my $frequency = $self->frequency;
    my $last_run  = $self->last_run;
    my $time      = time();
    if ($last_run) {    # turn it into an epoch - convert it to GMT first
        $last_run = MT::Util::ts2epoch( $blog, $last_run );
    }
    else {
        $last_run = $time;
    }
    # We must never insert a job with a next_run in the past
    my $next_epoch = $last_run + ( $frequency * SECONDS_PER_MINUTE );
    if ( $next_epoch < $time ) {
        if ($debug && $self && $self->id ) {
            MT->log(  'Bob job #'
                    . $self->id
                    . 'attempted to insert a job into the past with epoch '
                    . $next_epoch );
        }
        $next_epoch = time() + SECONDS_PER_MINUTE;
    }
    my $job = TheSchwartz::Job->new();
    $job->funcname('Bob::Worker::Rebuilder');
    $job->uniqkey( $self->id );
    $job->priority(WORKER_PRIORITY);
    $job->coalesce( $self->id );
    $job->run_after($next_epoch);
    MT::TheSchwartz->insert($job);
    $self->next_run( MT::Util::epoch2ts( $blog, $next_epoch ) );
    $self->save;
}

# The MT5 Listing Screen properties
sub list_properties {
    return {
        id => {
            auto    => 1,
            label   => 'ID',
            order   => 100,
            display => 'optional',
        },
        is_active => {
            label   => 'Status',
            order   => '101',
            col     => 'is_active',
            display => 'default',
            base    => '__virtual.string',
            html    => sub {
                my $prop = shift;
                my ( $obj, $app, $opts ) = @_;
                my $statuses = {
                    '0' => {
                        text => 'Inactive',
                        icon => 'role-inactive.gif',
                    },
                    '1' => {
                        text => 'Active',
                        icon => 'role-active.gif',
                    },
                };
                return '<img src="' . $app->static_path . 'images/status_icons/'
                    . $statuses->{ $obj->is_active }->{icon} . '" '
                    . 'width="9" height="9" style="padding: 0 2px 1px 0;" /> '
                    . $statuses->{ $obj->is_active }->{text};
            },
        },
        blog_name => {
            base      => '__common.blog_name',
            order     => 200,
            display   => 'force',
            site_name => sub { MT->app->blog ? 0 : 1 },
        },
        type => {
            base    => '__virtual.string',
            label   => 'Rebuild Object',
            order   => 300,
            display => 'force',
            col     => 'type',
            html    => sub {
                my $prop = shift;
                my ( $obj, $app, $opts ) = @_;
                my $types = get_type_data();
                my $uri = $app->uri . '?__mode=rebuilder_edit&id=' . $obj->id;
                return "<a href=\"$uri\">" . $types->{ $obj->type } . '</a>';
            },
        },
        frequency => {
            auto    => '1',
            label   => 'Frequency',
            order   => 400,
            display => 'default',
            html    => sub {
                my $prop = shift;
                my ( $obj, $app, $opts ) = @_;
                my $freqs = get_frequency_data();
                return $freqs->{ $obj->frequency };
            },
        },
        last_run => {
            base    => '__virtual.date',
            label   => 'Last Run',
            order   => 500,
            display => 'default',
            col     => 'last_run',
            # Need to set the blog context to get the correct date display.
            html    => sub {
                my $prop = shift;
                my ( $obj, $app, $opts ) = @_;
                my $ts          = $prop->raw(@_) or return 'never';
                my $date_format = MT::App::CMS::LISTING_DATE_FORMAT();
                my $blog        = MT->model('blog')->load( $obj->blog_id );
                my $is_relative
                    = ( $app->user->date_format || 'relative' ) eq
                    'relative' ? 1 : 0;
                return $is_relative
                    ? MT::Util::relative_date( $ts, time, $blog )
                    : MT::Util::format_ts(
                        $date_format,
                        $ts,
                        $blog,
                        $app->user ? $app->user->preferred_language
                        : undef
                    );
            },
        },
        next_run => {
            base    => '__virtual.date',
            label   => 'Next Run',
            order   => 600,
            display => 'default',
            col     => 'next_run',
            # Need to set the blog context to get the correct date display.
            html    => sub {
                my $prop = shift;
                my ( $obj, $app, $opts ) = @_;
                my $ts          = $prop->raw(@_) or return '';
                my $date_format = MT::App::CMS::LISTING_DATE_FORMAT();
                my $blog        = MT->model('blog')->load( $obj->blog_id );
                my $is_relative
                    = ( $app->user->date_format || 'relative' ) eq
                    'relative' ? 1 : 0;
                return $is_relative
                    ? MT::Util::relative_date( $ts, time, $blog )
                    : MT::Util::format_ts(
                        $date_format,
                        $ts,
                        $blog,
                        $app->user ? $app->user->preferred_language
                        : undef
                    );
            },
        },
        created_by => {
            base    => '__virtual.author_name',
            order   => 700,
            display => 'optional',
        },
        created_on => {
            base    => '__virtual.created_on',
            order   => 800,
            display => 'optional',
        },
    };
}


1;
