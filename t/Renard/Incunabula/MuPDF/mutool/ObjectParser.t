#!/usr/bin/env perl

use Test::Most tests => 1;

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

done_testing;
