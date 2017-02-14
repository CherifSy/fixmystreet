package FixMyStreet::Script::ArchiveOldEnquiries;

use strict;
use warnings;
require 5.8.0;

use FixMyStreet;
use FixMyStreet::App;
use FixMyStreet::DB;
use FixMyStreet::Cobrand;
use FixMyStreet::Map;
use FixMyStreet::Email;


# Problems with this in their bodies_str will be closed
my $bodies = $ENV{BODIES} || '2237';

# What cobrand to use for the email templates
my $cobrand_moniker = $ENV{COBRAND} || 'oxfordshire';

# Limit the number of reports we'll close. Primarily for testing.
my $rows = $ENV{ROWS} || undef;

# Anything before this will be closed with no email
my $closure_cutoff = $ENV{CLOSURE_CUTOFF} || "2015-01-01 00:00:00";

# Anything last updated between $closure_cutoff and this will be closed with an
# email sent to the reporter
my $email_cutoff = $ENV{EMAIL_CUTOFF} || "2016-01-01 00:00:00";

my $query = {
    bodies_str => { 'LIKE', "%${bodies}%"},
    -and       => [
      lastupdate => { '<', $email_cutoff },
      lastupdate => { '>', $closure_cutoff },
    ],
    state      => [ FixMyStreet::DB::Result::Problem->open_states() ],
};

sub archive {
    my @user_ids = FixMyStreet::DB->resultset('Problem')->search($query,
    {
        distinct => 1,
        columns  => ['user_id'],
        rows => $rows,
    })->all;

    @user_ids = map { $_->user_id } @user_ids;

    my $users = FixMyStreet::DB->resultset('User')->search({
        id => \@user_ids
    });

    printf("%d users will receive closure emails.\n", $users->count);

    while ( my $user = $users->next ) {
        send_email_and_close($user);
    }

    my $problems_to_close = FixMyStreet::DB->resultset('Problem')->search({
        bodies_str => { 'LIKE', "%${bodies}%"},
        lastupdate => { '<', $closure_cutoff },
        state      => [ FixMyStreet::DB::Result::Problem->open_states() ],
    }, {
        rows => $rows,
    });

    printf("Closing %d old reports, without sending emails: ", $problems_to_close->count);

    $problems_to_close->update({ state => 'closed' });

    printf("done.\n")
}

sub send_email_and_close {
    my ($user) = @_;

    my $problems = $user->problems->search($query);

    my @problems = $problems->all;

    return if scalar(@problems) == 0;

    my $cobrand = FixMyStreet::Cobrand->get_class_for_moniker($cobrand_moniker)->new();
    $cobrand->set_lang_and_domain($problems[0]->lang, 1);
    FixMyStreet::Map::set_map_class($cobrand->map_type);

    my %h = (
      reports => [@problems],
      report_count => scalar(@problems),
      site_name => $cobrand->moniker,
      user => $user,
      cobrand => $cobrand,
    );

    # Send email
    printf("Sending email about %d reports to user %d: ", scalar(@problems), $user->id);
    my $email_result = FixMyStreet::Email::send_cron(
        $problems->result_source->schema,
        'archive.txt',
        \%h,
        {
            To => [ [ $user->email, $user->name ] ],
        },
        undef,
        undef,
        $cobrand,
        $problems[0]->lang,
    );

    printf("done.\nClosing reports: ");

    $problems->update({ state => 'closed' });
    printf("done.\n");
}
