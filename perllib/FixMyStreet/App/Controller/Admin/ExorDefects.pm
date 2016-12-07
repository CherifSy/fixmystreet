package FixMyStreet::App::Controller::Admin::ExorDefects;
use Moose;
use namespace::autoclean;

use Text::CSV;

BEGIN { extends 'Catalyst::Controller'; }


sub begin : Private {
    my ( $self, $c ) = @_;

    $c->forward('/admin/begin');
}

sub index : Path : Args(0) {
    my ( $self, $c ) = @_;

    my $csv = Text::CSV->new({ binary => 1, eol => "" });

    my ($p_count, $i_count, $j_count, $m_count) = (0, 0, 0, 0);

    # RDI first line is always the same
    $csv->combine("1", "1.8", "1.0.0.0", "ENHN", "");
    my @body = ($csv->string);

    # Let's just group all defects into a single inspection/sequence for now
    $csv->combine(
        "G", # start of an area/sequence
        "35164", # randomised sequence number
        "","", # must be empty
        "M T", # inspector initials
        "161111", # date of inspection yymmdd
        "1459", # time of inspection hhmm
        "D", # inspection variant, should always be D
        "INS", # inspection type, always INS
        "N", # Area of the county - north (N) or south (S)
        "", "", "", "" # empty fields
    );
    push @body, $csv->string;

    $csv->combine(
        "H", # initial inspection type
        "MC", # minor carriageway (changes depending on activity code)
        "FC" # footway - seems optional if reports in this batch don't include FC activity code
    );
    push @body, $csv->string;

    my $problems = $c->model('DB::Problem')->search( { extra => { like => '%inspected,I1:1%' } } );

    while ( my $report = $problems->next ) {
        $csv->combine(
            "I", # beginning of defect record
            "MC", # activity code - minor carriageway, also FC (footway)
            "", # empty field, can also be A (seen on MC) or B (seen on FC)
            "46", # randomised sequence number
            "betw 21-23 cotswold cres-chipping norton", # defect location field
            "1459", # defect time raised
            "","","","","","","", # empty fields
            "m.t -TM none, fill in 300 x 300 x 50 (2 of 3)", # defect description
            "pothole in white ", # further description
        );
        push @body, $csv->string;
        $i_count++;

        $csv->combine(
            "J", # georeferencing record
            "POT2", # defect type - SFP2: sweep and fill <1m2, POT2 also seen
            "2", # priority of defect
            "","", # empty fields
            "431448.472269547", # eastings
            "226370.94024575", # northings
            "","","","","" # empty fields
        );
        push @body, $csv->string;
        $j_count++;

        $csv->combine(
            "M", # bill of quantities record
            "resolve", # permanent repair
            "","", # empty fields
            "/CMC", # /C + activity code
            "", "" # empty fields
        );
        push @body, $csv->string;
        $m_count++;
    }

    # end this group of defects with a P record
    $csv->combine(
        "P", # end of area/sequence
        "0", # always 0
        "999999", # charging code, always 999999 in OCC
    );
    push @body, $csv->string;
    $p_count++;

    # end the RDI file with an X record
    $csv->combine(
        "X", # end of inspection record
        "$p_count",
        "$p_count",
        "$i_count",
        "$j_count",
        "0", "0", "0", # always zero
        "$m_count",
        "0", # always zero
        "$p_count",
        "0", "0", "0" # error counts, always zero
    );
    push @body, $csv->string;

    # $c->res->content_type('text/csv; charset=utf-8');
    $c->res->content_type('text/plain; charset=utf-8');
    # $c->res->header('content-disposition' => "attachment; filename=rdioutput.csv");
    # The RDI format is very weird CSV - each line must be wrapped in
    # double quotes.
    $c->res->body( join "", map { "\"$_\"\r\n" } @body );
}

1;