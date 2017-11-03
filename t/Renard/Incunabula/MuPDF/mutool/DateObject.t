#!/usr/bin/env perl

use Test::Most tests => 1;

use Renard::Incunabula::Common::Setup;
use Renard::Incunabula::MuPDF::mutool::DateObject;

subtest "Date parsing" => sub {
	my @tests = (
		{
			input => "D:20061118211043-02'30'",
			output => {
				year => '2006', month => '11', day => '18',
				hour => '21', minute => '10', second => '43',
				tz => {
					offset => '-',
					hour => '02', minute => '30',
				}
			}
		}

	);


	plan tests => 0+@tests;

	for my $test (@tests) {
		is_deeply(
			Renard::Incunabula::MuPDF::mutool::DateObject->new(
				string => $test->{input}
			)->data,
			$test->{output},
			'correct date'
		);
	}
};

done_testing;
