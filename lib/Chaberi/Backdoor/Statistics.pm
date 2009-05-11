package Chaberi::Backdoor::Statistics;
use MooseX::POE;
use Chaberi::Backdoor::Schema;

our $MARGINE = 20 * 60;  # 範囲が連続していると見なす幅


has cont => (
	isa      => 'ArrayRef',
	is       => 'ro',
	required => 1,
);


has page => (
	isa      => 'HashRef',
	is       => 'ro',
	required => 1,
);


has schema => (
	isa     => 'Chaberi::Backdoor::Schema',
	is      => 'ro',
	default => sub { Chaberi::Backdoor::Schema->default_schema },
);


has now_epoch => (
	isa     => 'Int',
	is      => 'ro',
	default => sub { scalar time },
);


# subroutine =====================================
sub _calc_range{
	my $self = shift;
	my ($room, $nick) = @_;

	my $rs = $self->schema->resultset('EnterRange');

	my $cur_epoch = $rs->search(
		{
			room_id  => $room->id,
			nick_id  => $nick->id,
		}, 
	)->get_column('epoch2')->max;
	if ( $cur_epoch and $self->now_epoch - $cur_epoch < $MARGINE ) {
		# 前回の範囲を拡張する
		my $range = $rs->search(
			{
				room_id	 => $room->id,
				nick_id	 => $nick->id,
				epoch2	 => $cur_epoch,
			}, 
		)->first;
		$range->epoch2($self->now_epoch);
		$range->update;
		return $range;
	} else {
		# 新規範囲を作成
		return $rs->create(
			{
				room_id => $room->id,
				nick_id => $nick->id,
				epoch1 => $self->now_epoch,
				epoch2 => $self->now_epoch,
			}
		);
	}
}


# merge dbdata into page data (i.e. change page field destructively.)
sub _merge_statistics{
	my $self = shift;

	# load DB data
	for my $room_info ( @{ $self->page->{rooms} }){
		my $room = $self->schema->resultset('Room')->find({
			unique_key => $room_info->{link},
		});

		next unless $room;

		$room_info->{obj_room} = $room;

		for my $member ( $room_info->{status}->all_members ){
			my $nick = $self->schema->resultset('Nick')->find_or_new(
				name => $member->name,
			)->insert();
			my $range = $self->_calc_range($room, $nick);

			# XXX $member is object so this code is too agly.
			$member->{obj_nick}  = $nick;
			$member->{obj_range} = $range;
		}
	}
}


# events =====================================

sub START {}

event exec => sub {
	my ($self) = @_[OBJECT, ARG0 .. $#_];

	$self->_merge_statistics;

	$POE::Kernel::poe_kernel->post(
		@{ $self->cont }, $self->page
	);
};

no  MooseX::POE;
1;


=head1 NAME

Chaberi::Backdoor::Statistics - culculation with DB.

=head1 DESCRIPTION

=head1 AUTHOR

hiratara E<lt>hira.tara@gmail.comE<gt>

=cut