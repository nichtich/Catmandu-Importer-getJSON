use strict;
use Test::More;
use lib 't';
use MockFurl;
use File::Temp;
use Digest::MD5 qw(md5_hex);

use Catmandu::Importer::getJSON;

my $dir = File::Temp::tempdir(CLEANUP=>1);
my $counter = 0;
my %args = (
    client => MockFurl::new( 
        content => sub { '{"c":'.$counter++.'}' } 
    ),
    file => \"http://example.org\nhttp://example.com\nhttp://example.org",
);

my $importer = Catmandu::Importer::getJSON->new(%args);
is_deeply $importer->to_array, [{c=>0},{c=>1},{c=>2}], 'cache off'; 

$importer = Catmandu::Importer::getJSON->new(%args, cache => 1);
is_deeply $importer->to_array, [{c=>3},{c=>4},{c=>3}], 'in-memory cache'; 

$importer = Catmandu::Importer::getJSON->new(%args, cache => $dir);
is_deeply $importer->to_array, [{c=>5},{c=>6},{c=>5}], 'file cache';

my $file = $dir.'/'.md5_hex("http://example.org").'.json';
my $json = do { local (@ARGV,$/) = $file; <> };
is $json, <<JSON, 'cache file';
{
   "c" : 5
}
JSON

done_testing;
