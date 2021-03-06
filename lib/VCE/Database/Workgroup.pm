package VCE::Database::Workgroup;

use strict;
use warnings;
use Exporter;

our @ISA = qw( Exporter );
our @EXPORT = qw( add_workgroup get_workgroup get_workgroups get_workgroup_interfaces update_workgroup delete_workgroup );


=head2 add_workgroup


=cut
sub add_workgroup {
    my ( $self, $name, $description ) = @_;
    $self->{log}->debug("add_workgroup($name, $description)");

    eval {
        my $q = $self->{conn}->prepare(
            "insert into workgroup (name, description) values (?, ?)"
        );
        $q->execute($name, $description);
    };

    if ($@) {
        return (undef,"$@")
    }

    return ($self->{conn}->last_insert_id("", "", "workgroup", ""), undef);
}

=head2 get_workgroup


=cut
sub get_workgroup {
    my $self = shift;
    my %params = @_;

    my $reqs = [];
    my $args = [];
    my $where = '';

    if (defined $params{id}) {
        push @$reqs, 'id=?';
        push @$args, $params{id};
    }
    if (defined $params{name}) {
        push @$reqs, 'name=?';
        push @$args, $params{name};
    }
    $where .= join(' AND ', @$reqs);

    my $q = $self->{conn}->prepare(
        "select * from workgroup WHERE $where",
    );
    $q->execute(@$args);

    my $result = $q->fetchall_arrayref({})->[0];
    return $result;
}

=head2 get_workgroups


=cut
sub get_workgroups {
    my $self = shift;
    my %params = @_;

    $self->{log}->debug("get_workgroups()");

    my $keys = [];
    my $args = [];

    if (defined $params{name}) {
        push @$keys, 'name=?';
        push @$args, $params{name};
    }
    if (defined $params{workgroup_id}) {
        push @$keys, 'workgroup.id=?';
        push @$args, $params{workgroup_id};
    }
    if (defined $params{username}) {
        push @$keys, 'user.username=?';
        push @$args, $params{username};
    }

    my $values = join(' AND ', @$keys);
    my $where = scalar(@$keys) > 0 ? "WHERE $values" : "";

    my $q = $self->{conn}->prepare(
        "select workgroup.* from workgroup
         left join user_workgroup on user_workgroup.workgroup_id=workgroup.id
         left join user on user.id=user_workgroup.user_id
         $where
         group by workgroup.name"
    );
    $q->execute(@$args);

    my $result = $q->fetchall_arrayref({});
    return $result;
}

=head2 get_workgroup_interfaces

get_workgroup_interfaces returns a list of all interfaces that
C<workgroup_id> either owns or has access to. Interfaces may appear to
be duplicated if more than one vlan range has been made available to
C<workgroup_id>, although the high and low fields will be different.

=cut
sub get_workgroup_interfaces {
    my ( $self, $workgroup_id ) = @_;

    my $q = $self->{conn}->prepare(
        "select interface.*, switch.name as switch_name, acl.workgroup_id, acl.low, acl.high from workgroup
         join interface on workgroup.id=interface.workgroup_id
         join switch on interface.switch_id=switch.id
         join acl on interface.id=acl.interface_id
         where interface.workgroup_id=? OR acl.workgroup_id=?"
    );
    $q->execute($workgroup_id, $workgroup_id);

    my $result = $q->fetchall_arrayref({});
    return $result;
}

sub update_workgroup {
    my $self   = shift;
    my %params = @_;

    return if (!defined $params{id});

    $self->{log}->debug("modify_switch($params{id}, ...)");

    my $keys = [];
    my $args = [];

    if (defined $params{name}) {
        push @$keys, 'name=?';
        push @$args, $params{name};
    }
    if (defined $params{description}) {
        push @$keys, 'description=?';
        push @$args, $params{description};
    }

    my $values = join(', ', @$keys);
    push @$args, $params{id};

    my $q = $self->{conn}->prepare(
        "UPDATE workgroup SET $values WHERE id=?"
    );
    return $q->execute(@$args);
}

sub delete_workgroup {
    my $self   = shift;
    my %params = @_;

    return if (!defined $params{id});

    $self->{log}->debug("delete_workgroup($params{id}, ...)");

    my $keys = [];
    my $args = [];

    push @$args, $params{id};

    my $q = $self->{conn}->prepare(
        "DELETE FROM workgroup WHERE id=?"
    );
    return $q->execute(@$args);
}

return 1;
