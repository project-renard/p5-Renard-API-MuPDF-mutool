#!/usr/bin/env perl

use Test::Most tests => 2;

use Renard::Incunabula::Common::Setup;
use Renard::Incunabula::MuPDF::mutool::ObjectParser;

subtest "Unsecape" => sub {
	my @tests = (
		{ input => q(\0053), output => "\005" ."3" },
		{ input => q(\053), output => "+" },
		{ input => q(\53), output => "+" },
	);

	plan tests => 0+@tests;

	for my $test (@tests) {
		is(
			Renard::Incunabula::MuPDF::mutool::ObjectParser->unescape( $test->{input} ),
			$test->{output},
			"unescape @{[ $test->{input} ]}"
		);
	}
};

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
			Renard::Incunabula::MuPDF::mutool::ObjectParser->parse_date( $test->{input} ),
			$test->{output},
			'correct date'
		);
	}
};

done_testing;
