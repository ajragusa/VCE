#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 9;
use Test::Deep;

use VCE;

use GRNOC::Log;

`cp t/etc/nm1.sqlite.orig2 t/etc/nm1.sqlite`;

my $logger = GRNOC::Log->new( level => 'ERROR');

my $vce = VCE->new( config_file => './t/etc/test_config.xml',
                    db => 't/etc/nm1.sqlite',
                    network_model_file => "t/etc/nm1.sqlite");

ok(defined($vce), "VCE object created");

my $user_in_workgroup = $vce->access->user_in_workgroup( username => 'aragusa',
							 workgroup => 'ajco');

ok($user_in_workgroup, "AJ is in aj-co");

$user_in_workgroup = $vce->access->user_in_workgroup( username => 'aragusa',
						      workgroup => 'edco');

ok(!$user_in_workgroup, "AJ is not in ed-co");

$user_in_workgroup = $vce->access->user_in_workgroup( username => 'foo',
                                                      workgroup => 'ajco');

ok(!$user_in_workgroup, "User foo does not exist");

$user_in_workgroup = $vce->access->user_in_workgroup( username => 'aragusa',
                                                      workgroup => 'doesnt_exist');

ok(!$user_in_workgroup, "workgroup doesn't exist");


$user_in_workgroup = $vce->access->user_in_workgroup( username => 'ebalas',
                                                      workgroup => 'admin');

ok($user_in_workgroup, "Ed is in admin");

$user_in_workgroup = $vce->access->user_in_workgroup( username => 'ebalas',
                                                      workgroup => 'edco');

ok($user_in_workgroup, "Ed is also in edco");

$user_in_workgroup = $vce->access->user_in_workgroup( username => 'ebalas');

ok(!$user_in_workgroup, "Proper result when workgroup not specified");

$user_in_workgroup = $vce->access->user_in_workgroup( workgroup => 'edco');

ok(!$user_in_workgroup, "Proper result when user not specified");
