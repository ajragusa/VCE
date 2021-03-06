package VCE::Database::ACL;

use strict;
use warnings;
use Exporter;
# use Data::Dumper;
our @ISA = qw( Exporter );
our @EXPORT = qw( add_acl get_acls modify_acl delete_acl);


=head2 add_acl
=cut
sub add_acl {
    my ( $self, $workgroup_id, $interface_id, $low, $high ) = @_;

    $self->{log}->debug("add_acl($workgroup_id, $interface_id, $low, $high)");

    eval {
        my $q = $self->{conn}->prepare(
            "insert into acl
            (interface_id, workgroup_id, low, high)
            values (?, ?, ?, ?)"
        );
        $q->execute($interface_id, $workgroup_id, $low, $high);

    };


    if ($@) {
        return (undef,"$@");
    }

    my $id = $self->{conn}->last_insert_id("", "", "acl", "");
    return ($id, undef);

    # return $self->{conn}->last_insert_id("", "", "interface_workgroup_acl", "");
}

=head2 get_acls
=cut
sub get_acls {
    my ( $self, $workgroup_id, $interface_id ) = @_;

    $self->{log}->debug("get_acls($self->{conn}, $workgroup_id, $interface_id)");

    my $q = $self->{conn}->prepare(
        "select * from acl
        where acl.workgroup_id=? and acl.interface_id=?"
    );
    $q->execute($workgroup_id, $interface_id);

    my $acls = $q->fetchall_arrayref({});
    my $result = [];

    foreach my $acl (@$acls) {
        push @$result, { high => $acl->{high}, low  => $acl->{low} };
    }

    return $result;
}

=head2 modify_acl


=cut
sub modify_acl {
    my $self   = shift;
    my %params = @_;
    return if (!defined $params{id});

    $self->{log}->debug("modify_acl($params{id}, ...)");

    my $keys = [];
    my $args = [];

    if (defined $params{low}) {
        push @$keys, 'low=?';
        push @$args, $params{low};
    }
    if (defined $params{high}) {
        push @$keys, 'high=?';
        push @$args, $params{high};
    }

    my $values = join(', ', @$keys);
    push @$args, $params{id};
    my $result;
    eval {
        my $q = $self->{conn}->prepare(
            "UPDATE acl SET $values WHERE id=?"
        );

        $result = $q->execute(@$args);
    };
    if ($@) {
        $self->{log}->error("$@");
        return 0;
    }
    return $result;
}

=head2 delete_acl

=cut
sub delete_acl {
    my $self = shift;
    my $acl_id = shift;

    $self->{log}->debug("Calling delete_acl");

    if (!defined $acl_id) {
        $self->{log}->error("No acl id specified");
        return;
    }


    my $result;
    eval {
        my $query = $self->{conn}->prepare(
            'DELETE FROM acl WHERE id=?'
        );
       $result = $query->execute($acl_id);
    };
    if ($@) {
        $self->{log}->error("$@");
        return 0;
    }

    return $result;
}
return 1;
