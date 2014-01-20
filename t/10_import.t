use strict;
use Test::More;
use Catmandu::Importer::getJSON;

sub test_importer(@) { ##no critic
    my ($url, $requests, $content, $expect, $msg) = @_;

    my $importer = Catmandu::Importer::getJSON->new(
        file => \ do { join "\n", map { $_->[0] } @$requests },
        client => MockFurl::new( content => $content ),
    );
    $importer->url($url) if defined $url;
    
    $expect = [ map { $expect } @$requests ] if ref $expect ne 'ARRAY';
    is_deeply $importer->to_array, $expect, $msg;
    is_deeply $importer->client->urls, [ map { $_->[1] } @$requests ]; 
}

my @requests = (
    [ '{ } ' => 'http://example.org/' ],
    [ '{"q":"&"}' => 'http://example.org/?q=%26' ],
    [ '/path?q=%20 ' => 'http://example.org/path?q=%20' ],
);

test_importer 'http://example.org/', \@requests, 
    '{"x":"\u2603"}' => {x=>"\x{2603}"},
    'URI';

test_importer
    'http://example.{tdl}/{?foo}{?bar}',
    [ 
        [ 'http://example.org' => 'http://example.org' ],
        [ '{"tdl":"com"}' => 'http://example.com/' ],
        [ '{"tdl":"com","bar":"doz"}' => 'http://example.com/?bar=doz' ],
    ],
    '{}' => { },
    'URI::Template';

test_importer undef, 
    [ ["http://example.info" => "http://example.info" ] ],
    '[{"n":1},{"n":2}]' => [{"n"=>1},{"n"=>2}],
    'JSON array response';

done_testing;

package MockFurl;
sub new { bless { @_ }, 'MockFurl' }
sub decoded_content { $_[0]->{content} }
sub urls { $_[0]->{urls} // [] } 
sub get { push @{$_[0]->{urls}}, $_[1]; $_[0] }
sub is_success { 1 }

1;
