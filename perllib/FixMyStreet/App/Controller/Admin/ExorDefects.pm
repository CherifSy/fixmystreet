package FixMyStreet::App::Controller::Admin::ExorDefects;
use Moose;
use namespace::autoclean;

use Text::CSV;
use DateTime;
use mySociety::Random qw(random_bytes);

BEGIN { extends 'Catalyst::Controller'; }


sub begin : Private {
    my ( $self, $c ) = @_;

    $c->forward('/admin/begin');
}

sub index : Path : Args(0) {
    my ( $self, $c ) = @_;

    my $csv = Text::CSV->new({ binary => 1, eol => "" });

    my $p_count = 0;

    # RDI first line is always the same
    $csv->combine("1", "1.8", "1.0.0.0", "ENHN", "");
    my @body = ($csv->string);

    # Let's just group all defects into a single inspection/sequence for now
    my $now = DateTime->now( time_zone => FixMyStreet->time_zone || FixMyStreet->local_time_zone );
    $csv->combine(
        "G", # start of an area/sequence
        int(rand(99999)), # area id
        "","", # must be empty
        "M T", # inspector initials
        $now->strftime("%y%m%d"), # date of inspection yymmdd
        $now->strftime("%H%M"), # time of inspection hhmm
        "D", # inspection variant, should always be D
        "INS", # inspection type, always INS
        "N", # Area of the county - north (N) or south (S)
        "", "", "", "" # empty fields
    );
    push @body, $csv->string;

    $csv->combine(
        "H", # initial inspection type
        "MC" # minor carriageway (changes depending on activity code)
    );
    push @body, $csv->string;

    my $problems = $c->cobrand->problems->search( {
        state => [ 'action scheduled' ],
    } );

    my $i = 1;
    while ( my $report = $problems->next ) {
        my ($eastings, $northings) = $report->local_coords;
        $csv->combine(
            "I", # beginning of defect record
            "MC", # activity code - minor carriageway, also FC (footway)
            "", # empty field, can also be A (seen on MC) or B (seen on FC)
            sprintf("%03d", $i++), # randomised sequence number
            "${eastings}E ${northings}N", # defect location field, which we don't capture from inspectors
            $report->lastupdate->strftime("%H%M"), # defect time raised
            "","","","","","","", # empty fields
            $report->get_extra_metadata('traffic_information') ? 'TM required' : 'TM none', # further description
            $report->get_extra_metadata('detailed_information'), # defect description
        );
        push @body, $csv->string;

        $csv->combine(
            "J", # georeferencing record
            $report->get_extra_metadata('defect_type') || 'SFP2', # defect type - SFP2: sweep and fill <1m2, POT2 also seen
            $report->response_priority ?
                $report->response_priority->external_id :
                "2", # priority of defect
            "","", # empty fields
            $eastings, # eastings
            $northings, # northings
            "","","","","" # empty fields
        );
        push @body, $csv->string;

        $csv->combine(
            "M", # bill of quantities record
            "resolve", # permanent repair
            "","", # empty fields
            "/CMC", # /C + activity code
            "", "" # empty fields
        );
        push @body, $csv->string;
    }

    # end this group of defects with a P record
    $csv->combine(
        "P", # end of area/sequence
        0, # always 0
        999999, # charging code, always 999999 in OCC
    );
    push @body, $csv->string;
    $p_count++;

    # end the RDI file with an X record
    my $record_count = $problems->count;
    $csv->combine(
        "X", # end of inspection record
        $p_count,
        $p_count,
        $record_count, # number of I records
        $record_count, # number of J records
        0, 0, 0, # always zero
        $record_count, # number of M records
        0, # always zero
        $p_count,
        0, 0, 0 # error counts, always zero
    );
    push @body, $csv->string;

    # $c->res->content_type('text/csv; charset=utf-8');
    $c->res->content_type('text/plain; charset=utf-8');
    # $c->res->header('content-disposition' => "attachment; filename=exor_defects.rdi");
    # The RDI format is very weird CSV - each line must be wrapped in
    # double quotes.
    $c->res->body( join "", map { "\"$_\"\r\n" } @body );
}

1;