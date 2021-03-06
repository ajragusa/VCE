#!/usr/bin/perl

package VCE::NetworkDB;

use strict;
use warnings;

use Moo;
use GRNOC::Log;

use Data::Dumper;
use Data::UUID;
use DBI;
use VCE::Database::Connection;

has db     => (is => 'rwp');
has db2    => (is => 'rwp');
has logger => (is => 'rwp');
has path   => (is => 'rwp', default => '/var/lib/vce/network_model.sqlite' );
has uuid   => (is => 'rwp');

=head2 BUILD

creates a new NetworkModel object

=over 4

=item db

=item db2

=item logger

=item path

=item uuid

=back

=cut

sub BUILD{
    my ($self) = @_;

    my $logger = GRNOC::Log->get_logger("VCE::NetworkDB");
    $self->_set_logger($logger);

    $self->_set_uuid( Data::UUID->new() );
    my $path = $self->path;
    $self->logger->info("Loading database from: $path");
    $self->_set_db(DBI->connect("dbi:SQLite:dbname=$path", undef, undef, {
        AutoCommit => 1,
        RaiseError => 1,
        sqlite_see_if_its_a_number => 1
    }));
    $self->_set_db2(VCE::Database::Connection->new($path));

    my $query = undef;
    $query = $self->db->prepare(
    'CREATE TABLE IF NOT EXISTS network(
      id          INTEGER PRIMARY KEY,
      created     INTEGER,
      description TEXT,
      number      INTEGER,
      switch      TEXT,
      username    TEXT,
      uuid        TEXT,
      workgroup   TEXT,
      CONSTRAINT constraint_number UNIQUE (switch, number),
      CONSTRAINT constraint_uuid   UNIQUE (uuid)
    )'
    );
    $query->execute();

    $query = $self->db->prepare(
    'CREATE TABLE IF NOT EXISTS interface(
      id            INTEGER PRIMARY KEY,
      admin_status  INTEGER,
      description   TEXT,
      hardware_type TEXT,
      mac_addr      TEXT,
      mtu           TEXT,
      name          TEXT,
      speed         TEXT,
      status        INTEGER,
      switch        TEXT
    )'
    );
    $query->execute();

    $query = $self->db->prepare(
    'CREATE TABLE IF NOT EXISTS vlan(
      id         INTEGER PRIMARY KEY,
      interface  TEXT,
      mode       TEXT,
      network_id INTEGER
    )'
    );
    $query->execute();

    return $self;
}

=head2 add_interface

    my $id = add_interface(
      'admin_status' => 0,
      'description' => '',
      'hardware_type' => '100GigabitEthernet',
      'mac_addr' => 'cc4e.240c.0cc1',
      'mtu' => '9216'
      'name' => 'ethernet 5/2',
      'speed' => 'unknown',
      'status' => 0,
      'switch' => 'mlxe16-2.sdn-test.grnoc.iu.edu'
    );

=cut
sub add_interface {
    my $self = shift;
    my %params = @_;
    $self->logger->debug('Calling add_interface');

    return if(!defined($params{admin_status}));
    return if(!defined($params{description}));
    return if(!defined($params{name}));
    return if(!defined($params{status}));
    return if(!defined($params{switch}));

    my $query = undef;
    eval {
        $query = $self->db->prepare(
            'INSERT INTO interface (admin_status, description, hardware_type, mac_addr, mtu, name, speed, status, switch)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)'
        );
        $query->execute(
            $params{admin_status},
            $params{description},
            $params{hardware_type},
            $params{mac_addr},
            $params{mtu},
            $params{name},
            $params{speed},
            $params{status},
            $params{switch}
        );
    };
    if ($@) {
        $self->logger->error("$@");
        return undef;
    }

    $self->logger->debug('Called add_interface');
    return $self->db->sqlite_last_insert_rowid();
}

=head2 delete_interface

    my $ok = delete_interface(id => 1);

delete_interface removes interface C<$id> from the network model and
any VLANs it was previously associated with.

=cut
sub delete_interface{
    my $self = shift;
    my %params = @_;
    $self->logger->debug("Calling delete_interface");

    if (!defined $params{id}) {
        $self->logger->error("No interface id specified");
        return;
    }

    my $query = undef;
    eval {
        $query = $self->db->prepare(
            'SELECT * FROM interface WHERE id=?'
        );
        $query->execute($params{id});
    };
    if ($@) {
        $self->logger->error("$@");
        return;
    }
    my $interface = $query->fetchall_arrayref({});
    if (@{$interface} == 0) {
        $self->logger->error("Couldn't find interface " . $params{id});
        return;
    }

    eval {
        $query = $self->db->prepare(
            'DELETE FROM interface WHERE id=?'
        );
        $query->execute($interface->[0]->{id});
    };
    if ($@) {
        $self->logger->error("$@");
        return;
    }

    $self->logger->debug("Called delete_interface");
    return 1;
}

=head2 update_interface

    my $ok = update_interface(
      id            => 1,
      admin_status  => 0,
      description   => 'new',
      mtu           => '1500',
      speed         => '100Gbit',
      status        => 1
    );

=cut
sub update_interface {
    my $self = shift;
    my %params = @_;
    $self->logger->debug('Calling update_interface');

    return if (!defined $params{id});

    my $reqs = [];
    my $args = [];
    my $set = '';

    if (defined $params{admin_status}) {
        push(@{$reqs}, 'admin_status=?');
        push(@{$args}, $params{admin_status});
    }
    if (defined $params{description}) {
        push(@{$reqs}, 'description=?');
        push(@{$args}, $params{description});
    }
    if (defined $params{mtu}) {
        push(@{$reqs}, 'mtu=?');
        push(@{$args}, $params{mtu});
    }
    if (defined $params{speed}) {
        push(@{$reqs}, 'speed=?');
        push(@{$args}, $params{speed});
    }
    if (defined $params{status}) {
        push(@{$reqs}, 'status=?');
        push(@{$args}, $params{status});
    }
    $set .= join(', ', @{$reqs});
    push(@{$args}, $params{id});

    my $query = undef;
    eval {
        $query = $self->db->prepare(
            'UPDATE interface SET ' .
            $set .
            'WHERE id=?'
        );
        $query->execute(@{$args});
    };
    if ($@) {
        $self->logger->error("$@");
        return;
    }

    $self->logger->debug('Called update_interface');
    return 1;
}

=head2 get_interfaces

get_interfaces

=cut
sub get_interfaces {
    my $self = shift;
    my %params = @_;

    my $sw = $self->db2->get_switches(name => $params{switch})->[0];
    if (!defined $sw) {
        return;
    }

    my $wg = $self->db2->get_workgroups(name => $params{workgroup})->[0];
    if (!defined $wg) {
        return;
    }

    my $interfaces = $self->db2->get_interfaces(
        workgroup_id => $wg->{id},
        switch_id => $sw->{id}
    );
    return $interfaces;
}

=head2 add_vlan

    my $uuid = add_vlan(
      description => 'Example',
      endpoints   => [
        'ethernet 1/1',
        'ethernet 1/2'
      ],
      switch      => 'switch-demo.org',
      username    => 'admin',
      vlan        => 300,
      workgroup   => 'admin'
    );

add_vlan creates adds a vlan to the network model creates an
associated uuid ID for it.

returns the uuid for the vlan

=cut
sub add_vlan {
    my $self = shift;
    my %params = @_;
    $self->logger->info("Calling add_vlan");

    return if(!defined($params{description}));
    return if(!defined($params{endpoints}));
    return if(!defined($params{switch}));
    return if(!defined($params{username}));
    return if(!defined($params{vlan}));
    return if(!defined($params{workgroup}));

    my $switch = $self->db2->get_switches(name => $params{switch})->[0];
    if (!defined $switch) {
        return { vlan_id => undef, error => "Couldn't add VLAN to specified switch." };
    }
    my $workgroup = $self->db2->get_workgroups(name => $params{workgroup})->[0];
    if (!defined $workgroup) {
        return { vlan_id => undef, error => "Couldn't find specified workgroup." };
    }
    my $user = $self->db2->get_user_by_name($params{username});
    if (!defined $user) {
        return { vlan_id => undef, error => "Couldn't find specified user." };
    }

    my $nvlan_id = $self->db2->add_vlan(
        name => $params{description},
        description => $params{description},
        number => $params{vlan},
        created_by => $user->{id},
        switch_id => $switch->{id},
        workgroup_id => $workgroup->{id},
        created_on => time
    );
    if (!defined $nvlan_id) {
        return {vlan_id => undef, error => "Unable to add VLAN to the database. Please verify the VLAN does't already exist."};
    }

    foreach my $endpoint (@{$params{endpoints}}) {
        my $interface = $endpoint->{port};
        my $intf = $self->db2->get_interfaces(name => $interface)->[0];
        if (!defined $intf) {
            next;
        }
        $self->db2->add_tag('tagged', $intf->{id}, $nvlan_id);
    }

    $self->logger->debug("Called add_vlan");
    return {vlan_id => $nvlan_id, error => undef};
}

=head2 delete_vlan

    my $ok = delete_vlan(
      vlan_id => $string
    );

delete_vlan removes vlan C<$vlan_id> from the network model.

=cut
sub delete_vlan{
    my $self = shift;
    my %params = @_;
    $self->logger->info("Calling delete_vlan");

    if (!defined $params{vlan_id}) {
        $self->logger->error("No vlan_id specified");
        return;
    }

    my $ok = $self->db2->delete_vlan($params{vlan_id});
    return $ok;
}

=head2 get_vlans

    my $vlans = get_vlans(
      workgroup => $string, (optional)
      switch    => $string  (optional)
    );

get_vlans returns a list of vlan UUIDs filtered by C<workgroup> and
C<switch>.

=cut
sub get_vlans{
    my $self = shift;
    my %params = @_;

    my $args = [];
    my $reqs = [];
    my $where = '';

    my $switch_id;
    if (defined $params{switch}) {
        $switch_id = $self->db2->get_switches(name => $params{switch})->[0]->{id};
        return [] if (!defined $switch_id);
    }
    my $workgroup_id;
    if (defined $params{workgroup}) {
        $workgroup_id = $self->db2->get_workgroups(name => $params{workgroup})->[0]->{id};
        return [] if (!defined $workgroup_id);
    }

    my $networks = $self->db2->get_vlans(
        switch_id => $switch_id,
        workgroup_id => $workgroup_id
    );

    my $result = [];
    foreach my $network (@{$networks}) {
        push(@{$result}, $network->{id});
    }

    return $result;
}

=head2 get_vlans_state

    my $vlans = get_vlans_state(
      workgroup => $string, (optional)
      switch    => $string  (optional)
    );

get_vlans returns a list of vlan objects filtered by C<workgroup> and
C<switch>.

=cut
sub get_vlans_state {
    my $self = shift;
    my %params = @_;

    my $args = [];
    my $reqs = [];
    my $where = '';

    # TODO - Cleanup this garbage for optional filters
    if (defined $params{workgroup} || defined $params{switch}) {
        $where .= 'WHERE ';
        if (defined $params{workgroup}) {
            push(@{$reqs}, 'network.workgroup=?');
            push(@{$args}, $params{workgroup});
        }
        if (defined $params{switch}) {
            push(@{$reqs}, 'network.switch=?');
            push(@{$args}, $params{switch});
        }
        $where .= join(' AND ', @{$reqs});
    }

    my $query = undef;
    eval {
        $query = $self->db->prepare(
            'SELECT * FROM network
             LEFT JOIN vlan on network.id=vlan.network_id ' .
             $where .
            'ORDER BY network.number ASC'
        );
        $query->execute(@{$args});
    };
    if ($@) {
        $self->logger->error("$@");
        return undef;
    }
    my $endpoints = $query->fetchall_arrayref({});
    my $vlans = [];
    my $vlan  = {};

    foreach my $endpoint (@{$endpoints}) {
        if ($endpoint->{uuid} ne $vlan->{vlan_id}) {
            if (%{$vlan}) {
                push(@{$vlans}, $vlan);
            }

            $vlan = {
                create_time => $endpoint->{created},
                description => $endpoint->{description},
                endpoints   => [],
                status      => 'Active',
                switch      => $endpoint->{switch},
                username    => $endpoint->{username},
                vlan        => $endpoint->{number},
                vlan_id     => $endpoint->{uuid},
                workgroup   => $endpoint->{workgroup}
            };
        }

        if (!defined $endpoint->{interface}) {
            next;
        }
        my $info = {
            port => $endpoint->{interface}
        };
        push(@{$vlan->{endpoints}}, $info);
    }

    if (%{$vlan}) {
        push(@{$vlans}, $vlan);
    }
    return $vlans;
}


=head2 get_vlan_details

    my $vlan = get_vlan_details(
      vlan_id => $string
    );

get_vlan_details returns the VLAN associated with UUID C<$vlan_id>.

=cut
sub get_vlan_details{
    my $self = shift;
    my %params = @_;

    if (!defined $params{vlan_id}) {
        $self->logger->error("No VLAN ID specified");
        return;
    }

    my $vlan = $self->db2->get_vlan($params{vlan_id});
    if (!defined $vlan) {
        $self->logger->error("No VLAN found");
        return;
    }

    my $workgroup = $self->db2->get_workgroup(id => $vlan->{workgroup_id});
    my $user = $self->db2->get_user($vlan->{created_by});
    my $switch = $self->db2->get_switch($vlan->{switch_id});
    my $endpoints = $self->db2->get_tags(vlan_id => $vlan->{id});

    my $result = {
        create_time => $vlan->{created_on},
        description => $vlan->{description},
        endpoints   => [],
        status      => 'Active',
        switch      => $switch->{name},
        username    => $user->{username},
        vlan        => $vlan->{number},
        vlan_id     => $vlan->{id},
        workgroup   => $workgroup->{name}
    };
    foreach my $endpoint (@{$endpoints}) {
        if (!defined $endpoint->{name}) {
            next;
        }
        my $info = {
            port => $endpoint->{name}
        };
        push(@{$result->{endpoints}}, $info);
    }

    return $result;
}

=head2 get_vlan_details_by_number

    my $vlan = get_vlan_details_by_number(
      number => 300
    );

get_vlan_details_by_number returns the VLAN associated with VLAN
number C<$number>.

=cut
sub get_vlan_details_by_number {
    my $self = shift;
    my %params = @_;
    $self->logger->info("Calling get_vlan_details_by_number");

    if (!defined $params{number}) {
        $self->logger->error("No VLAN ID specified");
        return undef;
    }
    if (!defined $params{switch}) {
        $self->logger->error("No VLAN ID specified");
        return undef;
    }

    my $switch = $self->db2->get_switches(name => $params{switch})->[0];
    if (!defined $switch) {
        return 0;
    }

    my $vlan = $self->db2->get_vlans(
        switch_id => $switch->{id},
        number => $params{number}
    )->[0];
    return $vlan;
}

=head2 set_vlan_endpoints

=cut
sub set_vlan_endpoints {
    my $self = shift;
    my %params = @_;
    $self->logger->info("Calling set_vlan_endpoints");

    if (!defined $params{vlan_id}) {
        $self->logger->error("No vlan_id specified");
        return undef;
    }

    my $query = undef;
    eval {
        $query = $self->db->prepare(
            'SELECT * FROM network WHERE uuid=?'
        );
        $query->execute($params{vlan_id});
    };
    if ($@) {
        $self->logger->error("$@");
        return undef;
    }
    my $network = $query->fetchall_arrayref({});
    if (@{$network} == 0) {
        $self->logger->error("Couldn't find VLAN " . $params{'vlan_id'});
        return undef;
    }
    my $network_id = $network->[0]->{id};
    my $network_uuid = $network->[0]->{uuid};

    eval {
        $query = $self->db->prepare(
            'DELETE FROM vlan WHERE network_id=?'
        );
        $query->execute($network_id);
    };
    if ($@) {
        $self->logger->error("$@");
        return undef;
    }

    foreach my $endpoint (@{$params{endpoints}}) {
        my $interface = $endpoint->{port};

        eval {
            $query = $self->db->prepare(
                'INSERT INTO vlan (interface, mode, network_id) VALUES (?, ?, ?)'
            );
            $query->execute($interface, 'TAGGED', $network_id);
        };
        if ($@) {
            $self->logger->error("$@");
        }
    }

    $self->logger->debug("Called set_vlan_endpoints");
    return $self->get_vlan_details(vlan_id => $network_uuid);
}

=head2 check_tag_availability

this looks only at the network model to verify
that this vlan is not used in VCE

it does not verify that the user/workgroup has access
or that the vlan isn't already configured on the given
port

=cut
sub check_tag_availability {
    my $self = shift;
    my %params = @_;
    $self->logger->info("Calling check_tag_availability");

    if (!defined $params{'vlan'}) {
        $self->logger->error("check_tag_availability: vlan not defined");
        return;
    }

    if (!defined $params{'switch'}) {
        $self->logger->error("check_tag_availability: switch not defined");
        return;
    }

    my $vlan = $self->get_vlan_details_by_number(
        switch => $params{switch},
        number => $params{vlan}
    );
    if (defined $vlan) {
        return 0;
    }

    return 1;
}

1;
