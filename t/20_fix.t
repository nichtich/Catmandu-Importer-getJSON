use strict;
use Test::More;

my $pkg;
BEGIN {
    $pkg = 'Catmandu::Fix::get_json';
    use_ok $pkg;
}

is_deeply $pkg->new("http://example.com/json", dry => 1)->fix({}),
	{url => "http://example.com/json"};

is_deeply $pkg->new("http://example.com/json", dry => 1)->fix({foo => "bar"}),
	{url => "http://example.com/json"};

is_deeply $pkg->new("http://example.com/json", path => "tmp.test", dry => 1)->fix({foo => "bar"}),
	{foo => "bar", tmp => {test => {url => "http://example.com/json"}}};

done_testing;
