#!/usr/bin/perl

package VCE::Switch;

use strict;
use warnings;

use Data::Dumper;
use Moo;
use GRNOC::Log;
use GRNOC::RabbitMQ::Method;
use GRNOC::RabbitMQ::Dispatcher;
use GRNOC::WebService::Regex;

use VCE::Database::Connection;
use VCE::Device;
use VCE::Device::Brocade::MLXe::5_8_0;
use VCE::Device::JUNOS::MX::17;
use VCE::NetworkDB;

has logger => (is => 'rwp');
has id => (is => 'rwp');
has db => (is => 'rwp');
has device => (is => 'rwp');
has type => (is => 'rwp');
has vendor => (is => 'rwp');
has version => (is => 'rwp');
has username => (is => 'rwp');
has password => (is => 'rwp');
has port => (is => 'rwp');
has hostname => (is => 'rwp');
has dispatcher => (is => 'rwp');
has rabbit_mq => (is => 'rwp');
has op_state => (is => 'rwp');
has name => (is => 'rwp');

=head2 BUILD

=over 4

=item vce

=item logger

=item device

=item type

=item vendor

=item version

=item username

=item password

=item port

=item hostname

=item id

=item db

=item dispatcher

=item rabbit_mq

=item op_state

=item op_state

=item name

=back

=cut

sub BUILD {
    my ($self) = @_;

    my $logger = GRNOC::Log->get_logger("VCE::Switch");
    $self->_set_logger($logger);

    $0 = "VCE(" . $self->username . ")";

    $self->_set_db(VCE::Database::Connection->new('/var/lib/vce/database.sqlite'));

    $self->logger->info("Creating Dispatcher for " . $self->name);
    my $dispatcher = GRNOC::RabbitMQ::Dispatcher->new(
        host     => $self->rabbit_mq->{'host'},
        port     => $self->rabbit_mq->{'port'},
        user     => $self->rabbit_mq->{'user'},
        pass     => $self->rabbit_mq->{'pass'},
        exchange => 'VCE',
        queue    => 'VCE-Switch',
        topic    => 'VCE.Switch.' . $self->name
    );

    $self->_register_rpc_methods( $dispatcher );

    $self->_set_dispatcher($dispatcher);

    $self->logger->info("Connecting to device");

    $self->_connect_to_device();

    if(!defined($self->device)){
        $self->logger->error("Error connecting to device");
    }

    $SIG{'TERM'} = sub {
        $self->logger->info( "Received SIG TERM." );
        $self->stop();
    };

    $self->logger->debug("Creating timers");

    $self->{'operational_status_timer'} = AnyEvent->timer(after => 10, interval => 300, cb => sub { $self->_gather_operational_status() });

    $self->{'reconnect_timer'} = AnyEvent->timer(after => 10, interval => 10, cb => sub { $self->_reconnect_to_device() });

    $self->{interfaces} = {};
    return $self;
}

sub _reconnect_to_device{
    my $self = shift;

    if(defined($self->device) && $self->device->connected){
        $self->logger->debug("Already connected");
        return;
    }

    $self->logger->info("Attempt to connect");
    return $self->device->connect();
}

sub _connect_to_device{
    my $self = shift;

    $self->logger->debug("connecting to device");

    if($self->vendor eq 'Brocade'){
        if($self->type eq 'MLXe'){
            if($self->version eq '5.8.0'){
                my $dev = VCE::Device::Brocade::MLXe::5_8_0->new( username => $self->username,
                                                                  password => $self->password,
                                                                  hostname => $self->hostname,
                                                                  port => $self->port);

                $self->_set_device($dev);
                $dev->connect();
                if($dev->connected){
                    $self->logger->debug( "Successfully connected to device!" );
                    return 1;
                }else{
                    $self->logger->error( "Error connecting to device");
                    return;
                }
            }else{
                $self->logger->error( "No supported Brocade MLXe module for version " . $self->version );
                return;
            }
        }else{
            $self->logger->error( "No supported Brocade module for devices of type " . $self->type );
            return;
        }
    }elsif($self->vendor eq 'JUNOS'){
	if($self->type eq 'MX'){
	    if($self->version eq '17'){
		my $dev = VCE::Device::JUNOS::MX::17->new( username => $self->username,
							   password => $self->password,
							   hostname => $self->hostname,
							   port => $self->port);
		$self->_set_device($dev);
		$dev->connect();
		if($dev->connected){
		    $self->logger->debug( "Successfully connected to device!" );
                    return 1;
                }else{
                    $self->logger->error( "Error connecting to device");
                    return;
                }
	    }else{
		$self->logger->error("No supported JUNOS MX module for version " . $self->version );
		return;
	    }
	}else{
	    $self->logger->error("No supported JUNOS module for device of type " . $self->type );
	    return;
	}
    }else{
        $self->logger->error( "No supported vendor of type " . $self->vendor );
        return;
    }

}

sub _register_rpc_methods{
    my $self = shift;
    my $d = shift;

    my $method = GRNOC::RabbitMQ::Method->new(
        name => "get_interfaces",
        callback => sub { return $self->get_interfaces( @_ )  },
        description => "Get the device interfaces",
        async => 1
    );
    $method->add_input_parameter(
        name => "interface_name",
        description => "Name of the interface to gather data about",
        required => 0,
        multiple => 1,
        pattern => $GRNOC::WebService::Regex::NAME_ID
    );
    $d->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new(
        name => "get_vlans",
        callback => sub { return $self->get_vlans(@_) },
        description => "Get the device vlans",
        async => 1
    );
    $d->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new(
        name => "get_device_status",
        callback => sub { return $self->get_device_status( @_ )  },
        description => "Get the device status",
        async => 1
    );
    $d->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new(
        name => "execute_command",
        callback => sub { return $self->execute_command( @_ )  },
        description => "executes a command",
        async => 1
    );
    $method->add_input_parameter(
        name        => "command",
        description => "Actual command to run",
        required    => 1,
        pattern     => $GRNOC::WebService::Regex::TEXT
    );
    $method->add_input_parameter(
        name        => "context",
        description => "Any context for the command",
        required    => 0,
        pattern     => $GRNOC::WebService::Regex::TEXT
    );
    $method->add_input_parameter(
        name        => "cli_type",
        description => "Type of command to be run. Must be 'action' or 'show'.",
        required    => 0,
        pattern     => $GRNOC::WebService::Regex::TEXT
    );
    $method->add_input_parameter(
        name        => "config",
        description => "Does this command need to be done in commadn mode",
        required    => 1,
        default     => 0,
        pattern     => $GRNOC::WebService::Regex::BOOLEAN
    );
    $d->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new(
        name => "vlan_description",
        callback => sub { return $self->vlan_description( @_ )  },
        description => "Sets a vlan's description",
        async => 1
    );
    $method->add_input_parameter(
        name        => "description",
        description => "Description the vlan to add",
        required    => 1,
        pattern     => $GRNOC::WebService::Regex::TEXT
    );
    $method->add_input_parameter(
        name        => "vlan",
        description => "VLAN number to use for tag",
        required    => 1,
        pattern     => $GRNOC::WebService::Regex::INTEGER
    );
    $d->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new(
        name => "no_vlan",
        callback => sub { return $self->no_vlan(@_) },
        description => "Sets a vlan's description",
        async => 1
    );
    $method->add_input_parameter(
        name        => "vlan",
        description => "VLAN number to use for tag",
        required    => 1,
        pattern     => $GRNOC::WebService::Regex::INTEGER
    );
    $d->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new(
        name => "interface_tagged",
        callback => sub { return $self->interface_tagged( @_ )  },
        description => "Add vlan tagged interface",
        async => 1
    );
    $method->add_input_parameter(
        name        => "port",
        description => "Name of the interface to add tag to",
        required    => 1,
        multiple    => 1,
        pattern     => $GRNOC::WebService::Regex::TEXT
    );
    $method->add_input_parameter(
        name        => "vlan",
        description => "VLAN number to use for tag",
        required    => 1,
        pattern     => $GRNOC::WebService::Regex::INTEGER
    );
    $d->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new(
        name => "no_interface_tagged",
        callback => sub { return $self->no_interface_tagged( @_ )  },
        description => "Remove vlan tagged interface",
        async => 1
    );
    $method->add_input_parameter(
        name        => "port",
        description => "Name of the interface to remove tag from",
        required    => 0, # If required == 1, an empty array can't be passed.
        multiple    => 1,
        pattern     => $GRNOC::WebService::Regex::TEXT
    );
    $method->add_input_parameter(
        name        => "vlan",
        description => "VLAN number to use for tag",
        required    => 1,
        pattern     => $GRNOC::WebService::Regex::INTEGER
    );
    $d->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new(
        name => "vlan_spanning_tree",
        callback => sub { return $self->vlan_spanning_tree(@_)  },
        description => "Enable PVST on vlan",
        async => 1
    );
    $method->add_input_parameter(
        name        => "vlan",
        description => "VLAN to enable PVST on",
        required    => 1,
        pattern     => $GRNOC::WebService::Regex::INTEGER
    );
    $d->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new(
        name => "no_vlan_spanning_tree",
        callback => sub { return $self->no_vlan_spanning_tree(@_)  },
        description => "Disable PVST on vlan",
        async => 1
    );
    $method->add_input_parameter(
        name        => "vlan",
        description => "VLAN to disable PVST on",
        required    => 1,
        pattern     => $GRNOC::WebService::Regex::INTEGER
    );
    $d->register_method($method);

    $method = GRNOC::RabbitMQ::Method->new(
        name => "stop",
        callback => sub { $self->stop(); return; },
        description => "stop the child"
    );

    $d->register_method($method);

}


=head2 get_interfaces

=cut
sub get_interfaces{
    my $self   = shift;
    my $method = shift;
    my $params = shift;

    my $success = $method->{'success_callback'};
    my $error   = $method->{'error_callback'};

    if($self->device->connected){
        return &$success($self->device->get_interfaces());
    }else{
        $self->logger->error("Error device is not connected");
        return &$success({});
    }
}

=head2 get_vlans

get_vlans returns a hash of vlan objects describing this devices VLAN
configuration. This device's control and default VLANs are omitted
from the resulting hash. The mode of each port object will be 'TAGGED'
or 'UNTAGGED'.

Unlike get_interfaces, get_vlans has no associated _op method. All
requests for a device's VLAN configuration will be proxied through the
op_state variable.

=cut
sub get_vlans {
    my $self   = shift;
    my $method = shift;
    my $params = shift;

    my $success = $method->{'success_callback'};
    my $error   = $method->{'error_callback'};

    $self->logger->info("Calling get_vlans");

    if (!defined $self->op_state || !defined $self->op_state->{'vlans'}) {
        return &$error("VLAN opperational state has not yet been discovered.");
    }

    return &$success($self->op_state->{'vlans'});
}

=head2 vlan_description

=cut
sub vlan_description {
    my $self   = shift;
    my $method = shift;
    my $params = shift;

    my $success = $method->{'success_callback'};
    my $error   = $method->{'error_callback'};

    my $desc = $params->{'description'}{'value'};
    my $vlan = $params->{'vlan'}{'value'};

    $self->logger->info("Calling get_vlans");

    if (!$self->device->connected) {
        return &$error("Device is not connected.");
    }

    my ($res, $err) = $self->device->vlan_description($desc, $vlan);
    if (defined $err) {
        $self->logger->error($err);
        return &$error($err);
    }

    return &$success(1);
}


=head2 interface_tagged

    my $response = interface_tagged(
      port => ['ethernet 15/1', 'ethernet 15/2'],
      vlan => 300
    );

interface_tagged adds C<vlan> to the array of interfaces in C<port>.

Response

    { results => 1 }

or

    { error => "An error string" }

=cut
sub interface_tagged {
    my $self   = shift;
    my $method = shift;
    my $params = shift;

    my $success = $method->{'success_callback'};
    my $error   = $method->{'error_callback'};

    my $port = $params->{'port'}{'value'};
    my $vlan = $params->{'vlan'}{'value'};

    if (!$self->device->connected) {
        return &$error("Device is not connected.");
    }

    my ($res, $err) = $self->device->interface_tagged($port, $vlan);
    if (defined $err) {
        $self->logger->error($err);
        return &$error($err);
    }

    return &$success(1);
}

=head2 no_interface_tagged

    my $response = no_interface_tagged(
      port => ['ethernet 15/1', 'ethernet 15/2'],
      vlan => 300
    );

no_interface_tagged removes C<vlan> from the array of interfaces in
C<port>.

Response

    { results => 1 }

or

    { error => "An error string" }

=cut
sub no_interface_tagged {
    my $self   = shift;
    my $method = shift;
    my $params = shift;

    my $success = $method->{'success_callback'};
    my $error   = $method->{'error_callback'};

    my $port = $params->{'port'}{'value'} || [];
    my $vlan = $params->{'vlan'}{'value'};

    if (!$self->device->connected) {
        return &$error("Device is not connected.");
    }

    my ($res, $err) = $self->device->no_interface_tagged($port, $vlan);
    if (defined $err) {
        $self->logger->error($err);
        return &$error($err);
    }

    return &$success(1);
}

=head2 vlan_spanning_tree

Response

    { results => 1 }

or

    { error => "An error string" }

=cut
sub vlan_spanning_tree {
    my $self   = shift;
    my $method = shift;
    my $params = shift;

    my $success = $method->{'success_callback'};
    my $error   = $method->{'error_callback'};

    my $vlan = $params->{'vlan'}{'value'};

    $self->logger->info("Calling vlan_spanning_tree");

    if (!$self->device->connected) {
        return &$error("Device is not connected.");
    }

    my ($res, $err) = $self->device->vlan_spanning_tree($vlan);
    if (defined $err) {
        $self->logger->error($err);
        return &$error($err);
    }

    $self->logger->info("Returning from vlan_spanning_tree");
    return &$success(1);
}

=head2 no_vlan_spanning_tree

Response

    { results => 1 }

or

    { error => "An error string" }

=cut
sub no_vlan_spanning_tree {
    my $self   = shift;
    my $method = shift;
    my $params = shift;

    my $success = $method->{'success_callback'};
    my $error   = $method->{'error_callback'};

    my $vlan = $params->{'vlan'}{'value'};

    if (!$self->device->connected) {
        return &$error("Device is not connected.");
    }

    my ($res, $err) = $self->device->no_vlan_spanning_tree($vlan);
    if (defined $err) {
        $self->logger->error($err);
        return &$error($err);
    }

    return &$success(1);
}

=head2 no_vlan

=cut
sub no_vlan {
    my $self   = shift;
    my $method = shift;
    my $params = shift;

    my $success = $method->{'success_callback'};
    my $error   = $method->{'error_callback'};

    my $vlan = $params->{'vlan'}{'value'};

    if (!$self->device->connected) {
        return &$error("Device is not connected.");
    }

    my ($res, $err) = $self->device->no_vlan($vlan);
    if (defined $err) {
        $self->logger->error($err);
        return &$error($err);
    }

    return &$success(1);
}

=head2 get_device_status

=cut
sub get_device_status {
    my $self   = shift;
    my $method = shift;
    my $params = shift;

    my $success = $method->{'success_callback'};
    my $error   = $method->{'error_callback'};

    return &$success($self->device->connected);
}

=head2 _gather_operational_status

=cut
sub _gather_operational_status{
    my $self = shift;
    $self->logger->info('_gather_operational_status');

    if (!$self->device->connected) {
        $self->logger->error("Couldn't gather operational status. Device is disconnected.");
        return undef;
    }

    my $interfaces = $self->db->get_interfaces(switch_id => $self->id);

    my $ifaces = {};
    foreach my $intf (@{$interfaces}) {
        $ifaces->{$intf->{name}} = $intf;
    }

    my $interfaces_state = $self->device->get_interfaces();
    if (!defined $interfaces_state) {
        $self->logger->error("Couldn't gather interface data from device.");
        return undef;
    }

    $interfaces_state = $interfaces_state->{'interfaces'};
    if (!%{$interfaces_state}) {
        $self->logger->error("Got back zero interfaces from device; This is likely an error. Skipping diff for now.");
        return undef;
    }

    foreach my $name (keys %{$interfaces_state}) {
        if (defined $ifaces->{$name}) {
            $self->logger->info('Updating info on interface: ' . Dumper($interfaces_state->{$name}));
            $self->db->update_interface(
                id          => $ifaces->{$name}->{id},
                admin_up    => $interfaces_state->{$name}->{admin_status},
                link_up     => $interfaces_state->{$name}->{status},
                description => $interfaces_state->{$name}->{description},
                mtu         => $interfaces_state->{$name}->{mtu},
                speed       => $interfaces_state->{$name}->{speed}
            );
            delete $ifaces->{$name};
        } else {
            $self->logger->info('Creating interface');
            $self->db->add_interface(
                admin_up      => $interfaces_state->{$name}->{admin_status},
                description   => $interfaces_state->{$name}->{description},
                hardware_type => $interfaces_state->{$name}->{hardware_type},
                mac_addr      => $interfaces_state->{$name}->{mac_addr},
                mtu           => $interfaces_state->{$name}->{mtu},
                name          => $interfaces_state->{$name}->{name},
                speed         => $interfaces_state->{$name}->{speed},
                link_up       => $interfaces_state->{$name}->{status},
                switch_id     => $self->{id}
            );
        }
    }

    # Because ifaces doesn't contain new interfaces and interfaces
    # with updates are removed above, the only thing left are
    # interfaces which no longer exist on the device.
    foreach my $name (keys %{$ifaces}) {
        my $ok = $self->db->delete_interface($ifaces->{$name}->{id});
        if ($ok) {
            $self->logger->warn("Interface $name was removed from " . $self->name . "; Removing it from database.");
        }
    }


    $interfaces = $self->db->get_interfaces(switch_id => $self->id);
    $ifaces = {};
    foreach my $intf (@{$interfaces}) {
        $ifaces->{$intf->{name}} = $intf;
    }

    my $new_vlans = $self->db->get_vlans(switch_id => $self->id);

    my $vlans = {};
    foreach my $vlan (@{$new_vlans}) {
        $vlans->{$vlan->{number}} = $vlan;
    }

    my ($vlans_state, $err) = $self->device->get_vlans();
    if (defined $err) {
        $self->logger->error($err);
        return undef;
    }

    foreach my $vlan (@{$vlans_state}) {
        if (defined $vlans->{$vlan->{vlan}}) {
            $self->logger->info("Updating vlan $vlan->{vlan}!");
            $self->db->delete_tags($vlans->{$vlan->{vlan}}->{id});
        } else {
            $self->logger->info("Discovered vlan $vlan->{vlan}!");
            my $id = $self->db->add_vlan(
                created_by => 1, # admin user
                description => $vlan->{name},
                name => $vlan->{name},
                number => $vlan->{vlan},
                switch_id => $self->{id},
                workgroup_id => 1, # admin workgroup
            );
            if (!defined $id) {
                next;
            }
            $vlans->{$vlan->{vlan}} = { id => $id };
        }

        foreach my $port (@{$vlan->{ports}}) {
            my $mode = 'tagged';
            if ($port->{mode} ne 'TAGGED') {
                $mode = 'untagged';
            }
            my $int_id = $ifaces->{$port->{port}}->{id};
            my $vlan_id = $vlans->{$vlan->{vlan}}->{id};
            $self->db->add_tag($mode, $int_id, $vlan_id);
        }

        if (defined $vlans->{$vlan->{vlan}}) {
            delete $vlans->{$vlan->{vlan}};
        }
    }

    # Because vlans doesn't contain new vlans and vlans with updates
    # are removed above, the only thing left are vlans which no longer
    # exist on the device.
    foreach my $vlan (keys %{$vlans}) {
        my $ok = $self->db->delete_vlan($vlans->{$vlan}->{id});
        if ($ok) {
            $self->logger->warn("VLAN $vlan was removed from " . $self->name . "; Removing it from database.");
        }
    }
}

=head2 start

=cut
sub start{
    my $self = shift;

    if(!defined($self->dispatcher)){
        $self->logger->error("Dispatcher is not connected");
    }else{
        warn "Switch dispatcher is now consuming.";
        $self->dispatcher->start_consuming();
        return;
    }
}

=head2 stop

=cut
sub stop{
    my $self = shift;
    $self->logger->info("Stopping: " . $self->name);
    $self->dispatcher->stop_consuming();
}

=head2 execute_command

=cut
sub execute_command{
    my $self = shift;
    my $m_ref = shift;
    my $p_ref = shift;

    my $success = $m_ref->{'success_callback'};
    my $error   = $m_ref->{'error_callback'};

    if (!$self->device->connected) {
        return &$success({success => 0, error => 1, error_msg => 'Device is currently disconnected.'});
    }

    # We are now ready to send our command and get the results! The
    # regex prompt matches on the end of a line followed by text that
    # ends with a hash.
    my ($result, $err) = $self->device->issue_command($p_ref->{'command'}{'value'}, qr/\n.*\#$/);
    if (defined $err) {
        return &$success({success => 0, error => 1, error_msg => $err});
    }

    # TODO _gather_operational_status takes a while to complete which
    # holds up the response. Based on the provided information it
    # should be possible to limit what is queried from the switch to
    # increase response time. It would also be best to wrap this
    # request in an async method so the web user gets his response
    # immediately while the backend completes its query against the
    # device.
    if (defined $p_ref->{'cli_type'}{'value'} && $p_ref->{'cli_type'}{'value'} eq 'write') {
        $self->_gather_operational_status();
    }

    return &$success({success => 1, raw => $result});
}

1;
